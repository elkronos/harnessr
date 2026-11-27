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
  order_merges = FALSE,
  marker = NULL,
  overflow = c("marker", "stubs"),
  stub_tokens = 200L,
  disclose_subset = FALSE
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

- marker:

  `NULL` (the default) for each packer's own marker, or the text that
  marks a cut, with `{tokens_dropped}` and `{units_dropped}` filled in.

- overflow:

  `"marker"` (the default): a piece cut away entirely leaves nothing
  behind. `"stubs"`: such pieces are listed by name and title in the
  fit's `notice`.

- stub_tokens:

  The most tokens the list of stubs may take; 200 by default. When that
  cannot hold one stub, the list is the header and `"- and N more"`
  alone.

- disclose_subset:

  `FALSE` (the default), `TRUE`, or a template with `{shown}` and
  `{total}`: the line added to the fit's `notice` when pieces were cut
  away.

- x:

  An `hr_context_policy`.

- ...:

  Ignored.

## Value

An object of class `hr_context_policy`: a list of `pin`, `cut_order`,
`keep` and `order_merges`, followed by `marker`, `overflow`,
`stub_tokens` and `disclose_subset` for those set away from their
defaults.

## Details

Three settings make a cut say what it removed. `marker` replaces the
text that marks a cut piece, and may hold `{tokens_dropped}` and
`{units_dropped}` (see
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)).
`overflow = "stubs"` lists the pieces cut away entirely by name, with
the titles the caller gives
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
in at most `stub_tokens` tokens, or as a count alone when that cannot
hold one; fetching one by its name is left to the caller.
`disclose_subset` adds one line when pieces were cut away, such as "12
of 40 studies shown; do not state totals": `TRUE` writes "`{shown}` of
`{total}` items shown; do not state totals.", and a string is used as
the template.
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
returns the list and the line as its `notice`, for the caller to place
in the request. A policy that leaves these three at their defaults is
the same object it was before they existed.

A pinned piece is never cut by the policy. When the pinned pieces alone
do not fit,
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
says so (`fits = FALSE`) and leaves the decision to its caller.

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
applies a policy to a set of pieces. In the document layer, a read takes
one as the `context_policy` setting of
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
and a write-up as the `context_policy` argument of
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md);
`NULL`, the default, keeps each packer's own cuts.

## See also

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)

Other cost and token functions:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
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
p <- hr_context_policy(pin = c("question", "instructions", "draft"),
                       keep = c(excerpt = "both", "head"))
p
#> <hr_context_policy>
#>   pin:          question, instructions, draft
#>   cut first:    -
#>   keep:         excerpt = both, head
#>   order merges: FALSE
# A policy that names what it leaves out.
hr_context_policy(marker = " [{tokens_dropped} tokens cut]", overflow = "stubs",
                  disclose_subset = "{shown} of {total} studies shown; do not state totals.")
#> <hr_context_policy>
#>   pin:          question, instructions
#>   cut first:    -
#>   keep:         head
#>   order merges: FALSE
#>   marker:       " [{tokens_dropped} tokens cut]"
#>   overflow:     stubs, in at most 200 tokens
#>   subset line:  "{shown} of {total} studies shown; do not state totals."
```
