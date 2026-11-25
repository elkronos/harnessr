# core-bench-effort.R: whether an effort policy can replace a fixed effort.
#
# An escalation policy (core-effort-escalate.R) is admitted only if a
# benchmark shows it is not worse than the fixed levels it would replace, by
# more than a stated margin, and says what it costs, the raised requests
# included. This reads such a benchmark with hr_report()'s non-inferiority
# test and Holm's procedure over the comparisons. It plans nothing: the arms
# are the ones the person built.

#' Compare an effort policy with fixed efforts on a benchmark
#'
#' Tests whether the `candidate` arm (an [hr_effort_escalate()] policy, say)
#' is non-inferior to each of the `comparators` (fixed efforts, say), with
#' [hr_report()]'s non-inferiority test at `margin` and Holm's procedure over
#' the comparisons, and reports what each arm cost, the requests sent at a
#' raised effort included.
#'
#' With a `registration` from [hr_register_contrasts()], made before the
#' benchmark ran, its contrasts with `candidate` as `new` are the ones
#' tested, at their registered margins, and the result is confirmatory.
#' Without one, the contrasts are built here from `candidate`, `comparators`
#' and `margin`, all confirmatory so Holm's procedure covers them, and the
#' result is marked post hoc (`post_hoc = TRUE`): the margin was stated after
#' the benchmark was scored, so it is evidence for a decision to run a
#' registered comparison, not a verdict. Either way the benchmark's rows must
#' be on the test or final split, as [hr_report()] requires for a test.
#'
#' The cost table reads each run's trace: the requests it sent, the raises
#' an escalation policy made ([hr_effort_log()]) and the requests the raised
#' stages sent. Its `usd` is the run's cost from the benchmark, which already
#' counts every request, raised or not.
#'
#' @param bench An [hr_benchmark()] result.
#' @param candidate The arm under test, one name.
#' @param comparators The arms it is compared with; every other arm when
#'   `NULL`.
#' @param margin The non-inferiority margin, a proportion in (0, 1).
#' @param registration `NULL`, or an [hr_register_contrasts()] result.
#' @param cost_test Whether a verdict also needs `candidate` to be cheaper
#'   (for contrasts built here).
#' @param B,seed Bootstrap resamples and seed, passed to [hr_report()].
#' @param x An `hr_effort_check`.
#' @param ... Ignored.
#' @return An object of class `hr_effort_check`, a list of
#' \describe{
#'   \item{`contrasts`}{One row per comparison: `new`, `reference`, `label`,
#'     `margin`, `estimate`, `lower`, `level`, `accuracy_holds`,
#'     `cost_diff`, `cost_upper`, `cost_holds`, `verdict` and `p_value`,
#'     from [hr_report()]'s `ni` table.}
#'   \item{`cost`}{One row per arm: `arm`, `accuracy` (the mean of
#'     `correct` over reportable rows), `usd` (mean per run), `calls` (model
#'     requests per run), `escalations` (raises per run), `escalated_calls`
#'     (requests per run sent at a raised effort) and `resolved` (the share
#'     of raises whose stage fired none of the same triggers again, `NA`
#'     with none).}
#'   \item{`best_fixed`}{The most accurate comparator.}
#'   \item{`post_hoc`}{`TRUE` when no registration was given.}
#'   \item{`report`}{The [hr_report()] the contrasts come from.}
#' }
#' @seealso [hr_effort_escalate()], [hr_report()], [hr_register_contrasts()]
#' @family harness
#' @export
#' @examples
#' ref <- hr_reference(sprintf("q%02d", 1:40), labels = rep("yes", 40),
#'                     cluster = sprintf("c%02d", rep(1:20, each = 2)), split = "test")
#' arm_at <- function(name, effort) {
#'   hr_arm(name, function(item, ctx) {
#'     tr <- ctx$trace
#'     a <- hr_call(ctx$client, paste("first", item), model = "gpt-5.6-luna", trace = tr,
#'                  label = "task.draft", effort = effort)
#'     b <- hr_call(ctx$client, paste("final", item), model = "gpt-5.6-luna", trace = tr,
#'                  label = "task.final", effort = effort)
#'     b$text
#'   })
#' }
#' # Four hard items: the first step finds nothing at low effort, and the
#' # answer is wrong unless the final step reasons at high effort.
#' cl <- hr_mock_client(function(m, p) {
#'   hard <- grepl("q0[1-4]", m[[1]]$content)
#'   if (grepl("first", m[[1]]$content) && hard) return("NOT_IN_DOCUMENT")
#'   if (hard && identical(p$effort, "low")) "no" else "yes"
#' })
#' esc <- hr_effort_escalate(replies = c(not_in_document = "NOT_IN_DOCUMENT"))
#' arms <- list(arm_at("low", "low"), arm_at("high", "high"), arm_at("escalate", esc))
#' bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
#'                       governor = hr_governor(max_calls = 2000, max_cost_usd = 5))
#' chk <- hr_effort_check(bench, "escalate", margin = 0.1, cost_test = FALSE, B = 200)
#' chk
hr_effort_check <- function(bench, candidate, comparators = NULL, margin = 0.05,
                            registration = NULL, cost_test = TRUE, B = 2000, seed = 1) {
  if (!is.data.frame(bench) || !all(c("arm", "item", "correct") %in% names(bench))) {
    gr_abort("`bench` must be an hr_benchmark() result.", class = "gr_bad_setting")
  }
  arms <- unique(as.character(bench$arm))
  if (!is.character(candidate) || length(candidate) != 1L || !candidate %in% arms) {
    gr_abort(sprintf("`candidate` must be one of the benchmark's arms: %s.",
                     paste(arms, collapse = ", ")), class = "gr_bad_setting")
  }
  comparators <- comparators %||% setdiff(arms, candidate)
  bad <- setdiff(comparators, arms)
  if (!length(comparators) || length(bad) || candidate %in% comparators) {
    gr_abort("`comparators` must name other arms of the benchmark.", class = "gr_bad_setting")
  }
  post_hoc <- is.null(registration)
  if (post_hoc) {
    if (!is.numeric(margin) || length(margin) != 1L || is.na(margin) || margin <= 0 ||
        margin >= 1) {
      gr_abort("`margin` must be one number in (0, 1).", class = "gr_bad_setting")
    }
    registration <- post_hoc_registration(bench, candidate, comparators, margin,
                                          isTRUE(cost_test))
  }
  rep <- hr_report(bench, registration = registration, B = B, seed = seed)
  ni <- rep$ni
  ni <- ni[ni$new == candidate & ni$reference %in% comparators, , drop = FALSE]
  keep <- c("new", "reference", "label", "margin", "estimate", "lower", "level",
            "accuracy_holds", "cost_diff", "cost_upper", "cost_holds", "verdict", "p_value")
  ni <- ni[, intersect(keep, names(ni)), drop = FALSE]
  rownames(ni) <- NULL
  cost <- effort_costs(bench)
  acc <- cost$accuracy[match(comparators, cost$arm)]
  structure(list(contrasts = ni, cost = cost,
                 best_fixed = comparators[which.max(acc)], post_hoc = post_hoc, report = rep),
            class = "hr_effort_check")
}

