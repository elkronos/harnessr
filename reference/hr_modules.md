# List the registered modules of every kind

One table across the kinds of module: each registered extractor,
cleaner, segmenter, reader, embedder, protocol and step, with its
description, the call stems it declares, its version and the contract it
was registered under. Ask for one kind to add the columns only that kind
has, such as a reader's `signature` or an extractor's `extensions`. The
kind's own listing, such as
[`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md),
keeps its columns and adds `version` and `contract` as its last two.

## Usage

``` r
hr_modules(kind = NULL)
```

## Arguments

- kind:

  `NULL` (the default) for every kind, or one kind, such as `"reader"`.
  A kind the package does not know is an error of class
  `hr_unknown_kind`.

## Value

A data frame with one row per module, sorted by kind in the order the
kinds were registered and by name within a kind: `kind`, `name`,
`description`, and `calls`, a list column of the call stems each module
declares (`character(0)` for none). With `kind`, it also has a column
for each other setting the kind's modules were registered with, except
functions; a setting with more than one value per module, such as an
extractor's `extensions`, is a list column. The last two columns are
always `version` and `contract` (character): the module's version and
the module contract it was registered under with
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
`NA` for a module registered through its kind's own function.

## See also

[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md),
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
m <- hr_modules()
table(m$kind)
#> 
#>   cleaner  embedder extractor  protocol    reader segmenter 
#>        15         3         7         5        14        10 

# One kind, with that kind's own columns.
r <- hr_modules("reader")
r[r$name %in% c("stuff", "retrieve"), c("name", "signature", "cost_calls")]
#>        name   signature     cost_calls
#> 11 retrieve topk|1|none 1 + embeddings
#> 14    stuff  all|1|none              1
r$calls[r$name == "refine"][[1]]
#> [1] "refine.draft"  "refine.revise" "refine.answer"
```
