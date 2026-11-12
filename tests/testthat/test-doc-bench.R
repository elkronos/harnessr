# test-doc-bench.R: recipe arms, the QA reference and the answer scorer, run
# through hr_benchmark() on the bundled example document with mock clients.

# Answers from the example report. With temperature 1 the revenue answer is
# last year's figure, so an arm read at that temperature gets it wrong. The
# question about the chief executive is not answered by the report, and the
# question about the auditor is refused.
qa_client <- function() {
  gr_mock_client(function(messages, params) {
    q <- messages[[length(messages)]]$content
    hot <- identical(params$temperature, 1)
    if (grepl("auditor", q, fixed = TRUE)) {
      return(gr_result(FALSE, finish_reason = "refusal",
                       error = "Model refused the request: no."))
    }
    if (grepl("revenue", q, fixed = TRUE)) {
      return(if (hot) "Revenue was 38.7 million dollars." else "Revenue was 45.2 million dollars.")
    }
    if (grepl("Sheffield", q, fixed = TRUE)) return("Sheffield produced 12400 units in 2024.")
    if (grepl("Leipzig", q, fixed = TRUE)) return("Headcount at Leipzig was 186.")
    "NOT_IN_DOCUMENT"
  })
}

qa_ref <- function(split = "test") {
  gr_qa_reference(
    questions = c(revenue = "What was revenue in 2024?",
                  units = "How many units did the Sheffield plant produce?",
                  leipzig = "What was headcount at the Leipzig plant?",
                  ceo = "Who is the chief executive?",
                  dividend = "When is the dividend paid?"),
    documents = gr_example(),
    answers = list(c("45.2 million", "45,200,000"), "12,400", 168, NA, "14 March 2025"),
    unanswerable = "ceo", split = split)
}

two_arms <- function() {
  list(gr_arm("fast", list(temperature = 0), name = "cold"),
       gr_arm("fast", list(temperature = 1), name = "hot"))
}

quiet <- function(expr) suppressMessages(expr)

# ---- gr_qa_reference ---------------------------------------------------------

test_that("gr_qa_reference builds items, labels and clusters from questions and documents", {
  ref <- qa_ref()
  expect_s3_class(ref, "hr_reference")
  expect_identical(ref$ids, c("revenue", "units", "leipzig", "ceo", "dividend"))
  expect_identical(ref$items$units$question, "How many units did the Sheffield plant produce?")
  expect_identical(ref$items$units$document, gr_example())
  # The payload holds no part of the label: whether an item is unanswerable
  # is in its label alone.
  expect_identical(names(ref$items$ceo), c("question", "document"))
  expect_identical(names(ref$items$revenue), c("question", "document"))
  expect_identical(ref$labels$revenue, c("45.2 million", "45,200,000"))
  # A number is taken as text, and an unanswerable item expects the sentinel.
  expect_identical(ref$labels$leipzig, "168")
  expect_identical(ref$labels$ceo, "NOT_IN_DOCUMENT")
  # Clustered by document: a path names itself.
  expect_identical(unique(ref$cluster), gr_example())
  expect_identical(unique(ref$split), "test")
})

test_that("gr_qa_reference names unnamed items, recycles one document and clusters text by content", {
  txt <- "The plant made 12,400 units.\n\nIt employed 214 people."
  ref <- gr_qa_reference(c("How many units?", "How many people?", "Who owns it?"),
                         list(txt, txt, "Another report.\n\nNothing here."),
                         c("12400", "214", NA))
  expect_identical(ref$ids, c("q1", "q2", "q3"))
  # Without `split`, every item is on the dev split, as with hr_reference().
  expect_identical(ref$split, rep("dev", 3))
  expect_identical(ref$cluster[1], ref$cluster[2])
  expect_false(identical(ref$cluster[1], ref$cluster[3]))
  expect_match(ref$cluster[1], "^doc-[0-9a-f]{12}$")
  # No answer and not marked unanswerable: unlabelled.
  expect_identical(ref$labels$q3, NA_character_)
  # The cluster can be given.
  ref2 <- gr_qa_reference(c("a?", "b?"), txt, c("x", "y"), cluster = c("one", "two"))
  expect_identical(ref2$cluster, c("one", "two"))
})

