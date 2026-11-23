# Reasoning effort that is raised for the next stage when a trigger fires

A policy for a call's `effort`
([`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md))
or a read's `effort_mode`
([`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)).
Every stage starts at `base` (one level, or a map named by call stem,
resolved as a static effort is). When a trigger in `on` fired during a
stage, the next stage is sent at `to`. The stage after a raised one goes
back to `base` unless a trigger fired in the raised stage too and a
raise is left: at most `max_escalations` raises happen in one run (one
trace), so at the default of 1 it always goes back. A stage is a call
label up to its second dot, with a merge level (`.level2`), a summary
level (`.L2`) and a judge's order (`.o2`) left off, so `map.answer` and
`reduce` are stages and `reduce.level1` belongs to `reduce`.

## Usage

``` r
hr_effort_escalate(
  base = "low",
  to = "high",
  on = .hr_escalate_triggers,
  max_escalations = 1L,
  replies = NULL
)

# S3 method for class 'hr_effort_escalate'
print(x, ...)
```

## Arguments

- base:

  The starting effort: one level, or a character vector named by call
  stem.

- to:

  The raised effort, one level.

- on:

  The triggers that raise the next stage.

- max_escalations:

  The most raises in one run.

- replies:

  `NULL`, or a named character vector from trigger name to the text a
  reply that signals it starts with.

- x:

  An `hr_effort_escalate`.

- ...:

  Ignored.

## Value

An object of class `hr_effort_escalate`.

## Details

The triggers the core sees for itself are `"truncated"` (a `"truncate"`
step of the trace, or a reply cut off at its output cap; a cut made
while a stage packs its requests belongs to that stage, including one
made before its first request), `"parse_failure"` (a reply to a
structured request, such as `ctx$call_json()`, that is not JSON) and
`"schema_failure"` (one that does not fit the schema). `replies` names
replies that are triggers: a named character vector from trigger to the
text a reply starts with, such as
`c(not_in_document = "NOT_IN_DOCUMENT")`; such a trigger fires when
every request of the stage replied with it. Other triggers
(`"verify_failed"`, `"unclear"`, `"disagreement"`, or any name of your
own) fire when the caller reports them with
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md).

The state lives on the run's trace, so a call without a trace is sent at
`base`. Each raise writes an `"effort.escalate"` step naming the
triggers, the stage they fired in and the stage raised; when the raised
stage ends, an `"effort.resolve"` step says whether it fired the same
triggers again.
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)
returns both as a table.

## See also

[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
for `effort_mode`

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
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
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
pol <- hr_effort_escalate(base = "low", to = "high",
                          replies = c(not_in_document = "NOT_IN_DOCUMENT"))
pol
#> <hr_effort_escalate>
#>   base: low; raised to high for the next stage, at most 1 time(s) a run
#>   on:   truncated, parse_failure, schema_failure, verify_failed, not_in_document, unclear, disagreement

# A first stage that found nothing raises the second.
cl <- gr_mock_client(function(m, p) {
  if (identical(p$effort, "low") && grepl("first", m[[1]]$content)) {
    return("NOT_IN_DOCUMENT")
  }
  paste("done at", p$effort)
})
tr <- gr_trace()
gr_call(cl, "first step", model = "gpt-5.6-luna", trace = tr, label = "plan.draft",
        effort = pol)$text
#> [1] "NOT_IN_DOCUMENT"
gr_call(cl, "second step", model = "gpt-5.6-luna", trace = tr, label = "plan.final",
        effort = pol)$text
#> [1] "done at high"
hr_effort_log(tr)
#>        after      stage        triggers   to calls resolved
#> 1 plan.draft plan.final not_in_document high     1     TRUE
```
