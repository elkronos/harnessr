# List every known model

List every known model

## Usage

``` r
hr_models()
```

## Value

A data frame with `id`, `kind`, `context_window`, `max_output`,
`reasoning`, `input_usd_per_1m`, `output_usd_per_1m`, `as_of` (the month
the entry was recorded; a stale date is a prompt to verify) and
`cached_input_usd_per_1m`.

## See also

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
subset(hr_models(), kind == "chat")[, c("id", "context_window", "as_of")]
#>               id context_window   as_of
#> 1  gpt-3.5-turbo          16385 2026-08
#> 2          gpt-4           8192 2026-08
#> 3    gpt-4-turbo         128000 2026-08
#> 4        gpt-4.1        1047576 2026-08
#> 5   gpt-4.1-mini        1047576 2026-08
#> 6   gpt-4.1-nano        1047576 2026-08
#> 7         gpt-4o         128000 2026-08
#> 8    gpt-4o-mini         128000 2026-08
#> 9          gpt-5         400000 2026-08
#> 10    gpt-5-mini         400000 2026-08
#> 11    gpt-5-nano         400000 2026-08
#> 12       gpt-5.4         400000 2026-08
#> 13  gpt-5.4-mini         400000 2026-08
#> 14       gpt-5.5         400000 2026-08
#> 15  gpt-5.6-luna        1050000 2026-08
#> 16   gpt-5.6-sol        1050000 2026-08
#> 17 gpt-5.6-terra        1050000 2026-08
#> 18    mock-model         128000 2026-11
#> 19   priced-mock         128000 2026-11
```