test_that("gr_qa_reference takes unanswerable as flags, ids, positions or the sentinel", {
  q <- c(a = "First?", b = "Second?", c = "Third?")
  ans <- list("x", NA, NULL)
  by_flag <- gr_qa_reference(q, "Some text.", ans, unanswerable = c(FALSE, TRUE, TRUE))
  by_id <- gr_qa_reference(q, "Some text.", ans, unanswerable = c("b", "c"))
  by_pos <- gr_qa_reference(q, "Some text.", ans, unanswerable = 2:3)
  by_sentinel <- gr_qa_reference(q, "Some text.", list("x", "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT"))
  for (r in list(by_flag, by_id, by_pos, by_sentinel)) {
    expect_identical(unname(unlist(r$labels)), c("x", "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT"))
    expect_identical(unname(lapply(r$items, names)), rep(list(c("question", "document")), 3))
  }
})

test_that("gr_qa_reference refuses inconsistent input", {
  q <- c("First?", "Second?")
  expect_error(gr_qa_reference(q, "text", c("x", "y"), unanswerable = 1), class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, "text", list(c("x", "NOT_IN_DOCUMENT"), "y")),
               class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, "text", "x"), class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, c("a", "b", "c"), c("x", "y")), class = "hr_bad_reference")
  expect_error(gr_qa_reference(c("First?", ""), "text", c("x", "y")), class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, "text", c("x", "y"), unanswerable = "nope"),
               class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, list("text", 3), c("x", "y")), class = "hr_bad_reference")
  expect_error(gr_qa_reference(q, "text", c("x", "y"), split = "holdout"),
               class = "hr_bad_reference")
})

# ---- gr_scorer_answer --------------------------------------------------------

test_that("gr_scorer_answer marks an answer right when it contains an accepted answer", {
  s <- gr_scorer_answer()
  expect_s3_class(s, "hr_scorer")
  expect_identical(s$name, "answer_contains")
  item <- list(question = "q", document = "d", unanswerable = FALSE)
  right <- s$fn(item, "Revenue was  45.2 Million dollars.", "45.2 million")
  expect_identical(right, list(correct = TRUE, outcome = "revenue was 45.2 million dollars.",
                               failure_kind = NA_character_))
  # Any of the alternatives.
  expect_true(s$fn(item, "It was 45200000.", list(c("45.2 million", "45,200,000")))$correct)
  # Thousands separators folded on both sides, with a comma or a no-break space.
  expect_true(s$fn(item, "Sheffield made 12400 units.", "12,400")$correct)
  expect_true(s$fn(item, "Sheffield made 12,400 units.", "12400")$correct)
  expect_true(s$fn(item, "Sheffield made 12 400 units.", "12400")$correct)
  expect_true(s$fn(item, "It was 3,000,000.", "3000000")$correct)
  # A number is matched whole.
  expect_false(s$fn(item, "It was 145.2 million.", "45.2 million")$correct)
  expect_false(s$fn(item, "It was 45.25 million.", "45.2")$correct)
  expect_false(s$fn(item, "In 2023,2024 nothing.", "3,202")$correct)
  expect_true(s$fn(item, "It was 45.2.", "45.2")$correct)
  expect_false(s$fn(item, "Change was -12 percent.", "12")$correct)
  expect_false(s$fn(item, "Change was \u221212 percent.", "12")$correct)
  expect_true(s$fn(item, "Change was -12 percent.", "-12")$correct)
  # A word is matched whole too.
  expect_false(s$fn(item, "I do not know who it was.", "no")$correct)
  expect_false(s$fn(item, "The eyes have it.", "yes")$correct)
  expect_false(s$fn(item, "Romeo", "Rome")$correct)
  expect_true(s$fn(item, "Yes, it was Rome.", "rome")$correct)
  expect_true(s$fn(item, "No.", "no")$correct)
  wrong <- s$fn(item, "Revenue was 38.7 million.", "45.2 million")
  expect_identical(wrong$failure_kind, "wrong")
  expect_false(wrong$correct)
})

