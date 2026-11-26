# Estimate the USD cost of a set of calls

Estimate the USD cost of a set of calls

## Usage

``` r
hr_estimate_cost(
  model,
  input_tokens,
  output_tokens = 0,
  cached_input_tokens = 0,
  detail = FALSE
)
```

## Arguments

- model:

  Model id.

- input_tokens, output_tokens:

  Token counts (scalars or vectors; vectors are summed).

- cached_input_tokens:

  How many of `input_tokens` the provider served from its prompt cache.
  They are priced at the model's `cached_input_usd` when it has one, and
  as other input tokens when it does not.

- detail:

  `FALSE` (the default) for the figure alone; `TRUE` for a data frame
  that also says where the prices came from.

## Value

A single numeric USD figure, or `NA_real_` when the model has no pricing
in the registry, or no output price and `output_tokens` above zero (an
embedding model's missing output price counts as zero, since it produces
no output tokens). harnessr ships no prices: set them with
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
or
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md).
Treat the figure as an estimate. When the model's prices are older than
`hr_options("price_max_age_days")` (120 days by default, counted from
the first day of their `as_of` month), the first figure computed from
them in a session warns with class `hr_stale_price`.

With `detail = TRUE`, a one-row data frame instead: `model`, `usd` (the
same figure), `priced` (whether the model has a price), `as_of` (the
month of its prices, `NA` without one) and `certain` (`FALSE` when the
model's registry entry is a family guess or the default; see
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)).

## See also

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md),
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
# harnessr ships no prices, so a built-in model's cost is NA until you set
# them. Not 0: nothing says the run is free.
hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#> [1] NA

# Set the prices you pay. These figures are illustrative: use your
# provider's current prices, in USD per million tokens.
hr_register_model("gpt-4o", input_usd = 2.50, output_usd = 10)
hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.34

# Where the figure's prices came from.
hr_estimate_cost("gpt-4o", 120000, 4000, detail = TRUE)
#>    model  usd priced   as_of certain
#> 1 gpt-4o 0.34   TRUE 2026-11    TRUE
```
