# test-core-prices.R: requests to models with no price, and prices that are
# out of date.
#
# harnessr ships no prices, so a request to an unpriced chat model is the
# normal case. Under a spending limit it is sent, priced NA, with a warning of
# class hr_unpriced_model once per model per session. allow_unpriced = FALSE
# restores the refusal.

# A paying client on a model with no price, counting what it sends.
unpriced_backend <- function(model = "price-test-unpriced", env = parent.frame()) {
  local_registries(env)
  hr_register_model(model, context_window = 100000, max_output = 4000)
  sent <- new.env(parent = emptyenv())
  sent$n <- 0L
  cl <- hr_backend_client(function(m, p) {
    sent$n <- sent$n + 1L
    "sent"
  }, model = model)
  list(client = cl, sent = sent, model = model)
}

test_that("an unpriced request is sent under the default limit, with one warning per model", {
  local_price_warnings()
  b <- unpriced_backend()
  hr_options(harnessr:::gr_defaults)
  hr_options(verbose = FALSE)
  expect_true(hr_options("allow_unpriced"))
  expect_identical(hr_options("max_cost_usd"), 5)

  tr <- hr_trace()
  res <- NULL
  w <- expect_warning(res <- hr_call(b$client, "hi", trace = tr), class = "hr_unpriced_model")
  expect_true(res$ok)
  expect_identical(b$sent$n, 1L)
  expect_identical(w$model, b$model)
  expect_match(conditionMessage(w), "price-test-unpriced", fixed = TRUE)
  expect_match(conditionMessage(w), "$5 spending limit", fixed = TRUE)
  expect_match(conditionMessage(w), "hr_register_model(input_usd =, output_usd =)", fixed = TRUE)
  expect_match(conditionMessage(w), "hr_load_models()", fixed = TRUE)
  # The trace prices it NA, never 0, and records no refusal.
  expect_true(is.na(hr_trace_cost(tr)$usd[1]))
  expect_identical(tr$spent_usd, 0)
  expect_length(tr$refusals, 0L)
  expect_false(isTRUE(tr$budget_stop))

  # Once per model per session: the second request, and a new trace, are quiet.
  expect_no_warning(hr_call(b$client, "hi", trace = tr))
  expect_no_warning(hr_call(b$client, "hi", trace = hr_trace()))
  expect_identical(b$sent$n, 3L)

  # Another unpriced model is warned about on its own.
  hr_register_model("price-test-other", context_window = 100000, max_output = 4000)
  expect_warning(hr_call(b$client, "hi", model = "price-test-other", trace = hr_trace()),
                 class = "hr_unpriced_model")
})

test_that("an unpriced request is not warned about with no spending limit, or from a mock", {
  local_price_warnings()
  b <- unpriced_backend()
  expect_no_warning(res <- hr_call(b$client, "hi",
                                   trace = hr_trace(governor = hr_governor(max_cost_usd = NULL))))
  expect_true(res$ok)
  mock <- hr_mock_client(function(m, p) "ok")
  expect_no_warning(res <- hr_call(mock, "hi", model = b$model, trace = hr_trace()))
  expect_true(res$ok)
  # Neither used up the warning: the first paid request under a limit still warns.
  expect_warning(hr_call(b$client, "hi", trace = hr_trace()), class = "hr_unpriced_model")
})

test_that("allow_unpriced = FALSE refuses an unpriced request, from the option or the governor", {
  local_price_warnings()
  b <- unpriced_backend()
  hr_options(allow_unpriced = FALSE)
  tr <- hr_trace()
  res <- NULL
  expect_condition(res <- hr_call(b$client, "hi", trace = tr), class = "hr_unpriced_model")
  expect_true(res$refused)
  expect_identical(tr$stop_reason, "unpriced")
  expect_identical(b$sent$n, 0L)
  # The refusal names both ways to set a price.
  expect_match(res$error, "hr_register_model(input_usd =, output_usd =)", fixed = TRUE)
  expect_match(res$error, "hr_load_models()", fixed = TRUE)

  hr_options(allow_unpriced = TRUE)
  tr2 <- hr_trace(governor = hr_governor(allow_unpriced = FALSE))
  expect_condition(res <- hr_call(b$client, "hi", trace = tr2), class = "hr_budget_refused")
  expect_true(res$refused)
  expect_identical(tr2$stop_reason, "unpriced")
  expect_identical(b$sent$n, 0L)
  expect_error(hr_governor(allow_unpriced = NA), class = "gr_bad_option")
  expect_error(hr_options(allow_unpriced = "yes"), class = "gr_bad_option")
})

test_that("token and call limits still refuse an unpriced request", {
  local_price_warnings()
  b <- unpriced_backend()
  tr <- hr_trace(governor = hr_governor(max_calls = 1))
  expect_true(quiet(hr_call(b$client, "hi", trace = tr))$ok)
  res <- quiet(hr_call(b$client, "hi", trace = tr))
  expect_true(res$refused)
  expect_identical(tr$stop_reason, "calls")
  expect_identical(b$sent$n, 1L)

  tr2 <- hr_trace(governor = hr_governor(max_tokens_total = 10))
  res <- quiet(hr_call(b$client, "a prompt of some length", max_output = 50L, trace = tr2))
  expect_true(res$refused)
  expect_identical(tr2$stop_reason, "tokens")
  expect_identical(b$sent$n, 1L)
})

test_that("a priced model is held to the dollar limit as before, with no unpriced warning", {
  local_price_warnings()
  local_registries()
  hr_register_model("price-test-priced", context_window = 100000, max_output = 4000,
                    input_usd = 1, output_usd = 1000)
  n <- 0L
  cl <- hr_backend_client(function(m, p) { n <<- n + 1L; "sent" }, model = "price-test-priced")
  tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.001))
  res <- NULL
  expect_condition(res <- hr_call(cl, "hi", max_output = 100L, trace = tr),
                   class = "hr_budget_refused")
  expect_true(res$refused)
  expect_identical(tr$stop_reason, "cost")
  expect_identical(n, 0L)
  # Within the limit it is sent and priced.
  tr2 <- hr_trace(governor = hr_governor(max_cost_usd = 1))
  expect_no_warning(res <- hr_call(cl, "hi", max_output = 5L, trace = tr2))
  expect_true(res$ok)
  expect_gt(tr2$spent_usd, 0)
})
