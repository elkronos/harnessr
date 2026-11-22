# test-pipeline-options.R: the opt-in pipeline options of package 6b. Each
# is off by default, so a default run sends and returns what it did before;
# the golden records check that. These tests check what each option does
# when it is on.

po_quiet <- function(expr) suppressWarnings(suppressMessages(expr))
po_text <- function(messages) {
  paste(vapply(messages, function(m) paste(as.character(m$content), collapse = "\n"),
               character(1)), collapse = "\n")
}

# ---------------------------------------------------------------------------
# P1D-08: per-field agreement and resolve = "vote"
# ---------------------------------------------------------------------------

# Three paragraphs, each its own chunk at max_tokens = 48: an abstract that
# says 240 and two results paragraphs that say 236.
po_sample_file <- function() {
  say <- function(w) paste(rep(sprintf("%s paragraph of the report goes on here at length.", w),
                               3), collapse = " ")
  f <- tempfile(fileext = ".txt")
  writeLines(paste(say("Abstract"), say("Results"), say("Followup"), sep = "\n\n"), f)
  f
}

po_sample_client <- function(choice = NULL) {
  gr_mock_client(function(messages, params) {
    txt <- po_text(messages)
    if (grepl("Choose the", txt, fixed = TRUE)) return(sprintf('{"choice":%d}', choice))
    ex <- sub(".*<excerpt>", "", txt)
    if (grepl("Abstract paragraph", ex, fixed = TRUE)) {
      return('{"n":240,"n__quote":"Abstract paragraph"}')
    }
    if (grepl("Results paragraph", ex, fixed = TRUE)) {
      return('{"n":236,"n__quote":"Results paragraph"}')
    }
    '{"n":236,"n__quote":"Followup paragraph"}'
  })
}

po_sample_fields <- function() {
  gr_fields(n = gr_field("Participants randomised", type = "integer"),
            arm = "A field no chunk reports")
}

test_that("agreement_columns is off by default and leaves the table as it was", {
  a <- po_sample_file()
  x <- po_quiet(gr_extract(a, po_sample_fields(), client = po_sample_client(),
                           recipe = "thorough", max_tokens = 48))
  expect_false(any(grepl("_agreement$|_conflict$", names(x$table))))
  expect_identical(x$table$n[1], 240L)
  expect_identical(x$table$conflicts[1], "n")
})

test_that("abstract 240 against results 236 twice: 240 by default, 2/3 agreement, a conflict", {
  a <- po_sample_file()
  cl <- po_sample_client()
  x <- po_quiet(gr_extract(a, po_sample_fields(), client = cl, recipe = "thorough",
                           max_tokens = 48, agreement_columns = TRUE))
  expect_identical(length(cl$calls()), 3L)
  expect_identical(x$table$n[1], 240L)
  expect_identical(x$table$n_agreement[1], "2/3")
  expect_true(x$table$n_conflict[1])
  # A field no chunk reported: no agreement to give, and no conflict.
  expect_true(is.na(x$table$arm_agreement[1]))
  expect_false(x$table$arm_conflict[1])
  # The pair sits after the field columns.
  expect_identical(match(c("n_agreement", "n_conflict", "arm_agreement", "arm_conflict"),
                         names(x$table)),
                   match("arm", names(x$table)) + 1:4)
})

test_that("resolve = 'vote' takes the majority and costs nothing extra", {
  a <- po_sample_file()
  cl <- po_sample_client()
  x <- po_quiet(gr_extract(a, po_sample_fields(), client = cl, recipe = "thorough",
                           max_tokens = 48, resolve = "vote", agreement_columns = TRUE))
  expect_identical(x$table$n[1], 236L)
  expect_identical(x$table$n_agreement[1], "2/3")
  expect_true(x$table$n_conflict[1])
  expect_identical(length(cl$calls()), 3L)
  # The evidence follows the value kept.
  expect_match(x$evidence$quote[x$evidence$field == "n"], "Results paragraph")
})

