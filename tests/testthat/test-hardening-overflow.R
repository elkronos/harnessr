# A provider's "context too long" refusal is named hr_context_overflow, and
# an opt-in function of the caller's can retry it once with a smaller prompt.

ov_resp <- function(json, status) structure(
  list(content = charToRaw(json), status_code = as.integer(status),
       headers = list(`content-type` = "application/json; charset=utf-8"),
       all_headers = list(), url = "mock://"), class = "response")

ov_client <- function() {
  hr_client(api_key = "sk-not-real", base_url = "https://x.invalid", api = "chat",
            model = "gpt-4o", max_retries = 0L, retry_pause_base = 0)
}

# One error body per provider, as each documents or sends it.
ov_bodies <- list(
  openai = paste0('{"error":{"message":"This model\'s maximum context length is 128000 tokens. ',
                  'However, your messages resulted in 130512 tokens.","type":',
                  '"invalid_request_error","param":"messages","code":"context_length_exceeded"}}'),
  anthropic = paste0('{"type":"error","error":{"type":"invalid_request_error","message":',
                     '"prompt is too long: 208310 tokens > 200000 maximum"}}'),
  gemini = paste0('{"error":{"code":400,"message":"The input token count (1200000) exceeds the ',
                  'maximum number of tokens allowed (1048576).","status":"INVALID_ARGUMENT"}}'),
  bedrock = '{"message":"Input is too long for requested model."}',
  llamacpp = paste0('{"error":{"code":400,"message":"the request exceeds the available context ',
                    'size, try increasing it","type":"exceed_context_size_error"}}'),
  groq = paste0('{"error":{"message":"Please reduce the length of the messages or completion.",',
                '"type":"invalid_request_error","param":"messages"}}'),
  gateway = '{"error":"too many tokens in the request"}')

test_that("each provider's overflow body is named, with the estimate and window beside it", {
  for (nm in names(ov_bodies)) {
    body <- ov_bodies[[nm]]
    testthat::local_mocked_bindings(POST = function(...) ov_resp(body, 400L), .package = "httr")
    tr <- hr_trace()
    seen <- NULL
    r <- withCallingHandlers(hr_call(ov_client(), "What was revenue?", trace = tr),
                             hr_context_overflow = function(c) seen <<- c)
    expect_false(r$ok, info = nm)
    expect_identical(r$error_class, "hr_context_overflow", info = nm)
    expect_identical(r$error, paste0("HTTP 400: ", body), info = nm)
    st <- tr$steps[[1]]
    expect_identical(st$overflow$estimate_tokens, as.numeric(st$params$prompt_tokens), info = nm)
    expect_identical(st$overflow$context_window, as.numeric(hr_model_info("gpt-4o")$context_window),
                     info = nm)
    expect_identical(r$overflow, st$overflow, info = nm)
    expect_s3_class(seen, "hr_context_overflow")
    expect_identical(seen$estimate_tokens, st$overflow$estimate_tokens, info = nm)
    expect_identical(length(tr$steps), 1L)
  }
})

test_that("a 413 with an overflow body is named too", {
  testthat::local_mocked_bindings(POST = function(...) ov_resp(ov_bodies$anthropic, 413L),
                                  .package = "httr")
  expect_identical(hr_call(ov_client(), "hi")$error_class, "hr_context_overflow")
})

test_that("an unrelated 400 and a token rate limit are left as they were", {
  body <- '{"error":{"message":"Invalid value for temperature.","type":"invalid_request_error"}}'
  testthat::local_mocked_bindings(POST = function(...) ov_resp(body, 400L), .package = "httr")
  tr <- hr_trace()
  r <- hr_call(ov_client(), "hi", trace = tr)
  expect_false(r$ok)
  expect_null(r$error_class)
  expect_null(r$overflow)
  expect_identical(r$error, paste0("HTTP 400: ", body))
  expect_null(tr$steps[[1]]$overflow)
  expect_false("overflow_retry" %in% names(tr$steps[[1]]))
  rate <- '{"error":{"message":"Rate limit reached: too many tokens per minute."}}'
  testthat::local_mocked_bindings(POST = function(...) ov_resp(rate, 429L), .package = "httr")
  r <- quiet(hr_call(ov_client(), "hi"))
  expect_identical(r$status, 429L)
  expect_null(r$error_class)
})

