# core-stats-boot.R: the cluster bootstrap, BCa intervals and the small-sample
# intervals that replace them on small benchmarks.
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
