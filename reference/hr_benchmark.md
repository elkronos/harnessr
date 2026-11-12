# Run arms against a reference

Runs every arm on every item of the chosen split(s) of `reference`,
`runs` times, scores each output with `scorer`, and returns one row per
cluster x item x arm x run. Rows are ordered that way, and the runs are
made in the same order.

## Usage

``` r
hr_benchmark(
  arms,
  reference,
  runs = 5,
  client,
  scorer = hr_scorer_exact(),
  split = "test",
  governor = NULL,
  seed = 1
)

# S3 method for class 'hr_bench'
print(x, ...)
```

## Arguments

- arms:

  An
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
  or a list of them, with unique names.

- reference:

  An
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).

- runs:

  How many times each arm runs on each item: a whole number, at least 1.
  5 or more is the expected minimum.

- client:

  The client passed to the arms in `ctx$client`, or `NULL` for arms that
  call no model.

- scorer:

  An
  [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md);
  [`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
  by default.

- split:

  The split or splits of the reference to run on.

- governor:

  An
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  the whole benchmark is held to, or `NULL` to take the limits from
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md).

- seed:

  The seed of the arms' private random stream.

- x:

  An `hr_bench`.

- ...:

  Ignored.

## Value

An object of class `hr_bench`, a data frame with one row per cluster x
item x arm x run and the columns

- `cluster`, `item`, `arm`, `run`, `split`:

  Which run of which arm on which item.

- `correct`:

  `TRUE` or `FALSE`, or `NA` on every run of an item with no label (its
  `failure_kind` is still recorded).

- `outcome`:

  What the scorer saw (see
  [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)).

- `failure_kind`:

  Why a wrong run was wrong: `"parse_failure"`, `"refusal"`,
  `"not_in_document"`, `"wrong"`, `"budget_stop"` or `"error"`; `NA`
  when it was correct.

- `tokens_in`, `tokens_out`, `tokens_reasoning`, `tokens_cached`:

  The run's prompt and reply tokens over its model calls, and the
  reasoning and cached input tokens among them that the provider
  reported.

- `usd`:

  What the run cost, every request priced at its own model, embeddings
  included, as
  [`gr_trace_cost()`](https://elkronos.github.io/harnessr/reference/gr_trace_cost.md)
  prices it: 0 for requests a cache or a recording answered, `NA` when a
  model has no price.

- `usd_provenance`:

  Where the token counts the cost rests on came from, over the requests
  that were paid for: `"reported"` when the provider reported them all,
  else `"counted"` when they were counted with the model's own
  tokenizer, else `"estimated"`; `"none"` when the run paid for no
  request, and `NA` when a request does not say.

- `seconds`:

  The run's wall-clock time.

- `draw_index`:

  The draw index the run was given: its run number.

- `ledger_id`:

  The `run_id` of the run's own trace, which is kept in
  `attr(x, "traces")` under that name, and which every step the run
  added to the benchmark's trace, `attr(x, "trace")`, carries as
  `ledger_id`.

- `reportable`:

  `FALSE` for rows on the dev split.

Attributes record the arms (`arms`: name, version, hash, derived_from),
the reference hash, `runs`, `split`, `seed`, the scorer's name, and the
traces. [`print()`](https://rdrr.io/r/base/print.html) shows each arm's
accuracy over the reportable rows, the mean over runs within each item
and then over items, leaving out items with no label; the dev split's
accuracy, when there is one, is shown apart in its own column. It adds
failures and cost, and is descriptive only: no interval.

## Details

Run `r` of each arm on each item is given `ctx$draw_index = r` (see
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)),
so with the index passed to
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
each run is its own entry in a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
and its own recorded draw in a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md).
Each request a run makes with a draw index is recorded under the arm's
name as well, so a replay of a benchmark answers each arm with the
replies that arm got, even when two arms sent the same request, and
whether all the arms are replayed or some, in any order. An arm whose
runs are not distinct draws is refused with an error of class
`hr_duplicate_draw`: a run of an arm on an item is a duplicate when one
of its requests was answered from a cache or a recording with the same
request and draw index as a request of an earlier run, when one of its
replies has the provider response id of a reply in an earlier run, or
when a recording served a reply without its own draw key (a repeat after
the recording ran out of draws, or a recording made without per-draw
keys). Every request a run makes should therefore carry the run's draw
index. A
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
keeps no cache, so under it an arm that leaves the index out is not
refused; under a cache it would be.

Every request is checked against `governor` before it is sent, for the
benchmark as a whole: each run's trace is held to the governor's call,
spending and token limits less what the runs before it used. A run ends
at its first refused request (the `hr_budget_refused` condition is
caught there), is recorded as `failure_kind = "budget_stop"` and counted
wrong (or `NA` on an item with no label, as below). The runs after it
are still started, so every row exists and the refusals are visible;
their requests are refused before anything is sent. With
`governor = NULL` the limits are read from
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
when the benchmark starts and apply to the whole benchmark, as they
apply to one run of a reader. Those defaults are set for one run (400
calls), and a benchmark of two arms on 300 items for 5 runs needs
several thousand, so pass a governor sized for the benchmark. When any
run is stopped, `hr_benchmark()` warns (class `hr_budget_stopped`) with
the number of runs stopped, the limits that stopped them, how many of
them count against an arm (runs on the dev split or on items with no
label do not) and the first run stopped. With `governor = NULL` it also
gives the
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
values behind those limits.

An arm that raises an error has that run recorded as `"error"`, counted
wrong, with the message in the run's trace. Every run on an item with no
label has `correct = NA`, whatever its `failure_kind`: a failure on it
cannot count against an arm when a success could not count for it. Rows
on the `"dev"` split are marked `reportable = FALSE`: dev is for tuning,
and its scores are not evidence. The reference is locked when scoring
starts (see
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)).

Fewer than 5 runs warns (class `hr_few_runs`): with fewer, run-to-run
spread cannot be told from the differences between arms, and interval
reports are expected to refuse such a benchmark unless it is labelled
descriptive.

The arms run under a private random stream started from `seed`, so an
arm that samples gives the same draws on every call with the same seed,
and the caller's random state is left as it was.

## See also

[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
ref <- hr_reference(
  items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
  labels = c("Paris", "Lima", "N'Djamena", "Suva"),
  cluster = c("a", "a", "b", "b"), split = "test")
capitals <- c(France = "Paris", Peru = "Lima", Chad = "Ndjamena", Fiji = "Suva")
cl <- gr_mock_client(function(messages, params) {
  country <- sub("Capital of ", "", messages[[1]]$content)
  capitals[[country]]
})
ask <- hr_arm("ask", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
bench <- hr_benchmark(ask, ref, runs = 5, client = cl)
bench
#> <hr_bench> 1 arm(s) x 4 item(s) in 2 cluster(s) x 5 run(s); split test; scorer exact_normalised
#>  arm accuracy runs wrong failed budget_stop usd   
#>  ask 0.750    20   5     0      0           0.0000
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
head(bench[, c("item", "run", "correct", "failure_kind", "draw_index")])
#>   item run correct failure_kind draw_index
#> 1   q1   1    TRUE         <NA>          1
#> 2   q1   2    TRUE         <NA>          2
#> 3   q1   3    TRUE         <NA>          3
#> 4   q1   4    TRUE         <NA>          4
#> 5   q1   5    TRUE         <NA>          5
#> 6   q2   1    TRUE         <NA>          1
```
