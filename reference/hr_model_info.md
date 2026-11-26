# Look up a model's capabilities

Resolution order: user-registered exact id, built-in exact id, alias,
family regex, then a conservative default. The returned list always
carries `certain`, which is `FALSE` when the answer came from a regex or
the default. Treat that as "verify before trusting for cost control".

## Usage

``` r
hr_model_info(model = NULL)
```

## Arguments

- model:

  Model id.

## Value

A named list: `id`, `context_window`, `max_output`, `input_usd`,
`output_usd` and `cached_input_usd` (per 1M tokens, used by
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)),
`reasoning`, `supports_temperature`, `kind`, `dimensions`, `as_of`,
`certain`, and `source` (`"registered"`, `"builtin"`, `"alias"`,
`"pattern:..."` or `"default"`). `certain` is `FALSE` when the answer
came from a family regex or the fallback; verify before relying on it
for cost control.

## Details

An alias (`"chatgpt-4o-latest"`, say) takes the entry of the model it
names, a registered override of that model included, and reports the
alias as its `id`. A family-regex match and the default both warn with
class `gr_unknown_model`; under
`hr_options(unknown_model_action = "error")` both stop instead, because
neither id is in the registry.

## See also

[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md),
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
hr_model_info("gpt-4o")[c("context_window", "max_output", "certain")]
#> $context_window
#> [1] 128000
#> 
#> $max_output
#> [1] 16384
#> 
#> $certain
#> [1] TRUE
#> 

# An unrecognised id warns and falls back to conservative limits.
suppressWarnings(hr_model_info("some-model-from-next-year")$certain)
#> [1] FALSE
```
