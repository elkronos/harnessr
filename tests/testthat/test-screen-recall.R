# test-screen-recall.R: design-weighted recall on a stacked reference, its
# exact bounds, and the sample sizes that make a recall target reachable.
#
# Reference values are worked by hand from the hypergeometric distribution
# and stored as literals, with the phyper() values that place each bound
# checked beside them.

recall_run <- function(n_kept = 20, n_excl = 80) {
  dec <- c(rep("include", n_kept - 5), rep("unclear", 5), rep("exclude", n_excl))
  tab <- data.frame(document = sprintf("d%03d.pdf", seq_along(dec)), decision = dec,
                    reason = "because", stringsAsFactors = FALSE)
  structure(list(table = tab), class = "gr_screening")
}

# Every kept record judged, 12 of the 20 eligible; 20 of the 80 exclusions
# judged, with `x_excl` of them eligible.
stacked_ref <- function(scr, x_excl = 1) {
  ref <- gr_reference(scr, n = 20, of = "stacked", seed = 1, blind = FALSE)
  ref$human_decision <- "exclude"
  ref$human_decision[ref$stratum == "kept"][1:12] <- "include"
  if (x_excl > 0) ref$human_decision[ref$stratum == "excluded"][seq_len(x_excl)] <- "include"
  ref
}

test_that("a stacked reference takes every kept record and records inclusion probabilities", {
  scr <- recall_run()
  ref <- gr_reference(scr, n = 20, of = "stacked", seed = 1, blind = FALSE)
  expect_identical(nrow(ref), 40L)
  expect_identical(sum(ref$stratum == "kept"), 20L)
  expect_true(all(ref$inclusion_prob[ref$stratum == "kept"] == 1))
  expect_true(all(ref$inclusion_prob[ref$stratum == "excluded"] == 0.25))
  expect_identical(unique(ref$frame_n[ref$stratum == "excluded"]), 80L)
  expect_identical(unique(ref$sampled_from), "stacked")
  # Rows in the run's order, so position does not give the stratum away.
  expect_identical(ref$document, sort(ref$document))
  # The same draw under `frame =`, the name gr_screen_sample_size() uses.
  expect_identical(gr_reference(scr, n = 20, frame = "stacked", seed = 1, blind = FALSE)$document,
                   ref$document)
  expect_error(gr_reference(scr, of = "kept", frame = "stacked"), class = "gr_bad_setting")
})

test_that("a blind stacked sheet hides each row's stratum and reads back the same", {
  scr <- recall_run()
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  blind <- suppressMessages(gr_reference(scr, n = 20, of = "stacked", seed = 1, path = f))
  expect_false(any(c("stratum", "inclusion_prob", "frame_n", "model_decision") %in% names(blind)))
  # One key per row, all of one length whatever the stratum.
  expect_identical(length(unique(blind$sampled_from)), 40L)
  expect_length(unique(nchar(blind$sampled_from)), 1L)
  key <- harnessr:::frame_unkey(blind$sampled_from[1])
  expect_identical(key$of, "stacked")

  open <- stacked_ref(scr)
  d <- utils::read.csv(f, stringsAsFactors = FALSE)
  d$human_decision <- open$human_decision[match(d$document, open$document)]
  utils::write.csv(d, f, row.names = FALSE, na = "")
  expect_equal(gr_calibrate(scr, f)$recall, gr_calibrate(scr, open)$recall)
})

