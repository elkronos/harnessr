# core-stats-agreement.R: agreement between two raters.

#' Cohen's kappa between two labellings.
#'
#' Chance-corrected, which is the point: at a 5% inclusion rate a screener that
#' excluded everything agrees with a person 95% of the time, and only kappa
#' reports that as the nothing it is.
#' @noRd
cohen_kappa <- function(a, b) {
  lv <- union(unique(a), unique(b))
  m <- table(factor(a, levels = lv), factor(b, levels = lv))
  n <- sum(m)
  if (!n) return(NA_real_)
  po <- sum(diag(m)) / n
  pe <- sum(rowSums(m) * colSums(m)) / n^2
  if (isTRUE(all.equal(pe, 1))) return(NA_real_)
  as.numeric((po - pe) / (1 - pe))
}
