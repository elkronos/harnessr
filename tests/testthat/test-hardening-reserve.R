# A reserve for the closing call: reserve_calls and reserve_usd hold part of
# max_calls and max_cost_usd back for requests marked closing.

reserve_client <- function() hr_mock_client(function(m, p) "ok")

test_that("a run that uses up its calls still gets its closing call under a reserve", {
  cl <- reserve_client()
  # Without a reserve the rounds take every call and the answer is refused.
  tr <- hr_trace(governor = hr_governor(max_calls = 3))
  rounds <- vapply(1:5, function(i) hr_call(cl, "round", trace = tr, label = "round")$ok,
                   logical(1))
  expect_identical(rounds, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_false(hr_call(cl, "answer", trace = tr, label = "final", closing = TRUE)$ok)
  expect_identical(tr$calls, 3L)
  # With one call held back the rounds stop a call earlier and the answer is
  # sent.
  tr <- hr_trace(governor = hr_governor(max_calls = 3, reserve_calls = 1))
  rounds <- vapply(1:5, function(i) hr_call(cl, "round", trace = tr, label = "round")$ok,
                   logical(1))
  expect_identical(rounds, c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_match(tr$refusals[[1]]$message, "with 1 kept for closing requests", fixed = TRUE)
  expect_identical(tr$refusals[[1]]$limit, "calls")
  fin <- hr_call(cl, "answer", trace = tr, label = "final", closing = TRUE)
  expect_true(fin$ok)
  expect_identical(tr$calls, 3L)
  # The reserve is spent: nothing more goes, closing or not.
  expect_false(hr_call(cl, "again", trace = tr, closing = TRUE)$ok)
})

test_that("an ordinary request cannot spend the dollar reserve", {
  local_registries()
  hr_register_model("reserve-priced-1", context_window = 128000, max_output = 4096,
                    input_usd = 100, output_usd = 100)
  cl <- reserve_client()
  one <- function(tr, closing = FALSE) {
    hr_call(cl, "hi", model = "reserve-priced-1", max_output = 50, trace = tr,
            closing = closing)
  }
  # Each request could cost about $0.006 at worst; $0.02 holds three.
  tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.02, reserve_usd = 0.01,
                                        max_calls = NULL))
  sent <- 0L
  while (one(tr)$ok) sent <- sent + 1L
  expect_identical(tr$stop_reason, "cost")
  expect_match(tr$refusals[[1]]$message, "kept for closing requests", fixed = TRUE)
  expect_lte(tr$spent_usd, 0.01)
  expect_true(one(tr, closing = TRUE)$ok)
  expect_lte(tr$spent_usd, 0.02)
  tr0 <- hr_trace(governor = hr_governor(max_cost_usd = 0.02, max_calls = NULL))
  sent0 <- 0L
  while (one(tr0)$ok) sent0 <- sent0 + 1L
  expect_gt(sent0, sent)
})

test_that("the iterative reader gets its final answer under a dollar reserve", {
  local_registries()
  hr_register_model("reserve-priced-2", context_window = 128000, max_output = 4096,
                    input_usd = 100, output_usd = 100)
  n <- 0
  cl <- hr_mock_client(function(m, p) {
    if (identical(p$schema_name, "iterative_step")) {
      n <<- n + 1
      sprintf('{"can_answer": false, "answer": "", "next_query": "revenue detail %d"}', n)
    } else "Revenue was 45.2 million dollars."
  })
  run <- function(reserve) {
    n <<- 0
    tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.14, reserve_usd = reserve,
                                          max_calls = NULL))
    a <- suppressWarnings(suppressMessages(answer_document(
      gr_example(), "What was revenue?",
      list(segment = list(method = "paragraph", max_tokens = 60),
           read = list(reader = "iterative", max_rounds = 6, max_answer_tokens = 200,
                       top_k = 1, model = "reserve-priced-2")),
      client = cl, trace = tr)))
    list(answer = a$answer,
         final = any(vapply(tr$steps, function(s) identical(s$label, "iterative.final"),
                            logical(1))),
         refused = vapply(tr$refusals, function(r) r$label, ""))
  }
  without <- run(0)
  expect_false(without$final)
  expect_true("iterative.final" %in% without$refused)
  expect_identical(without$answer, "NOT_IN_DOCUMENT")
  with <- run(0.05)
  expect_true(with$final)
  expect_false("iterative.final" %in% with$refused)
  expect_identical(with$answer, "Revenue was 45.2 million dollars.")
})