test_that("recall on a stacked reference and its exact bound match a hand calculation", {
  # K = 12 eligible among the 20 kept (all judged). x = 1 eligible in n = 20
  # of the N = 80 exclusions. M = 80 * 1 / 20 = 4, recall = 12 / 16 = 0.75.
  # One-sided 95% upper bound on M: the largest D with P(X <= 1) > 0.05,
  # P(X <= 1 | D = 15) = 0.0603 and P(X <= 1 | D = 16) = 0.0450, so M_U = 15
  # and the recall bound is 12 / 27.
  expect_equal(stats::phyper(1, 15, 65, 20), 0.06029535, tolerance = 1e-7)
  expect_equal(stats::phyper(1, 16, 64, 20), 0.04501373, tolerance = 1e-7)
  scr <- recall_run()
  cal <- gr_calibrate(scr, stacked_ref(scr))
  expect_s3_class(cal, "gr_calibration")
  expect_identical(cal$frame$of, "stacked")
  expect_equal(cal$recall$estimate, 0.75)
  expect_equal(cal$recall$bound, 12 / 27)
  expect_identical(cal$recall$method, "hypergeometric")
  expect_equal(cal$lost$estimate, 4)
  expect_equal(cal$lost$bound, 15)
  # Two-sided at 95%: M from 1 to 17 (alpha / 2 on each side).
  expect_equal(c(cal$lost$lower, cal$lost$upper), c(1, 17))
  expect_equal(c(cal$recall$lower, cal$recall$upper), c(12 / 29, 12 / 13))
  expect_equal(cal$false_exclusion$estimate, 0.05)
  expect_equal(c(cal$false_exclusion$lower, cal$false_exclusion$upper), c(1 / 80, 17 / 80))
  expect_equal(cal$work_saved$estimate, 0.8)
  expect_equal(cal$unclear_rate$estimate, 0.05)
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "sensitivity (as deployed)"], 0.75)
  expect_false(cal$verdict$met)
  expect_false(cal$adequate)
  expect_identical(cal$adequacy$rule, "recall target")
  expect_null(cal$agreement)
  # The point estimate is the ratio of Horvitz-Thompson totals.
  st <- cal$strata
  expect_equal(st$estimate, c(12, 4))
  expect_equal(st$inclusion_prob, c(1, 0.25))
  out <- paste(capture.output(print(cal)), collapse = "\n")
  expect_match(out, "recall 75.0%", fixed = TRUE)
  expect_match(out, "not met", fixed = TRUE)
})

test_that("no misses in the excluded sample still gives a recall bound below 1", {
  # x = 0: P(X = 0 | D = 9) > 0.05 >= P(X = 0 | D = 10), so M_U = 9 and the
  # bound is 12 / 21. A bootstrap would give [1, 1] here.
  expect_true(stats::phyper(0, 9, 71, 20) > 0.05)
  expect_true(stats::phyper(0, 10, 70, 20) <= 0.05)
  scr <- recall_run()
  cal <- gr_calibrate(scr, stacked_ref(scr, x_excl = 0))
  expect_equal(cal$recall$estimate, 1)
  expect_equal(cal$recall$bound, 12 / 21)
  expect_true(cal$recall$bound < 1)
  expect_true(cal$recall$lower < 1)
  expect_equal(cal$lost$bound, 9)
  expect_false(cal$verdict$met)
  # Allowed to lose up to 9, the same sample meets the target.
  ok <- gr_calibrate(scr, stacked_ref(scr, x_excl = 0), max_lost = 9)
  expect_true(ok$verdict$met)
  expect_true(ok$adequate)
  expect_identical(ok$verdict$rule, "recall bound or lost bound")
  expect_false(gr_calibrate(scr, stacked_ref(scr, x_excl = 0), max_lost = 8)$verdict$met)
  # A lower target the bound clears.
  expect_true(gr_calibrate(scr, stacked_ref(scr, x_excl = 0), recall_target = 0.5)$verdict$met)
})

test_that("kept and excluded sheets stacked by hand need of = 'stacked'", {
  scr <- recall_run()
  open <- stacked_ref(scr)
  k <- as.data.frame(gr_reference(scr, n = Inf, of = "kept", blind = FALSE))
  e <- as.data.frame(gr_reference(scr, n = 20, of = "excluded", seed = 1, blind = FALSE))
  both <- rbind(k, e)
  both$human_decision <- open$human_decision[match(both$document, open$document)]
  expect_error(gr_calibrate(scr, both), class = "gr_mixed_frame")
  cal <- expect_silent(gr_calibrate(scr, both, of = "stacked"))
  expect_equal(cal$recall, gr_calibrate(scr, open)$recall)
})

