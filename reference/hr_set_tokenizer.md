# Register or inspect the active tokenizer

Register or inspect the active tokenizer

## Usage

``` r
hr_set_tokenizer(name, fn = NULL)
```

## Arguments

- name:

  One of the built-in tokenizers (`"heuristic"`, `"words"`, `"chars"`,
  `"tiktoken"`) or a name previously registered with a custom function.

- fn:

  Optional. A function taking a character vector and returning an
  integer vector of token counts. Supplying it registers a custom
  tokenizer under `name`.

## Value

Invisibly, the name of the newly active tokenizer.

## See also

[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md),
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
old <- hr_tokenizer()
hr_set_tokenizer("heuristic")
hr_count_tokens("the quick brown fox")
#> [1] 8

# Register your own; budgets recompute against it immediately.
hr_set_tokenizer("naive_words",
                 function(x) lengths(strsplit(trimws(x), "\\s+")))
hr_count_tokens("the quick brown fox")
#> [1] 4
hr_set_tokenizer(old)
```
