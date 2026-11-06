# test-core-governor.R: the limits every request is checked against before it
# is sent (hr_governor()).
#
# The limits used to be the readers' to check, with trace_can_call() before a
# call. That compared what the run had spent with the limit, knew nothing of
# the call about to go out, and so let a run pass the limit by one request; a
# call made by code that did not ask was not limited at all; and a model with
# no price added nothing to the spend, so the spending limit never fired.

# A model whose reply tokens cost a tenth of a cent each, so a request's worst
# case is set by its output cap: 4 tokens is $0.004 plus the prompt.
gov_model <- function(env = parent.frame()) {
  local_registries(env)
  gr_register_model("gov-priced", context_window = 100000, max_output = 4000,
                    input_usd = 1, output_usd = 1000)
  "gov-priced"
}

# Stands in for an OpenAI-shaped chat server and keeps every body it is sent.
gov_endpoint <- function(env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  seen$bodies <- list()
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) {
      seen$bodies <- c(seen$bodies, list(body))
      out <- list(id = "chatcmpl_1", object = "chat.completion", model = body$model,
                  choices = list(list(index = 0, finish_reason = "stop",
                                      message = list(role = "assistant", content = "ok"))),
                  usage = list(prompt_tokens = 10L, completion_tokens = 1L))
      structure(list(url = url, status_code = 200L,
                     headers = structure(list(`content-type` = "application/json"),
                                         class = c("insensitive", "list")),
                     content = charToRaw(as.character(jsonlite::toJSON(out, auto_unbox = TRUE)))),
                class = "response")
    },
    .package = "httr", .env = env)
  seen
}

gov_client <- function() {
  gr_client(api_key = "sk-test", base_url = "https://governor.invalid/v1", api = "chat",
            model = "gov-priced", max_retries = 0L)
}

test_that("a request that would cross max_cost_usd is refused before it leaves", {
  model <- gov_model()
  seen <- gov_endpoint()
  cl <- gov_client()
  tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.010))
  tr$spent_usd <- 0.007

  # Its worst case is the prompt plus 4 reply tokens, about $0.004: with $0.007
  # spent, that would pass $0.010, so nothing is sent.
  res <- NULL
  expect_condition(res <- gr_call(cl, "hi", max_output = 4L, trace = tr),
                   class = "hr_budget_refused")
  expect_length(seen$bodies, 0L)
  expect_false(res$ok)
  expect_true(res$refused)
  expect_match(res$error, "spending limit reached", fixed = TRUE)
  expect_identical(tr$calls, 0L)
  expect_length(tr$steps, 0L)
  expect_true(tr$budget_stop)
  expect_identical(tr$stop_reason, "cost")
  expect_length(tr$refusals, 1L)
  expect_identical(tr$refusals[[1]]$limit, "cost")
  expect_gt(tr$refusals[[1]]$worst_usd + 0.007, 0.010)

  # One whose worst case fits is sent.
  ok <- gr_call(cl, "hi", max_output = 2L, trace = tr)
  expect_true(ok$ok)
  expect_length(seen$bodies, 1L)
  expect_identical(tr$calls, 1L)
  expect_lte(tr$spent_usd, 0.010)

  # A mock's handler is not called for a refused request either.
  mock <- gr_mock_client(function(m, p) "never")
  tr2 <- gr_trace(governor = hr_governor(max_cost_usd = 0.010))
  tr2$spent_usd <- 0.007
  quiet(gr_call(mock, "hi", model = model, max_output = 4L, trace = tr2))
  expect_length(mock$calls(), 0L)
})

test_that("no run passes the spending limit, and the last request is refused, not sent", {
  model <- gov_model()
  cl <- gr_mock_client(function(m, p) paste(rep("word", 3), collapse = " "))
  tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.05))
  for (i in 1:40) quiet(gr_call(cl, "hi", model = model, max_output = 5L, trace = tr))
  expect_lte(tr$spent_usd, 0.05)
  expect_gt(tr$calls, 0L)
  expect_lt(tr$calls, 40L)
  # Every request after the first refusal was refused too, each before it left.
  expect_identical(tr$calls + length(tr$refusals), 40L)
  expect_identical(length(cl$calls()), tr$calls)
})

