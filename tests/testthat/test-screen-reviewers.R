# References judged by several reviewers: the sheet, the consensus rules,
# human-human agreement and each reviewer against the consensus. Every
# expected value below is worked out by hand in the comments beside it.

rv_screening <- function(decision, prefix = "d") {
  tab <- data.frame(document = paste0(prefix, seq_along(decision), ".pdf"), decision = decision,
                    stringsAsFactors = FALSE)
  structure(list(table = tab), class = "gr_screening")
}

# Twelve records, all judged by three reviewers (I include, E exclude):
#
#   doc  1  2  3  4  5  6  7  8  9 10 11 12
#   r1   I  I  I  E  I  E  E  I  E  E  E  E
#   r2   I  I  E  E  I  E  E  I  E  I  E  E
#   r3   I  E  I  E  I  E  E  E  E  E  E  E
#
# They disagree on 2, 3, 8 and 10. Majority: 2, 3 and 8 include, 10 exclude,
# so the eligible records are 1, 2, 3, 5 and 8. Any include adds 10.
rv_r1 <- c("include", "include", "include", "exclude", "include", "exclude",
           "exclude", "include", "exclude", "exclude", "exclude", "exclude")
rv_r2 <- c("include", "include", "exclude", "exclude", "include", "exclude",
           "exclude", "include", "exclude", "include", "exclude", "exclude")
rv_r3 <- c("include", "exclude", "include", "exclude", "include", "exclude",
           "exclude", "exclude", "exclude", "exclude", "exclude", "exclude")

rv_sheet <- function(times = 1L) {
  scr <- rv_screening(rep(c(rep("include", 4), "unclear", rep("exclude", 7)), times))
  ref <- gr_reference(scr, n = Inf, of = "all", seed = 1, reviewers = 3, blind = FALSE)
  ref$human_decision_1 <- rep(rv_r1, times)
  ref$human_decision_2 <- rep(rv_r2, times)
  ref$human_decision_3 <- rep(rv_r3, times)
  list(scr = scr, ref = ref)
}

test_that("reviewers = k writes one decision column per reviewer and one row per document", {
  scr <- rv_screening(c(rep("include", 3), rep("exclude", 9)))
  ref <- gr_reference(scr, n = 4, of = "excluded", seed = 1, reviewers = 3)
  expect_identical(nrow(ref), 4L)
  expect_false(anyDuplicated(ref$document) > 0)
  expect_true(all(c("human_decision_1", "human_decision_2", "human_decision_3",
                    "consensus") %in% names(ref)))
  expect_false("human_decision" %in% names(ref))
  expect_true(all(is.na(ref$human_decision_2)))
  # One reviewer is the sheet it always was.
  one <- gr_reference(scr, n = 4, of = "excluded", seed = 1)
  expect_true("human_decision" %in% names(one))
  expect_false(any(grepl("^human_decision_|^consensus$", names(one))))
  expect_identical(one$document, ref$document)
})