test_that("gr_scorer_answer scores unanswerable items and not-found answers", {
  s <- gr_scorer_answer()
  item <- list(question = "q", document = "d", unanswerable = TRUE)
  expect_true(s$fn(item, "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT")$correct)
  # is_not_found() tolerates decoration around the sentinel.
  expect_true(s$fn(item, "**NOT_IN_DOCUMENT.**", "NOT_IN_DOCUMENT")$correct)
  expect_true(s$fn(item, list(answer = "NOT_IN_DOCUMENT"), "NOT_IN_DOCUMENT")$correct)
  # An answer to a question the document does not answer is wrong.
  expect_identical(s$fn(item, "The CEO is Ann Lee.", "NOT_IN_DOCUMENT")$failure_kind, "wrong")
  # Expected an answer, got the sentinel.
  answerable <- list(question = "q", document = "d", unanswerable = FALSE)
  expect_identical(s$fn(answerable, "NOT_IN_DOCUMENT", "12400")$failure_kind, "not_in_document")
  # No label: NA.
  expect_identical(s$fn(answerable, "anything", NA)$correct, NA)
})

test_that("gr_scorer_answer maps answer states to failure kinds", {
  s <- gr_scorer_answer()
  item <- list(question = "q", document = "d", unanswerable = FALSE)
  expect_identical(s$fn(item, NULL, "x")$failure_kind, "parse_failure")
  expect_identical(s$fn(item, "   ", "x")$failure_kind, "parse_failure")
  expect_identical(s$fn(item, list(notes = list()), "x")$failure_kind, "parse_failure")
  expect_identical(s$fn(item, list(answer = "x", failure_kind = "refusal"), "x")$failure_kind,
                   "refusal")
  expect_identical(s$fn(item, gr_result(FALSE, error = "down"), "x")$failure_kind, "error")
  expect_identical(s$fn(item, gr_result(FALSE, finish_reason = "refusal"), "x")$failure_kind,
                   "refusal")

  tr <- gr_trace()
  capped <- new_answer("NOT_IN_DOCUMENT", "stuff", "q", integer(0), tr, partial = TRUE,
                       notes = list(cost_cap_reached = 0.01))
  expect_identical(s$fn(item, capped, "x")$failure_kind, "budget_stop")
  calls <- new_answer("Revenue was 38.7 million.", "map_reduce", "q", 1L, tr, partial = TRUE,
                      notes = list(call_cap_reached = 3))
  expect_identical(s$fn(item, calls, "45.2 million")$failure_kind, "budget_stop")
  # A stop on an unanswerable item is a stop, not a right answer: the reader
  # did not look.
  expect_identical(s$fn(list(unanswerable = TRUE), capped, "NOT_IN_DOCUMENT")$failure_kind,
                   "budget_stop")
  # A stopped run that still found the answer is right.
  partial_right <- new_answer("Revenue was 45.2 million.", "map_reduce", "q", 1L, tr,
                              partial = TRUE, notes = list(call_cap_reached = 3))
  expect_true(s$fn(item, partial_right, "45.2 million")$correct)
  # A cap note on an answer that is not partial is not a stop.
  not_partial <- new_answer("NOT_IN_DOCUMENT", "stuff", "q", integer(0), tr,
                            notes = list(call_cap_reached = 3))
  expect_identical(s$fn(item, not_partial, "x")$failure_kind, "not_in_document")
})

test_that("a model refusal on the answer's trace is scored as a refusal", {
  cl <- qa_client()
  a <- quiet(answer_document(gr_example(), "Who is the auditor?", "fast", client = cl))
  expect_true(is_not_found(a$answer))
  s <- gr_scorer_answer()
  expect_identical(s$fn(list(unanswerable = FALSE), a, "Smith LLP")$failure_kind, "refusal")
  expect_identical(s$fn(list(unanswerable = TRUE), a, "NOT_IN_DOCUMENT")$failure_kind, "refusal")
})

# ---- gr_arm and gr_arms ------------------------------------------------------

