# A step of a run, with the settings it was built with

A step does one part of a run: it takes what the step before it returned
(the item, for the first step) and returns what the next step takes.
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
runs steps in order as one
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md).
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
and
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
build the document steps (ingest, segment, retrieve, read) with this
function.

## Usage

``` r
hr_step(
  name,
  fn = NULL,
  params = list(),
  schema = NULL,
  input = NULL,
  output = NULL,
  version = "0.0.1",
  build = NULL,
  skill = NULL
)
```

## Arguments

- name:

  The step's name: one non-blank string.
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
  uses it when the step is given without a name.

- fn:

  A function of `(input, ctx)`, or of `...`; `NULL` when `build` is
  given.

- params:

  A named list of the step's settings.

- schema:

  An
  [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
  the settings are checked against, or `NULL`.

- input, output:

  What the step takes and returns: `NULL` or one of `"document"`,
  `"doc"`, `"chunks"`, `"answer"` and `"state"`.

- version:

  The step's version, one string. Change it when the step's behaviour
  changes.

- build:

  A function of the settings that returns the step's function, or `NULL`
  when `fn` is given.

- skill:

  A skill from
  [`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
  or `NULL`. Inside
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
  the step's `ctx$call()` and `ctx$call_json()` send the skill's
  instructions and references as a system message before the step's own
  messages, and `ctx$skill` holds the skill. The skill's hash is kept as
  the fixed setting `skill` and is part of the fingerprint, and the
  skill's version, when it has one, is the step's version.

## Value

A function of `(input, ctx)` with class `hr_step` and the attributes
`name`, `params` (as given), `resolved` (the settings the schema
resolved, or `params` without a schema), `extras` (settings the schema
does not name), `schema`, `input`, `output`, `version`, `build` `skill`
and `fingerprint`, a hash of the step's code, the values it reads, its
settings and its version.

## Details

Give exactly one of `fn` and `build`:

- `fn`:

  A function of `(input, ctx)`. Inside a chain, `ctx` is the context
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  gives the arm (see
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)),
  with two more entries: `step`, the step's name in the chain, and
  `step_params`, its resolved settings. `ctx$params` is still the arm's
  `params`.

- `build`:

  A function of one argument, the step's settings as a named list, that
  returns such a function. It is called here, so a setting it checks is
  checked when the step is built, not on the first run of a benchmark.

With a `schema` (an
[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)),
the settings in `params` that the schema names are checked and resolved
by
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md),
and every setting the schema has is filled from its default. A setting
the schema does not name is an error of class `hr_unknown_param` for a
step given `fn`. A step given `build` keeps it as a fixed extra setting,
which reaches `build` but is not part of the schema. Without a schema,
`params` is kept as given.

`input` and `output` say what the step takes and returns, so
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
can check the order of its steps: `"document"` (a file, URL or text),
`"doc"` (an ingested document), `"chunks"`, `"answer"` or `"state"`
(anything else). `NULL` declares nothing.

## See also

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)

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
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
shout <- hr_step("shout", function(input, ctx) {
  paste0(toupper(input), strrep("!", ctx$step_params$marks))
}, params = list(marks = 2L),
   schema = hr_schema(hr_param("marks", "integer", default = 1L, min = 0, max = 5)))
attr(shout, "resolved")
#> $marks
#> [1] 2
#> 
shout("hello", list(step_params = attr(shout, "resolved")))
#> [1] "HELLO!!"
```
