# Register a model, or set the prices of a known one

Use this to add a model the registry does not know, to correct a
built-in entry, or to give a model its prices. harnessr ships each
built-in model's limits but no prices, because providers change prices
more often than the package is released: cost estimates and the
`max_cost_usd` limit use the prices you set here or with
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md).
Registered entries take precedence over everything built in.

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

  Total context window in tokens. Leave it out to keep the current
  entry's.

- max_output:

  Maximum tokens the model will emit in one response. Leave it out to
  keep the current entry's.

- input_usd, output_usd:

  Price per 1M tokens, in USD; used for cost estimates and the
  `max_cost_usd` limit. Give both or neither for a chat model: one
  without the other is an error, since a cost with half its price
  missing cannot be estimated. An embedding model needs only
  `input_usd`. When you change an existing entry, a price you leave out
  keeps its current value.

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

## Details

Give both `context_window` and `max_output` to register a model in full:
every other argument you leave out takes its default. Leave either limit
out to change the model's current entry, built in or registered: the new
entry keeps every value you leave out. That is how you price a built-in
model without restating its limits.

The entry's `as_of`, shown by
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md),
is the current month. When you change an entry that has prices without
giving new ones, it keeps the month of those prices. When you give only
some of its prices, such as `cached_input_usd` alone, the prices you
leave out are as old as before, so the entry keeps their month too. An
alias such as `"chatgpt-4o-latest"` takes its entry from its target: set
the prices on the target. Once prices are older than
`hr_options("price_max_age_days")` (120 days by default), the first cost
computed from them in a session warns with class `hr_stale_price`.

## See also

[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
to register many models from a file,
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
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md),
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

# Price a built-in model and keep its limits. The figures are illustrative:
# use your provider's current prices.
hr_register_model("gpt-4o-mini", input_usd = 0.15, output_usd = 0.60)
hr_model_info("gpt-4o-mini")[c("context_window", "input_usd", "output_usd")]
#> $context_window
#> [1] 128000
#> 
#> $input_usd
#> [1] 0.15
#> 
#> $output_usd
#> [1] 0.6
#> 
```
