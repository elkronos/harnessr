# test-core-stats.R: the exported statistics checked against reference values.
#
# Every reference value is either another R function that computes the same
# thing (prop.test, binom.test, qbeta, t.test), a published worked example
# (Krippendorff 2011), or arithmetic written out in the comment beside it.
# Random draws run under harnessr's private seed so no test moves the
# session's random stream.

seeded <- function(seed, expr) harnessr:::with_private_rng(seed, expr)

# Two raters on two categories, rows x and columns y:
#            y keep  y drop
#   x keep     40       6
#   x drop      9      45
two_by_two <- function() {
  list(x = rep(c("keep", "keep", "drop", "drop"), c(40, 6, 9, 45)),
       y = rep(c("keep", "drop", "keep", "drop"), c(40, 6, 9, 45)))
}

# Krippendorff (2011), "Computing Krippendorff's alpha-reliability", the
# example with four coders and twelve units and some values missing.
kripp_example <- function() {
  cbind(A = c(1, 2, 3, 3, 2, 1, 4, 1, 2, NA, NA, NA),
        B = c(1, 2, 3, 3, 2, 2, 4, 1, 2, 5, NA, 3),
        C = c(NA, 3, 3, 3, 2, 3, 4, 2, 2, 5, 1, NA),
        D = c(1, 2, 3, 3, 2, 4, 4, 1, 2, 5, 1, NA))
}

# ---- hr_prop_ci -------------------------------------------------------------

test_that("Wilson matches prop.test without continuity correction", {
  for (n in c(1, 7, 20, 150)) for (x in unique(round(seq(0, n, length.out = 8)))) {
    w <- hr_prop_ci(x, n)
    ref <- suppressWarnings(prop.test(x, n, correct = FALSE)$conf.int)
    expect_equal(c(w$lower, w$upper), as.numeric(ref), tolerance = 1e-10)
    lo <- hr_prop_ci(x, n, side = "lower", conf = 0.9)
    ref_lo <- suppressWarnings(prop.test(x, n, correct = FALSE, alternative = "greater",
                                         conf.level = 0.9)$conf.int)
    expect_equal(c(lo$lower, lo$upper), as.numeric(ref_lo), tolerance = 1e-10)
    up <- hr_prop_ci(x, n, side = "upper")
    ref_up <- suppressWarnings(prop.test(x, n, correct = FALSE, alternative = "less")$conf.int)
    expect_equal(c(up$lower, up$upper), as.numeric(ref_up), tolerance = 1e-10)
  }
})

test_that("Clopper-Pearson matches binom.test, both sides and one", {
  for (n in c(1, 5, 30, 200)) for (x in unique(round(seq(0, n, length.out = 7)))) {
    cp <- hr_prop_ci(x, n, method = "clopper_pearson")
    expect_equal(c(cp$lower, cp$upper), as.numeric(binom.test(x, n)$conf.int),
                 tolerance = 1e-10)
    lo <- hr_prop_ci(x, n, method = "clopper_pearson", side = "lower", conf = 0.975)
    expect_equal(c(lo$lower, lo$upper),
                 as.numeric(binom.test(x, n, alternative = "greater", conf.level = 0.975)$conf.int),
                 tolerance = 1e-10)
    up <- hr_prop_ci(x, n, method = "clopper_pearson", side = "upper")
    expect_equal(c(up$lower, up$upper),
                 as.numeric(binom.test(x, n, alternative = "less")$conf.int), tolerance = 1e-10)
  }
})

test_that("Jeffreys uses the Beta(x + 1/2, n - x + 1/2) quantiles with fixed ends", {
  j <- hr_prop_ci(c(0, 3, 10), 10, method = "jeffreys")
  expect_equal(j$lower, c(0, qbeta(0.025, 3.5, 7.5), qbeta(0.025, 10.5, 0.5)))
  expect_equal(j$upper, c(qbeta(0.975, 0.5, 10.5), qbeta(0.975, 3.5, 7.5), 1))
  one <- hr_prop_ci(3, 10, method = "jeffreys", side = "lower")
  expect_equal(c(one$lower, one$upper), c(qbeta(0.05, 3.5, 7.5), 1))
})

test_that("hr_prop_ci is vectorised and returns the documented columns", {
  out <- hr_prop_ci(c(1, 2, 3), 10)
  expect_named(out, c("x", "n", "est", "lower", "upper", "method", "side", "conf"))
  expect_equal(nrow(out), 3L)
  expect_equal(out$est, c(0.1, 0.2, 0.3))
  expect_equal(hr_prop_ci(2, c(4, 8))$est, c(0.5, 0.25))
  empty <- hr_prop_ci(0, 0)
  expect_true(is.na(empty$est) && is.na(empty$lower) && is.na(empty$upper))
})

