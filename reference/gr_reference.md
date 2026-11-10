# Draw a sample to screen by hand

Picks documents out of a
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
run for a person to judge without seeing what the model said, and writes
them to a CSV to fill in. Feeding the completed file back to
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
is what turns "we used an LLM" into a claim with a number attached.

## Usage

``` r
gr_reference(
  screening,
  n = 50,
  of = c("excluded", "kept", "all", "stacked"),
  seed = NULL,
  path = NULL,
  blind = TRUE,
  frame = NULL,
  reviewers = 1L
)
```

## Arguments

- screening:

  A `gr_screening` from
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md).

- n:

  How many to draw: a whole number of at least 1. `Inf` takes the whole
  frame, as does any `n` larger than it. For `of = "stacked"`, how many
  of the excluded records to draw; the kept ones are all taken.

- of:

  Which rows to sample from: `"excluded"`, `"kept"` (include and
  unclear), `"all"`, or `"stacked"` (every kept record and a sample of
  the excluded ones).

- seed:

  A seed for the draw, so it is reproducible: the sample is drawn after
  `set.seed(seed)` and your session's random number stream is put back
  afterwards. A calibration sample is part of the method and has to be
  re-drawable.

- path:

  Where to write the CSV. `NULL` returns the frame without writing.

- blind:

  Leave the model's decision and reason out of the file. On by default:
  a person shown the answer agrees with it, and the resulting figure
  measures nothing. A blind sheet does not name its frame either, since
  "excluded" on every row says what the model decided: `sampled_from`
  holds an opaque key that
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  reads back as the frame and its size. With `blind = FALSE` the file
  has `model_decision`, `model_reason`, and the frame in plain words
  (`sampled_from`, `frame_n`, `screened_n`, and for a stacked sheet
  `stratum` and `inclusion_prob`, with `frame_n` the size of the row's
  stratum).

- frame:

  The same as `of`, under the name
  [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
  uses. Give one or the other.

- reviewers:

  How many people will judge each record. Above 1 the sheet has one
  decision column per reviewer, `human_decision_1` to
  `human_decision_<reviewers>`, in place of `human_decision`, and a
  `consensus` column for an adjudicator to fill where they disagree. See
  [`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)
  for how their decisions become one.

## Value

A data frame of class `gr_reference_frame`, invisibly when written. The
`human_decision` column is empty and is yours to fill with `include` or
`exclude` (with several reviewers, each `human_decision_<reviewer>`
column is).

## Which rows to sample

`of = "excluded"` is usually the right answer and is not the obvious
one. Sensitivity failures hide among the exclusions: a study the
screener threw away is gone, and nothing downstream will ever mention
it, while the records it kept are going to be read by a person anyway.
Sampling everything at a realistic inclusion rate spends most of the
sample confirming exclusions that were never in doubt, and leaves two or
three positives to estimate sensitivity from, which is no estimate at
all.

The design that matches how people actually work is to judge *every*
record the screener kept, plus a sample of what it discarded.
`of = "stacked"` draws exactly that in one sheet: every kept record, and
`n` of the excluded ones. Each row records its stratum and its inclusion
probability (1 for a kept record, `n` / N for an excluded one, N being
the number excluded), and
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
weights each stratum by it to estimate recall. Drawn as two sheets
(`of = "kept"` with `n = Inf`, and `of = "excluded"`) and stacked by
hand, the same reference needs `of = "stacked"` in
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md).
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
says how large `n` should be.
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
knows which frame it was given and will not compute a corpus-wide figure
from a sample that cannot support one.

A blind stacked sheet keeps each row's stratum and probability inside
the `sampled_from` key, one key per row, so that neither gives away what
the model decided; the rows are in the run's order, not grouped by
stratum.

## The file

The CSV is written as UTF-8 with a byte-order mark, which is what makes
Excel open accented names and titles correctly; save it back as "CSV
UTF-8".
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
reads it the same way in any locale, reads a sheet a spreadsheet
re-saved as Windows-1252 as that, and matches a row whose name still
does not agree by its `document_id`.

## See also

[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)

Other corpus functions:
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)

## Examples

``` r
tab <- data.frame(document = paste0("d", 1:6, ".pdf"),
                  decision = c("include", "exclude", "exclude",
                               "unclear", "exclude", "include"),
                  reason = "because", stringsAsFactors = FALSE)
gr_reference(structure(list(table = tab), class = "gr_screening"),
             n = 3, of = "excluded", seed = 1)
#>   document human_decision human_note                       sampled_from
#> 1   d2.pdf           <NA>       <NA> grd5b346bbe4d898050402719dd5027962
#> 2   d3.pdf           <NA>       <NA> grd5b346bbe4d898050402719dd5027962
#> 3   d5.pdf           <NA>       <NA> grd5b346bbe4d898050402719dd5027962

# Every kept record, and two of the four excluded ones.
gr_reference(structure(list(table = tab), class = "gr_screening"),
             n = 2, of = "stacked", seed = 1, blind = FALSE)
#>   document model_decision model_reason human_decision human_note sampled_from
#> 1   d1.pdf        include      because           <NA>       <NA>      stacked
#> 2   d2.pdf        exclude      because           <NA>       <NA>      stacked
#> 3   d3.pdf        exclude      because           <NA>       <NA>      stacked
#> 4   d4.pdf        unclear      because           <NA>       <NA>      stacked
#> 5   d6.pdf        include      because           <NA>       <NA>      stacked
#>    stratum inclusion_prob frame_n screened_n
#> 1     kept      1.0000000       3          6
#> 2 excluded      0.6666667       3          6
#> 3 excluded      0.6666667       3          6
#> 4     kept      1.0000000       3          6
#> 5     kept      1.0000000       3          6
```
