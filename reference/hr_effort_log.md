# The effort raises of a run

One row per raise an
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
policy made on a trace: `after` (the stage the triggers fired in),
`stage` (the stage sent raised), `triggers`, `to` (the raised effort),
`calls` (the requests the raised stage sent) and `resolved` (whether the
raised stage fired none of the same triggers). A raise whose stage is
the last of the run is settled from the trace as it is now.

## Usage

``` r
hr_effort_log(trace)
```

## Arguments

- trace:

  A `gr_trace`.

## Value

A data frame, with no rows when nothing was raised.

## See also

[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)

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
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md),
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
hr_effort_log(gr_trace())
#> [1] after    stage    triggers to       calls    resolved
#> <0 rows> (or 0-length row.names)
```