test_that("hr_prop_ci refuses impossible counts and settings", {
  expect_error(hr_prop_ci(11, 10), "0 <= x <= n", class = "gr_bad_setting")
  expect_error(hr_prop_ci(-1, 10), class = "gr_bad_setting")
  expect_error(hr_prop_ci(1.5, 10), class = "gr_bad_setting")
  expect_error(hr_prop_ci(NA, 10), class = "gr_bad_setting")
  expect_error(hr_prop_ci(1:3, 1:2 + 5), "lengths", class = "gr_bad_setting")
  expect_error(hr_prop_ci(1, 10, conf = 1), "conf", class = "gr_bad_setting")
  expect_error(hr_prop_ci(1, 10, method = "wald"))
})

# ---- hr_agreement, two raters -----------------------------------------------

test_that("two-rater agreement matches the hand-computed set", {
  d <- two_by_two()
  ag <- hr_agreement(d$x, d$y, positive = "keep", B = 500)
  expect_s3_class(ag, "hr_agreement")
  expect_equal(unname(unclass(ag$table)), matrix(c(40, 9, 6, 45), 2))
  st <- setNames(ag$stats$estimate, ag$stats$statistic)
  # po = 85 / 100. Marginals: x keep 0.46, y keep 0.49, so
  # pe = 0.46 * 0.49 + 0.54 * 0.51 = 0.5008 and kappa = 0.3492 / 0.4992.
  expect_equal(st[["observed agreement"]], 0.85)
  expect_equal(st[["kappa"]], 0.3492 / 0.4992)
  expect_equal(ag$kappa, 0.3492 / 0.4992)
  # PABAK = 2 * 0.85 - 1; PI = (40 - 45) / 100; BI = (6 - 9) / 100.
  expect_equal(st[["PABAK"]], 0.7)
  expect_equal(st[["prevalence index"]], -0.05)
  expect_equal(st[["bias index"]], -0.03)
  # AC1: pi_keep = (0.46 + 0.49) / 2 = 0.475, pe = 2 * 0.475 * 0.525 = 0.49875,
  # AC1 = (0.85 - 0.49875) / (1 - 0.49875).
  expect_equal(st[["AC1"]], 0.35125 / 0.50125)
  # Specific agreement 2a / (2a + b + c) and 2d / (2d + b + c).
  expect_equal(st[["positive agreement"]], 80 / 95)
  expect_equal(st[["negative agreement"]], 90 / 105)
  # y is the reference.
  expect_equal(st[["sensitivity"]], 40 / 49)
  expect_equal(st[["specificity"]], 45 / 51)
  expect_equal(st[["PPV"]], 40 / 46)
  expect_equal(st[["NPV"]], 45 / 54)
  sens <- ag$stats[ag$stats$statistic == "sensitivity", ]
  w <- hr_prop_ci(40, 49)
  expect_equal(c(sens$lower, sens$upper), c(w$lower, w$upper))
  # Kappa's standard error (Fleiss, Cohen and Everitt 1969), computed once
  # from the other published form of the same variance.
  expect_equal(ag$stats$se[ag$stats$statistic == "kappa"], 0.0713936026999882,
               tolerance = 1e-10)
  # PABAK's interval is the Wilson interval on po mapped by 2p - 1.
  po_w <- hr_prop_ci(85, 100)
  pab <- ag$stats[ag$stats$statistic == "PABAK", ]
  expect_equal(c(pab$lower, pab$upper), 2 * c(po_w$lower, po_w$upper) - 1)
  expect_false(ag$paradox_flag)
})

test_that("the AC1 interval is the one gr_calibrate() already reports", {
  d <- two_by_two()
  ag <- hr_agreement(d$x, d$y, B = 0)
  old <- harnessr:::agreement_2x2(40, 6, 9, 45)$stats
  new_ac1 <- ag$stats[ag$stats$statistic == "AC1", ]
  old_ac1 <- old[old$statistic == "AC1", ]
  expect_equal(c(new_ac1$estimate, new_ac1$lower, new_ac1$upper),
               c(old_ac1$estimate, old_ac1$lower, old_ac1$upper))
})

