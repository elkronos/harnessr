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

test_that("grouped packing keeps a row or header longer than the cap once", {
  long <- paste(rep("word", 300), collapse = " ")
  count_word <- function(ch) {
    sum(lengths(regmatches(ch$chunks$text, gregexpr("\\bword\\b", ch$chunks$text))))
  }
  as_rows <- function(texts, kinds) {
    d <- po_quiet(gr_ingest(texts))
    d$blocks$kind <- kinds
    tp <- harnessr:::table_provenance(d$blocks$kind, d$blocks$text)
    d$blocks$table_id <- tp$table_id; d$blocks$table_rows <- tp$table_rows
    d
  }
  # A row longer than the room left after the header.
  d <- as_rows(c("Intro text here.", "Name | Value", "a | 1", paste("b |", long), "c | 3",
                 "Outro text."), c("body", "table", "table", "table", "table", "body"))
  for (tp in c("rows", "grouped")) {
    ch <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 100,
                                                 table_packing = tp)))
    expect_identical(count_word(ch), 300L, label = tp)
  }
  ch <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 100,
                                               table_packing = "grouped")))
  tab <- ch$chunks$text[!is.na(ch$chunks$table_id)]
  expect_true(all(startsWith(tab, "Name | Value\n")))
  expect_identical(sum(grepl("a | 1", tab, fixed = TRUE)), 1L)
  expect_identical(sum(grepl("c | 3", tab, fixed = TRUE)), 1L)
  # A one-column table whose first row is the long cell.
  d2 <- as_rows(c("Intro.", long, "short row", "Outro."), c("body", "table", "table", "body"))
  ch2 <- po_quiet(gr_segment(d2, gr_segment_spec("paragraph", max_tokens = 100,
                                                 table_packing = "grouped")))
  expect_identical(count_word(ch2), 300L)
  # A Markdown header longer than the cap is sent once.
  hdr <- paste0("| ", paste(sprintf("column%03d", 1:60), collapse = " | "), " |")
  f <- tempfile(fileext = ".md")
  writeLines(c("Intro.", "", hdr, paste0("|", paste(rep("---", 60), collapse = "|"), "|"),
               sprintf("| %d | x |", 1:5), "", "Outro."), f)
  ch3 <- po_quiet(gr_segment(po_quiet(gr_ingest(f)),
                             gr_segment_spec("paragraph", max_tokens = 100,
                                             table_packing = "grouped")))
  expect_identical(sum(lengths(regmatches(ch3$chunks$text,
                                          gregexpr("column001 ", ch3$chunks$text)))), 1L)
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

# ---------------------------------------------------------------------------
# P1D-13: criteria_schema = "per_criterion"
# ---------------------------------------------------------------------------

po_screen_file <- function() {
  f <- tempfile(fileext = ".txt")
  writeLines(paste("We randomly assigned 120 adults to two groups and report",
                   "the primary outcome at twelve weeks."), f)
  f
}
po_include <- c("Randomised comparison", "Enrols adults")
po_exclude <- "Animal study"

po_screener <- function(reply) {
  seen <- new.env()
  cl <- gr_mock_client(function(messages, params) {
    seen$messages <- messages
    seen$params <- params
    reply
  })
  list(client = cl, seen = seen)
}

test_that("the default screening schema and request are as before", {
  s <- po_screener('{"decision":"include","reason":"An RCT.","criterion":null,"quote":null}')
  x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = s$client))
  expect_false("criteria_status" %in% names(x$table))
  txt <- po_text(s$seen$messages)
  expect_false(grepl("not_reported", txt, fixed = TRUE))
  expect_identical(harnessr:::.gr_screen_schema$required,
                   list("decision", "reason", "criterion", "quote"))
})

