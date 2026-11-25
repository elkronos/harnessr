# test-mock-modes.R: hr_mock_client(mode =) breaks replies the way a
# provider can, and a mock without a mode is the client it always was.

test_that("a mock without a mode has the fields it always had", {
  cl <- hr_mock_client()
  expect_identical(names(cl), c("model", "api", "base_url", "embedding_model", "max_retries",
                                "retry_pause_base", "timeout", "extra_body", ".client_id",
                                "handler", "embed_handler", ".log", "calls", "embeds", "reset"))
  expect_null(cl[["mode", exact = TRUE]])
  expect_identical(hr_call(cl, "hi")$text, "mock answer")
})

test_that("bad_json sends JSON cut off part way, which a schema reply cannot use", {
  cl <- hr_mock_client(function(m, p) '{"answer": "fine"}', mode = "bad_json")
  expect_identical(cl[["mode", exact = TRUE]], "bad_json")
  res <- hr_call(cl, "hi")
  expect_true(res$ok)
  expect_error(jsonlite::fromJSON(res$text))
  schema <- list(type = "object", properties = list(answer = list(type = "string")),
                 required = list("answer"))
  parsed <- quiet(harnessr:::gr_call_json(cl, list(list(role = "user", content = "hi")),
                                          schema = schema))
  expect_false(parsed$ok)
})

test_that("refuse gives an empty reply, reported as a failed call", {
  res <- hr_call(hr_mock_client(mode = "refuse"), "hi")
  expect_false(res$ok)
  expect_identical(res$finish_reason, "empty")
  expect_identical(res$text, "")
})

test_that("at_cap keeps the handler's text, marks it cut off and bills the cap", {
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.", mode = "at_cap")
  res <- hr_call(cl, "hi", max_output = 50)
  expect_true(res$ok)
  expect_identical(res$text, "Revenue was 45.2 million dollars.")
  expect_identical(res$finish_reason, "length")
  expect_identical(res$usage$output, 50L)
  # A reply cut off at the cap is not cached.
  cache <- hr_cache(dir = withr::local_tempdir())
  cached <- hr_cache_client(cl, cache)
  hr_call(cached, "hi", max_output = 50)
  hr_call(cached, "hi", max_output = 50)
  expect_length(cl$calls(), 3L)
})

test_that("a status sequence fails each call with its status, then repeats the last", {
  cl <- hr_mock_client(function(m, p) "ok then", mode = c(429, 500, 200))
  expect_identical(cl[["mode", exact = TRUE]], c(429L, 500L, 200L))
  got <- lapply(1:4, function(i) hr_call(cl, "hi"))
  expect_identical(vapply(got, function(r) r$ok, logical(1)), c(FALSE, FALSE, TRUE, TRUE))
  expect_identical(got[[1]]$status, 429L)
  expect_true(got[[1]]$retryable)
  expect_identical(got[[2]]$status, 500L)
  expect_match(got[[2]]$error, "HTTP 500", fixed = TRUE)
  expect_identical(got[[3]]$text, "ok then")
  # A 4xx other than 429 is not marked retryable.
  expect_false(hr_call(hr_mock_client(mode = 404), "hi")$retryable)
  # $reset() starts the sequence again.
  cl$reset()
  expect_identical(hr_call(cl, "hi")$status, 429L)
})

test_that("a status is marked retryable as the HTTP transport marks it", {
  statuses <- c(400L, 404L, 408L, 409L, 425L, 429L, 500L, 501L, 502L, 503L, 504L, 505L, 599L)
  got <- vapply(statuses, function(s) hr_call(hr_mock_client(mode = s), "hi")$retryable,
                logical(1))
  expect_identical(got, statuses %in% harnessr:::.retryable_status)
  expect_true(hr_call(hr_mock_client(mode = 408), "hi")$retryable)
  expect_false(hr_call(hr_mock_client(mode = 501), "hi")$retryable)
})

test_that("at_cap returns a failed handler result as it is", {
  fail <- function(m, p) harnessr:::gr_result(FALSE, error = "boom", status = 500L)
  plain <- hr_call(hr_mock_client(fail), "hi")
  capped <- hr_call(hr_mock_client(fail, mode = "at_cap"), "hi")
  expect_false(capped$ok)
  expect_identical(capped$status, 500L)
  expect_identical(capped$error, "boom")
  expect_identical(capped$finish_reason, plain$finish_reason)
  expect_identical(capped$usage$output, plain$usage$output)
})

test_that("a mode leaves embeddings alone", {
  plain <- hr_embed(hr_mock_client(), c("alpha", "beta"))
  moded <- hr_embed(hr_mock_client(mode = "refuse"), c("alpha", "beta"))
  expect_identical(unclass(moded)[, ], unclass(plain)[, ])
})

test_that("a mode that is not one is refused", {
  expect_error(hr_mock_client(mode = "slow"), class = "gr_bad_setting")
  expect_error(hr_mock_client(mode = c(200, 99)), class = "gr_bad_setting")
  expect_error(hr_mock_client(mode = 200.5), class = "gr_bad_setting")
  expect_error(hr_mock_client(mode = c("refuse", "at_cap")), class = "gr_bad_setting")
  expect_error(hr_mock_client(mode = NA), class = "gr_bad_setting")
})