test_that("three categories give kappa, PABAK and AC1 but no PI or BI", {
  # Rows x, columns y; n = 60, po = 47 / 60, both raters' marginals 25, 20, 15.
  tab <- matrix(c(20, 3, 2, 4, 15, 1, 1, 2, 12), 3)
  cells <- expand.grid(x = c("a", "b", "c"), y = c("a", "b", "c"), stringsAsFactors = FALSE)
  x <- rep(cells$x, as.vector(tab)); y <- rep(cells$y, as.vector(tab))
  ag <- hr_agreement(x, y, B = 0)
  st <- setNames(ag$stats$estimate, ag$stats$statistic)
  # pe = (25^2 + 20^2 + 15^2) / 60^2 = 1250 / 3600; kappa = (47/60 - pe) / (1 - pe).
  pe <- 1250 / 3600
  expect_equal(st[["kappa"]], (47 / 60 - pe) / (1 - pe))
  # PABAK for k = 3: (3 po - 1) / 2.
  expect_equal(st[["PABAK"]], (3 * 47 / 60 - 1) / 2)
  # AC1: pi = (25, 20, 15) / 60, pe = sum(pi (1 - pi)) / 2.
  pk <- c(25, 20, 15) / 60
  pg <- sum(pk * (1 - pk)) / 2
  expect_equal(st[["AC1"]], (47 / 60 - pg) / (1 - pg))
  expect_equal(ag$stats$se[ag$stats$statistic == "kappa"], 0.081803276965233,
               tolerance = 1e-10)
  expect_false("prevalence index" %in% names(st))
  expect_true(any(grepl("two categories", ag$notes)))
})

test_that("the paradox flag follows the stated rule", {
  # abs(PI) = |1 - 95| / 100 = 0.94 > 0.8.
  x <- rep(c(TRUE, TRUE, FALSE, FALSE), c(1, 2, 2, 95))
  y <- rep(c(TRUE, FALSE, TRUE, FALSE), c(1, 2, 2, 95))
  expect_true(hr_agreement(x, y, B = 0)$paradox_flag)
  # abs(PI) = 0.64, but po = 0.8 and kappa = (0.8 - 0.7048) / 0.2952 = 0.32.
  x <- rep(c(TRUE, TRUE, FALSE, FALSE), c(8, 10, 10, 72))
  y <- rep(c(TRUE, FALSE, TRUE, FALSE), c(8, 10, 10, 72))
  ag <- hr_agreement(x, y, positive = TRUE, B = 0)
  expect_equal(ag$kappa, 0.0952 / 0.2952)
  expect_true(ag$paradox_flag)
})

test_that("the kappa bootstrap is reproducible and leaves the caller's RNG alone", {
  d <- two_by_two()
  set.seed(11)
  before <- .Random.seed
  a1 <- hr_agreement(d$x, d$y, B = 300, seed = 7)
  expect_identical(.Random.seed, before)
  a2 <- hr_agreement(d$x, d$y, B = 300, seed = 7)
  k1 <- a1$stats[a1$stats$statistic == "kappa", ]
  k2 <- a2$stats[a2$stats$statistic == "kappa", ]
  expect_identical(c(k1$lower, k1$upper), c(k2$lower, k2$upper))
  expect_true(k1$lower < a1$kappa && a1$kappa < k1$upper)
  expect_equal(a1$bootstrap, list(B = 300L, seed = 7))
})

test_that("missing labels are left out and counted", {
  d <- two_by_two()
  x <- c(d$x, NA, "keep"); y <- c(d$y, "drop", NA)
  ag <- hr_agreement(x, y, B = 0)
  expect_equal(ag$n, 100L)
  expect_equal(ag$dropped, 2L)
  expect_true(any(grepl("2 item", ag$notes)))
})

test_that("print shows the table with every measure, and as_json writes it", {
  d <- two_by_two()
  ag <- hr_agreement(d$x, d$y, positive = "keep", B = 100)
  out <- paste(capture.output(print(ag)), collapse = "\n")
  for (s in c("Counts", "kappa", "PABAK", "AC1", "prevalence index", "sensitivity",
              "observed agreement")) {
    expect_match(out, s, fixed = TRUE)
  }
  js <- jsonlite::fromJSON(as_json(ag))
  expect_equal(js$type, "two_raters")
  expect_equal(js$table, matrix(c(40, 9, 6, 45), 2))
  expect_equal(js$kappa, ag$kappa)
  expect_true("AC1" %in% js$stats$statistic)
})

test_that("hr_agreement refuses inputs it cannot read", {
  expect_error(hr_agreement(1:3, 1:4), "same length", class = "gr_bad_setting")
  expect_error(hr_agreement(1:3), class = "gr_bad_setting")
  expect_error(hr_agreement(c(NA, NA), c(NA, NA)), "both raters", class = "gr_bad_setting")
  expect_error(hr_agreement(kripp_example(), positive = 1), "two raters",
               class = "gr_bad_setting")
  expect_error(hr_agreement(coders = 1:5), "matrix", class = "gr_bad_setting")
  expect_error(hr_agreement(coders = matrix(letters[1:6], 3), level = "interval"),
               "numeric", class = "gr_bad_setting")
  expect_error(hr_agreement(1:3, 1:3, B = -1), class = "gr_bad_setting")
  expect_error(hr_agreement(c("a", "b", "a"), c("a", "b", "b"), positive = "zz", B = 0),
               "not one of the labels", class = "gr_bad_setting")
})

