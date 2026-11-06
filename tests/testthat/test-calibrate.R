# test-calibrate.R -- how often the screener is wrong, measured.
#
# The statistics are checked against hand-computed values, because a plausible
# wrong number here is worse than no number: it is the figure that would go in a
# methods section and license trusting everything downstream of it.
#
# The other half is refusing to answer questions the sample cannot answer. A
# sample drawn only from exclusions contains no kept records, so sensitivity and
# specificity computed on it are artifacts of the frame -- 0% and 100% -- and
# reporting them would be the most damaging kind of wrong, because both look
# like findings.

screening_of <- function(decisions, documents = NULL) {
  structure(list(table = data.frame(
    document = documents %||% paste0("d", seq_along(decisions), ".pdf"),
    decision = decisions, reason = "because", stringsAsFactors = FALSE)),
    class = "gr_screening")
}

test_that("the confusion matrix and its rates are what they should be", {
  # Worked by hand. Kept means include OR unclear -- a deferral is not a miss.
  #   d1 include/include  TP      d5 exclude/exclude  TN
  #   d2 include/exclude  FP      d6 exclude/include  FN
  #   d3 unclear/include  TP      d7 include/include  TP
  #   d4 exclude/exclude  TN      d8 exclude/exclude  TN
  scr <- screening_of(c("include", "include", "unclear", "exclude",
                        "exclude", "exclude", "include", "exclude"))
  ref <- data.frame(document = paste0("d", 1:8, ".pdf"),
                    human_decision = c("include", "exclude", "include", "exclude",
                                       "exclude", "include", "include", "exclude"),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all")

  expect_identical(unname(cal$counts[c("tp", "fn", "fp", "tn")]), c(3L, 1L, 1L, 3L))
  est <- function(m) cal$metrics$estimate[cal$metrics$metric == m]
  expect_equal(est("sensitivity (as deployed)"), 0.75)
  # d3 was kept but not actively included, so strict sensitivity is lower. The
  # gap between the two is the reading a person still has to do.
  expect_equal(est("sensitivity (strict include)"), 0.5)
  expect_equal(est("specificity"), 0.75)
  expect_equal(est("reading avoided"), 0.5)

  # Kappa on the decision sensitivity uses: kept (include or unclear) against
  # excluded. This used to assert 1/3, the kappa of the screener's three labels
  # against the person's two, which scored d3 (unclear, eligible) as a
  # disagreement while the sensitivity above counted it as kept. By hand:
  #   kept/eligible 3, kept/not 1, excluded/eligible 1, excluded/not 3
  #   po = 6/8, pe = (4*4 + 4*4)/64 = 1/2, kappa = (0.75 - 0.5) / 0.5 = 1/2.
  expect_equal(cal$kappa, 1/2, tolerance = 1e-8)
  kap <- function(a) a$stats$estimate[a$stats$statistic == "kappa"]
  expect_equal(kap(cal$agreement$kept), 1/2, tolerance = 1e-8)
  # An unclear on an eligible record is agreement in the kept table.
  expect_identical(unname(cal$agreement$kept$table["positive", "positive"]), 3L)
  # Strict include against the rest, the secondary table:
  #   include/eligible 2 (d1, d7), include/not 1 (d2), rest/eligible 2 (d3, d6),
  #   rest/not 3; po = 5/8, pe = (3*4 + 5*4)/64 = 1/2, kappa = 0.125 / 0.5 = 1/4.
  expect_equal(kap(cal$agreement$strict), 1/4, tolerance = 1e-8)
  # The 0.6.0 figure, kept for one release under its own name.
  expect_equal(cal$kappa_legacy, 1/3, tolerance = 1e-8)
  # And the 3x2 counts both tables are made from.
  expect_identical(as.integer(cal$decisions), c(2L, 1L, 1L, 1L, 0L, 3L))

  # The misses themselves, which say more than the rate does.
  expect_equal(nrow(cal$missed), 1L)
  expect_identical(cal$missed$document, "d6.pdf")
  expect_equal(nrow(cal$disagreements), 2L)     # the miss, and the false include
})

test_that("the interval is Wilson, and stays sensible where the textbook one does not", {
  # At 5 of 5 the normal-approximation interval is [1, 1] -- certainty from five
  # observations. Wilson does not do that, which is the whole reason for it,
  # because screening proportions live at the ends of the scale.
  five <- harnessr:::prop_row("x", 5, 5)
  expect_equal(five$estimate, 1)
  expect_lt(five$lower, 1)
  expect_gt(five$lower, 0.5)
  expect_equal(five$upper, 1)

  none <- harnessr:::prop_row("x", 0, 5)
  expect_equal(none$estimate, 0)
  expect_equal(none$lower, 0)
  expect_gt(none$upper, 0)

  # Against a worked value: 3 of 4, z = 1.96 -> [0.3006, 0.9544].
  three <- harnessr:::prop_row("x", 3, 4)
  expect_equal(three$lower, 0.3006, tolerance = 1e-3)
  expect_equal(three$upper, 0.9544, tolerance = 1e-3)

  # A bigger sample says more, which is the property that makes the interval
  # worth printing at all.
  wide <- harnessr:::prop_row("x", 15, 20)
  narrow <- harnessr:::prop_row("x", 150, 200)
  expect_equal(wide$estimate, narrow$estimate)
  expect_lt(narrow$upper - narrow$lower, wide$upper - wide$lower)

  # And nothing at all is NA rather than a division by zero.
  expect_true(is.na(harnessr:::prop_row("x", 0, 0)$estimate))
})

test_that("kappa notices a screener that agrees by doing nothing", {
  # At a realistic inclusion rate, excluding everything is ~95% accurate. That
  # is why accuracy is not reported and kappa is.
  k <- harnessr:::cohen_kappa
  expect_equal(k(rep("exclude", 20), c(rep("exclude", 19), "include")), 0, tolerance = 1e-8)
  expect_equal(k(c("include", "exclude"), c("include", "exclude")), 1)
  # Perfect disagreement is negative, not zero.
  expect_lt(k(c("include", "exclude"), c("exclude", "include")), 0)
  # One rater using one label throughout leaves nothing to correct for.
  expect_true(is.na(k(rep("include", 5), rep("include", 5))))
})

test_that("PABAK, AC1 and kept-vs-excluded kappa match a hand calculation", {
  # Twelve records, three eligible. The screener includes d1-d2, defers d3-d4
  # and excludes the rest; the person finds d1, d3 and d5 eligible.
  #
  # Kept (include + unclear) against excluded, screener in rows:
  #                eligible  not
  #   kept            2       2      a = 2, b = 2
  #   excluded        1       7      c = 1, d = 7      n = 12
  #
  # po    = (a + d) / n = 9/12 = 0.75
  # kappa: pe = (4 * 3 + 8 * 9) / 144 = 84/144
  #        kappa = (108 - 84) / (144 - 84) = 24/60 = 0.4
  # PABAK = 2 po - 1 = 0.5
  # AC1:   pi = (4 + 3) / 24 = 7/24, pe = 2 * (7/24) * (17/24) = 238/576
  #        AC1 = (432 - 238) / (576 - 238) = 194/338 = 97/169
  # PI = (a - d) / n = -5/12, BI = (b - c) / n = 1/12
  #
  # Strict include against the rest: a = 1, b = 1, c = 2, d = 8;
  #   pe = (2 * 3 + 10 * 9) / 144 = 96/144, kappa = (108 - 96) / (144 - 96) = 1/4.
  # The 0.6.0 kappa on three labels against two: po = 8/12,
  #   pe = (2 * 3 + 2 * 0 + 8 * 9) / 144 = 78/144, kappa = 18/66 = 3/11.
  scr <- screening_of(c("include", "include", "unclear", "unclear", rep("exclude", 8)))
  ref <- data.frame(document = paste0("d", 1:12, ".pdf"),
                    human_decision = c("include", "exclude", "include", "exclude",
                                       "include", rep("exclude", 7)),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all", min_positives = 1L)
  st <- function(a, s) a$stats$estimate[a$stats$statistic == s]
  kept <- cal$agreement$kept
  expect_equal(cal$kappa, 0.4, tolerance = 1e-12)
  expect_equal(st(kept, "kappa"), 0.4, tolerance = 1e-12)
  expect_equal(st(kept, "PABAK"), 0.5, tolerance = 1e-12)
  expect_equal(st(kept, "AC1"), 97 / 169, tolerance = 1e-12)
  expect_equal(st(kept, "prevalence index"), -5 / 12, tolerance = 1e-12)
  expect_equal(st(kept, "bias index"), 1 / 12, tolerance = 1e-12)
  expect_equal(st(kept, "sensitivity"), 2 / 3, tolerance = 1e-12)
  expect_equal(st(kept, "specificity"), 7 / 9, tolerance = 1e-12)
  expect_equal(st(kept, "PPV"), 0.5, tolerance = 1e-12)
  expect_equal(st(kept, "NPV"), 7 / 8, tolerance = 1e-12)
  expect_equal(st(cal$agreement$strict, "kappa"), 0.25, tolerance = 1e-12)
  expect_equal(cal$kappa_legacy, 3 / 11, tolerance = 1e-12)
  expect_false(kept$paradox)

  # The PABAK interval is the Wilson interval on po (9 of 12), mapped by 2p - 1.
  w <- harnessr:::prop_row("po", 9, 12)
  pabak <- kept$stats[kept$stats$statistic == "PABAK", ]
  expect_equal(c(pabak$lower, pabak$upper), 2 * c(w$lower, w$upper) - 1, tolerance = 1e-12)
  # Every chance-corrected figure has an interval around it.
  for (s in c("kappa", "PABAK", "AC1")) {
    r <- kept$stats[kept$stats$statistic == s, ]
    expect_true(r$lower <= r$estimate && r$estimate <= r$upper, info = s)
  }

  # Kappa is printed beside PABAK and AC1, with the 3x2 counts above them.
  out <- paste(capture.output(print(cal)), collapse = "\n")
  expect_match(out, "kappa +0\\.40")
  expect_match(out, "PABAK +0\\.50")
  expect_match(out, "AC1 +0\\.57")
  expect_match(out, "unclear +1 +1")
})

test_that("the agreement set on a 2x2 where nearly every record is positive", {
  # a = 90, b = 5, c = 3, d = 2, n = 100: agreement on 92 records and a kappa
  # of only 0.29, because almost everything is positive.
  #   po = 0.92, PABAK = 2 * 0.92 - 1 = 0.84
  #   kappa: pe = (95 * 93 + 5 * 7) / 100^2 = 0.887, (0.92 - 0.887) / 0.113
  #   AC1:   pi = (95 + 93) / 200 = 0.94, pe = 2 * 0.94 * 0.06 = 0.1128,
  #          (0.92 - 0.1128) / (1 - 0.1128)
  #   PI = (90 - 2) / 100 = 0.88, BI = (5 - 3) / 100 = 0.02
  a <- harnessr:::agreement_2x2(90, 5, 3, 2)
  st <- function(s) a$stats$estimate[a$stats$statistic == s]
  expect_equal(st("PABAK"), 0.84, tolerance = 1e-12)
  expect_equal(st("kappa"), 0.033 / 0.113, tolerance = 1e-12)
  expect_equal(st("AC1"), 0.8072 / 0.8872, tolerance = 1e-12)
  expect_equal(st("prevalence index"), 0.88, tolerance = 1e-12)
  expect_equal(st("bias index"), 0.02, tolerance = 1e-12)
  # abs(PI) above 0.8: the case the flag exists for.
  expect_true(a$paradox)

  # The kappa and AC1 standard errors from the linearised variance, checked by
  # hand for the AC1 at this table. With p the cell proportions and pi as
  # above, the sum over cells of p_kl (w_kl - 2 (1 - AC1)(1 - (pi_k + pi_l) / 2))^2
  # less (po - 2 (1 - AC1) pe)^2, over n (1 - pe)^2.
  ac1 <- st("AC1"); pe <- 0.1128; pik <- c(0.94, 0.06)
  p <- matrix(c(0.90, 0.03, 0.05, 0.02), 2)
  s1 <- 0
  for (k in 1:2) for (l in 1:2) {
    s1 <- s1 + p[k, l] * ((k == l) - 2 * (1 - ac1) * (1 - (pik[k] + pik[l]) / 2))^2
  }
  se <- sqrt((s1 - (0.92 - 2 * (1 - ac1) * pe)^2) / (100 * (1 - pe)^2))
  r <- a$stats[a$stats$statistic == "AC1", ]
  expect_equal(c(r$lower, r$upper), ac1 + c(-1, 1) * stats::qt(0.975, 99) * se,
               tolerance = 1e-10)
})

test_that("the kappa interval is a seeded document bootstrap, and never a point", {
  # Percentile bootstrap, B = 2000, resampling documents under a fixed seed:
  # the same table gives the same interval, and the caller's stream is kept.
  set.seed(42); before <- stats::runif(1)
  set.seed(42)
  a <- harnessr:::agreement_2x2(90, 5, 3, 2)
  after <- stats::runif(1)
  expect_identical(before, after)
  expect_identical(a, harnessr:::agreement_2x2(90, 5, 3, 2))
  expect_identical(a$bootstrap$B, 2000L)
  expect_true(is.numeric(a$bootstrap$seed))
  k <- a$stats[a$stats$statistic == "kappa", ]
  expect_true(k$lower < k$estimate && k$estimate < k$upper)
  expect_true(is.na(a$note))

  # Perfect agreement: every resample agrees completely too, so an interval
  # would be [1, 1] from 31 records. There is none, and the note says why.
  for (cells in list(c(1, 0, 0, 30), c(10, 0, 0, 10), c(3, 0, 0, 0))) {
    p <- do.call(harnessr:::agreement_2x2, as.list(cells))
    st <- p$stats[p$stats$statistic %in% c("kappa", "AC1"), ]
    zero_width <- !is.na(st$lower) & !is.na(st$upper) & st$lower == st$upper
    expect_false(any(zero_width), info = paste(cells, collapse = " "))
    expect_true(all(is.na(st$lower) & is.na(st$upper)), info = paste(cells, collapse = " "))
    expect_match(p$note, "agree on every record")
  }
  # Complete disagreement, the same.
  dis <- harnessr:::agreement_2x2(0, 3, 4, 0)
  expect_true(all(is.na(dis$stats$lower[dis$stats$statistic %in% c("kappa", "AC1")])))
  # And too few records to say anything.
  few <- harnessr:::agreement_2x2(2, 1, 1, 2)
  expect_true(all(is.na(few$stats$lower[few$stats$statistic %in% c("kappa", "AC1")])))
  expect_match(few$note, "at least 10")

  # A calibration that agrees everywhere prints no [1.00, 1.00].
  scr <- screening_of(c(rep("include", 3), rep("exclude", 9)))
  ref <- data.frame(document = paste0("d", 1:12, ".pdf"),
                    human_decision = c(rep("include", 3), rep("exclude", 9)),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all", min_positives = 1L)
  out <- paste(capture.output(print(cal)), collapse = "\n")
  expect_false(grepl("[1.00, 1.00]", out, fixed = TRUE))
  expect_match(out, "no kappa or AC1 interval")
})

test_that("the 3x2 counts print on a sample of one stratum too", {
  scr <- screening_of(c(rep("exclude", 4), "include", "unclear"))
  ref <- data.frame(document = c("d5.pdf", "d6.pdf"), human_decision = c("include", "include"),
                    stringsAsFactors = FALSE)
  cal <- suppressWarnings(gr_calibrate(scr, ref, of = "kept", min_positives = 1L))
  expect_null(cal$agreement)
  out <- paste(capture.output(print(cal)), collapse = "\n")
  expect_match(out, "include +1 +0")
  expect_match(out, "unclear +1 +0")
  expect_match(out, "exclude +0 +0")
})

test_that("a sample of exclusions reports what was lost, not a sensitivity", {
  # THE trap. Every row in this frame was excluded by the model, so sensitivity
  # computes to 0% and specificity to 100% -- both artifacts of where the sample
  # came from, both alarming or flattering, neither a fact about the screener.
  scr <- screening_of(c(rep("exclude", 85), rep("include", 10), rep("unclear", 5)))
  ref <- gr_reference(scr, n = 20, of = "excluded", seed = 1)
  ref$human_decision <- c(rep("exclude", 18), "include", "include")
  cal <- suppressWarnings(gr_calibrate(scr, ref))

  expect_setequal(cal$metrics$metric, c("eligible among the excluded", "correctly excluded"))
  expect_false(any(grepl("sensitivity", cal$metrics$metric)))
  expect_false(any(grepl("specificity", cal$metrics$metric)))
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "eligible among the excluded"], 0.1)
  # Kappa needs both raters to use both labels; here the model said one thing
  # throughout, so it would be arithmetic on a constant.
  expect_true(is.na(cal$kappa))
  expect_null(cal$agreement)
  expect_true(is.na(cal$kappa_legacy))

  # The number somebody actually acts on: what the rate implies for the whole
  # discarded pile. 10% of 85.
  expect_equal(cal$projected$frame_n, 85L)
  expect_equal(cal$projected$lost, 8.5)
  expect_lt(cal$projected$lower, cal$projected$upper)
  expect_output(print(cal), "eligible studies lost")
  expect_output(print(cal), "sampled from exclusions only")
})

test_that("a sample of kept records reports what is worth keeping, not a sensitivity", {
  scr <- screening_of(c(rep("exclude", 20), rep("include", 8), rep("unclear", 2)))
  ref <- gr_reference(scr, n = Inf, of = "kept")
  expect_equal(nrow(ref), 10L)
  ref$human_decision <- c(rep("include", 6), rep("exclude", 4))
  # No `of =` here: the frame comes from gr_reference() and must survive as an
  # attribute, which is half of what this test is about.
  cal <- gr_calibrate(scr, ref)

  expect_setequal(cal$metrics$metric, c("eligible among those kept", "deferred to a person"))
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "eligible among those kept"], 0.6)
  expect_null(cal$projected)
  expect_output(print(cal), "sampled from kept records only")
})

