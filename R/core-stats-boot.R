# core-stats-boot.R: the cluster bootstrap, BCa and studentised bootstrap
# intervals, cluster-robust t intervals, and the small-sample intervals for
# accuracy.
#
# Every bootstrapped quantity in a benchmark report is a ratio of sums over
# clusters (accuracy is items' mean correctness summed per cluster over the
# items per cluster; cost per correct item is dollars summed per cluster over
# correct runs summed per cluster), so one resample is a vector of cluster
# counts and every statistic of it is a matrix product. The jackknife that
# BCa needs is the same ratio with one cluster left out.

#' Cluster resample counts: a B x C matrix whose row b counts how often each
#' cluster was drawn in resample b.
#'
#' The draws are made as boot::boot() makes them for an ordinary bootstrap,
#' one call to sample.int() filling a B x C index matrix by column, so the
#' same seed gives the same resamples as boot() on the clusters.
#' @noRd
cluster_counts <- function(C, B) {
  idx <- sample.int(C, C * B, replace = TRUE)
  dim(idx) <- c(B, C)
  # One tabulate() over (resample, cluster) pairs numbered row by row.
  cell <- (rep(seq_len(B), C) - 1L) * C + as.vector(idx)
  matrix(tabulate(cell, nbins = B * C), B, C, byrow = TRUE)
}

#' Bootstrap replicates, full-sample values and cluster jackknife values of
#' ratios of cluster sums.
#'
#' `num` and `den` are C x K matrices of per-cluster sums, one column per
#' statistic; statistic k is sum(num[, k]) / sum(den[, k]).
#' @noRd
ratio_boot <- function(num, den, counts) {
  num <- as.matrix(num); den <- as.matrix(den)
  tn <- colSums(num); td <- colSums(den)
  t0 <- tn / td
  t <- (counts %*% num) / (counts %*% den)
  # Leaving cluster c out takes its sums off both totals.
  jack <- sweep(-num, 2L, tn, `+`) / sweep(-den, 2L, td, `+`)
  list(t0 = t0, t = t, jack = jack)
}

#' Quantiles of bootstrap replicates interpolated on the normal scale, as
#' boot's norm.inter() takes them: the order statistic at (B + 1) * alpha when
#' that is a whole number, else a straight line between its neighbours on the
#' qnorm() scale, and the extremes when it falls outside 1..B.
#' @noRd
norm_inter <- function(t, alpha) {
  t <- sort(t[is.finite(t)])
  R <- length(t)
  rk <- (R + 1) * alpha
  k <- trunc(rk)
  vapply(seq_along(alpha), function(j) {
    if (k[j] <= 0) return(t[1L])
    if (k[j] >= R) return(t[R])
    if (k[j] == rk[j]) return(t[k[j]])
    z <- stats::qnorm(c(alpha[j], k[j] / (R + 1), (k[j] + 1) / (R + 1)))
    t[k[j]] + (z[1] - z[2]) / (z[3] - z[2]) * (t[k[j] + 1L] - t[k[j]])
  }, numeric(1))
}

#' A BCa interval (Efron 1987) from bootstrap replicates `t`, the full-sample
#' value `t0` and leave-one-cluster-out values `jack`.
#'
#' The bias correction is z0 = qnorm(share of replicates below t0, ties
#' within rounding error not counted) and the
#' acceleration a = sum(L^3) / (6 * sum(L^2)^1.5) with jackknife influence
#' values L = mean(jack) - jack (Efron and Tibshirani 1993, 14.3). The
#' adjusted levels are pnorm(z0 + (z0 + z) / (1 - a * (z0 + z))), read off
#' with norm_inter(). This is the interval boot::boot.ci(type = "bca")
#' returns when given the same replicates and L.
#'
#' When every replicate equals t0 the interval is the point. When t0 lies
#' outside the replicates, so z0 is infinite, or the acceleration is not
#' finite, BCa is undefined and the percentile interval is returned, with
#' `bca = FALSE` saying so.
#' @noRd
bca_interval <- function(t, t0, jack, conf = 0.95) {
  t <- t[is.finite(t)]
  if (!is.finite(t0) || length(t) < 2L) {
    return(list(lower = NA_real_, upper = NA_real_, bca = FALSE, z0 = NA_real_, a = NA_real_))
  }
  if (diff(range(t)) == 0) {
    return(list(lower = t[1L], upper = t[1L], bca = TRUE, z0 = NA_real_, a = NA_real_))
  }
  alpha <- (1 + c(-conf, conf)) / 2
  # A resample that equals t0 in exact arithmetic can land a rounding error
  # below it when its sums are added in another order; such ties are not
  # counted as below.
  z0 <- stats::qnorm(sum(t < t0 - 1e-12 * max(1, abs(t0))) / length(t))
  jack <- jack[is.finite(jack)]
  L <- mean(jack) - jack
  a <- sum(L^3) / (6 * sum(L^2)^1.5)
  if (!is.finite(z0) || !is.finite(a)) {
    q <- norm_inter(t, alpha)
    return(list(lower = q[1L], upper = q[2L], bca = FALSE, z0 = z0, a = a))
  }
  z <- stats::qnorm(alpha)
  adj <- stats::pnorm(z0 + (z0 + z) / (1 - a * (z0 + z)))
  q <- norm_inter(t, adj)
  list(lower = q[1L], upper = q[2L], bca = TRUE, z0 = z0, a = a)
}

