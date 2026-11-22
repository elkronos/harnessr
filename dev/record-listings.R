# record-listings.R: write the registry snapshot test-registry-snapshot.R
# compares against.
#
# Run from the repository root:
#
#   Rscript dev/record-listings.R
#
# It loads the package from this source tree (with pkgload, when installed;
# otherwise the installed harnessr, which must then be reinstalled from this
# tree first) in a fresh session, so the registries hold only what the
# package registers when it loads, and writes
# tests/testthat/fixtures/registry/listings.rds. See
# tests/testthat/helper-listings.R for what is recorded.
#
# The snapshot is the record of what the registries showed before a change to
# them. Rewriting it is how a change is accepted, so only rerun this when a
# change in a listing, a stamp or an ingest key is intended, and say why in the
# commit message.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "testthat"))) {
  stop("Run this from the repository root: Rscript dev/record-listings.R", call. = FALSE)
}

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
  from <- "this source tree"
} else {
  suppressPackageStartupMessages(library(harnessr))
  from <- sprintf("the installed harnessr %s", utils::packageVersion("harnessr"))
}

source(file.path("tests", "testthat", "helper-listings.R"), local = TRUE)

snap <- listings_snapshot()
path <- listings_path(".")
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
saveRDS(snap, path, version = 2)
cat(sprintf("Recorded from %s.\n", from))
cat(sprintf("%d listings, %d cleaner and %d extractor stamps, %d ingest keys, in %s\n",
            length(snap$listing), length(snap$stamps$cleaners),
            length(snap$stamps$extractors), length(snap$ingest), path))