test_that("the three consensus rules settle disagreements as documented", {
  s <- rv_sheet()
  maj <- gr_reference_consensus(s$ref, "majority")
  expect_identical(maj$human_decision,
                   c("include", "include", "include", "exclude", "include", "exclude",
                     "exclude", "include", "exclude", "exclude", "exclude", "exclude"))
  expect_identical(maj$consensus_from[c(1, 2, 3, 8, 10)],
                   c("unanimous", "majority", "majority", "majority", "majority"))
  expect_identical(attr(maj, "conflicts"), 4L)

  any_inc <- gr_reference_consensus(s$ref, "any_include")
  expect_identical(which(any_inc$human_decision == "include"), c(1L, 2L, 3L, 5L, 8L, 10L))
  expect_identical(any_inc$consensus_from[10], "any include")

  # Adjudicated: stops on a disagreement nobody settled, naming the count.
  expect_error(gr_reference_consensus(s$ref, "adjudicated"), "4 of 12 document",
               class = "gr_reference_conflict")
  ref <- s$ref
  ref$consensus[c(2, 3, 8, 10)] <- c("exclude", "include", "exclude", "include")
  adj <- gr_reference_consensus(ref, "adjudicated")
  expect_identical(which(adj$human_decision == "include"), c(1L, 3L, 5L, 10L))
  expect_identical(adj$consensus_from[c(2, 4)], c("adjudicated", "unanimous"))

  # Two reviewers: every disagreement is a tie, settled as include unless an
  # adjudicator settled it.
  two <- data.frame(document = paste0("d", 1:3, ".pdf"),
                    human_decision_a = c("include", "include", "exclude"),
                    human_decision_b = c("exclude", "exclude", "exclude"),
                    consensus = c(NA, "exclude", NA), stringsAsFactors = FALSE)
  t2 <- gr_reference_consensus(two, "majority")
  expect_identical(t2$human_decision, c("include", "exclude", "exclude"))
  expect_identical(t2$consensus_from, c("tie kept", "adjudicated", "unanimous"))

  # A blank is no decision: one reviewer's word stands, none leaves it blank.
  gap <- data.frame(document = c("x.pdf", "y.pdf"), human_decision_1 = c("include", NA),
                    human_decision_2 = c(NA, NA), stringsAsFactors = FALSE)
  g <- gr_reference_consensus(gap, "majority")
  expect_identical(g$human_decision, c("include", NA))
  expect_identical(g$consensus_from, c("one reviewer", "no decision"))

  expect_error(gr_reference_consensus(data.frame(document = "a", human_decision = "include")),
               class = "gr_bad_reference")
  bad <- s$ref
  bad$human_decision_2[1] <- "maybe"
  expect_error(gr_reference_consensus(bad), "human_decision_2", class = "gr_bad_reference")
})

test_that("note and date columns beside the decisions are not read as reviewers", {
  s <- rv_sheet()
  ref <- s$ref
  ref$human_decision_notes <- "second pass"
  ref$human_decision_date <- "2026-11-01"
  maj <- gr_reference_consensus(ref, "majority")
  expect_identical(harnessr:::reviewer_columns(maj),
                   c("human_decision_1", "human_decision_2", "human_decision_3"))
  expect_identical(which(maj$human_decision == "include"), c(1L, 2L, 3L, 5L, 8L))
  expect_identical(maj$human_decision_notes, rep("second pass", 12))
  # A long sheet whose reviewer id would make such a name is refused.
  long <- data.frame(document = c("a.pdf", "a.pdf"), reviewer = c("1", "notes"),
                     human_decision = c("include", "exclude"), stringsAsFactors = FALSE)
  expect_error(gr_reference_consensus(long, "majority"), "Reviewer 'notes'",
               class = "gr_bad_reference")
})

test_that("a long sheet, one row per document per reviewer, is read the same way", {
  s <- rv_sheet()
  long <- data.frame(document = rep(s$ref$document, 3), reviewer = rep(1:3, each = 12),
                     human_decision = c(rv_r1, rv_r2, rv_r3), stringsAsFactors = FALSE)
  wide <- gr_reference_consensus(s$ref, "majority")
  from_long <- gr_reference_consensus(long, "majority")
  expect_identical(from_long$human_decision, wide$human_decision)
  expect_identical(from_long$human_decision_3, rv_r3)
  # The same reviewer judging a record twice, differently, is refused.
  twice <- rbind(long, data.frame(document = s$ref$document[1], reviewer = 1,
                                  human_decision = "exclude"))
  expect_error(gr_reference_consensus(twice), class = "gr_reference_conflict")
})