test_that("gr_arm wraps a recipe as an hr_arm with its settings as params", {
  a <- gr_arm("fast", list(top_k = 3))
  expect_s3_class(a, "hr_arm")
  expect_identical(a$name, "fast")
  expect_identical(a$params, list(recipe = "fast", top_k = 3))
  expect_identical(a$version, as.character(utils::packageVersion("harnessr")))
  # The same arm built twice has the same hash; other settings, another hash.
  expect_identical(gr_arm("fast", list(top_k = 3))$hash, a$hash)
  expect_false(identical(gr_arm("fast", list(top_k = 4))$hash, a$hash))
  expect_identical(gr_arm("thorough", name = "slow")$name, "slow")
  expect_identical(gr_arm("auto")$params, list(recipe = "auto"))
  expect_identical(gr_arm(gr_recipe("mine", read = "stuff"))$name, "mine")
  # Unknown settings fail when the arm is built, not on every run.
  expect_error(gr_arm("fast", list(not_a_setting = 1)))
  expect_error(gr_arm("auto", list(not_a_setting = 1)))
  expect_error(gr_arm("fast", list(1)), class = "hr_bad_arm")
  expect_error(gr_arm("fast", name = ""), class = "hr_bad_arm")
})

test_that("gr_qa_reference formats each number in an answer on its own", {
  ref <- gr_qa_reference(c(a = "q?"), "Some text.\n\nMore.", list(c(1204, 45.2)), split = "test")
  expect_identical(ref$labels$a, c("1204", "45.2"))
  ten <- gr_qa_reference(paste0("q", 1:10, "?"), "Some text.\n\nMore.", as.list(1:10),
                         split = "test")
  expect_identical(ten$ids[c(1, 10)], c("q01", "q10"))
})

test_that("gr_arms builds one arm per recipe, named by recipe or by the names given", {
  arms <- gr_arms(c("fast", "thorough"))
  expect_identical(names(arms), c("fast", "thorough"))
  expect_true(all(vapply(arms, inherits, logical(1), what = "hr_arm")))
  named <- gr_arms(c(quick = "fast", slow = "thorough"), settings = list(temperature = 0))
  expect_identical(names(named), c("quick", "slow"))
  expect_identical(named$slow$params, list(recipe = "thorough", temperature = 0))
  expect_identical(names(gr_arms(gr_recipes("fast"))), "fast")
  one <- gr_arms(list(ingest = list(), segment = list(), read = list()))
  expect_length(one, 1L)
  expect_s3_class(one[[1]], "hr_arm")
  expect_error(gr_arms(c("fast", "fast")), class = "hr_bad_arm")
  expect_error(gr_arms(character(0)), class = "hr_bad_arm")
})

test_that("an arm run reads the item's document into the run's trace at the run's draw", {
  cl <- qa_client()
  arm <- gr_arm("fast")
  tr <- gr_trace()
  ctx <- list(client = cl, trace = tr, governor = NULL, draw_index = 3L)
  item <- list(question = "What was revenue in 2024?", document = gr_example())
  a <- quiet(arm$run(item, ctx))
  expect_s3_class(a, "gr_answer")
  expect_identical(a$answer, "Revenue was 45.2 million dollars.")
  expect_identical(a$trace, tr)
  req <- Filter(function(s) !is.null(s$model), tr$steps)
  expect_identical(length(req), 1L)
  expect_identical(req[[1]]$params$draw_index, 3L)
  # The mock was asked with the draw index too.
  expect_identical(cl$calls()[[1]]$params$draw_index, 3L)
  # Chunks are read with gr_read(); "auto" needs the document itself.
  ch <- quiet(gr_segment(gr_example(), list(method = "paragraph", max_tokens = 4000)))
  b <- quiet(arm$run(list(question = "What was revenue in 2024?", document = ch),
                     list(client = cl, trace = gr_trace(), draw_index = 1L)))
  expect_identical(b$answer, "Revenue was 45.2 million dollars.")
  expect_error(gr_arm("auto")$run(list(question = "q", document = ch),
                                  list(client = cl, trace = gr_trace(), draw_index = 1L)),
               class = "gr_bad_recipe")
  expect_error(arm$run("just a question", ctx), class = "hr_bad_reference")
})

