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
  # sqrt(7.849 * 0.2 / 240): about 8.1 points before Holm.
  expect_equal(m$mdd, 0.0808748, tolerance = 1e-5)
  # sqrt(13.06 * 0.2 / 240): about 10.4 points after Holm over 9 contrasts.
  m9 <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(m9$alpha_adj, 0.025 / 9)
  expect_equal(m9$mdd, 0.1043429, tolerance = 1e-5)
  # Without the Holm adjustment the family size does not matter.
  expect_equal(hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9,
                      holm = FALSE)$mdd, m$mdd)

  # 8 points needs about 245 effective items.
  n8 <- hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2)
  expect_equal(n8$n_eff, 245.2775, tolerance = 1e-4)
  # After Holm over nine contrasts about 408 effective items, 816 questions
  # and 136 documents of 6.
  n9 <- hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(n9$n_eff, 408.2787, tolerance = 1e-4)
  expect_equal(n9$n_items, 816.5574, tolerance = 1e-4)
  expect_equal(n9$n_clusters, 136.0929, tolerance = 1e-4)
  # Holm over six contrasts gives about 378.
  expect_equal(hr_n_needed(0.08, p_disc = 0.2, n_contrasts = 6)$n_eff, 378.4236,
               tolerance = 1e-4)
  # 3 points needs about 1,744 effective items.
  expect_equal(hr_n_needed(0.03, p_disc = 0.2)$n_eff, 1744.195, tolerance = 1e-3)
  # A true difference of -2 points against an 8-point margin needs about 436.
  expect_equal(hr_n_needed(0.08, p_disc = 0.2, true_diff = -0.02)$n_eff, 436.0489,
               tolerance = 1e-4)
  # The two are inverses of each other.
  m816 <- hr_mdd(816, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
  expect_equal(hr_n_needed(m816$mdd, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)$n_items,
               816)
  expect_true(is.na(hr_n_needed(0.08, p_disc = 0.2)$n_clusters))
  expect_output(print(n9), "409 effective items; DE 2, so 817 items in 137 clusters of 6")
  expect_output(print(m9), "10.4 points")
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
  expect_error(hr_n_needed(0.08, p_disc = 0.2, true_diff = -0.1), class = "gr_bad_setting")
  # Independent items need no ICC.
  expect_equal(hr_mdd(240, p_disc = 0.2)$mdd,
               (stats::qnorm(0.975) + stats::qnorm(0.8)) * sqrt(0.2 / 240))
})

test_that("a confirmatory margin below the design MDD after Holm is refused", {
  ref <- ni_reference(80, 6)
  design <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
  # 8 points is just under the 8.1-point MDD of this design.
  expect_error(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.08), design),
               class = "hr_margin_below_mdd")
  # 10 points clears it for one contrast, and for three (9.3 points after
  # Holm), but not for nine (10.4 points).
  expect_s3_class(hr_register_contrasts(ref, hr_contrast("a", "b", margin = 0.10), design),
                  "hr_contrast_registration")
  three <- lapply(c("a", "c", "d"), function(x) hr_contrast(x, "b", margin = 0.10))
  reg3 <- hr_register_contrasts(ref, three, design)
  expect_equal(reg3$mdd$mdd, 0.0934, tolerance = 1e-3)
  nine <- lapply(letters[3:11], function(x) hr_contrast(x, "b", margin = 0.10))
  err <- tryCatch(hr_register_contrasts(ref, nine, design), error = function(e) e)
  expect_s3_class(err, "hr_margin_below_mdd")
  expect_match(conditionMessage(err), "10.4 points")
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
  expect_equal(reg$mdd$mdd, 0.0808748, tolerance = 1e-5)
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
  # the bootstrap standard error.
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