test_that("a sampled kept stratum splits alpha between the strata", {
  # Kept: N = 20, n = 10, x = 6. Excluded: N = 80, n = 20, x = 0.
  # Bonferroni: alpha / 2 = 0.025 for each. Lower bound on the kept count:
  # the smallest D with P(X >= 6) > 0.025 is 7; upper bound on the excluded
  # count: the largest D with P(X = 0) > 0.025 is 11. Recall bound 7 / 18.
  expect_true(stats::phyper(5, 7, 13, 10, lower.tail = FALSE) > 0.025)
  expect_true(stats::phyper(5, 6, 14, 10, lower.tail = FALSE) <= 0.025)
  expect_true(stats::phyper(0, 11, 69, 20) > 0.025)
  expect_true(stats::phyper(0, 12, 68, 20) <= 0.025)
  scr <- recall_run()
  docs <- scr$table$document
  ref <- data.frame(document = c(docs[1:10], docs[21:40]),
                    human_decision = c(rep("include", 6), rep("exclude", 4), rep("exclude", 20)),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "stacked")
  expect_equal(cal$recall$estimate, 1)
  expect_equal(cal$recall$bound, 7 / 18)
  expect_identical(cal$recall$method, "hypergeometric, Bonferroni over strata")
})

test_that("a stacked reference without a stratum, or with the wrong weights, says so", {
  scr <- recall_run()
  ref <- stacked_ref(scr)
  only_kept <- ref[ref$stratum == "kept", ]
  expect_error(gr_calibrate(scr, only_kept, of = "stacked"), class = "gr_bad_reference")
  bad <- ref
  bad$inclusion_prob[bad$stratum == "excluded"] <- 0.5
  expect_warning(gr_calibrate(scr, bad), class = "gr_inclusion_mismatch")
  wrong <- ref
  wrong$stratum[1] <- "excluded"
  expect_error(gr_calibrate(scr, wrong), class = "gr_reference_mismatch")
})

test_that("blank rows in a stacked sheet part the weights from the recorded probabilities", {
  scr <- recall_run()
  # Five of the 20 exclusions left blank: 15 / 80 = 0.1875 is used, the sheet
  # says 0.25.
  ref <- stacked_ref(scr)
  ref$human_decision[ref$stratum == "excluded"][16:20] <- NA
  w <- character()
  cal <- withCallingHandlers(gr_calibrate(scr, ref), warning = function(cnd) {
    w <<- c(w, class(cnd)[1])
    invokeRestart("muffleWarning")
  })
  expect_true("gr_inclusion_mismatch" %in% w)
  expect_equal(cal$strata$inclusion_prob[cal$strata$stratum == "excluded"], 0.1875)
  # One kept row blank: 19 / 20 used against a recorded 1.
  kb <- stacked_ref(scr)
  kb$human_decision[kb$stratum == "kept"][20] <- NA
  w <- character()
  withCallingHandlers(gr_calibrate(scr, kb), warning = function(cnd) {
    w <<- c(w, class(cnd)[1])
    invokeRestart("muffleWarning")
  })
  expect_true("gr_inclusion_mismatch" %in% w)
})

test_that("a sample of everything bounds recall with Clopper-Pearson", {
  # 18 of 20 eligible kept: the one-sided 95% lower bound is
  # binom.test(18, 20, alternative = "greater")$conf.int[1] = 0.7173815.
  dec <- c(rep("include", 18), rep("exclude", 2), rep("exclude", 30))
  scr <- structure(list(table = data.frame(document = sprintf("a%02d", 1:50), decision = dec,
                                           stringsAsFactors = FALSE)), class = "gr_screening")
  ref <- data.frame(document = sprintf("a%02d", 1:50),
                    human_decision = c(rep("include", 20), rep("exclude", 30)),
                    stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all")
  expect_equal(cal$recall$estimate, 0.9)
  expect_equal(cal$recall$bound, 0.7173815, tolerance = 1e-6)
  expect_identical(cal$recall$method, "clopper_pearson")
  expect_false(cal$verdict$met)
  # The figures that were there before are as they were.
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "sensitivity (as deployed)"], 0.9)
  expect_identical(cal$adequacy$rule, "positives")
})

test_that("a sample of one stratum does not claim a recall", {
  scr <- recall_run()
  ex <- gr_reference(scr, n = 20, of = "excluded", seed = 1)
  ex$human_decision <- "exclude"
  cal <- gr_calibrate(scr, ex)
  expect_true(is.na(cal$recall$estimate))
  expect_match(cal$recall$note, "stacked", fixed = TRUE)
  expect_equal(cal$lost$bound, 9)
  expect_true(is.na(cal$verdict$met))
  expect_true(gr_calibrate(scr, ex, max_lost = 9)$verdict$met)
  expect_identical(cal$adequacy$rule, "interval")
})