test_that("the readers mark their closing requests and nothing else", {
  real <- governor_check
  log <- list()
  local_mocked_bindings(governor_check = function(trace, request, stage = "both") {
    if (stage %in% c("call", "both")) {
      log[[length(log) + 1L]] <<- c(label = as.character(request$label),
                                   closing = as.character(isTRUE(request$closing)))
    }
    real(trace, request, stage)
  })
  cl <- hr_mock_client(function(m, p) {
    if (identical(p$schema_name, "iterative_step")) {
      '{"can_answer": false, "answer": "", "next_query": "revenue"}'
    } else if (any(grepl("REPLACE", vapply(m, function(x) x$content, ""), fixed = TRUE))) {
      "ADD: Revenue was 45.2 million dollars."
    } else "Revenue was 45.2 million dollars."
  })
  closing_labels <- function(reader, ...) {
    log <<- list()
    suppressWarnings(suppressMessages(answer_document(
      gr_example(), "What was revenue?",
      list(segment = list(method = "paragraph", max_tokens = 60),
           read = list(reader = reader, ...)), client = cl)))
    m <- do.call(rbind, log)
    list(closing = unique(m[m[, "closing"] == "TRUE", "label"]),
         ordinary = unique(m[m[, "closing"] == "FALSE", "label"]))
  }
  expect_identical(closing_labels("map_reduce")$closing, "reduce")
  expect_identical(closing_labels("hierarchical")$closing, "hier.answer")
  expect_identical(closing_labels("refine", refine_state = "ledger")$closing,
                   "refine.answer")
  # Without a ledger the last revision is the answer, and no request closes.
  expect_identical(closing_labels("refine")$closing, character(0))
  expect_identical(closing_labels("skim")$closing, "skim.answer")
  expect_identical(closing_labels("rerank")$closing, "rerank.answer")
  expect_identical(closing_labels("stuff")$closing, character(0))
  expect_identical(closing_labels("retrieve")$closing, character(0))
  expect_true("ensemble.adjudicate" %in% closing_labels("ensemble")$closing)
  expect_identical(closing_labels("preview")$closing, "preview.answer")
  it <- closing_labels("iterative")
  expect_identical(it$closing, "iterative.final")
  expect_true("iterative.step" %in% it$ordinary)
})

test_that("closing changes no request, step or key", {
  got <- list()
  cl <- hr_mock_client(function(m, p) { got[[length(got) + 1L]] <<- p; "ok" })
  a <- hr_trace()
  b <- hr_trace()
  hr_call(cl, "hi", trace = a)
  hr_call(cl, "hi", trace = b, closing = TRUE)
  expect_identical(got[[1]], got[[2]])
  strip <- function(st) st[setdiff(names(st), c("at", "started_utc", "ended_utc", "seconds"))]
  expect_identical(strip(a$steps[[1]]), strip(b$steps[[1]]))
  expect_error(hr_call(cl, "hi", closing = NA), class = "gr_bad_setting")
})

test_that("a governor without a reserve is what it was", {
  g <- hr_governor(max_calls = 5)
  expect_named(unclass(g), c("max_calls", "max_cost_usd", "max_tokens_total",
                             "max_output_tokens", "allowed_models", "allow_unpriced"))
  expect_false(any(grepl("reserve", capture.output(print(g)))))
  g <- hr_governor(max_calls = 5, reserve_calls = 2, reserve_usd = 1)
  expect_identical(g$reserve_calls, 2)
  expect_identical(g$reserve_usd, 1)
  expect_true(any(grepl("reserve_calls: +2", capture.output(print(g)))))
  tr <- hr_trace()
  expect_null(hr_options()$reserve_calls_unused)
  expect_false("reserve_calls" %in% names(tr$config$options))
})

test_that("a reserve larger than its limit is refused", {
  expect_error(hr_governor(max_calls = 2, reserve_calls = 3), class = "hr_bad_reserve")
  expect_error(hr_governor(max_cost_usd = 1, reserve_usd = 2), class = "hr_bad_reserve")
  expect_error(hr_governor(max_calls = 2, reserve_calls = 3), class = "gr_bad_setting")
  expect_silent(hr_governor(max_calls = 2, reserve_calls = 2))
  # No limit to hold it back from: accepted, and it holds nothing.
  g <- hr_governor(max_calls = NULL, reserve_calls = 3)
  tr <- hr_trace(governor = g)
  expect_true(hr_call(reserve_client(), "hi", trace = tr)$ok)
  expect_error(hr_governor(reserve_calls = -1), class = "gr_bad_option")
  expect_error(hr_governor(reserve_usd = NA), class = "gr_bad_option")
  expect_error(hr_governor(reserve_usd = Inf), class = "gr_bad_option")
  expect_error(hr_options(reserve_calls = "x"), class = "gr_bad_option")
})

