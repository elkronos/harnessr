# test-core-bench-report.R: hr_report() intervals, stability, reliability,
# cost, frontier, failures and variance components.

# A benchmark table from a per-item count of correct runs: item i of arm a
# is right on its first k[i] runs out of `runs`.
counts_bench <- function(k, nper, arm = "a", runs = 5) {
  cl <- rep(seq_along(nper), nper)
  do.call(rbind, lapply(seq_along(k), function(i) {
    data.frame(cluster = sprintf("c%02d", cl[i]), item = sprintf("q%02d", i), arm = arm,
               run = seq_len(runs), correct = seq_len(runs) <= k[i],
               stringsAsFactors = FALSE)
  }))
}

# Clusters with accuracies drawn around mu, items drawn around their
# cluster, runs drawn around their item: mu is the accuracy of the
# population the clusters come from.
sim_bench <- function(n_clusters, per_cluster, runs = 5, mu = 0.7, rho = 0.2, conc = 4) {
  th <- stats::rbeta(n_clusters, mu * (1 - rho) / rho, (1 - mu) * (1 - rho) / rho)
  cl <- rep(seq_len(n_clusters), each = per_cluster)
  p <- stats::rbeta(length(cl), th[cl] * conc, (1 - th[cl]) * conc)
  d <- expand.grid(run = seq_len(runs), it = seq_along(cl))
  data.frame(cluster = paste0("c", cl[d$it]), item = paste0("i", d$it), arm = "a",
             run = d$run, correct = stats::runif(nrow(d)) < p[d$it],
             stringsAsFactors = FALSE)
}

# 12 clusters of 2 to 4 items, two arms, 5 runs.
nper12 <- c(3, 2, 4, 3, 3, 2, 4, 3, 2, 3, 4, 3)
ka12 <- c(5, 4, 0, 5, 3, 2, 5, 5, 5, 1, 4, 0, 3, 5, 5, 4, 2, 5, 5, 1, 0, 5, 3, 4, 5, 5, 2, 3,
          5, 5, 4, 0, 5, 3, 5, 4)
kb12 <- c(5, 5, 2, 5, 4, 3, 5, 5, 5, 3, 4, 2, 3, 5, 5, 5, 3, 5, 5, 3, 2, 5, 4, 5, 5, 5, 3, 3,
          5, 5, 5, 2, 5, 4, 5, 5)

test_that("the BCa cluster bootstrap matches boot::boot.ci on the same resamples", {
  # BCa still gives the cost and pass^k intervals, from the report's
  # resamples. Cluster sums of item accuracy (correct runs / 5) per arm.
  cl <- rep(seq_along(nper12), nper12)
  S <- cbind(tapply(ka12, cl, sum), tapply(kb12, cl, sum)) / 5
  cnt <- harnessr:::with_private_rng(7, harnessr:::cluster_counts(12L, 999L))
  den <- matrix(nper12, 12L, 2L)
  tab <- harnessr:::bca_table(harnessr:::ratio_boot(S, den, cnt), 0.95)
  dif <- harnessr:::bca_table(harnessr:::ratio_boot(S[, 1] - S[, 2], den[, 1], cnt), 0.95)
  # Reference values from boot 1.3: boot() over the 12 cluster sums with
  # set.seed(7) and R = 999, then boot.ci(type = "bca") with L the cluster
  # jackknife influence values (C - 1) * (mean(t_jack) - t_jack).
  expect_equal(tab$lower, c(0.593371176004613, 0.764790555665983), tolerance = 1e-10)
  expect_equal(tab$upper, c(0.789231622024109, 0.888082761058241), tolerance = 1e-10)
  expect_equal(dif$lower, -0.1716115464907494, tolerance = 1e-10)
  expect_equal(dif$upper, -0.0838355270689133, tolerance = 1e-10)
  expect_equal(tab$estimate, c(127, 150) / 180)
  expect_identical(tab$bca, c(TRUE, TRUE))
  # The resamples are the ones boot() draws: same clusters, same order.
  expect_identical(dim(cnt), c(999L, 12L))
  expect_true(all(rowSums(cnt) == 12))
  set.seed(7)
  idx <- matrix(sample.int(12L, 12L * 999L, replace = TRUE), 999L)
  expect_equal(as.vector(cnt[5, ]), tabulate(idx[5, ], 12L))
})

