# Screening recall is relative to the reference, and a worst case that counts
# every reviewer conflict as eligible is reported beside it.
#
# The sheet is the three-reviewer one of test-screen-reviewers.R. The screener
# keeps records 1 to 5 (include 1 to 4, unclear 5) and excludes 6 to 12. The
# reviewers split on 2, 3, 8 and 10. Under the majority rule the eligible
# records are 1, 2, 3, 5 and 8, so recall is 4 / 5. Record 10 is the one
# conflict the majority settled as not eligible: counted as eligible, the
# eligible records are 1, 2, 3, 5, 8 and 10, and recall is 4 / 6.

wc_sheet <- function() {
  scr <- structure(list(table = data.frame(
    document = paste0("d", 1:12, ".pdf"),
    decision = c(rep("include", 4), "unclear", rep("exclude", 7)),
    stringsAsFactors = FALSE)), class = "gr_screening")
  ref <- gr_reference(scr, n = Inf, of = "all", seed = 1, reviewers = 3, blind = FALSE)
  ref$human_decision_1 <- c("include", "include", "include", "exclude", "include", "exclude",
                            "exclude", "include", "exclude", "exclude", "exclude", "exclude")
  ref$human_decision_2 <- c("include", "include", "exclude", "exclude", "include", "exclude",
                            "exclude", "include", "exclude", "include", "exclude", "exclude")
  ref$human_decision_3 <- c("include", "exclude", "include", "exclude", "include", "exclude",
                            "exclude", "exclude", "exclude", "exclude", "exclude", "exclude")
  list(scr = scr, ref = ref)
}

test_that("the worst case counts the conflicts the consensus excluded as eligible", {
  s <- wc_sheet()
  cal <- gr_calibrate(s$scr, gr_reference_consensus(s$ref, "majority"))
  expect_equal(cal$recall$estimate, 4 / 5)
  w <- cal$worst_case
  expect_identical(w$rule, "reviewer conflicts counted as eligible")
  expect_identical(w$conflicts, 4L)
  expect_identical(w$changed, 1L)
  expect_equal(w$recall$estimate, 4 / 6)
  expect_identical(w$missed$document, c("d8.pdf", "d10.pdf"))
  expect_match(w$note, "1 record(s) the reviewers split on", fixed = TRUE)
  # The main figures are the ones they were.
  expect_identical(cal$missed$document, "d8.pdf")

  out <- capture.output(print(cal))
  at_main <- grep("^  recall ", out)
  at_worst <- grep("worst case, reviewer conflicts counted as eligible", out, fixed = TRUE)
  expect_length(at_worst, 1L)
  expect_true(at_worst > at_main[1])
  expect_true(any(grepl("recall 66.7%", out, fixed = TRUE)))
  expect_true(any(grepl("recall is relative to the reference", out, fixed = TRUE)))
})

test_that("under any_include the worst case is the main estimate", {
  s <- wc_sheet()
  cal <- gr_calibrate(s$scr, gr_reference_consensus(s$ref, "any_include"))
  expect_identical(cal$worst_case$changed, 0L)
  expect_equal(cal$worst_case$recall$estimate, cal$recall$estimate)
  expect_match(cal$worst_case$note, "already counts all 4 conflict", fixed = TRUE)
})

test_that("one decision per document has no conflicts, and still says what recall is relative to", {
  scr <- structure(list(table = data.frame(
    document = paste0("d", 1:6, ".pdf"),
    decision = c("include", "include", "exclude", "exclude", "include", "exclude"),
    stringsAsFactors = FALSE)), class = "gr_screening")
  ref <- data.frame(document = paste0("d", 1:6, ".pdf"),
                    human_decision = c("include", "exclude", "include", "exclude",
                                       "include", "exclude"), stringsAsFactors = FALSE)
  cal <- gr_calibrate(scr, ref, of = "all")
  expect_identical(cal$worst_case$conflicts, 0L)
  expect_equal(cal$worst_case$recall$estimate, cal$recall$estimate)
  expect_match(cal$worst_case$note, "One decision per document", fixed = TRUE)
  out <- capture.output(print(cal))
  expect_false(any(grepl("worst case", out, fixed = TRUE)))
  expect_true(any(grepl("recall is relative to the reference", out, fixed = TRUE)))

  # A sample of the exclusions gives no recall, and says nothing about it.
  ex <- gr_calibrate(scr, ref[ref$document %in% c("d3.pdf", "d4.pdf", "d6.pdf"), ],
                     of = "excluded")
  expect_false(any(grepl("relative to the reference", capture.output(print(ex)), fixed = TRUE)))
})

test_that("the audit report shows recall, its caveat and the worst case", {
  s <- wc_sheet()
  cal <- gr_calibrate(s$scr, gr_reference_consensus(s$ref, "majority"))
  f <- tempfile(fileext = ".html")
  quiet <- function(e) suppressWarnings(suppressMessages(e))
  quiet(gr_audit_report(f, screening = s$scr, calibration = cal, open = FALSE))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "<b>Recall:</b> 80.0%", fixed = TRUE)
  expect_match(html, "Worst case, reviewer conflicts counted as eligible:</b> recall 66.7%",
               fixed = TRUE)
  expect_match(html, "Recall is relative to the reference", fixed = TRUE)

  # A calibration saved before these fields existed still renders.
  old <- cal
  old$recall <- NULL; old$worst_case <- NULL; old$reviewers <- NULL
  g <- tempfile(fileext = ".html")
  quiet(gr_audit_report(g, screening = s$scr, calibration = old, open = FALSE))
  old_html <- paste(readLines(g, warn = FALSE), collapse = "\n")
  expect_false(grepl("Worst case", old_html, fixed = TRUE))
  # Its sensitivity rows are recall under another name, so the caveat stays.
  expect_match(old_html, "Recall is relative to the reference", fixed = TRUE)
  expect_output(print(old), "sensitivity")
})
