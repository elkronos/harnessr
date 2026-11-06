# test-screen.R -- the stage that decides which documents a review reads.
#
# The thing that must not happen here is a document quietly leaving the set. So
# most of these check the boring, structural property -- every source has a row,
# every row has a decision or an explicit absence of one -- rather than whether
# the model got the call right.

screen_client <- function(rules, default = NULL) {
  gr_mock_client(function(messages, params) {
    seen <- paste(vapply(messages, function(m) paste(as.character(m$content), collapse = ""),
                         character(1)), collapse = "\n")
    for (r in rules) if (grepl(r$where, seen, fixed = TRUE)) return(r$json)
    default %||% '{"decision":"unclear","reason":"The excerpt does not settle it.",
                   "criterion":null,"quote":null}'
  })
}

txt_file <- function(x) {
  f <- tempfile(fileext = ".txt"); writeLines(x, f); f
}

trial_txt <- "We randomly assigned 1,204 participants to two groups."
edit_txt  <- "This editorial comments on recent trials without new data."

basic_rules <- list(
  list(where = "randomly assigned",
       json = paste0('{"decision":"include","reason":"A randomised comparison.",',
                     '"criterion":"Reports a randomised comparison",',
                     '"quote":"We randomly assigned 1,204 participants to two groups."}')),
  list(where = "editorial",
       json = paste0('{"decision":"exclude","reason":"An editorial with no data.",',
                     '"criterion":"Not a primary research report",',
                     '"quote":"This editorial comments on recent trials without new data."}')))

test_that("every source gets a row, and every decision has a reason", {
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt); b <- txt_file(edit_txt); c3 <- txt_file("Something unrelated here.")

  s <- quiet(gr_screen(c(a, b, c3), question = "Does the drug work?",
                       include = "Reports a randomised comparison",
                       exclude = "Not a primary research report", client = cl))
  expect_s3_class(s, "gr_screening")
  expect_equal(nrow(s$table), 3L)
  expect_identical(s$table$decision, c("include", "exclude", "unclear"))
  expect_false(anyNA(s$table$reason))
  expect_identical(s$table$criterion[2], "Not a primary research report")
  expect_identical(s$included, a)                   # the path, not the label
  # The unclear one is deferred, not dropped: it goes on with the included.
  expect_identical(s$forward, c(a, c3))
  expect_identical(s$deferred, c3)
  expect_identical(length(cl$calls()), 3L)          # one call per document

  # The quote behind a decision is checked against what the model was shown,
  # exactly as an extracted value is.
  expect_true(all(s$table$verified[1:2]))
  expect_true(is.na(s$table$verified[3]))
})

test_that("a document that could not be read has no decision, and is not excluded", {
  # The failure mode this stage exists to prevent. An unreadable file must be an
  # outstanding job, not a silent exclusion and not a silent absence.
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(c(a, "no-such-file.txt"), question = "Does the drug work?",
                       include = "Reports a randomised comparison", client = cl))
  expect_equal(nrow(s$table), 2L)
  expect_true(is.na(s$table$decision[2]))
  expect_identical(s$table$status[2], "failed")
  expect_false(is.na(s$table$error[2]))
  expect_identical(s$included, a)
  expect_output(print(s), "could not be read and have NO decision")
})

test_that("an unreadable answer is 'unclear', never a guess in either direction", {
  # Defaulting to exclude loses studies silently; defaulting to include buys a
  # full extraction for every document the screener could not parse.
  dec <- harnessr:::screen_decision
  expect_identical(dec("include"), "include")
  expect_identical(dec("  EXCLUDE "), "exclude")
  expect_identical(dec("probably include"), "unclear")
  expect_identical(dec(""), "unclear")
  expect_identical(dec(NULL), "unclear")
  expect_identical(dec(NA), "unclear")

  # And end to end: a client that returns nothing usable. That is a failed
  # call, not a judgement, so it is not "unclear" either: no decision, status
  # "failed", and the error says why. "Unclear" counted in gr_flow() and
  # gr_calibrate() as the model deferring to a person, which it never did.
  cl <- gr_mock_client(function(messages, params) "not json at all")
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                       client = cl, keep_answers = TRUE))
  expect_true(is.na(s$table$decision))
  expect_identical(s$table$status, "failed")
  expect_match(s$table$error, "not the JSON")
  expect_true(s$answers[[1]]$partial)               # the call did not work
})

