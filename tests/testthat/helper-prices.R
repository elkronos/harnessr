# helper-prices.R: prices for the built-in models the tests use.
#
# harnessr ships each built-in model's limits but no prices, so a user sets
# them with hr_register_model() or hr_load_models(). The tests do what a user
# would: fixtures/models/prices.csv holds the prices the built-in models had
# at c3a86ee (as of 2026-08), and this loads them once, before any test runs,
# so expectations about dollars still check dollars. Tests that need a model
# without a price register one of their own, or remove the registered entry
# under local_registries().
#
# local_registries() restores the registry to what it was when it was called,
# so these entries survive every test that changes the registry.
test_prices_file <- function() {
  testthat::test_path("fixtures", "models", "prices.csv")
}

local({
  harnessr::hr_load_models(test_prices_file())
})

# Take a model's test prices away for the rest of the calling test, leaving
# its built-in entry.
local_unpriced <- function(ids, env = parent.frame()) {
  local_registries(env)
  st <- harnessr:::hr_state
  models <- st$models
  models[ids] <- NULL
  st$models <- models
  invisible(ids)
}

# The price warnings are given once per model per session. Clear the record
# of which have been given for the rest of the calling test, so a test sees
# the first warning whatever ran before it, and put it back afterwards.
local_price_warnings <- function(env = parent.frame()) {
  st <- harnessr:::hr_state
  old <- st$price_warned
  st$price_warned <- NULL
  withr::defer(st$price_warned <- old, envir = env)
  invisible(NULL)
}
