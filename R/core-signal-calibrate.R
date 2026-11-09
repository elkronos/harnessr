# core-signal-calibrate.R: calibration records for self-signals.
#
# A signal earns the right to gate an action only through a record that says
# how well it predicted being right on graded items, for one served model,
# task, format, prompt, effort, module and contract version. Any change to one
# of those voids the record, since a signal calibrated on one model says
# nothing about another.

#' The fields a calibration record is keyed by. A record is valid only for a
#' run whose key matches on every one of them.
#' @noRd
.hr_calibration_key_fields <- c("served_model", "version", "task", "format", "prompt_hash",
                                "effort", "module", "contract_version")

#' The number of errors a graded set needs before its record can gate.
#' @noRd
.hr_calibration_min_errors <- 100L

#' Calibrate a self-signal against graded items
#'
#' Measures how well a signal predicts that an item came out right, on a
#' graded set, and fits a map from the signal to a probability. The result is
#' a calibration record: it says how good the signal is, and it is the only
#' thing [hr_gate_threshold()] and [hr_apply_signal()] accept as grounds for
#' letting a signal gate an action. A new record is always `advisory`.
#'
#' @section The graded set:
#' One row per item, with these columns:
#' \describe{
#'   \item{`score` (or `value`)}{The signal: a number, or a logical read as 1
#'     and 0. Higher means more confident the item is right. The `score`
#'     column of [hr_signals()] is in this form.}
#'   \item{`correct`}{Whether the item came out right (logical, or 1 and 0).
#'     For an action such as "stop reading" or "accept", right means acting
#'     on the item was right.}
#'   \item{`answerable`}{Whether the item has an answer in its source. The set
#'     must include unanswerable items: a signal calibrated only on answerable
#'     questions has never been asked about the case where saying "I can
#'     answer" is most often wrong.}
#'   \item{`cluster`}{Optional: the document (or other unit) the item comes
#'     from. Without it each item is its own cluster.}
#'   \item{`item_id`, `signal`}{Optional. When `signal` is present only the
#'     rows for this signal are used.}
#' }
#'
#' @section How it is computed:
#' Within each cluster, a share `split` of the items goes to the fit half and
#' the rest to the calibration half (a cluster's odd item goes to either side
#' at random). The map is fitted on the fit half. Every metric, and the
#' threshold search in [hr_gate_threshold()], uses the calibration half, so
#' the map is never judged on the items it was fitted to.
#'
#' * **Platt scaling** (Platt 1999) fits `p = plogis(a + b * score)` by
#'   logistic regression on the targets `(N+ + 1) / (N+ + 2)` for a right
#'   item and `1 / (N- + 2)` for a wrong one, which keeps the fit finite when
#'   the halves separate. It is the default and the only fitted map allowed
#'   below 1000 graded items.
#' * **Isotonic regression** (pool adjacent violators, weighted by the number
#'   of items at each score) needs at least 1000 graded items. The count is
#'   of the whole graded set before the split, so the map itself is fitted on
#'   about `split` of them (500 at the minimum with the default `split`).
#'   Between fitted scores it interpolates linearly; beyond them it holds the
#'   end values.
#' * **`"none"`** takes the score as the probability, so it must lie in
#'   \[0, 1\]. It is the comparison that shows what fitting a map gained.
#'
#' On the calibration half, with `p` the mapped probability and `y` 1 for a
#' right item. The Brier score, its decomposition and the ECE judge `p`;
#' AUROC2 and AURC judge the signal's own score, so they describe the signal
#' and not the map. A Platt slope is free to be negative, and a map fitted to
#' a signal that points the wrong way would otherwise rank well and hide it.
#'
#' * **Brier score** `mean((p - y)^2)`, with its decomposition over bins of
#'   `p` (Murphy 1973; the two within-bin terms of Stephenson et al. 2008):
#'   `brier = reliability - resolution + uncertainty + within_var -
#'   2 * within_cov`. `reliability` is the weighted mean of
#'   `(mean p - mean y)^2` per bin, `resolution` the weighted mean of
#'   `(mean y in bin - mean y)^2`, `uncertainty` is `mean(y) * (1 - mean(y))`,
#'   and `within_var` and `within_cov` are the weighted within-bin variance of
#'   `p` and covariance of `p` and `y`. When `p` takes no more distinct values
#'   than `bins`, each value is its own bin, both within-bin terms are 0, and
#'   this is Murphy's three-part decomposition exactly.
#' * **AUROC2**, the type-2 area under the ROC curve: the probability that a
#'   right item scores above a wrong one, ties counting half (the
#'   Mann-Whitney statistic), on the raw score. It measures ranking alone,
#'   and is below 0.5 for a signal that is higher when the item is wrong.
#' * **AURC**, the area under the risk-coverage curve (Geifman and El-Yaniv
#'   2017): items are accepted from the most to the least confident, and the
#'   error rate among the first `k` is averaged over `k = 1, ..., n`, in the
#'   order of the raw score. Tied
#'   scores enter together, each position taking the expected error rate
#'   under a random order within the tie. `selective_risk` gives the same
#'   error rate at 50, 80 and 90 percent coverage. Lower is better.
#' * **ECE**, the debiased L2 calibration error over equal-mass bins (Kumar,
#'   Liang and Ma 2019): `sqrt(max(0, sum_k w_k * ((mean p - mean y)^2 -
#'   mean y * (1 - mean y) / (n_k - 1))))`. The plug-in error is biased upward
#'   by the noise in each bin's mean, and the subtracted term removes that
#'   bias, so a perfectly calibrated signal scores near 0 rather than at the
#'   noise floor. `bins` is held between 5 and 10. A calibration half of
#'   fewer than 10 items is lowered to fewer bins so each bin has at least
#'   two items; `reasons` then says how many bins were used.
#'
#' Intervals are 95 percent percentile intervals from a bootstrap that
#' resamples whole clusters of the calibration half, `B` times. With fewer
#' than two clusters in that half, or when every resample gives the same
#' value, there is nothing to resample and the bounds are `NA`. With fewer
#' than 20 clusters percentile intervals cover poorly, and `notes` says how
#' many clusters they rest on.
#'
#' A record is `advisory` until [hr_gate_threshold()] finds a threshold that
#' passes. It also stays advisory when the graded set has fewer than 100
#' wrong items, when the fitted map does not increase with the signal (a
#' Platt slope of 0 or less, or a flat isotonic fit), or when the ECE used
#' fewer than 5 bins; `reasons` says why.
#'
#' @param signal The signal's name, as recorded by [hr_signal()].
#' @param graded The graded set, a data frame; see "The graded set".
#' @param key A named list with the fields the record is valid for:
#'   `served_model` (the model the provider said answered, not the one asked
#'   for), `version` (the model version or snapshot), `task`, `format`,
#'   `prompt_hash` (of the prompt or template), `effort`, `module` (the reader
#'   or stage) and `contract_version`. Each is one string; `NA` is allowed
#'   except for `served_model`. A missing `contract_version` is filled with
#'   the running package's contract version.
#' @param method `"platt"`, `"isotonic"` or `"none"`.
#' @param bins Number of equal-mass bins for the ECE and the decomposition,
#'   held between 5 and 10.
#' @param split Share of each cluster's items that goes to the fit half,
#'   strictly between 0 and 1.
#' @param seed Seed for the split and the bootstrap. Required, so the same
#'   graded set always gives the same record. The caller's random state is
#'   left as it was.
#' @param B Number of bootstrap resamples; 0 for no intervals.
#' @return An `hr_calibration`: a list with `signal`, `key`, `method`,
#'   `n_items`, `n_errors`, `n_unanswerable`, `n_clusters`, `accuracy` (on
#'   the calibration half), `metrics` (a data frame of `metric`, `estimate`,
#'   `lower`, `upper`), `selective_risk`, `decomposition`, `map` (the fitted
#'   map), `grid` (the default thresholds for [hr_gate_threshold()], from the
#'   fit half), `data` (the graded items with their half and mapped `p`),
#'   `sample_design`, `bins`, `B`, `seed`, `created_utc`, `created_by`,
#'   `status` (`"advisory"` or `"gating"`), `reasons`, `notes` (remarks that
#'   do not stop a record from gating, such as a small cluster count behind
#'   the intervals) and `gate` (`NULL`
#'   until [hr_gate_threshold()] sets it). It has `print()` and [as_json()]
#'   methods.
#' @references
#' Geifman, Y. and El-Yaniv, R. (2017). Selective classification for deep
#' neural networks. *Advances in Neural Information Processing Systems* 30.
#'
#' Kumar, A., Liang, P. and Ma, T. (2019). Verified uncertainty calibration.
#' *Advances in Neural Information Processing Systems* 32.
#'
#' Murphy, A. H. (1973). A new vector partition of the probability score.
#' *Journal of Applied Meteorology* 12(4), 595-600.
#'
#' Platt, J. (1999). Probabilistic outputs for support vector machines and
#' comparisons to regularized likelihood methods. In *Advances in Large
#' Margin Classifiers*, 61-74.
#'
#' Stephenson, D. B., Coelho, C. A. S. and Jolliffe, I. T. (2008). Two extra
#' components in the Brier score decomposition. *Weather and Forecasting*
#' 23(4), 752-757.
#' @seealso [hr_gate_threshold()], [hr_calibration_valid()], [hr_signals()]
#' @family signals
#' @export
#' @examples
#' # A simulated graded set: 40 documents, 10 questions each, a quarter of
#' # them unanswerable, and a signal that is informative but overconfident.
#' set.seed(1)
#' n <- 400
#' answerable <- rep(c(TRUE, TRUE, TRUE, FALSE), length.out = n)
#' truth <- stats::runif(n, 0.2, 0.95) * answerable
#' graded <- data.frame(
#'   cluster = rep(sprintf("doc%02d", 1:40), each = 10),
#'   score = pmin(1, truth + 0.15),
#'   correct = stats::runif(n) < truth,
#'   answerable = answerable)
#' key <- list(served_model = "mock-model-2026-01-01", version = "2026-01-01",
#'             task = "qa", format = "pdf", prompt_hash = "a1b2c3", effort = "low",
#'             module = "iterative")
#' cal <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, seed = 7, B = 200)
#' cal
#'
#' # The same split with no map shows what Platt scaling bought.
#' raw <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, method = "none",
#'                            seed = 7, B = 0)
#' raw$metrics[raw$metrics$metric %in% c("brier", "ece"), ]
hr_calibrate_signal <- function(signal, graded, key, method = c("platt", "isotonic", "none"),
                                bins = 10L, split = 0.5, seed, B = 2000L) {
  method <- match.arg(method)
  if (!is.character(signal) || length(signal) != 1L || !is_nonblank(signal)) {
    gr_abort("`signal` must be one non-blank string.", class = "gr_bad_setting")
  }
  if (missing(seed) || !is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    gr_abort("`seed` is required: one number, so the split and bootstrap can be repeated.",
             class = "gr_bad_setting")
  }
  if (!is.numeric(split) || length(split) != 1L || is.na(split) || split <= 0 || split >= 1) {
    gr_abort("`split` must be one number strictly between 0 and 1.", class = "gr_bad_setting")
  }
  if (!is.numeric(bins) || length(bins) != 1L || is.na(bins)) {
    gr_abort("`bins` must be one number.", class = "gr_bad_setting")
  }
  bins <- as.integer(min(10, max(5, round(bins))))
  B <- as_int1(B, NA_integer_)
  if (is.na(B) || B < 0L) gr_abort("`B` must be a whole number, 0 or more.", class = "gr_bad_setting")
  key <- calibration_key(key)
  d <- graded_items(graded, signal)
  n <- nrow(d)
  if (method == "isotonic" && n < 1000L) {
    gr_abort(sprintf(paste0("Isotonic calibration needs at least 1000 graded items, counted before ",
                            "the split; this set has %d. ",
                            "Use method = \"platt\"."), n), class = "hr_bad_calibration")
  }
  if (method == "none" && any(d$score < 0 | d$score > 1)) {
    gr_abort("With method = \"none\" the score is the probability, so it must lie in [0, 1].",
             class = "hr_bad_calibration")
  }

  out <- with_private_rng(seed, {
    d$half <- cluster_split(d$cluster, split)
    if (sum(d$half == "fit") < 2L || sum(d$half == "calibration") < 2L) {
      gr_abort("Each half of the split needs at least two items; the graded set is too small.",
               class = "hr_bad_calibration")
    }
    fit <- d$half == "fit"
    map <- fit_signal_map(d$score[fit], d$correct[fit], method)
    d$p <- apply_signal_map(map, d$score)
    cal <- d[!fit, , drop = FALSE]
    est <- signal_metrics(cal$p, cal$score, cal$correct, bins)
    boot <- if (B > 0L) signal_boot(cal, bins, B) else NULL
    list(d = d, map = map, est = est, boot = boot)
  })
  d <- out$d
  est <- out$est
  metric_names <- c("brier", "auroc2", "aurc", "ece")
  cal_half <- d[d$half == "calibration", , drop = FALSE]
  cal_clusters <- length(unique(cal_half$cluster))
  ci <- function(m) {
    # One cluster has nothing to resample, and a bootstrap that never moves
    # on a half of several items says the same: a zero-width interval would
    # read as an exact estimate.
    if (is.null(out$boot) || cal_clusters < 2L) return(c(NA_real_, NA_real_))
    v <- out$boot[, m]
    v <- v[is.finite(v)]
    if (length(v) < 2L) return(c(NA_real_, NA_real_))
    if (nrow(cal_half) > 1L && max(v) - min(v) <= 0) return(c(NA_real_, NA_real_))
    unname(stats::quantile(v, c(0.025, 0.975), names = FALSE, type = 7))
  }
  metrics <- data.frame(metric = metric_names,
                        estimate = vapply(metric_names, function(m) est[[m]], numeric(1)),
                        lower = vapply(metric_names, function(m) ci(m)[1], numeric(1)),
                        upper = vapply(metric_names, function(m) ci(m)[2], numeric(1)),
                        stringsAsFactors = FALSE)
  rownames(metrics) <- NULL

  n_errors <- sum(!d$correct)
  reasons <- "no gate threshold has been set"
  if (n_errors < .hr_calibration_min_errors) {
    reasons <- c(sprintf("the graded set has %d wrong items, fewer than the %d a gating record needs",
                         n_errors, .hr_calibration_min_errors), reasons)
  }
  # A threshold on p is a threshold on the signal only when p rises with it.
  map <- out$map
  if ((map$method == "platt" && !(map$b > 0)) ||
      (map$method == "isotonic" && length(unique(map$y)) < 2L)) {
    reasons <- c("the fitted map does not increase with the signal", reasons)
  }
  if (est$bins < 5L) {
    reasons <- c(sprintf("the calibration half has %d items, so the ECE uses %d bins, fewer than 5",
                         nrow(cal_half), est$bins), reasons)
  }
  notes <- character(0)
  if (B > 0L && cal_clusters < 2L) {
    notes <- "the calibration half has one cluster, so there are no intervals"
  } else if (B > 0L && cal_clusters < 20L) {
    notes <- sprintf("the intervals rest on %d clusters; percentile intervals cover poorly below 20",
                     cal_clusters)
  }
  fit_p <- d$p[d$half == "fit"]
  grid <- sort(unique(stats::quantile(fit_p, probs = seq(0, 1, length.out = 20L), names = FALSE,
                                      type = 7)), decreasing = TRUE)
  structure(list(
    signal = signal,
    key = key,
    method = method,
    n_items = n,
    n_errors = n_errors,
    n_unanswerable = sum(!d$answerable),
    n_clusters = length(unique(d$cluster)),
    accuracy = mean(d$correct[d$half == "calibration"]),
    metrics = metrics,
    selective_risk = est$selective_risk,
    decomposition = est$decomposition,
    map = out$map,
    grid = grid,
    data = d,
    sample_design = list(split = split, stratified_by = "cluster",
                         fit = sum(d$half == "fit"), calibration = sum(d$half == "calibration")),
    bins = est$bins,
    B = B,
    seed = seed,
    created_utc = utc_stamp(Sys.time()),
    created_by = trace_actor(gr_options("actor"))$run_by,
    status = "advisory",
    reasons = reasons,
    notes = notes,
    gate = NULL
  ), class = "hr_calibration")
}

