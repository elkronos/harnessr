# Report a trigger for an effort escalation

Records an event a caller detects, such as a quotation that failed
verification (`"verify_failed"`), a decision left `"unclear"` or members
that disagree (`"disagreement"`), as an `"effort.event"` step of the
trace. An
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
policy reads it at the next stage boundary. Nothing is written unless an
escalation policy has already sent a request on this trace, so a run
without one records nothing new.

## Usage

``` r
hr_effort_event(trace, event, ...)
```

## Arguments

- trace:

  A `gr_trace`, or `NULL`.

- event:

  The trigger's name, one string.

- ...:

  Further detail for the step.

## Value

`TRUE` when the event was recorded, invisibly.

## See also

[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)

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
tr <- gr_trace()
hr_effort_event(tr, "disagreement")   # no policy has run: nothing recorded
```
