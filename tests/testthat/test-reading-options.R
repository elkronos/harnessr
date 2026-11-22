# test-reading-options.R: the opt-in reading options of package 6a. Each is
# off by default, so a default spec sends what it sent before; the golden
# records check that. These tests check what each option does when it is on.

ro_chunks <- function(txt, section = NA_character_) {
  new_chunks(txt, "precomputed", gr_segment_spec(max_tokens = max(gr_count_tokens(txt), 32L)),
             section = section)
}

ro_steps <- function(tr, label) {
  Filter(function(s) identical(s$label, label) && identical(s$kind, "local"), tr$steps)
}

# ---------------------------------------------------------------------------
# P1D-06: preview safeguards
# ---------------------------------------------------------------------------

ro_preview_doc <- function() {
  txt <- c("The board met in spring and approved the plan.",
           "Office moves were finished in the autumn.",
           "Enrolment reached 482 participants across nine sites.",
           "The auditors signed the accounts in March.")
  ro_chunks(txt, section = sprintf("Part %d", 1:4))
}

ro_planner <- function(treatments, answer = function(body) "PLANNED ANSWER") {
  gr_mock_client(function(m, p) {
    sys <- m[[1]]$content
    if (grepl("You plan how to read a document", sys, fixed = TRUE)) {
      return(preview_plan_json(treatments))
    }
    if (grepl("extract evidence, not answers", sys, fixed = TRUE)) return("NONE")
    answer(paste(vapply(m, function(x) x$content, ""), collapse = "\n"))
  })
}

test_that("unskip_k is off by default and leaves the spec as it was", {
  expect_null(gr_read_spec("preview")$unskip_k)
  expect_null(gr_read_spec("preview")$reread_on)
  expect_identical(gr_read_spec("preview", unskip_k = 1)$unskip_k, 1L)
  expect_identical(gr_read_spec("preview", reread_on = "not")$reread_on, "not_found")
  expect_error(gr_read_spec("preview", reread_on = "always"), class = "gr_bad_setting")
})

test_that("each skip is logged with its score, and the plan is followed by default", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  cl <- ro_planner(c("read", "read", "skip", "read"))
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, "preview", trace = tr))
  skips <- ro_steps(tr, "preview.skip")
  expect_length(skips, 1L)
  expect_identical(skips[[1]]$detail$section, 3L)
  expect_gt(skips[[1]]$detail$score, 0)
  expect_false(skips[[1]]$detail$unskipped)
  expect_identical(a$notes$skipped, 1L)
  expect_null(a$notes$unskipped)
  expect_false(grepl("482", cl$calls()[[length(cl$calls())]]$messages[[3]]$content))
})

test_that("unskip_k = 1 reads the only section holding the question's words", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  cl <- ro_planner(c("read", "read", "skip", "skip"))
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", unskip_k = 1), trace = tr))
  expect_identical(a$notes$unskipped, 3L)
  expect_identical(a$notes$skipped, 1L)
  skips <- ro_steps(tr, "preview.skip")
  expect_identical(vapply(skips, function(s) s$detail$unskipped, logical(1)), c(TRUE, FALSE))
  last <- cl$calls()[[length(cl$calls())]]
  expect_true(any(grepl("482", vapply(last$messages, function(x) x$content, ""))))
  # A section that shares no word with the question is not unskipped.
  cl2 <- ro_planner(c("read", "skip", "read", "read"))
  a2 <- quiet(gr_read(ch, q, cl2, gr_read_spec("preview", unskip_k = 1)))
  expect_identical(a2$notes$unskipped, integer(0))
  expect_identical(a2$notes$skipped, 1L)
})