test_that("per_criterion asks for each criterion's status and records it", {
  s <- po_screener(paste0(
    '{"decision":"include","reason":"An RCT in adults.","criterion":null,"quote":null,',
    '"criteria":[{"criterion":"Randomised comparison","status":"met"},',
    '{"criterion":"Enrols adults","status":"met"},',
    '{"criterion":"Animal study","status":"not_met"}]}'))
  x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = s$client,
                          criteria_schema = "per_criterion"))
  expect_match(po_text(s$seen$messages), "not_reported", fixed = TRUE)
  expect_identical(x$table$decision, "include")
  expect_identical(x$table$criteria_status,
                   "Randomised comparison: met; Enrols adults: met; Animal study: not_met")
})

test_that("an exclusion with a criterion not reported and none not met becomes unclear", {
  s <- po_screener(paste0(
    '{"decision":"exclude","reason":"Age is not given.","criterion":"Enrols adults",',
    '"quote":null,"criteria":[{"criterion":"Randomised comparison","status":"met"},',
    '{"criterion":"Enrols adults","status":"not_reported"},',
    '{"criterion":"Animal study","status":"not_met"}]}'))
  x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = s$client,
                          criteria_schema = "per_criterion"))
  expect_identical(x$table$decision, "unclear")
  expect_match(x$table$reason, "not reported: Enrols adults", fixed = TRUE)
  # The same reply under the default schema is an exclusion, as before.
  d <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = s$client))
  expect_identical(d$table$decision, "exclude")
})

test_that("an exclusion that a criterion shows stands", {
  for (st in list(c("not_met", "met", "not_met"), c("met", "met", "met"))) {
    s <- po_screener(sprintf(paste0(
      '{"decision":"exclude","reason":"Fails.","criterion":"%s","quote":null,',
      '"criteria":[{"criterion":"Randomised comparison","status":"%s"},',
      '{"criterion":"Enrols adults","status":"%s"},',
      '{"criterion":"Animal study","status":"%s"}]}'),
      if (st[1] == "not_met") "Randomised comparison" else "Animal study", st[1], st[2], st[3]))
    x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                            exclude = po_exclude, client = s$client,
                            criteria_schema = "per_criterion"))
    expect_identical(x$table$decision, "exclude")
  }
  # A criterion left out of the reply counts as not reported.
  st <- harnessr:::criteria_statuses(list(list(criterion = "enrols adults.", status = "met")),
                                     po_include, po_exclude)
  expect_identical(unname(st), c("not_reported", "met", "not_reported"))
})

test_that("criteria_schema is checked and swept as arms", {
  expect_error(gr_screen(po_screen_file(), question = "q", include = "x",
                         criteria_schema = "nope"))
  arms <- hr_sweep(function(criteria_schema) {
    hr_arm(paste0("screen-", criteria_schema), function(item, ctx) {
      gr_screen(item, question = "Does it work?", include = po_include, exclude = po_exclude,
                client = ctx$client, criteria_schema = criteria_schema,
                trace = ctx$trace)$table$decision
    })
  }, list(criteria_schema = c("decision", "per_criterion")))
  expect_length(arms, 2L)
})

# ---------------------------------------------------------------------------
# P4-06: contextual (llm) section paths and cost; proposition provenance,
# context and invented propositions
# ---------------------------------------------------------------------------

po_sections_file <- function() {
  long <- function(w) paste(rep(sprintf("The %s section reports one more finding here.", w), 12),
                            collapse = " ")
  f <- tempfile(fileext = ".md")
  writeLines(c("# Report", "", "## Methods", "", "### Participants", "",
               "We enrolled 120 adults in Leeds.", "", "## Results", "",
               "Revenue was 45.2 million dollars.", "", "## Appendix", "", long("appendix"),
               "", "## Glossary", "", long("glossary")), f)
  f
}

po_recording_client <- function(propositions = NULL) {
  seen <- new.env()
  seen$asks <- character(0)
  cl <- gr_mock_client(function(m, p) {
    seen$asks <- c(seen$asks, m[[2]]$content)
    if (grepl("Decompose", m[[1]]$content, fixed = TRUE)) {
      return(propositions(m[[2]]$content))
    }
    "Context line."
  })
  list(client = cl, seen = seen)
}

