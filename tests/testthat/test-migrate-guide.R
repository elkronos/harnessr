# test-migrate-guide.R: the tables in vignettes/migrate.Rmd match NAMESPACE
# and NEWS.md.
#
# Each table has three columns: old, new and what to change. Every function in
# an old cell must not be exported, and every function in a new cell must be.
# The core table must hold exactly the renames NEWS.md lists under "## Renamed
# core functions", and the other tables must cover the "## Removed" table, so
# test-removed-names.R guards every old name the guide lists. The vignette
# source is not installed, so this runs from the source tree and skips under
# R CMD check.

migrate_lines <- function() {
  path <- test_path("..", "..", "vignettes", "migrate.Rmd")
  skip_if_not(file.exists(path), "vignettes/migrate.Rmd is not in an installed package")
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

# The source NEWS.md, beside the vignette, so both come from the same tree.
news_lines <- function() {
  path <- test_path("..", "..", "NEWS.md")
  if (!file.exists(path)) path <- system.file("NEWS.md", package = "harnessr")
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

# The table rows (header and |---| line dropped) under the first heading that
# matches `heading`, as a character matrix with one column per cell.
section_table <- function(lines, heading) {
  start <- grep(heading, lines)[1]
  if (is.na(start)) return(NULL)
  level <- sub("^(#+).*$", "\\1", lines[start])
  ends <- grep(sprintf("^#{1,%d} ", nchar(level)), lines)
  end <- c(ends[ends > start], length(lines) + 1L)[1]
  body <- lines[seq(start + 1L, end - 1L)]
  rows <- grep("^\\|", body, value = TRUE)[-(1:2)]
  cells <- lapply(strsplit(sub("\\|[[:space:]]*$", "", rows), "|", fixed = TRUE),
                  function(x) trimws(x[-1]))
  do.call(rbind, cells)
}

# Functions named in a cell: backticked `name()` with empty parentheses.
cell_functions <- function(cell) {
  ticks <- gsub("`", "", regmatches(cell, gregexpr("`[^`]+`", cell))[[1]])
  sub("[(][)]$", "", grep("^[A-Za-z.][A-Za-z0-9_.]*[(][)]$", ticks, value = TRUE))
}

# What an old cell names, read as test-removed-names.R reads NEWS.md: a field
# (`$x`), an option (`options(x =)`), a function (`x()`) or a plain name.
old_item <- function(cell) {
  ticks <- gsub("`", "", regmatches(cell, gregexpr("`[^`]+`", cell))[[1]])
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

migrate_headings <- c(
  core = "^## From readgpt 0[.]6[.]0: core functions",
  other = "^## From readgpt 0[.]6[.]0: the package",
  v1 = "^## From v1"
)

migrate_tables <- function() {
  lines <- migrate_lines()
  lapply(migrate_headings, function(h) section_table(lines, h))
}

test_that("the guide has its three tables, each with old, new and what to change", {
  lines <- migrate_lines()
  tabs <- migrate_tables()
  for (nm in names(tabs)) {
    expect_false(is.null(tabs[[nm]]), info = nm)
    expect_identical(ncol(tabs[[nm]]), 3L, info = nm)
    expect_true(all(nzchar(tabs[[nm]])), info = nm)
    start <- grep(migrate_headings[[nm]], lines)[1]
    header <- grep("^\\|", lines[-seq_len(start)], value = TRUE)[1]
    expect_identical(header, "| Old | New | What to change |", info = nm)
  }
  expect_identical(nrow(tabs$core), 27L)
  expect_identical(nrow(tabs$other), 6L)
  expect_identical(nrow(tabs$v1), 6L)
})

test_that("no old function in the guide is exported", {
  tabs <- do.call(rbind, migrate_tables())
  items <- lapply(tabs[, 1], old_item)
  funs <- vapply(Filter(function(i) i[["kind"]] == "function", items), `[[`, "", "name")
  expect_gte(length(funs), 27L + 7L)
  ns <- asNamespace("harnessr")
  back <- funs[funs %in% getNamespaceExports("harnessr") |
                 vapply(funs, exists, logical(1), envir = ns, inherits = FALSE)]
  expect(length(back) == 0,
         sprintf("Old in vignettes/migrate.Rmd but exported or defined: %s.",
                 paste(back, collapse = ", ")))
  # The package's old name is not the package's name.
  others <- vapply(Filter(function(i) i[["kind"]] == "name", items), `[[`, "", "name")
  expect_true("readgpt" %in% others)
  expect_false("readgpt" %in% c(utils::packageName(ns), getNamespaceExports("harnessr")))
})

test_that("every new function in the guide is exported, and every new option is read", {
  tabs <- do.call(rbind, migrate_tables())
  funs <- unique(unlist(lapply(tabs[, 2], cell_functions)))
  expect_gte(length(funs), 27L + 6L)
  missing <- setdiff(funs, getNamespaceExports("harnessr"))
  expect(length(missing) == 0,
         sprintf("New in vignettes/migrate.Rmd but not exported: %s.",
                 paste(missing, collapse = ", ")))
  # An old field's new cell names the same function, which stays exported.
  field_rows <- vapply(tabs[, 1], function(x) old_item(x)[["kind"]] == "field", logical(1))
  expect_true(all(unlist(lapply(tabs[field_rows, 1], cell_functions)) %in%
                    getNamespaceExports("harnessr")))
  # A new option is one some function reads.
  opts <- vapply(Filter(function(i) i[["kind"]] == "option", lapply(tabs[, 2], old_item)),
                 `[[`, "", "name")
  expect_identical(sort(opts), c("harnessr.allow_local_urls", "harnessr.api_key"))
  ns <- asNamespace("harnessr")
  code <- unlist(lapply(ls(ns, all.names = TRUE), function(n) {
    f <- get(n, envir = ns)
    if (is.function(f)) deparse(f) else character(0)
  }), use.names = FALSE)
  for (o in opts) expect_true(any(grepl(sprintf("\"%s\"", o), code, fixed = TRUE)), info = o)
})

test_that("the core table holds the renames NEWS.md lists, and only those", {
  news <- section_table(news_lines(), "^## Renamed core functions[[:space:]]*$")
  expect_false(is.null(news))
  expect_identical(nrow(news), 27L)
  pairs <- function(tab) {
    old <- vapply(tab[, 1], function(x) cell_functions(x)[1], "")
    new <- vapply(tab[, 2], function(x) cell_functions(x)[1], "")
    sort(paste(old, new, sep = " -> "))
  }
  expect_identical(pairs(migrate_tables()$core), pairs(news))
  expect_true(all(grepl("^gr_[a-z_]+ -> hr_[a-z_]+$", pairs(news))))
})

test_that("the guide lists every name NEWS.md removes", {
  news <- section_table(news_lines(), "^## Removed[[:space:]]*$")
  expect_false(is.null(news))
  removed <- vapply(news[, 1], function(x) old_item(x)[["name"]], "", USE.NAMES = FALSE)
  tabs <- migrate_tables()
  listed <- vapply(rbind(tabs$other, tabs$v1)[, 1], function(x) old_item(x)[["name"]], "",
                   USE.NAMES = FALSE)
  missing <- setdiff(removed, listed)
  expect(length(missing) == 0,
         sprintf("Removed in NEWS.md but not in vignettes/migrate.Rmd: %s.",
                 paste(missing, collapse = ", ")))
  # Every old name but the package's is in that table, so test-removed-names.R
  # keeps each one out of the code.
  expect_identical(sort(setdiff(listed, "readgpt")), sort(removed))
})
