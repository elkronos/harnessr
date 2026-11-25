# Count tokens in text

Vectorised over `text`. Always returns a non-negative integer vector of
the same length; blank and `NA` entries count as 0.

## Usage

``` r
hr_count_tokens(text, model = NULL)
```

## Arguments

- text:

  Character vector.

- model:

  Optional model id; used only by tokenizers that are encoding-specific
  (e.g. `"tiktoken"`).

## Value

Integer vector of token counts: under the default tokenizer, an estimate
built to err high (see above for the one kind of text where it can fall
short).

## Details

The default `"heuristic"` tokenizer is a deliberate **over-estimate**,
not an exact count: it classifies each word, sums the per-script
contributions, and adds a small per-message framing allowance. For
numbers, tables, code and short lines it also counts the pieces a BPE
tokenizer splits text into first (digit groups, punctuation runs, line
breaks, indentation) and keeps the larger figure, line by line.
Overcounting wastes a little context; undercounting produces a hard API
failure after you have paid for the request. Rare long words (technical
and medical vocabulary) can still come in under the real count, by about
a tenth for a table of medical terms; that is what the `safety_margin`
of
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
is for.

For counts from OpenAI's own tokenizer install reticulate plus Python
`tiktoken` and call `hr_set_tokenizer("tiktoken")`. Given `model`, it
counts in that model's encoding. Without one, which is how the package's
own budgets call it, it counts in both encodings current OpenAI models
use (`cl100k_base` and `o200k_base`) and keeps the larger, so the count
holds for any of them. Models from other providers tokenize differently,
and for them it is an estimate without the heuristic's padding. Text
that spells a special token (`<|endoftext|>`, in a paper about language
models) is counted as the plain text it is.

## See also

[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md),
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
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
hr_count_tokens(c("the quick brown fox", "", "a much longer sentence than that one"))
#> [1]  8  0 12

# Compare tokenizers on the same text.
old <- hr_tokenizer()
vapply(c("heuristic", "words", "chars"), function(t) {
  hr_set_tokenizer(t); hr_count_tokens("the quick brown fox jumps")
}, integer(1))
#> heuristic     words     chars 
#>         9         5         7 
hr_set_tokenizer(old)
```
