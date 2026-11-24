# Change some settings of a step or a chain

`hr_set()` builds a step or a chain again with some settings changed and
the rest as they were. In a chain each setting is named by its path,
`"step.setting"` (split at the first dot), as
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
lists them: `hr_set(chain, retrieve.top_k = 8)`. For a single step, the
setting's own name is enough: `hr_set(step, top_k = 8)`.

## Usage

``` r
hr_set(x, ...)
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

- ...:

  The settings to change, each named: `"step.setting" = value` for a
  chain, `setting = value` for a single step.

## Value

`x` built again with the settings changed: a step of the same class, or
an arm from
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
with the same name and version. With no settings given, `x` as it is.

## Details

Only settings of a step's schema can be changed. A path whose step is
not in the chain, or whose setting is not in that step's schema, is an
error of class `hr_unknown_setting` (also `hr_unknown_param` and
`gr_bad_setting`) that lists the settings of the step it names, or the
steps of the chain. A setting the schema does not name, which a step
built with `build` keeps as a fixed extra, is refused the same way.

The new values are checked by
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
as when the step was built, so a number outside its range is moved to
the nearest bound with a warning of class `hr_param_clamped` (also
`gr_clamped`), and a value the step's constructor refuses, such as an
unknown reader, is an error. Each step that changed is built again from
its settings, through its `build` function when it has one, so a setting
its constructor checks is checked here, and keeps its class: a
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
stays a `gr_step`.

The chain is then built again by
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
under its own name and version, with the changed steps in place, so its
hash and configuration are those of the new settings. A setting changed
to its default gives the configuration of the chain with that setting
left out.
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
calls `hr_set()` for each row of its grid when given a chain, which is
how a chain is swept by name.

## See also

[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)

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
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
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
wider <- hr_set(chain, retrieve.top_k = 8, segment.max_tokens = 300)
wider$params
#> $segment.max_tokens
#> [1] 300
#> 
#> $retrieve.top_k
#> [1] 8
#> 
#> $read.reader
#> [1] "stuff"
#> 
hr_settings(wider)[hr_settings(wider)$set, c("step", "param", "value")]
#>        step      param value
#> 2   segment max_tokens   300
#> 21 retrieve      top_k     8
#> 35     read     reader stuff

# A setting at its default is the chain without it.
six <- hr_set(chain, retrieve.top_k = 6)
plain <- hr_chain(chain, retrieve = gr_step_retrieve(), name = "checked")
identical(attr(six, "hr_config"), attr(plain, "hr_config"))
#> [1] TRUE

# A single step takes the setting's own name.
attr(hr_set(gr_step_retrieve(), top_k = 2), "resolved")$top_k
#> [1] 2
```
