# doc-screen-stop.R: when prioritised screening may stop.

#' Hypergeometric stopping test for prioritised screening
#'
#' After each screened record, tests the null hypothesis that recall is still
#' below `target`, given what has been screened and how many records are left.
#' Screening may stop at the first record where the p-value falls below
#' `alpha`. This is the test of Callaghan and Muller-Hansen (2020), computed
#' with [stats::phyper()]. It is for prioritised screening only (records read
#' in ranked order, as [hr_baseline_ranker()] simulates); a one-pass screen
#' that reads every record has no stopping point to choose.
#'
#' **The test.** Let N be the number of records, t the number screened so far
#' and r the relevant records among them. Recall r / R is below `target` only
#' if the total number of relevant records R is at least
#' K = floor(r / target) + 1. Take the last m screened records as if they were
#' a random draw from the N - t + m records that were unscreened before them,
#' with k relevant among them. Under the null, at least K - (r - k) of those
#' N - t + m records are relevant, and the chance of seeing k or fewer in the
#' draw is at most the hypergeometric probability
#'
#' p(m) = P(X <= k), X ~ Hypergeometric(N - t + m records,
#' K - (r - k) relevant, m drawn),
#'
#' which is `phyper(k, K - r + k, N - t + m - (K - r + k), m)`. The p-value
#' after t records is the smallest p(m) over m = 1, ..., t, as in the authors'
#' treatment of already screened records as a sample. When fewer than
#' K - r records are left unscreened, the null cannot hold and p is 0.
#'
#' **Caveats.** The ranked records are not a random draw. A working ranker
#' reads the most likely relevant of the remaining records first, so the
#' window is richer in relevant records than a random draw from them would
#' be. That makes the test cautious when the ranker works and unreliable when
#' it ranks worse than chance. The minimum over m
#' and the look after every record are not corrected for repeated testing,
#' as in the original method. No stopping rule is standard; report the rule
#' and its settings with the result.
#'
#' @param screened_order The relevance of the records in the order they were
#'   screened: logical, or numeric 0 and 1 (1 = relevant). Records not yet
#'   screened may follow as `NA` at the end, and count toward `n_total`. An
#'   [hr_baseline_ranker()] result is also accepted, and its whole simulated
#'   order is tested.
#' @param target Recall level, strictly between 0 and 1.
#' @param alpha Significance level, strictly between 0 and 1.
#' @param n_total Total number of records, screened or not. Defaults to the
#'   length of `screened_order`.
#' @return A `gr_stop_test`, a list with:
#'   * `steps`: one row per screened record, with `n_screened`,
#'     `relevant_found`, `p_value` and `reject` (p below `alpha`).
#'   * `stop_at`: the first `n_screened` with `reject`, or `NA` when the
#'     test never rejects.
#'   * `relevant_at_stop` and `recall_at_stop`: the relevant records found
#'     by then and, when every record's relevance is known, the recall
#'     reached there.
#'   * `work_saved`: 1 - stop_at / n_total.
#'   * `target`, `alpha`, `n_total` and `n_screened`.
#' @references
#' Callaghan, M. W. and Muller-Hansen, F. (2020). Statistical stopping
#' criteria for automated screening in systematic reviews. *Systematic
#' Reviews* 9, 273.
#' @seealso [hr_baseline_ranker()] for a simulated screening order.
#' @export
#' @examples
#' # 1,000 records: 100 relevant found first, then 400 irrelevant in a row.
#' seen <- c(rep(1, 100), rep(0, 400), rep(NA, 500))
#' st <- gr_stop_test(seen)
#' st
#' # At 500 screened, the last 400 records hold no relevant ones; under the
#' # null at least 6 relevant records were among the 900 left before them.
#' prod((500 - 0:5) / (900 - 0:5))
#' st$steps$p_value[500]
gr_stop_test <- function(screened_order, target = 0.95, alpha = 0.05, n_total = NULL) {
  if (inherits(screened_order, "hr_baseline_ranker")) {
    screened_order <- screened_order$relevant
  }
  if (!is.numeric(target) || length(target) != 1L || is.na(target) || target <= 0 ||
      target >= 1) {
    gr_abort("`target` must be one number strictly between 0 and 1.", class = "gr_bad_setting")
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) || alpha <= 0 || alpha >= 1) {
    gr_abort("`alpha` must be one number strictly between 0 and 1.", class = "gr_bad_setting")
  }
  if (!length(screened_order)) {
    gr_abort("`screened_order` must have at least one record.", class = "gr_bad_setting")
  }
  miss <- is.na(screened_order)
  t_max <- sum(!miss)
  if (t_max && any(miss[seq_len(t_max)])) {
    gr_abort("`NA` in `screened_order` may only follow the screened records, at the end.",
             class = "gr_bad_setting")
  }
  y <- relevance_labels(screened_order[seq_len(t_max)], what = "screened_order")
  if (is.null(n_total)) n_total <- length(screened_order)
  if (!is.numeric(n_total) || length(n_total) != 1L || is.na(n_total) ||
      n_total != round(n_total) || n_total < length(screened_order)) {
    gr_abort("`n_total` must be a whole number, at least the length of `screened_order`.",
             class = "gr_bad_setting")
  }
  found <- cumsum(y)
  p <- vapply(seq_len(t_max), function(t) {
    r <- found[t]
    # The small tolerance keeps r / target from landing just under a whole
    # number in floating point (19 / 0.95), which would test recall = target.
    k_tar <- floor(r / target + 1e-9) + 1
    if (k_tar - r > n_total - t) return(0)
    m <- seq_len(t)
    k <- cumsum(y[t:1])
    urn <- n_total - t + m
    white <- k_tar - r + k
    min(stats::phyper(k, white, urn - white, m))
  }, numeric(1))
  reject <- p < alpha
  stop_at <- if (any(reject)) which(reject)[1] else NA_integer_
  known <- !any(miss) && length(screened_order) == n_total
  at_stop <- if (is.na(stop_at)) NA_real_ else found[stop_at]
  structure(list(
    steps = data.frame(n_screened = seq_len(t_max), relevant_found = found, p_value = p,
                       reject = reject),
    stop_at = stop_at,
    relevant_at_stop = at_stop,
    recall_at_stop = if (known && sum(y) > 0) at_stop / sum(y) else NA_real_,
    work_saved = if (is.na(stop_at)) NA_real_ else 1 - stop_at / n_total,
    target = target,
    alpha = alpha,
    n_total = as.integer(n_total),
    n_screened = t_max
  ), class = "gr_stop_test")
}

#' @rdname gr_stop_test
#' @param x A `gr_stop_test`.
#' @param ... Not used.
#' @export
print.gr_stop_test <- function(x, ...) {
  cat(sprintf("<gr_stop_test> recall target %s, alpha %s, %d of %d records screened\n",
              format(x$target), format(x$alpha), x$n_screened, x$n_total))
  if (is.na(x$stop_at)) {
    last <- if (x$n_screened) x$steps$p_value[x$n_screened] else NA_real_
    cat(sprintf("  not yet safe to stop: last p-value %s\n", format(signif(last, 3))))
  } else {
    cat(sprintf("  safe to stop after %d records (%d relevant found), work saved %.3f\n",
                x$stop_at, as.integer(x$relevant_at_stop), x$work_saved))
    if (!is.na(x$recall_at_stop)) cat(sprintf("  recall at that point: %.3f\n", x$recall_at_stop))
  }
  invisible(x)
}
