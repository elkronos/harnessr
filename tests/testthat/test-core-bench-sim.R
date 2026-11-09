# test-core-bench-sim.R: the simulations behind dev/sim-coverage.R and
# dev/sim-power.R. The nightly job runs 2000 replicates; these run a few, to
# keep the functions working and their output in the shape the scripts read.

test_that("sim_design fixes the true values and the two regimes", {
  large <- sim_design("large")
  small <- sim_design("small")
  expect_s3_class(large, "hr_sim_design")
  expect_equal(sum(large$sizes), 386L)
  expect_equal(length(large$sizes), 40L)
  expect_equal(sum(small$sizes), 50L)
  expect_equal(length(small$sizes), 10L)
  expect_equal(small$runs, 5L)
  expect_equal(sum(small$var), 1)
  expect_equal(small$icc_doc, 0.2)
  expect_equal(small$run_share, 0.2)
  expect_equal(unname(small$truth), c(0.70, 0.75, 0.05))
  expect_equal(names(small$truth), c("ref", "new", "diff"))
  # Components given on another scale are rescaled to sum to 1.
  d <- sim_design("small", var_doc = 2, var_doc_arm = 0, var_item = 2, var_item_arm = 0,
                  var_run = 4)
  expect_equal(unname(d$var), c(0.25, 0, 0.25, 0, 0.5))
  expect_error(sim_design("small", accuracy = c(0.7, 0.8)), class = "gr_bad_setting")
  expect_error(sim_design("small", var_run = -1), class = "gr_bad_setting")
})

test_that("sim_corpus gives a paired benchmark hr_report reads", {
  d <- sim_design("small")
  b <- with_private_rng(3, sim_corpus(d))
  expect_named(b, c("cluster", "item", "arm", "run", "correct"))
  expect_equal(nrow(b), 50L * 5L * 2L)
  expect_true(is.logical(b$correct))
  expect_equal(sort(unique(b$arm)), c("new", "ref"))
  expect_equal(length(unique(b$cluster)), 10L)
  # Each item sits in one cluster, with every run of both arms.
  expect_true(all(tapply(b$cluster, b$item, function(v) length(unique(v))) == 1L))
  expect_true(all(table(b$item) == 10L))
})

test_that("sim_coverage reports the small regime with its gate and exact rows", {
  d <- sim_design("small")
  x <- sim_coverage(d, reps = 2, seed = 11, B = 200)
  expect_named(x, c("rep", "quantity", "arm", "method", "gate", "truth", "estimate",
                    "lower", "upper", "covered", "below", "above"))
  expect_equal(nrow(x), 10L)
  expect_equal(sort(unique(x$rep)), 1:2)
  g <- x[x$gate, ]
  expect_equal(nrow(g), 6L)
  expect_equal(sort(unique(g$method)), c("cluster_robust_t", "logit_cluster_robust_t"))
  expect_true(all(g$method[g$quantity == "difference"] == "cluster_robust_t"))
  expect_true(all(x$method[!x$gate] == "korn_graubard_clopper_pearson"))
  expect_equal(x$truth[x$quantity == "difference"], c(0.05, 0.05))
  expect_true(all(x$lower <= x$upper))
  expect_equal(x$covered, x$lower <= x$truth & x$truth <= x$upper)
  expect_true(all(!(x$below & x$above)))

  s <- sim_coverage_summary(x)
  expect_named(s, c("quantity", "arm", "method", "gate", "reps", "coverage", "mc_lower",
                    "mc_upper", "below", "above", "width", "bias", "pass"))
  expect_equal(nrow(s), 5L)
  expect_true(all(s$reps == 2L))
  expect_true(is.logical(s$pass))
})

test_that("sim_coverage uses the bootstrap in the large regime", {
  x <- sim_coverage(sim_design("large"), reps = 1, seed = 5, B = 200)
  expect_equal(nrow(x), 3L)
  expect_true(all(x$gate))
  expect_identical(x$method, c("studentised_cluster_bootstrap", "studentised_cluster_bootstrap",
                               "cluster_robust_t"))
})

