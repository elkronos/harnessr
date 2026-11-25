# Score benchmark runs with a validated judge

An
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
that grades each run's output against the item's label with a grade-mode
judge. It is built only for a configuration that has a validation record
[`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
accepts; without one it refuses with an error of class
`hr_judge_unvalidated`, since an unvalidated judge's decisions are not
evidence of accuracy.

## Usage

``` r
hr_scorer_judge(
  judge_config,
  validation,
  client,
  governor = NULL,
  draw_index = 0L,
  judge_model = judge_config$model
)
```

## Arguments

- judge_config:

  A grade-mode
  [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md).

- validation:

  Its
  [`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  record.

- client:

  The `gr_client` the judge calls.

- governor:

  Optional
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  for the judge's requests.

- draw_index:

  Draw index passed to every judge request (see
  [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)).
  With a caching client and a fixed index, identical outputs graded
  against the same label reuse one cached verdict; give another index
  for a fresh judge draw.

- judge_model:

  The model the judge runs on, as the arms' traces would name it: by
  default the configuration's `model`.
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  compares it with the model and served model of each run's requests and
  records the result as `self_judged`. Give the served model id when the
  provider names it differently from the configuration, so the
  comparison can match it. `NA` records no comparison.

## Value

An `hr_scorer` with three more elements: `trace`, the judge's
`gr_trace`, `config_hash` and `judge_model`.

## Details

Each output is graded in the configuration's orders with the label as
the reference (several accepted answers are listed). A run is right when
the judgement is answered with the configuration's positive grade. A run
the judge left unresolved is wrong with outcome `"judge_unresolved"`,
and one it failed on is an `"error"` with outcome `"judge_failed"`:
counting them wrong keeps the arm's accuracy from rising on the items
the judge could not settle. Outputs that report their own failure, or
have no text, are sorted as
[`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
sorts them, with no judge call.

The judge's requests are recorded in the scorer's own trace (`$trace`),
held to `governor`, and never in the runs' traces, so a benchmark's cost
columns leave judging out. Accuracy estimated by a judge should be
reported corrected against human labels, with
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md).

## Self-judging

A model grading its own output can favour it. `hr_scorer_judge()` never
refuses such a pairing, since a provider may offer only one capable
model, but
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
marks each run graded by a judge on the arm's own model in
`self_judged`, and
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
says so in its notes. The match is exact: a model id that differs by a
date or a version suffix is a different model to it.

## See also

[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md)

Other judges:
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)

## Examples

``` r
cfg <- hr_judge_config("mock-model", "Does the response give the reference's answer?",
                       mode = "grade")
try(hr_scorer_judge(cfg, NULL, hr_mock_client()))
#> Error in hr_scorer_judge(cfg, NULL, hr_mock_client()) : 
#>   This judge has no valid validation record: no validation record from hr_judge_validate(). Validate the configuration against blind human labels with hr_judge_validate() first.

set.seed(3)
human <- rep(c(TRUE, FALSE), c(60, 60))
v <- hr_judge_validate(cfg, data.frame(judge = ifelse(runif(120) < 0.9, human, !human),
                                       human = human), B = 200)
grader <- hr_mock_client(function(messages, params) {
  txt <- messages[[2]]$content
  ok <- grepl("Response to grade:\nParis", txt, fixed = TRUE)
  sprintf('{"verdict": "%s", "reason": "."}', if (ok) "pass" else "fail")
})
sc <- hr_scorer_judge(cfg, v, grader)
sc$fn("Capital of France?", "Paris", "Paris")$correct
#> [1] TRUE
sc$fn("Capital of France?", "Lyon", "Paris")$correct
#> [1] FALSE
```
