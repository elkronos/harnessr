# Context and output limits for a model

A two-field convenience wrapper over
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md).

## Usage

``` r
hr_model_limits(model = NULL)
```

## Arguments

- model:

  Model id.

## Value

A list with exactly two elements: `context_window` and `output_tokens`.
(Note the second name differs from
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)'s
`max_output`.)

## See also

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md),
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
hr_model_limits("gpt-4o")
#> $context_window
#> [1] 128000
#> 
#> $output_tokens
#> [1] 16384
#> 
```
