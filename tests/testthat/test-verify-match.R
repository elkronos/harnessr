# The edit-distance quote matcher (shadow mode) and verify = TRUE.

ms <- function(q, s, ...) harnessr:::match_span(q, s, ...)

test_that("normalisation folds ligatures, line-break hyphens, escapes and quote marks", {
  norm <- harnessr:::normalise_quote_text
  expect_identical(norm("eﬃcacy and ﬂuid"), "efficacy and fluid")
  expect_identical(norm("the investi-\ngator  said"), norm("the investigator said"))
  expect_identical(norm("\\\"Revenue rose\\nsharply\\\""), norm("\"Revenue rose sharply\""))
  expect_identical(norm("“Revenue”"), norm("\"revenue\""))
  expect_identical(norm("soft­hyphen"), "softhyphen")
  expect_identical(norm("ＡＢＣ"), "abc")
  # A superscript digit is not folded: 10 to the 6th is not 106.
  expect_false(identical(norm("10⁶"), norm("106")))
})

test_that("a quotation with line-break hyphenation and curly quotes is verbatim", {
  src <- "The \"investigator-\nblinded\" assessment found no change in 2024."
  r <- ms("the “investigator-blinded” assessment found no change", src)
  expect_identical(r$status, "verbatim")
  expect_identical(r$sim, 1)
  expect_true(r$critical_ok)
})

test_that("similarity falls by the same step for each edit wherever it falls", {
  src <- "In the main analysis the drug did not reduce mortality at twelve months in all of the arms."
  q <- "the drug did not reduce mortality at twelve months in all of"
  expect_identical(nchar(q), 60L)
  at <- list(start = c(2, 5, 8, 11, 14), middle = c(22, 25, 28, 31, 34),
             end = nchar(q) - c(1, 4, 7, 10, 13))
  for (where in names(at)) {
    sims <- vapply(0:5, function(k) {
      chars <- strsplit(q, "")[[1]]
      chars[at[[where]][seq_len(k)]] <- "x"
      ms(paste(chars, collapse = ""), src)$sim
    }, numeric(1))
    expect_true(all(diff(sims) < 0), info = where)
    expect_equal(sims, 1 - (0:5) / 60, tolerance = 1e-3, info = where)
  }
})

test_that("a changed number or negation fails however similar the quotation is", {
  src <- paste("Overall, 25% of patients had nausea and the drug did not reduce",
               "mortality at 12 months. Change in revenue: -12% year on year.")
  for (q in c("Overall, 2.5% of patients had nausea and the drug did not reduce mortality",
              "Overall, 25% of patients had nausea and the drug did now reduce mortality",
              "Overall, 25% of patients had nausea and the drug did not reduce mortality at 13 months")) {
    r <- ms(q, src)
    expect_gt(r$sim, 0.95)
    expect_false(r$critical_ok, info = q)
    expect_identical(r$status, "unverified", info = q)
  }
  # Whole numbers, with their sign: not "5%" inside "25%", nor "12%" in "-12%".
  expect_identical(ms("5% of patients had nausea", src)$status, "unverified")
  expect_identical(ms("revenue: 12% year on year", src)$status, "unverified")
  expect_identical(ms("revenue: -12% year on year", src)$status, "verbatim")
  # A unit is part of the number it follows.
  expect_identical(ms("revenue of 45.2 billion dollars in 2024",
                      "Revenue of 45.2 million dollars in 2024.")$status, "unverified")
})

test_that("a changed number word or comparison sign fails as a changed digit does", {
  src <- paste("The company does not currently hedge beyond twelve months of forecast",
               "exposure. Seven of the ten sites enrolled patients in the first quarter.",
               "Mortality was lower in the treated group (p = 0.04) and higher in controls.")
  for (q in c("The company does not currently hedge beyond eleven months of forecast exposure.",
              "Seven of the nine sites enrolled patients in the first quarter.",
              "Six of the ten sites enrolled patients in the first quarter.",
              "Mortality was lower in the treated group (p < 0.04) and higher in controls.",
              "Mortality was lower in the treated group (p \u2264 0.04) and higher in controls.")) {
    r <- ms(q, src)
    expect_gt(r$sim, 0.90)
    expect_false(r$critical_ok, info = q)
    expect_identical(r$status, "unverified", info = q)
  }
  expect_identical(ms("Seven of the ten sites enrolled patients", src)$status, "verbatim")
  expect_identical(ms("lower in the treated group (p = 0.04) and higher", src)$status,
                   "verbatim")
})

