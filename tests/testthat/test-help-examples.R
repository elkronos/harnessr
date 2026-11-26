# Help examples that once ran without error but did not show what their page
# says. R CMD check passes an example that only warns or returns an empty
# reply, so these tests run the examples as written and check their results.

run_help_example <- function(topic) {
  # The help sources when the tests run beside them, else the installed help.
  rd <- test_path("..", "..", "man", paste0(topic, ".Rd"))
  if (!file.exists(rd)) rd <- tools::Rd_db("harnessr")[[paste0(topic, ".Rd")]]
  ex <- tempfile(fileext = ".R")
  on.exit(unlink(ex), add = TRUE)
  tools::Rd2ex(rd, ex)
  env <- new.env(parent = globalenv())
  utils::capture.output(out <- source(ex, local = env))
  # The value of the example's last expression.
  env$.value <- out$value
  env
}

test_that("the hr_backend_client() example sends its call and records it", {
  local_registries()
  env <- expect_no_warning(run_help_example("hr_backend_client"))
  res <- hr_call(env$cl, "What was revenue?", max_output = 128L)
  expect_true(res$ok)
  expect_identical(res$text, "I was asked 1 thing(s) with a 128-token cap.")
  expect_identical(as.integer(hr_trace_summary(env$tr)$calls), 1L)
})

test_that("the gr_calibrate() example says which rows its sheet covers", {
  env <- expect_no_warning(run_help_example("gr_calibrate"))
  expect_s3_class(env$.value, "gr_calibration")
  expect_identical(env$.value$frame$of, "all")
  # It printed "sampled from: all (NA of 8 screened)".
  out <- utils::capture.output(print(env$.value))
  expect_false(any(grepl("\\bNA\\b", out)))
  expect_true(any(grepl("sampled from: all (8 of 8 screened)", out, fixed = TRUE)))
})
