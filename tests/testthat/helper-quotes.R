# helper-quotes.R: the labelled quotation set and the rates both quote
# matchers reach on it, for test-verify-match.R and dev/quote-matcher-rates.R.
# Nothing here runs on load.
#
# The set is written by dev/build-quote-fixture.R; see there for what each
# variant is.

quote_fixture_dir <- function(root = NULL) {
  if (!is.null(root)) return(file.path(root, "tests", "testthat", "fixtures", "quotes"))
  testthat::test_path("fixtures", "quotes")
}

quote_fixture <- function(root = NULL) {
  dir <- quote_fixture_dir(root)
  tab <- utils::read.csv(file.path(dir, "labelled.csv"), stringsAsFactors = FALSE,
                         encoding = "UTF-8")
  tab$quote <- enc2utf8(tab$quote)
  files <- unique(tab$source)
  text <- vapply(files, function(f) {
    enc2utf8(paste(readLines(file.path(dir, f), encoding = "UTF-8", warn = FALSE),
                   collapse = "\n"))
  }, character(1))
  tab$source_text <- unname(text[tab$source])
  tab
}

# Each quotation through both matchers: `old` is span_match()'s `verified`;
# `new` is TRUE when match_span() says verbatim or near_verbatim, and
# `new_verbatim` when it says verbatim. The two readings of the new matcher
# are kept apart because near_verbatim is reported, never counted as
# verified.
quote_fixture_scored <- function(tab = quote_fixture()) {
  old <- vapply(seq_len(nrow(tab)), function(i) {
    isTRUE(harnessr:::span_match(tab$quote[i], tab$source_text[i])$verified)
  }, logical(1))
  shadow <- lapply(seq_len(nrow(tab)), function(i) {
    harnessr:::match_span(tab$quote[i], tab$source_text[i])
  })
  tab$old <- old
  tab$status <- vapply(shadow, `[[`, "", "status")
  tab$sim <- vapply(shadow, function(s) as.numeric(s$sim), numeric(1))
  tab$new <- tab$status %in% c("verbatim", "near_verbatim")
  tab$new_verbatim <- tab$status == "verbatim"
  tab
}

# A rate with its exact (Clopper-Pearson) 95% interval.
cp_rate <- function(x, n) {
  if (!n) return(c(x = 0, n = 0, rate = NA_real_, lower = NA_real_, upper = NA_real_))
  ci <- stats::binom.test(x, n)$conf.int
  c(x = x, n = n, rate = x / n, lower = ci[1L], upper = ci[2L])
}

# False rejections (true quotations not accepted) and false acceptances
# (false ones accepted) for each matcher, overall and by variant.
quote_matcher_rates <- function(scored = quote_fixture_scored()) {
  one <- function(d, label) {
    rows <- lapply(c("old", "new_verbatim", "new"), function(m) {
      acc <- d[[m]]
      x <- if (label) sum(!acc) else sum(acc)
      r <- cp_rate(x, nrow(d))
      data.frame(matcher = m, x = r[["x"]], n = r[["n"]], rate = r[["rate"]],
                 lower = r[["lower"]], upper = r[["upper"]])
    })
    do.call(rbind, rows)
  }
  pieces <- list()
  for (label in c(TRUE, FALSE)) {
    d <- scored[scored$label == label, , drop = FALSE]
    what <- if (label) "false rejection" else "false acceptance"
    pieces[[length(pieces) + 1L]] <- cbind(measure = what, variant = "all", one(d, label))
    for (v in sort(unique(d$variant))) {
      pieces[[length(pieces) + 1L]] <- cbind(measure = what, variant = v,
                                             one(d[d$variant == v, , drop = FALSE], label))
    }
  }
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}
