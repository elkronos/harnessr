# Pull request hygiene checks, run by .github/workflows/pr-checks.yaml and
# runnable by hand against any two git refs:
#
#   Rscript dev/ci/pr-checks.R tests     <base> <head>
#   Rscript dev/ci/pr-checks.R deps      <base> <head>
#   Rscript dev/ci/pr-checks.R lint      <base> <head>
#   Rscript dev/ci/pr-checks.R namespace <base> <head>
#   Rscript dev/ci/pr-checks.R commits   <base> <head>
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
# tests      Fails when the change removes an expect_*() call from tests/, or
#            adds a skip(), skip_if*() or skip_on_*() call, unless the pull
#            request carries the label "tests-reviewed". A line removed in one
#            place and added back unchanged in another (a test moved between
#            files) does not count. Comments and quoted strings are ignored,
#            so a skip() in a comment or a message does not count. A line with
#            an expect_ call that is edited (its arguments changed, say)
#            counts as a removed expectation, since the old line no longer
#            appears. Only skip(), skip_if*(), skip_on_*(), skip_unless*() and
#            skip_empty() are caught; a project helper that wraps skip() under
#            another name is not. A row added to one of the lists that may
#            only shrink (tests/testthat/fixtures/boundary/allowed.csv and
#            doc-uses-internal.csv) counts too: it lets more past a test.
# deps       Fails when the change adds a package to Depends, Imports,
#            LinkingTo or Suggests in DESCRIPTION, unless the pull request
#            carries the label "deps-reviewed". Moving a package from Suggests
#            to Imports counts as an addition to Imports. Every added package
#            must also exist on CRAN, label or not: it is looked up at
#            https://crandb.r-pkg.org/<pkg>, and a 404 means it is missing.
#            CRANDB_URL overrides the host, for testing.
# lint       Runs lintr, with the repository's .lintr, on the files under R/
#            that the change adds or modifies. It lints the files as they are
#            in the working tree, so check out <head> before running it
#            locally.
# namespace  Fails when an export() line of NAMESPACE at the merge base is
#            gone at <head>, unless the pull request carries the label
#            "exports-reviewed". A removed export breaks code that calls it;
#            list it under "## Removed" in NEWS.md with what to use instead.
#            Renaming counts as a removal. Only export() is compared, not
#            S3method() or exportPattern().
# commits    Fails when the message of a commit in <base>..<head> has a
#            Co-Authored-By trailer, a link to a chat or a session (claude.ai,
#            chatgpt.com and the like, or a trailer such as "X-Session: <url>"),
#            or a line that starts with "Generated with". No label allows
#            it: reword the commit. It reads commit messages only, never the
#            files, which may mention any tool.
#
# Sourced rather than run (source("dev/ci/pr-checks.R")), the file only
# defines its functions, so the tests in tests/testthat/test-pr-checks.R can
# call the ones that decide a verdict without git.

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

# Fixtures that may only shrink: each row lets something past a test.
shrink_only <- c("tests/testthat/fixtures/boundary/allowed.csv",
                 "tests/testthat/fixtures/boundary/doc-uses-internal.csv")

# Rows added to a shrink-only list and not just moved within it. The header
# row is the same before and after, so it never counts.
shrink_only_added <- function(added, removed) {
  added <- added[nzchar(trimws(added))]
  added[!squish(added) %in% squish(removed)]
}

`%||%` <- function(a, b) if (is.null(a)) b else a