test_that("simulation replicates do not depend on how the run is split", {
  d <- sim_design("small")
  both <- sim_coverage(d, reps = 2, seed = 7, B = 200)
  second <- sim_coverage(d, reps = 1, seed = 7, B = 200, first = 2)
  expect_equal(both[both$rep == 2, ], second, ignore_attr = TRUE)

  p <- sim_power_design(60, 12, icc = 0.2, p_disc = 0.3)
  pb <- sim_power(p, reps = 2, seed = 4)
  ps <- sim_power(p, reps = 1, seed = 4, first = 2)
  expect_equal(pb[2, ], ps, ignore_attr = TRUE)
})

test_that("the simulations leave the caller's random state alone", {
  set.seed(99)
  before <- .Random.seed
  sim_coverage(sim_design("small"), reps = 1, B = 200)
  sim_power(sim_power_design(60, 12, icc = 0.2, p_disc = 0.3), reps = 1)
  expect_identical(.Random.seed, before)
})

test_that("sim_coverage_summary applies the pass rule to the Wilson interval", {
  mk <- function(hit, n) {
    data.frame(rep = seq_len(n), quantity = "accuracy", arm = "ref", method = "m",
               gate = TRUE, truth = 0.5, estimate = 0.5, lower = 0.4, upper = 0.6,
               covered = seq_len(n) <= hit, below = FALSE, above = seq_len(n) > hit,
               stringsAsFactors = FALSE)
  }
  # 95 of 100: the interval holds 0.95 but its lower end is below 0.93.
  s <- sim_coverage_summary(mk(95, 100))
  expect_equal(s$coverage, 0.95)
  expect_equal(s$mc_lower, 0.8882495308, tolerance = 1e-9)
  expect_equal(s$mc_upper, 0.9784563208, tolerance = 1e-9)
  expect_false(s$pass)
  expect_equal(s$above, 0.05)
  # 1900 of 2000 passes.
  s <- sim_coverage_summary(mk(1900, 2000))
  expect_equal(s$mc_lower, 0.9395558911, tolerance = 1e-9)
  expect_equal(s$mc_upper, 0.9587187664, tolerance = 1e-9)
  expect_true(s$pass)
  # 1980 of 2000 overcovers: the interval leaves 0.95 out.
  expect_false(sim_coverage_summary(mk(1980, 2000))$pass)
})

test_that("sim_power_design builds the sizes hr_mdd sees", {
  d <- sim_power_design(480, 80, icc = 0.2, p_disc = 0.2)
  expect_s3_class(d, "hr_sim_power_design")
  expect_equal(d$sizes, rep(6L, 80))
  expect_equal(d$cv, 0)
  # (qt(0.975, 79) + qt(0.8, 79)) * sqrt(0.2 / 240).
  expect_equal(d$mdd$mdd, 0.081886888316, tolerance = 1e-9)
  u <- sim_power_design(400, 40, icc = 0.1, p_disc = 0.3, cv = 0.5)
  expect_equal(sum(u$sizes), 400L)
  expect_true(all(u$sizes >= 1L))
  expect_equal(u$cv, 0.4760952286, tolerance = 1e-9)
  expect_equal(u$mdd$cv, u$cv)
  # (qt(0.975, 39) + qt(0.8, 39)) * sqrt(0.3 x DE / 400), with
  # DE = 1 + ((cv^2 + 1) x 10 - 1) x 0.1 for the cv made.
  expect_equal(u$mdd$mdd, 0.114765295444, tolerance = 1e-9)
  expect_equal(sim_power_design(10, 3, icc = 0, p_disc = 0.5)$sizes, c(4L, 3L, 3L))
  expect_error(sim_power_design(10, 3, icc = 0, p_disc = 0.5, cv = NA), class = "gr_bad_setting")
  expect_error(sim_power_design(10, 3, icc = 0, p_disc = 0.5, cv = -0.2),
               class = "gr_bad_setting")
})