test_that("a module that never checks the limits is still stopped", {
  model <- gov_model()
  gr_register_reader("unchecked", signature = "some|N|none", cost_calls = "N",
    fn = function(chunks, question, client, spec, trace) {
      for (i in 1:10) gr_call(client, "more", model = spec$model, trace = trace,
                              label = "unchecked")
      new_answer("done", "unchecked", question, chunks$chunks$chunk_id, trace)
    })
  ch <- quiet(gr_segment("One short paragraph.", list(method = "paragraph")))
  gr_options(max_calls = 3)
  cl <- mock_echo()
  tr <- gr_trace()
  a <- quiet(gr_read(ch, "Q?", cl, list(reader = "unchecked", model = model), trace = tr))
  expect_length(cl$calls(), 3L)
  expect_identical(tr$calls, 3L)
  expect_true(a$partial)
  expect_equal(a$notes$call_cap_reached, 3)
})

test_that("judge and adjudication calls count against max_calls", {
  model <- gov_model()
  cl <- mock_echo("An answer.")
  # A judge made by a script through gr_call() is held to the run's cap like
  # any other request.
  tr <- gr_trace(governor = hr_governor(max_calls = 2))
  quiet(gr_call(cl, "answer", model = model, trace = tr, label = "answer"))
  quiet(gr_call(cl, "answer", model = model, trace = tr, label = "answer"))
  judge <- quiet(gr_call(cl, "judge it", model = model, trace = tr, label = "judge"))
  expect_true(judge$refused)
  expect_identical(tr$refusals[[1]]$label, "judge")
  expect_identical(tr$calls, 2L)

  # The ensemble's adjudication is a request like the members' own. Each
  # member's reply costs about $0.009 and could cost $0.016 at its cap, so
  # under $0.03 both members are sent and the adjudication, with about $0.019
  # spent, is not. (The reply stays under its cap, as a provider's does.)
  ch <- quiet(gr_segment(sample_doc(2, 2), list(method = "paragraph", max_tokens = 200)))
  wordy <- mock_echo("The answer is in the second paragraph.")
  gr_options(max_cost_usd = 0.03)
  tr2 <- gr_trace()
  a <- quiet(gr_read(ch, "Q?", wordy, list(reader = "ensemble", members = c("stuff", "retrieve"),
                                           model = model, max_answer_tokens = 16L), trace = tr2))
  labels <- vapply(Filter(function(s) !identical(s$kind, "local"), tr2$steps),
                   function(s) s$label, character(1))
  expect_true(all(c("stuff.answer", "retrieve.answer") %in% labels))
  expect_false("ensemble.adjudicate" %in% labels)
  expect_identical(tr2$refusals[[1]]$label, "ensemble.adjudicate")
  expect_lte(tr2$spent_usd, 0.03)
  expect_true(a$partial)
})

test_that("an unpriced model is refused unless allow_unpriced = TRUE", {
  local_registries()
  gr_register_model("gov-unpriced", context_window = 100000, max_output = 4000)
  n <- 0L
  cl <- gr_backend_client(function(m, p) { n <<- n + 1L; "sent" }, model = "gov-unpriced")
  tr <- gr_trace()
  res <- NULL
  expect_condition(res <- gr_call(cl, "hi", trace = tr), class = "hr_unpriced_model")
  expect_true(res$refused)
  expect_match(res$error, "allow_unpriced = TRUE", fixed = TRUE)
  expect_identical(n, 0L)
  expect_identical(tr$stop_reason, "unpriced")

  # A whole read is stopped before its first request.
  ch <- quiet(gr_segment(sample_doc(2, 2), list(method = "paragraph", max_tokens = 200)))
  expect_error(quiet(gr_read(ch, "Q?", cl, "stuff")), class = "hr_unpriced_model")
  expect_identical(n, 0L)

  # Allowed, it is sent, and its cost is unknown rather than zero.
  gr_options(allow_unpriced = TRUE)
  tr2 <- gr_trace()
  expect_true(gr_call(cl, "hi", trace = tr2)$ok)
  expect_identical(n, 1L)
  expect_true(is.na(gr_trace_cost(tr2)$usd[1]))
  expect_identical(tr2$spent_usd, 0)
  gr_options(allow_unpriced = FALSE)
  # The same on the run's governor.
  tr3 <- gr_trace(governor = hr_governor(allow_unpriced = TRUE))
  expect_true(gr_call(cl, "hi", trace = tr3)$ok)
  # With no spending limit there is nothing to hold it to.
  tr4 <- gr_trace(governor = hr_governor(max_cost_usd = NULL))
  expect_true(gr_call(cl, "hi", trace = tr4)$ok)
  # A mock sends nothing anyone pays for.
  mock <- gr_mock_client(function(m, p) "ok")
  expect_true(gr_call(mock, "hi", model = "gov-unpriced", trace = gr_trace())$ok)
})