test_that("gr_calibrate stops on an unsettled disagreement and reports reviewers otherwise", {
  s <- rv_sheet()
  expect_error(gr_calibrate(s$scr, s$ref), "4 of 12", class = "gr_reference_conflict")
  cal <- gr_calibrate(s$scr, gr_reference_consensus(s$ref, "majority"))
  r <- cal$reviewers
  expect_identical(r$reviewers, c("1", "2", "3"))
  expect_identical(r$rule, "majority")
  expect_identical(r$conflicts, 4L)
  expect_false(r$weighted)
  # The screener is compared with the consensus: eligible 1, 2, 3, 5 and 8;
  # it kept 1 to 5 and excluded 8.
  expect_identical(cal$counts, c(tp = 4L, fn = 1L, fp = 1L, tn = 6L))

  ag <- r$agreement
  get <- function(pair, stat) ag$estimate[ag$pair == pair & ag$statistic == stat]
  # Reviewers 1 and 2: both include 1, 2, 5, 8 (a = 4); 1 only on 3 (b = 1);
  # 2 only on 10 (c = 1); both exclude the other 6 (d = 6); n = 12.
  # po = 10/12; each includes 5/12, so pe = (5/12)^2 + (7/12)^2 = 74/144 and
  # kappa = (120 - 74) / (144 - 74) = 46/70. PABAK = 2 po - 1 = 2/3.
  # AC1: q = 5/12, pe_g = 2 q (1 - q) = 70/144, AC1 = (120 - 70)/(144 - 70) = 50/74.
  # PI = (a - d)/n = -2/12, BI = (b - c)/n = 0.
  expect_equal(get("1 vs 2", "observed agreement"), 10 / 12)
  expect_equal(get("1 vs 2", "kappa"), 46 / 70)
  expect_equal(get("1 vs 2", "PABAK"), 2 / 3)
  expect_equal(get("1 vs 2", "AC1"), 50 / 74)
  expect_equal(get("1 vs 2", "prevalence index"), -1 / 6)
  expect_equal(get("1 vs 2", "bias index"), 0)
  # Reviewers 2 and 3: a = 2 (1, 5), b = 3 (2, 8, 10), c = 1 (3), d = 6.
  # po = 8/12; pe = (5/12)(3/12) + (7/12)(9/12) = 78/144; kappa = 18/66.
  # q = 8/24 = 1/3, pe_g = 4/9, AC1 = (2/3 - 4/9)/(5/9) = 0.4.
  # PI = (2 - 6)/12, BI = (3 - 1)/12.
  expect_equal(get("2 vs 3", "kappa"), 18 / 66)
  expect_equal(get("2 vs 3", "AC1"), 0.4)
  expect_equal(get("2 vs 3", "prevalence index"), -1 / 3)
  expect_equal(get("2 vs 3", "bias index"), 1 / 6)
  # Kappa is never the only figure for a pair.
  expect_true(all(c("kappa", "PABAK", "AC1", "prevalence index", "bias index") %in%
                    ag$statistic[ag$pair == "2 vs 3"]))
  # Twelve items is below alpha's 30, so percent agreement stands in: 8
  # unanimous items give 6 agreeing ordered pairs each, the 4 split ones 2
  # each, out of 12 x 6 = 72 pairs: (48 + 8) / 72.
  expect_equal(get("all reviewers", "percent agreement"), 56 / 72)
  expect_true(is.na(get("all reviewers", "Krippendorff's alpha")))

  # Each reviewer against the majority consensus (eligible 1, 2, 3, 5, 8).
  # Reviewer 1 includes exactly those: 5/5 and 7/7. Reviewer 2 includes
  # 1, 2, 5, 8 and 10: 4/5, and excludes 6 of the 7 others. Reviewer 3
  # includes 1, 3, 5: 3/5, and every one of the 7.
  se <- r$sensitivity
  val <- function(id, stat, col = "estimate") se[[col]][se$reviewer == id & se$statistic == stat]
  expect_equal(val("1", "sensitivity"), 1)
  expect_equal(val("1", "specificity"), 1)
  expect_equal(val("2", "sensitivity"), 4 / 5)
  expect_equal(val("2", "specificity"), 6 / 7)
  expect_equal(val("3", "sensitivity"), 3 / 5)
  expect_equal(val("3", "specificity"), 1)
  # Wilson intervals, as prop.test(x, n, correct = FALSE) gives them.
  expect_equal(c(val("2", "sensitivity", "lower"), val("2", "sensitivity", "upper")),
               c(0.3755346, 0.9637759), tolerance = 1e-6)
  expect_equal(c(val("2", "specificity", "lower"), val("2", "specificity", "upper")),
               c(0.4868722, 0.9743204), tolerance = 1e-6)
  expect_equal(c(val("3", "sensitivity", "lower"), val("3", "sensitivity", "upper")),
               c(0.2307243, 0.8823792), tolerance = 1e-6)
  expect_identical(val("2", "sensitivity", "n"), 5L)
  expect_identical(unique(se$method), "wilson")

  out <- capture.output(print(cal))
  expect_true(any(grepl("reviewers: 3; consensus by majority; 4 document", out)))
  expect_true(any(grepl("reviewer 2 vs consensus: sensitivity 80.0%", out, fixed = TRUE)))
})