test_that("sim_power's bound is the report's non-inferiority bound on the same corpus", {
  d <- sim_power_design(60, 12, icc = 0.2, p_disc = 0.3)
  x <- sim_power(d, reps = 2, seed = 5)
  ref <- hr_reference(sprintf("q%03d", 1:60), labels = rep("yes", 60),
                      cluster = sprintf("doc%02d", rep(seq_along(d$sizes), d$sizes)),
                      split = "test")
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.1,
                                                confirmatory = FALSE, cost_test = FALSE),
                               d$mdd)
  for (r in 1:2) {
    dif <- harnessr:::sim_power_draw(d, 5 + r - 1)
    # d = 1: only "new" right; d = -1: only "ref" right; d = 0: both right.
    g <- expand.grid(run = 1:5, i = 1:60)
    one <- function(arm, v) {
      data.frame(cluster = ref$cluster[g$i], item = ref$ids[g$i], arm = arm, run = g$run,
                 split = "test", reportable = TRUE, correct = v[g$i], usd = 0.001,
                 stringsAsFactors = FALSE)
    }
    b <- rbind(one("new", dif >= 0), one("ref", dif <= 0))
    attr(b, "reference_hash") <- ref$hash
    rep_r <- hr_report(b, contrasts = c("new", "ref"), registration = reg, B = 100)
    expect_equal(rep_r$ni$level, 0.025)
    expect_equal(rep_r$ni$estimate, x$estimate[r])
    expect_equal(rep_r$ni$lower, x$lower[r])
  }
})

test_that("sim_power returns one lower bound per replicate", {
  d <- sim_power_design(60, 12, icc = 0.2, p_disc = 0.3, n_contrasts = 3)
  x <- sim_power(d, reps = 3, seed = 2)
  expect_named(x, c("rep", "estimate", "lower", "lower_normal", "p_disc_seen"))
  expect_equal(x$rep, 1:3)
  expect_true(all(x$lower <= x$estimate))
  expect_true(all(x$lower_normal <= x$estimate))
  # The t quantile on C - 1 = 11 degrees of freedom is above the normal one,
  # at the Holm worst-case level 0.025 / 3.
  expect_true(all(x$lower <= x$lower_normal))
  expect_equal((x$estimate - x$lower) / (x$estimate - x$lower_normal),
               rep(stats::qt(1 - 0.025 / 3, 11) / stats::qnorm(1 - 0.025 / 3), 3))
  expect_true(all(x$p_disc_seen >= 0 & x$p_disc_seen <= 1))
  # With no clustering the draws still run.
  expect_equal(nrow(sim_power(sim_power_design(60, 12, icc = 0, p_disc = 0.3), reps = 2)), 2L)
})

test_that("sim_power_summary reads the MDD off the quantile of the bounds", {
  d <- sim_power_design(480, 80, icc = 0.2, p_disc = 0.2)
  x <- data.frame(lower = -(1:100) / 1000, lower_normal = -(1:100) / 1000)
  s <- sim_power_summary(x, d)
  expect_equal(s$reps, 100L)
  expect_equal(s$mdd_formula, 0.081886888316, tolerance = 1e-9)
  # The 20% quantile of -0.100, ..., -0.001 is -0.0802.
  expect_equal(s$mdd_sim, 0.0802)
  # Ranks k_lo and k_hi + 1 of the sorted bounds: the 12th and the 29th.
  expect_equal(s$mdd_sim_lower, 0.072)
  expect_equal(s$mdd_sim_upper, 0.089)
  # -0.001, ..., -0.081 clear the formula's MDD of 8.19 points: 81 of 100.
  expect_equal(s$power_at_mdd, 0.81)
  expect_equal(s$power_check, "")
  expect_true(s$pass)
  # Bounds spaced so that 1500 of 2000 clear the formula's MDD: b[1500] is
  # above -MDD and b[1501] below it, neither within rounding error of it.
  # Power 75%, simulated MDD half a point above the formula. Flagged, still
  # a pass.
  b <- -(1:2000) * d$mdd$mdd / 1500.5
  short <- sim_power_summary(data.frame(lower = b, lower_normal = b), d)
  expect_equal(sum(b > -d$mdd$mdd), 1500L)
  expect_equal(short$power_at_mdd, 0.75)
  expect_lt(short$difference, 0.01)
  expect_true(short$pass)
  expect_equal(short$power_check, "below target")
  expect_false(sim_power_summary(transform(x, lower = lower - 0.02), d)$pass)
})