test_that("hr_agreement drops factor levels neither rater used", {
  lv <- c("a", "b", "c")
  ag <- hr_agreement(factor(c("a", "b", "a"), levels = lv),
                     factor(c("a", "b", "b"), levels = lv), B = 0)
  expect_equal(dim(ag$table), c(2L, 2L))
  st <- setNames(ag$stats$estimate, ag$stats$statistic)
  # po = 2 / 3, so PABAK = 2 * 2 / 3 - 1 with k = 2, not (3 po - 1) / 2.
  expect_equal(st[["PABAK"]], 1 / 3)
  # a = 1, b = 1, c = 0, d = 1: PI = 0, BI = 1 / 3.
  expect_equal(st[["prevalence index"]], 0)
  expect_equal(st[["positive agreement"]], 2 / 3)
  expect_true(any(grepl("neither rater used left out of the table: c", ag$notes, fixed = TRUE)))

  # A declared positive level stays, so an all-negative decision is still 2x2.
  yn <- factor(c("no", "no", "no"), levels = c("yes", "no"))
  ag2 <- hr_agreement(yn, yn, positive = "yes", B = 0)
  expect_equal(dim(ag2$table), c(2L, 2L))
  expect_equal(rownames(ag2$table), c("yes", "no"))
})

# ---- Krippendorff's alpha ---------------------------------------------------

test_that("alpha reproduces Krippendorff's (2011) worked example at every level", {
  ex <- kripp_example()
  alpha_at <- function(level) {
    cm <- harnessr:::coder_matrix(ex, level)
    harnessr:::kripp_alpha(cm$values, level, cm$categories)$alpha
  }
  # Published: nominal 0.743, ordinal 0.815, interval 0.849, ratio 0.797.
  expect_equal(round(alpha_at("nominal"), 3), 0.743)
  expect_equal(round(alpha_at("ordinal"), 3), 0.815)
  expect_equal(round(alpha_at("interval"), 3), 0.849)
  expect_equal(round(alpha_at("ratio"), 3), 0.797)
})

test_that("ordinal alpha merges coders' factor levels in order", {
  # Coder A never says "mid" and its factor has levels low, high; coder B's
  # has low, mid, high. Items: 10 x (low, low), 10 x (high, high),
  # 6 x (high, mid), 4 x (low, mid). Coincidences o_ll = 20, o_hh = 20,
  # o_mh = 6 each way, o_lm = 4 each way; margins n_l = 24, n_m = 10,
  # n_h = 26, n = 60. Ordinal distances on low < mid < high:
  # d_lm = (34 / 2)^2 = 289, d_mh = (36 / 2)^2 = 324, d_lh = (60 - 25)^2 = 1225.
  # D_o = 2 * (4 * 289 + 6 * 324) = 6200;
  # D_e = 2 * (24 * 10 * 289 + 10 * 26 * 324 + 24 * 26 * 1225) = 1836000;
  # alpha = 1 - 59 * 6200 / 1836000 = 0.8007625. Reading the order as
  # low, high, mid (the old result) gives 0.3997168.
  a <- rep(c("low", "high", "high", "low"), c(10, 10, 6, 4))
  b <- rep(c("low", "high", "mid", "mid"), c(10, 10, 6, 4))
  lv <- c("low", "mid", "high")
  ag <- hr_agreement(factor(a, levels = c("low", "high")), factor(b, levels = lv),
                     level = "ordinal", B = 0)
  expect_equal(ag$categories, lv)
  expect_equal(ag$alpha, 1 - 59 * 6200 / 1836000)
  expect_equal(round(ag$alpha, 7), 0.8007625)
  # The same with the coders swapped, and with common levels.
  expect_equal(hr_agreement(factor(b, levels = lv), factor(a, levels = c("low", "high")),
                            level = "ordinal", B = 0)$alpha, 1 - 59 * 6200 / 1836000)
  expect_equal(hr_agreement(factor(a, levels = lv), factor(b, levels = lv),
                            level = "ordinal", B = 0)$alpha, 1 - 59 * 6200 / 1836000)
  # Orders that conflict, or that leave two levels unordered, are an error
  # for the ordinal level; nominal alpha does not depend on the order.
  expect_error(hr_agreement(factor(a, levels = c("high", "low")), factor(b, levels = lv),
                            level = "ordinal", B = 0),
               "same levels", class = "gr_bad_setting")
  expect_error(hr_agreement(factor(a, levels = c("low", "high")),
                            factor(b, levels = c("low", "mid")), level = "ordinal", B = 0),
               "same levels", class = "gr_bad_setting")
  nom <- hr_agreement(coders = data.frame(a = factor(a, levels = c("high", "low")),
                                          b = factor(b, levels = lv)), B = 0)
  expect_setequal(nom$categories, lv)
})