test_that("a vote tie goes to the earliest value, as 'first' chooses", {
  hits <- list(list(ok = TRUE, chunk = 1L, value = list(n = 5L, n__quote = "")),
               list(ok = TRUE, chunk = 2L, value = list(n = 7L, n__quote = "")))
  d <- data.frame(chunk_id = 1:2, text = c("five", "seven"), stringsAsFactors = FALSE)
  f <- gr_fields(n = gr_field("A count", type = "integer"))
  rec <- harnessr:::reconcile_fields(hits, f, d, NULL, list(resolve = "vote"), NULL)
  expect_identical(rec$record$n, 5L)
  expect_identical(rec$agreement[["n"]], "1/2")
  expect_named(rec$conflicts, "n")
})

test_that("a resolver that always picks option 1 still records the conflict", {
  a <- po_sample_file()
  cl <- po_sample_client(choice = 1L)
  x <- po_quiet(gr_extract(a, po_sample_fields(), client = cl, recipe = "thorough",
                           max_tokens = 48, resolve = "model", agreement_columns = TRUE))
  expect_identical(x$table$n[1], 240L)
  expect_true(x$table$n_conflict[1])
  expect_identical(x$table$n_agreement[1], "2/3")
  expect_identical(length(cl$calls()), 4L)
})

test_that("agreement_columns is checked, and refuses a field it would collide with", {
  a <- po_sample_file()
  expect_error(gr_extract(a, po_sample_fields(), client = po_sample_client(),
                          agreement_columns = NA), class = "gr_bad_setting")
  f <- gr_fields(n = gr_field("Count", type = "integer"), n_conflict = "Clashes")
  expect_error(gr_extract(a, f, client = po_sample_client(), agreement_columns = TRUE),
               class = "gr_bad_field")
})

test_that("the agreement columns are not shown to synthesis as study fields", {
  used <- data.frame(document = "a", n = 1L, n_agreement = "1/1", n_conflict = FALSE,
                     own_agreement = "x")
  expect_identical(harnessr:::study_fields(used), c("n", "own_agreement"))
})

test_that("resolve is swept as arms, one per value", {
  arms <- hr_sweep(function(resolve) {
    hr_arm(paste0("extract-", resolve), function(item, ctx) {
      gr_extract(item, po_sample_fields(), client = ctx$client, resolve = resolve,
                 recipe = "thorough", max_tokens = 48, trace = ctx$trace)$table$n
    })
  }, list(resolve = c("first", "vote")))
  expect_length(arms, 2L)
  ref <- hr_reference(po_sample_file(), labels = "236", cluster = "doc", split = "dev")
  bench <- po_quiet(hr_benchmark(arms, ref, runs = 1, client = po_sample_client(),
                                 split = "dev"))
  # vote sends what first sends; only the value kept differs.
  chk <- hr_sweep_check(bench)
  expect_identical(nrow(chk), 1L)
  expect_identical(chk$same_as, names(arms)[1])
})

# ---------------------------------------------------------------------------
# P1D-09: semantic_threshold = "texttiling" and the semantic->lexical label
# ---------------------------------------------------------------------------

po_cat_sentences <- c(
  "The cat sat on the warm mat by the door.", "A cat likes a warm mat in the sun.",
  "Our cat sleeps on the mat most of the day.", "The mat is where the cat waits for food.",
  "When the sun moves, the cat moves the mat too.", "The cat purrs on its favourite mat.",
  "Visitors see the cat asleep on the mat.", "The cat guards the mat from the dog.",
  "At night the cat leaves the mat for the bed.", "In the morning the cat returns to its mat.",
  "The cat and the mat are old friends.", "Nobody else may sit on the mat of the cat.",
  "The cat stretches on the mat after lunch.", "A warm mat keeps the old cat happy.",
  "The cat washes its paws on the mat.", "Rain keeps the cat on its mat all day.",
  "The cat naps on the mat while the house is quiet.", "Children stroke the cat on the mat.",
  "The cat kneads the soft mat before it sleeps.", "Each evening the cat curls up on the mat.")
po_rate_sentences <- c(
  "Interest rates rose by half a point in March.", "Banks raised mortgage rates after the rise.",
  "Higher rates slowed lending to small firms.", "The central bank expects rates to stay high.",
  "Savers earned more interest on deposits.", "Analysts expect rates to fall next year.")