#' A calibration key, checked and with every field one string.
#' @noRd
calibration_key <- function(key, fill = TRUE) {
  if (!is.list(key) || is.null(names(key))) {
    gr_abort(sprintf("`key` must be a named list with fields %s.",
                     paste(.hr_calibration_key_fields, collapse = ", ")), class = "gr_bad_setting")
  }
  if (fill && is.null(key[["contract_version", exact = TRUE]])) {
    key$contract_version <- hr_contract_version()
  }
  missing_f <- setdiff(.hr_calibration_key_fields, names(key))
  if (length(missing_f)) {
    gr_abort(sprintf("`key` is missing %s. Give NA for a field that does not apply.",
                     paste(missing_f, collapse = ", ")), class = "gr_bad_setting")
  }
  out <- lapply(.hr_calibration_key_fields, function(f) {
    v <- key[[f]]
    if (!is.atomic(v) || length(v) != 1L) {
      gr_abort(sprintf("`key$%s` must be one value.", f), class = "gr_bad_setting")
    }
    as.character(v)
  })
  names(out) <- .hr_calibration_key_fields
  if (!is_nonblank(out$served_model)) {
    gr_abort("`key$served_model` must name the model that answered.", class = "gr_bad_setting")
  }
  out
}

#' The graded items for one signal, checked: score, correct, answerable,
#' cluster and item_id columns.
#' @noRd
graded_items <- function(graded, signal) {
  if (!is.data.frame(graded)) gr_abort("`graded` must be a data frame.", class = "gr_bad_setting")
  if (!is.null(graded$signal)) graded <- graded[graded$signal %in% signal, , drop = FALSE]
  score <- graded$score %||% graded$value
  if (is.null(score)) {
    gr_abort("`graded` needs a `score` (or `value`) column holding the signal.",
             class = "gr_bad_setting")
  }
  for (col in c("correct", "answerable")) {
    if (is.null(graded[[col]])) {
      gr_abort(sprintf("`graded` needs a `%s` column.", col), class = "gr_bad_setting")
    }
  }
  if (!nrow(graded)) {
    gr_abort(sprintf("`graded` has no rows for signal '%s'.", signal), class = "hr_bad_calibration")
  }
  as_flag <- function(v, col) {
    if (is.numeric(v) && all(v %in% c(0, 1))) v <- v == 1
    if (!is.logical(v) || anyNA(v)) {
      gr_abort(sprintf("`graded$%s` must be logical (or 1 and 0) with no NA.", col),
               class = "gr_bad_setting")
    }
    v
  }
  if (is.logical(score)) score <- as.numeric(score)
  if (!is.numeric(score) || anyNA(score) || any(!is.finite(score))) {
    gr_abort("The signal's score must be numeric or logical, finite, with no NA.",
             class = "gr_bad_setting")
  }
  answerable <- as_flag(graded$answerable, "answerable")
  if (all(answerable)) {
    gr_abort(paste0("`graded` has no unanswerable items. A signal has to be calibrated on items ",
                    "whose answer is not in the source too, or it is never tested where it is ",
                    "most often wrong."), class = "hr_bad_calibration")
  }
  n <- nrow(graded)
  cluster <- if (is.null(graded$cluster)) seq_len(n) else graded$cluster
  if (anyNA(cluster)) gr_abort("`graded$cluster` must not contain NA.", class = "gr_bad_setting")
  data.frame(item_id = as.character(graded$item_id %||% seq_len(n)),
             cluster = as.character(cluster),
             score = as.numeric(score),
             correct = as_flag(graded$correct, "correct"),
             answerable = answerable,
             stringsAsFactors = FALSE)
}