test_that("the output ceiling and the allowed models refuse a request", {
  model <- gov_model()
  cl <- gr_mock_client(function(m, p) "ok")
  tr <- gr_trace(governor = hr_governor(max_output_tokens = 100))
  big <- quiet(gr_call(cl, "hi", model = model, max_output = 500L, trace = tr))
  expect_true(big$refused)
  expect_identical(tr$stop_reason, "output")
  expect_true(gr_call(cl, "hi", model = model, max_output = 100L, trace = tr)$ok)
  expect_identical(tr$calls, 1L)

  tr2 <- gr_trace(governor = hr_governor(allowed_models = "mock-model"))
  expect_true(gr_call(cl, "hi", trace = tr2)$ok)
  other <- NULL
  expect_condition(other <- gr_call(cl, "hi", model = model, trace = tr2),
                   class = "hr_model_not_allowed")
  expect_true(other$refused)
  expect_identical(tr2$stop_reason, "model")
  expect_length(cl$calls(), 2L)
})

test_that("a request a cache answers spends nothing and is not held to the spending limit", {
  model <- gov_model()
  local_clean_cache()
  n <- 0L
  cl <- gr_cache_client(gr_mock_client(function(m, p) { n <<- n + 1L; "cached reply" }),
                        gr_cache(withr::local_tempdir()))
  expect_true(gr_call(cl, "hi", model = model, max_output = 4L)$ok)
  tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.001))
  hit <- gr_call(cl, "hi", model = model, max_output = 4L, trace = tr)
  expect_true(hit$ok)
  expect_true(hit$cached)
  expect_identical(n, 1L)
  # A new request is checked as it leaves.
  miss <- quiet(gr_call(cl, "something else", model = model, max_output = 4L, trace = tr))
  expect_true(miss$refused)
  expect_identical(n, 1L)
})

test_that("an embeddings request is held to the same limits", {
  local_registries()
  seen <- new.env(parent = emptyenv())
  seen$n <- 0L
  testthat::local_mocked_bindings(
    POST = function(url, ...) { seen$n <- seen$n + 1L; stop("should not be sent") },
    .package = "httr")
  cl <- gr_client(api_key = "sk-test", base_url = "https://governor.invalid/v1", max_retries = 0L)
  tr <- gr_trace(governor = hr_governor(max_calls = 0))
  emb <- quiet(gr_embed(cl, c("alpha", "beta"), trace = tr, cache = FALSE))
  expect_identical(seen$n, 0L)
  expect_true(isTRUE(attr(emb, "embedding_fallback")))
  expect_identical(tr$refusals[[1]]$label, "embed.request")
  expect_identical(tr$stop_reason, "calls")
})

test_that("a parallel batch never passes the run's limits", {
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")
  model <- gov_model()
  gr_options(workers = 2)
  cl <- gr_mock_client(function(m, p) "ok")
  item <- function(i, trace) gr_call(cl, paste("item", i), model = model, max_output = 4L,
                                     trace = trace)$ok
  # Shares of $0.02 over 8 items are too small for any item's worst case, so
  # the workers send nothing, and the items run again here against the run.
  tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.02))
  out <- quiet(harnessr:::gr_lapply(1:8, item, parallel = TRUE, workers = 2, trace = tr,
                                    client = cl))
  expect_lte(tr$spent_usd, 0.02)
  expect_gt(tr$calls, 0L)
  expect_identical(sum(unlist(out)), tr$calls)
  expect_true(all(vapply(tr$refusals, function(r) r$spent_usd + r$worst_usd > 0.02,
                         logical(1))))

  # Room for all of them: sent from the workers, within the limit.
  tr2 <- gr_trace(governor = hr_governor(max_cost_usd = 1))
  out2 <- quiet(harnessr:::gr_lapply(1:8, item, parallel = TRUE, workers = 2, trace = tr2,
                                     client = cl))
  expect_true(all(unlist(out2)))
  expect_identical(tr2$calls, 8L)
  expect_lte(tr2$spent_usd, 1)

  # A batch bigger than the calls left runs here, and stops at the cap.
  tr3 <- gr_trace(governor = hr_governor(max_calls = 5))
  out3 <- quiet(harnessr:::gr_lapply(1:8, item, parallel = TRUE, workers = 2, trace = tr3,
                                     client = cl))
  expect_identical(tr3$calls, 5L)
  expect_identical(sum(unlist(out3)), 5L)
})

