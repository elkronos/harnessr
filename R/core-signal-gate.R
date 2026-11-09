# core-signal-gate.R: thresholds that let a calibrated signal gate an action,
# and the policy that decides what happens when it may not.
#
# Ranking well and gating well are different claims: a signal can order items
# nicely and still let through too many wrong ones at any usable threshold. So
# a threshold is accepted only when an exact upper confidence bound on its
# error rate, on items the map was not fitted to, is below a tolerance the user
# fixed in advance. Until one is, the signal can only send an item to a check.

#' Choose a gate threshold by Learn-then-Test
#'
#' Finds the loosest threshold on a calibrated signal at which acting on the
#' items whose probability `p` is at or above it keeps a risk below `alpha`,
#' with confidence `1 - delta`, on the calibration half of the record.
#'
#' @section The procedure:
#' Learn-then-Test (Angelopoulos et al. 2021) with fixed-sequence testing:
#' each threshold `t` is a hypothesis "the risk at `t` exceeds `alpha`",
#' rejected when the one-sided Clopper-Pearson upper bound
#' `ucb = qbeta(1 - delta, k + 1, n - k)` is at most `alpha` (1 when
#' `k = n`). Thresholds are tested from strict to loose; the sequence stops at
#' the first that fails, and the loosest one that passed is kept. Because the
#' order is fixed before the labels are looked at, no correction for testing
#' many thresholds is needed.
#'
#' The risk sets `n` and `k`:
#' \describe{
#'   \item{`"error_among_accepted"`}{`n` is the number of items acted on at
#'     `t` (those with `p >= t`) and `k` the number of those that were wrong.
#'     For actions such as stopping, skipping or accepting.}
#'   \item{`"miss_rate"`}{`n` is the number of items on which acting is wrong
#'     (for screening, the eligible records) and `k` the number of those acted
#'     on at `t`. The denominator does not depend on `t`. For screening
#'     exclusions.}
#' }
#'
#' Even with no errors the bound reaches `alpha` only from
#' `n_min = ceiling(log(delta) / log(1 - alpha))` items: 59 at `alpha = 0.05`
#' and 299 at `alpha = 0.01`, with `delta = 0.05`. For
#' `"error_among_accepted"` the sequence therefore starts at the strictest
#' threshold that acts on at least `n_min` items; that count uses only the
#' scores, not the labels, so starting there keeps the guarantee. For
#' `"miss_rate"` the set needs at least `n_min` items on which acting is
#' wrong.
#'
#' The record becomes `"gating"` only when a threshold passes and none of
#' the reasons [hr_calibrate_signal()] gave holds: the graded set had at
#' least 100 wrong items, the fitted map increases with the signal and the
#' ECE used at least 5 bins. Otherwise it stays `"advisory"` and `reasons`
#' says why.
#'
#' @param cal An `hr_calibration` from [hr_calibrate_signal()].
#' @param action The action the signal would gate, such as `"stop"`,
#'   `"skip"`, `"accept"` or `"exclude"`. Recorded, and matched against the
#'   action of an [hr_signal_policy()].
#' @param risk `"error_among_accepted"` or `"miss_rate"`.
#' @param alpha The tolerated risk, strictly between 0 and 1. There is no
#'   default: it is a decision about the task, made before the data are seen.
#' @param delta The chance the guarantee fails, strictly between 0 and 1.
#' @param grid Thresholds on the probability scale, in any order; they are
#'   tested from the highest down. `NULL` uses 20 quantiles of `p` on the fit
#'   half (`cal$grid`).
#' @return `cal` with `$gate` set: a list of `action`, `risk`, `alpha`,
#'   `delta`, `n_min`, `threshold` (`NA` when none passed), `n`, `k`, `ucb`
#'   and `coverage` (the share of the calibration half acted on) at that
#'   threshold, `status` (`"passed"`, `"none passed"` or `"too few items"`)
#'   and `path`, a data frame of every threshold with its `n`, `k`, `ucb`,
#'   whether it was `tested` and whether it `passed`. `$status` and
#'   `$reasons` are updated.
#' @references
#' Angelopoulos, A. N., Bates, S., Candes, E. J., Jordan, M. I. and Lei, L.
#' (2021). Learn then test: calibrating predictive algorithms to achieve risk
#' control. arXiv:2110.01052.
#'
#' Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or fiducial
#' limits illustrated in the case of the binomial. *Biometrika* 26(4), 404-413.
#' @seealso [hr_calibrate_signal()], [hr_apply_signal()]
#' @family signals
#' @export
#' @examples
#' set.seed(2)
#' n <- 2000
#' answerable <- stats::runif(n) < 0.8
#' score <- stats::runif(n)
#' graded <- data.frame(cluster = rep(1:200, each = 10), score = score,
#'                      correct = stats::runif(n) < ifelse(answerable, score, score / 4),
#'                      answerable = answerable)
#' key <- list(served_model = "m-2026", version = "2026", task = "qa", format = "pdf",
#'             prompt_hash = "abc", effort = NA, module = "iterative")
#' cal <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, seed = 3, B = 0)
#' cal <- hr_gate_threshold(cal, "stop", alpha = 0.1)
#' cal$gate[c("threshold", "n", "k", "ucb", "status")]
hr_gate_threshold <- function(cal, action, risk = c("error_among_accepted", "miss_rate"),
                              alpha, delta = 0.05, grid = NULL) {
  if (!inherits(cal, "hr_calibration")) {
    gr_abort("`cal` must come from hr_calibrate_signal().", class = "gr_bad_setting")
  }
  if (!is.character(action) || length(action) != 1L || !is_nonblank(action)) {
    gr_abort("`action` must be one non-blank string.", class = "gr_bad_setting")
  }
  risk <- match.arg(risk)
  if (missing(alpha)) {
    gr_abort("`alpha` has no default: choose the risk you will tolerate before looking at the data.",
             class = "gr_bad_setting")
  }
  for (a in list(list("alpha", alpha), list("delta", delta))) {
    v <- a[[2]]
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v <= 0 || v >= 1) {
      gr_abort(sprintf("`%s` must be one number strictly between 0 and 1.", a[[1]]),
               class = "gr_bad_setting")
    }
  }
  grid <- grid %||% cal$grid
  if (!is.numeric(grid) || !length(grid) || anyNA(grid)) {
    gr_abort("`grid` must be a numeric vector of thresholds with no NA.", class = "gr_bad_setting")
  }
  grid <- sort(unique(grid), decreasing = TRUE)
  half <- cal$data[cal$data$half == "calibration", , drop = FALSE]
  p <- half$p
  wrong <- !half$correct
  n_min <- ceiling(log(delta) / log(1 - alpha))

  acted <- vapply(grid, function(t) sum(p >= t), numeric(1))
  if (risk == "error_among_accepted") {
    n <- acted
    k <- vapply(grid, function(t) sum(p >= t & wrong), numeric(1))
  } else {
    n <- rep(sum(wrong), length(grid))
    k <- vapply(grid, function(t) sum(p >= t & wrong), numeric(1))
  }
  ucb <- ifelse(n <= 0, NA_real_,
                ifelse(k >= n, 1, stats::qbeta(1 - delta, k + 1, pmax(n - k, 1))))
  tested <- passed <- logical(length(grid))
  start <- if (risk == "error_among_accepted") which(n >= n_min)[1] else if (n[1] >= n_min) 1L
           else NA_integer_
  if (!is.na(start)) {
    for (i in seq.int(start, length(grid))) {
      tested[i] <- TRUE
      if (is.na(ucb[i]) || ucb[i] > alpha) break
      passed[i] <- TRUE
    }
  }
  best <- if (any(passed)) max(which(passed)) else NA_integer_
  status <- if (is.na(start)) "too few items" else if (is.na(best)) "none passed" else "passed"
  at <- function(v) if (is.na(best)) NA_real_ else v[best]
  cal$gate <- list(
    action = action, risk = risk, alpha = alpha, delta = delta, n_min = n_min,
    threshold = at(grid), n = at(n), k = at(k), ucb = at(ucb),
    coverage = if (is.na(best)) NA_real_ else acted[best] / length(p),
    status = status,
    path = data.frame(threshold = grid, n = n, k = k, ucb = ucb, tested = tested,
                      passed = passed))

  reasons <- setdiff(cal$reasons, c("no gate threshold has been set",
                                    grep("^gate: ", cal$reasons, value = TRUE)))
  if (status == "too few items") {
    reasons <- c(reasons, sprintf(
      "gate: no threshold has the %d %s that a bound of %.3g at delta %.3g needs",
      n_min, if (risk == "miss_rate") "items on which acting is wrong" else "acted-on items",
      alpha, delta))
  } else if (status == "none passed") {
    reasons <- c(reasons, sprintf("gate: no threshold kept the upper bound on %s at or below %.3g",
                                  risk, alpha))
  }
  cal$reasons <- reasons
  cal$status <- if (status == "passed" && !length(reasons)) "gating" else "advisory"
  cal
}