test_that("reread_on = 'not_found' reads what the plan left out after a not-found", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  answer <- function(body) if (grepl("482", body)) "482 participants." else "NOT_IN_DOCUMENT"
  # Default: the not-found stands and no second answer request is sent.
  cl <- ro_planner(c("read", "read", "skip", "read"), answer)
  a <- quiet(gr_read(ch, q, cl, "preview"))
  expect_true(is_not_found(a$answer))
  expect_false("preview.reread" %in% vapply(cl$calls(), function(x) x$label, ""))
  # Opted in: one more request over the skipped section finds it.
  cl <- ro_planner(c("read", "read", "skip", "read"), answer)
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found"), trace = tr))
  expect_identical(a$answer, "482 participants.")
  expect_identical(vapply(cl$calls(), function(x) x$label, "")[length(cl$calls())],
                   "preview.reread")
  expect_true(a$notes$reread$found)
  expect_identical(a$chunks_used, 3L)
  expect_length(ro_steps(tr, "preview.reread"), 1L)
  # A plan that skipped everything is re-read too.
  cl <- ro_planner(rep("skip", 4), answer)
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found")))
  expect_identical(a$answer, "482 participants.")
  # A re-read that finds nothing leaves the not-found and says so.
  cl <- ro_planner(c("read", "read", "skip", "read"), function(body) "NOT_IN_DOCUMENT")
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found")))
  expect_true(is_not_found(a$answer))
  expect_false(a$notes$reread$found)
})

test_that("reread_on raises the preview's worst case by one request", {
  ch <- ro_preview_doc()
  st <- harnessr:::read_input_stats(ch, gr_read_spec("preview"), gr_mock_client(), "q")
  base <- harnessr:::cost_preview(st, gr_read_spec("preview"))
  more <- harnessr:::cost_preview(st, gr_read_spec("preview", reread_on = "not_found"))
  expect_identical(as.integer(more$calls_max), as.integer(base$calls_max) + 1L)
})

# ---------------------------------------------------------------------------
# P1D-07: rerank when every candidate scores low
# ---------------------------------------------------------------------------

ro_rerank_client <- function(score = 1, answer = "NOT_IN_DOCUMENT") {
  gr_mock_client(function(m, p) {
    if (identical(p$schema_name, "relevance")) {
      return(sprintf('{"score": %d, "reason": "weak"}', as.integer(score)))
    }
    answer
  })
}

ro_rerank_doc <- function() {
  ro_chunks(sprintf("Budget line %d mentions revenue planning for year %d.", 1:8, 2010 + 1:8))
}

test_that("rerank records retrieval_low_score when every candidate scores low", {
  ch <- ro_rerank_doc()
  cl <- ro_rerank_client(score = 1)
  tr <- gr_trace()
  a <- quiet(gr_read(ch, "What was revenue?", cl, "rerank", trace = tr))
  expect_true(is_not_found(a$answer))
  expect_true(a$notes$retrieval_low_score)
  expect_false(a$partial)
  expect_false("rerank.answer" %in% vapply(cl$calls(), function(x) x$label, ""))
  low <- ro_steps(tr, "rerank.low_score")
  expect_length(low, 1L)
  expect_identical(low[[1]]$detail$action, "not_found")
  # A candidate at the cut is not low.
  a2 <- quiet(gr_read(ch, "What was revenue?", ro_rerank_client(score = 4, answer = "x"),
                      "rerank"))
  expect_null(a2$notes$retrieval_low_score)
})

test_that("low_score = 'read_top_k' sends the top 5 and marks a not-found", {
  ch <- ro_rerank_doc()
  spec <- gr_read_spec("rerank", low_score = "read_top_k", top_k = 2)
  expect_identical(spec$low_score, "read_top_k")
  expect_null(gr_read_spec("rerank")$low_score)
  cl <- ro_rerank_client(score = 1)
  a <- quiet(gr_read(ch, "What was revenue?", cl, spec))
  calls <- cl$calls()
  last <- calls[[length(calls)]]
  expect_identical(last$label, "rerank.answer")
  expect_length(regmatches(last$messages[[2]]$content,
                           gregexpr("\\[chunk [0-9]+\\]", last$messages[[2]]$content))[[1]], 5L)
  expect_true(is_not_found(a$answer))
  expect_true(a$notes$retrieval_low_score)
  expect_true(a$notes$read_below_min_score)
  # An answer found below the cut is kept, and says what it read.
  a2 <- quiet(gr_read(ch, "What was revenue?", ro_rerank_client(1, "Revenue was 4."), spec))
  expect_identical(a2$answer, "Revenue was 4.")
  expect_null(a2$notes$retrieval_low_score)
  expect_true(a2$notes$read_below_min_score)
})