test_that("a decision outside the schema's enum is a failed call, not a decision", {
  # Valid JSON that names no allowed decision used to be accepted and cached,
  # and re-running served the same reply. Now it is refused before either.
  cl <- screen_client(list(), default = paste0(
    '{"decision":"probably","reason":"It looks relevant.",',
    '"criterion":null,"quote":null}'))
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                       client = cl, keep_answers = TRUE))
  expect_true(is.na(s$table$decision))
  expect_identical(s$table$status, "failed")
  expect_match(s$table$error, "$.decision", fixed = TRUE)
})

test_that("'unclear' is an answer, not a partial one", {
  # A correct "we cannot tell from this" and a broken call must not land in the
  # same bucket: one is for a person to read, the other is for the run to redo.
  cl <- screen_client(list(), default = paste0(
    '{"decision":"unclear","reason":"The excerpt does not say what was studied.",',
    '"criterion":null,"quote":null}'))
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                       client = cl, keep_answers = TRUE))
  expect_identical(s$table$decision, "unclear")
  expect_false(s$answers[[1]]$partial)
  expect_false(s$summary$partial)
})

test_that("screening reads the opening of a document, contiguously, in one call", {
  # A screening decision is made from the front of the paper. An "opening"
  # assembled from paragraphs 1, 2 and 47 because those happened to fit is not
  # one, and it is what fit_chunks() does by default.
  paras <- vapply(1:8, function(i)
    sprintf("Paragraph %d of the document, with enough words in it to occupy a chunk.", i),
    character(1))
  f <- txt_file(paste(paras, collapse = "\n\n"))

  cl <- screen_client(list(), default = paste0(
    '{"decision":"include","reason":"Fine.","criterion":null,"quote":null}'))
  s <- quiet(gr_screen(f, question = "Q?", include = "Anything at all",
                       client = cl, screen_tokens = 40, max_tokens = 40,
                       keep_answers = TRUE))

  expect_identical(length(cl$calls()), 1L)          # one call, whatever the size
  expect_true(s$table$truncated)
  expect_lt(s$table$seen_tokens, s$table$document_tokens)

  seen <- paste(vapply(cl$calls()[[1]]$messages,
                       function(m) as.character(m$content), character(1)), collapse = "\n")
  expect_true(grepl("Paragraph 1 of", seen, fixed = TRUE))
  expect_false(grepl("Paragraph 8 of", seen, fixed = TRUE))
  expect_gt(s$answers[[1]]$notes$seen_tokens, 0L)
})

test_that("the opening stops at the first chunk that does not fit", {
  # Contiguity, at the reader rather than end to end: segmentation enforces the
  # token cap, so every chunk of a segmented document is small enough to fit and
  # skipping and stopping cannot be told apart. Hand-built chunks of unequal size
  # are what separate them -- and unequal chunks are what a `page` or
  # `structural` segmentation actually produces.
  ch <- new_chunks(c("Alpha, the opening line.",
                     paste(rep("padding", 300), collapse = " "),
                     "Gamma, a short line that would fit."),
                   method = "test", spec = gr_segment_spec(max_tokens = 4000))
  cl <- screen_client(list(), default = paste0(
    '{"decision":"include","reason":"Fine.","criterion":null,"quote":null}'))
  a <- quiet(gr_read(ch, "Q?", cl,
                     # 40 tokens: chunks one and three both fit inside it and
                     # chunk two does not, so skipping reaches "Gamma" and
                     # stopping does not. At 20 neither reaches it and the test
                     # would pass whichever the reader does.
                     list(reader = "screen", include = "Anything at all",
                          screen_tokens = 40)))
  seen <- paste(vapply(cl$calls()[[1]]$messages,
                       function(m) as.character(m$content), character(1)), collapse = "\n")
  expect_true(grepl("Alpha, the opening line.", seen, fixed = TRUE))
  expect_false(grepl("Gamma, a short line", seen, fixed = TRUE))
  expect_true(a$notes$truncated)
  expect_identical(a$notes$seen_tokens, as.integer(ch$chunks$tokens[1]))
  expect_identical(a$answer, "include")
})