#' What a signal may do, and what happens when it may not
#'
#' A policy names a signal, the action it would gate and where an item goes
#' when the signal cannot gate it. [hr_apply_signal()] applies it.
#'
#' `hr_apply_signal()` lets the signal gate only when every one of these
#' holds: a calibration record is given, it is for this signal, its key
#' matches the run's `key` ([hr_calibration_valid()]), its status is
#' `"gating"`, and its gate was set for the policy's action. Otherwise the
#' signal is advisory: `gated` is `FALSE`, the action is not taken, the item
#' is routed by `on_fail`, and `reason` says which condition failed. When the
#' signal does gate, the action is taken for a value whose mapped probability
#' is at or above the gate's threshold, and a value below it is routed by
#' `on_fail`. No reader calls this yet, so nothing in the package gates on a
#' signal.
#'
#' @param signal The signal's name.
#' @param action The action the signal would gate, as given to
#'   [hr_gate_threshold()].
#' @param on_fail Where an item goes when the signal does not gate it:
#'   `"route_check"` (an outside check, the default), `"route_person"` or
#'   `"ignore"`.
#' @return `hr_signal_policy()` returns an `hr_signal_policy`: a list with
#'   `signal`, `action` and `on_fail`.
#' @family signals
#' @export
#' @examples
#' pol <- hr_signal_policy("gr.iterative.can_answer", "stop")
#' sig <- hr_signal("gr.iterative.can_answer", TRUE)
#'
#' # With no calibration record the signal stays advisory.
#' hr_apply_signal(sig, pol)
hr_signal_policy <- function(signal, action, on_fail = c("route_check", "route_person", "ignore")) {
  for (a in list(list("signal", signal), list("action", action))) {
    v <- a[[2]]
    if (!is.character(v) || length(v) != 1L || !is_nonblank(v)) {
      gr_abort(sprintf("`%s` must be one non-blank string.", a[[1]]), class = "gr_bad_setting")
    }
  }
  on_fail <- match.arg(on_fail)
  structure(list(signal = signal, action = action, on_fail = on_fail),
            class = "hr_signal_policy")
}

