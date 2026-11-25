# Run steps in order as one arm

`hr_chain()` turns steps into an
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
whose run passes the item to the first step, what that returns to the
second, and so on, and returns what the last step returns. Each step is
called as `step(x, ctx)`, where `ctx` is the arm's context with
`ctx$step` (the step's name) and `ctx$step_params` (its resolved
settings) added; `ctx$params` stays the arm's `params`.

## Usage

``` r
hr_chain(..., name, version = "0.0.1")
```

## Arguments

- ...:

  Steps, or a chain to derive from followed by steps and `NULL`s.

- name:

  The chain's name, one string, as an arm's name.

- version:

  The chain's version, one string.

## Value

An [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
with the attribute `hr_steps`, the named list of its steps in order.

## Details

Steps come from
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
or
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md).
A named argument names its step, and the name is written into the step;
an unnamed one keeps the step's own name. Names must be unique, must not
contain a dot (a setting is named `"step.setting"`) and must not be
`name` or `version`.

Given a chain first, `hr_chain()` derives a new chain from it:
`x = NULL` drops step `x`, `x = step` replaces step `x` where it stands,
and a step under a new name is added at the end. So
`hr_chain(checked, judge = NULL, name = "nojudge")` is `checked` without
its judge.

The order is checked when the chain is built, from what each step
declares it takes and returns. A step that takes `"chunks"` when no step
before it returns chunks warns with class `hr_chain_gap`: a
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
read step would cut the document at the default settings without saying
so. A step that takes `"doc"` with no step before it returning one does
not warn: a chain usually starts at the segment step, which reads the
document at the default ingest settings, and a warning there would fire
on almost every chain. Add an ingest step first to choose those
settings. After a step that returns `"answer"`, only steps that take
`"answer"` or `"state"`, or declare nothing, may follow; any other is an
error of class `hr_bad_chain`. A held command step (see
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md))
must come last, or be followed only by other held steps; any other step
after it is an error of class `hr_held_not_last`.

The arm records each step's settings as given, as `"step.setting"`, in
`params` and as the settings
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
turns into `param.*` columns. Its configuration, which
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
compare, is a hash of the steps' names, versions, code, the values that
code reads and the resolved settings, so a setting given at its default
gives the same configuration as the setting left out.
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
lists every setting of the chain by path,
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
changes some of them, and
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
sweeps them by path, as
`hr_sweep(chain, data.frame(retrieve.top_k = c(2, 8)))`.

## See also

[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
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
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?"),
  documents = gr_example(), answers = list("45.2 million"), split = "test")
tidy <- hr_step("tidy", function(a, ctx) {
  a$answer <- trimws(a$answer)
  a
}, input = "answer", output = "answer")
checked <- hr_chain(segment = gr_step("segment"),
                    retrieve = gr_step_retrieve(top_k = 4),
                    read = gr_step("read", reader = "stuff"),
                    tidy = tidy, name = "checked")
plain <- hr_chain(checked, tidy = NULL, name = "plain")
names(attr(plain, "hr_steps"))
#> [1] "segment"  "retrieve" "read"    
old <- hr_options(verbose = FALSE)
bench <- hr_benchmark(list(checked, plain), ref, runs = 5, client = cl,
                      scorer = gr_scorer_answer())
table(bench$arm, bench$correct)
#>          
#>           TRUE
#>   checked    5
#>   plain      5
hr_options(old)
```
