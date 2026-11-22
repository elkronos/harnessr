# Fit named pieces of text into a token budget under a context policy

When the pieces together are longer than `budget` tokens, cuts them
under `policy`
([`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)):
pinned pieces are never cut; the pieces in `cut_order` are cut first, in
order, and then the others, the last piece first. Each piece is cut only
as far as the total needs, by
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
with the piece's keep rule, and a piece that must go entirely becomes
`""`. Each cut is written to `trace` as a `"truncate"` step with `where`
set to `"<where>.<piece>"`.

## Usage

``` r
hr_context_fit(
  pieces,
  budget,
  policy = hr_context_policy(),
  scores = NULL,
  trace = NULL,
  where = "context"
)
```

## Arguments

- pieces:

  A named character vector (or a named list of single strings), in the
  order the request carries them.

- budget:

  The most tokens the pieces may hold together.

- policy:

  An
  [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md).

- scores:

  For pieces cut with `keep = "scored"`: a list of score vectors named
  by piece. A piece without scores is cut with `"head"`.

- trace:

  Optional `gr_trace`.

- where:

  The packer's name, the start of each cut's `where`.

## Value

A list of `pieces` (named character, in the order given), `fits`
(whether they now fit; `FALSE` when the pinned pieces alone do not),
`tokens` (their total), `cut` (the names of the pieces cut) and
`tokens_dropped`.

## See also

[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)

Other cost and token functions:
[`gr_budget()`](https://elkronos.github.io/harnessr/reference/gr_budget.md),
[`gr_count_tokens()`](https://elkronos.github.io/harnessr/reference/gr_count_tokens.md),
[`gr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/gr_estimate_cost.md),
[`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md),
[`gr_model_limits()`](https://elkronos.github.io/harnessr/reference/gr_model_limits.md),
[`gr_models()`](https://elkronos.github.io/harnessr/reference/gr_models.md),
[`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md),
[`gr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_set_tokenizer.md),
[`gr_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_tokenizer.md),
[`gr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/gr_truncate_tokens.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)

## Examples

``` r
pieces <- c(question = "What was revenue?",
            draft = paste(rep("Revenue rose.", 30), collapse = " "),
            excerpt = paste(rep("Costs fell.", 30), collapse = " "))
fit <- hr_context_fit(pieces, 80, hr_context_policy(pin = c("question", "draft")))
vapply(fit$pieces, gr_count_tokens, numeric(1))
#> question    draft  excerpt 
#>        7       93        0 
fit$cut
#> [1] "excerpt"
```
