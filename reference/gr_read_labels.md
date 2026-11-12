# Read a filled label sheet

Reads one or more sheets written by
[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md),
checks every value and id, and returns the labels in the form the
package's comparisons take: a screening reference for
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
a table for
[`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md),
calibration labels, or labels to compare a judge's verdicts with in
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md).
A calibration sheet written with `blind = FALSE` gives a graded set
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
takes, with or without `items`: without them, the sheet's `model_score`
column is read back as the number `score`. A blind one gives reference
answers, and the model's answers must be scored against them to make the
`correct` column it needs.

## Usage

``` r
gr_read_labels(path, kind, items = NULL, fields = NULL)
```

## Arguments

- path:

  One or more CSV files written by
  [`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
  (one per reviewer), or the sheet as a data frame.

- kind:

  The kind the sheet was written as.

- items:

  The items the sheet was written from. Optional; with them, ids are
  checked against the items and the items' other columns (`cluster`,
  `split`, `inclusion_prob`, a signal's `score` and so on) are joined to
  the labels by `item_id`.

- fields:

  For `kind = "extraction"`: names, a
  [`gr_fields()`](https://elkronos.github.io/harnessr/reference/gr_fields.md)
  schema or a
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md).
  A schema also checks each value's type. `NULL` takes every column of
  the sheet that is not an id, item, model or note column.

## Value

A data frame with one row per sheet row: `item_id`, `reviewer` when
there are several, the item columns, the decisions and the note, then
any columns joined from `items`. An item column named like one of the
sheet's decision or note columns (`answer`, `verdict` and so on, often
the model's own output) is joined as `model_<name>`, unless the sheet
already has a column of that name. `answerable` and `correct` are
logical; `human_decision` and `verdict` are lower case; extraction
values are text as written. A calibration result has a `cluster` column
(from `items`, else `document`), and a `correct` column only when the
sheet was written with `blind = FALSE`; only then is it ready for
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md).
Its `score` comes from `items` when they are given, else from the
sheet's `model_score` (yes and no, or `TRUE` and `FALSE`, read as 1 and
0; left out when a value is not a number). Attributes `label_kind` and
`unlabelled` (the number of rows not yet labelled) are set.

## What is checked

- Every row has an `item_id`, and no id appears twice for one reviewer.
  With `items`, every id is one of the items', and an item missing from
  the sheets is reported with a warning of class `gr_labels_missing`.

- Yes-or-no columns (`answerable`, `correct`) hold yes, no, y, n, true,
  false, 1 or 0, in any case. `human_decision` holds include or exclude,
  and `verdict` pass or fail.

- An answerable QA or calibration item has an `answer`, and one that is
  not answerable has none; an item whose `answerable` is empty has no
  other decision filled; a calibration sheet with a `correct` column has
  it filled on every labelled row.

- An extraction row with any field filled has every field filled (with
  "not reported" where the document does not report it), and with a
  schema each value reads as its field's type: a whole number, a number,
  yes or no, or one of an `enum` field's values.

Every value that fails is collected, and the error, of class
`gr_bad_labels`, names the sheet, the row (counting the header as row 1,
as a spreadsheet does) and the item. Its `problems` field holds them
all. A row whose first decision column is empty is an item not yet
labelled: it is returned with its decisions `NA`, and counted.

## See also

[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md),
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md),
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)

Other reference sets:
[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md),
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)

## Examples

``` r
qa <- data.frame(document = c("a.pdf", "a.pdf", "b.pdf"),
                 question = c("What was revenue?", "Who audited it?",
                              "When did the trial start?"))
path <- file.path(tempdir(), "qa-read.csv")
gr_label_sheet("qa", qa, path = path)
#> Wrote 3 item(s) to '/tmp/Rtmp0cYkSI/qa-read.csv', with instructions in '/tmp/Rtmp0cYkSI/qa-read_instructions.txt'. Read the filled sheet back with gr_read_labels().

# A person fills it in; here the filling is simulated.
sheet <- read.csv(path, fileEncoding = "UTF-8-BOM")
sheet$answerable <- c("yes", "no", "yes")
sheet$answer <- c("45.2 million dollars", NA, "March 2019")
write.csv(sheet, path, row.names = FALSE, na = "")

gr_read_labels(path, "qa", items = qa)
#> Read 3 row(s): 3 labelled, 0 not yet labelled.
#>   item_id document                  question answerable               answer
#> 1 qa-0001    a.pdf         What was revenue?       TRUE 45.2 million dollars
#> 2 qa-0002    a.pdf           Who audited it?      FALSE                 <NA>
#> 3 qa-0003    b.pdf When did the trial start?       TRUE           March 2019
#>   quote note
#> 1  <NA> <NA>
#> 2  <NA> <NA>
#> 3  <NA> <NA>
```
