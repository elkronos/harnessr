# test-core-bench-ni.R: the minimum detectable difference, registered
# non-inferiority contrasts and their verdicts in hr_report().

# A test-split reference of n_clusters clusters of `per` items.
ni_reference <- function(n_clusters, per) {
  n <- n_clusters * per
  hr_reference(sprintf("q%04d", seq_len(n)), labels = rep("yes", n),
               cluster = rep(sprintf("doc%03d", seq_len(n_clusters)), each = per),
               split = "test")
}

# Rows for a reference arm "ref" and the arms in `shift` (named by arm) on
# the reference's items: "ref" is right on item i with probability p_i,
# which varies by cluster and item, and arm a with p_i + shift[a]. Dollars
# per run are drawn around usd_new and usd_ref. The table carries the
# reference hash, as an hr_benchmark() does.
ni_bench <- function(ref, shift, runs = 5, usd_new = 0.001, usd_ref = 0.002) {
  if (is.null(names(shift))) names(shift) <- "new"
  ids <- ref$ids
  cl <- ref$cluster
  ce <- stats::rnorm(length(unique(cl)), 0, 0.08)[match(cl, unique(cl))]
  p <- pmin(pmax(0.75 + ce + stats::rnorm(length(ids), 0, 0.1), 0.4), 0.95)
  one <- function(arm, prob, usd) {
    g <- expand.grid(run = seq_len(runs), i = seq_along(ids))
    data.frame(cluster = cl[g$i], item = ids[g$i], arm = arm, run = g$run,
               split = "test", reportable = TRUE,
               correct = stats::runif(nrow(g)) < prob[g$i],
               usd = usd * stats::runif(nrow(g), 0.8, 1.2), stringsAsFactors = FALSE)
  }
  d <- do.call(rbind, c(lapply(names(shift), function(a) one(a, p + shift[[a]], usd_new)),
                        list(one("ref", p, usd_ref))))
  attr(d, "reference_hash") <- ref$hash
  d
}

test_that("hr_mdd and hr_n_needed reproduce the worked numbers of the QA design", {
  # 480 scored questions in 80 documents, m = 6, ICC_D 0.2, p_disc 0.20.
  m <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
  expect_s3_class(m, "hr_mdd")
  expect_equal(m$de, 2)
  expect_equal(m$n_eff, 240)
  expect_equal(m$m, 6)
  # (qt(0.975, 79) + qt(0.8, 79)) * sqrt(0.2 / 240) = (1.99045 + 0.84619) *
  # 0.0288675: about 8.2 points before Holm.
  expect_equal(m$mdd, 0.0818869, tolerance = 1e-5)
  expect_equal(m$df, 79)
  # (qt(1 - 0.025 / 9, 79) + qt(0.8, 79)) * sqrt(0.2 / 240): about 10.7
  # points after Holm over 9 contrasts.
  m9 <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(m9$alpha_adj, 0.025 / 9)
  expect_equal(m9$mdd, 0.1067334, tolerance = 1e-5)
  # Without the Holm adjustment the family size does not matter.
  expect_equal(hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9,
                      holm = FALSE)$mdd, m$mdd)

  # The item counts below solve n = (qt(1 - alpha', n / m - 1) +
  # qt(0.8, n / m - 1))^2 x p_disc x DE / gap^2, found once by bisection on n.
  # 8 points needs about 251 effective items.
  n8 <- hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2)
  expect_equal(n8$n_eff, 251.1714, tolerance = 1e-4)
  # After Holm over nine contrasts about 419 effective items, 838 questions
  # and 140 documents of 6.
  n9 <- hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(n9$n_eff, 418.8948, tolerance = 1e-4)
  expect_equal(n9$n_items, 837.7896, tolerance = 1e-4)
  expect_equal(n9$n_clusters, 139.6316, tolerance = 1e-4)
  # Holm over six contrasts gives about 382 (independent items, df n - 1).
  expect_equal(hr_n_needed(0.08, p_disc = 0.2, n_contrasts = 6)$n_eff, 381.6507,
               tolerance = 1e-4)
  # 3 points needs about 1,746 effective items.
  expect_equal(hr_n_needed(0.03, p_disc = 0.2)$n_eff, 1746.146, tolerance = 1e-3)
  # A true difference of -2 points against an 8-point margin needs about 438.
  expect_equal(hr_n_needed(0.08, p_disc = 0.2, true_diff = -0.02)$n_eff, 438.0018,
               tolerance = 1e-4)
  # The two are inverses of each other.
  m816 <- hr_mdd(816, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(hr_n_needed(m816$mdd, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)$n_items,
               816)
  expect_true(is.na(hr_n_needed(0.08, p_disc = 0.2)$n_clusters))
  expect_output(print(n9), "419 effective items; DE 2, so 838 items in 140 clusters of 6")
  expect_output(print(m9), "10.7 points")
})