# ---- end to end --------------------------------------------------------------

test_that("a two-arm benchmark over a QA reference scores right, wrong and unanswerable items", {
  bench <- quiet(hr_benchmark(two_arms(), qa_ref(), runs = 5, client = qa_client(),
                              scorer = gr_scorer_answer()))
  expect_s3_class(bench, "hr_bench")
  expect_identical(nrow(bench), 50L)
  expect_identical(attr(bench, "scorer"), "answer_contains")
  one <- bench[bench$run == 1L, c("item", "arm", "correct", "failure_kind")]
  rownames(one) <- NULL
  expect_identical(one$item, rep(c("revenue", "units", "leipzig", "ceo", "dividend"), each = 2))
  expect_identical(one$arm, rep(c("cold", "hot"), 5))
  expect_identical(one$correct, c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE,
                                  FALSE, FALSE))
  expect_identical(one$failure_kind, c(NA, "wrong", NA, NA, "wrong", "wrong", NA, NA,
                                       "not_in_document", "not_in_document"))
  # Every run of an arm on an item is the same here, and is its own draw.
  expect_identical(nrow(unique(bench[, c("item", "arm", "correct", "failure_kind")])), 10L)
  expect_identical(bench$draw_index, bench$run)
  tr <- attr(bench, "traces")[[bench$ledger_id[7]]]
  draws <- vapply(Filter(function(s) !is.null(s$model), tr$steps),
                  function(s) s$params$draw_index, integer(1))
  expect_identical(draws, bench$run[7])

  rep <- hr_report(bench)
  expect_identical(rep$accuracy$arm, c("cold", "hot"))
  expect_equal(rep$accuracy$estimate, c(0.6, 0.4))
  expect_identical(rep$failures$wrong, c(5L, 10L))
  expect_identical(rep$failures$not_in_document, c(5L, 5L))
})

test_that("a refused request is a refusal in the benchmark, and a limit a budget stop", {
  ref <- gr_qa_reference(c(auditor = "Who is the auditor?", revenue = "What was revenue in 2024?"),
                         gr_example(), c("Smith LLP", "45.2 million"), split = "test")
  bench <- quiet(hr_benchmark(gr_arm("fast"), ref, runs = 5, client = qa_client(),
                              scorer = gr_scorer_answer()))
  expect_identical(unique(bench$failure_kind[bench$item == "auditor"]), "refusal")
  expect_identical(bench$correct[bench$item == "revenue"], rep(TRUE, 5))

  # One call for the whole benchmark: the first run reads, and the reader of
  # every later run refuses to start, which is a budget stop, not an error.
  # The warning names the limit the readers met, though no request of
  # theirs was refused: each reader stopped before sending one.
  stop_warning <- NULL
  stopped <- withCallingHandlers(
    quiet(hr_benchmark(gr_arm("fast"), ref, runs = 5, client = qa_client(),
                       scorer = gr_scorer_answer(), split = "test",
                       governor = hr_governor(max_calls = 1))),
    hr_budget_stopped = function(w) {
      stop_warning <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    })
  expect_identical(stopped$failure_kind[stopped$item == "revenue"], rep("budget_stop", 5))
  expect_match(stop_warning, "^9 of 10 runs were stopped by the benchmark's limits \\(calls: 9\\)")
  # The note names the limit on the run's trace, and the trace's own
  # stop_reason, which a replay reads, is left as the governor set it.
  tr <- attr(stopped, "traces")[[2]]
  expect_true(any(vapply(tr$steps, function(s) identical(s$label, "budget.preflight"), logical(1))))
  expect_true(is.null(tr$stop_reason) || is.na(tr$stop_reason))
})