test_that("a passage too long to score is not_checked for size, not as empty", {
  src <- "Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024."
  r <- ms("Northwind Instruments reported revenue of 45.2 milion dollars", src, max_cells = 100)
  expect_identical(r$status, "not_checked")
  expect_identical(r$method, "too_long")
  # Found as written, it needs no table and is scored whatever its size.
  r <- ms("Northwind Instruments reported revenue", src, max_cells = 100)
  expect_identical(r$status, "verbatim")
  expect_identical(r$method, "edit_window")
  expect_identical(ms("", src)$method, "edit_window")
})

test_that("near_verbatim needs the length, the threshold and five words", {
  src <- "Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024."
  # An OCR letter error in a long quotation.
  r <- ms("Northwind Instrurnents reported revenue of 45.2 million dollars", src)
  expect_identical(r$status, "near_verbatim")
  expect_gte(r$sim, 0.90)
  # Short quotations: under five words, only an exact match.
  expect_identical(ms("Northwind Instrurnents", src)$status, "unverified")
  expect_identical(ms("Northwind Instruments", src)$status, "verbatim")
  # An invented sentence is far from anything.
  expect_identical(ms("The board approved a share buyback programme.", src)$status, "unverified")
  expect_identical(ms("", src)$status, "not_checked")
  expect_identical(ms("revenue", "")$status, "not_checked")
})

test_that("an elided quotation takes the worst of its passages", {
  src <- "Revenue rose 12% in 2024. Costs were flat. Margins improved to 41 percent."
  expect_identical(ms("Revenue rose 12% ... Margins improved to 41 percent", src)$status,
                   "verbatim")
  expect_identical(ms("Revenue rose 12% ... Margins improved to 44 percent", src)$status,
                   "unverified")
})

test_that("verify_spans records the shadow matcher beside verified and match", {
  v <- harnessr:::verify_spans(c("revenue of 45.2 million", "revenue of 88 million", "x"),
                               c("Revenue of 45.2 million dollars.", "Revenue of 45.2 million.",
                                 NA))
  expect_named(v, c("verified", "match", "quote_status", "quote_sim", "quote_coverage",
                    "quote_edits", "quote_critical_ok"))
  expect_identical(v$verified, c(TRUE, FALSE, NA))
  expect_identical(v$quote_status, c("verbatim", "unverified", "not_checked"))
  expect_identical(v$quote_critical_ok, c(TRUE, FALSE, NA))
  # The old score is still the one recorded as `match`.
  expect_equal(v$match[2], harnessr:::span_match("revenue of 88 million",
                                                 "Revenue of 45.2 million.")$match)
})

test_that("both matchers' rates on the labelled quotation set", {
  scored <- quote_fixture_scored()
  rates <- quote_matcher_rates(scored)
  get <- function(measure, variant, matcher) {
    rates[rates$measure == measure & rates$variant == variant & rates$matcher == matcher, ]
  }
  expect_gte(sum(scored$label), 200L)
  expect_true(all(scored$status %in% harnessr:::.gr_quote_statuses))
  # Every true quotation in the clean variants is accepted by both.
  for (v in c("exact", "clause")) {
    expect_identical(get("false rejection", v, "old")$x, 0, info = v)
    expect_identical(get("false rejection", v, "new")$x, 0, info = v)
  }
  # The new matcher rejects at most 2% of true quotations overall, fewer than
  # the old one, and no hyphenation, ligature or typographic variant.
  new <- get("false rejection", "all", "new")
  old <- get("false rejection", "all", "old")
  expect_lte(new$rate, 0.02)
  expect_lt(new$upper, old$lower)
  for (v in c("hyphenation", "ligature", "ligature_in_quote", "typographic")) {
    expect_identical(get("false rejection", v, "new")$x, 0, info = v)
  }
  # No changed number (in digits or in words), changed comparison sign,
  # flipped negation or invented sentence gets through either matcher.
  for (v in c("number_changed", "number_word_changed", "comparison_changed",
              "negation_flipped", "invented")) {
    expect_identical(get("false acceptance", v, "old")$x, 0, info = v)
    expect_identical(get("false acceptance", v, "new")$x, 0, info = v)
  }
  expect_gte(get("false acceptance", "number_changed", "new")$n, 30)
  # Reading near_verbatim as verified would let a swapped word through, which
  # is why it is reported apart and gates nothing.
  expect_gt(get("false acceptance", "word_swapped", "new")$x, 0)
  expect_identical(get("false acceptance", "all", "new_verbatim")$x, 0)
  # The intervals are exact binomial ones.
  expect_equal(c(new$lower, new$upper),
               stats::binom.test(new$x, new$n)$conf.int[1:2])
})

