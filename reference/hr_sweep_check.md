# Find the settings of a sweep that changed nothing that was sent

A setting a reader does not use (`top_k` under a reader that sends every
chunk, `mmr` with `top_k` at or above the number of chunks) leaves the
requests as they were, and a sweep over it compares an arm with itself.
`hr_sweep_check()` finds such pairs in a benchmark: two arms that sent
byte-identical requests (the same model, prompts and request settings,
in the same order) on every item and run they share.

## Usage

``` r
hr_sweep_check(bench)
```

## Arguments

- bench:

  An `hr_bench` from
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md).

## Value

A data frame with one row per arm whose requests were identical to an
earlier arm's: `arm` and `same_as` (the first earlier arm, in the
benchmark's order, that sent the same requests), `runs` (the item and
run pairs compared), `requests` (the requests `arm` sent over them), and
`settings`, the recorded settings (`param.*` columns) that differ
between the two, as `"top_k: 2 vs 8"`, which are the settings that
changed nothing. No rows when every pair of arms sent different
requests.

## Details

An arm is reported once, against the first arm before it with the same
requests, so three arms that sent the same requests give two rows. Pairs
in which neither arm sent a request are left out, since requests cannot
tell them apart. A request answered from a cache counts as sent: its
prompt is recorded as it would have gone out.

## See also

[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)

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
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?"),
  documents = gr_example(), answers = list("45.2 million"), split = "test")
old <- gr_options(verbose = FALSE)
# `stuff` sends the whole document, so top_k changes nothing.
arms <- hr_sweep(gr_arm("fast"), list(top_k = c(2, 8)))
bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
                      scorer = gr_scorer_answer())
hr_sweep_check(bench)
#>            arm      same_as runs requests      settings
#> 1 fast:top_k=8 fast:top_k=2    5        5 top_k: 2 vs 8
gr_options(old)
```