test_that("a reader stopped before it starts by a spending limit or an unpriced model is named", {
  ref <- gr_qa_reference(c(revenue = "What was revenue in 2024?", units = "How many units?"),
                         gr_example(), c("45.2 million", "12,400"), split = "test")
  stop_of <- function(expr) {
    msg <- NULL
    withCallingHandlers(quiet(expr), hr_budget_stopped = function(w) {
      msg <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }, gr_cost_uncheckable = function(w) invokeRestart("muffleWarning"))
    msg
  }
  cl <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
  local_model <- function(...) {
    suppressWarnings(gr_register_model("bench-priced-model", context_window = 128000L,
                                       max_output = 16384L, ...))
  }
  local_model(input_usd = 10, output_usd = 30)
  on.exit(suppressWarnings(gr_register_model("bench-priced-model", context_window = 128000L,
                                             max_output = 16384L)), add = TRUE)
  arm <- gr_arm("fast", list(model = "bench-priced-model"))
  w <- stop_of(hr_benchmark(arm, ref, runs = 5, client = cl, scorer = gr_scorer_answer(),
                            governor = hr_governor(max_cost_usd = 0.05)))
  expect_match(w, "\\(cost: [0-9]+\\)")
  expect_false(grepl("unknown", w, fixed = TRUE))
  # With no price, a spending limit stops a real client's reader before it
  # starts; a mock is let through with a warning instead. Nothing is sent:
  # the check comes before the first request, and the address is closed.
  local_model()
  real <- gr_client(model = "bench-priced-model", api_key = "sk-not-a-real-key",
                    base_url = "http://127.0.0.1:9/v1", max_retries = 0L)
  w <- stop_of(hr_benchmark(gr_arm("fast"), ref, runs = 5, client = real,
                            scorer = gr_scorer_answer(), governor = hr_governor(max_cost_usd = 1)))
  expect_match(w, "\\(unpriced: 10\\)")
  # A priced model under a limit too small for one read is stopped by the
  # reader's own check, before the governor sees a request: the cost label
  # then comes from the check's error and the note it leaves on the trace.
  priced <- gr_client(model = "gpt-4o", api_key = "sk-not-a-real-key",
                      base_url = "http://127.0.0.1:9/v1", max_retries = 0L)
  b <- NULL
  w <- stop_of(b <- hr_benchmark(gr_arm("fast"), ref, runs = 5, client = priced,
                                 scorer = gr_scorer_answer(),
                                 governor = hr_governor(max_cost_usd = 1e-6)))
  expect_match(w, "\\(cost: 10\\)")
  notes <- Filter(function(s) identical(s$label, "budget.preflight"),
                  attr(b, "traces")[[1]]$steps)
  expect_length(notes, 1L)
  expect_identical(notes[[1]]$detail$limit, "cost")
  expect_identical(attr(b, "traces")[[1]]$calls, 0L)
})

test_that("recipe arms under a cache are separate draws, and a second pass is answered from it", {
  dir <- withr::local_tempdir()
  cl <- gr_cache_client(qa_client(), gr_cache(dir))
  ref <- qa_ref()
  first <- quiet(hr_benchmark(two_arms(), ref, runs = 5, client = cl, scorer = gr_scorer_answer()))
  # The reference is locked once scored, so the second pass builds it again.
  second <- quiet(hr_benchmark(two_arms(), qa_ref(), runs = 5, client = cl,
                               scorer = gr_scorer_answer()))
  expect_identical(second$correct, first$correct)
  expect_identical(second$failure_kind, first$failure_kind)
  steps <- unlist(lapply(attr(second, "traces"), function(tr) {
    Filter(function(s) !is.null(s$model), tr$steps)
  }), recursive = FALSE)
  expect_true(all(vapply(steps, function(s) isTRUE(s$cached), logical(1))))
})

test_that("hr_report gives a descriptive summary of a short recipe benchmark", {
  bench <- quiet(suppressWarnings(hr_benchmark(two_arms(), qa_ref(), runs = 2,
                                               client = qa_client(),
                                               scorer = gr_scorer_answer())))
  rep <- hr_report(bench)
  expect_true(rep$descriptive)
  expect_identical(rep$method, "none")
  expect_equal(rep$accuracy$estimate, c(0.6, 0.4))
  expect_true(all(is.na(rep$accuracy$lower)))
  expect_output(print(rep), "Descriptive only")
})