#' @rdname hr_signal_policy
#' @param sig An `hr_signal` from [hr_signal()], or the bare value (one or
#'   more), taken to be the policy's signal.
#' @param policy An `hr_signal_policy`.
#' @param cal An `hr_calibration`, or `NULL`.
#' @param key The run's calibration key (see [hr_calibrate_signal()]). Without
#'   it the record cannot be checked, and the signal stays advisory.
#' @return `hr_apply_signal()` returns a data frame with one row per value:
#'   `signal`, `value`, `p` (the mapped probability, or `NA`), `threshold`,
#'   `gated` (whether the gate decided), `act` (whether the action is taken),
#'   `would_act` (what the value alone suggests: the value of a logical
#'   signal, or `p >= threshold` when both are known), `route` (`"act"`, or
#'   the policy's `on_fail`) and `reason`.
#' @export
hr_apply_signal <- function(sig, policy, cal = NULL, key = NULL) {
  if (!inherits(policy, "hr_signal_policy")) {
    gr_abort("`policy` must come from hr_signal_policy().", class = "gr_bad_setting")
  }
  if (!inherits(sig, "hr_signal")) sig <- hr_signal(policy$signal, sig)
  if (!identical(sig$name, policy$signal)) {
    gr_abort(sprintf("The signal is '%s' but the policy is for '%s'.", sig$name, policy$signal),
             class = "gr_bad_setting")
  }
  value <- sig$value
  n <- length(value)
  score <- if (sig$type == "logical") as.numeric(value)
           else if (sig$type == "numeric") as.numeric(value) else rep(NA_real_, n)
  have_cal <- inherits(cal, "hr_calibration")
  p <- if (have_cal && sig$type != "character") apply_signal_map(cal$map, score) else rep(NA_real_, n)
  threshold <- if (have_cal && !is.null(cal$gate)) cal$gate$threshold else NA_real_

  reason <- if (!have_cal) "no calibration record"
    else if (!identical(cal$signal, policy$signal)) sprintf("the record is for signal '%s'", cal$signal)
    else if (is.null(key)) "no run key to check the record against"
    else if (!isTRUE(v <- hr_calibration_valid(cal, key))) {
      sprintf("the record does not hold for this run (%s differs)",
              paste(attr(v, "differs"), collapse = ", "))
    }
    else if (is.null(cal$gate)) "the record has no gate threshold"
    else if (!identical(cal$gate$action, policy$action)) {
      sprintf("the record's gate is for action '%s'", cal$gate$action)
    }
    else if (!identical(cal$status, "gating")) {
      paste0("the record is advisory: ", paste(cal$reasons, collapse = "; "))
    }
    else if (sig$type == "character") "a text signal cannot be compared with a threshold"
    else NA_character_
  gated <- is.na(reason)
  act <- gated & !is.na(p) & p >= threshold
  would <- if (sig$type == "logical") as.logical(value)
           else if (!is.na(threshold)) !is.na(p) & p >= threshold else rep(NA, n)
  data.frame(signal = sig$name, value = as.character(value), p = p,
             threshold = threshold, gated = rep(gated, n), act = act, would_act = would,
             route = ifelse(act, "act", policy$on_fail),
             reason = if (gated) ifelse(act, "at or above the gate threshold",
                                        "below the gate threshold")
                      else rep(reason, n),
             stringsAsFactors = FALSE)
}

#' @export
print.hr_signal_policy <- function(x, ...) {
  cat(sprintf("<hr_signal_policy> %s may gate '%s'; otherwise %s\n", x$signal, x$action, x$on_fail))
  invisible(x)
}