# ---------------------------------------------------------------------------
# P1D-10: one fusion function for retrieve and iterative
# ---------------------------------------------------------------------------

ro_rank_doc <- function() {
  ro_chunks(c("Revenue rose to 45.2 million dollars in fiscal 2024.",
              "The margin on revenue was 41 percent, with revenue growth steady.",
              "Staff numbers grew to 310 across two plants.",
              "Currency exposure is the principal risk named.",
              "Revenue guidance for next year is 49 to 52 million.",
              "The auditors signed the accounts without qualification."))
}

ro_order <- function(reader, spec_args, embedder = NULL) {
  local_registries()
  if (!is.null(embedder)) gr_options(embedder = embedder)
  ch <- ro_rank_doc()
  cl <- gr_mock_client(function(m, p) {
    if (identical(p$schema_name, "iterative_step")) {
      return('{"can_answer": true, "answer": "45.2 million", "next_query": ""}')
    }
    "45.2 million"
  })
  spec <- do.call(gr_read_spec, c(list(reader, top_k = 6L), spec_args))
  a <- quiet(gr_read(ch, "What was revenue in 2024?", cl, spec))
  as.integer(a$chunks_used)
}

test_that("fusion is off by default and rrf_k is cited", {
  expect_null(gr_read_spec("retrieve")$fusion)
  expect_null(gr_read_spec("retrieve")$rrf_k)
  expect_identical(gr_read_spec("retrieve", fusion = "rrf")$fusion, "rrf")
  expect_identical(gr_read_spec("retrieve", fusion = "rrf", rrf_k = 10)$rrf_k, 10)
  s <- gr_settings("read")
  expect_identical(s$rrf_k$evidence$status, "cited")
  expect_match(s$rrf_k$evidence$source, "Cormack, Clarke and Buettcher \\(2009\\)")
  expect_identical(s$rrf_k$default, 60)
})

test_that("the default fusion keeps the 0.6.0 blend and rrf is rank based", {
  ns <- asNamespace("harnessr")
  texts <- ro_rank_doc()$chunks$text
  dense <- c(0.9, 0.5, 0.1, 0.2, 0.7, 0.3)
  q <- "What was revenue?"
  expect_identical(ns$fuse_scores(dense, texts, q, list()), dense)
  bm <- ns$bm25_scores(texts, q)
  expect_equal(ns$fuse_scores(dense, texts, q, list(), lexical = TRUE),
               0.5 * dense + 0.5 * ns$scale01(bm))
  r <- ns$fuse_scores(dense, texts, q, list(fusion = "rrf"))
  want <- 1 / (60 + rank(-dense, ties.method = "min")) + 1 / (60 + rank(-bm, ties.method = "min"))
  expect_equal(r, want)
  expect_equal(ns$rrf_scores(list(c(3, 2, 1)), k = 1), c(1 / 2, 1 / 3, 1 / 4))
  # A non-finite score ranks last.
  expect_equal(ns$rrf_scores(list(c(NA, 2, 1)), k = 1), c(1 / 4, 1 / 2, 1 / 3))
})

