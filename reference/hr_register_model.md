# Register a model (or override a built-in entry)

Use this whenever the shipped registry is stale or you are pointing the
client at a compatible non-OpenAI endpoint. Registered entries take
precedence over everything built in.

## Usage

``` r
hr_register_model(
  id,
  context_window,
  max_output,
  input_usd = NA_real_,
  output_usd = NA_real_,
  reasoning = FALSE,
  supports_temperature = TRUE,
  kind = c("chat", "embedding"),
  dimensions = NA_integer_,
  cached_input_usd = NA_real_
)
```

## Arguments

- id:

  Model id string, exactly as the API expects it.

- context_window:

  Total context window in tokens.

- max_output:

  Maximum tokens the model will emit in one response.

- input_usd, output_usd:

  Price per 1M tokens; used for cost estimates. Give both or neither for
  a chat model: one without the other is an error, since a cost with
  half its price missing cannot be estimated. An embedding model needs
  only `input_usd`.

- reasoning:

  Whether this is a reasoning model (affects prompt shape).

- supports_temperature:

  Whether the API accepts `temperature`.

- kind:

  `"chat"` or `"embedding"`.

- dimensions:

  Embedding dimensionality, for `kind = "embedding"`.

- cached_input_usd:

  Price per 1M input tokens the provider served from its prompt cache,
  where that is billed at its own rate. `NA` (the default) prices them
  as other input tokens, which never undercounts.

## Value

Invisibly, `id`.

## See also

[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
to see the registry,
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
for lookup and its `certain` flag,
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md),
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
hr_register_model("my-local-llama", context_window = 32768, max_output = 4096)
hr_model_info("my-local-llama")[c("context_window", "source", "certain")]
#> $context_window
#> [1] 32768
#> 
#> $source
#> [1] "registered"
#> 
#> $certain
#> [1] TRUE
#> 

# Without prices, the cost cap cannot be checked; harnessr says so rather
# than assuming the run is free.
is.na(hr_estimate_cost("my-local-llama", 1000, 500))
#> [1] TRUE
```