test_that("hr_report gives the studentised bootstrap and the cluster-robust t intervals", {
  d <- rbind(counts_bench(ka12, nper12, "a"), counts_bench(kb12, nper12, "b"))
  r <- hr_report(d, method = "bootstrap", B = 999, seed = 7)
  expect_equal(r$accuracy$estimate, c(127, 150) / 180)
  expect_identical(r$accuracy$method, rep("studentised_cluster_bootstrap", 2))
  # Computed apart from the package: with set.seed(7) and
  # idx <- matrix(sample.int(12, 12 * 999, replace = TRUE), 999), resample b
  # takes clusters idx[b, ] with their sums S_j and sizes n_j and gives
  # r_b = sum(S_j) / sum(n_j),
  # se_b = sqrt(12 / 11 * sum((S_j - r_b n_j)^2)) / sum(n_j) and
  # t_b = (r_b - r) / se_b. With se the same formula on the data and q(p)
  # the ceiling(999 p)-th smallest t_b, the interval is
  # [r - q(0.975) se, r - q(0.025) se].
  expect_equal(r$accuracy$lower, c(0.548125220311359, 0.73013180948318), tolerance = 1e-10)
  expect_equal(r$accuracy$upper, c(0.796884871066802, 0.893981648193649), tolerance = 1e-10)
  # The paired difference a - b: S_c the cluster sums of item differences,
  # d = sum(S_c) / 36 = -0.127777...,
  # se = sqrt(12 / 11 * sum((S_c - d n_c)^2)) / 36 = 0.0239083912771860,
  # and d -/+ qt(0.975, 11) se with qt(0.975, 11) = 2.20098516009164.
  expect_identical(r$contrasts$method, "cluster_robust_t")
  expect_equal(r$contrasts$estimate, -23 / 180)
  expect_equal(r$contrasts$lower, -0.180399792180529, tolerance = 1e-10)
  expect_equal(r$contrasts$upper, -0.0751557633750269, tolerance = 1e-10)
  # One pair: the simultaneous critical value is the t quantile itself.
  expect_identical(r$simultaneous$method, "max_t_cluster_robust")
  expect_equal(r$simultaneous$critical, 2.20098516009164, tolerance = 1e-12)
  expect_equal(r$simultaneous$lower, r$contrasts$lower)
  # The logit interval: r = 127 / 180 and 150 / 180, se from the same
  # formula (0.0494372244063329 and 0.0304290309725092), and
  # plogis(qlogis(r) -/+ qt(0.975, 11) se / (r (1 - r))).
  ct <- hr_report(d, method = "cluster_t", B = 999, seed = 7)
  expect_identical(ct$method, "cluster_t")
  expect_identical(ct$accuracy$method, rep("logit_cluster_robust_t", 2))
  expect_equal(ct$accuracy$lower, c(0.58664910420145, 0.75532664538481), tolerance = 1e-10)
  expect_equal(ct$accuracy$upper, c(0.801812357628383, 0.890088911019808), tolerance = 1e-10)
  expect_equal(ct$contrasts, r$contrasts)
  expect_output(print(ct), "cluster-robust t on the logit scale")
  expect_output(print(r), "studentised cluster bootstrap, B = 999")
})

test_that("the max-t critical value follows the correlation of the differences", {
  set.seed(1)
  z <- matrix(stats::rnorm(40000), 20000, 2)
  w <- stats::rchisq(20000, 9)
  # Perfectly correlated differences (a singular matrix) act as one.
  one <- harnessr:::max_t_critical(matrix(1, 2, 2), 9, 0.95, z, w)
  expect_equal(one, stats::qt(0.975, 9), tolerance = 0.02)
  # Independent ones need more. With a shared chi-squared denominator the
  # exact value solves E[(2 pnorm(c sqrt(W / 9)) - 1)^2] = 0.95 for
  # W ~ chi-squared on 9 df; integrate() and uniroot() give c = 2.656693233.
  # 20000 draws carry a Monte Carlo error of about 0.03.
  ind <- harnessr:::max_t_critical(diag(2), 9, 0.95, z, w)
  expect_equal(ind, 2.656693233, tolerance = 0.06 / 2.66)
  expect_identical(harnessr:::max_t_critical(matrix(4), 9, 0.95, z, w), stats::qt(0.975, 9))
})