test_that("unequal cluster sizes raise m to (cv^2 + 1) x m", {
  m <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, cv = 0.5)
  expect_equal(m$m_adj, 7.5)
  expect_equal(m$de, 1 + 6.5 * 0.2)
  expect_equal(m$n_eff, 480 / 2.3)
})

test_that("hr_mdd asks for the design values it cannot assume", {
  expect_error(hr_mdd(480, n_clusters = 80, p_disc = 0.2), class = "gr_bad_setting")
  expect_error(hr_mdd(480, n_clusters = 80, icc = 0.2), class = "gr_bad_setting")
  expect_error(hr_mdd(480, n_clusters = 80, m = 5, icc = 0.2, p_disc = 0.2),
               class = "gr_bad_setting")
  expect_error(hr_mdd(480, icc = 1, p_disc = 0.2), class = "gr_bad_setting")
  # Items and clusters are counts.
  expect_error(hr_mdd(480, n_clusters = 79.5, icc = 0.2, p_disc = 0.2),
               class = "gr_bad_setting")
  expect_error(hr_mdd(480.5, p_disc = 0.2), class = "gr_bad_setting")
  # The t quantiles need more than one cluster (C - 1 degrees of freedom).
  expect_error(hr_mdd(6, n_clusters = 1, icc = 0.2, p_disc = 0.2), class = "gr_bad_setting")
  expect_error(hr_mdd(1, p_disc = 0.2), class = "gr_bad_setting")
  expect_error(hr_n_needed(0.08, p_disc = 0.2, true_diff = -0.1), class = "gr_bad_setting")
  # Independent items need no ICC; each item is its own cluster, so the t
  # quantiles have 239 degrees of freedom.
  expect_equal(hr_mdd(240, p_disc = 0.2)$mdd,
               (stats::qt(0.975, 239) + stats::qt(0.8, 239)) * sqrt(0.2 / 240))
})

test_that("a confirmatory margin below the design MDD after Holm is refused", {
  ref <- ni_reference(80, 6)
  design <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
  # 8 points is just under the 8.2-point MDD of this design.
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.08), design),
               class = "hr_margin_below_mdd")
  # 10 points clears it for one contrast, and for three (9.5 points after
  # Holm), but not for nine (10.7 points).
  expect_s3_class(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.10), design),
                  "hr_contrast_registration")
  three <- lapply(c("a", "c", "d"), function(x) hr_contrast(x, "b", margin = 0.10))
  reg3 <- hr_register_contrasts(ref, three, design)
  # (qt(1 - 0.025 / 3, 79) + qt(0.8, 79)) * sqrt(0.2 / 240) = 0.09504.
  expect_equal(reg3$mdd$mdd, 0.0950, tolerance = 1e-3)
  nine <- lapply(letters[3:11], function(x) hr_contrast(x, "b", margin = 0.10))
  err <- tryCatch(hr_register_contrasts(ref, nine, design), error = function(e) e)
  expect_s3_class(err, "hr_margin_below_mdd")
  expect_match(conditionMessage(err), "10.7 points")
  # A design given at lower power is still checked at 80%.
  weak <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, power = 0.5)
  expect_lt(weak$mdd, 0.08)
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.08), weak),
               class = "hr_margin_below_mdd")
  # A design given at a larger alpha is still checked at one-sided 0.025.
  loose <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, alpha = 0.2)
  expect_lt(loose$mdd, 0.06)
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.06), loose),
               class = "hr_margin_below_mdd")
  reg <- hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.10), loose)
  expect_equal(reg$alpha, 0.025)
  expect_equal(reg$mdd$mdd, 0.0818869, tolerance = 1e-5)
})

