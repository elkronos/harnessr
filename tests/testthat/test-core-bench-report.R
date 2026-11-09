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
  d <- rbind(counts_bench(ka12, nper12, "a"), counts_bench(kb12, nper12, "b"))
  r <- hr_report(d, method = "bootstrap", B = 999, seed = 7)
  # Reference values from boot 1.3: boot() over the 12 cluster sums with
  # set.seed(7) and R = 999, then boot.ci(type = "bca") with L the cluster
  # jackknife influence values (C - 1) * (mean(t_jack) - t_jack).
  expect_equal(r$accuracy$lower, c(0.593371176004613, 0.764790555665983), tolerance = 1e-10)
  expect_equal(r$accuracy$upper, c(0.789231622024109, 0.888082761058241), tolerance = 1e-10)
  expect_equal(r$contrasts$lower, -0.1716115464907494, tolerance = 1e-10)
  expect_equal(r$contrasts$upper, -0.0838355270689133, tolerance = 1e-10)
  expect_equal(r$accuracy$estimate, c(127, 150) / 180)
  expect_identical(r$accuracy$method, rep("bca_cluster_bootstrap", 2))
  expect_identical(r$contrasts$method, "bca_cluster_bootstrap")
  # The resamples are the ones boot() draws: same clusters, same order.
  cnt <- harnessr:::with_private_rng(7, harnessr:::cluster_counts(12L, 999L))
  expect_identical(dim(cnt), c(999L, 12L))
  expect_true(all(rowSums(cnt) == 12))
  set.seed(7)
  idx <- matrix(sample.int(12L, 12L * 999L, replace = TRUE), 999L)
  expect_equal(as.vector(cnt[5, ]), tabulate(idx[5, ], 12L))
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

test_that("a small benchmark uses the Bayesian model, never a Wald interval", {
  set.seed(5)
  d <- sim_bench(10, 5)
  r <- hr_report(d)
  expect_identical(r$method, "bayes")
  expect_identical(r$accuracy$method, "beta_binomial_bayes")
  expect_match(r$method_reason, "fall short of 300 items and 30 clusters")
  p <- r$accuracy$estimate
  for (n in c(50, 250)) {
    wald <- p + c(-1, 1) * stats::qnorm(0.975) * sqrt(p * (1 - p) / n)
    expect_false(isTRUE(all.equal(c(r$accuracy$lower, r$accuracy$upper), wald,
                                  tolerance = 1e-3)))
  }
  expect_true(r$accuracy$lower >= 0 && r$accuracy$upper <= 1)
  expect_false(is.null(r$bayes))
  # Even with 300 items, too few clusters keep the Bayesian model.
  set.seed(6)
  expect_identical(hr_report(sim_bench(20, 16))$method, "bayes")
  ex <- hr_report(d, method = "exact")
  expect_identical(ex$accuracy$method, "korn_graubard_clopper_pearson")
  expect_true(ex$accuracy$lower < p && ex$accuracy$upper > p)
  for (m in c("auto", "bayes", "exact", "bootstrap")) {
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
  hit_bayes <- vapply(seq_len(100), function(i) {
    r <- hr_report(sim_bench(10, 5), B = 100, seed = i)
    stopifnot(identical(r$method, "bayes"))
    r$accuracy$lower <= 0.7 && r$accuracy$upper >= 0.7
  }, logical(1))
  expect_gte(mean(hit_boot), 0.85)
  expect_lte(mean(hit_boot), 0.99)
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
  expect_identical(s$method[1], "max_t_cluster_bootstrap")
  expect_identical(r$accuracy$rank_lower[2], 1)
  one <- hr_report(d, contrasts = matrix(c("b", "a"), 1), B = 1000)
  expect_equal(one$contrasts$estimate, -ab$estimate)
  expect_error(hr_report(d, contrasts = matrix(c("a", "z"), 1)), class = "gr_bad_setting")
  expect_error(hr_report(d, contrasts = matrix(c("a", "a"), 1)), class = "gr_bad_setting")
  # Small samples: the same cluster bootstrap, never a t or normal interval,
  # with a note that it may undercover.
  small <- hr_report(d[d$cluster %in% paste0("c", 1:8), ], B = 200)
  expect_identical(small$method, "bayes")
  expect_true(all(grepl("cluster_bootstrap$", small$contrasts$method)))
  expect_identical(small$simultaneous$method[1], "max_t_cluster_bootstrap")
  expect_true(any(grepl("Paired differences, simultaneous intervals", small$notes)))
})

test_that("small-sample differences come from the bootstrap, not a t interval", {
  # Arm b differs from a on one item of each of 6 clusters, by a different
  # number of runs, so the cluster differences vary.
  a <- counts_bench(rep(c(5, 3), 6), rep(2, 6), arm = "a")
  b <- counts_bench(c(4, 3, 3, 3, 5, 3, 2, 3, 5, 3, 1, 3), rep(2, 6), arm = "b")
  r <- hr_report(rbind(a, b), B = 500)
  expect_identical(r$contrasts$method, "bca_cluster_bootstrap")
  expect_true(r$contrasts$lower < r$contrasts$upper)
  expect_false(is.null(r$simultaneous$critical))
  # Identical arms: the resamples have no spread, and the report says so.
  same <- b
  same$correct <- a$correct
  rr <- hr_report(rbind(a, same), B = 200)
  expect_identical(rr$contrasts$method, "bca_cluster_bootstrap")
  expect_true(any(grepl("zero width", rr$notes)))
})

test_that("the exact interval counts items, not runs, as trials", {
  d <- counts_bench(rep(5, 50), rep(5, 10))
  ex <- hr_report(d, method = "exact")
  expect_identical(ex$accuracy$upper, 1)
  # binom.test(50, 50)$conf.int[1]: 50 independent items, all correct.
  expect_lte(ex$accuracy$lower, 0.9288783)
  expect_gt(ex$accuracy$lower, 0.5)
})

test_that("a Bayesian interval at accuracy 0 or 1 is one-sided from the boundary", {
  wrong <- hr_report(counts_bench(rep(0, 12), rep(2, 6)), B = 200)
  expect_identical(wrong$accuracy$method, "beta_binomial_bayes")
  expect_identical(wrong$accuracy$lower, 0)
  expect_true(wrong$accuracy$upper > 0 && wrong$accuracy$upper < 0.5)
  right <- hr_report(counts_bench(rep(5, 12), rep(2, 6)), B = 200)
  expect_identical(right$accuracy$upper, 1)
  expect_true(right$accuracy$lower > 0.5 && right$accuracy$lower < 1)
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
  expect_identical(js$method, "bayes")
  expect_identical(js$arms, "ask")
  expect_equal(js$accuracy$estimate, 2 / 3)
  expect_true(is.list(js$variance))
})

test_that("a table without failure kinds counts its wrong runs as wrong", {
  r <- hr_report(counts_bench(c(5, 3, 0), c(2, 1)), B = 200)
  expect_identical(r$failures$wrong, 7L)
})