test_that("the frame survives a CSV, because that is what gets emailed and read back", {
  # An attribute does not survive write.csv, Excel, and a fortnight. Without the
  # frame the misleading metrics come back: an exclusions sample would report
  # sensitivity 0% and specificity 100%.
  scr <- screening_of(c(rep("exclude", 50), rep("include", 8), rep("unclear", 2)))
  f <- withr::local_tempfile(fileext = ".csv")
  quiet(gr_reference(scr, n = 10, of = "excluded", seed = 1, path = f))

  d <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_true(all(c("document", "human_decision", "sampled_from") %in% names(d)))
  # Blind by default: a person shown the model's answer agrees with it.
  expect_false("model_decision" %in% names(d))
  expect_true(all(is.na(d$human_decision) | !nzchar(d$human_decision)))

  d$human_decision <- c(rep("exclude", 9), "include")
  utils::write.csv(d, f, row.names = FALSE, na = "")
  cal <- suppressWarnings(gr_calibrate(scr, f))
  expect_identical(cal$frame$of, "excluded")
  expect_equal(cal$frame$frame_n, 50L)
  expect_false(any(grepl("sensitivity", cal$metrics$metric)))
})

test_that("the sample is reproducible, and blind can be turned off deliberately", {
  scr <- screening_of(c(rep("exclude", 40), rep("include", 10)))
  expect_identical(gr_reference(scr, n = 8, seed = 42)$document,
                   gr_reference(scr, n = 8, seed = 42)$document)
  expect_false(identical(gr_reference(scr, n = 8, seed = 42)$document,
                         gr_reference(scr, n = 8, seed = 7)$document))
  # Asking for more than exists takes the frame, rather than erroring.
  expect_equal(nrow(gr_reference(scr, n = 999, of = "kept")), 10L)
  expect_true("model_decision" %in% names(gr_reference(scr, n = 5, blind = FALSE, seed = 1)))
  expect_error(gr_reference(screening_of(rep("include", 3)), of = "excluded"),
               class = "gr_no_reference_frame")
})

