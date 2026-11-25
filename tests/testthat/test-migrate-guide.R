# test-migrate-guide.R: the tables in vignettes/migrate.Rmd match NAMESPACE
# and NEWS.md.
#
# Each table has three columns: old, new and what to change. Every function in
# an old cell must not be exported, and every function in a new cell must be.
# The core table must hold exactly the renames NEWS.md lists under "## Renamed
# core functions", and the other tables must cover the "## Removed" table, so
# test-removed-names.R guards every old name the guide lists. Each removed
# name's replacement, and the reader a gr_read() call names, must be the one
# NEWS.md gives, and the reader must exist. This reads the source tree when it
# is there, and otherwise the copy of the vignette that a built package
# installs in doc/. An install without vignettes skips.

migrate_lines <- function() {
  path <- test_path("..", "..", "vignettes", "migrate.Rmd")
  if (!file.exists(path)) path <- system.file("doc", "migrate.Rmd", package = "harnessr")
  skip_if_not(nzchar(path) && file.exists(path), "migrate.Rmd is not installed")
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

# A row's NEWS.md "Removed" entry, found by the old name, and the guide row
# with the same old name.
removed_pairs <- function() {
  news <- section_table(news_lines(), "^## Removed[[:space:]]*$")
  tabs <- migrate_tables()
  guide <- rbind(tabs$other, tabs$v1)
  news_old <- vapply(news[, 1], function(x) old_item(x)[["name"]], "", USE.NAMES = FALSE)
  guide_old <- vapply(guide[, 1], function(x) old_item(x)[["name"]], "", USE.NAMES = FALSE)
  rows <- match(news_old, guide_old)
  list(news = news, guide = guide[rows, , drop = FALSE], old = news_old, rows = rows)
}

# The reader named in a cell: `reader = "x"` in NEWS.md, or the quoted last
# argument of `gr_read(...)` in the guide.
cell_reader <- function(cell) {
  m <- regmatches(cell, regexec("reader = \"([a-z_]+)\"", cell))[[1]]
  if (length(m)) return(m[2])
  m <- regmatches(cell, regexec("gr_read[(][^)]*\"([a-z_]+)\"[)]", cell))[[1]]
  if (length(m)) return(m[2])
  NA_character_
}

test_that("each removed name's replacement in the guide is the one NEWS.md gives", {
  p <- removed_pairs()
  expect(!anyNA(p$rows),
         sprintf("Removed in NEWS.md but not in vignettes/migrate.Rmd: %s.",
                 paste(p$old[is.na(p$rows)], collapse = ", ")))
  expect_identical(nrow(p$guide), nrow(p$news))
  for (i in seq_len(nrow(p$news))) {
    news_new <- p$news[i, 2]
    guide_new <- p$guide[i, 2]
    # The first thing each New cell names is the same function, field or
    # option, and the guide names no function NEWS.md does not. A field's
    # cell may name the function the field belongs to, as the old cell does.
    expect_identical(old_item(guide_new), old_item(news_new), info = p$old[i])
    extra <- setdiff(cell_functions(guide_new),
                     c(cell_functions(news_new), cell_functions(p$guide[i, 1])))
    expect(length(extra) == 0,
           sprintf("vignettes/migrate.Rmd pairs %s with %s, which NEWS.md does not.",
                   p$old[i], paste(extra, collapse = ", ")))
  }
})

test_that("the reader the guide names for each removed reader is the one NEWS.md gives", {
  p <- removed_pairs()
  news_readers <- vapply(p$news[, 2], cell_reader, "", USE.NAMES = FALSE)
  guide_readers <- vapply(p$guide[, 3], cell_reader, "", USE.NAMES = FALSE)
  expect_gte(sum(!is.na(news_readers)), 4L)
  expect_identical(guide_readers, news_readers)
  named <- guide_readers[!is.na(guide_readers)]
  unknown <- setdiff(named, gr_readers()$name)
  expect(length(unknown) == 0,
         sprintf("vignettes/migrate.Rmd names readers that do not exist: %s.",
                 paste(unknown, collapse = ", ")))
  # No other cell in the guide calls gr_read() with a reader.
  tabs <- do.call(rbind, migrate_tables())
  all_readers <- vapply(tabs[, 3], cell_reader, "", USE.NAMES = FALSE)
  expect_identical(sum(!is.na(all_readers)), length(named))
})