test_that("below 30 items alpha is withheld and percent agreement given", {
  ag <- hr_agreement(coders = kripp_example())
  expect_s3_class(ag, "hr_agreement")
  expect_true(is.na(ag$alpha))
  # Coincidence matrix diagonal 7 + 10 + 8 + 4 + 3 = 32 of 40 pairable values.
  expect_equal(ag$po, 32 / 40)
  expect_equal(ag$n, 11L)
  expect_equal(ag$dropped, 1L)
  expect_true(any(grepl("needs at least 30", ag$notes)))
  out <- paste(capture.output(print(ag)), collapse = "\n")
  expect_match(out, "Coincidence matrix")
})

test_that("alpha is reported with a bootstrap interval from 30 items", {
  m <- seeded(21, {
    truth <- sample(1:4, 60, replace = TRUE)
    sapply(1:3, function(j) ifelse(runif(60) < 0.8, truth, sample(1:4, 60, TRUE)))
  })
  m[cbind(c(1, 2, 3), c(1, 2, 3))] <- NA
  ag <- hr_agreement(coders = m, B = 300)
  cm <- harnessr:::coder_matrix(m, "nominal")
  expect_equal(ag$alpha, harnessr:::kripp_alpha(cm$values, "nominal", cm$categories)$alpha)
  a <- ag$stats[ag$stats$statistic == "Krippendorff's alpha", ]
  expect_true(a$lower < ag$alpha && ag$alpha < a$upper)
  # Two raters at a non-nominal level are alpha too.
  two <- hr_agreement(m[, 1], m[, 2], level = "interval", B = 0)
  expect_equal(two$type, "coders")
  expect_false(is.na(two$alpha))
})

test_that("a constant field gives no alpha and says why", {
  ag <- hr_agreement(coders = matrix("yes", 40, 3), B = 0)
  expect_true(is.na(ag$alpha))
  expect_equal(ag$po, 1)
  expect_true(any(grepl("same", ag$notes)))
})

# ---- hr_ht_estimate ---------------------------------------------------------

test_that("Horvitz-Thompson, Hajek and ratio estimates match hand calculation", {
  y <- c(1, 0, 1, 1); pi <- c(1, 0.5, 0.25, 0.5)
  # Weights 1, 2, 4, 2. HT total = 1 + 0 + 4 + 2 = 7; sum of weights 9.
  expect_equal(hr_ht_estimate(y, pi, estimand = "total", B = 0)$estimate, 7)
  hj <- hr_ht_estimate(y, pi, estimand = "mean", B = 0)
  expect_equal(hj$estimate, 7 / 9)
  expect_equal(hj$N_hat, 9)
  expect_equal(hj$method, "hajek")
  # den = 2, 1, 1, 1: its total is 2 + 2 + 4 + 2 = 10.
  expect_equal(hr_ht_estimate(y, pi, estimand = "ratio", den = c(2, 1, 1, 1), B = 0)$estimate,
               0.7)
  # Difference estimator: sum(yhat_pop) = 6, residuals 0, -1, 1, 0 weighted
  # 1, 2, 4, 2 add -2 + 4. Total 8, mean 8 / 10.
  yhat <- c(1, 1, 0, 1); pop <- c(1, 1, 0, 1, rep(c(1, 0), 3))
  expect_equal(hr_ht_estimate(y, pi, estimand = "total", yhat = yhat, yhat_pop = pop,
                              B = 0)$estimate, 8)
  expect_equal(hr_ht_estimate(y, pi, yhat = yhat, yhat_pop = pop, B = 0)$estimate, 0.8)
})

test_that("the HT and difference estimators are exactly unbiased under Poisson sampling", {
  # Every one of the 2^6 samples of a population of six, each weighted by its
  # probability; the empty sample contributes an estimate of 0.
  yp <- c(3, 0, 5, 1, 2, 4)
  pp <- c(0.9, 0.3, 0.5, 0.2, 0.6, 0.4)
  hp <- c(2, 1, 4, 1, 2, 3)
  e_ht <- 0; e_diff <- sum(hp) * prod(1 - pp)
  for (s in 1:63) {
    inc <- bitwAnd(s, 2^(0:5)) > 0
    pr <- prod(ifelse(inc, pp, 1 - pp))
    e_ht <- e_ht + pr * hr_ht_estimate(yp[inc], pp[inc], estimand = "total", B = 0)$estimate
    e_diff <- e_diff + pr * hr_ht_estimate(yp[inc], pp[inc], estimand = "total",
                                           yhat = hp[inc], yhat_pop = hp, B = 0)$estimate
  }
  expect_equal(e_ht, sum(yp))
  expect_equal(e_diff, sum(yp))
})