test_that("contextual under llm sends each chunk's section path and declares its cost", {
  r <- po_recording_client()
  ch <- po_quiet(gr_segment(po_sections_file(),
                            gr_segment_spec("contextual", context_source = "llm", max_tokens = 40),
                            client = r$client))
  n <- nrow(ch$chunks)
  expect_identical(ch$extra$cost, list(calls = n, calls_max = n))
  expect_length(r$seen$asks, n)
  expect_true(any(grepl("<section_path>Report > Methods > Participants</section_path>",
                        r$seen$asks, fixed = TRUE)))
  expect_true(any(grepl("<section_path>Report > Glossary</section_path>", r$seen$asks,
                        fixed = TRUE)))
  # The metadata source sends nothing and declares nothing.
  meta <- po_quiet(gr_segment(po_sections_file(), gr_segment_spec("contextual", max_tokens = 40)))
  expect_null(meta$extra$cost)
  expect_identical(harnessr:::segmenter_cost("contextual", gr_segment_spec("contextual"), 7L),
                   list(calls = 0L, calls_max = 0L))
  paths <- harnessr:::chunk_section_paths(
    data.frame(text = c("1 Intro", "1.1 Aims", "Body", "2 Methods"),
               kind = c("heading", "heading", "body", "heading")),
    c("1.1 Aims", NA, "2 Methods", "Elsewhere"))
  expect_identical(paths, c("1 Intro > 1.1 Aims", "", "2 Methods", "Elsewhere"))
})

test_that("proposition keeps page and section, carries context, and drops invented ones", {
  r <- po_recording_client(function(ask) {
    if (grepl("appendix section", ask, fixed = TRUE) && !grepl("glossary", ask, fixed = TRUE)) {
      return(paste0('{"propositions":["The appendix section reports one more finding.",',
                    '"The appendix lists 999 patients.",',
                    '"Purple elephants dance gracefully tonight."]}'))
    }
    if (grepl("glossary section", ask, fixed = TRUE)) {
      return(sprintf('{"propositions":["%s"]}',
                     paste(rep("The glossary section reports one more finding here.", 3),
                           collapse = " ")))
    }
    '{"propositions":["Revenue was 45.2 million dollars."]}'
  })
  f <- po_sections_file()
  # By default an unsupported proposition is kept and counted.
  kept <- po_quiet(gr_segment(f, gr_segment_spec("proposition", max_tokens = 40,
                                                 proposition_batch_tokens = 200),
                              client = r$client))
  expect_identical(kept$extra$propositions_unsupported, 2L)
  expect_identical(kept$extra$propositions_dropped, 0L)
  expect_true(any(grepl("999", kept$chunks$text, fixed = TRUE)))
  expect_null(gr_segment_spec("proposition")$proposition_check)
  # Each batch alone by default, as before.
  expect_false(any(grepl("<context>", r$seen$asks, fixed = TRUE)))
  r$seen$asks <- character(0)
  ch <- po_quiet(gr_segment(f, gr_segment_spec("proposition", max_tokens = 40,
                                               proposition_batch_tokens = 200,
                                               proposition_check = "drop",
                                               proposition_context_tokens = 120),
                            client = r$client))
  expect_identical(ch$extra$propositions_dropped, 2L)
  expect_identical(ch$extra$propositions_unsupported, 2L)
  expect_false(any(grepl("999|elephants", ch$chunks$text)))
  # Each chunk carries its batch's section where the batch has one.
  gl <- ch$chunks[grepl("glossary", ch$chunks$text, fixed = TRUE), ]
  expect_identical(unique(gl$section), "Glossary")
  # Every batch after the first is sent the end of the one before it.
  asks <- r$seen$asks
  expect_false(grepl("<context>", asks[1], fixed = TRUE))
  expect_true(all(grepl("<context>", asks[-1], fixed = TRUE)))
  expect_identical(ch$extra$cost, list(calls = length(asks), calls_max = length(asks)))
  expect_warning(gr_segment(f, gr_segment_spec("proposition", max_tokens = 60,
                                               proposition_batch_tokens = 200,
                                               proposition_check = "drop"),
                            client = r$client),
                 class = "gr_proposition_dropped")
  expect_true(harnessr:::proposition_supported("Revenue was 45 million.", "Revenue was 45 million."))
  expect_false(harnessr:::proposition_supported("Revenue was 46 million.", "Revenue was 45 million."))
  # A number written in another form than the batch's is still the batch's.
  expect_true(harnessr:::proposition_supported("The trial enrolled 1200 adults.",
                                               "The trial enrolled 1,200 adults."))
  expect_true(harnessr:::proposition_supported("Follow-up lasted 12 weeks.",
                                               "Follow-up lasted twelve weeks."))
  expect_false(harnessr:::proposition_supported("The trial enrolled 1300 adults.",
                                                "The trial enrolled 1,200 adults."))
  expect_false(harnessr:::proposition_supported("Follow-up lasted 13 weeks.",
                                                "Follow-up lasted twelve weeks."))
  # A resolved pronoun names what the context gave.
  expect_true(harnessr:::proposition_supported("Northwind reported revenue growth.",
                                               "It reported revenue growth.",
                                               context = "Northwind Instruments"))
})