test_that("with 30 items or more alpha is reported over all three reviewers", {
  s <- rv_sheet(3L)
  cal <- gr_calibrate(s$scr, gr_reference_consensus(s$ref, "majority"))
  ag <- cal$reviewers$agreement
  # Nominal alpha from the coincidence matrix. Per copy of the 12 records,
  # with weight 1 / (m - 1) = 1/2 per ordered pair: o_II = 9, o_EE = 19 and
  # o_IE = o_EI = 4. Over three copies n = 108, n_I = 39 and n_E = 69, so
  # D_o = 24/108 and D_e = 2 n_I n_E / (n (n - 1)), and alpha = 1 - D_o / D_e.
  expect_equal(ag$estimate[ag$pair == "all reviewers" & ag$statistic == "Krippendorff's alpha"],
               1 - (24 / 108) / (2 * 39 * 69 / (108 * 107)))
  expect_equal(1 - (24 / 108) / (2 * 39 * 69 / (108 * 107)), 0.5228539576)
})

test_that("on a stacked reference both are weighted like recall", {
  # 8 kept records, all judged (pi = 1), and 8 of 32 excluded (pi = 1/4).
  scr <- rv_screening(c(rep("include", 8), rep("exclude", 32)), prefix = "s")
  ref <- gr_reference(scr, n = 8, of = "stacked", seed = 3, reviewers = 2)
  kept_docs <- paste0("s", 1:8, ".pdf")
  exc <- setdiff(ref$document, kept_docs)
  expect_length(exc, 8L)
  # Reviewer 1 includes kept 1-6, reviewer 2 kept 1-5 and 7; both include
  # the first sampled exclusion and nothing else.
  ref$human_decision_1 <- ifelse(ref$document %in% c(kept_docs[1:6], exc[1]), "include", "exclude")
  ref$human_decision_2 <- ifelse(ref$document %in% c(kept_docs[c(1:5, 7)], exc[1]),
                                 "include", "exclude")
  cal <- gr_calibrate(scr, gr_reference_consensus(ref, "any_include"))
  r <- cal$reviewers
  expect_true(r$weighted)
  se <- r$sensitivity
  val <- function(id, stat, col = "estimate") se[[col]][se$reviewer == id & se$statistic == stat]
  # Any include: eligible are kept 1-7 and exc[1]. Reviewer 1 in the kept
  # stratum includes 6 of the 7 eligible (a = 6, b = 1), weight 1; in the
  # excluded stratum the one eligible (a = 1, b = 0), weight 32/8 = 4.
  # Sensitivity = (6 + 4 x 1) / (6 + 4 x 1 + 1 + 4 x 0) = 10/11.
  expect_equal(val("1", "sensitivity"), 10 / 11)
  # Bounds: the kept stratum is a census, so a and b are exact there. In the
  # excluded stratum a and b are each bounded at alpha = 0.025 / 2 = 0.0125
  # (two counts, Bonferroni). For b, x = 0 of 8 from 32: the upper bound is
  # 11, since phyper(0, 11, 21, 8) = 0.0193 > 0.0125 and
  # phyper(0, 12, 20, 8) = 0.0120 is not. For a, x = 1: the lower bound is 1
  # and the upper 16. So the interval is
  # [(6 + 1) / (6 + 1 + 1 + 11), (6 + 16) / (6 + 16 + 1 + 0)] = [7/19, 22/23].
  expect_equal(stats::phyper(0, 11, 21, 8), 0.01934628, tolerance = 1e-6)
  expect_equal(stats::phyper(0, 12, 20, 8), 0.01197627, tolerance = 1e-6)
  expect_equal(c(val("1", "sensitivity", "lower"), val("1", "sensitivity", "upper")),
               c(7 / 19, 22 / 23))
  # Specificity: the one ineligible kept record (8) excluded (d = 1, c = 0),
  # and all 7 ineligible exclusions excluded (d = 7, weight 4): (1 + 28) / 29.
  # The lower bound on d in the excluded stratum is 16 (the smallest D with
  # P(X >= 7) above 0.0125: 0.0186 at 16, 0.0110 at 15), and c's upper bound
  # is 11 as above: (1 + 16) / (1 + 16 + 0 + 11) = 17/28.
  expect_equal(val("1", "specificity"), 1)
  expect_equal(val("1", "specificity", "lower"), 17 / 28)
  expect_identical(unique(se$method), "design-weighted, hypergeometric")

  # Agreement on the weighted table: kept stratum (weight 1) a = 5, b = 1,
  # c = 1, d = 1; excluded stratum (weight 4) a = 1, d = 7. Weighted:
  # a = 9, b = 1, c = 1, d = 29, total 40. po = 38/40; both include 10/40,
  # pe = 0.25^2 + 0.75^2 = 0.625, kappa = (0.95 - 0.625) / 0.375.
  # PABAK = 0.9; q = 0.25, pe_g = 0.375, AC1 = (0.95 - 0.375) / 0.625 = 0.92.
  # PI = (9 - 29) / 40 = -0.5, BI = 0.
  ag <- r$agreement
  w <- ag[ag$scope == "weighted", ]
  get <- function(stat) w$estimate[w$statistic == stat]
  expect_equal(get("observed agreement"), 0.95)
  expect_equal(get("kappa"), 0.325 / 0.375)
  expect_equal(get("PABAK"), 0.9)
  expect_equal(get("AC1"), 0.92)
  expect_equal(get("prevalence index"), -0.5)
  expect_equal(get("bias index"), 0)
  # Only the sampled excluded stratum is resampled, the kept stratum being
  # judged whole, and the two reviewers agree on all 8 sampled exclusions, so
  # no resample can differ in agreement and no interval is given.
  expect_true(all(is.na(w$lower)))
  expect_true(any(grepl("1 vs 2 (weighted): The reviewers agree on every sampled record",
                        r$notes, fixed = TRUE)))
  # Within each stratum, unweighted, as hr_agreement() gives it.
  expect_setequal(unique(ag$scope), c("kept", "excluded", "weighted"))
  expect_equal(ag$estimate[ag$scope == "kept" & ag$statistic == "observed agreement"], 6 / 8)
  expect_equal(ag$estimate[ag$scope == "excluded" & ag$statistic == "observed agreement"], 1)
})

