# Cut text to a token count, keeping the part you choose

`keep = "head"` (the default) keeps the start of `text` and is
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
itself, so a caller that switches to this function sends what it sent
before. `"tail"` keeps the end, with `marker` at the front. `"both"`
keeps the start and the end, about half the budget each, with `marker`
between them on a line of its own. `"scored"` splits the text into units
(the elements of `text` when it has more than one, else its paragraphs,
split at blank lines), keeps the units with the highest `scores` that
fit, and joins them with a blank line in their original order, followed
by `marker` when any unit was dropped; when no unit fits beside the
marker, the units that fit without it are kept with no marker. With
`marker = ""`, `"tail"` and `"both"` have the whole budget for text, as
`"head"` does; `"both"` keeps only the start when the end has no room,
and only the end when no word of the start fits. The result is never
longer than `n` tokens.

## Usage

``` r
hr_truncate(
  text,
  n,
  keep = c("head", "tail", "both", "scored"),
  scores = NULL,
  marker = " ...[truncated]",
  trace = NULL,
  where = "truncate",
  piece = NULL
)
```

## Arguments

- text:

  A single string; for `keep = "scored"`, a character vector of units is
  accepted as well.

- n:

  Maximum token count.

- keep:

  `"head"`, `"tail"`, `"both"` or `"scored"`.

- scores:

  For `keep = "scored"`: one number per unit, higher kept first. Ties
  keep the earlier unit.

- marker:

  The text that marks a cut; `""` for none. As in
  [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md),
  it is dropped when it would cost half the budget or more.

- trace:

  Optional `gr_trace` to write the cut to.

- where:

  The cut site, written to the trace, in the dotted style of call labels
  (`"refine.draft"`).

- piece:

  The name of the piece that was cut, written to the trace, or `NULL`.

## Value

A single string.

## Details

With a `trace`, a cut writes a `"truncate"` step that records `where`,
`piece`, `keep`, `dropped_part` (`"end"`, `"start"`, `"middle"`, or the
units dropped, as `"units 2, 5"`), the token counts before and after and
`tokens_dropped`. Nothing is written when the text fits.

## See also

[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

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
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)

## Examples

``` r
txt <- paste("Para", 1:6, "says something about revenue.", collapse = "\n\n")
hr_truncate(txt, 20)                      # the start, as hr_truncate_tokens()
#> [1] "Para 1 says something about revenue. ...[truncated]"
hr_truncate(txt, 20, keep = "tail")       # the end
#> [1] "...[truncated] Para 6 says something about revenue."
cat(hr_truncate(txt, 24, keep = "both"))  # both ends
#> Para 1 says
#> ...[truncated]
#> something about revenue.
# The paragraphs that score highest, in document order.
cat(hr_truncate(txt, 20, keep = "scored", scores = c(1, 9, 2, 8, 3, 4)))
#> Para 2 says something about revenue.
#> 
#> ...[truncated]

# The cut is written to a trace.
tr <- hr_trace()
invisible(hr_truncate(txt, 20, keep = "tail", trace = tr, where = "demo", piece = "notes"))
tr$steps[[1]]$detail[c("where", "piece", "dropped_part", "tokens_dropped")]
#> $where
#> [1] "demo"
#> 
#> $piece
#> [1] "notes"
#> 
#> $dropped_part
#> [1] "start"
#> 
#> $tokens_dropped
#> [1] 43
#> 
```