#' A registration made after scoring, for hr_effort_check(): every contrast
#' confirmatory, so Holm's procedure covers them, and labelled post hoc.
#' @noRd
post_hoc_registration <- function(bench, candidate, comparators, margin, cost_test) {
  k <- length(comparators)
  tab <- data.frame(new = rep(candidate, k), reference = comparators, margin = margin,
                    confirmatory = TRUE, cost_test = cost_test, label = "post hoc",
                    mdd_design = NA_real_, stringsAsFactors = FALSE)
  out <- list(contrasts = tab, mdd = NULL, mdd_single = NULL, alpha = 0.025, power = 0.8,
              n_confirmatory = k, reference_hash = attr(bench, "reference_hash"),
              registered_at = "post hoc")
  out$hash <- registration_hash(out)
  structure(out, class = "hr_contrast_registration")
}

#' Per arm: accuracy, cost per run, requests per run, and the raises an
#' escalation policy made, from the runs' traces.
#' @noRd
effort_costs <- function(bench) {
  df <- as.data.frame(bench)
  rep_ok <- if ("reportable" %in% names(df)) df$reportable %in% TRUE else rep(TRUE, nrow(df))
  traces <- attr(bench, "traces")
  per_run <- function(id) {
    tr <- if (!is.null(traces) && !is.na(id)) traces[[id]]
    if (!inherits(tr, "gr_trace")) return(c(calls = NA, escalations = NA, raised = NA,
                                            resolved = NA))
    reqs <- Filter(function(s) !identical(s$kind, "local") && !identical(s$kind, "embedding"),
                   tr$steps)
    log <- hr_effort_log(tr)
    c(calls = length(reqs), escalations = nrow(log),
      raised = sum(log$calls, na.rm = TRUE), resolved = sum(log$resolved %in% TRUE))
  }
  ids <- if ("ledger_id" %in% names(df)) as.character(df$ledger_id) else rep(NA_character_,
                                                                            nrow(df))
  runs <- t(vapply(ids, per_run, numeric(4)))
  arms <- unique(as.character(df$arm))
  out <- do.call(rbind, lapply(arms, function(a) {
    w <- df$arm == a
    r <- runs[w, , drop = FALSE]
    esc <- sum(r[, "escalations"], na.rm = TRUE)
    data.frame(arm = a,
               accuracy = mean(df$correct[w & rep_ok], na.rm = TRUE),
               usd = if ("usd" %in% names(df)) mean(df$usd[w], na.rm = TRUE) else NA_real_,
               calls = mean(r[, "calls"], na.rm = TRUE),
               escalations = mean(r[, "escalations"], na.rm = TRUE),
               escalated_calls = mean(r[, "raised"], na.rm = TRUE),
               resolved = if (esc > 0) sum(r[, "resolved"], na.rm = TRUE) / esc else NA_real_,
               stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL
  out
}

#' @rdname hr_effort_check
#' @export
print.hr_effort_check <- function(x, ...) {
  cat(sprintf("<hr_effort_check> %s against %s%s\n", x$contrasts$new[1] %||% "-",
              paste(x$contrasts$reference, collapse = ", "),
              if (isTRUE(x$post_hoc)) " (post hoc: no registration)" else ""))
  ct <- x$contrasts
  if (nrow(ct)) {
    for (i in seq_len(nrow(ct))) {
      cat(sprintf("  vs %-12s margin %.1f pts, difference %+.1f pts, lower bound %+.1f: %s\n",
                  ct$reference[i], 100 * ct$margin[i], 100 * ct$estimate[i],
                  100 * ct$lower[i], if (isTRUE(ct$verdict[i])) "non-inferior" else "not shown"))
    }
  }
  cat(sprintf("  best fixed comparator: %s\n", x$best_fixed))
  print(x$cost, row.names = FALSE, digits = 3)
  invisible(x)
}
