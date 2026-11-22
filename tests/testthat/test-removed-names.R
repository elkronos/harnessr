# test-removed-names.R: what NEWS.md lists under "## Removed" stays removed.
#
# Each row of that table names a removed function (`answer_question()`), an
# option (`options(readgpt.api_key =)`), a field of a result
# (gr_calibrate()'s `$kappa_legacy`) or a condition class (`gr_deprecated`).
# A function must not come back as an export or as a function defined in the
# namespace. Every name, whatever it is, must not come back as an object of
# the namespace or as a string, symbol or argument name in the code of any of
# its functions. NEWS.md is installed with the package, so this runs on the
# installed copy.

# The rows of the table under the first "## Removed" heading.
removed_rows <- function(news) {
  start <- grep("^## Removed[[:space:]]*$", news)[1]
  if (is.na(start)) return(character(0))
  end <- grep("^## ", news)
  end <- c(end[end > start], length(news) + 1L)[1]
  rows <- grep("^\\|", news[seq(start + 1L, end - 1L)], value = TRUE)
  # Drop the header and the |---| line, then keep the first cell.
  rows <- rows[-(1:2)]
  trimws(vapply(strsplit(rows, "|", fixed = TRUE), `[`, character(1), 2L))
}

# One removed thing from a first cell: what kind it is and its name.
removed_item <- function(cell) {
  ticks <- regmatches(cell, gregexpr("`[^`]+`", cell))[[1]]
  ticks <- gsub("`", "", ticks)
  field <- grep("^[$]", ticks, value = TRUE)
  if (length(field)) return(c(kind = "field", name = sub("^[$]", "", field[1])))
  opt <- grep("^options[(]", ticks, value = TRUE)
  if (length(opt)) {
    return(c(kind = "option", name = trimws(sub("^options[(]([^=)]+).*$", "\\1", opt[1]))))
  }
  fun <- grep("[(][)]$", ticks, value = TRUE)
  if (length(fun)) return(c(kind = "function", name = sub("[(][)]$", "", fun[1])))
  c(kind = "name", name = ticks[1])
}

removed_items <- function() {
  path <- system.file("NEWS.md", package = "harnessr")
  if (!nzchar(path)) path <- test_path("..", "..", "NEWS.md")
  news <- readLines(path, warn = FALSE, encoding = "UTF-8")
  items <- lapply(removed_rows(news), removed_item)
  data.frame(kind = vapply(items, `[[`, character(1), "kind"),
             name = vapply(items, `[[`, character(1), "name"),
             stringsAsFactors = FALSE)
}

# Every string, symbol and argument name in a function or a piece of code.
# Argument names count because a removed option or field comes back as one:
# options(readgpt.api_key = k), list(kappa_legacy = kappa).
code_walk <- function(x) {
  if (is.function(x)) return(c(code_walk(formals(x)), code_walk(body(x))))
  if (is.character(x)) return(x)
  if (is.name(x)) return(as.character(x))
  if (is.call(x) || is.pairlist(x) || is.list(x)) {
    tags <- names(x)
    return(c(tags[!is.na(tags) & nzchar(tags)],
             unlist(lapply(as.list(x), code_walk), use.names = FALSE)))
  }
  character(0)
}

# The atoms of every function in the namespace.
code_atoms <- function() {
  ns <- asNamespace("harnessr")
  objs <- ls(ns, all.names = TRUE)
  funs <- Filter(function(n) is.function(get(n, envir = ns)), objs)
  unique(unlist(lapply(funs, function(n) code_walk(get(n, envir = ns))), use.names = FALSE))
}

test_that("the code walk sees strings, symbols and argument names", {
  f <- function(k) {
    old <- options(readgpt.api_key = k)
    out <- structure(list(kappa = 1, kappa_legacy = 2), class = c(gr_deprecated = "x"))
    getOption("readgpt.allow_local_urls")
    out$old_field
  }
  atoms <- code_walk(f)
  for (a in c("readgpt.api_key", "kappa_legacy", "gr_deprecated",
              "readgpt.allow_local_urls", "old_field", "k")) {
    expect_true(a %in% atoms, label = a)
  }
})

test_that("the Removed table of NEWS.md is read", {
  items <- removed_items()
  expect_gte(nrow(items), 11L)
  expect_true(all(nzchar(items$name) & !is.na(items$name)))
  expect_true("answer_question" %in% items$name[items$kind == "function"])
  expect_true("readgpt.api_key" %in% items$name[items$kind == "option"])
  expect_true("kappa_legacy" %in% items$name[items$kind == "field"])
  expect_true("gr_deprecated" %in% items$name[items$kind == "name"])
})

test_that("no removed function is exported or defined again", {
  items <- removed_items()
  funs <- items$name[items$kind == "function"]
  expect_gt(length(funs), 0L)
  ns <- asNamespace("harnessr")
  back <- funs[funs %in% getNamespaceExports("harnessr") |
                 vapply(funs, exists, logical(1), envir = ns, inherits = FALSE)]
  expect(length(back) == 0,
         sprintf("Removed in NEWS.md but back in the namespace: %s.",
                 paste(back, collapse = ", ")))
})

test_that("no removed option, field or class is named in the code again", {
  items <- removed_items()
  atoms <- code_atoms()
  expect_true("harnessr.api_key" %in% atoms)
  back <- items$name[items$name %in% atoms |
                       items$name %in% ls(asNamespace("harnessr"), all.names = TRUE)]
  expect(length(back) == 0,
         sprintf("Removed in NEWS.md but named in the package code again: %s.",
                 paste(back, collapse = ", ")))
})
