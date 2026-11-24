# List the settings of a step or a chain

`hr_settings()` lists every setting that
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
can change: one row per setting of each step's schema, with the value
the step resolved it to, whether it was given or left at its default,
and what the schema declares about it (default, range, type, tier and
evidence). In a chain a setting is named by its path, `"step.setting"`,
as in
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
in
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)'s
grid and in the `param.*` columns of
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md):
`paste(step, param, sep = ".")`.

## Usage

``` r
hr_settings(x)
```

## Arguments

- x:

  A step from
  [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
  [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  or
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md),
  or an arm built by
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md).

## Value

A data frame with one row per setting: `step` (the step's name in the
chain, or the step's own name), `param`, `value` (the resolved value as
text), `set` (`TRUE` when the value was given rather than left at its
default), and from the schema `default`, `range`, `type`, `tier`,
`status` and `source` (the evidence for the default, `NA` when none is
declared).

## Details

A step with no schema has no rows: its settings are fixed when it is
built. Neither has a setting the schema does not name, which a step
built with `build` keeps as a fixed extra (see
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md));
to change one, build the step again and replace it with
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md).

Only steps and chains carry schemas. An arm from
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md) is
a recipe, whose settings
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
lists, and an arm from
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
alone records none, so either is an error of class `hr_bad_arm`.

The arm attribute `hr_settings`, which
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
turns into `param.*` columns, is a different thing: it holds only the
settings the chain was given, as `"step.setting"`, while this function
lists every setting with its resolved value.

## See also

[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)

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
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
chain <- hr_chain(segment = gr_step("segment"),
                  retrieve = gr_step_retrieve(top_k = 4),
                  read = gr_step("read", reader = "stuff"), name = "checked")
s <- hr_settings(chain)
s[s$set, c("step", "param", "value", "default")]
#>        step  param value    default
#> 21 retrieve  top_k     4          6
#> 35     read reader stuff map_reduce
hr_settings(gr_step_retrieve())[, c("param", "value", "range")]
#>           param   value       range
#> 1         top_k       6  [1, 10000]
#> 2     min_score    -Inf            
#> 3           mmr       1      [0, 1]
#> 4       bm25_k1     1.5     [0, 10]
#> 5        bm25_b    0.75      [0, 1]
#> 6 lexical_blend     0.5      [0, 1]
#> 7        fusion default default|rrf
#> 8         rrf_k      60  [1, 10000]
```