test_that("the reserve options reach a trace without a governor", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  hr_options(max_calls = 2, reserve_calls = 1)
  tr <- hr_trace()
  cl <- reserve_client()
  expect_true(hr_call(cl, "a", trace = tr)$ok)
  expect_false(hr_call(cl, "b", trace = tr)$ok)
  expect_true(hr_call(cl, "c", trace = tr, closing = TRUE)$ok)
  # Recorded in the trace's options snapshot only when set.
  expect_identical(tr$config$options$reserve_calls, 1)
})

test_that("a parallel batch's shares leave the reserve alone", {
  local_registries()
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  hr_options(reserve_calls = 3)
  tr <- hr_trace(governor = hr_governor(max_calls = 10, reserve_calls = 4))
  share <- batch_share(tr, 3L)
  expect_identical(share$max_calls, 2)
  expect_null(share$reserve_calls)
  expect_identical(batch_shortfall(tr, 6L), NULL)
  expect_identical(batch_shortfall(tr, 7L), "call cap")
  hr_register_model("reserve-priced-3", context_window = 128000, max_output = 4096,
                    input_usd = 1, output_usd = 1)
  tr <- hr_trace(governor = hr_governor(max_cost_usd = 1, reserve_usd = 0.4))
  expect_equal(batch_share(tr, 2L)$max_cost_usd, 0.3)
  expect_identical(governor_headroom(tr, closing = TRUE)$usd, 1)
})

test_that("combined governors hold ordinary and closing requests to the tighter limit", {
  a <- hr_governor(max_calls = 10, reserve_calls = 2, max_cost_usd = NULL)
  b <- hr_governor(max_calls = 9, max_cost_usd = NULL)
  g <- governor_tighter(a, b)
  # Ordinary: min(10 - 2, 9) = 8. Closing: min(10, 9) = 9.
  expect_identical(g$max_calls, 9)
  expect_identical(g$reserve_calls, 1)
  g <- governor_tighter(b, a)
  expect_identical(g$max_calls, 9)
  expect_identical(g$reserve_calls, 1)
  # A reserve that the other limit already covers holds nothing more.
  g <- governor_tighter(hr_governor(max_calls = 10, reserve_calls = 1),
                        hr_governor(max_calls = 5))
  expect_identical(g$max_calls, 5)
  expect_null(g$reserve_calls)
  u <- governor_tighter(hr_governor(max_cost_usd = 2, reserve_usd = 1),
                        hr_governor(max_cost_usd = 3, reserve_usd = 0.5))
  expect_identical(u$max_cost_usd, 2)
  expect_identical(u$reserve_usd, 1)
  # A stage's own trace keeps the parent's reserve.
  parent <- hr_trace(governor = hr_governor(max_calls = 5, reserve_calls = 1))
  cl <- reserve_client()
  hr_call(cl, "x", trace = parent)
  f <- fork_governor(parent)
  expect_identical(f$max_calls, 4)
  expect_identical(f$reserve_calls, 1)
})

test_that("hr_options() refuses a reserve larger than its limit and keeps the old values", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  hr_options(max_calls = 5, max_cost_usd = 1)
  expect_error(hr_options(reserve_calls = 6), class = "hr_bad_reserve")
  expect_error(hr_options(reserve_usd = 2), class = "gr_bad_option")
  expect_equal(hr_options("reserve_calls"), 0)
  expect_identical(hr_options("reserve_usd"), 0)
  # Checked once every setting of the call is in, so the order does not matter.
  hr_options(reserve_calls = 8, max_calls = 10)
  expect_identical(hr_options("reserve_calls"), 8)
  expect_error(hr_options(max_calls = 7), class = "hr_bad_reserve")
  expect_identical(hr_options("max_calls"), 10)
  # No limit holds no reserve, so any reserve passes.
  hr_options(max_cost_usd = NULL, reserve_usd = 50)
  expect_identical(hr_options("reserve_usd"), 50)
})