test_that("retrieve and iterative give the same order on the same inputs", {
  # Embeddings that are not lexical: the default ranks alike.
  expect_identical(ro_order("retrieve", list()), ro_order("iterative", list()))
  # Under rrf, on lexical embeddings as well.
  expect_identical(ro_order("retrieve", list(fusion = "rrf")),
                   ro_order("iterative", list(fusion = "rrf")))
  expect_identical(ro_order("retrieve", list(fusion = "rrf"), "lexical"),
                   ro_order("iterative", list(fusion = "rrf"), "lexical"))
  expect_length(ro_order("retrieve", list(fusion = "rrf"), "lexical"), 6L)
})

# ---------------------------------------------------------------------------
# P3-09 and DEC-05: the outcome, and answer_format
# ---------------------------------------------------------------------------

ro_doc <- function() {
  ro_chunks(c("The trial enrolled 40 participants.",
              "None of the 40 participants dropped out before the end."))
}

test_that("every answer from gr_read() carries an outcome", {
  ch <- ro_doc()
  a <- quiet(gr_read(ch, "Did anyone drop out?",
                     gr_mock_client(function(m, p) "None of the 40 participants dropped out."),
                     "stuff"))
  expect_identical(a$outcome, "answered")
  expect_false(is_not_found(a))
  a <- quiet(gr_read(ch, "What was revenue?", gr_mock_client(function(m, p) "NOT_IN_DOCUMENT"),
                     "stuff"))
  expect_identical(a$outcome, "not_found")
  expect_true(is_not_found(a))
  # A failed request is not a not-found.
  a <- quiet(gr_read(ch, "What was revenue?", gr_mock_client(function(m, p) stop("down")),
                     "stuff"))
  expect_identical(a$outcome, "failed")
  expect_true(is_not_found(a$answer))
  expect_false(is_not_found(a))
  # A limit that stopped the run is a refusal.
  stopped <- new_answer("NOT_IN_DOCUMENT", "stuff", "q", integer(0), gr_trace(), partial = TRUE,
                        notes = list(call_cap_reached = 1))
  expect_identical(harnessr:::answer_outcome(stopped), "refused")
  # A partial answer.
  ans <- new_answer("x", "stuff", "q", 1L, gr_trace(), partial = TRUE)
  expect_identical(harnessr:::answer_outcome(ans), "partial")
  # Without an outcome, the sentinel decides.
  expect_true(is_not_found(new_answer("NOT_IN_DOCUMENT", "stuff", "q", integer(0), gr_trace())))
  expect_true(is_not_found(list(answer = "NOT_IN_DOCUMENT")))
  expect_false(is_not_found(list(answer = "NOT_IN_DOCUMENT", outcome = "failed")))
  expect_match(harnessr::as_json(a), "\"outcome\"")
})

test_that("answer_format = 'parsed' is the default and sends no schema", {
  expect_null(gr_read_spec("stuff")$answer_format)
  expect_identical(gr_read_spec("stuff", answer_format = "schema")$answer_format, "schema")
  expect_error(gr_read_spec("stuff", answer_format = "json"), class = "gr_bad_setting")
  cl <- gr_mock_client(function(m, p) "NOT_IN_DOCUMENT")
  quiet(gr_read(ro_doc(), "q?", cl, "stuff"))
  expect_false(identical(cl$calls()[[1]]$params$schema_name, "answer"))
})