test_that("a design larger than the reference is refused", {
  ref <- ni_reference(80, 6)
  big <- hr_mdd(100000, m = 6, icc = 0.2, p_disc = 0.2)
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.01), big),
               class = "gr_bad_setting")
  wide <- hr_mdd(480, n_clusters = 160, icc = 0.2, p_disc = 0.2)
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.10), wide),
               class = "gr_bad_setting")
  # Dev items do not count toward the design.
  mixed <- hr_reference(sprintf("q%03d", 1:60), labels = rep("yes", 60),
                        cluster = rep(sprintf("doc%02d", 1:10), each = 6),
                        split = rep(c("dev", "test"), each = 30))
  expect_error(hr_register_contrasts(mixed, hr_contrast("a", "b", margin = 0.5),
                                     hr_mdd(60, n_clusters = 10, icc = 0.1, p_disc = 0.2)),
               class = "gr_bad_setting")
  expect_s3_class(hr_register_contrasts(mixed, hr_contrast("a", "b", margin = 0.5),
                                        hr_mdd(30, n_clusters = 5, icc = 0.1, p_disc = 0.2)),
                  "hr_contrast_registration")
})

test_that("a margin below the MDD can be registered as exploratory", {
  ref <- ni_reference(80, 6)
  design <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, list(
    hr_contrast("a", "b", margin = 0.10),
    hr_contrast("c", "b", margin = 0.03, confirmatory = FALSE)), design)
  expect_identical(reg$contrasts$label, c("confirmatory", "exploratory"))
  expect_identical(reg$n_confirmatory, 1L)
  expect_equal(reg$contrasts$mdd_design, c(design$mdd, design$mdd))
  expect_identical(reg$reference_hash, ref$hash)
  expect_match(reg$hash, "^[0-9a-f]{64}$")
  expect_output(print(reg), "exploratory")
})

test_that("contrasts cannot be registered once scoring has begun", {
  ref <- ni_reference(10, 3)
  harnessr:::reference_lock(ref, "bench-1")
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.2, confirmatory = FALSE),
                                     hr_mdd(30, n_clusters = 10, icc = 0.1, p_disc = 0.2)),
               class = "hr_registration_after_scoring")
  # A reference rebuilt with the same content is refused too.
  ref2 <- ni_reference(10, 3)
  expect_identical(ref2$hash, ref$hash)
  expect_false(isTRUE(ref2$.lock$locked))
  expect_error(hr_register_contrasts(ref2, hr_contrast("a", "b", margin = 0.5),
                                     hr_mdd(30, n_clusters = 10, icc = 0.1, p_disc = 0.2)),
               class = "hr_registration_after_scoring")
})

test_that("hr_contrast checks its arguments", {
  expect_error(hr_contrast("a", "a", 0.1), class = "gr_bad_setting")
  expect_error(hr_contrast("a", "b", 8), class = "gr_bad_setting")
  expect_error(hr_contrast("a", "b"), class = "gr_bad_setting")
  expect_error(hr_contrast("a", "b", 0.1, confirmatory = NA), class = "gr_bad_setting")
  expect_output(print(hr_contrast("a", "b", 0.1)), "margin 10.0 points, confirmatory")
})

