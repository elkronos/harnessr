# Pull request hygiene checks, run by .github/workflows/pr-checks.yaml and
# runnable by hand against any two git refs:
#
#   Rscript dev/ci/pr-checks.R tests <base> <head>
#   Rscript dev/ci/pr-checks.R deps  <base> <head>
#   Rscript dev/ci/pr-checks.R lint  <base> <head>
#
# Labels on the pull request come from the PR_LABELS environment variable, a
# comma separated list. Locally, set it by hand to see what a label changes:
#
#   PR_LABELS=tests-reviewed Rscript dev/ci/pr-checks.R tests main HEAD
#
# The diff is taken from the merge base, as GitHub shows it (`base...head`).
# Each check exits 1 when it fails and 0 when it passes. Base R only, except
# `lint`, which needs lintr.
#
# tests  Fails when the change removes an expect_*() call from tests/, or adds
#        a skip(), skip_if*() or skip_on_*() call, unless the pull request
#        carries the label "tests-reviewed". A line removed in one place and
#        added back unchanged in another (a test moved between files) does not
#        count. Comments and quoted strings are ignored, so a skip() in a
#        comment or a message does not count. A line with an expect_ call that
#        is edited (its arguments changed, say) counts as a removed
#        expectation, since the old line no longer appears. Only skip(),
#        skip_if*(), skip_on_*(), skip_unless*() and skip_empty() are caught;
#        a project helper that wraps skip() under another name is not.
# deps   Fails when the change adds a package to Depends, Imports, LinkingTo
#        or Suggests in DESCRIPTION, unless the pull request carries the label
#        "deps-reviewed". Moving a package from Suggests to Imports counts as
#        an addition to Imports. Every added package must also exist on CRAN,
#        label or not: it is looked up at https://crandb.r-pkg.org/<pkg>, and a
#        404 means it is missing. CRANDB_URL overrides the host, for testing.
# lint   Runs lintr, with the repository's .lintr, on the files under R/ that
#        the change adds or modifies. It lints the files as they are in the
#        working tree, so check out <head> before running it locally.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !args[[1]] %in% c("tests", "deps", "lint")) {
  cat("usage: Rscript dev/ci/pr-checks.R <tests|deps|lint> <base> <head>\n")
  quit(status = 2)
}
check <- args[[1]]
base  <- args[[2]]
head  <- args[[3]]

labels <- trimws(strsplit(Sys.getenv("PR_LABELS"), ",", fixed = TRUE)[[1]])
labels <- labels[nzchar(labels)]