test_that("an unfilled row is not an exclusion, and a bad one is not guessed at", {
  scr <- screening_of(c("include", "exclude", "exclude", "include"))
  ref <- data.frame(document = paste0("d", 1:4, ".pdf"),
                    human_decision = c("include", NA, "", "exclude"),
                    stringsAsFactors = FALSE)
  expect_warning(cal <- gr_calibrate(scr, ref, of = "all"), class = "gr_reference_incomplete")
  expect_equal(cal$n, 2L)          # the two that were actually judged

  bad <- data.frame(document = "d1.pdf", human_decision = "maybe", stringsAsFactors = FALSE)
  expect_error(gr_calibrate(scr, bad), class = "gr_bad_reference")

  # A reference naming documents this run does not contain is two different
  # runs, and comparing them would produce a number about nothing.
  other <- data.frame(document = "somewhere-else.pdf", human_decision = "include",
                      stringsAsFactors = FALSE)
  expect_error(gr_calibrate(scr, other), class = "gr_reference_mismatch")
  expect_error(gr_calibrate(scr, data.frame(document = "d1.pdf")), class = "gr_bad_reference")
})

test_that("a document that was never read is left out of the comparison", {
  # NA is the absence of a judgement, not an exclusion. Counting it as one would
  # charge the screener for a document it never saw.
  scr <- screening_of(c("include", NA, "exclude", "include"))
  ref <- data.frame(document = paste0("d", 1:4, ".pdf"),
                    human_decision = c("include", "include", "exclude", "include"),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all")
  expect_equal(cal$n, 3L)
  expect_equal(cal$n_positives, 2L)
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "sensitivity (as deployed)"], 1)
})

