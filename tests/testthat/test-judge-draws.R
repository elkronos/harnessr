# test-judge-draws.R: a judge, a stage or a structured call made inside a
# benchmark run is a step of that run. Its requests count against the run's
# governor, are part of the run's cost, and are sent at the run's draw index
# and under its draw scope.

# A mock that answers a judge's request with a new reason every time, grading
# odd requests "pass" and even ones "fail", and anything else with an answer.
# The params of every request it is sent are kept.
draw_judge <- function(answer = "Revenue was 45.2 million dollars [chunk 1].") {
  env <- new.env()
  env$n <- 0L
  env$sent <- list()
  env$client <- hr_mock_client(function(messages, params) {
    env$n <- env$n + 1L
    env$sent[[length(env$sent) + 1L]] <- list(messages = messages, params = params)
    if (grepl("You grade one response", messages[[1]]$content, fixed = TRUE)) {
      return(sprintf('{"verdict": "%s", "reason": "reply %d"}',
                     if (env$n %% 2L) "pass" else "fail", env$n))
    }
    answer
  })
  env
}

draw_reference <- function() {
  gr_qa_reference(questions = c(revenue = "What was revenue in 2024?",
                                units = "How many units did Sheffield produce?"),
                  documents = gr_example(), answers = list("45.2 million", "12,400"),
                  split = "test")
}

judge_steps <- function(trace) {
  Filter(function(s) startsWith(as.character(s$label %||% ""), "judge.") && !is.null(s$model),
         trace$steps)
}

test_that("a judge given a trace counts against that trace's governor", {
  m <- draw_judge()
  run <- hr_trace(governor = hr_governor(max_calls = 2))
  res <- hr_judge("Paris", m$client, mode = "grade", reference = "Paris", rubric = "r",
                  trace = run)
  expect_identical(res$judge_cost$calls, 2L)
  expect_identical(run$calls, 2L)
  # The run's two calls are spent, so its next request is refused.
  r <- suppressWarnings(hr_call(m$client, "Answer.", trace = run))
  expect_false(r$ok)
  expect_length(run$refusals, 1L)
  expect_identical(m$n, 2L)
})

test_that("a judge given a trace is drawn at the trace's draw index and scope", {
  m <- draw_judge()
  cached <- hr_cache_client(m$client, hr_cache(tempfile("judge-draws-")))
  reasons <- vapply(1:3, function(r) {
    tr <- hr_trace()
    tr$draw_index <- r
    tr$draw_scope <- "arm"
    j <- hr_judge("Paris", cached, mode = "grade", reference = "Paris", rubric = "r",
                  trace = tr, orders = 1)
    st <- judge_steps(tr)
    expect_length(st, 1L)
    expect_identical(as.integer(st[[1]]$params$draw_index), r)
    expect_identical(st[[1]]$draw_scope, "arm")
    j$verdicts$reason
  }, character(1))
  # Three draws, three replies: the cache does not hand every run the first.
  expect_identical(reasons, c("reply 1", "reply 2", "reply 3"))
  expect_identical(vapply(m$sent, function(s) as.integer(s$params$draw_index), 1L), 1:3)
  # A draw index given to the judge is used instead of the trace's.
  tr <- hr_trace()
  tr$draw_index <- 5L
  invisible(hr_judge("Paris", cached, mode = "grade", reference = "Paris", rubric = "r",
                     trace = tr, orders = 1, draw_index = 7))
  expect_identical(as.integer(judge_steps(tr)[[1]]$params$draw_index), 7L)
})