test_that("context_source and the proposition settings are swept as recipe arms", {
  arms <- hr_sweep(gr_arm("needle", list(method = "contextual")),
                   list(context_source = c("metadata", "llm")))
  expect_length(arms, 2L)
  arms <- hr_sweep(gr_arm("needle", list(method = "proposition")),
                   list(proposition_check = c("count", "drop")))
  expect_length(arms, 2L)
  arms <- hr_sweep(gr_arm("needle", list(method = "proposition")),
                   list(proposition_context_tokens = c(0, 120)))
  expect_length(arms, 2L)
  expect_null(gr_segment_spec("proposition")$proposition_context_tokens)
})

# ---------------------------------------------------------------------------
# P4-17: balanced packing, a forward merge for a leading runt, and screening
# samples combined by include_if_any
# ---------------------------------------------------------------------------

po_paras <- function(n = 25L) {
  sprintf(paste0("Paragraph %02d says something about the year and its results in some ",
                 "detail, with more words to make it longer than before."), seq_len(n))
}

test_that("packing and runt_merge are off by default and leave the spec as it was", {
  expect_null(gr_segment_spec()$packing)
  expect_null(gr_segment_spec()$runt_merge)
  expect_identical(gr_segment_spec(packing = "balanced")$packing, "balanced")
  expect_identical(gr_segment_spec(runt_merge = "both")$runt_merge, "both")
})

test_that("balanced packing keeps the chunk count and evens the sizes, losing no text", {
  d <- po_quiet(gr_ingest(paste(po_paras(), collapse = "\n\n")))
  g <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 300)))
  b <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 300,
                                              packing = "balanced")))
  expect_identical(nrow(b$chunks), nrow(g$chunks))
  expect_lt(diff(range(b$chunks$tokens)), diff(range(g$chunks$tokens)))
  expect_true(all(b$chunks$tokens <= 300))
  expect_identical(paste(b$chunks$text, collapse = "\n\n"), paste(po_paras(), collapse = "\n\n"))
  # With overlap, every chunk after the first opens with the end of the one before.
  bo <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 300, overlap_tokens = 20,
                                               packing = "balanced")))
  expect_identical(nrow(bo$chunks), nrow(g$chunks))
  expect_true(all(bo$chunks$tokens <= 300))
  # One chunk: nothing to balance.
  one <- harnessr:::pack_units(c("a b c", "d e f"), 200, balanced = TRUE)
  expect_identical(one$text, "a b c\n\nd e f")
})

