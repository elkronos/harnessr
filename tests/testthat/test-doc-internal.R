# test-doc-internal.R: the document layer's use of core internals may only
# shrink.
#
# fixtures/boundary/doc-uses-internal.csv lists the core functions that are
# not exported and that some document layer function calls or hands on. The
# document layer should reach the core through its exports, so a new entry
# fails here. When an entry is no longer used, the test passes and says so;
# rerun `Rscript dev/record-doc-internal.R` from the repository root to drop
# the row. Adding a row to the CSV needs the label tests-reviewed on the pull
# request. The parsing is the boundary test's, in helper-boundary.R.

test_that("the document layer uses no core internal that is not already listed", {
  skip_if_not_installed("codetools")
  listed <- utils::read.csv(boundary_doc_internal_csv(), stringsAsFactors = FALSE)$name
  expect_gt(length(listed), 0L)
  used <- boundary_doc_internal(boundary_layers())
  new <- setdiff(used, listed)
  expect(length(new) == 0,
         sprintf(paste("The document layer now uses core internals not in",
                       "fixtures/boundary/doc-uses-internal.csv: %s. Call an export",
                       "instead, or export the function and say why in",
                       "NOTES-primitives.md."),
                 paste(new, collapse = ", ")))
  gone <- setdiff(listed, used)
  if (length(gone)) {
    message(sprintf(paste("No longer used by the document layer: %s.",
                          "Run Rscript dev/record-doc-internal.R to drop them from",
                          "fixtures/boundary/doc-uses-internal.csv."),
                    paste(gone, collapse = ", ")))
  }
})

test_that("doc-uses-internal.csv lists only internal core functions, once each", {
  listed <- utils::read.csv(boundary_doc_internal_csv(), stringsAsFactors = FALSE)$name
  layers <- boundary_layers()
  core_funs <- layers$name[layers$layer == "core" & layers$kind == "function"]
  expect_identical(anyDuplicated(listed), 0L)
  expect_identical(setdiff(listed, core_funs), character(0))
  expect_identical(intersect(listed, getNamespaceExports("harnessr")), character(0))
})
