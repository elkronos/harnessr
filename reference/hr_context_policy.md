# Rules for what a request keeps when its text does not fit

A context policy tells a packer, the code that fits named pieces of text
into a request, what to do when they do not fit. `pin` names the pieces
that are never cut, such as the question and the instructions.
`cut_order` names the pieces cut first, in order; the pieces it does not
name are cut after them, the last piece of the request first. `keep`
says which part of a cut piece is kept (see
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)):
one rule for every piece, or a character vector named by piece, with an
unnamed element as the rule for the pieces it does not name.
`order_merges = TRUE` asks the packers that merge findings to place them
by the read's `context_order` as well; see
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
for which packers those are.

## Usage

``` r
hr_context_policy(
  pin = c("question", "instructions"),
  cut_order = character(0),
  keep = "head",
  order_merges = FALSE
)

# S3 method for class 'hr_context_policy'
print(x, ...)
```

## Arguments

- pin:

  Names of pieces that are never cut.

- cut_order:

  Names of pieces cut first, in order.

- keep:

  `"head"`, `"tail"`, `"both"` or `"scored"`, or a character vector of
  them named by piece.

- order_merges:

  Whether merge packers follow `context_order`.

- x:

  An `hr_context_policy`.

- ...:

  Ignored.

## Value

An object of class `hr_context_policy`: a list of `pin`, `cut_order`,
`keep` and `order_merges`.

## Details

A pinned piece is never cut by the policy. When the pinned pieces alone
do not fit,
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
says so (`fits = FALSE`) and leaves the decision to its caller.

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
applies a policy to a set of pieces. In the document layer, a read takes
one as the `context_policy` setting of
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md);
`NULL`, the default, keeps each reader's own cuts.

## See also

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)

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
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)

## Examples

``` r
p <- hr_context_policy(pin = c("question", "instructions", "draft"),
                       keep = c(excerpt = "both", "head"))
p
#> <hr_context_policy>
#>   pin:          question, instructions, draft
#>   cut first:    -
#>   keep:         excerpt = both, head
#>   order merges: FALSE
```
