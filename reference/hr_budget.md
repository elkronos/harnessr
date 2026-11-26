# Compute a usable input-token budget for one model call

This is the single arithmetic chokepoint that every prompt-building path
in the package must go through. It has three guarantees:

- the returned `input` budget is always **strictly positive**;

- `input + output + overhead <= context_window * (1 - safety_margin)`;

- if no positive budget exists, it raises a `gr_budget_error` naming the
  parameter to change, rather than returning a negative number that
  silently corrupts every downstream
  [`split()`](https://rdrr.io/r/base/split.html) and `while` loop.

## Usage

``` r
hr_budget(
  model = NULL,
  reserve_output = NULL,
  overhead = 0,
  safety_margin = NULL
)
```

## Arguments

- model:

  Model id.

- reserve_output:

  Tokens to reserve for the completion. An explicit value is clamped to
  the model's `max_output`. `NULL` reserves
  `min(max_output, max(min_output_tokens, usable * output_reserve_share))`,
  where `usable` is the context window after `safety_margin`, and
  `min_output_tokens` (default 256) and `output_reserve_share` (default
  0.25) are
  [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
  settings. When the reserve leaves no positive input budget, explicit
  or not, it is lowered to `min_output_tokens` (or kept, if already
  smaller) before an error is raised.

- overhead:

  Tokens consumed by system prompts, question text and message framing
  that are not part of the document payload.

- safety_margin:

  Fraction of the context window left unused to absorb tokenizer error.
  Defaults to the `safety_margin` option; clamped to \[0, 0.5\].

## Value

A list with `input`, `output`, `context_window`, `overhead`, `margin`
and `certain` (`FALSE` when the model's limits were guessed rather than
known; see
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)).

## See also

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md)

Other cost and token functions:
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
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
unlist(hr_budget("gpt-4o", reserve_output = 1024, overhead = 200))
#>          input         output context_window       overhead         margin 
#>       113976.0         1024.0       128000.0          200.0            0.1 
#>        certain 
#>            1.0 

# The same question leaves very different room on different models.
vapply(c("gpt-4", "gpt-4o", "gpt-5.6-terra"),
       function(m) hr_budget(m)$input, numeric(1))
#>         gpt-4        gpt-4o gpt-5.6-terra 
#>          5529         98816        817000 

# No positive budget is an error naming what to change, never a negative
# number that silently reverses the document downstream.
tryCatch(hr_budget("gpt-4", overhead = 9000),
         gr_budget_error = function(e) conditionMessage(e))
#> [1] "No positive input budget for model 'gpt-4': context 8192, usable after a 10% safety margin 7372, output reserve 256, fixed overhead 9000. Reduce `reserve_output`, shorten the question/system prompt, or use a model with a larger context window."
```