#' "fit" or "calibration" for each item: within each cluster, round(share * n)
#' items to fit, the fractional item going either way at random.
#' @noRd
cluster_split <- function(cluster, share) {
  half <- character(length(cluster))
  for (g in unique(cluster)) {
    idx <- which(cluster == g)
    m <- length(idx) * share
    k <- floor(m) + (stats::runif(1) < m - floor(m))
    pick <- if (length(idx) == 1L) idx[k > 0] else idx[sample.int(length(idx), k)]
    half[idx] <- "calibration"
    half[pick] <- "fit"
  }
  half
}

#' Fit a map from score to probability on the fit half.
#' @noRd
fit_signal_map <- function(score, y, method) {
  if (method == "none") return(list(method = "none"))
  if (method == "platt") {
    n_pos <- sum(y)
    n_neg <- sum(!y)
    target <- ifelse(y, (n_pos + 1) / (n_pos + 2), 1 / (n_neg + 2))
    if (length(unique(score)) < 2L) {
      return(list(method = "platt", a = stats::qlogis(mean(target)), b = 0))
    }
    fit <- stats::glm.fit(cbind(1, score), target, family = stats::quasibinomial())
    co <- unname(fit$coefficients)
    co[is.na(co)] <- 0
    return(list(method = "platt", a = co[1], b = co[2]))
  }
  # Isotonic: pool adjacent violators over the distinct scores, each weighted
  # by its number of items.
  xs <- sort(unique(score))
  w <- as.numeric(table(factor(score, levels = xs)))
  ym <- as.numeric(tapply(as.numeric(y), factor(score, levels = xs), mean))
  list(method = "isotonic", x = xs, y = pava(ym, w))
}

