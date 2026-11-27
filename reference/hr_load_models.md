# Register models from a CSV file

Reads a file of models and registers each row as
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
would. Use it to set the prices of many models at once: harnessr ships
each built-in model's limits but no prices, because providers change
prices more often than the package is released.

## Usage

``` r
hr_load_models(file)
```

## Arguments

- file:

  Path to the CSV file.

## Value

Invisibly, the ids registered, in file order.

## File format

A CSV file with a header row and one row per model. Only `id` is
required; a blank cell, or `NA`, means the value is not given.

- `id`:

  The model id, exactly as the API expects it. Each id may appear once.

- `input_usd`, `output_usd`:

  Price per 1M tokens, in USD. Give both for a chat model, or neither.
  An embedding model needs only `input_usd`.

- `cached_input_usd`:

  Price per 1M input tokens served from the provider's prompt cache.
  Blank prices them as other input tokens.

- `as_of`:

  The month the prices were checked, as `YYYY-MM`. Blank stamps the
  current month, and a month after the current one is an error. A row
  that gives only some of a priced model's prices keeps the older month,
  since the prices it leaves out are as old as before. A cost computed
  from prices older than `hr_options("price_max_age_days")` warns with
  class `hr_stale_price`, once per model per session.

- `context_window`, `max_output`:

  Limits in tokens.

- `reasoning`, `supports_temperature`:

  `TRUE` or `FALSE`.

- `kind`:

  `chat` or `embedding`.

- `dimensions`:

  Embedding dimensions, for an embedding model.

A row that gives both `context_window` and `max_output` registers the
model in full, and a blank column takes
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)'s
default. A row that leaves either limit blank changes the model's
current entry, built in or registered, and keeps every value the row
leaves blank. So a row with only `id`, `input_usd` and `output_usd`
prices a built-in model and keeps its limits:


    id,input_usd,output_usd,as_of
    gpt-4o,2.50,10.00,2026-11
    my-local-llama,0,0,2026-11

The second row works only if `my-local-llama` is already registered.

harnessr checks the whole file before it registers anything. A file it
cannot use stops with an error of class `hr_bad_models_file` that names
the row and column at fault (row 1 is the first row after the header)
and carries them as the condition's `row` and `column` fields; the
registry is then left as it was.

## See also

[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
for one model,
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
to check the result,
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
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
# The prices here are illustrative: use your provider's current prices.
# With no as_of column, the prices are stamped with the current month.
prices <- tempfile(fileext = ".csv")
writeLines(c("id,input_usd,output_usd",
             "gpt-4o,2.50,10.00",
             "gpt-4o-mini,0.15,0.60"), prices)
hr_load_models(prices)
m <- hr_models()
m[m$id %in% c("gpt-4o", "gpt-4o-mini"),
  c("id", "context_window", "input_usd_per_1m", "output_usd_per_1m", "as_of")]
#>            id context_window input_usd_per_1m output_usd_per_1m   as_of
#> 7      gpt-4o         128000             2.50              10.0 2026-11
#> 8 gpt-4o-mini         128000             0.15               0.6 2026-11

# A malformed file names the row and column, and registers nothing.
writeLines(c("id,input_usd,output_usd", "gpt-4o,two,10"), prices)
tryCatch(hr_load_models(prices), hr_bad_models_file = conditionMessage)
#> [1] "Models file '/tmp/RtmpVwNvOF/file1bfe4b01cb1b.csv', row 1, column 'input_usd': 'two' is not a price; give USD per 1M tokens as a number of 0 or more, such as 2.5."
unlink(prices)
```