test_that("the bootstrap resamples within strata and keeps the caller's RNG", {
  y <- c(rep(1, 20), rep(c(1, 0), c(3, 27)))
  pi <- c(rep(1, 20), rep(0.1, 30))
  st <- rep(c("kept", "excluded"), c(20, 30))
  set.seed(3); before <- .Random.seed
  r <- hr_ht_estimate(y, pi, strata = st, estimand = "total", B = 400)
  expect_identical(.Random.seed, before)
  # The kept stratum has no variance, so every replicate keeps its 20.
  expect_equal(r$estimate, 20 + 3 / 0.1)
  expect_true(r$lower >= 20 && r$lower <= r$estimate && r$estimate <= r$upper)
  expect_true(r$se > 0)
  expect_identical(r, hr_ht_estimate(y, pi, strata = st, estimand = "total", B = 400))
  one <- hr_ht_estimate(c(1, 0, 1), c(1, 0.5, 0.5), strata = c("a", "b", "b"), B = 50)
  expect_match(one$note, "one sampled unit")
})

test_that("the bootstrap applies the finite population correction", {
  # A census: all 20 units judged at pi = 1, 12 of them eligible. The total is
  # known exactly, so se = 0 and the interval is [12, 12] although y varies.
  # Before the fix: se 2.22, interval [8, 16].
  y <- c(rep(1, 12), rep(0, 8))
  cen <- hr_ht_estimate(y, rep(1, 20), estimand = "total", B = 2000)
  expect_equal(c(cen$estimate, cen$se, cen$lower, cen$upper), c(12, 0, 12, 12))
  # Kept records judged in full with varying y, excluded ones at pi = 0.1: the
  # kept stratum adds nothing, so the se depends on the excluded stratum only.
  y2 <- c(y, rep(c(1, 0), c(3, 27)))
  pi2 <- c(rep(1, 20), rep(0.1, 30))
  st2 <- rep(c("kept", "excluded"), c(20, 30))
  only_ex <- hr_ht_estimate(y2[21:50], pi2[21:50], estimand = "total", B = 1000)
  both <- hr_ht_estimate(y2, pi2, strata = st2, estimand = "total", B = 1000)
  expect_equal(both$se, only_ex$se)
  expect_equal(both$estimate, 12 + 3 / 0.1)
  # SRS of 100 from N = 200 (pi = 0.5), 30 eligible. Design variance
  # N^2 (1 - f) s^2 / n with s^2 = 30 * 70 / (100 * 99) = 0.2121212:
  # 40000 * 0.5 * 0.2121212 / 100 = 42.42424, se 6.513389. Without the
  # correction the bootstrap gave 9.14.
  y3 <- rep(c(1, 0), c(30, 70))
  srs <- hr_ht_estimate(y3, rep(0.5, 100), estimand = "total", B = 4000)
  expect_equal(srs$se, 6.513389, tolerance = 0.3 / 6.513389)
  # The documented example: excluded stratum N = 300, n = 30, one eligible, so
  # s^2 = (1 - 1 / 30) / 29 = 1 / 30 and the variance is
  # 300^2 * 0.9 * (1 / 30) / 30 = 90, se 9.486833; the census of kept records
  # adds nothing. Before the fix: 10.07.
  el <- c(rep(1, 18), rep(0, 2), rep(1, 1), rep(0, 29))
  kp <- c(rep(1, 20), rep(0, 30))
  ex <- hr_ht_estimate(el, ifelse(kp == 1, 1, 0.1), strata = kp, estimand = "total",
                       B = 4000)
  expect_equal(ex$se, 9.486833, tolerance = 0.4 / 9.486833)
})

test_that("hr_ht_estimate refuses bad probabilities and mismatched inputs", {
  expect_error(hr_ht_estimate(1:3, c(0.5, 0, 1)), "\\(0, 1\\]", class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:3, c(0.5, 1.2, 1)), class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:3, c(0.5, NA, 1)), class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:3, c(0.5, 1)), "one value per unit", class = "gr_bad_setting")
  expect_error(hr_ht_estimate(c(1, NA), c(1, 1)), class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:2, c(1, 1), strata = "a"), class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:2, c(1, 1), estimand = "ratio"), "den",
               class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:2, c(1, 1), yhat = 1:2), "both", class = "gr_bad_setting")
  expect_error(hr_ht_estimate(1:2, c(1, 1), estimand = "ratio", den = 1:2, yhat = 1:2,
                              yhat_pop = 1:4), class = "gr_bad_setting")
})