test_that("on_overflow retries once with the caller's smaller prompt", {
  local_registries()
  hr_register_model("ov-backend", context_window = 128000, max_output = 4096,
                    input_usd = 0, output_usd = 0)
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  prompts <- character(0)
  cl <- hr_backend_client(model = "ov-backend", handler = function(messages, params) {
    txt <- messages[[length(messages)]]$content
    prompts <<- c(prompts, txt)
    if (nchar(txt) > 20) {
      structure(list(ok = FALSE, text = "", error = paste0("HTTP 400: ", ov_bodies$openai),
                     status = 400L, usage = list(input = 0L, output = 0L)), class = "gr_result")
    } else "Revenue was 45.2 million."
  })
  long <- strrep("revenue ", 10)
  # Default: no retry.
  tr <- hr_trace()
  r <- hr_call(cl, long, trace = tr)
  expect_identical(r$error_class, "hr_context_overflow")
  expect_identical(length(prompts), 1L)
  expect_identical(tr$calls, 1L)
  # Opt-in: one retry, recorded and counted.
  seen <- NULL
  hr_options(on_overflow = function(messages, info) {
    seen <<- info
    messages[[length(messages)]]$content <- "revenue?"
    messages
  })
  prompts <- character(0)
  tr <- hr_trace()
  r <- hr_call(cl, long, trace = tr, label = "answer")
  expect_true(r$ok)
  expect_true(r$overflow_retry)
  expect_identical(prompts, c(long, "revenue?"))
  expect_identical(tr$calls, 2L)
  expect_identical(vapply(tr$steps, function(s) s$label, ""), c("answer", "answer"))
  expect_true(tr$steps[[2]]$overflow_retry)
  expect_identical(tr$steps[[1]]$overflow$estimate_tokens, seen$estimate_tokens)
  expect_identical(seen$label, "answer")
  expect_match(seen$error, "context_length_exceeded", fixed = TRUE)
  # The governor counts the retry: with one call allowed it is refused.
  tr <- hr_trace(governor = hr_governor(max_calls = 1))
  r <- hr_call(cl, long, trace = tr)
  expect_true(r$refused)
  expect_identical(tr$calls, 1L)
  expect_identical(tr$stop_reason, "calls")
  # A retry that overflows again is not retried a second time.
  hr_options(on_overflow = function(messages, info) messages)
  prompts <- character(0)
  tr <- hr_trace()
  r <- hr_call(cl, long, trace = tr)
  expect_identical(r$error_class, "hr_context_overflow")
  expect_true(r$overflow_retry)
  expect_identical(length(prompts), 2L)
  # A function that fails or gives nothing sends nothing more.
  hr_options(on_overflow = function(messages, info) stop("no"))
  prompts <- character(0)
  expect_warning(r <- hr_call(cl, long), class = "hr_overflow_refit_failed")
  expect_identical(length(prompts), 1L)
  hr_options(on_overflow = function(messages, info) NULL)
  prompts <- character(0)
  expect_silent(r <- hr_call(cl, long))
  expect_identical(length(prompts), 1L)
})

test_that("on_overflow is checked, and recorded without its code", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  expect_error(hr_options(on_overflow = "retry"), class = "gr_bad_option")
  expect_error(hr_options(on_overflow = NULL), class = "gr_bad_option")
  expect_false("on_overflow" %in% names(hr_trace()$config$options))
  hr_options(on_overflow = function(messages, info) messages)
  tr <- hr_trace()
  expect_identical(tr$config$options$on_overflow, "<function>")
  expect_no_error(as_json(tr))
  s <- gr_settings_table("options")
  expect_identical(s$default[s$name == "on_overflow"], "error")
  expect_identical(s$guide[s$name == "on_overflow"], "context#set-overflow")
})

test_that("the mock's overflow mode refuses its first request", {
  cl <- hr_mock_client(function(m, p) "fine", mode = "overflow")
  expect_identical(hr_call(cl, "a")$error_class, "hr_context_overflow")
  expect_true(hr_call(cl, "a")$ok)
  cl$reset()
  expect_false(hr_call(cl, "a")$ok)
})