test_that("a judge in a benchmark arm is in the run's usd and the benchmark's count", {
  hr_register_model("judge-draws-priced", context_window = 128000L, max_output = 4096L,
                    input_usd = 2, output_usd = 8)
  m <- draw_judge("Revenue was 45.2 million dollars.")
  log <- new.env()
  judged <- hr_arm("judged", function(item, ctx) {
    ans <- ctx$call(item$question, model = "judge-draws-priced", label = "answer")
    j <- hr_judge(ans$text, ctx$client, mode = "grade", reference = "45.2 million",
                  model = "judge-draws-priced", rubric = "r", trace = ctx$trace)
    log[[ctx$item_id]] <- j$judge_cost$usd
    ans$text
  })
  b <- quiet(suppressWarnings(hr_benchmark(judged, draw_reference(), runs = 1,
                                           client = m$client, scorer = gr_scorer_answer(),
                                           governor = hr_governor(max_calls = 10))))
  traces <- attr(b, "traces")
  for (i in seq_len(nrow(b))) {
    tr <- traces[[b$ledger_id[i]]]
    js <- judge_steps(tr)
    expect_length(js, 2L)
    expect_true(all(vapply(js, function(s) identical(s$draw_scope, "judged"), logical(1))))
    expect_true(all(vapply(js, function(s) identical(as.integer(s$params$draw_index), 1L),
                           logical(1))))
    # The run's usd holds the answer and the judge, once each.
    expect_equal(b$usd[i], sum(hr_trace_cost(tr)$usd))
    expect_gt(log[[b$item[i]]], 0)
    answer_usd <- b$usd[i] - log[[b$item[i]]]
    expect_gt(answer_usd, 0)
  }
  expect_identical(attr(b, "trace")$calls, 6L)
  # Three calls: the first run's answer and its two judge requests. The second
  # run has nothing left and is a budget stop.
  m2 <- draw_judge("Revenue was 45.2 million dollars.")
  b3 <- quiet(suppressWarnings(hr_benchmark(judged, draw_reference(), runs = 1,
                                            client = m2$client, scorer = gr_scorer_answer(),
                                            governor = hr_governor(max_calls = 3))))
  expect_identical(b3$failure_kind, c(NA, "budget_stop"))
  expect_identical(m2$n, 3L)
})

test_that("a judged arm under a cache makes distinct draws", {
  m <- draw_judge()
  cached <- hr_cache_client(m$client, hr_cache(tempfile("judge-bench-")))
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  arm <- hr_arm("judged", function(item, ctx) {
    j <- hr_judge("Paris", ctx$client, mode = "grade", reference = "Paris", rubric = "r",
                  trace = ctx$trace, orders = 1)
    j$verdicts$reason
  })
  b <- quiet(hr_benchmark(arm, ref, runs = 5, client = cached, scorer = hr_scorer_exact()))
  expect_identical(b$outcome, sprintf("reply %d", 1:5))
})

test_that("a stage called with ctx$trace in an arm is sent at the run's draw", {
  m <- draw_judge()
  cached <- hr_cache_client(m$client, hr_cache(tempfile("stage-bench-")))
  arm <- hr_arm("stages", function(item, ctx) {
    ch <- gr_segment(item$document, list(method = "paragraph", max_tokens = 200),
                     trace = ctx$trace)
    gr_read(ch, item$question, ctx$client, list(reader = "retrieve", top_k = 2),
            trace = ctx$trace)
  })
  b <- quiet(suppressWarnings(hr_benchmark(arm, draw_reference(), runs = 2, client = cached,
                                           scorer = gr_scorer_answer())))
  expect_identical(nrow(b), 4L)
  draws <- vapply(m$sent, function(s) as.integer(s$params$draw_index %||% 0L), 1L)
  expect_identical(sort(draws), c(1L, 1L, 2L, 2L))
  for (tr in attr(b, "traces")) {
    req <- Filter(function(s) !is.null(s$model), tr$steps)
    expect_true(all(vapply(req, function(s) identical(s$draw_scope, "stages"), logical(1))))
  }
})