#' Weighted pool adjacent violators: the non-decreasing fit to `y`.
#' @noRd
pava <- function(y, w) {
  val <- numeric(0); wt <- numeric(0); len <- integer(0)
  for (i in seq_along(y)) {
    val <- c(val, y[i]); wt <- c(wt, w[i]); len <- c(len, 1L)
    while (length(val) > 1L && val[length(val) - 1L] > val[length(val)]) {
      j <- length(val)
      v <- (val[j - 1L] * wt[j - 1L] + val[j] * wt[j]) / (wt[j - 1L] + wt[j])
      val <- c(val[seq_len(j - 2L)], v)
      wt <- c(wt[seq_len(j - 2L)], wt[j - 1L] + wt[j])
      len <- c(len[seq_len(j - 2L)], len[j - 1L] + len[j])
    }
  }
  rep(val, len)
}

#' The probability a fitted map gives each score.
#' @noRd
apply_signal_map <- function(map, score) {
  switch(map$method,
         none = as.numeric(score),
         platt = stats::plogis(map$a + map$b * score),
         isotonic = if (length(map$x) == 1L) rep(map$y, length(score))
                    else stats::approx(map$x, map$y, xout = score, rule = 2, ties = mean)$y)
}

#' Equal-mass bins: each item's bin, `nb` bins by rank of `p`. When `p` takes
#' no more than `nb` distinct values, each value is its own bin.
#' @noRd
mass_bins <- function(p, nb, distinct = TRUE) {
  u <- sort(unique(p))
  if (distinct && length(u) <= nb) return(match(p, u))
  n <- length(p)
  bin <- integer(n)
  bin[order(p)] <- as.integer(ceiling(seq_len(n) * nb / n))
  bin
}

