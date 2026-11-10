# A judge configuration

Everything that decides what a judge answers, held in one object with a
hash: the model, the mode, the rubric, the package's instructions for
that mode, the reply schema, the number of presentation orders, how
their verdicts are combined (`"unanimous"`: every order must agree) and,
for grading, which grade counts as positive.
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
keys its record by this hash, and
[`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
says a record no longer holds once any part of it differs.

## Usage

``` r
hr_judge_config(
  model,
  rubric,
  mode = c("select", "grade", "pairwise"),
  orders = 2,
  schema = NULL,
  positive = NULL
)

# S3 method for class 'hr_judge_config'
print(x, ...)
```

## Arguments

- model:

  The judge's model, one string.

- rubric:

  What the judge is to decide, in words, one string.

- mode:

  `"select"` (choose one of several candidates), `"grade"` (grade one
  response against a reference) or `"pairwise"` (A, B or a tie).

- orders:

  How many presentation orders each item is judged in.

- schema:

  `NULL` for the default reply schema, or a JSON schema (a list) with a
  string `verdict` property.

- positive:

  For `"grade"`, the grade that counts as positive (the response is
  right); the first allowed grade by default. Ignored for the other
  modes.

- x:

  An `hr_judge_config`.

- ...:

  Ignored.

## Value

An object of class `hr_judge_config`: a list of `model`, `mode`,
`rubric`, `prompt` (the package's instructions for the mode), `schema`,
`orders`, `aggregation`, `positive`, `grades` and `hash` (SHA-256 of the
others).

## Details

Orders: with `orders = 2` the candidates are shown in their given order
and then reversed; for `"grade"` the reference comes first and then the
response first. With more than two candidates in `"select"`, `orders`
above 2 shows that many cyclic rotations, since a forward and a reversed
order leave the middle positions where they were. `orders = 1` is
allowed only for `"grade"`, and such a judge has no swap check.

The reply is JSON with a string `verdict` and a `reason`. For `"select"`
the verdict is a candidate's letter, for `"pairwise"` `"A"`, `"B"` or
`"tie"`, and for `"grade"` one of the grades, `"pass"` or `"fail"`
unless `schema` gives others as the `enum` of its `verdict` property. A
`schema` of your own must be an object schema with a string `verdict`
property.

## See also

[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

Other judges:
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

## Examples

``` r
cfg <- hr_judge_config("mock-model", "Is the response's answer the reference's?",
                       mode = "grade")
cfg
#> <hr_judge_config be8928d73564> grade, 2 order(s), unanimous
#>   model: mock-model
#>   grades: pass, fail (positive: pass)
#>   rubric: Is the response's answer the reference's?
# Another rubric is another configuration.
other <- hr_judge_config("mock-model", "Is the response fully correct?", mode = "grade")
identical(cfg$hash, other$hash)
#> [1] FALSE
```