# ---- hr_ppi -----------------------------------------------------------------

test_that("PPI without tuning matches the formula by hand", {
  # mean(yhat_U) = 0.75, mean(y - yhat_L) = 1/3. Variance
  # var(yhat_U) / 4 + var(c(0, 1, 0)) / 3 = 0.0625 + 1/9, so se = 5/12.
  r <- hr_ppi(c(1, 0, 1, 1), c(1, 0, 1), c(1, 1, 1), tune = FALSE)
  expect_equal(r$estimate, 0.75 + 1 / 3)
  expect_equal(r$se, 5 / 12)
  expect_equal(r$lambda, 1)
  expect_equal(r$method, "ppi")
  expect_equal(c(r$n, r$N), c(3L, 4L))
  expect_equal(r$upper - r$estimate, qnorm(0.975) * 5 / 12)
})

test_that("PPI and PPI++ are unbiased and cover the mean in simulation", {
  # A judge right 85% of the time on a 30% outcome over-reports it
  # (0.3 * 0.85 + 0.7 * 0.15 = 0.36), so the naive mean is biased.
  reps <- seeded(31, lapply(1:200, function(r) {
    y <- rbinom(1100, 1, 0.3)
    yh <- ifelse(runif(1100) < 0.85, y, 1 - y)
    lab <- 1:100
    rbind(hr_ppi(yh[-lab], yh[lab], y[lab], tune = FALSE),
          hr_ppi(yh[-lab], yh[lab], y[lab]))
  }))
  for (m in c("ppi", "ppi++")) {
    est <- vapply(reps, function(d) d$estimate[d$method == m], numeric(1))
    cover <- mean(vapply(reps, function(d) {
      d <- d[d$method == m, ]
      d$lower <= 0.3 && 0.3 <= d$upper
    }, logical(1)))
    expect_lt(abs(mean(est) - 0.3), 3 * sd(est) / sqrt(200))
    expect_gte(cover, 0.88)
    expect_lte(cover, 0.99)
  }
  lam <- vapply(reps, function(d) d$lambda[d$method == "ppi++"], numeric(1))
  expect_true(all(lam >= 0 & lam <= 1))
})

test_that("the DSL form with unequal labelling probabilities is unbiased and covers", {
  # Units the judge calls positive are labelled at 0.3, the rest at 0.05.
  reps <- seeded(41, vapply(1:200, function(r) {
    y <- rbinom(1500, 1, 0.3)
    yh <- ifelse(runif(1500) < 0.85, y, 1 - y)
    p <- ifelse(yh == 1, 0.3, 0.05)
    lab <- runif(1500) < p
    d <- hr_ppi(yh[!lab], yh[lab], y[lab], pi = p[lab])
    c(d$estimate, d$lower <= 0.3 && 0.3 <= d$upper, d$method == "dsl tuned")
  }, numeric(3)))
  expect_true(all(reps[3, ] == 1))
  expect_lt(abs(mean(reps[1, ]) - 0.3), 3 * sd(reps[1, ]) / sqrt(200))
  expect_gte(mean(reps[2, ]), 0.88)
  expect_lte(mean(reps[2, ]), 0.99)
})

test_that("equal labelling probabilities reduce DSL to the unweighted form", {
  yu <- c(1, 0, 1, 1, 0, 1); yl <- c(1, 0, 1, 0); y <- c(1, 1, 1, 0)
  expect_identical(hr_ppi(yu, yl, y, pi = rep(0.4, 4)), hr_ppi(yu, yl, y))
})

test_that("hr_ppi refuses mismatched or impossible inputs", {
  expect_error(hr_ppi(c(1, 0, 1), c(1, 0), c(1, 0, 1)), "same length",
               class = "gr_bad_setting")
  expect_error(hr_ppi(c(1, 0), c(1), c(1)), "two labelled", class = "gr_bad_setting")
  expect_error(hr_ppi(c(1, 0), c(1, 0), c(1, NA)), class = "gr_bad_setting")
  expect_error(hr_ppi(c(1, 0), c(1, 0), c(1, 0), pi = c(0, 0.5)), "\\(0, 1\\]",
               class = "gr_bad_setting")
  expect_error(hr_ppi(c(1, 0), c(1, 0), c(1, 0), tune = NA), class = "gr_bad_setting")
})

# ---- hr_alt_test ------------------------------------------------------------

# Four annotators who each match the gold label about 70% of the time.
alt_people <- function(seed, n = 100) {
  seeded(seed, {
    gold <- sample(c("a", "b", "c"), n, replace = TRUE)
    people <- sapply(1:4, function(j) {
      ifelse(runif(n) < 0.7, gold, sample(c("a", "b", "c"), n, TRUE))
    })
    colnames(people) <- paste0("p", 1:4)
    list(gold = gold, people = people,
         random = sample(c("a", "b", "c"), n, TRUE))
  })
}

