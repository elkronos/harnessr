# Register a module of any kind

`hr_register()` files a module under a kind, such as `"reader"` or
`"segmenter"`, through the same checks as that kind's own registration
function: `hr_register("reader", ...)` runs what
[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
runs, so a reader named `"auto"` or with a malformed `signature` is
refused here as it is there.
[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
lists the kinds and what each holds.

## Usage

``` r
hr_register(
  kind,
  name,
  fn,
  ...,
  description = "",
  calls = NULL,
  version = NULL
)
```

## Arguments

- kind:

  The kind of module, one string. A kind the package does not know is an
  error of class `hr_unknown_kind`.

- name:

  The module's name, one string. Registering a name again replaces the
  module.

- fn:

  The module's function, with the arguments its kind calls it with (see
  the kind's own registration function). For a protocol, the protocol
  object; for a step, a step or a function of `(input, ctx)`.

- ...:

  The other arguments of the kind's own registration function, by name,
  such as `signature` for a reader or `extensions` for an extractor. A
  segmenter also takes `effort_label`, a function of the segment spec
  that returns the trace label its model requests carry, or `""` when it
  sends none. A run's `effort` setting then reaches the segmenter as the
  effort for that label alone. Without it, the segmenter gets the run's
  whole effort map. A step takes the arguments of
  [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
  such as `params`, `input` and `output`.

- description:

  One-line description, shown by the kind's listing and by
  [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md).
  For a protocol, a non-empty description replaces the protocol's own.

- calls:

  The stems of the trace labels the module's model calls carry, for the
  kinds that declare them (readers, segmenters and steps). `NULL` (the
  default) declares the module's name for a reader or a segmenter and no
  stems for a step. Any other value for a kind that does not declare
  calls is an error of class `gr_bad_setting`.

- version:

  The module's own version, one string, kept in the `version` field.
  `NULL` (the default) records `NA`, or, for a step, the step's own
  version.

## Value

Invisibly, `name`.

## Details

The kinds the package brings, and the function each one goes through:
`"extractor"`
([`gr_register_extractor()`](https://elkronos.github.io/harnessr/reference/gr_register_extractor.md)),
`"cleaner"`
([`gr_register_cleaner()`](https://elkronos.github.io/harnessr/reference/gr_register_cleaner.md)),
`"segmenter"`
([`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)),
`"reader"`
([`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)),
`"embedder"`
([`gr_register_embedder()`](https://elkronos.github.io/harnessr/reference/gr_register_embedder.md)),
`"protocol"`
([`gr_register_protocol()`](https://elkronos.github.io/harnessr/reference/gr_register_protocol.md))
and `"step"`. For a protocol, `fn` is the protocol object from
[`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md).
For a step, `fn` is a step from
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
or a function of `(input, ctx)` that `hr_register()` passes to
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
with the name and the arguments in `...`.

A module registered here records two more fields: `version`, the version
you give, and `contract`, the version of the module contract the package
implements, 0.2 in this release. Every listing shows them as its last
two columns. A module registered through a kind's own function has `NA`
in both, and its conformance check stays advisory.

## See also

[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md),
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)

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
# A segmenter that makes one chunk per line, registered by kind.
hr_register("segmenter", "by_line", description = "one chunk per line",
  version = "1.0.0",
  fn = function(doc, spec, client, trace) {
    new_chunks(strsplit(doc$text, "\n+")[[1]], "by_line", spec)
  })
subset(hr_modules("segmenter"), name == "by_line")[, c("kind", "name", "cost", "contract")]
#>        kind    name cost contract
#> 2 segmenter by_line free      0.2
nrow(gr_segment(gr_example(), list(method = "by_line"))$chunks)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'by_line' (cap 1200 tokens, overlap 0).
#> [1] 32

# A step, registered by kind and listed with its input and output.
hr_register("step", "shout", fn = function(input, ctx) toupper(input),
  input = "answer", output = "state")
hr_modules("step")[, c("name", "input", "output", "version", "contract")]
#>    name  input output version contract
#> 1 shout answer  state   0.0.1      0.2

# A kind the package does not know is refused.
try(hr_register("ranker", "mine", fn = identity))
#> Error in kind_access(kind, "set") : 
#>   Unknown kind of module 'ranker'. Kinds you can register: extractor, cleaner, segmenter, reader, embedder, protocol, step.
```
