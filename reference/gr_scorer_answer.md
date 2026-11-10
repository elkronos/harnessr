# Score a reading recipe's answer against acceptable answers

An
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
for the
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)s
that
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
returns, against a reference from
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md).
An answer is right when its text contains any of the item's acceptable
answers, after both are folded the same way: lower case, runs of white
space as one space, and thousands separators dropped between digits, so
`"1,204"`, `"1 204"` (with a no-break or thin space) and `"1204"` are
the same. A number in a label is written in plain digits, so the label
`100000` accepts `"100,000"`. A number is matched whole: `"45.2"` is not
found in `"145.2"` or `"45.25"`, and `"12"` is not found in `".12"` (the
decimal 0.12) or in `"-12"`. A unit written against a number does not
hide it (`"45.2m"` and `"5mg"` contain `"45.2"` and `"5"`), and a hyphen
between two numbers is a range, not a minus sign (`"12-15"` contains
`"15"`). On an unanswerable item, labelled `"NOT_IN_DOCUMENT"`, the
answer is right when
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
says it reports the document does not hold the answer.

## Usage

``` r
gr_scorer_answer()
```

## Value

An
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
named `"answer_contains"`.

## Details

An answer that is not right gets the first of these failure kinds that
applies:

- `"parse_failure"`:

  There is no answer text: the output is not a string or has no `answer`
  or `text`, or the text is blank.

- `"budget_stop"`:

  The answer is `partial` and notes that a limit stopped it: the
  spending limit (`cost_cap_reached`), the call limit
  (`call_cap_reached`), or another limit that refused a request
  (`limit_refused`).

- `"refusal"`:

  A model refused a request of the run: a step of the answer's trace
  finished with reason `"refusal"` or `"content_filter"`, or the output
  is a refused
  [gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md).

- `"not_in_document"`:

  An answer was expected and the reader said the document does not hold
  one.

- `"wrong"`:

  Anything else, an answer to an unanswerable question included.

An output that carries its own `failure_kind` keeps it, and a failed
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md)
is an `"error"`, as with
[`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md).
A stopped or refused run that still found an acceptable answer is right.
A not-found answer from a run that was stopped or refused is that stop
on an unanswerable item as well: a reader that ran out of budget did not
look.

The `outcome` is the answer's folded text.

## See also

[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
s <- gr_scorer_answer()
item <- list(question = "How many units?", document = gr_example())
s$fn(item, "Sheffield produced 12,400 units.", "12400")$correct
#> [1] TRUE
s$fn(item, "NOT_IN_DOCUMENT", "12400")$failure_kind
#> [1] "not_in_document"
s$fn(item, "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT")$correct
#> [1] TRUE
```