test_that("the zero-failure sample size is ln(alpha) / ln(T)", {
  expect_identical(gr_screen_sample_size(0.95, 0.95)$positives, 59)
  expect_identical(gr_screen_sample_size(0.90, 0.95)$positives, 29)
  expect_identical(gr_screen_sample_size(0.99, 0.95)$positives, 299)
  expect_identical(gr_screen_sample_size(0.95, 0.95, prevalence = 0.05)$n, 1180)
  # The size that clears the target: 0.05^(1/59) is above 0.95, 0.05^(1/58) is not.
  expect_true(0.05^(1 / 59) >= 0.95 && 0.05^(1 / 58) < 0.95)
  expect_error(gr_screen_sample_size(1), class = "gr_bad_setting")
  expect_error(gr_screen_sample_size(frame = "kept"), class = "gr_bad_setting")
  expect_error(gr_screen_sample_size(frame = "excluded"), class = "gr_bad_setting")
})

test_that("the excluded-frame sample size uses the finite frame", {
  # u = 90 / 9000 = 1%: the binomial rule asks for 299. Exactly, a frame with
  # 91 eligible shows none in n draws with probability
  # phyper(0, 91, 8909, n): 0.0505266 at n = 289 and 0.0499988 at 290.
  expect_equal(stats::phyper(0, 91, 8909, 289), 0.0505266, tolerance = 1e-6)
  expect_equal(stats::phyper(0, 91, 8909, 290), 0.0499988, tolerance = 1e-6)
  s <- gr_screen_sample_size(frame = "excluded", max_lost = 90, frame_n = 9000)
  expect_identical(s$n_binomial, 299)
  expect_identical(s$n_exact, 290)
  expect_identical(s$n, 290)
  # The worked example: K = 285 kept eligible, 9000 exclusions, T = 0.95,
  # so at most 15 lost; ln(0.05) / ln(1 - 15 / 9000) = 1795.9 gives 1796.
  st <- gr_screen_sample_size(frame = "stacked", max_lost = 15, frame_n = 9000)
  expect_identical(st$n_binomial, 1796)
  expect_true(st$n_exact < st$n_binomial)
  # The exact size is the one gr_calibrate() certifies with.
  d <- 16
  expect_true(stats::phyper(0, d, 9000 - d, st$n_exact) <= 0.05)
  expect_true(stats::phyper(0, d, 9000 - d, st$n_exact - 1) > 0.05)
})

test_that("a sample of everything uses the finite frame when its size is given", {
  # 5% of 500 records gives E = 25 eligible; T = 0.95 allows m = 1 missed, so
  # a frame with 2 missed must show neither with probability at most 0.05:
  # phyper(0, 2, 498, n) is 0.0507255 at n = 387 and 0.0498277 at 388.
  expect_equal(stats::phyper(0, 2, 498, 387), 0.0507255, tolerance = 1e-6)
  expect_equal(stats::phyper(0, 2, 498, 388), 0.0498277, tolerance = 1e-6)
  s <- gr_screen_sample_size(0.95, 0.95, prevalence = 0.05, frame_n = 500)
  expect_identical(s$n_binomial, 1180)
  expect_identical(s$n_exact, 388)
  expect_identical(s$n, 388)
  # Without the frame size the binomial draw stands.
  b <- gr_screen_sample_size(0.95, 0.95, prevalence = 0.05)
  expect_identical(b$n, 1180)
  expect_true(is.na(b$n_exact))
})

test_that("reviewers > 1 gives one decision column per reviewer", {
  scr <- recall_run()
  ref <- gr_reference(scr, n = 3, of = "excluded", seed = 1, reviewers = 2)
  expect_identical(nrow(ref), 3L)
  expect_true(all(c("human_decision_1", "human_decision_2", "consensus") %in% names(ref)))
  expect_identical(ref$document, gr_reference(scr, n = 3, of = "excluded", seed = 1)$document)
  expect_error(gr_reference(scr, reviewers = 0), class = "gr_bad_setting")
})