test_that("ctx$call_json is a structured call on the run's trace and draw", {
  schema <- list(type = "object", properties = list(answer = list(type = "string")),
                 required = list("answer"), additionalProperties = FALSE)
  sent <- new.env()
  sent$draws <- integer()
  cl <- hr_mock_client(function(messages, params) {
    sent$draws <- c(sent$draws, as.integer(params$draw_index))
    if (grepl("Peru", messages[[length(messages)]]$content)) return("not json")
    sprintf('{"answer": "Paris %d"}', params$draw_index)
  })
  cached <- hr_cache_client(cl, hr_cache(tempfile("call-json-")))
  ref <- hr_reference(list(q1 = "France", q2 = "Peru"), c("Paris", "Lima"), "a",
                      split = "test")
  got <- new.env()
  arm <- hr_arm("json", function(item, ctx) {
    out <- ctx$call_json(paste("Capital of", item), schema = schema, label = "capital")
    got[[paste(item, ctx$run)]] <- out
    if (inherits(out, "gr_result")) out else out$answer
  })
  b <- quiet(suppressWarnings(hr_benchmark(arm, ref, runs = 2, client = cached,
                                           scorer = hr_scorer_exact(),
                                           governor = hr_governor(max_calls = 10))))
  expect_identical(got[["France 1"]], list(answer = "Paris 1"))
  expect_identical(got[["France 2"]], list(answer = "Paris 2"))
  expect_s3_class(got[["Peru 1"]], "gr_result")
  expect_false(got[["Peru 1"]]$ok)
  expect_match(got[["Peru 1"]]$error, "does not meet the schema")
  expect_identical(b$failure_kind[b$item == "q2"], c("error", "error"))
  expect_identical(sort(sent$draws), c(1L, 1L, 2L, 2L))
  # Recorded in the run's trace under its label and counted by the governor.
  expect_identical(attr(b, "trace")$calls, 4L)
  tr <- attr(b, "traces")[[b$ledger_id[1]]]
  req <- Filter(function(s) !is.null(s$model), tr$steps)
  expect_identical(vapply(req, function(s) s$label, ""), "capital")
  # A failed request comes back as that request's failed result.
  down <- hr_mock_client(function(messages, params) stop("network down"))
  b2 <- quiet(suppressWarnings(hr_benchmark(arm, ref, runs = 1, client = down,
                                            scorer = hr_scorer_exact())))
  expect_false(got[["France 1"]]$ok)
  expect_match(got[["France 1"]]$error, "network down")
  expect_identical(b2$failure_kind, c("error", "error"))
})

test_that("a judge recorded at draw 0 replays when asked at a run's draw", {
  m <- draw_judge()
  rec <- hr_judge("Paris", m$client, mode = "grade", reference = "Paris", rubric = "r",
                  orders = 2)
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  hr_trace_save(rec$trace, path)
  tr <- hr_trace()
  tr$draw_index <- 1L
  tr$draw_scope <- "arm"
  again <- hr_judge("Paris", hr_replay_client(path), mode = "grade", reference = "Paris",
                    rubric = "r", orders = 2, trace = tr)
  expect_identical(again$verdicts$reason, rec$verdicts$reason)
  expect_identical(again$outcome, rec$outcome)
  expect_true(all(vapply(judge_steps(tr), function(s) isTRUE(s$cached), logical(1))))
})

test_that("a benchmark recorded before a run's trace carried its draw still replays", {
  m <- draw_judge()
  read_it <- function(item, client, trace) {
    ch <- gr_segment(item$document, list(method = "paragraph", max_tokens = 200), trace = trace)
    gr_read(ch, item$question, client, list(reader = "stuff"), trace = trace)
  }
  ref <- draw_reference()
  # record(r, scope) builds the benchmark trace a run of the arm made: with
  # the run's draw and the arm's scope when the arm set them on its trace, as
  # recipe arms did, or at draw 0 when it did not.
  record <- function(runs, drawn) {
    rec <- hr_trace()
    for (i in seq_along(ref$ids)) for (r in seq_len(runs)) {
      child <- hr_trace()
      if (drawn) {
        child$draw_index <- r
        child$draw_scope <- "stages"
      }
      quiet(read_it(ref$items[[i]], m$client, child))
      harnessr:::trace_absorb(rec, child)
    }
    path <- tempfile(fileext = ".json")
    hr_trace_save(rec, path)
    path
  }
  arm <- hr_arm("stages", function(item, ctx) read_it(item, ctx$client, ctx$trace))
  replay <- function(path, runs) {
    quiet(suppressWarnings(hr_benchmark(arm, ref, runs = runs, client = hr_replay_client(path),
                                        scorer = gr_scorer_answer())))
  }
  drawn <- record(2, TRUE)
  undrawn <- record(1, FALSE)
  on.exit(unlink(c(drawn, undrawn)), add = TRUE)
  b <- replay(drawn, 2)
  expect_identical(b$failure_kind[b$item == "revenue"], c(NA_character_, NA_character_))
  # A run recorded at draw 0 is answered with its reply (see replay_lookup()).
  b1 <- replay(undrawn, 1)
  expect_identical(b1$failure_kind[b1$item == "revenue"], NA_character_)
  expect_identical(b1$correct, b$correct[b$run == 1L])
})