test_that("screening is costed as the one call it is", {
  # The pre-flight estimate. Falling through to the default -- one call per chunk
  # -- made a long document abort against a call cap it would never have reached,
  # which is a reader that cannot be used on exactly the documents it is for.
  local_registries()
  gr_options(max_calls = 3)
  paras <- vapply(1:8, function(i)
    sprintf("Paragraph %d of the document, with enough words in it to fill a chunk.", i),
    character(1))
  f <- txt_file(paste(paras, collapse = "\n\n"))
  cl <- screen_client(list(), default = paste0(
    '{"decision":"include","reason":"Fine.","criterion":null,"quote":null}'))

  s <- quiet(gr_screen(f, question = "Q?", include = "Anything at all",
                       client = cl, max_tokens = 40))
  expect_identical(s$table$status, "ok")
  expect_identical(s$table$decision, "include")
  expect_identical(length(cl$calls()), 1L)
})

test_that("a screening span is verified as model-written, not as chunk text", {
  # The per-row `kind` column normally settles this. The reader-name fallback is
  # for an evidence table built any other way -- a custom reader, or an answer
  # from an older build -- and getting it wrong would report a sentence the model
  # composed as verbatim document text.
  ev <- data.frame(chunk_id = 1L, text = "A quoted sentence.",
                   source_text = "Before. A quoted sentence. After.",
                   stringsAsFactors = FALSE)
  ans <- structure(list(reader = "screen", evidence = ev), class = "gr_answer")
  out <- gr_verify_evidence(ans)
  expect_identical(out$kind, "extracted")
  expect_true(out$verified)
})

test_that("fit_chunks(prefix =) stops rather than skipping", {
  fit <- harnessr:::fit_chunks
  d <- data.frame(chunk_id = 1:4, text = c("aa", strrep("b ", 400), "cc", "dd"),
                  page = NA_integer_, section = NA_character_, stringsAsFactors = FALSE)
  loose <- fit(d, 60)
  tight <- fit(d, 60, prefix = TRUE)
  expect_true(all(c(1L, 3L, 4L) %in% loose$idx))    # skips the oversized one
  expect_identical(tight$idx, 1L)                   # stops at it
})

test_that("a whole document that fits is not reported as truncated", {
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                       client = cl))
  expect_false(s$table$truncated)
  expect_identical(s$table$seen_tokens, s$table$document_tokens)
})

test_that("gr_screen() takes its criteria and question from a protocol", {
  p <- gr_protocol("trials", question = "Does the drug reduce events?",
                   include = c("Reports a randomised comparison", "Reports a clinical outcome"),
                   exclude = "Not a primary research report",
                   recipe = "fast")
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  s <- quiet(gr_screen(a, p, client = cl, max_tokens = 60))
  expect_identical(s$include, p$include)
  expect_identical(s$exclude, p$exclude)

  seen <- paste(vapply(cl$calls()[[1]]$messages,
                       function(m) as.character(m$content), character(1)), collapse = "\n")
  expect_true(grepl(p$question, seen, fixed = TRUE))
  for (crit in c(p$include, p$exclude)) expect_true(grepl(crit, seen, fixed = TRUE))

  # An explicit argument still wins.
  cl2 <- screen_client(basic_rules)
  s2 <- quiet(gr_screen(a, p, include = "Only this one", client = cl2, max_tokens = 60))
  expect_identical(s2$include, "Only this one")
  seen2 <- paste(vapply(cl2$calls()[[1]]$messages,
                        function(m) as.character(m$content), character(1)), collapse = "\n")
  expect_true(grepl("Only this one", seen2, fixed = TRUE))
  expect_false(grepl("Reports a clinical outcome", seen2, fixed = TRUE))
})

test_that("screening without criteria is refused before anything is spent", {
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  expect_error(gr_screen(a, question = "Q?", client = cl), class = "gr_no_criteria")
  expect_error(gr_screen(a, include = "Something", client = cl))
  expect_error(gr_screen(a, protocol = list(question = "Q?"), client = cl),
               class = "gr_bad_protocol")
  expect_identical(length(cl$calls()), 0L)

  # And the reader says the same thing when it is reached directly.
  ch <- quiet(gr_segment("Some text about a trial.", list(method = "paragraph",
                                                          max_tokens = 100)))
  expect_error(quiet(gr_read(ch, "Q?", cl, "screen")), class = "gr_no_criteria")
})

