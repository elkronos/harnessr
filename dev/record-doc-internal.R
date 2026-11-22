# record-doc-internal.R: write the list of internal core functions that the
# document layer uses, which test-doc-internal.R compares against.
#
# Run from the repository root, after dev/record-layers.R when objects were
# added, removed or moved:
#
#   Rscript dev/record-doc-internal.R
#
# A document layer function (R/doc-*.R) should reach the core through its
# exports. This lists the core functions (R/core-*.R) that are not exported
# and that some document layer function calls or hands on, one per row, in
# tests/testthat/fixtures/boundary/doc-uses-internal.csv. The parsing is the
# boundary test's, in tests/testthat/helper-boundary.R.
#
# The list may only shrink. When a change stops the document layer using an
# internal, rerun this to drop the row. A change that adds a row needs the
# label tests-reviewed on its pull request (dev/ci/pr-checks.R tests).

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/record-doc-internal.R", call. = FALSE)
}
if (!requireNamespace("codetools", quietly = TRUE)) {
  stop("Package 'codetools' is needed.", call. = FALSE)
}

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
  from <- "this source tree"
} else {
  suppressPackageStartupMessages(library(harnessr))
  from <- sprintf("the installed harnessr %s", utils::packageVersion("harnessr"))
}

source(file.path("tests", "testthat", "helper-boundary.R"), local = TRUE)

used <- boundary_doc_internal(boundary_layers("."))
path <- boundary_doc_internal_csv(".")
old <- if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE)$name else character(0)
utils::write.csv(data.frame(name = used), path, row.names = FALSE)
cat(sprintf("Read from %s.\n", from))
cat(sprintf("%d internal core functions used by the document layer (was %d).\n",
            length(used), length(old)))
if (length(added <- setdiff(used, old))) cat("Added:", paste(added, collapse = ", "), "\n")
if (length(dropped <- setdiff(old, used))) cat("Dropped:", paste(dropped, collapse = ", "), "\n")
cat(sprintf("Wrote %s\n", path))