test_that("a true difference of 0 passes at a generous margin and -0.15 fails", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  expect_lt(design$mdd, 0.10)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.10), design)

  set.seed(11)
  same <- ni_bench(ref, shift = 0)
  r0 <- hr_report(same, registration = reg, B = 2000)
  expect_true(r0$confirmatory)
  expect_identical(r0$method, "bootstrap")
  ni <- r0$ni
  expect_true(ni$verdict)
  expect_true(ni$accuracy_holds)
  expect_true(ni$cost_holds)
  expect_gt(ni$lower, -0.10)
  expect_lt(ni$cost_upper, 0)
  expect_equal(ni$level, 0.025)
  expect_lte(ni$p_value, 0.025)
  expect_true(ni$tango_agrees)
  # The achieved MDD sits beside the verdict and is the design formula on
  # the linearised standard error.
  expect_gt(ni$mdd_achieved, 0)
  expect_equal(ni$mdd_design, design$mdd)
  expect_output(print(r0), "non-inferior")
  expect_output(print(r0), "mdd_achieved")

  set.seed(12)
  worse <- ni_bench(ref, shift = -0.15)
  r1 <- hr_report(worse, registration = reg, B = 2000)
  expect_false(r1$ni$verdict)
  expect_false(r1$ni$accuracy_holds)
  expect_lt(r1$ni$lower, -0.10)
  expect_gt(r1$ni$p_value, 0.025)
  expect_output(print(r1), "not shown")
  # The report itself is unchanged apart from the added tables.
  plain <- hr_report(worse, B = 2000)
  expect_null(plain$ni)
  expect_equal(plain$contrasts, r1$contrasts)
})

test_that("the non-inferiority bound is the one-sided cluster-robust t bound", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.10,
                                                cost_test = FALSE), design)
  set.seed(11)
  d <- ni_bench(ref, shift = 0)
  r <- hr_report(d, contrasts = c("new", "ref"), registration = reg, B = 200)
  # By hand: item accuracy over runs, the paired item differences summed per
  # cluster (D_c over n_c items), the ratio estimate sum(D_c) / N and
  # SE = sqrt(C / (C - 1) x sum((D_c - n_c x estimate)^2)) / N, with C = 40
  # and N = 400.
  acc <- tapply(d$correct, list(d$item, d$arm), mean)
  dif <- acc[, "new"] - acc[, "ref"]
  cl <- ref$cluster[match(rownames(acc), ref$ids)]
  Dc <- tapply(dif, cl, sum); nc <- tapply(dif, cl, length)
  est <- sum(Dc) / 400
  se <- sqrt(40 / 39 * sum((Dc - nc * est)^2)) / 400
  expect_equal(r$ni$estimate, est)
  expect_equal(r$ni$level, 0.025)
  expect_equal(r$ni$lower, est - stats::qt(0.975, 39) * se)
  # At one-sided 0.025 it is the lower end of the printed 95% interval.
  expect_equal(r$ni$lower, r$contrasts$lower)
  expect_identical(r$contrasts$method, "cluster_robust_t")
  # Without the cost condition the p-value is the t tail at the margin.
  expect_equal(r$ni$p_value, stats::pt((est + 0.10) / se, 39, lower.tail = FALSE),
               tolerance = 1e-6)
  # The achieved MDD is the design formula on the same SE and degrees of
  # freedom.
  expect_equal(r$ni$mdd_achieved, (stats::qt(0.975, 39) + stats::qt(0.8, 39)) * se)
})

test_that("a paired difference with no cluster variance takes items as pairs", {
  ref <- ni_reference(10, 5)
  design <- hr_mdd(50, n_clusters = 10, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.10,
                                                confirmatory = FALSE, cost_test = FALSE),
                               design)
  # "new" is right on every run of every item; "ref" only on the first item
  # of each cluster. Every cluster then has a mean difference of 0.8 per item,
  # so the cluster variance is 0 and the t bound is not defined.
  g <- expand.grid(run = 1:5, i = seq_along(ref$ids))
  first <- !duplicated(ref$cluster)
  one <- function(arm, correct) {
    data.frame(cluster = ref$cluster[g$i], item = ref$ids[g$i], arm = arm, run = g$run,
               split = "test", reportable = TRUE, correct = correct[g$i], usd = 0.001,
               stringsAsFactors = FALSE)
  }
  d <- rbind(one("new", rep(TRUE, 50)), one("ref", first))
  attr(d, "reference_hash") <- ref$hash
  r <- hr_report(d, contrasts = c("new", "ref"), registration = reg, B = 200)
  expect_equal(r$ni$estimate, 0.8)
  # Tango's interval with b = 0.8 n discordant pairs, c = 0, on
  # n = 50 (qnorm(0.975) / qt(0.975, 9))^2 = 37.5336360168 pairs. With c = 0
  # the score equation has closed forms: lower (b - z^2) / (n + z^2), and
  # upper the larger root of (n + z^2) d^2 - (1.6 n + z^2) d + 0.64 n = 0.
  expect_equal(r$ni$lower, 0.632879515940509, tolerance = 1e-9)
  expect_equal(r$contrasts$lower, 0.632879515940509, tolerance = 1e-9)
  expect_equal(r$contrasts$upper, 0.897170450954456, tolerance = 1e-9)
  expect_identical(r$contrasts$method, "tango_items")
  expect_true(r$ni$verdict)
  # No variance is estimated, so there is no achieved MDD.
  expect_true(is.na(r$ni$mdd_achieved))
  expect_true(any(grepl("Tango's score interval with items as pairs", r$notes)))
})