test_that("screening feeds extraction, and duplicates are screened once", {
  # The whole point of the stage: what comes out is the argument to gr_extract().
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  a2 <- txt_file(trial_txt)                        # the same paper again
  b <- txt_file(edit_txt)

  s <- quiet(gr_screen(c(a, a2, b), question = "Q?",
                       include = "Reports a randomised comparison",
                       exclude = "Not a primary research report", client = cl))
  expect_identical(length(cl$calls()), 2L)          # the duplicate was not screened again
  expect_identical(s$table$decision, c("include", "include", "exclude"))
  expect_identical(s$table$duplicate_of, c(NA, basename(a), NA))

  # `included` is the PATHS, not the display labels -- summary$document is a
  # basename, made unique with a suffix when two folders hold the same filename,
  # and there is no way back from it to a file. Handing labels to gr_extract()
  # failed with "file not found" on every row, which is the whole purpose of the
  # field. And it is the DISTINCT set: a duplicate is the same study.
  expect_identical(s$included, a)
  expect_true(all(file.exists(s$included)))
  expect_identical(s$forward, a)                    # distinct here too
  expect_length(s$deferred, 0L)

  fields <- gr_fields(n = gr_field("Participants", type = "integer"))
  ex <- gr_mock_client(function(messages, params) {
    '{"n":1204,"n__quote":"We randomly assigned 1,204 participants to two groups."}'
  })
  x <- quiet(gr_extract(s$included, fields, client = ex, recipe = "fast"))
  expect_identical(x$table$status, "ok")
  expect_identical(x$table$n, 1204L)
})

test_that("gr_read_many() hands back the sources it read, aligned with the summary", {
  cl <- mock_echo()
  a <- txt_file(trial_txt); b <- txt_file(edit_txt)
  out <- quiet(gr_read_many(c(a, b, "no-such-file.txt"), "Q?", "fast", client = cl))
  expect_length(out$sources, nrow(out$summary))
  expect_identical(out$sources, c(a, b, "no-such-file.txt"))

  # A directory is expanded, so the sources are what was actually read rather
  # than the argument that was passed.
  dir <- withr::local_tempdir()
  writeLines(trial_txt, file.path(dir, "one.txt"))
  writeLines(edit_txt, file.path(dir, "two.txt"))
  d <- quiet(gr_read_many(dir, "Q?", "fast", client = mock_echo()))
  expect_length(d$sources, 2L)
  expect_true(all(file.exists(d$sources)))
  expect_identical(basename(d$sources), d$summary$document)
})

test_that("a screening run resumes from a store", {
  cl <- screen_client(basic_rules)
  a <- txt_file(trial_txt)
  store <- withr::local_tempdir()
  first <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                           client = cl, store = store))
  n1 <- length(cl$calls())
  again <- quiet(gr_screen(a, question = "Q?", include = "Reports a randomised comparison",
                           client = cl, store = store))
  expect_identical(again$table$status, "restored")
  expect_identical(again$table$decision, first$table$decision)
  expect_identical(again$table$reason, first$table$reason)
  expect_identical(length(cl$calls()), n1)
})

test_that("the screen reader is a distinct traversal", {
  r <- gr_readers()
  expect_true("screen" %in% r$name)
  expect_identical(r$signature[r$name == "screen"], "head|1|none")
  # Distinctness is what gr_compare() checks; two readers sharing a signature
  # would be reported as corroborating each other when they cannot.
  expect_false(anyDuplicated(r$signature) > 0L)
})

test_that("unclear records go forward, and the flow accounts for every record", {
  # 3 include, 2 unclear, 5 exclude. `forward` holds the five kept for full
  # text; gr_extract(screened) still reads only the included three in this
  # release, and says so instead of dropping the other two silently.
  inc <- vapply(1:3, function(i) txt_file(paste("We randomly assigned group", i)), "")
  unc <- vapply(1:2, function(i) txt_file(paste("Participants were adults, cohort", i)), "")
  exc <- vapply(1:5, function(i) txt_file(paste("This editorial comments, number", i)), "")
  s <- quiet(gr_screen(c(inc, unc, exc), question = "Does the drug work?",
                       include = "Reports a randomised comparison",
                       exclude = "Not a primary research report",
                       client = screen_client(basic_rules)))
  expect_identical(table(s$table$decision)[c("include", "unclear", "exclude")],
                   table(c(rep("include", 3), rep("unclear", 2), rep("exclude", 5)))[
                     c("include", "unclear", "exclude")])
  expect_length(s$forward, 5L)
  expect_identical(s$forward, c(inc, unc))
  expect_identical(s$deferred, unc)
  expect_identical(s$included, inc)

  fields <- gr_fields(n = gr_field("Participants", type = "integer"))
  ex <- gr_mock_client(function(messages, params) '{"n":null,"n__quote":null}')
  expect_warning(x <- suppressMessages(gr_extract(s, fields, client = ex, recipe = "fast")),
                 class = "gr_unclear_dropped")
  expect_equal(nrow(x$table), 3L)

  fl <- gr_flow(s)
  n <- function(stage) fl$n[trimws(fl$stage) == stage]
  # The five decision rows sum to the records screened, which is all ten.
  expect_identical(n("screened"), 10L)
  expect_identical(n("include") + n("exclude") + n("unclear") + n("could not be read") +
                     n("screening call failed"), 10L)
  expect_identical(n("kept for full text"), 5L)
  expect_identical(n("deferred to full text"), 2L)
  expect_identical(n("resolved by a person"), 0L)
})