test_that("both formats classify the two example sentences", {
  ch <- ro_doc()
  q <- "Did anyone drop out?"
  # Parsed: the reply as free text, the sentinel read from it.
  parsed <- function(reply) quiet(gr_read(ch, q, gr_mock_client(function(m, p) reply), "stuff"))
  expect_identical(parsed("None of the 40 participants dropped out.")$outcome, "answered")
  expect_identical(parsed("NOT_IN_DOCUMENT. The excerpt does not mention revenue.")$outcome,
                   "not_found")
  # Without the sentinel, a free-text "does not mention" is read as an answer:
  # the limit of the parsed path that the schema exists to test.
  expect_identical(parsed("The excerpt does not mention revenue.")$outcome, "answered")
  # Schema: the outcome is a field of the reply.
  spec <- gr_read_spec("stuff", answer_format = "schema")
  schema <- function(answer, outcome) {
    cl <- gr_mock_client(function(m, p) {
      expect_identical(p$schema_name, "answer")
      jsonlite::toJSON(list(answer = answer, outcome = outcome), auto_unbox = TRUE)
    })
    quiet(gr_read(ch, q, cl, spec))
  }
  a <- schema("None of the 40 participants dropped out.", "answered")
  expect_identical(a$outcome, "answered")
  expect_identical(a$answer, "None of the 40 participants dropped out.")
  expect_true(a$notes$structured$parsed)
  b <- schema("The excerpt does not mention revenue.", "not_found")
  expect_identical(b$outcome, "not_found")
  expect_true(is_not_found(b))
  expect_identical(b$answer, "NOT_IN_DOCUMENT")
  expect_identical(b$notes$structured$reply, "The excerpt does not mention revenue.")
  # A reply that does not parse is read as free text.
  c <- quiet(gr_read(ch, q, gr_mock_client(function(m, p) "NOT_IN_DOCUMENT"), spec))
  expect_identical(c$outcome, "not_found")
  expect_false(c$notes$structured$parsed)
})

test_that("answer_format = 'schema' reaches each covered reader's answer request", {
  ch <- ro_chunks(sprintf("Revenue line %d was %d dollars.", 1:4, 100 + 1:4))
  for (r in c("stuff", "retrieve", "map_reduce", "skim", "hierarchical")) {
    cl <- gr_mock_client(function(m, p) {
      if (identical(p$schema_name, "answer")) {
        return('{"answer": "Revenue was 101 dollars.", "outcome": "answered"}')
      }
      if (grepl("extract evidence", m[[1]]$content, fixed = TRUE)) {
        return("Revenue line 1 was 101 dollars.")
      }
      "Revenue was 101 dollars."
    })
    a <- quiet(gr_read(ch, "What was revenue line 1?", cl,
                       gr_read_spec(r, answer_format = "schema")))
    names <- vapply(cl$calls(), function(x) as.character(x$params$schema_name %||% ""), "")
    expect_true("answer" %in% names, info = r)
    expect_true(a$outcome %in% c("answered", "partial"), info = r)
    expect_false(is_not_found(a), info = r)
  }
})

# ---------------------------------------------------------------------------
# P1D-14: a structured premise verdict with its quote checked
# ---------------------------------------------------------------------------

ro_premise_doc <- function() {
  ro_chunks(c("Revenue rose 12% in 2023, to 45.2 million dollars.",
              "The company opened a second plant in Leipzig.",
              "Staff numbers grew to 310."))
}

ro_verdict <- function(status, quote, answer = "Revenue rose 12% in 2023.") {
  function(m, p) {
    if (identical(p$schema_name, "answer")) {
      return(jsonlite::toJSON(list(answer = answer, premise_status = status, quote = quote),
                              auto_unbox = TRUE))
    }
    "Merged: revenue rose."
  }
}

test_that("premise_verdict is opt-in and needs premise = TRUE", {
  expect_null(gr_read_spec("stuff", premise = TRUE)$premise_verdict)
  expect_identical(gr_read_spec("stuff", premise = TRUE,
                                premise_verdict = "structured")$premise_verdict, "structured")
  expect_error(gr_read_spec("stuff", premise_verdict = "structured"), class = "gr_bad_setting")
  # Under premise = TRUE alone, the sentence rule is sent, with no schema.
  cl <- gr_mock_client(function(m, p) "FALSE_PREMISE: Revenue rose.")
  a <- quiet(gr_read(ro_premise_doc(), "Why did revenue fall?", cl,
                     gr_read_spec("stuff", premise = TRUE)))
  expect_false(identical(cl$calls()[[1]]$params$schema_name, "answer"))
  expect_null(a$premise_verdict)
  expect_identical(a$premise, "Revenue rose.")
})