test_that("too few eligible studies is said out loud rather than printed as a rate", {
  # "100%" from two observations is not a finding, and it is exactly the figure
  # somebody would quote.
  scr <- screening_of(c("include", "include", rep("exclude", 8)))
  ref <- data.frame(document = paste0("d", 1:10, ".pdf"),
                    human_decision = c("include", "include", rep("exclude", 8)),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all")
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "sensitivity (as deployed)"], 1)
  expect_false(cal$adequate)
  expect_equal(cal$n_positives, 2L)
  expect_output(print(cal), "Hand-screen more")
  # The interval says the same thing in numbers.
  sens <- cal$metrics[cal$metrics$metric == "sensitivity (as deployed)", ]
  expect_lt(sens$lower, 0.5)

  # Enough eligible studies, and it stops complaining.
  big <- screening_of(c(rep("include", 12), rep("exclude", 20)))
  ref2 <- data.frame(document = paste0("d", 1:32, ".pdf"),
                     human_decision = c(rep("include", 12), rep("exclude", 20)),
                     stringsAsFactors = FALSE)
  expect_true(gr_calibrate(big, ref2, of = "all")$adequate)
})

test_that("duplicates are not screened twice into the calibration", {
  tab <- data.frame(document = paste0("d", 1:4, ".pdf"),
                    decision = c("include", "include", "exclude", "exclude"),
                    duplicate_of = c(NA, "d1.pdf", NA, NA), stringsAsFactors = FALSE)
  scr <- structure(list(table = tab), class = "gr_screening")
  expect_equal(nrow(gr_reference(scr, n = Inf, of = "all")), 3L)
})