test_that("gr_resolve() records who settled a deferred record, and when", {
  a <- txt_file(trial_txt); u <- txt_file("Participants were adults.")
  s <- quiet(gr_screen(c(a, u), question = "Q?", include = "Reports a randomised comparison",
                       client = screen_client(basic_rules)))
  expect_identical(s$deferred, u)
  steps_before <- length(s$trace$steps)
  at <- as.POSIXct("2026-03-01 09:30:00", tz = "UTC")
  r <- gr_resolve(s, basename(u), "include", by = "AB", reason = "Methods say randomised.",
                  at = at)
  expect_identical(r$table$decision, c("include", "include"))
  expect_identical(r$table$screener_decision, c("include", "unclear"))
  expect_identical(r$table$resolved_by, c(NA, "AB"))
  expect_identical(r$table$resolved_at, c(NA, "2026-03-01T09:30:00Z"))
  expect_identical(r$included, c(a, u))
  expect_identical(r$forward, c(a, u))
  expect_length(r$deferred, 0L)
  # In the trace as a step of its own, with the person and the time.
  st <- r$trace$steps[[length(r$trace$steps)]]
  expect_identical(length(r$trace$steps), steps_before + 1L)
  expect_identical(st$label, "screen.resolve")
  expect_identical(st$detail$by, "AB")
  expect_identical(st$detail$from, "unclear")

  fl <- gr_flow(r)
  n <- function(stage) fl$n[trimws(fl$stage) == stage]
  expect_identical(n("resolved by a person"), 1L)
  expect_identical(n("include"), 2L)
  expect_identical(n("unclear"), 0L)
  expect_output(print(r), "1 decided by a person")

  # A calibration measures the screener, not the person who corrected it.
  ref <- data.frame(document = basename(c(a, u)), human_decision = c("include", "include"),
                    stringsAsFactors = FALSE)
  cal <- suppressWarnings(gr_calibrate(r, ref, of = "all", min_positives = 1L))
  expect_identical(unname(cal$decisions["unclear", "eligible"]), 1L)

  # A duplicate of the resolved record takes the person's decision too, and
  # keeps the screener's own.
  a2 <- txt_file(trial_txt); u2 <- txt_file("Participants were adults.")
  e <- txt_file(edit_txt)
  sd <- quiet(gr_screen(c(a, a2, u, u2, e), question = "Q?",
                        include = "Reports a randomised comparison",
                        exclude = "Not a primary research report",
                        client = screen_client(basic_rules)))
  expect_identical(sd$table$duplicate_of[4], basename(u))
  r2 <- gr_resolve(sd, basename(u), "exclude", by = "AB", at = at)
  expect_identical(r2$table$decision[3:4], c("exclude", "exclude"))
  expect_identical(r2$table$screener_decision[3:4], c("unclear", "unclear"))
  expect_identical(r2$table$resolved_by[3:4], c("AB", "AB"))
  expect_identical(r2$table$resolved_at[4], "2026-03-01T09:30:00Z")
  expect_length(r2$deferred, 0L)
  out <- paste(capture.output(print(r2)), collapse = "\n")
  expect_match(out, "0 unclear")
  expect_match(out, "1 decided by a person")

  expect_error(gr_resolve(s, basename(u), "include"), class = "gr_bad_setting")
  expect_error(gr_resolve(s, basename(u), "maybe", by = "AB"), class = "gr_bad_setting")
  expect_error(gr_resolve(s, "not-a-document.txt", "exclude", by = "AB"),
               class = "gr_reference_mismatch")
})