test_that("a structured verdict carries its quote, checked against the excerpts", {
  ch <- ro_premise_doc()
  q <- "Why did revenue fall in 2023?"
  spec <- gr_read_spec("stuff", premise = TRUE, premise_verdict = "structured")
  cl <- gr_mock_client(ro_verdict("contradicted", "Revenue rose 12% in 2023"))
  a <- quiet(gr_read(ch, q, cl, spec))
  expect_identical(cl$calls()[[1]]$params$schema_name, "answer")
  sys <- cl$calls()[[1]]$messages[[1]]$content
  expect_match(sys, "premise_status", fixed = TRUE)
  expect_false(grepl("FALSE_PREMISE:", sys, fixed = TRUE))
  expect_identical(a$premise, "Revenue rose 12% in 2023.")
  expect_identical(a$premise_verdict$premise_status, "contradicted")
  expect_true(a$premise_verdict$quote_verified)
  expect_false(is_not_found(a))
  # A quote that is not in the excerpts is recorded as not verified.
  a <- quiet(gr_read(ch, q, gr_mock_client(ro_verdict("contradicted", "Revenue doubled")), spec))
  expect_false(a$premise_verdict$quote_verified)
  # A premise that holds is an ordinary answer.
  a <- quiet(gr_read(ch, "How much did revenue rise?",
                     gr_mock_client(ro_verdict("holds", "", "It rose 12%.")), spec))
  expect_identical(a$answer, "It rose 12%.")
  expect_true(is.na(a$premise))
  expect_identical(a$premise_verdict$premise_status, "holds")
  expect_true(is.na(a$premise_verdict$quote))
})

test_that("map_reduce drops a premise flag whose quote is absent", {
  ch <- ro_premise_doc()
  q <- "Why did revenue fall in 2023?"
  spec <- gr_read_spec("map_reduce", premise = TRUE, premise_verdict = "structured",
                       parallel = FALSE)
  # Chunk 1 flags with its own words; chunk 2 flags with a quote it does not
  # hold; chunk 3 is silent.
  cl <- gr_mock_client(function(m, p) {
    if (identical(p$schema_name, "answer")) {
      body <- m[[2]]$content
      if (grepl("Revenue rose", body, fixed = TRUE)) {
        return('{"answer": "Revenue rose 12%.", "premise_status": "contradicted", "quote": "Revenue rose 12% in 2023"}')
      }
      if (grepl("Leipzig", body, fixed = TRUE)) {
        return('{"answer": "Revenue did not fall.", "premise_status": "contradicted", "quote": "Revenue never fell"}')
      }
      return('{"answer": "NOT_IN_DOCUMENT", "premise_status": "holds", "quote": ""}')
    }
    "FALSE_PREMISE: Revenue rose 12% in 2023."
  })
  a <- quiet(gr_read(ch, q, cl, spec))
  expect_identical(as.integer(a$notes$premise_chunks), 1L)
  expect_identical(as.integer(a$notes$premise_dropped), 2L)
  expect_identical(a$notes$degradation, "premise_flagged")
  expect_identical(as.integer(a$chunks_used), 1L)
  # The merge saw only the verified finding.
  merge <- Filter(function(x) identical(x$label, "reduce"), cl$calls())
  if (length(merge)) {
    body <- paste(vapply(merge[[1]]$messages, function(x) x$content, ""), collapse = "\n")
    expect_false(grepl("did not fall", body, fixed = TRUE))
  }
  # Without the structured verdict, nothing is dropped.
  cl2 <- gr_mock_client(function(m, p) {
    if (grepl("Leipzig|Revenue rose", m[[2]]$content)) "FALSE_PREMISE: Revenue rose." else
      "NOT_IN_DOCUMENT"
  })
  a2 <- quiet(gr_read(ch, q, cl2, gr_read_spec("map_reduce", premise = TRUE, parallel = FALSE)))
  expect_null(a2$notes$premise_dropped)
  expect_null(a2$notes$degradation)
  expect_identical(sort(as.integer(a2$notes$premise_chunks)), 1:2)
})

