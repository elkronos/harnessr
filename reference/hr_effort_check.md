# Compare an effort policy with fixed efforts on a benchmark

Tests whether the `candidate` arm (an
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
policy, say) is non-inferior to each of the `comparators` (fixed
efforts, say), with
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)'s
non-inferiority test at `margin` and Holm's procedure over the
comparisons, and reports what each arm cost, the requests sent at a
raised effort included.

## Usage

``` r
hr_effort_check(
  bench,
  candidate,
  comparators = NULL,
  margin = 0.05,
  registration = NULL,
  cost_test = TRUE,
  B = 2000,
  seed = 1
)

# S3 method for class 'hr_effort_check'
print(x, ...)
```

## Arguments

- bench:

  An
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  result.

- candidate:

  The arm under test, one name.

- comparators:

  The arms it is compared with; every other arm when `NULL`.

- margin:

  The non-inferiority margin, a proportion in (0, 1).

- registration:

  `NULL`, or an
  [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  result.

- cost_test:

  Whether a verdict also needs `candidate` to be cheaper (for contrasts
  built here).

- B, seed:

  Bootstrap resamples and seed, passed to
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md).

- x:

  An `hr_effort_check`.

- ...:

  Ignored.

## Value

An object of class `hr_effort_check`, a list of

- `contrasts`:

  One row per comparison: `new`, `reference`, `label`, `margin`,
  `estimate`, `lower`, `level`, `accuracy_holds`, `cost_diff`,
  `cost_upper`, `cost_holds`, `verdict` and `p_value`, from
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)'s
  `ni` table.

- `cost`:

  One row per arm: `arm`, `accuracy` (the mean of `correct` over
  reportable rows), `usd` (mean per run, `NA` when a run has no price),
  `calls` (model requests per run), `escalations` (raises per run),
  `escalated_calls` (requests per run sent at a raised effort) and
  `resolved` (the share of raises whose stage fired none of the same
  triggers again, `NA` with none), then `priced`, `as_of` and `certain`,
  where `usd`'s prices came from, as in
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)'s
  `cost` table.

- `best_fixed`:

  The most accurate comparator.

- `post_hoc`:

  `TRUE` when no registration was given.

- `report`:

  The
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  the contrasts come from.

## Details

With a `registration` from
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
made before the benchmark ran, its contrasts with `candidate` as `new`
are the ones tested, at their registered margins, and the result is
confirmatory. Without one, the contrasts are built here from
`candidate`, `comparators` and `margin`, all confirmatory so Holm's
procedure covers them, and the result is marked post hoc
(`post_hoc = TRUE`): the margin was stated after the benchmark was
scored, so it is evidence for a decision to run a registered comparison,
not a verdict. Either way the benchmark's rows must be on the test or
final split, as
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
requires for a test.

The cost table reads each run's trace: the requests it sent, the raises
an escalation policy made
([`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md))
and the requests the raised stages sent. Its `usd` is the run's cost
from the benchmark, which already counts every request, raised or not.

## See also

[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
ref <- hr_reference(sprintf("q%02d", 1:40), labels = rep("yes", 40),
                    cluster = sprintf("c%02d", rep(1:20, each = 2)), split = "test")
arm_at <- function(name, effort) {
  hr_arm(name, function(item, ctx) {
    tr <- ctx$trace
    a <- hr_call(ctx$client, paste("first", item), model = "gpt-5.6-luna", trace = tr,
                 label = "task.draft", effort = effort)
    b <- hr_call(ctx$client, paste("final", item), model = "gpt-5.6-luna", trace = tr,
                 label = "task.final", effort = effort)
    b$text
  })
}
# Four hard items: the first step finds nothing at low effort, and the
# answer is wrong unless the final step reasons at high effort.
cl <- hr_mock_client(function(m, p) {
  hard <- grepl("q0[1-4]", m[[1]]$content)
  if (grepl("first", m[[1]]$content) && hard) return("NOT_IN_DOCUMENT")
  if (hard && identical(p$effort, "low")) "no" else "yes"
})
esc <- hr_effort_escalate(replies = c(not_in_document = "NOT_IN_DOCUMENT"))
arms <- list(arm_at("low", "low"), arm_at("high", "high"), arm_at("escalate", esc))
bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
                      governor = hr_governor(max_calls = 2000, max_cost_usd = 5))
chk <- hr_effort_check(bench, "escalate", margin = 0.1, cost_test = FALSE, B = 200)
chk
#> <hr_effort_check> escalate against low, high (post hoc: no registration)
#>   vs low          margin 10.0 pts, difference +10.0 pts, lower bound -6.7: non-inferior
#>   vs high         margin 10.0 pts, difference +0.0 pts, lower bound -9.9: non-inferior
#>   best fixed comparator: high
#>       arm accuracy usd calls escalations escalated_calls resolved priced as_of
#>       low      0.9  NA     2         0.0             0.0       NA  FALSE  <NA>
#>      high      1.0  NA     2         0.0             0.0       NA  FALSE  <NA>
#>  escalate      1.0  NA     2         0.1             0.1        1  FALSE  <NA>
#>  certain
#>     TRUE
#>     TRUE
#>     TRUE
#>   usd is NA for low, high, escalate: no price set for a model of those arms (set one with hr_register_model() or hr_load_models())
```