test_that("runt_merge = 'both' merges a leading runt forward; 'backward' leaves it", {
  body <- "Body"
  while (gr_count_tokens(body) < 56L) body <- paste(body, "word")
  d <- po_quiet(gr_ingest(paste(c("Short title.", body, "Another paragraph follows here."),
                                collapse = "\n\n")))
  back <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 60, min_tokens = 20)))
  both <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 60, min_tokens = 20,
                                                 runt_merge = "both")))
  expect_identical(back$chunks$text[1], "Short title.")
  expect_identical(nrow(both$chunks), nrow(back$chunks) - 1L)
  expect_identical(both$chunks$text[1], paste("Short title.", body, sep = "\n\n"))
  # Nothing is merged at min_tokens = 0.
  none <- po_quiet(gr_segment(d, gr_segment_spec("paragraph", max_tokens = 60,
                                                 runt_merge = "both")))
  expect_identical(none$chunks$text[1], "Short title.")
})

test_that("packing and runt_merge are swept as recipe arms", {
  arms <- hr_sweep(gr_arm("needle", list(method = "paragraph", max_tokens = 120)),
                   list(packing = c("greedy", "balanced")))
  expect_length(arms, 2L)
  arms <- hr_sweep(gr_arm("needle", list(method = "paragraph", min_tokens = 20)),
                   list(runt_merge = c("backward", "both")))
  expect_length(arms, 2L)
})

po_draw_screener <- function(decisions) {
  gr_mock_client(function(messages, params) {
    k <- max(1L, as.integer(params$draw_index %||% 0L))
    d <- decisions[[k]]
    sprintf('{"decision":"%s","reason":"Draw %d.","criterion":%s,"quote":null}', d, k,
            if (d == "exclude") '"Animal study"' else "null")
  })
}

test_that("samples is off by default and sends one request, as before", {
  cl <- po_draw_screener(list("include"))
  x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = cl))
  expect_length(cl$calls(), 1L)
  expect_null(cl$calls()[[1]]$params$draw_index)
  expect_false(any(c("sample_decisions", "include_share") %in% names(x$table)))
  expect_error(gr_screen(po_screen_file(), question = "q", include = "x", samples = 0),
               class = "gr_bad_setting")
})

test_that("include_if_any keeps a document any draw included, and records the share", {
  cl <- po_draw_screener(list("exclude", "include", "exclude"))
  x <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                          exclude = po_exclude, client = cl, samples = 3))
  expect_length(cl$calls(), 3L)
  expect_identical(x$table$decision, "include")
  expect_identical(x$table$sample_decisions, "exclude, include, exclude")
  expect_equal(x$table$include_share, 1 / 3)
  # Every draw excluding: an exclusion. A split with no include: unclear.
  all_out <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?",
                                include = po_include, exclude = po_exclude,
                                client = po_draw_screener(list("exclude", "exclude")),
                                samples = 2))
  expect_identical(all_out$table$decision, "exclude")
  split <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?",
                              include = po_include, exclude = po_exclude,
                              client = po_draw_screener(list("exclude", "unclear")),
                              samples = 2))
  expect_identical(split$table$decision, "unclear")
  # majority: the decision most draws gave.
  maj <- po_quiet(gr_screen(po_screen_file(), question = "Does it work?", include = po_include,
                            exclude = po_exclude,
                            client = po_draw_screener(list("exclude", "include", "exclude")),
                            samples = 3, sample_rule = "majority"))
  expect_identical(maj$table$decision, "exclude")
})

test_that("samples is swept as arms", {
  arms <- hr_sweep(function(samples) {
    hr_arm(paste0("screen-", samples), function(item, ctx) {
      gr_screen(item, question = "Does it work?", include = po_include, exclude = po_exclude,
                client = ctx$client, samples = samples, trace = ctx$trace)$table$decision
    })
  }, list(samples = c(1, 3)))
  expect_length(arms, 2L)
})

# ---------------------------------------------------------------------------
# P2D-08: error-correlation metrics on benchmark output
# ---------------------------------------------------------------------------