po_semantic <- function(sentences, ...) {
  local_registries()
  gr_options(embedder = "lexical")
  po_quiet(gr_segment(paste(sentences, collapse = " "),
                      gr_segment_spec("semantic", max_tokens = 4000, ...),
                      client = gr_mock_client()))
}

test_that("semantic_threshold is off by default and leaves the spec as it was", {
  expect_null(gr_segment_spec("semantic")$semantic_threshold)
  expect_identical(gr_segment_spec("semantic", semantic_threshold = "texttiling")$semantic_threshold,
                   "texttiling")
  expect_error(gr_segment_spec("semantic", semantic_threshold = "nope"))
})

test_that("texttiling cuts a single-topic text at most once, where the percentile cuts often", {
  pct <- po_semantic(po_cat_sentences)
  tt <- po_semantic(po_cat_sentences, semantic_threshold = "texttiling")
  expect_gte(pct$extra$boundaries, 2L)
  expect_lte(tt$extra$boundaries, 1L)
})

test_that("texttiling cuts where the topic changes", {
  txt <- c(po_cat_sentences[1:6], po_rate_sentences)
  tt <- po_semantic(txt, semantic_threshold = "texttiling")
  expect_identical(tt$extra$boundaries, 1L)
  emb <- harnessr:::lexical_embed(vapply(seq_along(txt), function(i)
    paste(txt[max(1L, i - 1L):i], collapse = " "), character(1)))
  expect_identical(harnessr:::texttiling_cuts(emb, 2L)$cut_after, 6L)
  # Too few gaps with a block on each side: no cut.
  expect_length(harnessr:::texttiling_cuts(emb[1:5, ], 2L)$cut_after, 0L)
})

test_that("semantic on lexical vectors is labelled semantic->lexical", {
  expect_identical(po_semantic(po_cat_sentences)$method, "semantic->lexical")
  # Vectors from an embeddings endpoint (here the mock's) keep "semantic".
  ch <- po_quiet(gr_segment(paste(po_cat_sentences, collapse = " "),
                            gr_segment_spec("semantic", max_tokens = 4000),
                            client = gr_mock_client()))
  expect_identical(ch$method, "semantic")
})

test_that("semantic_threshold is swept as recipe arms", {
  arms <- hr_sweep(gr_arm("needle", list(method = "semantic", max_tokens = 200)),
                   list(semantic_threshold = c("percentile", "texttiling")))
  expect_length(arms, 2L)
  expect_identical(vapply(arms, function(a) a$params$semantic_threshold, ""),
                   c("percentile", "texttiling"), ignore_attr = TRUE)
})

# ---------------------------------------------------------------------------
# P1D-11: table provenance and table_packing = "grouped"
# ---------------------------------------------------------------------------

po_table_rows <- function(n = 60L) {
  c("| id | name | value |", "|---|---|---|",
    sprintf("| %02d | item%02d | %03d |", seq_len(n), seq_len(n), seq_len(n) * 7L))
}
po_table_doc <- function(n = 60L) {
  f <- tempfile(fileext = ".md")
  writeLines(c("# Data", "", "The table below lists every item.", "", po_table_rows(n), "",
               "That was the table."), f)
  po_quiet(gr_ingest(f))
}

test_that("each table block carries its table and rows; other blocks carry NA", {
  d <- po_table_doc()
  b <- d$blocks
  expect_identical(b$table_id, c(NA, NA, 1L, NA))
  expect_identical(b$table_rows, c(NA, NA, "1-61", NA))
  # One block per row, as Word and HTML give them, and two tables.
  tp <- harnessr:::table_provenance(c("table", "table", "body", "table", "table", "table"),
                                    c("a | b", "1 | 2", "text", "c | d", "3 | 4", "5 | 6"))
  expect_identical(tp$table_id, c(1L, 1L, NA, 2L, 2L, 2L))
  expect_identical(tp$table_rows, c("1", "2", NA, "1", "2", "3"))
  # A cell with a line break is still one row.
  expect_identical(harnessr:::table_lines("a | b\ncontinued"), "a | b\ncontinued")
})