test_that("a model that labels the gold standard passes", {
  d <- alt_people(51)
  r <- hr_alt_test(d$gold, d$people, expertise = "skilled")
  expect_s3_class(r, "hr_alt_test")
  expect_true(r$passed)
  expect_equal(r$omega, 1)
  expect_equal(r$epsilon, 0.15)
  expect_true(r$rho > 0.5)
  expect_equal(r$sweep$epsilon, c(0.05, 0.10, 0.15, 0.20))
  expect_equal(nrow(r$per_annotator), 4L)
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "passed: omega = 1")
})

test_that("a model that labels at random fails", {
  d <- alt_people(52)
  r <- hr_alt_test(d$random, d$people, expertise = "expert")
  expect_false(r$passed)
  expect_equal(r$omega, 0)
  expect_equal(r$epsilon, 0.2)
  expect_true(all(!r$sweep$passed))
})

test_that("the per-annotator p-value is a one-sided t test on the indicator difference", {
  d <- c(1, 0, 0, 1, -1, 0, 0, 1, 0, 0)
  expect_equal(harnessr:::alt_pvalue(d, 0.1),
               t.test(d, mu = 0.1, alternative = "less")$p.value)
  expect_equal(harnessr:::alt_pvalue(rep(0, 40), 0.1), 0)
  expect_equal(harnessr:::alt_pvalue(rep(1, 40), 0.1), 1)
  # BY over the annotators: the rejections are those p.adjust(BY) puts at or under q.
  dd <- alt_people(53)
  r <- hr_alt_test(dd$gold, dd$people, expertise = "crowd")
  expect_equal(r$per_annotator$p_adjusted, p.adjust(r$per_annotator$p_value, "BY"))
  expect_equal(r$per_annotator$rejected, r$per_annotator$p_adjusted <= 0.05)
})

test_that("hr_alt_test refuses repeated or empty annotator names", {
  d <- alt_people(51)
  r <- hr_alt_test(d$gold, d$people, expertise = "skilled")
  # Independently: one one-sided t test per column on W_human - W_model, then
  # BY over all four p-values.
  own_p <- vapply(1:4, function(j) {
    dj <- vapply(1:100, function(i) {
      o <- d$people[i, -j]; sh <- mean(d$people[i, j] == o); sm <- mean(d$gold[i] == o)
      (sh >= sm) - (sm >= sh)
    }, numeric(1))
    t.test(dj, mu = 0.15, alternative = "less")$p.value
  }, numeric(1))
  expect_equal(r$per_annotator$annotator, paste0("p", 1:4))
  expect_equal(r$per_annotator$p_value, own_p)
  expect_equal(r$per_annotator$p_adjusted, p.adjust(own_p, "BY"))
  # Before: two columns named "p1" gave three rows, the first annotator gone
  # and BY run over three p-values. Now it is an error.
  dup <- d$people; colnames(dup) <- c("p1", "p1", "p3", "p4")
  expect_error(hr_alt_test(d$gold, dup, expertise = "skilled"), "repeated name\\(s\\): p1",
               class = "gr_bad_setting")
  emp <- d$people; colnames(emp) <- c("p1", "", "p3", "p4")
  expect_error(hr_alt_test(d$gold, emp, expertise = "skilled"), "1 empty name",
               class = "gr_bad_setting")
})

test_that("hr_alt_test enforces its minimums and requires expertise", {
  d <- alt_people(54)
  expect_error(hr_alt_test(d$gold, d$people), "expertise", class = "gr_bad_setting")
  expect_error(hr_alt_test(d$gold, d$people, expertise = "novice"), "expertise",
               class = "gr_bad_setting")
  expect_error(hr_alt_test(d$gold, d$people[, 1:2], expertise = "expert"), "at least 3",
               class = "gr_bad_setting")
  expect_error(hr_alt_test(d$gold[1:20], d$people[1:20, ], expertise = "expert"),
               "at least 30 items", class = "gr_bad_setting")
  expect_error(hr_alt_test(d$gold[1:10], d$people, expertise = "expert"),
               "one label per row", class = "gr_bad_setting")
  expect_warning(r <- hr_alt_test(d$gold[1:40], d$people[1:40, ], expertise = "expert"),
                 "50 to 100", class = "gr_small_sample")
  expect_equal(r$n_items, 40L)
  expect_error(hr_alt_test(d$gold, d$people, expertise = "expert", metric = "neg_rmse"),
               "numeric", class = "gr_bad_setting")
})