test_that("BCa falls back to the percentile interval when the estimate is outside the resamples", {
  iv <- harnessr:::bca_interval(t = c(1, 2, 3, 4), t0 = 0, jack = c(0, 1, 2), conf = 0.9)
  expect_false(iv$bca)
  expect_identical(c(iv$lower, iv$upper), c(1, 4))
  same <- harnessr:::bca_interval(t = rep(0.5, 10), t0 = 0.5, jack = rep(0.5, 3))
  expect_identical(c(same$lower, same$upper), c(0.5, 0.5))
})

test_that("a large simulated benchmark uses the cluster bootstrap and covers the truth", {
  set.seed(101)
  d <- sim_bench(40, 8)
  r <- hr_report(d)
  expect_identical(r$method, "bootstrap")
  expect_identical(c(r$n_items, r$n_clusters, r$runs, r$B), c(320L, 40L, 5L, 2000L))
  expect_true(r$accuracy$lower < 0.7 && r$accuracy$upper > 0.7)
  expect_identical(hr_report(d, confirmatory = TRUE)$B, 5000L)
})

test_that("a small benchmark uses the cluster-robust t interval, never a Wald interval", {
  set.seed(5)
  d <- sim_bench(10, 5)
  r <- hr_report(d)
  expect_identical(r$method, "cluster_t")
  expect_identical(r$accuracy$method, "logit_cluster_robust_t")
  expect_match(r$method_reason, "fall short of 300 items and 30 clusters")
  p <- r$accuracy$estimate
  for (n in c(50, 250)) {
    wald <- p + c(-1, 1) * stats::qnorm(0.975) * sqrt(p * (1 - p) / n)
    expect_false(isTRUE(all.equal(c(r$accuracy$lower, r$accuracy$upper), wald,
                                  tolerance = 1e-3)))
  }
  expect_true(r$accuracy$lower >= 0 && r$accuracy$upper <= 1)
  expect_null(r$bayes)
  by <- hr_report(d, method = "bayes", B = 200)
  expect_identical(by$accuracy$method, "beta_binomial_bayes")
  expect_false(is.null(by$bayes))
  expect_true(any(grepl("missed mostly below the truth", by$notes)))
  # Even with 300 items, too few clusters keep the t interval.
  set.seed(6)
  expect_identical(hr_report(sim_bench(20, 16))$method, "cluster_t")
  ex <- hr_report(d, method = "exact")
  expect_identical(ex$accuracy$method, "korn_graubard_clopper_pearson")
  expect_true(ex$accuracy$lower < p && ex$accuracy$upper > p)
  for (m in c("auto", "cluster_t", "bayes", "exact", "bootstrap")) {
    expect_false(any(grepl("wald|normal", hr_report(d, method = m, B = 200)$accuracy$method)))
  }
  forced <- hr_report(d, method = "bootstrap", B = 200)
  expect_true(any(grepl("can undercover", forced$notes)))
})

test_that("coverage of both interval methods is near nominal over 100 replicates", {
  set.seed(2024)
  hit_boot <- vapply(seq_len(100), function(i) {
    a <- hr_report(sim_bench(40, 8), B = 1000, seed = i)$accuracy
    a$lower <= 0.7 && a$upper >= 0.7
  }, logical(1))
  # The small regime checks the paired difference too, on a two-arm corpus
  # of the coverage simulation's small design (50 items in 10 clusters, true
  # difference 0.05), drawn from a private stream so the draws of sim_bench()
  # are the same as without it.
  small <- harnessr:::sim_design("small")
  hit_t <- vapply(seq_len(100), function(i) {
    r <- hr_report(sim_bench(10, 5), B = 100, seed = i)
    stopifnot(identical(r$method, "cluster_t"))
    pair <- harnessr:::with_private_rng(i, harnessr:::sim_corpus(small))
    ct <- hr_report(pair, contrasts = c("new", "ref"), B = 100, seed = i, k = 1)$contrasts
    stopifnot(identical(ct$method, "cluster_robust_t"))
    c(accuracy = r$accuracy$lower <= 0.7 && r$accuracy$upper >= 0.7,
      difference = ct$lower <= 0.05 && ct$upper >= 0.05)
  }, logical(2))
  hit_bayes <- vapply(seq_len(100), function(i) {
    r <- hr_report(sim_bench(10, 5), B = 100, seed = i, method = "bayes")
    r$accuracy$lower <= 0.7 && r$accuracy$upper >= 0.7
  }, logical(1))
  expect_gte(mean(hit_boot), 0.85)
  expect_lte(mean(hit_boot), 0.99)
  expect_gte(mean(hit_t["accuracy", ]), 0.85)
  expect_lte(mean(hit_t["accuracy", ]), 0.99)
  # Bounds for the difference from the binomial spread of 100 replicates: at
  # a true coverage of 95% the count falls below 90 with probability 1.1%
  # (pbinom(89, 100, 0.95)) and reaches 100 with probability 0.6%
  # (0.95^100). The replicates are seeded, so the bounds can only fail after
  # a change to the method. The BCa cluster bootstrap that the t interval
  # replaced covers 87 of these 100 differences on the same resamples,
  # below the lower bound.
  expect_gte(mean(hit_t["difference", ]), 0.90)
  expect_lte(mean(hit_t["difference", ]), 0.99)
  expect_gte(mean(hit_bayes), 0.85)
  expect_lte(mean(hit_bayes), 0.99)
})

