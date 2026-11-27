# Run time in the trace: elapsed_s read from the steps, and where the time
# went.

time_trace <- function() {
  tr <- hr_trace()
  cl <- hr_mock_client(function(m, p) "ok")
  hr_call(cl, "hi", trace = tr)
  tr
}

test_that("elapsed_s does not grow when the summary is taken later", {
  tr <- time_trace()
  first <- hr_trace_summary(tr)$elapsed_s
  Sys.sleep(1.2)
  expect_identical(hr_trace_summary(tr)$elapsed_s, first)
  expect_lt(first, 1)
})

test_that("elapsed_s of a trace read back from a file is the recorded run time", {
  tr <- hr_trace()
  tr$started <- as.POSIXct("2026-01-01 10:00:00", tz = "UTC")
  trace_push_steps(tr, list(list(step = 1L, label = "a", ok = TRUE,
                                 started_utc = "2026-01-01T10:00:01.000Z",
                                 ended_utc = "2026-01-01T10:00:04.500Z", seconds = 3.5,
                                 tokens = list(input = 1L, output = 1L))))
  f <- tempfile(fileext = ".rds")
  saveRDS(tr, f)
  back <- readRDS(f)
  unlink(f)
  s <- hr_trace_summary(back)
  expect_identical(s$elapsed_s, 4.5)
  expect_identical(s$request_s, 3.5)
  expect_identical(s$overhead_s, 1)
  expect_identical(s$request_share, round(3.5 / 4.5, 4))
})

test_that("an empty trace has taken no time", {
  s <- hr_trace_summary(hr_trace())
  expect_identical(s$elapsed_s, 0)
  expect_identical(s$request_s, 0)
  expect_true(is.na(s$request_share))
})

test_that("the time columns come after every column the summary had", {
  s <- hr_trace_summary(time_trace())
  expect_identical(names(s)[1:13], c(
    "run_id", "calls", "cached", "steps", "tokens_in", "tokens_out", "errors", "elapsed_s",
    "embed_calls", "embed_tokens", "tokens_reasoning", "tokens_cached_in", "usage_estimated"))
  expect_identical(names(s)[14:19], c("request_s", "local_s", "overhead_s", "request_share",
                                      "local_share", "overhead_share"))
})

test_that("local steps that time themselves count as local time", {
  tr <- hr_trace()
  tr$started <- as.POSIXct("2026-01-01 10:00:00", tz = "UTC")
  trace_push_steps(tr, list(
    list(step = 1L, label = "a", ok = TRUE, ended_utc = "2026-01-01T10:00:02.000Z",
         seconds = 2, tokens = list(input = 1L, output = 1L)),
    list(step = 2L, label = "step.command", ok = TRUE, kind = "local",
         at = format(as.POSIXct("2026-01-01 10:00:10", tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3",
                     tz = ""),
         detail = list(seconds = 6))))
  s <- hr_trace_summary(tr)
  expect_identical(s$elapsed_s, 10)
  expect_identical(s$local_s, 6)
  expect_identical(s$overhead_s, 2)
  expect_identical(s$request_share + s$local_share + s$overhead_share, 1)
})

test_that("parallel requests whose seconds pass the run time leave no negative overhead", {
  tr <- hr_trace()
  tr$started <- as.POSIXct("2026-01-01 10:00:00", tz = "UTC")
  trace_push_steps(tr, lapply(1:2, function(i) list(
    step = i, label = "a", ok = TRUE, ended_utc = "2026-01-01T10:00:02.000Z", seconds = 2,
    tokens = list(input = 1L, output = 1L))))
  s <- hr_trace_summary(tr)
  expect_identical(s$request_s, 4)
  expect_identical(s$overhead_s, 0)
})

test_that("the print shows the run time and the provider's cached share", {
  tr <- time_trace()
  out <- capture.output(print(tr))
  expect_true(any(grepl("^  time: [0-9.]+ s \\(requests [0-9]+%, local [0-9]+%, overhead [0-9]+%\\)$",
                        out)))
  tr$tokens_in <- 100L
  tr$steps[[1]]$tokens$cached_input <- 25L
  expect_true(any(grepl("25% of input tokens from the provider's cache", capture.output(print(tr)),
                        fixed = TRUE)))
  expect_false(any(grepl("^  time:", capture.output(print(hr_trace())))))
})
