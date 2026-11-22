# test-bench-ctx.R: the judge and note shortcuts an arm's ctx carries, and
# hr_signals() given a benchmark.

ctx_reference <- function() {
  gr_qa_reference(questions = c(revenue = "What was revenue in 2024?",
                                units = "How many units did Sheffield produce?"),
                  documents = gr_example(), answers = list("45.2 million", "12,400"),
                  split = "test")
}

# A client that grades with a verdict that changes from call to call, so a
# cache that handed every run one stored verdict would show.
ctx_client <- function(answer = "Revenue was 45.2 million dollars.") {
  env <- new.env()
  env$n <- 0L
  env$sent <- list()
  env$client <- gr_mock_client(function(messages, params) {
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

ctx_judge_steps <- function(trace) {
  Filter(function(s) startsWith(as.character(s$label %||% ""), "judge.") && !is.null(s$model),
         trace$steps)
}

test_that("ctx carries judge and note next to the shortcuts it had", {
  got <- NULL
  arm <- hr_arm("look", function(item, ctx) {
    got <<- ctx
    "x"
  })
  ref <- hr_reference(list(q1 = "a"), "x", "a", split = "test")
  quiet(hr_benchmark(arm, ref, runs = 1, client = gr_mock_client(function(m, p) "x")))
  expect_identical(names(got), c("client", "trace", "governor", "draw_index", "item_id",
                                 "arm", "run", "params", "call", "call_json", "judge",
                                 "note"))
  expect_true(is.function(got$judge))
  expect_identical(names(formals(got$note)), c("name", "value", "refs"))
})

test_that("ctx$judge is in the run's usd once and carries the run's draw", {
  gr_register_model("bench-ctx-priced", context_window = 128000L, max_output = 4096L,
                    input_usd = 2, output_usd = 8)
  m <- ctx_client()
  own <- new.env()
  arm <- hr_arm("judged", function(item, ctx) {
    ans <- ctx$call(item$question, model = "bench-ctx-priced", label = "answer")
    j <- ctx$judge(ans$text, mode = "grade", reference = "45.2 million",
                   model = "bench-ctx-priced", rubric = "Does it give the figure?")
    own[[sprintf("%s %d", ctx$item_id, ctx$run)]] <- j
    ans$text
  })
  b <- quiet(hr_benchmark(arm, ctx_reference(), runs = 2, client = m$client,
                          scorer = gr_scorer_answer(),
                          governor = hr_governor(max_calls = 20)))
  expect_identical(nrow(b), 4L)
  traces <- attr(b, "traces")
  for (i in seq_len(nrow(b))) {
    tr <- traces[[b$ledger_id[i]]]
    j <- own[[sprintf("%s %d", b$item[i], b$run[i])]]
    js <- ctx_judge_steps(tr)
    expect_length(js, 2L)
    expect_true(all(vapply(js, function(s) identical(as.integer(s$params$draw_index),
                                                     b$run[i]), logical(1))))
    expect_true(all(vapply(js, function(s) identical(s$draw_scope, "judged"), logical(1))))
    # The run's usd is its answer plus its judge, the judge counted once.
    expect_gt(j$judge_cost$usd, 0)
    answer <- Filter(function(s) identical(s$label, "answer"), tr$steps)
    expect_length(answer, 1L)
    answer_usd <- sum(gr_trace_cost(tr)$usd) - j$judge_cost$usd
    expect_gt(answer_usd, 0)
    expect_equal(b$usd[i], answer_usd + j$judge_cost$usd)
    expect_equal(b$usd[i], sum(gr_trace_cost(tr)$usd))
  }
  # Three requests a run, all counted by the benchmark's governor.
  expect_identical(attr(b, "trace")$calls, 12L)
  # Every judge request went out at its run's draw index.
  judge_draws <- vapply(Filter(function(s) grepl("You grade one response",
                                                 s$messages[[1]]$content, fixed = TRUE),
                               m$sent), function(s) as.integer(s$params$draw_index), 1L)
  expect_identical(sort(judge_draws), rep(1:2, each = 4L))
})

test_that("ctx$judge under a cache gives each run its own verdict", {
  m <- ctx_client()
  cached <- gr_cache_client(m$client, gr_cache(tempfile("bench-ctx-")))
  verdicts <- new.env()
  arm <- hr_arm("cached", function(item, ctx) {
    j <- ctx$judge("45.2 million", mode = "grade", reference = "45.2 million",
                   rubric = "Same figure?", orders = 1)
    verdicts[[sprintf("%s %d", ctx$item_id, ctx$run)]] <- j$verdicts$reason
    "45.2 million"
  })
  quiet(hr_benchmark(arm, ctx_reference(), runs = 2, client = cached,
                     scorer = gr_scorer_answer()))
  expect_false(identical(verdicts[["revenue 1"]], verdicts[["revenue 2"]]))
})

test_that("ctx$judge needs a rubric, as hr_judge() does", {
  m <- ctx_client()
  arm <- hr_arm("norubric", function(item, ctx) {
    ctx$judge("45.2 million", mode = "grade", reference = "45.2 million")
    "45.2 million"
  })
  b <- quiet(hr_benchmark(arm, ctx_reference(), runs = 1, client = m$client,
                          scorer = gr_scorer_answer()))
  expect_identical(b$failure_kind, c("error", "error"))
  expect_identical(m$n, 0L)
})

test_that("ctx$note records a signal on the run's trace about the item", {
  arm <- hr_arm("noted", function(item, ctx) {
    ctx$note("demo.sure", ctx$run > 1)
    ctx$note("demo.score", c(0.25, 0.75), refs = list(part = 1:2))
    "45.2 million"
  })
  sent <- 0L
  cl <- gr_mock_client(function(m, p) {
    sent <<- sent + 1L
    "x"
  })
  b <- quiet(hr_benchmark(arm, ctx_reference(), runs = 2, client = cl,
                          scorer = gr_scorer_answer()))
  # A note sends nothing.
  expect_identical(sent, 0L)
  expect_identical(attr(b, "trace")$calls, 0L)
  tr <- attr(b, "traces")[[b$ledger_id[1]]]
  s <- hr_signals(tr)
  expect_identical(s$signal, c("demo.sure", "demo.score", "demo.score"))
  expect_identical(s$item_id, rep(b$item[1], 3L))
  expect_identical(s$score, c(0, 0.25, 0.75))
  expect_identical(s$refs, c(NA, '{"part":1}', '{"part":2}'))
})

test_that("hr_signals() reads a benchmark once per run, with arm, run and item", {
  noted <- hr_arm("noted", function(item, ctx) {
    ctx$note("demo.sure", ctx$run == 1)
    "45.2 million"
  })
  plain <- hr_arm("plain", function(item, ctx) "12,400")
  b <- quiet(hr_benchmark(list(noted, plain), ctx_reference(), runs = 2,
                          client = gr_mock_client(function(m, p) "x"),
                          scorer = gr_scorer_answer()))
  s <- hr_signals(b)
  expect_identical(names(s)[1:4], c("run_id", "arm", "run", "item"))
  expect_identical(setdiff(names(s), c("arm", "run", "item")),
                   names(hr_signals(gr_trace())))
  # One row per note: two items by two runs of the arm that notes. The
  # benchmark's own trace holds the same steps and is not read again.
  expect_identical(nrow(s), 4L)
  expect_false(anyDuplicated(s[, c("arm", "run", "item", "step", "index")]) > 0L)
  expect_identical(unique(s$arm), "noted")
  expect_identical(s$item, s$item_id)
  expect_setequal(paste(s$item, s$run), c("revenue 1", "revenue 2", "units 1", "units 2"))
  expect_identical(s$score, ifelse(s$run == 1L, 1, 0))
  key <- match(s$run_id, b$ledger_id)
  expect_false(anyNA(key))
  expect_identical(s$arm, b$arm[key])
  expect_identical(s$run, b$run[key])
  expect_identical(s$item, b$item[key])
  # The folded trace holds the same signals, which a direct read would double.
  folded <- hr_signals(attr(b, "trace"))
  expect_identical(nrow(folded), 4L)
  # name filters as it does for a trace.
  expect_identical(nrow(hr_signals(b, "nothing")), 0L)
  expect_identical(names(hr_signals(b, "nothing")), names(s))
  # A benchmark subset to some rows lists the signals of those runs.
  sub <- b[b$run == 2L, ]
  expect_identical(hr_signals(sub)$run, c(2L, 2L))
  # A benchmark that lost its traces says so.
  bare <- b
  attr(bare, "traces") <- NULL
  expect_error(hr_signals(bare), class = "gr_bad_trace")
})

test_that("hr_signals() of a benchmark includes the signals a reader recorded", {
  cl <- gr_mock_client(function(m, p) {
    '{"can_answer": true, "answer": "45.2 million dollars", "next_query": ""}'
  })
  arm <- hr_arm("iter", function(item, ctx) {
    ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150),
                     trace = ctx$trace)
    gr_read(ch, item$question, ctx$client, "iterative", trace = ctx$trace)$answer
  })
  b <- quiet(hr_benchmark(arm, ctx_reference(), runs = 1, client = cl,
                          scorer = gr_scorer_answer()))
  s <- hr_signals(b, "gr.iterative.can_answer")
  expect_gt(nrow(s), 0L)
  expect_setequal(unique(s$item), b$item)
  expect_identical(s$arm, rep("iter", nrow(s)))
})

test_that("an arm that uses neither judge nor note sends the requests it sent before", {
  # digest and jsonlite, which the golden records need, are imported.
  runs <- golden_compose_runs()
  for (nm in names(runs)) {
    path <- file.path(golden_dir(), paste0(nm, ".json"))
    expect_true(file.exists(path))
    now <- golden_roundtrip(runs[[nm]]())
    d <- golden_diff(golden_read(path), now, path = nm)
    expect(length(d) == 0L, paste(c(sprintf("%s changed:", nm), utils::head(d, 10)),
                                  collapse = "\n"))
  }
})