#' BCa intervals for every column of a ratio_boot() result, as a data frame
#' with estimate, lower, upper and whether BCa held (else percentile).
#' @noRd
bca_table <- function(rb, conf) {
  rows <- lapply(seq_along(rb$t0), function(k) {
    iv <- bca_interval(rb$t[, k], rb$t0[[k]], rb$jack[, k], conf)
    data.frame(estimate = unname(rb$t0[[k]]), lower = iv$lower, upper = iv$upper,
               bca = iv$bca, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Cluster-robust (linearised) standard errors of ratios of cluster sums.
#'
#' `num` and `den` are C x K matrices of per-cluster sums; statistic k is the
#' ratio estimator r_k = sum(num[, k]) / sum(den[, k]). Its first-order
#' (Taylor) linearisation gives the residuals e_ck = num_ck - r_k den_ck, and
#' the variance with the small-sample factor C / (C - 1),
#' V_k = C / (C - 1) * sum_c e_ck^2 / (sum_c den_ck)^2 (Cochran 1977,
#' chapter 6; Cameron and Miller 2015). The covariance of r_j
#' and r_k is the same sum over e_cj e_ck. `df` is C - 1, the degrees of
#' freedom the t quantiles take with few clusters (Cameron and Miller 2015).
#' @noRd
cluster_ratio_se <- function(num, den) {
  num <- as.matrix(num); den <- as.matrix(den)
  C <- nrow(num)
  td <- colSums(den)
  est <- colSums(num) / td
  res <- num - sweep(den, 2L, est, `*`)
  # Residuals that are 0 in exact arithmetic (every cluster at the same
  # ratio) can come out at rounding-error size; they are set to 0.
  res[abs(res) < 1e-12 * pmax(1, abs(num))] <- 0
  scaled <- sweep(res, 2L, td, `/`)
  vc <- C / (C - 1) * crossprod(scaled)
  list(estimate = est, se = sqrt(diag(vc)), vcov = vc, df = C - 1L)
}

#' Cluster-robust t intervals for ratios of cluster sums: the estimate plus
#' and minus t_(C - 1, (1 + conf) / 2) times the linearised standard error of
#' cluster_ratio_se(). A statistic whose standard error is 0 (every cluster
#' at the same ratio) gets the point as its interval, with `zero_var = TRUE`.
#'
#' With `scale = "logit"` the interval is built for logit(r), with the delta
#' method standard error se / (r (1 - r)), and mapped back, so it stays inside
#' (0, 1) and follows the skew of a proportion near a bound (Agresti 2013).
#' It is undefined at r = 0 or 1 and
#' when se = 0; those rows come back NA with `defined = FALSE`.
#' @noRd
cluster_t_table <- function(num, den, conf, scale = c("identity", "logit")) {
  scale <- match.arg(scale)
  v <- cluster_ratio_se(num, den)
  q <- stats::qt((1 + conf) / 2, v$df)
  est <- unname(v$estimate); se <- unname(v$se)
  zero <- se == 0
  if (scale == "identity") {
    lower <- est - ifelse(zero, 0, q * se)
    upper <- est + ifelse(zero, 0, q * se)
    defined <- is.finite(est)
  } else {
    defined <- is.finite(est) & est > 0 & est < 1 & !zero
    h <- ifelse(defined, q * se / (est * (1 - est)), NA_real_)
    lg <- ifelse(defined, stats::qlogis(pmin(pmax(est, 1e-300), 1 - 1e-16)), NA_real_)
    lower <- stats::plogis(lg - h)
    upper <- stats::plogis(lg + h)
  }
  data.frame(estimate = est, se = se, lower = lower, upper = upper, df = v$df,
             zero_var = zero, defined = defined, stringsAsFactors = FALSE)
}

#' Studentised (bootstrap-t) cluster bootstrap intervals for ratios of
#' cluster sums (Efron and Tibshirani 1993, chapter 12; Davison and Hinkley
#' 1997, chapters 2 and 5).
#'
#' Each resample b gives r*_b and its own linearised standard error se*_b,
#' the cluster_ratio_se() formula applied to the resampled clusters with
#' their counts as weights, and t*_b = (r*_b - r) / se*_b. With q_lo and q_hi
#' the (1 - conf) / 2 and (1 + conf) / 2 quantiles of t* (the order
#' statistics of quantile type 1), the interval is
#' [r - q_hi se, r - q_lo se], with se the full-sample standard error.
#' A resample at r with se*_b = 0 has t*_b = 0. With `bounds` the interval is
#' cut to that range. A statistic with se = 0 comes back NA with
#' `defined = FALSE`.
#' @noRd
studentised_table <- function(num, den, counts, conf, bounds = c(-Inf, Inf)) {
  num <- as.matrix(num); den <- as.matrix(den)
  C <- nrow(num)
  v <- cluster_ratio_se(num, den)
  nb <- counts %*% num; db <- counts %*% den
  rb <- nb / db
  # sum_c w_c (num_c - r* den_c)^2, expanded so each part is one product.
  ss <- counts %*% num^2 - 2 * rb * (counts %*% (num * den)) + rb^2 * (counts %*% den^2)
  seb <- sqrt(C / (C - 1) * pmax(ss, 0)) / db
  rows <- lapply(seq_len(ncol(num)), function(k) {
    est <- unname(v$estimate[[k]]); se <- unname(v$se[[k]])
    if (!is.finite(est) || se == 0) {
      return(data.frame(estimate = est, se = se, lower = NA_real_, upper = NA_real_,
                        defined = FALSE))
    }
    tt <- (rb[, k] - est) / seb[, k]
    tt[is.nan(tt)] <- 0
    q <- stats::quantile(tt, c((1 + conf) / 2, (1 - conf) / 2), type = 1, names = FALSE)
    data.frame(estimate = est, se = se,
               lower = min(max(est - q[[1]] * se, bounds[[1]]), bounds[[2]]),
               upper = max(min(est - q[[2]] * se, bounds[[2]]), bounds[[1]]), defined = TRUE)
  })
  do.call(rbind, rows)
}

#' The critical value of simultaneous cluster-robust t intervals: the `conf`
#' quantile of max_j |T_j| for T multivariate t with `df` degrees of freedom
#' and correlation matrix that of `vcov` (Hothorn, Bretz and Westfall 2008,
#' the single-step max-t method). It is computed from `z`, an M x K matrix of
#' standard normal draws, and `w`, M chi-squared draws on `df` degrees of
#' freedom: T = (z L) / sqrt(w / df) with L L' the correlation matrix (from
#' its eigen decomposition, so a singular matrix is allowed). With one
#' statistic it is the t quantile itself.
#' @noRd
max_t_critical <- function(vcov, df, conf, z, w) {
  K <- nrow(vcov)
  if (K == 1L) return(stats::qt((1 + conf) / 2, df))
  s <- sqrt(diag(vcov))
  R <- vcov / outer(s, s)
  e <- eigen(R, symmetric = TRUE)
  L <- t(e$vectors %*% diag(sqrt(pmax(e$values, 0)), K))
  tt <- (z[, seq_len(K), drop = FALSE] %*% L) / sqrt(w / df)
  stats::quantile(do.call(pmax, as.data.frame(abs(tt))), conf, names = FALSE)
}

#' Posterior of the mean accuracy under a beta-binomial model with a cluster
#' random effect, computed on a grid.
#'
#' Cluster c has n_c trials (scored runs over its items) and x_c successes.
#' Its accuracy theta_c is Beta(mu (1 - rho) / rho, (1 - mu) (1 - rho) / rho):
#' mean mu, and rho the intra-cluster correlation, the overdispersion of
#' cluster accuracies. Given theta_c the trials are binomial. The priors on
#' mu and rho are flat on (0, 1). The likelihood of one cluster, up to a
#' constant, is B(x_c + alpha, n_c - x_c + beta) / B(alpha, beta). The
#' posterior is evaluated on a grid of 100 rho values and twice for mu: a
#' coarse grid of 200 to find where the mass is, then 400 points over that
#' range. The interval is equal-tailed, read from the
#' marginal posterior CDF of mu by linear interpolation; the one-sided bounds
#' at level `conf` are returned too, for estimates at 0 or 1.
#' @noRd
bayes_betabin <- function(x, n, conf = 0.95) {
  keep <- n > 0
  x <- x[keep]; n <- n[keep]
  # Clusters with the same counts contribute the same term.
  key <- paste(x, n)
  first <- !duplicated(key)
  mult <- as.vector(table(factor(key, levels = key[first])))
  x <- x[first]; n <- n[first]
  rho <- (seq_len(100) - 0.5) / 100
  post_mu <- function(mu) {
    a <- outer(mu, (1 - rho) / rho)
    b <- outer(1 - mu, (1 - rho) / rho)
    ll <- matrix(0, length(mu), length(rho))
    for (j in seq_along(x)) {
      ll <- ll + mult[j] * (lbeta(x[j] + a, n[j] - x[j] + b) - lbeta(a, b))
    }
    p <- exp(ll - max(ll))
    list(mu = rowSums(p), rho = colSums(p))
  }
  coarse <- (seq_len(200) - 0.5) / 200
  pm <- post_mu(coarse)$mu
  live <- which(pm > max(pm) * 1e-10)
  lo <- max(coarse[min(live)] - 1 / 200, 1e-6)
  hi <- min(coarse[max(live)] + 1 / 200, 1 - 1e-6)
  step <- (hi - lo) / 400
  mu <- lo + (seq_len(400) - 0.5) * step
  p <- post_mu(mu)
  w <- p$mu / sum(p$mu)
  # Each grid point holds the mass of its cell; the CDF rises across cells.
  edges <- c(lo, lo + seq_len(400) * step)
  cdf <- c(0, cumsum(w))
  q <- function(prob) stats::approx(cdf, edges, xout = prob, ties = "ordered")$y
  alpha <- (1 - conf) / 2
  list(lower = q(alpha), upper = q(1 - alpha), median = q(0.5), mean = sum(w * mu),
       rho_mean = sum(rho * p$rho) / sum(p$rho),
       lower_one_sided = q(1 - conf), upper_one_sided = q(conf))
}

#' An interval for a proportion from clustered data by Clopper-Pearson on an
#' effective sample size (Korn and Graubard 1998), with items as trials.
#'
#' `x` holds each cluster's sum of item accuracies (each item's mean over
#' runs, so it may be fractional) and `n` its number of items. Runs are not
#' trials: runs of one item mostly agree, and counting them would make N
#' runs look like N independent draws. The variance of the pooled proportion
#' is estimated from cluster totals,
#' v = C / (C - 1) * sum((n_c * (pbar_c - p))^2) / N^2; the effective size is
#' p (1 - p) / v, at most N items, scaled by (t_{N-1} / t_{C-1})^2 for the few
#' degrees of freedom C clusters carry; and the Clopper-Pearson bounds are
#' taken at x = p * n_eff, with qbeta() accepting fractional counts.
#' @noRd
korn_graubard <- function(x, n, conf = 0.95) {
  keep <- n > 0
  x <- x[keep]; n <- n[keep]
  N <- sum(n); C <- length(n)
  p <- sum(x) / N
  a <- (1 - conf) / 2
  if (C < 2L) return(list(lower = NA_real_, upper = NA_real_, n_eff = NA_real_))
  v <- C / (C - 1) * sum((x - n * p)^2) / N^2
  n_eff <- if (v > 0) min(N, p * (1 - p) / v) else N
  if (N > 1) n_eff <- n_eff * (stats::qt(1 - a, N - 1) / stats::qt(1 - a, C - 1))^2
  xe <- p * n_eff
  lower <- if (xe <= 0) 0 else stats::qbeta(a, xe, n_eff - xe + 1)
  upper <- if (xe >= n_eff) 1 else stats::qbeta(1 - a, xe + 1, n_eff - xe)
  list(lower = lower, upper = upper, n_eff = n_eff)
}
