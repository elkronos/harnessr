# A rule for scoring an arm's output

A scorer is a function `fn(item, output, label)` that
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
calls once per run of an arm on an item. `item` is the item's payload,
`output` what the arm returned, and `label` the item's label from
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).
It returns a list of

- `correct`:

  `TRUE`, `FALSE`, or `NA` when the item cannot be scored (it has no
  label).

- `outcome`:

  What the scorer saw, as one string (for the exact scorer, the answer
  as compared), or `NA`.

- `failure_kind`:

  Why a wrong output was wrong: `"parse_failure"`, `"refusal"`,
  `"not_in_document"`, `"wrong"`, `"budget_stop"` or `"error"`. `NA`
  when the output was correct.

A wrong output whose `failure_kind` is `NA` is recorded as `"wrong"`. An
output with a `failure_kind` is counted wrong, so a `correct` of `NA`
beside one is recorded as `FALSE`, and `TRUE` beside one is an error in
the scorer. The exception is an item with no label: every run on it is
recorded `NA`, with its `failure_kind` kept.

## Usage

``` r
hr_scorer(fn, name)

hr_scorer_exact(normalise = TRUE)
```

## Arguments

- fn:

  A function of `(item, output, label)` returning the list above.

- name:

  The scorer's name, one string; it is recorded with the benchmark.

- normalise:

  `TRUE` to fold case and white space before comparing.

## Value

An object of class `hr_scorer`: a list of `name` and `fn`.

## Details

`hr_scorer_exact()` compares the output's text with the label, and is
the default scorer. The text is `output` itself when it is one string,
or its `answer` or `text` element when it is a list (a
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md)
has `text`). A label may hold several accepted answers; matching any one
is correct. A number in a label is compared as written in plain digits,
so the label `100000` accepts `"100000"` (not `"1e+05"`). With
`normalise = TRUE` both sides are folded first: lower case, white space
trimmed and runs of it collapsed to one space. Before comparing, it
sorts out the outputs that are not answers:

- an output with a `failure_kind` element from the list above is wrong
  for that reason, so an arm can report a refusal or a parse failure
  itself;

- a
  [gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md)
  with `ok = FALSE` is an `"error"`;

- no text at all (`NULL`, `NA`, an empty string, something with no
  `answer` or `text`) is a `"parse_failure"`;

- the text `NOT_IN_DOCUMENT` (in any case) is `"not_in_document"` unless
  the label accepts it.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)

## Examples

``` r
exact <- hr_scorer_exact()
exact$fn("Capital of France?", "  paris ", "Paris")
#> $correct
#> [1] TRUE
#> 
#> $outcome
#> [1] "paris"
#> 
#> $failure_kind
#> [1] NA
#> 
exact$fn("Capital of France?", "Lyon", "Paris")$failure_kind
#> [1] "wrong"

# A scorer of your own: a number within 1% of the label.
near <- hr_scorer(function(item, output, label) {
  x <- suppressWarnings(as.numeric(output))
  if (is.na(x)) return(list(correct = FALSE, outcome = NA, failure_kind = "parse_failure"))
  list(correct = abs(x - label) <= 0.01 * abs(label), outcome = format(x),
       failure_kind = NA)
}, name = "within_1pct")
near$fn(NULL, "45.3", 45.2)
#> $correct
#> [1] TRUE
#> 
#> $outcome
#> [1] "45.3"
#> 
#> $failure_kind
#> [1] NA
#> 
```
