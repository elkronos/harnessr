# test-stage-fixtures.R: review-stage objects saved by an earlier version are
# still read by this one.
#
# fixtures/stages/ holds one object of each review stage (gr_screening,
# gr_extraction, gr_claims, gr_gaps, the outline and gr_synthesis), built
# offline by dev/build-stage-fixtures.R and saved with saveRDS(). A user who
# saved a stage's result and reads it back after an upgrade must be able to go
# on with it: report on it, recheck it, synthesise from it and print it. The
# files are never rebuilt to make this test pass.

stage_fixture <- function(name) readRDS(test_path("fixtures", "stages", paste0(name, ".rds")))

stage_client <- function() hr_mock_client(golden_reply)

test_that("every saved stage object reads back with its class", {
  expect_s3_class(stage_fixture("screening"), "gr_screening")
  expect_s3_class(stage_fixture("extraction"), "gr_extraction")
  expect_s3_class(stage_fixture("claims"), "gr_claims")
  expect_s3_class(stage_fixture("gaps"), "gr_gaps")
  expect_type(stage_fixture("outline"), "character")
  expect_s3_class(stage_fixture("synthesis"), "gr_synthesis")
})

test_that("the print methods accept the saved objects", {
  for (nm in c("screening", "extraction", "claims", "gaps", "synthesis")) {
    x <- stage_fixture(nm)
    out <- capture.output(res <- print(x))
    expect_true(length(out) > 0L, info = nm)
    expect_identical(res, x, info = nm)
  }
  expect_output(print(stage_fixture("outline")), "Findings")
})

test_that("gr_audit_report() reports on the saved objects", {
  path <- tempfile(fileext = ".html")
  on.exit(unlink(path), add = TRUE)
  out <- quiet(gr_audit_report(path, screening = stage_fixture("screening"),
                               extraction = stage_fixture("extraction"),
                               synthesis = stage_fixture("synthesis"),
                               protocol = golden_protocol(),
                               claims = stage_fixture("claims"), open = FALSE))
  expect_true(file.exists(path))
  expect_gt(file.size(path), 0)
  expect_identical(out, path)
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_match(html, "Findings", fixed = TRUE)
})

test_that("gr_recheck() rechecks the saved synthesis", {
  syn <- stage_fixture("synthesis")
  re <- quiet(gr_recheck(syn))
  expect_s3_class(re, "gr_synthesis")
  expect_identical(nrow(re$sections), nrow(syn$sections))
})

test_that("gr_synthesise() writes from the saved extraction, outline and claims", {
  syn <- quiet(gr_synthesise(stage_fixture("extraction"), protocol = golden_protocol(),
                             outline = stage_fixture("outline"),
                             claims = stage_fixture("claims"), client = stage_client()))
  expect_s3_class(syn, "gr_synthesis")
  expect_true(nzchar(syn$text))
  expect_identical(syn$text, stage_fixture("synthesis")$text)
})
