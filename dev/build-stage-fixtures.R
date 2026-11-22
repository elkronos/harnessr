# build-stage-fixtures.R: save one object of each review stage, as the package
# builds it now, for test-stage-fixtures.R.
#
# Run from the repository root, once:
#
#   Rscript dev/build-stage-fixtures.R
#
# It runs the review stages offline on the bundled example with the golden
# mock (tests/testthat/helper-golden.R) and saves, in
# tests/testthat/fixtures/stages/:
#
#   screening.rds   gr_screen()
#   extraction.rds  gr_extract()
#   claims.rds      gr_claims()
#   gaps.rds        gr_gaps()
#   outline.rds     gr_outline()
#   synthesis.rds   gr_synthesise()
#
# These files stand for objects a user saved with an earlier version, and the
# test checks that later versions still read them. Rebuilding them would hide
# exactly the change the test is there to catch, so do it only to add an
# object that was not saved before, and say why in the commit.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "testthat"))) {
  stop("Run this from the repository root: Rscript dev/build-stage-fixtures.R", call. = FALSE)
}
Sys.setenv(OPENAI_API_KEY = "")

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(harnessr))
}
source(file.path("tests", "testthat", "helper-golden.R"), local = TRUE)

harnessr::gr_options(verbose = FALSE)
dir <- file.path("tests", "testthat", "fixtures", "stages")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)

cl <- harnessr::gr_mock_client(golden_reply)
p <- golden_protocol()
quietly <- function(e) suppressWarnings(suppressMessages(e))
s <- quietly(harnessr::gr_screen(harnessr::gr_example(), p, client = cl))
x <- quietly(harnessr::gr_extract(s, p, client = cl))
cm <- quietly(harnessr::gr_claims(x, question = p$question, client = cl))
gp <- quietly(harnessr::gr_gaps(cm, extraction = x))
o <- quietly(harnessr::gr_outline(cm, client = cl))
sy <- quietly(harnessr::gr_synthesise(x, protocol = p, outline = o, claims = cm, client = cl))

objs <- list(screening = s, extraction = x, claims = cm, gaps = gp, outline = o,
             synthesis = sy)

# The example's path is this machine's; a saved file keeps only its name.
ex <- harnessr::gr_example()
paths <- unique(c(normalizePath(ex, winslash = "/", mustWork = FALSE), ex))
scrub <- function(v) {
  if (is.character(v)) {
    for (pth in paths) v[] <- gsub(pth, basename(ex), v, fixed = TRUE)
    return(v)
  }
  if (is.list(v)) {
    a <- attributes(v)
    v <- lapply(v, scrub)
    attributes(v) <- a
  }
  v
}
objs <- lapply(objs, scrub)
for (nm in names(objs)) saveRDS(objs[[nm]], file.path(dir, paste0(nm, ".rds")), version = 2)
cat(sprintf("Saved %d stage objects in %s\n", length(objs), dir))