test_that("the overflow record keeps the status, so a replay names the refusal and retries it", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  testthat::local_mocked_bindings(POST = function(...) ov_resp(ov_bodies$anthropic, 413L),
                                  .package = "httr")
  tr <- hr_trace()
  r <- hr_call(ov_client(), "hi", trace = tr)
  expect_identical(r$overflow$status, 413L)
  expect_identical(tr$steps[[1]]$overflow$status, 413L)

  hr_options(on_overflow = function(messages, info) {
    messages[[length(messages)]]$content <- "short"
    messages
  })
  live <- hr_mock_client(function(m, p) "Revenue was 45.2 million.", mode = "overflow")
  tr <- hr_trace()
  r <- hr_call(live, "What was revenue?", trace = tr)
  expect_true(r$ok)
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  hr_trace_save(tr, f)
  tr2 <- hr_trace()
  r2 <- hr_call(hr_replay_client(f), "What was revenue?", trace = tr2)
  expect_true(r2$ok)
  expect_identical(r2$text, r$text)
  expect_identical(length(tr2$steps), 2L)
  expect_identical(tr2$steps[[1]]$overflow$status, 400L)
  expect_true(tr2$steps[[2]]$overflow_retry)
})

test_that("a refusal a handler raises with httr2's HTTP 400 is named too", {
  tr <- hr_trace()
  cl <- hr_mock_client(function(m, p) {
    stop("HTTP 400 Bad Request.\n* prompt is too long: 208310 tokens > 200000 maximum")
  })
  got <- NULL
  r <- withCallingHandlers(hr_call(cl, "q", trace = tr),
                           hr_context_overflow = function(c) got <<- c)
  expect_false(r$ok)
  expect_identical(r$error_class, "hr_context_overflow")
  expect_identical(r$status, 400L)
  expect_identical(tr$steps[[1]]$overflow$status, 400L)
  expect_s3_class(got, "hr_context_overflow")
  # 413 is read the same way; a raised 400 for another reason, a raised
  # overflow phrase with no status, and a 429 are not.
  big <- hr_mock_client(function(m, p) stop("HTTP 413 Payload Too Large: input is too long"))
  expect_identical(hr_call(big, "q")$error_class, "hr_context_overflow")
  for (msg in c("HTTP 400 Bad Request. invalid model",
                "prompt is too long: 208310 tokens > 200000 maximum",
                "HTTP 429 Too Many Requests. too many tokens per minute",
                "HTTP 4000 prompt is too long")) {
    r <- hr_call(hr_mock_client(function(m, p) stop(msg)), "q")
    expect_null(r$error_class, info = msg)
    expect_true(is.na(r$status), info = msg)
  }
})

test_that("a replay retries a refusal only where the recorded run did", {
  old <- hr_options()
  on.exit(hr_options(old), add = TRUE)
  shorter <- function(messages, info) {
    messages[[length(messages)]]$content <- "short"
    messages
  }
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  # Recorded with no on_overflow: one refusal, no retry. A session that sets
  # one replays the recorded failure and sends no retry.
  tr <- hr_trace()
  r <- hr_call(hr_mock_client(function(m, p) "fine", mode = "overflow"), "Q", trace = tr)
  expect_identical(r$error_class, "hr_context_overflow")
  hr_trace_save(tr, f)
  hr_options(on_overflow = shorter)
  tr2 <- hr_trace()
  r2 <- hr_call(hr_replay_client(f), "Q", trace = tr2)
  expect_false(r2$ok)
  expect_identical(r2$error_class, "hr_context_overflow")
  expect_identical(length(tr2$steps), 1L)
  expect_null(r2$overflow_retried)
  # Recorded with a retry: a session without the function cannot rebuild the
  # retried prompt, and says which option to set.
  tr <- hr_trace()
  r <- hr_call(hr_mock_client(function(m, p) "fine", mode = "overflow"), "Q", trace = tr)
  expect_true(r$ok)
  hr_trace_save(tr, f)
  hr_options(on_overflow = "error")
  expect_error(hr_call(hr_replay_client(f), "Q"), "on_overflow", class = "gr_replay_miss")
  r3 <- hr_call(hr_replay_client(f, strict = FALSE), "Q")
  expect_identical(r3$error_class, "hr_context_overflow")
})

test_that("an on_overflow function travels to the workers of a parallel batch", {
  fn <- function(messages, info) messages
  got <- harnessr:::worker_functions(NULL, list(tokenizer = "heuristic", on_overflow = fn))
  expect_identical(got$on_overflow, fn)
  expect_null(harnessr:::worker_functions(NULL, list(tokenizer = "heuristic",
                                                     on_overflow = "error"))$on_overflow)
})
