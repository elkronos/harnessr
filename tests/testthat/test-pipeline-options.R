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