# Four clusters of five items; each arm is right or wrong on an item on every
# run, so items, not runs, carry the information.
zero_var_bench <- function(ref, new_right, ref_right) {
  g <- expand.grid(run = 1:5, i = seq_along(ref$ids))
  one <- function(arm, v) {
    data.frame(cluster = ref$cluster[g$i], item = ref$ids[g$i], arm = arm, run = g$run,
               split = "test", reportable = TRUE, correct = v[g$i], usd = 0.001,
               stringsAsFactors = FALSE)
  }
  d <- rbind(one("new", new_right), one("ref", ref_right))
  attr(d, "reference_hash") <- ref$hash
  d
}

test_that("identical arms with no cluster variance are not declared non-inferior by default", {
  ref <- ni_reference(4, 5)
  design <- hr_mdd(20, n_clusters = 4, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.05,
                                                confirmatory = FALSE, cost_test = FALSE),
                               design)
  set.seed(4)
  truth <- stats::runif(20) < 0.7
  r <- hr_report(zero_var_bench(ref, truth, truth), contrasts = c("new", "ref"),
                 registration = reg, B = 200)
  expect_equal(r$ni$estimate, 0)
  # No discordant item: Tango's lower bound is -z^2 / (n + z^2) on
  # n = 20 (qnorm(0.975) / qt(0.975, 3))^2 pairs.
  expect_equal(r$ni$lower, -0.336164910534051, tolerance = 1e-9)
  expect_false(r$ni$verdict)
  # The p-value is the level a at which z_a^2 / (n(a) + z_a^2) = 0.05, with
  # n(a) = 20 (qnorm(1 - a) / qt(1 - a, 3))^2, solved by uniroot().
  expect_equal(r$ni$p_value, 0.1901995852, tolerance = 1e-7)
  expect_true(is.na(r$ni$mdd_achieved))
  # Tango's cross-check counts the 20 items, not the 100 paired runs.
  expect_equal(r$ni$n_eff, 20)
})

test_that("a constant cluster difference with item-level spread is not known exactly", {
  ref <- ni_reference(4, 5)
  design <- hr_mdd(20, n_clusters = 4, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.25,
                                                confirmatory = FALSE, cost_test = FALSE),
                               design)
  # In every cluster "new" wins two items and loses three: each cluster's mean
  # difference is -0.2, while item differences are +1 or -1.
  r <- hr_report(zero_var_bench(ref, rep(c(TRUE, TRUE, FALSE, FALSE, FALSE), 4),
                                rep(c(FALSE, FALSE, TRUE, TRUE, TRUE), 4)),
                 contrasts = c("new", "ref"), registration = reg, B = 200)
  expect_equal(r$ni$estimate, -0.2)
  # Tango's lower bound for b = 0.4 n, c = 0.6 n on
  # n = 20 (qnorm(0.975) / qt(0.975, 3))^2 = 7.58584575607 pairs, found by
  # uniroot() on a separate implementation of the score.
  expect_equal(r$ni$lower, -0.704814732682492, tolerance = 1e-9)
  expect_equal(r$contrasts$lower, r$ni$lower)
  expect_false(r$ni$verdict)
  expect_false(any(grepl("the verdict follows the bootstrap", r$notes)))
})