test_that("pass^k is the mean of choose(c, k) / choose(R, k)", {
  d <- counts_bench(c(5, 3, 0), c(2, 1))
  r <- hr_report(d, k = c(1, 3, 5, 7), B = 200)
  pk <- r$pass_k
  expect_identical(pk$k, c(1L, 3L, 5L))
  expect_equal(pk$pass_k, c((1 + 3 / 5 + 0) / 3, (1 + 1 / 10 + 0) / 3, 1 / 3))
  expect_true(any(grepl("k = 7 left out", r$notes)))
})

test_that("flip rate, TARa and run-level SD are read from a constructed table", {
  d <- data.frame(
    cluster = rep(c("a", "a", "b", "b"), each = 5), item = rep(paste0("q", 1:4), each = 5),
    arm = "x", run = rep(1:5, 4),
    correct = c(rep(TRUE, 5), TRUE, TRUE, FALSE, TRUE, TRUE, rep(FALSE, 10)),
    outcome = c(rep("Paris", 5), "Lima", "Lima", "Cusco", "Lima", "Lima",
                "Lyon", "Nice", "Lyon", "Lyon", "Lyon", rep(NA, 5)),
    failure_kind = c(rep(NA, 5), NA, NA, "wrong", NA, NA, rep("wrong", 5),
                     rep("refusal", 5)),
    stringsAsFactors = FALSE)
  r <- hr_report(d, B = 200)
  # Only q2's correctness changes across runs; q1 and q4 give the same
  # output every time (q4 refuses every time), while q3 is always wrong but
  # not always the same wrong answer.
  expect_equal(r$stability$flip_rate, 1 / 4)
  expect_equal(r$stability$tara, 2 / 4)
  expect_equal(r$stability$run_sd, stats::sd(c(0.5, 0.5, 0.25, 0.5, 0.5)))
  f <- r$failures
  expect_identical(c(f$wrong, f$refusal, f$parse_failure), c(6L, 5L, 0L))
  expect_equal(f$accuracy, 9 / 20)
  # Without refusals q4 drops out: (1 + 0.8 + 0) / 3.
  expect_equal(f$accuracy_without_parse_refusal, 1.8 / 3)
  expect_identical(f$runs_dropped, 5L)
})