test_that("each item of a batch gets an equal share of what is left", {
  model <- gov_model()
  tr <- gr_trace(governor = hr_governor(max_calls = 10, max_cost_usd = 1,
                                        allowed_models = model))
  tr$calls <- 2L
  tr$spent_usd <- 0.2
  share <- harnessr:::batch_share(tr, 4)
  expect_s3_class(share, "hr_governor")
  expect_identical(share$max_calls, 2)
  expect_equal(share$max_cost_usd, 0.2)
  expect_identical(share$allowed_models, model)
  expect_null(harnessr:::batch_share(NULL, 4))
})

test_that("a trace says what was refused, and which governor held it", {
  model <- gov_model()
  cl <- gr_mock_client(function(m, p) "ok")
  plain <- gr_trace()
  gr_call(cl, "hi", trace = plain)
  js <- jsonlite::fromJSON(as_json(plain), simplifyVector = FALSE)
  expect_null(js$refusals)
  expect_null(js$governor)

  tr <- gr_trace(governor = hr_governor(max_calls = 0))
  quiet(gr_call(cl, "hi", trace = tr))
  js <- jsonlite::fromJSON(as_json(tr), simplifyVector = FALSE)
  expect_identical(js$refusals[[1]]$limit, "calls")
  expect_identical(js$governor$max_calls, 0L)
  expect_true(js$budget_stop)

  # One allowed model is written as an array, as two are.
  one <- gr_trace(governor = hr_governor(allowed_models = "gpt-4o"))
  expect_match(as.character(as_json(one)), '"allowed_models": ["gpt-4o"]', fixed = TRUE)
  js <- jsonlite::fromJSON(as_json(one), simplifyVector = FALSE)
  expect_identical(js$governor$allowed_models, list("gpt-4o"))
})

test_that("a governor checks its limits as the options do", {
  local_registries()
  expect_error(hr_governor(max_cost_usd = NA), class = "gr_bad_option")
  expect_error(hr_governor(max_calls = -1), class = "gr_bad_option")
  expect_error(hr_governor(max_output_tokens = 0), class = "gr_bad_option")
  expect_error(hr_governor(allowed_models = 3), class = "gr_bad_option")
  expect_error(hr_governor(allow_unpriced = NA), class = "gr_bad_option")
  expect_error(gr_trace(governor = list(max_calls = 1)), class = "gr_bad_setting")
  gr_options(max_calls = 7, allowed_models = c("a", "b"))
  g <- hr_governor()
  expect_identical(g$max_calls, 7)
  expect_identical(g$allowed_models, c("a", "b"))
  expect_output(print(g), "max_calls:         7", fixed = TRUE)
})

test_that("the worst case covers the prompt a provider bills, not only the text counted", {
  local_registries()
  # Prompt tokens as dear as reply tokens, so the prompt's framing matters.
  gr_register_model("gov-dear", context_window = 100000, max_output = 4000,
                    input_usd = 1000, output_usd = 1000)
  seen <- new.env(parent = emptyenv())
  seen$n <- 0L
  # Reports what an OpenAI chat server bills: the text, 3 tokens of framing per
  # message and 3 to prime the reply, and a reply at its cap.
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) {
      seen$n <- seen$n + 1L
      text <- vapply(body$messages, function(m) m$content, character(1))
      billed <- sum(gr_count_tokens(text)) + 3L * length(text) + 3L
      cap <- body$max_completion_tokens %||% body$max_tokens
      out <- list(id = "chatcmpl_1", object = "chat.completion", model = body$model,
                  choices = list(list(index = 0, finish_reason = "length",
                                      message = list(role = "assistant", content = "ok ok"))),
                  usage = list(prompt_tokens = billed, completion_tokens = cap))
      structure(list(url = url, status_code = 200L,
                     headers = structure(list(`content-type` = "application/json"),
                                         class = c("insensitive", "list")),
                     content = charToRaw(as.character(jsonlite::toJSON(out, auto_unbox = TRUE)))),
                class = "response")
    },
    .package = "httr")
  cl <- gr_client(api_key = "sk-test", base_url = "https://governor.invalid/v1", api = "chat",
                  model = "gov-dear", max_retries = 0L)
  tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.2))
  for (i in 1:20) quiet(gr_call(cl, "hi there", max_output = 2L, trace = tr))
  expect_gt(seen$n, 0L)
  expect_lt(seen$n, 20L)
  expect_lte(tr$spent_usd, 0.2)

  # A schema is billed as part of the prompt, so it is counted in the worst case.
  schema <- list(type = "object", properties = list(answer = list(type = "string")),
                 required = list("answer"), additionalProperties = FALSE)
  req <- list(messages = list(list(role = "user", content = "hi")), model = "gov-dear",
              params = list(prompt_tokens = 1L), schema = schema, schema_name = "result")
  plain <- harnessr:::governor_input_tokens(cl, utils::modifyList(req, list(schema = NULL)))
  expect_gt(harnessr:::governor_input_tokens(cl, req), plain)
})