test_that("a Tango disagreement is noted against the t bound the verdict follows", {
  ref <- ni_reference(4, 5)
  design <- hr_mdd(20, n_clusters = 4, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.4,
                                                confirmatory = FALSE, cost_test = FALSE),
                               design)
  # "new" wins items 1 and 2 of each cluster and loses 3 to 5, except item 3
  # of the first cluster, where both are right. Cluster sums of item
  # differences 0, -1, -1, -1: estimate -0.15, residuals 0.75 and -0.25
  # (three times), SE = sqrt(4 / 3 x 0.75) / 20 = 0.05.
  nw <- rep(c(TRUE, TRUE, FALSE, FALSE, FALSE), 4); rf <- !nw
  nw[3] <- TRUE
  r <- hr_report(zero_var_bench(ref, nw, rf), contrasts = c("new", "ref"),
                 registration = reg, B = 200)
  expect_equal(r$ni$estimate, -0.15)
  expect_equal(r$ni$lower, -0.15 - stats::qt(0.975, 3) * 0.05)
  expect_true(r$ni$verdict)
  # Tango's check: q10 = 8 / 20, q01 = 11 / 20, and
  # (q10 + q01 - 0.15^2) / SE^2 = 371 effective pairs, capped at 20 items.
  expect_equal(r$ni$n_eff, 20)
  expect_lt(r$ni$tango_lower, -0.4)
  expect_false(r$ni$tango_agrees)
  expect_true(any(grepl(paste0("different accuracy conclusion from the non-inferiority ",
                               "bound \\(the cluster-robust t bound"), r$notes)))
  expect_false(any(grepl("the verdict follows the bootstrap", r$notes)))
})

test_that("the verdict needs the new arm to be cheaper when the contrast tests cost", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, list(
    hr_contrast("new", "ref", margin = 0.10)), design)
  reg_nc <- hr_register_contrasts(ref, list(
    hr_contrast("new", "ref", margin = 0.10, cost_test = FALSE)), design)
  set.seed(13)
  dear <- ni_bench(ref, shift = 0, usd_new = 0.003, usd_ref = 0.002)
  r <- hr_report(dear, registration = reg, B = 1000)
  expect_true(r$ni$accuracy_holds)
  expect_false(r$ni$cost_holds)
  expect_gt(r$ni$cost_upper, 0)
  expect_false(r$ni$verdict)
  expect_identical(r$ni$p_value, 1)
  # Without the cost condition accuracy alone decides.
  r2 <- hr_report(dear, registration = reg_nc, B = 1000)
  expect_true(r2$ni$verdict)
  expect_true(is.na(r2$ni$cost_holds))
  expect_output(print(r2), "not tested")
  # Unknown cost cannot be shown lower.
  dear$usd[dear$arm == "new"][1] <- NA
  r3 <- hr_report(dear, registration = reg, B = 1000)
  expect_false(r3$ni$verdict)
})

test_that("Holm tests the confirmatory contrasts step down and exploratory ones alone", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, list(
    hr_contrast("good", "ref", margin = 0.11),
    hr_contrast("bad", "ref", margin = 0.11),
    hr_contrast("probe", "ref", margin = 0.05, confirmatory = FALSE)), design)
  set.seed(14)
  d <- ni_bench(ref, shift = c(good = 0, bad = -0.2, probe = 0))
  r <- hr_report(d, registration = reg, B = 1000)
  ni <- r$ni
  expect_identical(ni$label, c("confirmatory", "confirmatory", "exploratory"))
  # The good arm has the smaller p-value, so it is tested first at 0.025 / 2;
  # the bad arm is then tested at 0.025 and fails.
  expect_equal(ni$level, c(0.0125, 0.025, 0.025))
  expect_identical(ni$verdict[1:2], c(TRUE, FALSE))
  # The achieved MDD of a confirmatory contrast uses alpha / 2.
  expect_gt(ni$mdd_achieved[1], ni$mdd_achieved[3] * 0.9)
})

