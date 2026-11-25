# Estimate the USD cost of a set of calls

Estimate the USD cost of a set of calls

## Usage

``` r
hr_estimate_cost(
  model,
  input_tokens,
  output_tokens = 0,
  cached_input_tokens = 0
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

## Value

A single numeric USD figure, or `NA_real_` when the model has no pricing
in the registry, or no output price and `output_tokens` above zero (an
embedding model's missing output price counts as zero, since it produces
no output tokens). Pricing is seeded from the registry's `as_of`
snapshot. Treat it as an estimate, and use
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
to correct it.

## See also

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
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
hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.34
hr_estimate_cost("a-model-with-no-pricing", 1000, 100)
#> Warning: Model 'a-model-with-no-pricing' is not in the registry. Falling back to a conservative 128000-token context with a 4096-token output reserve. Register the real limits with hr_register_model('a-model-with-no-pricing', context_window = ..., max_output = ...) so budgets and cost estimates are correct.
#> [1] NA
```