test_that("gr_read_many() and gr_synthesise() hold their requests to the given trace's governor", {
  model <- gov_model()
  d <- withr::local_tempdir()
  for (i in 1:3) writeLines(sprintf("Document %d says the revenue rose.", i),
                            file.path(d, sprintf("doc%d.txt", i)))
  # A model the governor does not allow is refused in every document.
  cl <- mock_echo("An answer.")
  tr <- gr_trace(governor = hr_governor(allowed_models = "some-other-model"))
  quiet(gr_read_many(d, "Q?", recipe = "fast", client = cl, model = model, trace = tr))
  expect_length(cl$calls(), 0L)
  expect_identical(tr$stop_reason, "model")

  # The spending limit covers the whole run, not each document.
  cl2 <- mock_echo("An answer.")
  tr2 <- gr_trace(governor = hr_governor(max_cost_usd = 0.05))
  quiet(gr_read_many(d, "Q?", recipe = "fast", client = cl2, model = model, trace = tr2))
  expect_lte(tr2$spent_usd, 0.05)
  expect_lt(length(cl2$calls()), 3L)

  # The governor a forked stage is held to keeps max_calls whole and takes off
  # what the parent has already spent.
  tr3 <- gr_trace(governor = hr_governor(max_calls = 4, max_cost_usd = 1,
                                         max_tokens_total = 100))
  tr3$spent_usd <- 0.25
  tr3$tokens_in <- 30L
  tr3$calls <- 3L
  fork <- harnessr:::fork_governor(tr3)
  expect_identical(fork$max_calls, 4)
  expect_equal(fork$max_cost_usd, 0.75)
  expect_equal(fork$max_tokens_total, 70)
  expect_null(harnessr:::fork_governor(gr_trace()))
})

test_that("max_tokens_total stops a run on an unpriced model sent with allow_unpriced", {
  local_registries()
  gr_register_model("gov-unpriced", context_window = 100000, max_output = 4000)
  n <- 0L
  cl <- gr_backend_client(function(m, p) { n <<- n + 1L; "sent" }, model = "gov-unpriced")
  tr <- gr_trace(governor = hr_governor(allow_unpriced = TRUE, max_tokens_total = 100))
  res <- NULL
  for (i in 1:20) res <- quiet(gr_call(cl, "hi", max_output = 5L, trace = tr))
  expect_gt(n, 0L)
  expect_lt(n, 20L)
  expect_true(res$refused)
  expect_identical(tr$stop_reason, "tokens")
  expect_lte(tr$tokens_in + tr$tokens_out, 100)
  expect_true(is.na(sum(gr_trace_cost(tr)$usd)))
  expect_match(res$error, "token ceiling reached", fixed = TRUE)

  # The same from the option.
  gr_options(allow_unpriced = TRUE, max_tokens_total = 30)
  tr2 <- gr_trace()
  for (i in 1:10) quiet(gr_call(cl, "hi", max_output = 5L, trace = tr2))
  expect_identical(tr2$stop_reason, "tokens")
  expect_lte(tr2$tokens_in + tr2$tokens_out, 30)
  expect_error(gr_options(max_tokens_total = -1), class = "gr_bad_option")
})

test_that("a batch item refused by its share after its first request does not stop the run", {
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")
  model <- gov_model()
  cl <- gr_mock_client(function(m, p) "ok")
  item <- function(i, trace) {
    a <- gr_call(cl, paste("first", i), model = model, max_output = 4L, trace = trace)
    b <- gr_call(cl, paste("second", i), model = model, max_output = 4L, trace = trace)
    c(a$ok, b$ok)
  }
  tr <- gr_trace(governor = hr_governor(max_calls = 6))
  expect_warning(suppressMessages(harnessr:::gr_lapply(1:4, item, parallel = TRUE, workers = 2,
                                                       trace = tr, client = cl)),
                 class = "gr_parallel_share")
  expect_lte(tr$calls, 6L)
  expect_false(isTRUE(tr$budget_stop))
  expect_length(tr$refusals, 0L)
})