po_blind_bench <- function(everies = c(4, 5, 6), runs = 5) {
  truth <- hr_reference(sprintf("q%02d", 1:12), labels = rep("yes", 12),
                        cluster = sprintf("c%02d", 1:12), split = "test")
  blind <- function(every) {
    hr_arm(paste0("every-", every), function(item, ctx) {
      n <- as.integer(sub("q", "", item))
      if (n <= 3) return("no")
      if (n %% every == 0) return(paste("wrong", every))
      "yes"
    }, params = list(every = every))
  }
  po_quiet(hr_benchmark(hr_sweep(blind, list(every = everies)), truth, runs = runs,
                        client = NULL))
}

test_that("phi, the same-wrong rate and the hand-check sample are what the runs say", {
  eb <- po_blind_bench()
  ec <- hr_error_correlation(eb, n_strata = 1)
  expect_s3_class(ec, "hr_error_correlation")
  # hr_sweep() names each arm by its setting.
  arm <- function(k) unique(eb$arm)[startsWith(unique(eb$arm), paste0("every-", k))]
  p <- ec$pairs[ec$pairs$arm_a == arm(4) & ec$pairs$arm_b == arm(6), ]
  # every-4 is wrong on 1-4, 8, 12; every-6 on 1-3, 6, 12.
  x <- (1:12) %in% c(1:4, 8, 12); y <- (1:12) %in% c(1:3, 6, 12)
  expect_equal(p$phi_pooled, stats::cor(x, y))
  expect_identical(p$both_wrong, 4L)
  # Both say "no" on 1-3; on 12 they give different wrong answers.
  expect_identical(p$same_wrong, 3L)
  expect_equal(p$same_wrong_rate, 3 / 4)
  expect_identical(ec$all_wrong, 3L)
  expect_setequal(ec$check$item, c("q01", "q02", "q03"))
  expect_true(all(ec$check[[arm(5)]] == "no"))
  expect_match(ec$q3, "lme4", fixed = TRUE)
  # The sample is drawn under its own seed and leaves the caller's alone.
  set.seed(9); before <- runif(1); set.seed(9)
  small <- hr_error_correlation(eb, n_strata = 1, n_check = 2, seed = 3)
  expect_identical(runif(1), before)
  expect_identical(nrow(small$check), 2L)
  expect_identical(hr_error_correlation(eb, n_strata = 1, n_check = 2, seed = 3)$check,
                   small$check)
})

test_that("difficulty strata separate a shared blind spot from the arms' own errors", {
  eb <- po_blind_bench()
  ec <- hr_error_correlation(eb)
  # The three items every arm gets wrong sit in the hardest stratum, where
  # phi is undefined.
  hard <- names(ec$strata)[ec$strata == ec$strata[["q01"]]]
  expect_true(all(c("q01", "q02", "q03") %in% hard))
  expect_true(all(is.na(ec$phi$phi[ec$phi$stratum == ec$strata[["q01"]]])))
  # Given strata are used as given.
  st <- stats::setNames(rep(c("a", "b"), each = 6), sprintf("q%02d", 1:12))
  ec2 <- hr_error_correlation(eb, strata = st)
  expect_setequal(unique(ec2$phi$stratum), c("a", "b"))
  expect_output(print(ec), "hr_error_correlation")
})

test_that("hr_error_correlation() checks its inputs", {
  eb <- po_blind_bench()
  expect_error(hr_error_correlation(data.frame()), class = "gr_bad_setting")
  expect_error(hr_error_correlation(eb, n_strata = 0), class = "gr_bad_setting")
  expect_error(hr_error_correlation(eb, n_check = -1), class = "gr_bad_setting")
  expect_error(hr_error_correlation(eb, strata = c(a = "x")), class = "gr_bad_setting")
  one <- po_blind_bench(everies = 4)
  expect_error(hr_error_correlation(one), class = "gr_bad_setting")
})
