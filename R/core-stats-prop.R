# core-stats-prop.R: a proportion with its Wilson interval.

#' A proportion with a Wilson score interval.
#'
#' Wilson rather than the textbook normal interval, because screening
#' proportions sit at the ends of the scale where the textbook one is worst: at
#' 5 of 5 it gives [1, 1], which asserts certainty from five observations.
#' @noRd
prop_row <- function(name, hits, total, conf = 0.95) {
  if (!total) {
    return(data.frame(metric = name, estimate = NA_real_, lower = NA_real_,
                      upper = NA_real_, n = 0L, stringsAsFactors = FALSE))
  }
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- hits / total
  d <- 1 + z^2 / total
  centre <- (p + z^2 / (2 * total)) / d
  half <- z * sqrt(p * (1 - p) / total + z^2 / (4 * total^2)) / d
  data.frame(metric = name, estimate = p, lower = max(0, centre - half),
             upper = min(1, centre + half), n = as.integer(total),
             stringsAsFactors = FALSE)
}
