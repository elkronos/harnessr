# Validate a judge against blind human labels

Compares a judge's binary decisions with blind human labels on the same
items and records how far they agree, for one judge configuration.
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
scores with a judge only when such a record exists for its configuration
and `hr_judge_valid()` says it still holds.

## Usage

``` r
hr_judge_validate(
  judge_config,
  labels,
  n_pos_min = 50,
  n_neg_min = 50,
  positive = NULL,
  B = 2000,
  conf = 0.95,
  seed = 1
)

hr_judge_valid(validation, judge_config)

# S3 method for class 'hr_judge_validation'
print(x, ...)
```

## Arguments

- judge_config:

  An
  [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md).

- labels:

  A data frame with one row per item and the columns

  `judge`

  :   The judge's decision: `positive` or another value, `NA` when it
      was unresolved or failed.

  `human`

  :   The blind human label on the same scale; rows with `NA` are left
      out.

  `consistent`

  :   Optional. `FALSE` where the judge's verdict changed with the
      order.

  `outcome`

  :   Optional, used when `consistent` is absent: the judgement's
      outcome; `"unresolved"` marks an inconsistent item and `"failed"`
      an item with no swap check. With neither column, every `NA` in
      `judge` is taken as inconsistent.

  `config_hash`

  :   Optional. When given, every row must carry the configuration's
      hash: labels on another configuration's outputs are refused.

  Columns are matched by their exact names, and other columns are
  ignored: a column named `consistently_long` is not read as
  `consistent`.

- n_pos_min, n_neg_min:

  The fewest human-positive and human-negative items accepted; 50 or
  more.

- positive:

  The value of `judge` and `human` that counts as positive. Both columns
  must be on one scale: when no resolved `judge` value occurs in `human`
  (logical judge calls beside `"pass"`/`"fail"` labels, say), the call
  stops with `gr_bad_setting`. `NULL` (the default) takes the
  configuration's positive grade (such as `"pass"`) when the
  configuration is in mode `"grade"` and the `judge` or `human` column
  holds text, and `TRUE` otherwise.

- B:

  Bootstrap resamples for the kappa interval.

- conf:

  Confidence level of every interval.

- seed:

  Seed for the bootstrap.

- validation:

  An `hr_judge_validation`.

- x:

  An `hr_judge_validation`.

- ...:

  Ignored.

## Value

`hr_judge_validate()` returns an object of class `hr_judge_validation`:
a list of `config_hash`, `config` (the keyed parts), `n` (items with a
human label), `n_pos`, `n_neg`, `n_unresolved`, `n_dropped` (rows
without a human label), `kappa`, `sensitivity` and `specificity`
(one-row data frames: `estimate`, `lower`, `upper`, and `n` for the
rates), `sens_halfwidth`, `swap_inconsistency` (`x`, `n`, `estimate`,
`lower`, `upper`), `agreement` (the
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
object), `conf`, `validated_at` (UTC) and `hash`. `hr_judge_valid()`
returns `TRUE` or `FALSE`.

## Details

The record gives, over every item with a human label:

- Cohen's kappa between judge and human, with a percentile bootstrap
  interval, and the full
  [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
  set beside it (kappa is never read alone);

- sensitivity (the share of human positives the judge called positive)
  and specificity, with Wilson intervals, and the half-width of the
  sensitivity interval;

- the swap-inconsistency rate: the share of judged items whose verdict
  changed with the presentation order, with a Wilson interval (`NA` for
  a one-order judge). Swap inconsistency is the position-bias measure of
  Zheng et al. (2023).

At least 50 human-positive and 50 human-negative items are required, and
a smaller sample is refused with an error of class
`hr_judge_too_few_labels`. A bare total is not enough: at 10% prevalence
100 labels hold 10 positives, and the sensitivity interval is then about
plus or minus 0.3. The minimums cannot be set below 50.

Items the judge left unresolved or failed on (`judge` is `NA`) are
scored as the judge not calling them positive, which is how
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
counts them: an unresolved verdict is a wrong run there. Kappa,
sensitivity and specificity therefore describe the judge as the scorer
uses it, and items the judge cannot settle lower them rather than drop
out. The rates' denominators are the class sizes the minimums are
checked against. These items also count in the swap-inconsistency rate
and are reported in `n_unresolved`.

The record is keyed by the configuration's hash. `hr_judge_valid()` is
`FALSE`, with the reason in `attr(, "reason")`, when the configuration
differs in any keyed part (model, mode, rubric, the package's prompt,
schema, orders, aggregation, positive grade), or when the record was
changed after it was made.

Whether the agreement is good enough for a given use is a decision to
register before labelling, for example lower bounds on kappa,
sensitivity and specificity and a swap-inconsistency rate of at most
10%. This function measures; it does not admit.

## References

Cohen, J. (1960). A coefficient of agreement for nominal scales.
*Educational and Psychological Measurement* 20(1), 37-46.

Wilson, E. B. (1927). Probable inference, the law of succession, and
statistical inference. *Journal of the American Statistical Association*
22(158), 209-212.

Zheng, L. et al. (2023). Judging LLM-as-a-judge with MT-Bench and
Chatbot Arena. *Advances in Neural Information Processing Systems* 36.

## See also

[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md)

Other judges:
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

## Examples

``` r
cfg <- hr_judge_config("mock-model", "Does the response give the reference's answer?",
                       mode = "grade")
set.seed(3)
human <- rep(c(TRUE, FALSE), c(60, 60))
judge <- ifelse(runif(120) < 0.9, human, !human)
judge[c(5, 70)] <- NA   # two items unresolved
v <- hr_judge_validate(cfg, data.frame(judge = judge, human = human), B = 200)
v
#> <hr_judge_validation> config 76e45eaf9cc6 (grade, mock-model)
#>   items: 120 labelled (60 positive, 60 negative), 2 unresolved, 0 dropped
#>   kappa:       0.850 [0.750, 0.950]
#>   sensitivity: 0.933 [0.841, 0.974], n = 60, half-width 0.067
#>   specificity: 0.917 [0.819, 0.964], n = 60
#>   swap inconsistency: 0.017 [0.005, 0.059], 2 of 120
hr_judge_valid(v, cfg)
#> [1] TRUE
# A new rubric voids the record.
cfg2 <- hr_judge_config("mock-model", "Is the response right?", mode = "grade")
hr_judge_valid(v, cfg2)
#> [1] FALSE
#> attr(,"reason")
#> [1] "the judge configuration changed since validation (rubric)"
```