# ---------------------------------------------------------------------------
# P1D-04: gr_methods_text()
# ---------------------------------------------------------------------------

test_that("gr_methods_text() describes an answer from its record only", {
  ch <- ro_chunks(sprintf("Revenue line %d was %d dollars.", 1:4, 100 + 1:4))
  cl <- gr_mock_client(function(m, p) "Revenue was 101 dollars.")
  a <- quiet(gr_read(ch, "What was revenue line 1?", cl, gr_read_spec("retrieve", top_k = 2)))
  txt <- gr_methods_text(a)
  expect_s3_class(txt, "gr_methods_text")
  expect_length(txt, 1L)
  expect_match(txt, sprintf("harnessr %s", utils::packageVersion("harnessr")), fixed = TRUE)
  expect_match(txt, "the 'retrieve' reader with these settings changed from their defaults: top_k = 2",
               fixed = TRUE)
  expect_match(txt, "1 model request(s), which asked for 'mock-model'", fixed = TRUE)
  expect_match(txt, "The provider did not report which model answered them.", fixed = TRUE)
  # Only what the trace holds: embeddings requests appear when it has them.
  n_emb <- sum(vapply(harnessr:::answer_trace(a)$steps,
                      function(s) identical(s$kind, "embedding"), logical(1)))
  expect_identical(grepl("embeddings request(s)", txt, fixed = TRUE), n_emb > 0L)
  sys <- cl$calls()[[1]]$messages[[1]]$content
  expect_match(txt, paste("retrieve.answer", substr(harnessr:::hr_hash(sys), 1, 12)), fixed = TRUE)
  expect_match(txt, "makes no claim beyond it", fixed = TRUE)
  expect_false(grepl("—|–| -- ", txt))
  out <- capture.output(print(txt))
  expect_gt(length(out), 1L)
  # A default spec says so.
  a2 <- quiet(gr_read(ch, "What was revenue line 1?", cl, "stuff"))
  expect_match(gr_methods_text(a2), "the 'stuff' reader at its default settings", fixed = TRUE)
  # The served model, when the provider reported one.
  tr <- gr_trace()
  harnessr:::trace_record(tr, "x.answer", list(list(role = "system", content = "S")),
                       list(ok = TRUE, text = "a", model = "m1", served_model = "m1-2026",
                            usage = list(input = 3L, output = 1L)))
  t2 <- gr_methods_text(tr)
  expect_match(t2, "reported that 'm1-2026' answered 1 of them", fixed = TRUE)
  expect_error(gr_methods_text(1), class = "gr_bad_setting")
})

test_that("gr_methods_text() describes a benchmark's design and requests", {
  qa <- gr_qa_reference(questions = c(revenue = "What was revenue in 2024?"),
                        documents = gr_example(), answers = list("45.2 million"), split = "dev")
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  arms <- hr_sweep(gr_arm("needle", list(method = "structural", max_tokens = 120,
                                          overlap_tokens = 0)),
                   list(top_k = c(2, 4)))
  bench <- quiet(hr_benchmark(arms, qa, runs = 2, client = cl, split = "dev",
                              scorer = gr_scorer_answer()))
  txt <- gr_methods_text(bench)
  expect_match(txt, "The benchmark ran 2 arm(s)", fixed = TRUE)
  expect_match(txt, "top_k = 2", fixed = TRUE)
  expect_match(txt, "on 1 item(s), 2 run(s) per item, 4 run(s) in all", fixed = TRUE)
  expect_match(txt, "model request(s)", fixed = TRUE)
})
