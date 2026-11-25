# Truncate text to at most `n` tokens

The result is the start of `text` as written (line breaks, indentation
and paragraph breaks kept), followed by `marker`. The cut falls at the
end of a word where the text has whitespace. When the next unit is too
long to be a word (a CJK run, base64, a data URI, minified JSON, a long
URL: anything that alone would cost more than 16 tokens) the cut goes
inside it at a character, so a long unbroken run fills the budget
instead of being dropped whole; otherwise the cap would be
unenforceable, or nearly all of it wasted, for exactly the inputs that
most need it. Returns `""` for empty input and never returns `NA`.

## Usage

``` r
hr_truncate_tokens(text, n, marker = " ...[truncated]")
```

## Arguments

- text:

  A single string.

- n:

  Maximum token count.

- marker:

  Appended when truncation occurred; set `""` to suppress. It is dropped
  when it would cost half the budget or more.

## Value

A single string. `""` when `n <= 0` or the input is blank. This is not
treated as an error.

## See also

[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md)

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
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)

## Examples

``` r
hr_truncate_tokens(paste(rep("alpha beta gamma", 40), collapse = " "), 20)
#> [1] "alpha beta gamma alpha beta gamma alpha ...[truncated]"
hr_truncate_tokens("short enough already", 100)
#> [1] "short enough already"

# A table keeps its rows.
cat(hr_truncate_tokens("Arm | N | Events\nA | 482 | 31\nB | 479 | 44\nC | 470 | 50", 24))
#> Arm | N | Events
#> A | 482 | ...[truncated]
```