check_tests <- function() {
  # In a git pathspec `*` also matches `/`, so this covers every R file
  # under tests/, at any depth.
  ch <- changed_lines("tests/*.R")
  expect_re <- "(^|[^A-Za-z0-9_.])expect_[A-Za-z0-9_.]*\\s*\\("
  skip_re   <- paste0("(^|[^A-Za-z0-9_.])skip(_if[A-Za-z0-9_.]*|",
                      "_on_[A-Za-z0-9_.]+|_unless[A-Za-z0-9_.]*|_empty)?\\s*\\(")
  lost_expect <- unmatched(ch$removed, ch$added, expect_re)
  new_skip    <- unmatched(ch$added, ch$removed, skip_re)
  sh <- changed_lines(shrink_only)
  new_rows <- shrink_only_added(sh$added, sh$removed)
  report("Removed expectations", lost_expect)
  report("Added skips", new_skip)
  report("Rows added to a list that may only shrink", new_rows)
  if (!length(lost_expect) && !length(new_skip) && !length(new_rows)) {
    cat("No expectations removed, no skips added and no rows added to a",
        "list that may only shrink.\n")
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


# ---------------------------------------------------------------------------
# namespace
# ---------------------------------------------------------------------------

# The names exported by export() lines of a NAMESPACE file's text. roxygen
# writes one name per line; a hand-written export(a, b) is split too. Quotes
# and backticks around a name are dropped.
namespace_exports <- function(txt) {
  txt <- sub("#.*$", "", txt)
  hits <- regmatches(txt, regexpr("^[[:space:]]*export[[:space:]]*[(].*[)]", txt))
  inner <- sub("^[[:space:]]*export[[:space:]]*[(](.*)[)]$", "\\1", hits)
  names <- trimws(unlist(strsplit(inner, ",", fixed = TRUE)))
  names <- gsub("^[`'\"]|[`'\"]$", "", names)
  sort(unique(names[nzchar(names)]), method = "radix")
}

# The verdict on two NAMESPACE texts and the pull request's labels: status 0
# or 1, and the lines to print.
namespace_verdict <- function(base_txt, head_txt, labels = character(0)) {
  gone <- setdiff(namespace_exports(base_txt), namespace_exports(head_txt))
  added <- setdiff(namespace_exports(head_txt), namespace_exports(base_txt))
  out <- character(0)
  if (length(added)) {
    out <- c(out, sprintf("Exports added (%d): %s", length(added),
                          paste(added, collapse = ", ")))
  }
  if (!length(gone)) {
    return(list(status = 0L, out = c(out, "No exports removed.")))
  }
  out <- c(out, sprintf("Exports removed (%d): %s", length(gone),
                        paste(gone, collapse = ", ")))
  if ("exports-reviewed" %in% labels) {
    return(list(status = 0L, out = c(out,
      "Allowed: the pull request carries the label exports-reviewed.")))
  }
  list(status = 1L, out = c(out, paste(
    "Removing an export breaks code that calls it. List each one under",
    "\"## Removed\" in NEWS.md with what to use instead, have the change",
    "reviewed, and add the label exports-reviewed to the pull request.")))
}

# NAMESPACE at a ref, or no lines when the ref has none.
namespace_at <- function(ref) {
  out <- suppressWarnings(system2("git", shQuote(c("show", paste0(ref, ":NAMESPACE"))),
                                  stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(out, "status"))) character(0) else out
}

check_namespace <- function() {
  mb <- git("merge-base", base, head)[1]
  v <- namespace_verdict(namespace_at(mb), namespace_at(head), labels)
  cat(v$out, sep = "\n")
  v$status
}

# ---------------------------------------------------------------------------
# commits
# ---------------------------------------------------------------------------

# Hosts of chat and assistant sessions. A link to any of them in a commit
# message points at a conversation, not at the change.
chat_hosts <- c("claude[.]ai", "chatgpt[.]com", "chat[.]openai[.]com",
                "gemini[.]google[.]com", "g[.]co/gemini", "bard[.]google[.]com",
                "copilot[.]microsoft[.]com", "perplexity[.]ai", "poe[.]com",
                "chat[.]deepseek[.]com", "chat[.]mistral[.]ai", "huggingface[.]co/chat")

commit_rules <- list(
  "a Co-Authored-By trailer" = "^[[:space:]]*co-authored-by[[:space:]]*:",
  "a chat or session link" = paste0("(^|[^a-z0-9.-])(", paste(chat_hosts, collapse = "|"),
                                    ")([/:?#[:space:]]|$)"),
  "a session trailer" = "^[[:space:]]*[a-z0-9-]*session[[:space:]]*:[[:space:]]*https?://",
  "a \"Generated with\" line" = "^[^[:alnum:]]*generated with([^[:alnum:]]|$)"
)

# What is wrong with one commit message: for each rule it breaks, the rule's
# name and the first line that breaks it. Matching ignores case.
commit_problems <- function(msg) {
  lines <- unlist(strsplit(paste(msg, collapse = "\n"), "\n", fixed = TRUE))
  out <- character(0)
  for (rule in names(commit_rules)) {
    hit <- grep(commit_rules[[rule]], lines, ignore.case = TRUE, perl = TRUE, value = TRUE)
    if (length(hit)) out <- c(out, sprintf("%s: %s", rule, trimws(hit[1])))
  }
  out
}

# The verdict on a set of commit messages, named by commit: status 0 or 1,
# and the lines to print.
commits_verdict <- function(messages) {
  if (!length(messages)) return(list(status = 0L, out = "No commits to check."))
  ids <- names(messages) %||% rep("", length(messages))
  out <- character(0)
  bad <- 0L
  for (i in seq_along(messages)) {
    p <- commit_problems(messages[[i]])
    if (!length(p)) next
    bad <- bad + 1L
    subject <- strsplit(messages[[i]], "\n", fixed = TRUE)[[1]][1]
    out <- c(out, sprintf("%s %s", substr(ids[i], 1L, 10L), subject), paste0("  ", p))
  }
  if (!bad) {
    return(list(status = 0L, out = sprintf("%d commit message(s) checked, none with an %s",
                                           length(messages),
                                           "attribution trailer, chat link or generator line.")))
  }
  list(status = 1L, out = c(sprintf("%d of %d commit message(s) need rewording:", bad,
                                    length(messages)),
                            out,
                            paste("Commit messages carry no attribution trailers, chat or",
                                  "session links or \"Generated with\" lines. Reword the",
                                  "commits (git rebase) and push again.")))
}

# The messages of the commits in base..head, named by commit, oldest first.
commit_messages <- function() {
  raw <- git("log", "--reverse", "--format=%H%x1f%B%x1e", paste0(base, "..", head))
  recs <- strsplit(paste(raw, collapse = "\n"), "\x1e", fixed = TRUE)[[1]]
  recs <- sub("^\n+", "", recs)
  recs <- recs[nzchar(trimws(recs))]
  parts <- strsplit(recs, "\x1f", fixed = TRUE)
  stats::setNames(vapply(parts, function(x) paste(x[-1], collapse = ""), character(1)),
                  vapply(parts, `[`, character(1), 1L))
}

check_commits <- function() {
  v <- commits_verdict(commit_messages())
  cat(v$out, sep = "\n")
  v$status
}

# ---------------------------------------------------------------------------
# Run as a script. Sourced, the file stops here having defined its functions.
# ---------------------------------------------------------------------------

if (sys.nframe() == 0L) {
  modes <- c("tests", "deps", "lint", "namespace", "commits")
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 3L || !args[[1]] %in% modes) {
    cat("usage: Rscript dev/ci/pr-checks.R <", paste(modes, collapse = "|"),
        "> <base> <head>\n", sep = "")
    quit(status = 2)
  }
  check <- args[[1]]
  base  <- args[[2]]
  head  <- args[[3]]

  labels <- trimws(strsplit(Sys.getenv("PR_LABELS"), ",", fixed = TRUE)[[1]])
  labels <- labels[nzchar(labels)]

  status <- switch(check,
                   tests     = check_tests(),
                   deps      = check_deps(),
                   lint      = check_lint(),
                   namespace = check_namespace(),
                   commits   = check_commits())
  quit(status = status)
}
