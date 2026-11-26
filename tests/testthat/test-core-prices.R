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

# Prices that are out of date. A price's age runs from the first day of its
# as_of month to price_today(), which these tests move.

local_today <- function(date, env = parent.frame()) {
  testthat::local_mocked_bindings(price_today = function() as.Date(date), .package = "harnessr",
                                  .env = env)
}

stale_models <- function(env = parent.frame()) {
  local_registries(env)
  path <- tempfile(fileext = ".csv")
  writeLines(c("id,context_window,max_output,input_usd,output_usd,as_of",
               "price-test-old,100000,4000,1,2,2026-01",
               "price-test-older,100000,4000,1,2,2025-06"), path)
  withr::defer(unlink(path), envir = env)
  hr_load_models(path)
}

test_that("a price is stale at 121 days and not at 120, counted from the first of its month", {
  local_price_warnings()
  stale_models()
  expect_equal(hr_options("price_max_age_days"), 120)
  local_today(as.Date("2026-01-01") + 120)
  expect_no_warning(usd <- hr_estimate_cost("price-test-old", 1e6, 1e6))
  expect_equal(usd, 3)
  local_today(as.Date("2026-01-01") + 121)
  w <- expect_warning(usd <- hr_estimate_cost("price-test-old", 1e6, 1e6),
                      class = "hr_stale_price")
  # The figure is still computed from the prices.
  expect_equal(usd, 3)
  expect_identical(w$model, "price-test-old")
  expect_identical(w$as_of, "2026-01")
  expect_match(conditionMessage(w), "as of 2026-01, 121 days ago", fixed = TRUE)
  expect_match(conditionMessage(w), "hr_register_model(input_usd =, output_usd =)", fixed = TRUE)
  expect_match(conditionMessage(w), "hr_load_models()", fixed = TRUE)
})

test_that("a stale price warns once per model per session", {
  local_price_warnings()
  stale_models()
  local_today("2026-11-26")
  expect_warning(hr_estimate_cost("price-test-old", 1000, 100), class = "hr_stale_price")
  expect_no_warning(hr_estimate_cost("price-test-old", 1000, 100))
  expect_no_warning(hr_estimate_cost("price-test-old", 5, 5))
  expect_warning(hr_estimate_cost("price-test-older", 1000, 100), class = "hr_stale_price")
  expect_no_warning(hr_estimate_cost("price-test-older", 1000, 100))
})

test_that("hr_load_models() with an old as_of warns when a request is priced, and still prices it", {
  local_price_warnings()
  stale_models()
  local_today("2026-11-26")
  n <- 0L
  cl <- hr_backend_client(function(m, p) { n <<- n + 1L; "sent" }, model = "price-test-older")
  tr <- hr_trace()
  expect_warning(res <- hr_call(cl, "hi", max_output = 5L, trace = tr), class = "hr_stale_price")
  expect_true(res$ok)
  expect_gt(tr$spent_usd, 0)
  expect_no_warning(hr_call(cl, "hi", max_output = 5L, trace = tr))
  expect_identical(n, 2L)
  # hr_trace_cost() prices the calls from the stale prices, rather than
  # reading the warning as an unknown model.
  local_price_warnings()
  expect_warning(cost <- hr_trace_cost(tr), class = "hr_stale_price")
  expect_false(is.na(cost$usd[cost$model == "price-test-older"]))
  expect_equal(sum(cost$usd), tr$spent_usd)
})

test_that("price_max_age_days sets the age, NULL turns the warning off, and fresh prices are quiet", {
  local_price_warnings()
  stale_models()
  local_today("2026-03-01")
  # 2026-01 is 59 days old here.
  expect_no_warning(hr_estimate_cost("price-test-old", 1000, 100))
  hr_options(price_max_age_days = 30)
  expect_warning(hr_estimate_cost("price-test-old", 1000, 100), class = "hr_stale_price")
  hr_options(price_max_age_days = NULL)
  expect_null(hr_options("price_max_age_days"))
  expect_no_warning(hr_estimate_cost("price-test-older", 1000, 100))
  expect_warning(hr_options(price_max_age_days = "x"), class = "gr_bad_option")
  hr_options(price_max_age_days = 120)
  # Prices set this month, and a model with no price, never warn.
  local_today(Sys.Date())
  hr_register_model("price-test-new", context_window = 100000, max_output = 4000,
                    input_usd = 1, output_usd = 2)
  expect_no_warning(hr_estimate_cost("price-test-new", 1000, 100))
  local_unpriced("gpt-4o")
  expect_no_warning(expect_true(is.na(hr_estimate_cost("gpt-4o", 1000, 100))))
})

test_that("price_max_age_days is an option with evidence, kept out of a trace at its default", {
  o <- gr_settings_table("options")
  row <- o[o$name == "price_max_age_days", ]
  expect_identical(row$default, "120")
  expect_identical(row$status, "untested")
  expect_identical(o$default[o$name == "allow_unpriced"], "TRUE")
  expect_identical(o$status[o$name == "allow_unpriced"], "untested")
  local_registries()
  hr_options(harnessr:::gr_defaults)
  expect_false("price_max_age_days" %in% names(hr_trace()$config$options))
  hr_options(price_max_age_days = 90)
  expect_identical(hr_trace()$config$options$price_max_age_days, 90)
})
