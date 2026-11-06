# record-golden.R -- write the fixtures test-golden.R compares against.
#
# Run from the repository root:
#
#   Rscript dev/record-golden.R
#
# It loads the package from this source tree (with pkgload, when installed;
# otherwise the installed harnessr, which must then be reinstalled from this
# tree first), runs every golden run defined in tests/testthat/helper-golden.R
# and rewrites tests/testthat/fixtures/golden/ from scratch.
#
# Only rerun this when a change in behaviour is intended. The fixtures are the
# record of what the package did before the change; rewriting them is how the
# change is accepted, so commit them with a message that says what changed and
# why.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "testthat"))) {
  stop("Run this from the repository root: Rscript dev/record-golden.R", call. = FALSE)
}
Sys.setenv(OPENAI_API_KEY = "")

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
  from <- "this source tree"
} else {
  suppressPackageStartupMessages(library(harnessr))
  from <- sprintf("the installed harnessr %s", utils::packageVersion("harnessr"))
}

source(file.path("tests", "testthat", "helper-golden.R"), local = TRUE)

for (p in golden_needs) {
  if (!requireNamespace(p, quietly = TRUE)) stop(sprintf("Package '%s' is needed.", p), call. = FALSE)
}

records <- golden_compute()
dir <- golden_dir(".")
files <- golden_write(records, dir)

runs <- setdiff(names(records), "api")
n_calls <- vapply(records[runs], function(r) length(r$calls), integer(1))
size <- sum(file.size(files))
cat(sprintf("Recorded from %s.\n", from))
cat(sprintf("%d golden runs, %d model calls; API snapshot of %d exports and %d S3 methods.\n",
            length(runs), sum(n_calls), length(records$api$exports),
            length(records$api$s3methods)))
cat(sprintf("%d files, %.1f KB, in %s\n", length(files), size / 1024, dir))
