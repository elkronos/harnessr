# core-stats-estimate.R: design-weighted and prediction-powered estimates.

#' Design-weighted estimates from a probability sample
#'
#' Estimates a population total, mean or ratio from units sampled with known
#' inclusion probabilities `pi`, such as a reference that judged every kept
#' record and a 10% sample of the excluded ones.
#'
#' * `"total"`: the Horvitz-Thompson estimator, sum(y / pi).
#' * `"mean"`: the Hajek estimator, sum(y / pi) / sum(1 / pi), which divides
#'   by the estimated population size and is steadier than the HT total over
#'   a known N when the sample size varies.
#' * `"ratio"`: the ratio of two HT totals, sum(y / pi) / sum(den / pi). With
#'   y = "eligible and kept" and den = "eligible", this is design-weighted
#'   recall.
#'
#' With `yhat` (predictions for the sampled units) and `yhat_pop`
#' (predictions for every unit in the population) the difference estimator is
#' used instead: total = sum(yhat_pop) + sum((y - yhat) / pi), and the mean is
#' that total over length(yhat_pop). It stays unbiased whatever the quality of
#' the predictions, and its variance shrinks as they improve.
#'
#' The interval is a percentile bootstrap with the finite population
#' correction: the rescaling bootstrap of Rao and Wu (1988) with n_h - 1 draws
#' per stratum. In each of `B` resamples (under `seed`, with the caller's
#' random state put back) each stratum h draws n_h - 1 of its n_h sampled
#' units with replacement, and unit i gets the weight multiplier
#' 1 - lambda_h + lambda_h * r_i * n_h / (n_h - 1), where r_i is the number of
#' times it was drawn and lambda_h = sqrt(1 - f_h). The sampling fraction f_h
#' is n_h / sum(1 / pi) over the stratum, which is pi itself when pi is
#' constant within the stratum. For an HT total under stratified simple random
#' sampling the replicate variance then has expectation
#' sum_h N_h^2 (1 - f_h) s_h^2 / n_h, the design variance. A stratum judged in
#' full (pi = 1, so f_h = 1) is a census and adds no variance whatever its
#' values. `se` is the standard deviation of the replicates. A stratum with
#' one sampled unit also adds no variance, and the result notes it. Give
#' strata that match the design, with one pi per stratum, for the correction
#' to be exact.
#'
#' @param y Values for the sampled units (numeric or logical), no NA.
#' @param pi Inclusion probability of each sampled unit, in (0, 1].
#' @param strata Optional stratum of each sampled unit; the bootstrap
#'   resamples within strata.
#' @param estimand `"mean"`, `"total"` or `"ratio"`.
#' @param den For `"ratio"`, the denominator variable on the sampled units.
#' @param yhat,yhat_pop Predictions on the sampled units and on every unit in
#'   the population, for the difference estimator. Give both or neither.
#'   Not used with `"ratio"`.
#' @param B Number of bootstrap resamples; 0 skips the interval.
#' @param conf Confidence level.
#' @param seed Seed for the bootstrap.
#' @return A one-row data frame: `estimand`, `method` (`"horvitz_thompson"`,
#'   `"hajek"`, `"ratio"` or `"difference"`), `estimate`, `se`, `lower`,
#'   `upper`, `n` (sampled units), `N_hat` (sum(1 / pi), the estimated
#'   population size), `conf`, `B` and `note`.
#' @references
#' Horvitz, D. G. and Thompson, D. J. (1952). A generalization of sampling
#' without replacement from a finite universe. *Journal of the American
#' Statistical Association* 47(260), 663-685.
#'
#' Hajek, J. (1971). Comment on a paper by D. Basu. In Godambe, V. P. and
#' Sprott, D. A. (eds), *Foundations of Statistical Inference*, 236.
#'
#' Rao, J. N. K. and Wu, C. F. J. (1988). Resampling inference with complex
#' survey data. *Journal of the American Statistical Association* 83(401),
#' 231-241.
#'
#' Sarndal, C.-E., Swensson, B. and Wretman, J. (1992). *Model Assisted Survey
#' Sampling*. Springer. (The difference estimator, section 6.3.)
#' @family statistics
#' @export
#' @examples
#' # Every kept record judged (pi = 1), one in ten excluded records judged.
#' eligible <- c(rep(1, 18), rep(0, 2), rep(1, 1), rep(0, 29))
#' kept <- c(rep(1, 20), rep(0, 30))
#' pi <- ifelse(kept == 1, 1, 0.1)
#'
#' # Design-weighted recall: eligible and kept over all eligible.
#' hr_ht_estimate(eligible * kept, pi, strata = kept, estimand = "ratio",
#'                den = eligible, B = 500)
#'
#' # Estimated number of eligible records in the population.
#' hr_ht_estimate(eligible, pi, strata = kept, estimand = "total", B = 500)
hr_ht_estimate <- function(y, pi, strata = NULL, estimand = c("mean", "total", "ratio"),
                           den = NULL, yhat = NULL, yhat_pop = NULL, B = 2000,
                           conf = 0.95, seed = 1) {
  estimand <- match.arg(estimand)
  check_conf(conf)
  check_boot(B, seed)
  num_vec <- function(v, name) {
    if (is.logical(v)) v <- as.numeric(v)
    if (!is.numeric(v) || anyNA(v)) {
      gr_abort(sprintf("`%s` must be numeric (or logical) with no NA.", name),
               class = "gr_bad_setting")
    }
    v
  }
  y <- num_vec(y, "y")
  n <- length(y)
  if (!n) gr_abort("`y` has no sampled units.", class = "gr_bad_setting")
  if (!is.numeric(pi) || length(pi) != n) {
    gr_abort(sprintf("`pi` must be numeric with one value per unit of `y` (%d).", n),
             class = "gr_bad_setting")
  }
  if (anyNA(pi) || any(pi <= 0 | pi > 1)) {
    gr_abort("Every inclusion probability in `pi` must be in (0, 1], with no NA.",
             class = "gr_bad_setting")
  }
  if (is.null(strata)) strata <- rep(1L, n)
  if (length(strata) != n || anyNA(strata)) {
    gr_abort(sprintf("`strata` must have one value per unit of `y` (%d), with no NA.", n),
             class = "gr_bad_setting")
  }
  if (estimand == "ratio") {
    if (is.null(den)) gr_abort("The ratio estimand needs `den`.", class = "gr_bad_setting")
    den <- num_vec(den, "den")
    if (length(den) != n) {
      gr_abort(sprintf("`den` must have one value per unit of `y` (%d).", n),
               class = "gr_bad_setting")
    }
  } else if (!is.null(den)) {
    gr_abort("`den` is used only with estimand = \"ratio\".", class = "gr_bad_setting")
  }
  diff_est <- !is.null(yhat) || !is.null(yhat_pop)
  if (diff_est) {
    if (is.null(yhat) || is.null(yhat_pop)) {
      gr_abort("The difference estimator needs both `yhat` and `yhat_pop`.",
               class = "gr_bad_setting")
    }
    if (estimand == "ratio") {
      gr_abort("`yhat` and `yhat_pop` are used with the total and the mean, not the ratio.",
               class = "gr_bad_setting")
    }
    yhat <- num_vec(yhat, "yhat")
    yhat_pop <- num_vec(yhat_pop, "yhat_pop")
    if (length(yhat) != n) {
      gr_abort(sprintf("`yhat` must have one value per unit of `y` (%d).", n),
               class = "gr_bad_setting")
    }
    if (length(yhat_pop) < n) {
      gr_abort("`yhat_pop` must cover every unit in the population, so it cannot be shorter than `y`.",
               class = "gr_bad_setting")
    }
  }
  w <- 1 / pi
  method <- if (diff_est) "difference" else switch(estimand, total = "horvitz_thompson",
                                                   mean = "hajek", ratio = "ratio")
  # The estimate from case weights: each sampled unit counted `cw` times.
  est_fun <- function(cw) {
    switch(method,
      horvitz_thompson = sum(cw * w * y),
      hajek = sum(cw * w * y) / sum(cw * w),
      ratio = { d <- sum(cw * w * den); if (d == 0) NA_real_ else sum(cw * w * y) / d },
      difference = {
        tot <- sum(yhat_pop) + sum(cw * w * (y - yhat))
        if (estimand == "mean") tot / length(yhat_pop) else tot
      })
  }
  est <- est_fun(rep(1, n))
  note <- NA_character_
  groups <- split(seq_len(n), as.character(strata))
  if (any(lengths(groups) == 1L)) {
    note <- "A stratum with one sampled unit adds no variance to the bootstrap."
  }
  if (method == "ratio" && is.na(est)) {
    note <- "The denominator total is zero, so the ratio is undefined."
  }
  se <- NA_real_; ci <- c(NA_real_, NA_real_)
  if (B > 0 && !is.na(est)) {
    # Rao-Wu rescaling: n_h - 1 draws per stratum, multipliers scaled by
    # lambda_h = sqrt(1 - f_h). A census stratum (f_h = 1) gets lambda_h = 0,
    # so every one of its units keeps multiplier 1 in every replicate.
    lambda <- vapply(groups, function(g) sqrt(max(0, 1 - length(g) / sum(w[g]))),
                     numeric(1))
    reps <- with_private_rng(seed, vapply(seq_len(B), function(b) {
      cw <- rep(1, n)
      for (k in seq_along(groups)) {
        g <- groups[[k]]; m <- length(g) - 1L
        if (m < 1L || lambda[[k]] == 0) next
        r <- tabulate(sample.int(m + 1L, m, replace = TRUE), m + 1L)
        cw[g] <- 1 - lambda[[k]] + lambda[[k]] * r * (m + 1L) / m
      }
      est_fun(cw)
    }, numeric(1)))
    if (any(!is.na(reps))) {
      se <- stats::sd(reps, na.rm = TRUE)
      a <- 1 - conf
      ci <- stats::quantile(reps, c(a / 2, 1 - a / 2), names = FALSE, na.rm = TRUE, type = 7)
    }
  }
  data.frame(estimand = estimand, method = method, estimate = est, se = se,
             lower = ci[1], upper = ci[2], n = n, N_hat = sum(w), conf = conf,
             B = as.integer(B), note = note, stringsAsFactors = FALSE)
}