test_that("paragraph chunks of a table say which table and rows, and send the same text", {
  d <- po_table_doc()
  ch <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 4000)))
  expect_identical(ch$chunks$table_id, 1L)
  expect_identical(ch$chunks$table_rows, "1-61")
  expect_identical(ch$chunks$text, paste(d$blocks$text, collapse = "\n\n"))
  # Rows as blocks: a chunk's range runs over the rows it was packed from.
  rows <- data.frame(text = c("Intro.", "a | b", "1 | 2", "3 | 4", "Outro."),
                     kind = c("body", "table", "table", "table", "body"))
  doc <- po_quiet(gr_ingest(c("Intro.", "a | b", "1 | 2", "3 | 4", "Outro.")))
  doc$blocks$kind <- rows$kind
  tp <- harnessr:::table_provenance(doc$blocks$kind, doc$blocks$text)
  doc$blocks$table_id <- tp$table_id; doc$blocks$table_rows <- tp$table_rows
  got <- harnessr:::chunk_table_provenance(doc$blocks, c(1L, 3L, 5L), c(2L, 4L, 5L))
  expect_identical(got$table_id, c(1L, 1L, NA))
  expect_identical(got$table_rows, c("1", "2-3", NA))
  # A document with no table gets no table columns.
  plain <- po_quiet(gr_segment(gr_example(), gr_segment_spec("paragraph")))
  expect_false("table_id" %in% names(plain$chunks))
})

test_that("table_packing is off by default and leaves the spec as it was", {
  expect_null(gr_segment_spec()$table_packing)
  expect_identical(gr_segment_spec(table_packing = "grouped")$table_packing, "grouped")
  expect_error(gr_segment_spec(table_packing = "nope"))
})

test_that("grouped packing splits 60 rows in 3 chunks that each open with the header", {
  rows <- po_table_rows(60L)
  header <- paste(rows[1:2], collapse = "\n")
  data_rows <- rows[-(1:2)]
  # Room for 20 rows after the header, as the packer counts them.
  cap <- gr_count_tokens(paste0(header, "\n")) + sum(gr_count_tokens(data_rows[1:20]))
  d <- po_table_doc(60L)
  ch <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = cap,
                                               table_packing = "grouped")))
  tab <- ch$chunks[!is.na(ch$chunks$table_id), ]
  expect_identical(nrow(tab), 3L)
  expect_true(all(startsWith(tab$text, paste0(header, "\n"))))
  expect_identical(tab$table_rows, c("1-21", "22-41", "42-61"))
  # Every row is in exactly one chunk.
  got <- unlist(lapply(strsplit(tab$text, "\n"), function(l) l[-(1:2)]))
  expect_identical(got, data_rows)
  # The prose around the table is packed as before.
  expect_identical(ch$chunks$text[is.na(ch$chunks$table_id)],
                   c("# Data\n\nThe table below lists every item.", "That was the table."))
  # Rows packed as blocks: no header repeated.
  plain <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = cap)))
  expect_lt(sum(startsWith(plain$chunks$text, header)), 2L)
})

test_that("table_packing is swept as recipe arms", {
  arms <- hr_sweep(gr_arm("needle", list(method = "paragraph", max_tokens = 200)),
                   list(table_packing = c("rows", "grouped")))
  expect_length(arms, 2L)
})

# ---------------------------------------------------------------------------
# P1D-12: ocr_trigger, OCR tags and confidence, Word image OCR failures
# ---------------------------------------------------------------------------

po_stamp <- "CONFIDENTIAL FAX COPY 2024-03-01 FROM CLINIC RECORDS ROOM 12"

test_that("ocr_trigger is off by default and leaves the spec as it was", {
  expect_null(gr_ingest_spec()$ocr_trigger)
  expect_identical(gr_ingest_spec(ocr_trigger = "after_running_lines")$ocr_trigger,
                   "after_running_lines")
  expect_error(gr_ingest_spec(ocr_trigger = "nope"))
})