#' The Brier score and its decomposition over the bins in `bin`.
#' @noRd
brier_parts <- function(p, y, bin) {
  y <- as.numeric(y)
  n <- length(p)
  ybar <- mean(y)
  rel <- res <- wbv <- wbc <- 0
  for (k in unique(bin)) {
    i <- bin == k
    w <- sum(i) / n
    pk <- mean(p[i]); yk <- mean(y[i])
    rel <- rel + w * (pk - yk)^2
    res <- res + w * (yk - ybar)^2
    wbv <- wbv + w * mean((p[i] - pk)^2)
    wbc <- wbc + w * mean((p[i] - pk) * (y[i] - yk))
  }
  list(brier = mean((p - y)^2), reliability = rel, resolution = res,
       uncertainty = ybar * (1 - ybar), within_var = wbv, within_cov = wbc,
       bins = length(unique(bin)))
}

#' Type-2 AUROC: P(score of a right item > score of a wrong one), ties half.
#' @noRd
auroc2 <- function(p, y) {
  n1 <- sum(y); n0 <- sum(!y)
  if (!n1 || !n0) return(NA_real_)
  r <- rank(p, ties.method = "average")
  (sum(r[y]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' The risk-coverage curve: the expected error rate among the k most
#' confident items, for k = 1..n, ties taken in random order.
#' @noRd
risk_curve <- function(p, y) {
  n <- length(p)
  err <- as.numeric(!y)
  lev <- sort(unique(p), decreasing = TRUE)
  g <- match(p, lev)
  m <- tabulate(g, length(lev))
  e <- vapply(seq_along(lev), function(j) sum(err[g == j]), numeric(1))
  before_n <- c(0, cumsum(m))[seq_along(lev)]
  before_e <- c(0, cumsum(e))[seq_along(lev)]
  k <- seq_len(n)
  j <- findInterval(k - 1, cumsum(c(0, m)), rightmost.closed = FALSE)
  j <- pmin(pmax(j, 1L), length(lev))
  (before_e[j] + (k - before_n[j]) * e[j] / m[j]) / k
}

#' The debiased L2 calibration error over equal-mass bins (Kumar et al. 2019).
#' @noRd
ece_debiased <- function(p, y, nb) {
  y <- as.numeric(y)
  n <- length(p)
  nb <- max(1L, min(nb, n %/% 2L))
  bin <- mass_bins(p, nb, distinct = FALSE)
  s <- 0
  for (k in unique(bin)) {
    i <- bin == k
    nk <- sum(i)
    yk <- mean(y[i])
    s <- s + nk / n * ((mean(p[i]) - yk)^2 - if (nk > 1L) yk * (1 - yk) / (nk - 1) else 0)
  }
  list(ece = sqrt(max(0, s)), bins = nb)
}

#' Every metric of a calibration half: Brier, its decomposition and the ECE
#' on the mapped `p`, AUROC2 and the risk-coverage curve on the raw `score`.
#' @noRd
signal_metrics <- function(p, score, y, nb) {
  rc <- risk_curve(score, y)
  n <- length(p)
  cover <- c(0.5, 0.8, 0.9)
  sr <- data.frame(coverage = cover,
                   items = as.integer(ceiling(cover * n)),
                   risk = rc[as.integer(ceiling(cover * n))])
  ec <- ece_debiased(p, y, nb)
  dec <- brier_parts(p, y, mass_bins(p, min(nb, max(1L, n %/% 2L))))
  list(brier = dec$brier, auroc2 = auroc2(score, y), aurc = mean(rc), ece = ec$ece,
       bins = ec$bins, selective_risk = sr,
       decomposition = dec)
}

#' Cluster bootstrap of the headline metrics on the calibration half.
#' @noRd
signal_boot <- function(cal, nb, B) {
  groups <- split(seq_len(nrow(cal)), cal$cluster)
  ng <- length(groups)
  out <- matrix(NA_real_, B, 4L, dimnames = list(NULL, c("brier", "auroc2", "aurc", "ece")))
  for (b in seq_len(B)) {
    idx <- unlist(groups[sample.int(ng, ng, replace = TRUE)], use.names = FALSE)
    p <- cal$p[idx]; s <- cal$score[idx]; y <- cal$correct[idx]
    out[b, ] <- c(mean((p - y)^2), auroc2(s, y), mean(risk_curve(s, y)),
                  ece_debiased(p, y, nb)$ece)
  }
  out
}

#' Is a calibration record valid for a run?
#'
#' A record holds only for the served model, model version, task, format,
#' prompt hash, effort, module and contract version it was measured on.
#' `hr_calibration_valid()` is `FALSE` when any of them differs from `key`, or
#' is missing from it, and the fields that differ are in the `"differs"`
#' attribute. A `key` without `contract_version` is checked against the
#' running package's contract version, so a record made under another
#' contract version is void.
#'
#' @param cal An `hr_calibration` from [hr_calibrate_signal()].
#' @param key A named list with the fields described under `key` in
#'   [hr_calibrate_signal()], for the run the record would be used in.
#' @return `TRUE` or `FALSE`, with attribute `differs` naming the fields that
#'   did not match.
#' @family signals
#' @export
#' @examples
#' graded <- data.frame(score = rep(c(0.9, 0.2), 20), correct = rep(c(TRUE, FALSE), 20),
#'                      answerable = rep(c(TRUE, TRUE, TRUE, FALSE), 10))
#' key <- list(served_model = "m-2026", version = "2026", task = "qa", format = "pdf",
#'             prompt_hash = "abc", effort = NA, module = "iterative")
#' cal <- hr_calibrate_signal("demo", graded, key, seed = 1, B = 0)
#' hr_calibration_valid(cal, key)
#' hr_calibration_valid(cal, utils::modifyList(key, list(served_model = "m-2027")))
hr_calibration_valid <- function(cal, key) {
  if (!inherits(cal, "hr_calibration")) {
    gr_abort("`cal` must come from hr_calibrate_signal().", class = "gr_bad_setting")
  }
  if (!is.list(key)) gr_abort("`key` must be a named list.", class = "gr_bad_setting")
  if (is.null(key[["contract_version", exact = TRUE]])) key$contract_version <- hr_contract_version()
  differs <- .hr_calibration_key_fields[!vapply(.hr_calibration_key_fields, function(f) {
    v <- key[[f]]
    is.atomic(v) && length(v) == 1L && identical(as.character(v), cal$key[[f]])
  }, logical(1))]
  structure(!length(differs), differs = differs)
}

#' @export
print.hr_calibration <- function(x, ...) {
  cat(sprintf("<hr_calibration> %s: %s\n", x$signal, x$status))
  cat(sprintf("  %d items (%d wrong, %d unanswerable) in %d clusters; map: %s\n",
              x$n_items, x$n_errors, x$n_unanswerable, x$n_clusters, x$method))
  cat(sprintf("  key: %s\n", paste(sprintf("%s=%s", names(x$key), unlist(x$key)), collapse = ", ")))
  cat(sprintf("  calibration half: %d items, accuracy %.3f\n",
              x$sample_design$calibration, x$accuracy))
  m <- x$metrics
  for (i in seq_len(nrow(m))) {
    cat(sprintf("  %-7s %.4f%s\n", m$metric[i], m$estimate[i],
                if (is.na(m$lower[i])) "" else sprintf("  [%.4f, %.4f]", m$lower[i], m$upper[i])))
  }
  if (!is.null(x$gate)) {
    g <- x$gate
    cat(sprintf("  gate (%s, %s, alpha %.3g): %s%s\n", g$action, g$risk, g$alpha, g$status,
                if (is.na(g$threshold)) "" else sprintf(" at p >= %.4f", g$threshold)))
  }
  if (length(x$reasons)) cat(sprintf("  advisory: %s\n", paste(x$reasons, collapse = "; ")))
  if (length(x$notes)) cat(sprintf("  note: %s\n", paste(x$notes, collapse = "; ")))
  invisible(x)
}

#' @export
as_json.hr_calibration <- function(x, pretty = TRUE, ...) {
  as_json.default(unclass(x), pretty = pretty, ...)
}