test_that("a draw index on the trace reaches requests that do not give one", {
  cl <- gr_mock_client(function(m, p) "ok")
  tr <- gr_trace()
  tr$draw_index <- 2L
  gr_call(cl, "hi", trace = tr)
  gr_call(cl, "hi", trace = tr, draw_index = 4)
  expect_identical(vapply(cl$calls(), function(x) x$params$draw_index, integer(1)), c(2L, 4L))
  # Without one on the trace, nothing changes.
  plain <- gr_trace()
  gr_call(cl, "hi", trace = plain)
  expect_null(cl$calls()[[3]]$params$draw_index)
})

# ---- review fixes ------------------------------------------------------------

test_that("an arm cannot read from the payload which items are unanswerable", {
  qa <- gr_qa_reference(c(revenue = "What was revenue in 2024?",
                          ceo = "Who is the chief executive?"),
                        gr_example(), list("45.2 million", NA), unanswerable = "ceo",
                        split = "test")
  cheat <- hr_arm("cheat", function(item, ctx) {
    if (isTRUE(item$unanswerable)) "NOT_IN_DOCUMENT" else "no idea"
  })
  b <- hr_benchmark(cheat, qa, runs = 5, client = NULL, scorer = gr_scorer_answer())
  # Before the fix the arm saw unanswerable = TRUE on ceo and scored 5 of 5
  # there. Now it answers "no idea" on both items: 0 of 10.
  expect_identical(c(tapply(b$correct, b$item, mean))[c("ceo", "revenue")],
                   c(ceo = 0, revenue = 0))
  expect_identical(unique(b$failure_kind), "wrong")
  # The label alone makes an item unanswerable for the scorer.
  s <- gr_scorer_answer()
  expect_true(s$fn(list(question = "q"), "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT")$correct)
  # A payload flag without the label no longer counts: no label, no score.
  expect_identical(s$fn(list(unanswerable = TRUE), "NOT_IN_DOCUMENT", NA)$correct, NA)
})

test_that("gr_scorer_answer writes a numeric label in plain digits", {
  # as.character(100000) is "1e+05"; the label is compared as "100000", and
  # "100,000" folds to "100000".
  s <- gr_scorer_answer()
  item <- list(question = "q", document = "d")
  expect_identical(s$fn(item, "Sheffield made 100,000 units.", 100000),
                   list(correct = TRUE, outcome = "sheffield made 100000 units.",
                        failure_kind = NA_character_))
  expect_true(s$fn(item, "It made 100000.", 100000)$correct)
  expect_true(s$fn(item, "A rate of 0.0001.", 1e-04)$correct)
  expect_identical(s$fn(item, "It made 1e+05.", 100000)$failure_kind, "wrong")
})

test_that("gr_scorer_answer finds numbers with a unit, in a range, and not in a decimal", {
  s <- gr_scorer_answer()
  item <- list(question = "q", document = "d")
  # A unit written against the number: before the fix FALSE.
  expect_true(s$fn(item, "\u20ac45.2m", "45.2")$correct)
  expect_true(s$fn(item, "Take 5mg twice a day.", "5")$correct)
  # A range: the hyphen follows a digit, so it is not a minus sign. Before
  # the fix FALSE.
  expect_true(s$fn(item, "The range was 12-15.", "15")$correct)
  expect_true(s$fn(item, "The range was 12-15.", "12")$correct)
  expect_true(s$fn(item, "From 2020-2024.", "2024")$correct)
  # A leading decimal point: .12 is 0.12, not 12. Before the fix TRUE.
  expect_false(s$fn(item, "The value is .12", "12")$correct)
  expect_false(s$fn(item, "The value is 0.12", "12")$correct)
  # Still: a minus sign with no digit before it, a digit or a decimal part
  # after the number, and a letter after a word.
  expect_false(s$fn(item, "Change was -12 percent.", "12")$correct)
  expect_false(s$fn(item, "-12", "12")$correct)
  expect_false(s$fn(item, "It was 125.", "12")$correct)
  expect_false(s$fn(item, "It was 12.5.", "12")$correct)
  expect_false(s$fn(item, "Romeo", "Rome")$correct)
})