test_that("after_running_lines OCRs a page whose only text is a running stamp", {
  expect_identical(nchar(po_stamp), 60L)
  body <- function(i) {
    paste(sprintf("Page %d opens a paragraph of real text in its text layer,", i),
          c("well past the forty characters that mark a page for OCR.",
            "and the paragraph goes on to a second line of its own."), collapse = "\n")
  }
  pages <- c(vapply(1:3, function(i) paste(body(i), po_stamp, sep = "\n"), ""), po_stamp)
  raw <- harnessr:::ocr_needs(pages, "auto", 40, "raw_text")
  after <- harnessr:::ocr_needs(pages, "auto", 40, "after_running_lines")
  expect_identical(raw, c(FALSE, FALSE, FALSE, FALSE))
  expect_identical(after, c(FALSE, FALSE, FALSE, TRUE))
  # never and always are as they were.
  expect_identical(harnessr:::ocr_needs(pages, "never", 40, "after_running_lines"),
                   rep(FALSE, 4))
  expect_identical(harnessr:::ocr_needs(pages, "always", 40, "after_running_lines"),
                   rep(TRUE, 4))
})

test_that("OCR-ed PDF blocks are kind 'ocr' with a confidence; headings keep theirs", {
  b <- data.frame(text = c("Methods", "Scanned text.", "Typed text."), page = c(1L, 1L, 2L),
                  section = "Methods", kind = c("heading", "body", "body"))
  out <- harnessr:::tag_ocr_blocks(b, c(TRUE, FALSE))
  expect_identical(out$kind, c("heading", "ocr", "body"))
  expect_identical(harnessr:::tag_ocr_blocks(b, c(FALSE, FALSE)), b)
  res <- po_quiet(harnessr:::ocr_pdf_pages(
    "scan.pdf", pages = c("", "Typed."), needs = c(TRUE, FALSE), opts = list(parallel = FALSE),
    engine = function(lang) "engine", read_page = function(path, i, dpi) i,
    ocr = function(img, eng) "Scanned text.", confidence = function(img, eng) 87.5))
  expect_identical(res$confidence, c(87.5, NA))
  # A confidence pass that fails leaves NA, and the text stands.
  res <- po_quiet(harnessr:::ocr_pdf_pages(
    "scan.pdf", pages = "", needs = TRUE, opts = list(parallel = FALSE),
    engine = function(lang) "engine", read_page = function(path, i, dpi) i,
    ocr = function(img, eng) "Scanned text.", confidence = function(img, eng) stop("no")))
  expect_identical(res$pages, "Scanned text.")
  expect_identical(res$confidence, NA_real_)
})

test_that("a real OCR pass tags a PDF's pages and records tesseract's confidence", {
  skip_if_not_installed("tesseract")
  skip_if_not_installed("magick")
  skip_if_not_installed("pdftools")
  f <- test_path("fixtures", "pdf", "single-column.pdf")
  d <- po_quiet(gr_ingest(f, gr_ingest_spec(ocr = "always"), cache = FALSE))
  ocr <- d$blocks[d$blocks$kind == "ocr", , drop = FALSE]
  expect_gt(nrow(ocr), 0L)
  expect_true(all(ocr$ocr_confidence >= 0 & ocr$ocr_confidence <= 100, na.rm = TRUE))
  expect_true(all(is.na(d$blocks$ocr_confidence[d$blocks$kind != "ocr"])))
})

test_that("a Word image whose OCR fails warns instead of vanishing", {
  expect_warning(got <- harnessr:::ocr_images(c("a/fig1.png", "a/fig2.png"), "engine",
                                              ocr = function(f, eng) {
                                                if (grepl("fig1", f)) stop("bad image") else "Fig 2"
                                              }),
                 "fig1.png", class = "gr_ocr_failed")
  expect_identical(got, c("", "Fig 2"))
})

test_that("ocr_trigger is swept as recipe arms", {
  arms <- hr_sweep(gr_arm("scanned"), list(ocr_trigger = c("raw_text", "after_running_lines")))
  expect_length(arms, 2L)
})
