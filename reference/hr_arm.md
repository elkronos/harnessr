# A configuration to compare in a benchmark

An arm is one way of answering the items of a reference: a prompt, a
model, a reading recipe, a baseline that calls no model at all. It is a
function `run(item, ctx)` that returns the arm's output for one item,
which the benchmark's scorer then compares with the item's label.

## Usage

``` r
hr_arm(name, run, params = list(), derived_from = NULL, version = "0.0.1")
```

## Arguments

- name:

  The arm's name: one non-blank string, unique within a benchmark.

- run:

  A function of `(item, ctx)` returning the arm's output for one item:
  what the scorer is given (see
  [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)).
  `item` is the item's payload from
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).

- params:

  A named list of the settings that make this arm what it is. They are
  recorded with the benchmark and reach `run` as `ctx$params`.

- derived_from:

  The name of the arm this one is built from (for an arm that reuses
  another's draws offline), or `NULL`.

- version:

  The arm's version, one string. Change it when the arm's behaviour
  changes, so results from before and after can be told apart.

## Value

An object of class `hr_arm`: a list of `name`, `run`, `params`,
`derived_from`, `version` and `hash`, a SHA-256 hash of the other five
that changes when the arm's code, settings or version do. The code is
hashed as text, with the values it names from the environment it was
made in: the workspace for an arm written at top level, or the function
of yours that built it. So an arm that reads a global prompt has a new
hash when that prompt changes, and the same arm has the same hash in
every session and after
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html). A function from a
package is hashed by its code and the package's name.

## Details

`ctx` is a list with

- `client`:

  The client given to
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md).

- `trace`:

  A
  [`gr_trace()`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  of this run alone. Every request the arm makes must be recorded into
  it (`gr_call(..., trace = ctx$trace)`): it is how the benchmark counts
  the run's tokens, dollars and refusals, and how it holds the run to
  the benchmark's limits.

- `governor`:

  The
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  the run is held to: the benchmark's limits less what earlier runs
  used. It is already attached to `trace`.

- `draw_index`:

  The run number, 1 to `runs`. Pass it to
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  as `draw_index` so each run is its own draw: under a
  [`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
  or a
  [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  a request sent without it answers every run with the same stored
  reply, and the benchmark refuses such an arm.

- `call`:

  A shortcut, `ctx$call(messages, ...)`, for
  `gr_call(ctx$client, messages, ..., trace = ctx$trace, draw_index = ctx$draw_index)`.

- `item_id`, `arm`, `run`, `params`:

  The item's id, the arm's name, the run number and the arm's `params`.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
short <- hr_arm("short", function(item, ctx) {
  ctx$call(paste("Answer in one word:", item))$text
}, params = list(prompt = "one word"))
short
#> <hr_arm short> version 0.0.1
#>   params: prompt = one word 
#>   hash: 8c436eb80f4b
```