# verify = TRUE ----------------------------------------------------------------

iter_chunks <- function() {
  quiet(gr_segment(gr_example(), list(method = "paragraph", max_tokens = 80)))
}

# An iterative step that says it can answer, with the quotations given.
iter_step <- function(answer, quotes, next_query = "") {
  as.character(jsonlite::toJSON(list(can_answer = TRUE, answer = answer,
                                     next_query = next_query,
                                     quotes = quotes), auto_unbox = TRUE))
}

test_that("verify is a spec field only when TRUE and is checked", {
  expect_null(gr_read_spec("iterative")$verify)
  expect_true(gr_read_spec("iterative", verify = TRUE)$verify)
  expect_error(gr_read_spec("iterative", verify = NA), class = "gr_bad_setting")
  expect_error(gr_read_spec("iterative", verify = "yes"), class = "gr_bad_setting")
})

test_that("by default the iterative step sends what it always sent", {
  ch <- iter_chunks()
  cl <- gr_mock_client(function(m, p) {
    if (grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) {
      return('{"can_answer": true, "answer": "Revenue was 45.2 million.", "next_query": ""}')
    }
    "x"
  })
  a <- quiet(gr_read(ch, "What was revenue?", cl, "iterative"))
  step <- Filter(function(c) identical(c$label, "iterative.step"), cl$calls())[[1]]
  expect_false("quotes" %in% names(step$params$schema$properties))
  expect_length(step$messages, 3L)
  expect_false(any(grepl("quotes", vapply(step$messages, `[[`, "", "content"))))
  expect_identical(unique(a$evidence$kind), "verbatim")
  expect_null(a$notes$quotes_checked)
  expect_false("read.verify" %in% vapply(a$trace$steps, `[[`, "", "label"))
})

test_that("verify = TRUE: a fabricated quotation does not stop the loop", {
  ch <- iter_chunks()
  seen <- list()
  cl <- gr_mock_client(function(m, p) {
    if (!grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) return("x")
    seen[[length(seen) + 1L]] <<- m
    if (length(seen) == 1L) {
      return(iter_step("Revenue was 88 million.",
                       list(list(chunk_id = 2L, text = "revenue of 88.0 million dollars"))))
    }
    iter_step("Revenue was 45.2 million.",
              list(list(chunk_id = 2L,
                        text = "reported revenue of 45.2 million dollars in fiscal 2024")))
  })
  a <- quiet(gr_read(ch, "What was revenue in 2024?", cl,
                     gr_read_spec("iterative", verify = TRUE, top_k = 3L)))
  expect_length(seen, 2L)
  # The second prompt names the refused quotation and its chunk.
  last <- seen[[2]][[length(seen[[2]])]]$content
  expect_match(last, "revenue of 88.0 million dollars", fixed = TRUE)
  expect_match(last, "[chunk 2]", fixed = TRUE)
  expect_identical(a$answer, "Revenue was 45.2 million.")
  expect_false(a$partial)
  expect_identical(a$notes$quotes_rejected_steps, 1L)
  # The evidence is the cited chunk, not every chunk shown.
  expect_identical(a$evidence$chunk_id, 2L)
  expect_identical(a$evidence$kind, "extracted")
  expect_true(a$evidence$verified)
  expect_identical(a$evidence$quote_status, "verbatim")
  expect_gt(length(a$chunks_used), 1L)
  labels <- vapply(a$trace$steps, `[[`, "", "label")
  expect_true(all(c("iterative.unverified", "read.verify") %in% labels))
})

test_that("verify = TRUE: a step with a verified quotation stops at once", {
  ch <- iter_chunks()
  cl <- gr_mock_client(function(m, p) {
    if (!grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) return("x")
    iter_step("Revenue was 45.2 million.",
              list(list(chunk_id = 2L,
                        text = "Northwind Instruments reported revenue of 45.2 million dollars")))
  })
  a <- quiet(gr_read(ch, "What was revenue in 2024?", cl,
                     gr_read_spec("iterative", verify = TRUE, top_k = 20L)))
  step <- Filter(function(c) identical(c$label, "iterative.step"), cl$calls())
  expect_length(step, 1L)
  expect_true("quotes" %in% names(step[[1]]$params$schema$properties))
  expect_identical(a$notes$stop_reason, "model satisfied")
  expect_identical(a$evidence$chunk_id, 2L)
})

