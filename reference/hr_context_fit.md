# Fit named pieces of text into a token budget under a context policy

When the pieces together are longer than `budget` tokens, cuts them
under `policy`
([`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)):
pinned pieces are never cut; the pieces in `cut_order` are cut first, in
order, and then the others, the last piece first. Each piece is cut only
as far as the total needs, by
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
with the piece's keep rule and the policy's `marker`, and a piece that
must go entirely becomes `""`. Each cut is written to `trace` as a
`"truncate"` step with `where` set to `"<where>.<piece>"`.

## Usage

``` r
hr_context_fit(
  pieces,
  budget,
  policy = hr_context_policy(),
  scores = NULL,
  trace = NULL,
  where = "context",
  titles = NULL
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

- titles:

  For `overflow = "stubs"`: a character vector of titles named by piece,
  written after each stub's name. A piece without a title is listed by
  name alone.

## Value

A list of `pieces` (named character, in the order given), `fits`
(whether they now fit with the notice; `FALSE` when the pinned pieces
alone do not), `tokens` (their total, the notice's included), `cut` (the
names of the pieces cut), `tokens_dropped`, `omitted` (the names of the
unpinned pieces cut away entirely) and `notice` (the subset line and
stubs, or `""`).

## Details

Under a policy with `overflow = "stubs"` or `disclose_subset`, room for
the `notice` is set aside before anything is cut, and the notice names
the unpinned pieces cut away entirely: the subset line first, then the
stubs, one line each, `"- <name>: <title>"`, with `"- and N more"` for
those the stub cap leaves out. The pieces and the notice together stay
within `budget` whenever the pinned pieces fit. When `stub_tokens`
cannot hold one stub, the stubs shrink to the header and
`"- and N more"`. The room set aside is at most half of `budget`, so the
notice is `""` when nothing was cut away, when the policy asks for
neither, or when that room cannot hold the subset line or that shortest
list; placing it in the request is the caller's job.

## See also

[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
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
pieces <- c(question = "What was revenue?",
            draft = paste(rep("Revenue rose.", 30), collapse = " "),
            excerpt = paste(rep("Costs fell.", 30), collapse = " "))
fit <- hr_context_fit(pieces, 80, hr_context_policy(pin = c("question", "draft")))
vapply(fit$pieces, hr_count_tokens, numeric(1))
#> question    draft  excerpt 
#>        7       93        0 
fit$cut
#> [1] "excerpt"

# Studies as pieces: the ones left out are named, with their titles.
studies <- setNames(paste("Study", 1:8, paste(rep("findings", 20), collapse = " ")),
                    paste("study", 1:8))
pol <- hr_context_policy(overflow = "stubs",
  disclose_subset = "{shown} of {total} studies shown; do not state totals.")
fit <- hr_context_fit(c(question = "What was found?", studies), 150, pol,
                      titles = setNames(paste("Trial", 1:8), names(studies)))
cat(fit$notice)
#> 2 of 8 studies shown; do not state totals.
#> Left out for space:
#> - study 3: Trial 3
#> - study 4: Trial 4
#> - study 5: Trial 5
#> - study 6: Trial 6
#> - study 7: Trial 7
#> - and 1 more
```