test_that("a one-reviewer reference is calibrated as before", {
  scr <- rv_screening(c(rep("include", 4), "unclear", rep("exclude", 7)))
  ref <- gr_reference(scr, n = Inf, of = "all", seed = 1)
  ref$human_decision <- rv_r1
  cal <- gr_calibrate(scr, ref)
  expect_null(cal$reviewers)
  expect_false("reviewers" %in% names(cal))
  # Two sheets stacked without a reviewer column are still one reviewer's
  # copies, refused when they disagree.
  r2 <- ref
  r2$human_decision[1] <- "exclude"
  expect_error(gr_calibrate(scr, rbind(ref, r2)), class = "gr_reference_conflict")
})

test_that("a sheet filled in and saved as CSV reads back with its reviewers", {
  s <- rv_sheet()
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  utils::write.csv(as.data.frame(s$ref), path, row.names = FALSE, na = "")
  expect_error(gr_calibrate(s$scr, path), "4 of 12", class = "gr_reference_conflict")
  cons <- gr_reference_consensus(path, "majority")
  utils::write.csv(as.data.frame(cons), path, row.names = FALSE, na = "")
  cal <- gr_calibrate(s$scr, path)
  expect_identical(cal$reviewers$rule, "majority")
  expect_identical(cal$reviewers$conflicts, 4L)
  expect_identical(cal$counts, c(tp = 4L, fn = 1L, fp = 1L, tn = 6L))
})

