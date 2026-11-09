# core-stats-prop.R: proportions with their intervals.

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
  # Exact bounds at 0 and total hits, where the formula leaves a rounding error.
  lower <- if (hits == 0) 0 else max(0, centre - half)
  upper <- if (hits == total) 1 else min(1, centre + half)
  data.frame(metric = name, estimate = p, lower = lower, upper = upper, n = as.integer(total),
             stringsAsFactors = FALSE)
}

#' Confidence intervals for binomial proportions
#'
#' Intervals for `x` successes out of `n` trials, vectorised over both.
#'
#' Which method to use:
#' * **Wilson** (the default) for descriptive rates: a sensitivity, a share of
#'   records kept, an error rate reported alongside an estimate. It is close
#'   to nominal coverage on average and does not collapse to a point at 0 or
#'   n successes.
#' * **Clopper-Pearson** for any "at least" or "at most" guarantee, such as
#'   "recall is at least 0.95" or "the error rate is at most 2%". It never
#'   covers less than `conf`, where Wilson can dip below it when x or n - x is
#'   0 to 3 (Brown, Cai and DasGupta 2001).
#' * **Jeffreys**, the equal-tailed interval of the Beta(x + 1/2, n - x + 1/2)
#'   posterior, as a middle ground when a one-number comparison with other
#'   Bayesian summaries is wanted.
#'
#' Wilson here has no continuity correction, so the two-sided interval is the
#' one `prop.test(x, n, correct = FALSE)` reports, with the lower bound exactly
#' 0 at `x = 0` and the upper exactly 1 at `x = n`. The Clopper-Pearson interval
#' is the one `binom.test(x, n)` reports. The Jeffreys bounds are
#' `qbeta(a, x + 0.5, n - x + 0.5)` and `qbeta(1 - a, x + 0.5, n - x + 0.5)`,
#' with the lower bound set to 0 at `x = 0` and the upper to 1 at `x = n`.
#'
#' A one-sided bound spends the whole of `1 - conf` on its side: `side =
#' "lower"` gives `[lower, 1]` and `side = "upper"` gives `[0, upper]`, as
#' `binom.test(..., alternative = "greater")` and `"less"` do.
#'
#' @param x Number of successes: whole numbers from 0 to `n`.
#' @param n Number of trials: whole numbers. Recycled against `x`. A row with
#'   `n = 0` has `NA` for the estimate and both bounds.
#' @param method One of `"wilson"`, `"clopper_pearson"` or `"jeffreys"`.
#' @param side `"two"` for a two-sided interval, `"lower"` for a lower bound
#'   only, `"upper"` for an upper bound only.
#' @param conf Confidence level, strictly between 0 and 1.
#' @return A data frame with one row per element: `x`, `n`, `est` (x / n),
#'   `lower`, `upper`, `method`, `side` and `conf`.
#' @references
#' Brown, L. D., Cai, T. T. and DasGupta, A. (2001). Interval estimation for a
#' binomial proportion. *Statistical Science* 16(2), 101-133.
#'
#' Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or fiducial
#' limits illustrated in the case of the binomial. *Biometrika* 26(4), 404-413.
#'
#' Wilson, E. B. (1927). Probable inference, the law of succession, and
#' statistical inference. *Journal of the American Statistical Association*
#' 22(158), 209-212.
#' @family statistics
#' @export
#' @examples
#' # A descriptive rate: 46 of 50 eligible records were kept.
#' hr_prop_ci(46, 50)
#'
#' # A guarantee: is recall at least 0.90? Read the one-sided exact bound.
#' hr_prop_ci(46, 50, method = "clopper_pearson", side = "lower")
#'
#' # Vectorised: three rates at once.
#' hr_prop_ci(c(0, 5, 20), c(20, 20, 20), method = "jeffreys")
hr_prop_ci <- function(x, n, method = c("wilson", "clopper_pearson", "jeffreys"),
                       side = c("two", "lower", "upper"), conf = 0.95) {
  method <- match.arg(method)
  side <- match.arg(side)
  check_conf(conf)
  if (!is.numeric(x) || !is.numeric(n) || !length(x) || !length(n)) {
    gr_abort("`x` and `n` must be numeric vectors with at least one element.",
             class = "gr_bad_setting")
  }
  if (anyNA(x) || anyNA(n)) gr_abort("`x` and `n` must not contain NA.", class = "gr_bad_setting")
  len <- max(length(x), length(n))
  if (len %% length(x) || len %% length(n)) {
    gr_abort("The lengths of `x` and `n` must be equal, or one must be 1.",
             class = "gr_bad_setting")
  }
  x <- rep_len(x, len); n <- rep_len(n, len)
  whole <- function(v) all(abs(v - round(v)) < 1e-8)
  if (!whole(x) || !whole(n) || any(n < 0) || any(x < 0) || any(x > n)) {
    gr_abort("`x` and `n` must be whole numbers with 0 <= x <= n.", class = "gr_bad_setting")
  }
  # Two-sided splits 1 - conf between the tails; one-sided puts it all on one.
  a <- if (side == "two") (1 - conf) / 2 else 1 - conf
  est <- ifelse(n > 0, x / n, NA_real_)
  lo <- hi <- rep(NA_real_, len)
  ok <- n > 0
  if (any(ok)) {
    xo <- x[ok]; no <- n[ok]
    b <- switch(method,
      wilson = {
        z <- stats::qnorm(1 - a)
        p <- xo / no
        d <- 1 + z^2 / no
        centre <- (p + z^2 / (2 * no)) / d
        half <- z * sqrt(p * (1 - p) / no + z^2 / (4 * no^2)) / d
        # At x = 0 and x = n the bounds are exactly 0 and 1, but centre - half
        # and centre + half can miss them by a rounding error (2.8e-17 at
        # x = 0, n = 10), so they are set as prop.test() gives them.
        list(ifelse(xo == 0, 0, pmax(0, centre - half)),
             ifelse(xo == no, 1, pmin(1, centre + half)))
      },
      clopper_pearson = list(
        ifelse(xo == 0, 0, stats::qbeta(a, xo, no - xo + 1)),
        ifelse(xo == no, 1, stats::qbeta(1 - a, xo + 1, no - xo))),
      jeffreys = list(
        ifelse(xo == 0, 0, stats::qbeta(a, xo + 0.5, no - xo + 0.5)),
        ifelse(xo == no, 1, stats::qbeta(1 - a, xo + 0.5, no - xo + 0.5))))
    lo[ok] <- b[[1]]; hi[ok] <- b[[2]]
    if (side == "lower") hi[ok] <- 1
    if (side == "upper") lo[ok] <- 0
  }
  data.frame(x = x, n = n, est = est, lower = lo, upper = hi, method = method,
             side = side, conf = conf, stringsAsFactors = FALSE)
}

#' Stop unless `conf` is one number strictly between 0 and 1.
#' @noRd
check_conf <- function(conf) {
  if (!is.numeric(conf) || length(conf) != 1L || is.na(conf) || conf <= 0 || conf >= 1) {
    gr_abort("`conf` must be one number strictly between 0 and 1.", class = "gr_bad_setting")
  }
  invisible(conf)
}

#' Stop unless `B` is a whole number of resamples, at least `min`.
#' @noRd
check_boot <- function(B, seed, min = 0L) {
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < min || B != round(B)) {
    gr_abort(sprintf("`B` must be a whole number, at least %d.", min), class = "gr_bad_setting")
  }
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    gr_abort("`seed` must be one number.", class = "gr_bad_setting")
  }
  invisible(B)
}