test_that("verify = TRUE: a refusal is sent back after retrieval has run out", {
  ch <- iter_chunks()
  seen <- list()
  cl <- gr_mock_client(function(m, p) {
    if (!grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) return("x")
    seen[[length(seen) + 1L]] <<- m
    if (length(seen) == 1L) {
      return(iter_step("Revenue was 88 million.",
                       list(list(chunk_id = 2L, text = "revenue of 88.0 million dollars"))))
    }
    iter_step("Revenue was 45.2 million.",
              list(list(chunk_id = 2L,
                        text = "reported revenue of 45.2 million dollars in fiscal 2024")))
  })
  # top_k covers the document, so the first round takes every chunk and the
  # second has none left to add.
  a <- quiet(gr_read(ch, "What was revenue in 2024?", cl,
                     gr_read_spec("iterative", verify = TRUE,
                                  top_k = nrow(ch$chunks) + 5L)))
  step <- Filter(function(c) identical(c$label, "iterative.step"), cl$calls())
  expect_length(step, 2L)
  last <- seen[[2]][[length(seen[[2]])]]$content
  expect_match(last, "revenue of 88.0 million dollars", fixed = TRUE)
  expect_identical(a$notes$stop_reason, "model satisfied")
  expect_identical(a$answer, "Revenue was 45.2 million.")
  expect_identical(a$notes$quotes_rejected_steps, 1L)
})

test_that("verify = TRUE with premise = TRUE: a premise verdict needs no quotation", {
  ch <- iter_chunks()
  cl <- gr_mock_client(function(m, p) {
    if (grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) {
      return(paste0('{"can_answer": false, "answer": "Revenue rose in 2024.", ',
                    '"next_query": "", "false_premise": true, "quotes": []}'))
    }
    "x"
  })
  q <- "Why did revenue fall in 2024?"
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("iterative", verify = TRUE, premise = TRUE,
                                             max_rounds = 2L)))
  b <- quiet(gr_read(ch, q, cl, gr_read_spec("iterative", premise = TRUE, max_rounds = 2L)))
  expect_identical(a$notes$stop_reason, "premise contradicted")
  expect_identical(a$answer, b$answer)
  expect_identical(a$premise, b$premise)
  expect_true(is_nonblank(a$premise))
  expect_identical(a$notes$quotes_rejected_steps, 0L)
  expect_identical(unique(a$evidence$kind), "verbatim")
})

test_that("verify = TRUE: a quotation from a chunk not shown does not count", {
  ch <- iter_chunks()
  cl <- gr_mock_client(function(m, p) {
    if (!grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) return("x")
    # Chunk 99 does not exist; the text is real but cited to nothing.
    iter_step("Revenue was 45.2 million.",
              list(list(chunk_id = 99L,
                        text = "Northwind Instruments reported revenue of 45.2 million dollars")))
  })
  a <- quiet(gr_read(ch, "What was revenue in 2024?", cl,
                     gr_read_spec("iterative", verify = TRUE, top_k = 3L, max_rounds = 2L)))
  expect_true(is_not_found(a$answer))
  expect_true(a$partial)
  expect_identical(a$notes$unverified_answer, "Revenue was 45.2 million.")
  expect_identical(a$notes$quotes_rejected_steps, 2L)
  # No final answer call is made from what was gathered.
  expect_false("iterative.final" %in% vapply(cl$calls(), `[[`, "", "label"))
})

test_that("verify = TRUE checks a skim answer's quotations and records the shadow status", {
  ch <- iter_chunks()
  cl <- gr_mock_client(function(m, p) "Revenue of 88.9 billion dollars on record demand.")
  a <- quiet(gr_read(ch, "What was revenue?", cl, gr_read_spec("skim", verify = TRUE)))
  expect_true(a$partial)
  expect_gt(a$notes$unverified_evidence, 0L)
  expect_true(all(c("quote_status", "quote_sim") %in% names(a$evidence)))
  expect_true(all(a$evidence$quote_status == "unverified"))
  st <- Filter(function(s) identical(s$label, "read.verify"), a$trace$steps)
  expect_length(st, 1L)
  expect_identical(st[[1]]$detail$failed, nrow(a$evidence))
})