test_that("weighted agreement holds a census stratum fixed and flags a small sample", {
  wa <- harnessr:::weighted_agreement
  # Both strata judged whole: no sampling error, so no interval.
  w0 <- wa(c(TRUE, TRUE, FALSE, FALSE), c(TRUE, FALSE, FALSE, TRUE),
           c("kept", "kept", "excluded", "excluded"), c(kept = 2, excluded = 2), 0.95)
  expect_true(all(is.na(w0$stats$lower)))
  expect_identical(w0$note,
                   "Every record was judged, so the figures have no sampling error and no interval.")
  # Kept stratum judged whole with one disagreement in four; excluded stratum
  # 10 of 100 sampled (weight 10), all agreeing. Only the excluded rows are
  # resampled, so every resample has the same agreement and none is given.
  x <- c(TRUE, TRUE, TRUE, FALSE, TRUE, rep(FALSE, 9))
  y <- c(TRUE, TRUE, FALSE, FALSE, TRUE, rep(FALSE, 9))
  st <- c(rep("kept", 4), rep("excluded", 10))
  w1 <- wa(x, y, st, c(kept = 4, excluded = 100), 0.95)
  expect_true(all(is.na(w1$stats$lower)))
  # Weighted table: a = 2 + 10, b = 1, c = 0, d = 1 + 90, total 104.
  expect_equal(w1$stats$estimate[1], 103 / 104)

  # Three reviewers, stacked: 4 kept records judged whole and 6 of 60
  # excluded sampled. Reviewers 1 and 2 disagree on one sampled exclusion, so
  # the weighted kappa has an interval, and with 6 sampled exclusions, under
  # 100, the notes say it is approximate. Reviewer 3 judged none of the
  # excluded sample, so their weighted rates are NA and the notes say why.
  scr <- rv_screening(c(rep("include", 4), rep("exclude", 60)), prefix = "w")
  ref <- gr_reference(scr, n = 6, of = "stacked", seed = 2, reviewers = 3)
  kept_docs <- paste0("w", 1:4, ".pdf")
  exc <- setdiff(ref$document, kept_docs)
  expect_length(exc, 6L)
  ref$human_decision_1 <- ifelse(ref$document %in% c(kept_docs[1:3], exc[1:2]),
                                 "include", "exclude")
  ref$human_decision_2 <- ifelse(ref$document %in% c(kept_docs[1:2], exc[1]),
                                 "include", "exclude")
  ref$human_decision_3 <- ifelse(ref$document %in% kept_docs[1:3], "include", "exclude")
  ref$human_decision_3[ref$document %in% exc] <- NA
  cal <- gr_calibrate(scr, gr_reference_consensus(ref, "any_include"))
  r <- cal$reviewers
  w <- r$agreement[r$agreement$pair == "1 vs 2" & r$agreement$scope == "weighted", ]
  expect_false(is.na(w$lower[w$statistic == "kappa"]))
  expect_true(paste0("1 vs 2 (weighted): the excluded sample is 6 records, so the kappa ",
                     "interval is approximate and may be too narrow.") %in% r$notes)
  expect_true(paste0("Reviewer 3 judged no record in the excluded stratum, so their ",
                     "weighted rates cannot be estimated.") %in% r$notes)
  expect_true(paste0("1 vs 3 (weighted): no record in the excluded stratum was judged by ",
                     "both, so no weighted agreement is given.") %in% r$notes)
  s3 <- r$sensitivity[r$sensitivity$reviewer == "3", ]
  expect_true(all(is.na(s3$estimate)))
})