# system2() goes through the shell, so every argument is quoted: a pathspec
# such as tests/*.R must reach git unexpanded.
git <- function(...) {
  out <- suppressWarnings(system2("git", shQuote(c(...)), stdout = TRUE,
                                  stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    cat("git", paste(c(...), collapse = " "), "failed:\n")
    cat(out, sep = "\n")
    quit(status = 2)
  }
  out
}

# Lines added and removed by the change, for the files matching `paths`. Diff
# headers are dropped; what is left is the line text without its +/- marker.
changed_lines <- function(paths) {
  d <- git("diff", "--no-color", "--find-renames", "-U0",
           paste0(base, "...", head), "--", paths)
  body <- d[!grepl("^(\\+\\+\\+|---) ", d)]
  list(added   = substring(body[startsWith(body, "+")], 2L),
       removed = substring(body[startsWith(body, "-")], 2L))
}

squish <- function(x) gsub("[[:space:]]+", " ", trimws(x))
# The code part of each line: quoted strings emptied, then everything from #
# to the end of the line dropped. Strings go first so a # inside one is kept
# out of the way. Good enough for one line at a time; a string that spans
# lines is not handled.
code_only <- function(x) {
  x <- gsub("\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'", "\"\"", x, perl = TRUE)
  sub("#.*$", "", x)
}

# Lines in `x` whose code matches `pattern` and that do not appear, whitespace
# aside, in `y`. The lines are returned as written, for the report.
unmatched <- function(x, y, pattern) {
  x <- x[grepl(pattern, code_only(x), perl = TRUE)]
  x[!squish(x) %in% squish(y)]
}

report <- function(title, lines) {
  if (!length(lines)) return(invisible())
  cat(sprintf("%s (%d):\n", title, length(lines)))
  cat(paste0("  ", trimws(utils::head(lines, 50L))), sep = "\n")
  if (length(lines) > 50L) cat(sprintf("  and %d more\n", length(lines) - 50L))
}

check_tests <- function() {
  # In a git pathspec `*` also matches `/`, so this covers every R file
  # under tests/, at any depth.
  ch <- changed_lines("tests/*.R")
  expect_re <- "(^|[^A-Za-z0-9_.])expect_[A-Za-z0-9_.]*\\s*\\("
  skip_re   <- paste0("(^|[^A-Za-z0-9_.])skip(_if[A-Za-z0-9_.]*|",
                      "_on_[A-Za-z0-9_.]+|_unless[A-Za-z0-9_.]*|_empty)?\\s*\\(")
  lost_expect <- unmatched(ch$removed, ch$added, expect_re)
  new_skip    <- unmatched(ch$added, ch$removed, skip_re)
  report("Removed expectations", lost_expect)
  report("Added skips", new_skip)
  if (!length(lost_expect) && !length(new_skip)) {
    cat("No expectations removed and no skips added.\n")
    return(0L)
  }
  if ("tests-reviewed" %in% labels) {
    cat("Allowed: the pull request carries the label tests-reviewed.\n")
    return(0L)
  }
  cat("\nThis change weakens the test suite. If that is intended, have it",
      "reviewed and add the label tests-reviewed to the pull request.\n")
  1L
}

# Package names in one DESCRIPTION field at a ref, version requirements dropped.
dep_names <- function(ref, field) {
  txt <- git("show", paste0(ref, ":DESCRIPTION"))
  dcf <- read.dcf(textConnection(txt), all = TRUE)
  if (!field %in% colnames(dcf) || is.na(dcf[1, field])) return(character(0))
  pkgs <- trimws(strsplit(dcf[1, field], ",", fixed = TRUE)[[1]])
  pkgs <- trimws(sub("\\(.*$", "", pkgs))
  # Depends may name R itself, which is not a package.
  pkgs[nzchar(pkgs) & pkgs != "R"]
}

base_packages <- c("base", "compiler", "datasets", "graphics", "grDevices",
                   "grid", "methods", "parallel", "splines", "stats", "stats4",
                   "tcltk", "tools", "utils")

# HTTP status of a crandb lookup, or NA when the request could not be made.
crandb_status <- function(pkg) {
  host <- sub("/+$", "", Sys.getenv("CRANDB_URL", "https://crandb.r-pkg.org"))
  out <- suppressWarnings(system2(
    "curl", c("-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "30",
              shQuote(paste0(host, "/", pkg))),
    stdout = TRUE, stderr = TRUE))
  code <- suppressWarnings(as.integer(utils::tail(out, 1L)))
  if (length(code) != 1L || is.na(code) || code == 0L) NA_integer_ else code
}

check_deps <- function() {
  added <- list()
  for (field in c("Depends", "Imports", "LinkingTo", "Suggests")) {
    new <- setdiff(dep_names(head, field), dep_names(base, field))
    if (length(new)) added[[field]] <- new
  }
  if (!length(added)) {
    cat("No packages added to Depends, Imports, LinkingTo or Suggests.\n")
    return(0L)
  }
  for (field in names(added))
    cat(sprintf("Added to %s: %s\n", field, paste(added[[field]], collapse = ", ")))

  failed <- FALSE
  to_look_up <- setdiff(unique(unlist(added)), base_packages)
  for (pkg in to_look_up) {
    code <- crandb_status(pkg)
    if (identical(code, 200L)) {
      cat(sprintf("  %s: on CRAN\n", pkg))
    } else if (identical(code, 404L)) {
      cat(sprintf("  %s: NOT on CRAN\n", pkg))
      failed <- TRUE
    } else {
      cat(sprintf("  %s: could not look up (status %s)\n", pkg,
                  if (is.na(code)) "none" else code))
      failed <- TRUE
    }
  }
  if (failed) {
    cat("\nEvery new dependency must be a package on CRAN.\n")
    return(1L)
  }
  if ("deps-reviewed" %in% labels) {
    cat("Allowed: the pull request carries the label deps-reviewed.\n")
    return(0L)
  }
  cat("\nNew dependencies need a review. Once that is done, add the label",
      "deps-reviewed to the pull request.\n")
  1L
}

check_lint <- function() {
  files <- git("diff", "--name-only", "--diff-filter=AMR",
               paste0(base, "...", head), "--", "R/*.R")
  files <- files[grepl("[.][Rr]$", files) & file.exists(files)]
  if (!length(files)) {
    cat("No R files under R/ changed.\n")
    return(0L)
  }
  if (!requireNamespace("lintr", quietly = TRUE)) {
    cat("lintr is not installed.\n")
    return(2L)
  }
  n <- 0L
  for (f in files) {
    l <- lintr::lint(f)
    if (length(l)) print(l)
    n <- n + length(l)
  }
  cat(sprintf("%d file(s) linted, %d lint(s).\n", length(files), n))
  if (n) 1L else 0L
}

status <- switch(check,
                 tests = check_tests(),
                 deps  = check_deps(),
                 lint  = check_lint())
quit(status = status)