test_that("the frontier is the Pareto set on cost and accuracy", {
  ps <- harnessr:::pareto_set(c(1, 2, 3, 2, 4, NA), c(0.5, 0.7, 0.9, 0.6, 0.85, 0.99))
  expect_identical(ps, c(TRUE, TRUE, TRUE, FALSE, FALSE, NA))
  # Ties: an arm matched on both by another is still on the frontier.
  expect_identical(harnessr:::pareto_set(c(1, 1), c(0.5, 0.5)), c(TRUE, TRUE))
  k <- c(5, 4, 5, 3, 5, 5, 2, 4)
  nper <- c(2, 2, 2, 2)
  arms <- list(cheap = c(0.001, 0), mid = c(0.002, 0), dear = c(0.003, 0), waste = c(0.004, 0))
  d <- do.call(rbind, Map(function(nm, adj) {
    b <- counts_bench(pmin(5, pmax(0, k + c(cheap = -2, mid = 0, dear = 1, waste = -1)[[nm]])),
                      nper, nm)
    b$usd <- adj[1]
    b
  }, names(arms), arms))
  r <- hr_report(d, B = 300)
  fr <- r$frontier
  expect_identical(fr$arm, names(arms))
  expect_identical(fr$on_frontier, c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(fr$usd_per_item, c(0.001, 0.002, 0.003, 0.004))
  expect_true(all(fr$frontier_share >= 0 & fr$frontier_share <= 1))
  expect_equal(fr$frontier_share[1], 1)
  expect_true(any(grepl("extension, not a published standard", r$notes)))
})

test_that("cost per item and per correct item, with the estimated share flagged", {
  d <- counts_bench(c(5, 5, 0, 5), c(2, 2), "a")
  d$usd <- 0.01
  d$tokens_in <- 100L
  d$tokens_out <- 20L
  d$usd_provenance <- ifelse(d$item == "q01", "estimated", "reported")
  r <- hr_report(d, B = 200)
  co <- r$cost
  expect_equal(co$usd_per_item, 0.01)
  expect_equal(co$usd_per_correct, 0.01 / 0.75)
  expect_equal(co$tokens_per_item, 120)
  expect_equal(co$tokens_per_correct, 160)
  expect_equal(co$usd_estimated_share, 0.25)
  expect_true(co$estimated_flag)
  expect_true(any(grepl("estimated token counts", r$notes)))
  expect_true(co$usd_per_correct_lower <= co$usd_per_correct)
  # No dollars recorded: cost is unknown rather than zero.
  d$usd[1] <- NA
  expect_true(is.na(hr_report(d, B = 200)$cost$usd_per_item))
})

test_that("variance components compare within-item run variance with between-item variance", {
  # p = 1, 0.6, 0, 0.4: within mean(p (1 - p)) = 0.12, between variance 0.13.
  d <- counts_bench(c(5, 3, 0, 2), c(2, 2))
  r <- hr_report(d, B = 200)
  p <- c(1, 0.6, 0, 0.4)
  expect_equal(r$variance$within, mean(p * (1 - p)))
  expect_equal(r$variance$between, mean((p - mean(p))^2))
  expect_equal(r$variance$within_share, 0.12 / 0.25)
  expect_identical(r$variance$recommend_runs, 10L)
  expect_true(any(grepl("use runs = 10", r$notes)))
  stable <- counts_bench(c(5, 5, 0, 0), c(2, 2))
  expect_identical(hr_report(stable, B = 200)$variance$within_share, 0)
})

test_that("fewer than 5 runs give a descriptive report without intervals", {
  d <- counts_bench(c(3, 2, 0, 1), c(2, 2), runs = 3)
  r <- hr_report(d)
  expect_true(r$descriptive)
  expect_identical(r$method, "none")
  expect_true(all(is.na(c(r$accuracy$lower, r$accuracy$upper, r$accuracy$rank_lower))))
  expect_identical(r$accuracy$method, "descriptive")
  expect_true(is.na(r$B))
  expect_true(any(grepl("Descriptive only", r$notes)))
  expect_identical(r$pass_k$k, c(1L, 3L))
})

test_that("paired differences, simultaneous intervals and rank intervals", {
  set.seed(9)
  base <- sim_bench(30, 10)
  shift <- base
  shift$arm <- "b"
  flip <- shift$correct == FALSE & stats::runif(nrow(shift)) < 0.5
  shift$correct[flip] <- TRUE
  third <- base
  third$arm <- "c"
  drop <- third$correct & stats::runif(nrow(third)) < 0.3
  third$correct[drop] <- FALSE
  d <- rbind(base, shift, third)
  r <- hr_report(d, B = 1000)
  expect_identical(r$method, "bootstrap")
  expect_identical(r$accuracy$arm, c("a", "b", "c"))
  expect_identical(paste(r$contrasts$arm1, r$contrasts$arm2), c("a b", "a c", "b c"))
  ab <- r$contrasts[1, ]
  expect_true(ab$upper < 0)
  s <- r$simultaneous
  # Three pairs widen the critical value past the one-at-a-time 1.96.
  expect_gt(s$critical[1], stats::qnorm(0.975))
  expect_true(all(s$lower < s$estimate & s$upper > s$estimate))
  expect_identical(s$method[1], "max_t_cluster_robust")
  # ... and stays below Bonferroni's for three pairs.
  expect_lt(s$critical[1], stats::qt(1 - 0.025 / 3, 29))
  expect_identical(r$accuracy$rank_lower[2], 1)
  one <- hr_report(d, contrasts = matrix(c("b", "a"), 1), B = 1000)
  expect_equal(one$contrasts$estimate, -ab$estimate)
  expect_error(hr_report(d, contrasts = matrix(c("a", "z"), 1)), class = "gr_bad_setting")
  expect_error(hr_report(d, contrasts = matrix(c("a", "a"), 1)), class = "gr_bad_setting")
  # Small samples: the same cluster-robust t intervals, with t quantiles on
  # 7 degrees of freedom, and a note that the bootstrap parts are rough.
  small <- hr_report(d[d$cluster %in% paste0("c", 1:8), ], B = 200)
  expect_identical(small$method, "cluster_t")
  expect_true(all(small$contrasts$method == "cluster_robust_t"))
  expect_identical(small$simultaneous$method[1], "max_t_cluster_robust")
  expect_gt(small$simultaneous$critical[1], stats::qt(0.975, 7))
  expect_true(any(grepl("Cost, pass\\^k, frontier share and rank intervals", small$notes)))
})

test_that("small-sample differences use the cluster-robust t interval on C - 1 df", {
  # Arm b differs from a on one item of each of 6 clusters, by a different
  # number of runs, so the cluster differences vary.
  a <- counts_bench(rep(c(5, 3), 6), rep(2, 6), arm = "a")
  b <- counts_bench(c(4, 3, 3, 3, 5, 3, 2, 3, 5, 3, 1, 3), rep(2, 6), arm = "b")
  r <- hr_report(rbind(a, b), B = 500)
  expect_identical(r$contrasts$method, "cluster_robust_t")
  # Mean item differences a - b per cluster: 0.1, 0.2, 0, 0.3, 0, 0.4, with
  # mean 1 / 6. Equal clusters make the linearised variance s^2 / C:
  # s^2 = 0.13333 / 5, so se = sqrt(0.026667 / 6) = 1 / 15, and the
  # interval is 1 / 6 -/+ qt(0.975, 5) / 15 = 1 / 6 -/+ 2.570582 / 15.
  expect_equal(r$contrasts$estimate, 1 / 6)
  expect_equal(r$contrasts$lower, -0.00470545570908759, tolerance = 1e-10)
  expect_equal(r$contrasts$upper, 0.338038789042421, tolerance = 1e-10)
  expect_false(is.null(r$simultaneous$critical))
  # Identical arms: every cluster gives the same difference, the cluster
  # variance is 0, and the interval takes items as pairs: Tango's interval
  # with q10 = q01 = mean(p (1 - p)) = 0.12 over items at 1 and 0.6, on
  # n = 12 (qnorm(0.975) / qt(0.975, 5))^2 = 6.97612990768 pairs, its lower
  # end found by uniroot() on a separate implementation of the score.
  same <- b
  same$correct <- a$correct
  rr <- hr_report(rbind(a, same), B = 200)
  expect_identical(rr$contrasts$method, "tango_items")
  expect_equal(rr$contrasts$lower, -0.425519164271732, tolerance = 1e-9)
  expect_equal(rr$contrasts$upper, 0.425519164271732, tolerance = 1e-9)
  expect_true(any(grepl("cluster variance 0", rr$notes)))
  # The simultaneous interval of the one pair is Bonferroni over one pair,
  # the same interval.
  expect_identical(rr$simultaneous$method, "tango_items")
  expect_equal(rr$simultaneous$lower, rr$contrasts$lower)
})

test_that("difference intervals stay within [-1, 1] with two clusters", {
  # Two clusters of two items. Arm a is right on every run; b only in the
  # second cluster, c only on the last item. a - b is 1 per item in the
  # first cluster and 0 in the second: estimate 0.5, cluster sums 2 and 0,
  # se = sqrt(2 / 1 x (1^2 + 1^2)) / 4 = 0.5, and with qt(0.975, 1) =
  # 12.7062047361747 the t interval 0.5 -/+ 6.35 reaches far past -1 and 1.
  d <- rbind(counts_bench(c(5, 5, 5, 5), c(2, 2), arm = "a"),
             counts_bench(c(0, 0, 5, 5), c(2, 2), arm = "b"),
             counts_bench(c(0, 0, 0, 5), c(2, 2), arm = "c"))
  r <- hr_report(d, contrasts = c("a", "b"), B = 200)
  expect_identical(r$contrasts$method, "cluster_robust_t")
  expect_equal(r$contrasts$estimate, 0.5)
  expect_true(0.5 + stats::qt(0.975, 1) * 0.5 > 1)
  expect_identical(c(r$contrasts$lower, r$contrasts$upper), c(-1, 1))
  s <- r$simultaneous
  expect_identical(s$method, rep("max_t_cluster_robust", 3))
  expect_true(all(s$lower >= -1 & s$upper <= 1))
  expect_true(all(s$lower <= s$estimate & s$estimate <= s$upper))
  expect_identical(s$lower[s$arm1 == "a" & s$arm2 == "b"], -1)
  expect_identical(s$upper[s$arm1 == "a" & s$arm2 == "b"], 1)
})

test_that("the exact interval counts items, not runs, as trials", {
  d <- counts_bench(rep(5, 50), rep(5, 10))
  ex <- hr_report(d, method = "exact")
  expect_identical(ex$accuracy$upper, 1)
  # binom.test(50, 50)$conf.int[1]: 50 independent items, all correct.
  expect_lte(ex$accuracy$lower, 0.9288783)
  expect_gt(ex$accuracy$lower, 0.5)
})

test_that("an interval at accuracy 0 or 1 is one-sided from the boundary", {
  wrong <- hr_report(counts_bench(rep(0, 12), rep(2, 6)), B = 200, method = "bayes")
  expect_identical(wrong$accuracy$method, "beta_binomial_bayes")
  expect_identical(wrong$accuracy$lower, 0)
  expect_true(wrong$accuracy$upper > 0 && wrong$accuracy$upper < 0.5)
  right <- hr_report(counts_bench(rep(5, 12), rep(2, 6)), B = 200, method = "bayes")
  expect_identical(right$accuracy$upper, 1)
  expect_true(right$accuracy$lower > 0.5 && right$accuracy$lower < 1)
  # The default t interval is not defined there; Korn and Graubard's is
  # given, one-sided at 95%: 12 items in 6 clusters with variance 0 give
  # n_eff = 12 (qt(0.95, 11) / qt(0.95, 5))^2 = 9.53163, and the bound is
  # qbeta(0.95, 1, n_eff) = 1 - 0.05^(1 / n_eff).
  kw <- hr_report(counts_bench(rep(0, 12), rep(2, 6)), B = 200)
  expect_identical(kw$accuracy$method, "korn_graubard_clopper_pearson")
  expect_identical(kw$accuracy$lower, 0)
  expect_equal(kw$accuracy$upper, 0.269695531086814, tolerance = 1e-10)
  expect_true(any(grepl("where the t interval is not defined", kw$notes)))
  kr <- hr_report(counts_bench(rep(5, 12), rep(2, 6)), B = 200)
  expect_identical(kr$accuracy$upper, 1)
  expect_equal(kr$accuracy$lower, 1 - 0.269695531086814, tolerance = 1e-10)
  kb <- hr_report(counts_bench(rep(5, 12), rep(2, 6)), B = 200, method = "bootstrap")
  expect_identical(kb$accuracy$method, "korn_graubard_clopper_pearson")
  expect_equal(kb$accuracy$lower, 1 - 0.269695531086814, tolerance = 1e-10)
})

test_that("an item scored on some runs but not all is refused", {
  d <- counts_bench(rep(c(5, 3), 6), rep(2, 6))
  d$correct[1] <- NA
  expect_error(hr_report(d, k = c(1, 5)), "some runs but not all", class = "hr_bad_bench")
})

test_that("dev rows and unlabelled items are left out; unpaired designs are refused", {
  d <- counts_bench(c(5, 3, 0, 2, 4, 4), c(2, 2, 2))
  d$reportable <- d$cluster != "c03"
  d$correct[d$item == "q04"] <- NA
  r <- hr_report(d, B = 200)
  expect_identical(r$n_items, 3L)
  expect_true(any(grepl("not reportable", r$notes)))
  expect_true(any(grepl("no label", r$notes)))
  d$reportable <- FALSE
  expect_error(hr_report(d), class = "hr_bad_bench")
  e <- rbind(counts_bench(c(5, 3), 2, "a"), counts_bench(c(5), 1, "b"))
  expect_error(hr_report(e), class = "hr_bad_bench")
  expect_error(hr_report(d[, c("item", "arm")]), class = "hr_bad_bench")
  expect_error(hr_report(counts_bench(5, 1), B = 10), class = "gr_bad_setting")
})

test_that("hr_report reads an hr_benchmark result, prints and writes JSON", {
  ref <- hr_reference(
    items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
    labels = c("Paris", "Lima", "N'Djamena", "Suva"),
    cluster = c("a", "a", "b", "b"), split = c("test", "test", "test", "dev"))
  capitals <- c(France = "Paris", Peru = "Lima", Chad = "Ndjamena", Fiji = "Suva")
  cl <- gr_mock_client(function(messages, params) {
    capitals[[sub("Capital of ", "", messages[[1]]$content)]]
  })
  ask <- hr_arm("ask", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
  bench <- hr_benchmark(ask, ref, runs = 5, client = cl, split = c("test", "dev"))
  set.seed(3)
  before <- .Random.seed
  r <- hr_report(bench, B = 200)
  expect_identical(.Random.seed, before)
  expect_s3_class(r, "hr_bench_report")
  expect_identical(r$n_items, 3L)
  expect_equal(r$accuracy$estimate, 2 / 3)
  expect_identical(r$failures$wrong, 5L)
  expect_output(print(r), "<hr_bench_report> 1 arm\\(s\\), 3 item\\(s\\) in 2 cluster\\(s\\)")
  expect_output(print(r), "not ranked")
  js <- jsonlite::fromJSON(as_json(r))
  expect_identical(js$method, "cluster_t")
  expect_identical(js$arms, "ask")
  expect_equal(js$accuracy$estimate, 2 / 3)
  expect_true(is.list(js$variance))
})

test_that("a table without failure kinds counts its wrong runs as wrong", {
  r <- hr_report(counts_bench(c(5, 3, 0), c(2, 1)), B = 200)
  expect_identical(r$failures$wrong, 7L)
})

test_that("a contrast written against benchmark order prints its simultaneous interval", {
  set.seed(2)
  grid <- expand.grid(run = 1:5, arm = c("short", "long", "mid"), item = 1:36,
                      stringsAsFactors = FALSE)
  grid$cluster <- paste0("doc", (grid$item - 1) %/% 3 + 1)
  grid$item <- paste0("q", grid$item)
  grid$correct <- stats::runif(nrow(grid)) < ifelse(grid$arm == "long", 0.8, 0.7)
  r <- hr_report(grid, contrasts = c("long", "short"), B = 500)
  # The simultaneous rows hold short - long only: estimate -0.2111,
  # interval [-0.35396, -0.06826]. long - short is its negation,
  # [-(-0.06826), -(-0.35396)] = [0.068, 0.354] at 3 decimals. It used to
  # print "-".
  s <- r$simultaneous[r$simultaneous$arm1 == "short" & r$simultaneous$arm2 == "long", ]
  expect_equal(c(s$lower, s$upper), c(-0.35396144811, -0.06826077412), tolerance = 1e-9)
  expect_output(print(r), "long - short 0.211      [0.094, 0.328] [0.068, 0.354]",
                fixed = TRUE)
})

test_that("max-t with a zero-variance pair leaves room for its Bonferroni share", {
  # 12 clusters of 3 items. Arm a is right on items 1 and 2 of each cluster
  # and arm b on item 1, so a - b is 1/3 in every cluster (cluster variance
  # 0) and takes Tango's interval at (1 - 0.95) / (2 x 3) per tail. Arm c is
  # random, so a - c and b - c take the max-t interval, at level
  # 1 - 0.05 x 2 / 3 = 0.96667 so that the family stays at 0.95.
  # mvtnorm::qmvt(1 - 0.05 * 2 / 3, tail = "both.tails", df = 11) on the
  # correlation of those two differences gives 2.4317; at 0.95 it gives
  # 2.2014, about the 2.1957 used before. 100000 draws carry a Monte Carlo
  # error of about 0.01.
  set.seed(5)
  C <- 12; m <- 3; I <- C * m
  g <- expand.grid(run = 1:5, arm = c("a", "b", "c"), item = 1:I, stringsAsFactors = FALSE)
  g$cluster <- paste0("doc", (g$item - 1) %/% m + 1)
  pos <- (g$item - 1) %% m + 1
  g$item <- paste0("q", g$item)
  g$correct <- ifelse(g$arm == "a", pos %in% 1:2,
                      ifelse(g$arm == "b", pos == 1, stats::runif(nrow(g)) < 0.6))
  s <- hr_report(g, B = 200)$simultaneous
  expect_identical(s$method, c("tango_items", "max_t_cluster_robust", "max_t_cluster_robust"))
  expect_true(is.na(s$critical[1]))
  expect_equal(s$critical[2:3], c(2.4317, 2.4317), tolerance = 0.02 / 2.43)
  expect_identical(s$critical[2], s$critical[3])
})