#' Prediction-powered inference for a mean
#'
#' Estimates the mean of an outcome from many units that have only a model's
#' prediction and a few that also have the true value, without inheriting the
#' model's bias. Use it to report a judge-scored accuracy, or any rate where a
#' model labelled everything and people labelled a sample.
#'
#' With `tune = FALSE` this is the estimator of Angelopoulos et al. (2023):
#'
#'     estimate = mean(yhat_U) + mean(y_L - yhat_L)
#'     variance = var(yhat_U) / N + var(y_L - yhat_L) / n
#'
#' where U are the `N` unlabelled units and L the `n` labelled ones. The
#' second term (the rectifier) removes the predictions' bias.
#'
#' With `tune = TRUE` (PPI++, Angelopoulos, Duchi and Zrnic 2023) the
#' predictions are scaled by lambda:
#'
#'     estimate = mean(y_L) + lambda * (mean(yhat_U) - mean(yhat_L))
#'     lambda   = cov(y_L, yhat_L) / ((1 + n / N) * var(yhat_L))
#'
#' clipped to `[0, 1]`. lambda = 0 is the mean of the labelled units alone and
#' lambda = 1 the untuned estimator, so tuning never does worse than either
#' in large samples: poor predictions get little weight.
#'
#' When `pi` is given and varies, the labelled units were drawn with unequal
#' probabilities from the whole set (U and L together, N + n units), and the
#' rectifier is inverse-probability weighted as in design-based supervised
#' learning (Egami et al. 2023). Each unit gets the pseudo-outcome
#'
#'     ytilde_i = lambda * yhat_i + R_i * (y_i - lambda * yhat_i) / pi_i
#'
#' with R_i = 1 for labelled units, and the estimate is the mean of ytilde
#' over all N + n units with variance var(ytilde) / (N + n). Tuning chooses
#' the lambda in `[0, 1]` that minimises that variance. Equal `pi` gives the
#' unweighted form above.
#'
#' The interval is normal: estimate +/- z * se.
#'
#' @param yhat_unlabelled Predictions on the units without a true value.
#' @param yhat_labelled Predictions on the labelled units.
#' @param y_labelled True values on the labelled units (numeric or logical).
#' @param pi Optional probability with which each labelled unit was chosen for
#'   labelling, in (0, 1].
#' @param conf Confidence level.
#' @param tune Whether to tune lambda (PPI++). `FALSE` fixes it at 1.
#' @return A one-row data frame: `estimate`, `se`, `lower`, `upper`, `n`
#'   (labelled), `N` (unlabelled), `lambda` and `method` (`"ppi"`, `"ppi++"`,
#'   `"dsl"` or `"dsl tuned"`).
#' @references
#' Angelopoulos, A. N., Bates, S., Fannjiang, C., Jordan, M. I. and Zrnic, T.
#' (2023). Prediction-powered inference. *Science* 382(6671), 669-674.
#'
#' Angelopoulos, A. N., Duchi, J. C. and Zrnic, T. (2023). PPI++: Efficient
#' prediction-powered inference. arXiv:2311.01453.
#'
#' Egami, N., Hinck, M., Stewart, B. M. and Wei, H. (2023). Using imperfect
#' surrogates for downstream inference: design-based supervised learning for
#' social science applications of large language models. *Advances in Neural
#' Information Processing Systems* 36.
#' @family statistics
#' @export
#' @examples
#' set.seed(2)
#' truth <- rbinom(2100, 1, 0.3)
#' # A judge that is right 85% of the time.
#' judged <- ifelse(runif(2100) < 0.85, truth, 1 - truth)
#' lab <- 1:100
#' hr_ppi(judged[-lab], judged[lab], truth[lab])
#' hr_ppi(judged[-lab], judged[lab], truth[lab], tune = FALSE)
hr_ppi <- function(yhat_unlabelled, yhat_labelled, y_labelled, pi = NULL,
                   conf = 0.95, tune = TRUE) {
  check_conf(conf)
  num_vec <- function(v, name) {
    if (is.logical(v)) v <- as.numeric(v)
    if (!is.numeric(v) || anyNA(v)) {
      gr_abort(sprintf("`%s` must be numeric (or logical) with no NA.", name),
               class = "gr_bad_setting")
    }
    v
  }
  yu <- num_vec(yhat_unlabelled, "yhat_unlabelled")
  yl <- num_vec(yhat_labelled, "yhat_labelled")
  y <- num_vec(y_labelled, "y_labelled")
  if (!is.logical(tune) || length(tune) != 1L || is.na(tune)) {
    gr_abort("`tune` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  n <- length(y); N <- length(yu)
  if (length(yl) != n) {
    gr_abort(sprintf("`yhat_labelled` and `y_labelled` must have the same length, not %d and %d.",
                     length(yl), n), class = "gr_bad_setting")
  }
  if (n < 2L || N < 2L) {
    gr_abort("At least two labelled and two unlabelled units are needed.",
             class = "gr_bad_setting")
  }
  if (!is.null(pi)) {
    if (!is.numeric(pi) || length(pi) != n || anyNA(pi) || any(pi <= 0 | pi > 1)) {
      gr_abort(sprintf("`pi` must give one probability in (0, 1] per labelled unit (%d), with no NA.", n),
               class = "gr_bad_setting")
    }
  }
  z <- stats::qnorm(1 - (1 - conf) / 2)
  out <- function(est, se, lambda, method) {
    data.frame(estimate = est, se = se, lower = est - z * se, upper = est + z * se,
               n = n, N = N, lambda = lambda, method = method, stringsAsFactors = FALSE)
  }
  if (!is.null(pi) && diff(range(pi)) > 1e-12) {
    # DSL: every unit, labelled or not, gets a pseudo-outcome
    # lambda * a_i + b_i, with a = yhat (1 - R / pi) and b = R y / pi.
    yh <- c(yu, yl)
    R <- c(rep(0, N), rep(1, n))
    p_all <- c(rep(1, N), pi)
    a <- yh * (1 - R / p_all)
    b <- R * c(rep(0, N), y) / p_all
    lambda <- 1
    if (tune) {
      va <- stats::var(a)
      lambda <- if (va > 0) min(1, max(0, -stats::cov(a, b) / va)) else 0
    }
    yt <- lambda * a + b
    return(out(mean(yt), sqrt(stats::var(yt) / (N + n)), lambda,
               if (tune) "dsl tuned" else "dsl"))
  }
  lambda <- 1
  if (tune) {
    v <- stats::var(yl)
    lambda <- if (v > 0) min(1, max(0, stats::cov(y, yl) / ((1 + n / N) * v))) else 0
  }
  est <- mean(y) + lambda * (mean(yu) - mean(yl))
  se <- sqrt(lambda^2 * stats::var(yu) / N + stats::var(y - lambda * yl) / n)
  out(est, se, lambda, if (tune) "ppi++" else "ppi")
}