test_that("a judge given a trace and a governor is held to both", {
  m <- draw_judge()
  # Alone, the judge's own governor would allow it; the run has one call left.
  run <- hr_trace(governor = hr_governor(max_calls = 1))
  res <- suppressWarnings(hr_judge("Paris", m$client, mode = "grade", reference = "Paris",
                                   rubric = "r", trace = run,
                                   governor = hr_governor(max_calls = 100)))
  expect_identical(m$n, 1L)
  expect_identical(run$calls, 1L)
  expect_length(run$refusals, 1L)
  expect_true(run$budget_stop)
  # The lower limit holds whichever governor sets it.
  run2 <- hr_trace(governor = hr_governor(max_calls = 100))
  invisible(suppressWarnings(hr_judge("Paris", m$client, mode = "grade", reference = "Paris",
                                      rubric = "r", trace = run2,
                                      governor = hr_governor(max_calls = 1))))
  expect_identical(run2$calls, 1L)
  expect_length(run2$refusals, 1L)
  # Models: only those both allow; unpriced models only when both allow them.
  g <- governor_tighter(hr_governor(allowed_models = c("a", "b"), allow_unpriced = TRUE),
                        hr_governor(allowed_models = c("b", "c"), max_cost_usd = 2))
  expect_identical(g$allowed_models, "b")
  expect_false(g$allow_unpriced)
  expect_identical(g$max_cost_usd, 2)
  expect_null(governor_tighter(NULL, NULL))
})

test_that("a judge with its own governor in a benchmark run stops at the benchmark's limit", {
  m <- draw_judge("Paris")
  ref <- hr_reference(list(q1 = "France", q2 = "Peru"), labels = c("Paris", "Lima"),
                      cluster = c("d1", "d2"), split = "test")
  arm <- hr_arm("a", function(item, ctx) {
    a <- ctx$call(item)$text
    hr_judge(a, ctx$client, mode = "grade", reference = "Paris", rubric = "r",
             trace = ctx$trace, governor = hr_governor(max_calls = 100))
    a
  })
  w <- character()
  b <- withCallingHandlers(
    hr_benchmark(arm, ref, runs = 1, client = m$client, scorer = hr_scorer_exact(),
                 governor = hr_governor(max_calls = 2)),
    warning = function(x) {
      w <<- c(w, class(x)[1])
      invokeRestart("muffleWarning")
    })
  expect_identical(attr(b, "trace")$calls, 2L)
  expect_identical(m$n, 2L)
  expect_identical(b$failure_kind, c("budget_stop", "budget_stop"))
  expect_true("hr_budget_stopped" %in% w)
})

test_that("a reader's pre-flight cap in a hand-written arm is a budget stop", {
  m <- draw_judge("Revenue was 45.2 million dollars [chunk 1].")
  arm <- hr_arm("doc_self", function(item, ctx) {
    answer_document(item$document, item$question, "fast", client = ctx$client,
                    trace = ctx$trace)
  })
  w <- character()
  b <- withCallingHandlers(
    hr_benchmark(arm, draw_reference(), runs = 1, client = m$client,
                 scorer = gr_scorer_answer(), governor = hr_governor(max_calls = 1)),
    warning = function(x) {
      w <<- c(w, paste(class(x)[1], conditionMessage(x)))
      invokeRestart("muffleWarning")
    })
  expect_identical(b$failure_kind[2], "budget_stop")
  expect_identical(b$usd[2], 0)
  stopped <- grep("^hr_budget_stopped", w, value = TRUE)
  expect_length(stopped, 1L)
  expect_match(stopped, "1 of 2 runs were stopped by the benchmark's limits (calls: 1)", fixed = TRUE)
  tr <- attr(b, "traces")[[b$ledger_id[2]]]
  notes <- Filter(function(s) identical(s$label, "budget.preflight"), tr$steps)
  expect_length(notes, 1L)
  expect_identical(notes[[1]]$detail$limit, "calls")
})