test_that("dev-split rows are refused as evidence", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.10), design)
  set.seed(15)
  d <- ni_bench(ref, shift = 0)
  dev <- d
  dev$split[dev$item == dev$item[1]] <- "dev"
  dev$reportable[dev$item == dev$item[1]] <- FALSE
  expect_error(hr_report(dev, registration = reg, B = 200), class = "hr_dev_not_evidence")
  expect_error(hr_report(dev, confirmatory = TRUE, B = 200), class = "hr_dev_not_evidence")
  # Flipping reportable does not make a dev row evidence.
  dev$reportable <- TRUE
  expect_error(hr_report(dev, registration = reg, B = 200), class = "hr_dev_not_evidence")
  # Calibration and exploratory rows are reportable but not evidence.
  cal <- d
  cal$split[cal$item == cal$item[1]] <- "calibration"
  err <- tryCatch(hr_report(cal, registration = reg, B = 200), error = function(e) e)
  expect_s3_class(err, "hr_dev_not_evidence")
  expect_match(conditionMessage(err), "calibration")
  cal$split[cal$item == cal$item[1]] <- "exploratory"
  expect_error(hr_report(cal, confirmatory = TRUE, B = 200), class = "hr_dev_not_evidence")
  # A descriptive, non-confirmatory report still leaves dev rows out quietly.
  dev$reportable <- dev$split != "dev"
  expect_s3_class(hr_report(dev, B = 200), "hr_bench_report")
})

test_that("a registration is tied to its reference and cannot be changed", {
  ref <- ni_reference(40, 10)
  design <- hr_mdd(400, n_clusters = 40, icc = 0.1, p_disc = 0.2)
  reg <- hr_register_contrasts(ref, hr_contrast("new", "ref", margin = 0.10), design)
  set.seed(16)
  d <- ni_bench(ref, shift = 0)
  loose <- reg
  loose$contrasts$margin <- 0.5
  expect_error(hr_report(d, registration = loose, B = 200), class = "hr_registration_changed")
  expect_error(hr_report(d, registration = list(), B = 200), class = "hr_registration_changed")
  other <- d
  attr(other, "reference_hash") <- NULL
  expect_error(hr_report(other, registration = reg, B = 200),
               class = "hr_registration_mismatch")
  wrong <- d
  wrong$arm[wrong$arm == "new"] <- "other"
  expect_error(hr_report(wrong, registration = reg, B = 200),
               class = "hr_registration_mismatch")
})

test_that("Tango's paired score interval matches a hand-computed example", {
  # b = 12 items right under the first arm only, c = 2 under the second only,
  # n = 50. The bounds solve Z(Delta) = +-1.959964 with the restricted MLE of
  # the discordant cell; computed once by maximising the restricted
  # multinomial likelihood numerically and solving for Z.
  tg <- harnessr:::tango_interval(12, 2, 50)
  expect_equal(unname(tg), c(0.0611124, 0.3447087), tolerance = 1e-6)
  tg2 <- harnessr:::tango_interval(7, 3, 40)
  expect_equal(unname(tg2), c(-0.0618375, 0.2641605), tolerance = 1e-6)
  # At Delta = 0 the score statistic is McNemar's (b - c) / sqrt(b + c), so
  # the bound for b = c + z sqrt(b + c) is exactly 0: b = 4.5, c = 0.5 gives
  # (4.5 - 0.5) / sqrt(5) = 1.789, so take conf where z = 4 / sqrt(5).
  conf <- 1 - 2 * stats::pnorm(-4 / sqrt(5))
  expect_equal(unname(harnessr:::tango_interval(4.5, 0.5, 30, conf)[1]), 0, tolerance = 1e-8)
  # No discordant items: symmetric about 0, and the edges are reached.
  z <- harnessr:::tango_interval(0, 0, 50)
  expect_equal(z[["lower"]], -z[["upper"]])
  expect_identical(unname(harnessr:::tango_interval(5, 0, 5)[2]), 1)
})
