# Record a self-signal

`hr_signal()` writes a value the package produced about its own work
into a run's trace, and `hr_signals()` reads every recorded signal back
as one table. Recording is all that happens: no signal changes what a
reader does unless a calibration record and a passing threshold allow it
(see
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
and
[`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)).

## Usage

``` r
hr_signal(name, value, trace = NULL, item_id = NA_character_, refs = NULL)

hr_signals(x, name = NULL)
```

## Arguments

- name:

  For `hr_signal()`, the signal's name, one string, such as
  `"gr.iterative.can_answer"`. For `hr_signals()`, the names to keep, or
  `NULL` (the default) for every signal.

- value:

  The value: a logical, numeric or character vector with at least one
  element and no `NA` for a logical or numeric one. Several values
  record several observations of the signal in one step.

- trace:

  A `gr_trace` to record into, or an object holding one in `$trace` (an
  answer). `NULL` records nothing and only returns the signal.

- item_id:

  The item each value is about: one value, or one per element of
  `value`. `NA` when the caller has no item id.

- refs:

  `NULL`, or a named list of references (a round, a section number),
  each element either one value or one per element of `value`.

- x:

  For `hr_signals()`: a `gr_trace`, an object holding one in `$trace`
  (an answer, a stage result), or a list of these, such as the answers
  of several runs.

## Value

`hr_signal()` returns an `hr_signal` invisibly: a list with `name`,
`value`, `type` (`"logical"`, `"numeric"` or `"character"`), `item_id`,
`refs` and `step` (the step number in the trace, or `NA`).

`hr_signals()` returns a data frame with one row per recorded value:
`run_id`, `step`, `source` and `recipe` (the document and recipe the
step was stamped with, or `NA`), `signal`, `type`, `item_id`, `index`
(the value's position within its step), `value` (as text), `score` (the
value as a number: 1 or 0 for a logical, the number for a numeric, `NA`
for text) and `refs` (the references for that value as a JSON object, or
`NA`). A trace reached more than once in `x` (the same trace object, as
the answers of one comparison share it) lists each step once; two
separate traces are both read, even with the same `run_id`.

## Details

A signal is stored as a local step labelled `"signal"`, with the name,
value, item and references in its `detail`. A local step is not a
request, so it is not a row of `as.data.frame(trace)`, is not counted in
`trace$calls`, and changes no request or cache key.

Three signals are recorded by the readers:

- `gr.iterative.can_answer`:

  One per step of the `iterative` reader whose reply parsed: `TRUE` when
  the step said it could answer. `refs$round` is the round.

- `gr.preview.skip`:

  One value per section after the `preview` reader's plan: `TRUE` for a
  section the plan marked skip. `refs$section` is the section number and
  `refs$treatment` what the plan said.

- `gr.ensemble.adjudicate`:

  How the `ensemble` reader settled its members: `"model"` when the
  adjudication request answered, `"concatenated"` when it failed and the
  findings were joined, or `"single member"` when only one member
  answered.

## See also

[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

Other signals:
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md),
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
[`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

## Examples

``` r
tr <- gr_trace()
hr_signal("demo.confident", TRUE, tr, item_id = "q1")
hr_signal("demo.confident", c(0.9, 0.2), tr, item_id = c("q2", "q3"))
hr_signals(tr)
#>                          run_id step source recipe         signal    type
#> 1 run_20261112232549.999_6a2cef    1   <NA>   <NA> demo.confident logical
#> 2 run_20261112232549.999_6a2cef    2   <NA>   <NA> demo.confident numeric
#> 3 run_20261112232549.999_6a2cef    2   <NA>   <NA> demo.confident numeric
#>   item_id index value score refs
#> 1      q1     1  TRUE   1.0 <NA>
#> 2      q2     1   0.9   0.9 <NA>
#> 3      q3     2   0.2   0.2 <NA>

# The readers record their own signals.
cl <- gr_mock_client(function(m, p) {
  '{"can_answer": true, "answer": "45.2 million dollars", "next_query": ""}'
})
ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'sentence' (cap 150 tokens, overlap 0).
ans <- gr_read(ch, "What was revenue?", cl, "iterative")
#> Reading with 'iterative' (topk|rounds*2|forward) over 5 chunk(s).
hr_signals(ans)
#>                          run_id step source recipe                  signal
#> 1 run_20261112232550.054_5b40aa    5   <NA>   <NA> gr.iterative.can_answer
#>      type item_id index value score        refs
#> 1 logical    <NA>     1  TRUE     1 {"round":1}
```
