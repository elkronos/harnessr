# test-guide-groups.R: the site's Guides menu and the README's Guides section
# list the same groups, and every vignette appears once.
#
# _pkgdown.yml and README.md are left out of the built package, so these tests
# read the source tree and skip when it is absent. The parser below reads only
# the articles: block, whose layout is fixed: "- title:", "navbar:", "desc: >"
# with indented lines, and "contents:" with "  - name" items.

guide_source <- function(...) {
  f <- testthat::test_path("..", "..", ...)
  if (file.exists(f)) normalizePath(f) else NULL
}

# One list per group: title, navbar (NA when absent), desc and contents.
pkgdown_article_groups <- function(path) {
  y <- readLines(path, warn = FALSE, encoding = "UTF-8")
  start <- grep("^articles:\\s*$", y)
  stopifnot(length(start) == 1L)
  tops <- grep("^[A-Za-z_]", y)
  end <- c(tops[tops > start], length(y) + 1L)[1]
  block <- y[seq(start + 1L, end - 1L)]
  heads <- grep("^- title:", block)
  lapply(seq_along(heads), function(i) {
    to <- c(heads[-1] - 1L, length(block))[i]
    g <- block[heads[i]:to]
    field <- function(name) {
      hit <- grep(sprintf("^\\s*(- )?%s:", name), g, value = TRUE)
      if (length(hit) == 0L) NA_character_
      else trimws(sub(sprintf("^\\s*-?\\s*%s:", name), "", hit[1]))
    }
    at <- grep("^\\s+contents:\\s*$", g)
    items <- if (length(at) == 1L) g[seq.int(at + 1L, length(g))] else character()
    items <- items[grepl("^\\s+- ", items)]
    d <- grep("^\\s+desc:", g)
    desc <- if (length(d) == 1L) {
      rest <- g[seq.int(d + 1L, length(g))]
      rest <- rest[seq_len(match(FALSE, grepl("^\\s{4,}\\S", rest), nomatch = length(rest) + 1L) - 1L)]
      paste(trimws(rest), collapse = " ")
    } else ""
    list(title = field("title"), navbar = field("navbar"), desc = desc,
         contents = trimws(sub("^\\s+- ", "", items)))
  })
}

test_that("the articles groups list every vignette once, each with a description", {
  skip_on_cran()
  yml <- guide_source("_pkgdown.yml")
  vig <- guide_source("vignettes")
  skip_if(is.null(yml) || is.null(vig), "the package source tree is not available")
  groups <- pkgdown_article_groups(yml)
  listed <- unlist(lapply(groups, `[[`, "contents"))
  vignettes <- sub("\\.Rmd$", "", list.files(vig, pattern = "\\.Rmd$"))

  expect_gt(length(groups), 1L)
  expect_false(anyDuplicated(listed) > 0L, info = paste(listed[duplicated(listed)], collapse = ", "))
  expect_setequal(listed, vignettes)
  for (g in groups) expect_true(nzchar(g$desc), info = g$title)

  # The get started guide has its own navbar link; every other group is a
  # heading in the Guides menu, named as on the articles index.
  expect_identical(groups[[1]]$contents, "harnessr")
  for (g in groups[-1]) expect_identical(g$navbar, g$title, info = g$title)
})

test_that("the README lists the guides under the site's groups, in the same order", {
  skip_on_cran()
  yml <- guide_source("_pkgdown.yml")
  readme <- guide_source("README.md")
  skip_if(is.null(yml) || is.null(readme), "the package source tree is not available")
  groups <- pkgdown_article_groups(yml)

  r <- readLines(readme, warn = FALSE, encoding = "UTF-8")
  start <- grep("^## Guides\\s*$", r)
  expect_length(start, 1L)
  ends <- grep("^## ", r)
  end <- c(ends[ends > start], length(r) + 1L)[1]
  sec <- r[seq(start + 1L, end - 1L)]

  heads <- grep("^### ", sec)
  expect_identical(sub("^### ", "", sec[heads]), vapply(groups, `[[`, "", "title"))
  for (i in seq_along(heads)) {
    to <- c(heads[-1] - 1L, length(sec))[i]
    items <- grep("^- \\[", sec[heads[i]:to], value = TRUE)
    names <- sub("^.*\\(`([A-Za-z0-9_.-]+)`\\):.*$", "\\1", items)
    expect_identical(names, groups[[i]]$contents, info = groups[[i]]$title)
    # Each link goes to that guide's page on the site.
    links <- sub("^- \\[[^]]+\\]\\(([^)]+)\\).*$", "\\1", items)
    expect_identical(links, sprintf("https://elkronos.github.io/harnessr/articles/%s.html", names),
                     info = groups[[i]]$title)
  }
})
