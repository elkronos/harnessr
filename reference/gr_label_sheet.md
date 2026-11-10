# Write a sheet for people to label

Writes a CSV with one row per item, an `item_id` column, the columns a
person needs to judge the item, and empty columns for their decisions,
with a short instructions file beside it. Read the filled sheet back
with
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md).

## Usage

``` r
gr_label_sheet(
  kind = c("qa", "screening", "extraction", "calibration", "judge"),
  items,
  path = NULL,
  blind = TRUE,
  reviewers = 1,
  fields = NULL
)
```

## Arguments

- kind:

  `"qa"`, `"screening"`, `"extraction"`, `"calibration"` or `"judge"`;
  see "Kinds of sheet".

- items:

  A data frame with one row per item. Its ids come from an `item_id`
  column, else an `id` column; without either they are made from the
  kind and the row number (`"qa-0001"`), so pass the same rows in the
  same order to
  [`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md).
  Column names are matched exactly: a column such as `ideal_answer` is
  never taken for `id`, so reference answers cannot reach a blind sheet
  as ids.

- path:

  Where to write the CSV. `NULL` returns the sheet without writing. The
  instructions go to `<name>_instructions.txt` beside it.

- blind:

  Leave model output out of the sheet; see "Blind sheets".

- reviewers:

  How many people label each item, a whole number of at least 1; see
  "Several reviewers".

- fields:

  For `kind = "extraction"`, the fields: names, a
  [`gr_fields()`](https://elkronos.github.io/harnessr/reference/gr_fields.md)
  schema or a
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md).
  A schema's descriptions and allowed values go into the instructions.

## Value

The sheet as a data frame (several reviewers' sheets stacked, with their
`reviewer` column), invisibly when written; then its `paths` attribute
holds the files written.

## Kinds of sheet

- `"qa"`:

  Questions about documents. Items need `document` and `question`. The
  person fills `answerable` (yes or no: is the answer in the document),
  `answer` (required when answerable) and `quote` (the passage that
  gives it).

- `"screening"`:

  Records to judge for eligibility. Items need `document`; `title`,
  `authors`, `year`, `journal` and `abstract` are copied when present.
  The person fills `human_decision` (include or exclude) and
  `human_note`, the columns
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  reads.

- `"extraction"`:

  Documents to extract fields from. Items need `document`, one row per
  document, and `fields` names the fields. The person fills one column
  per field, writing "not reported" when the document does not report
  it.

- `"calibration"`:

  The graded set a signal is calibrated on. Items need `document` and
  `question`, and must include questions the document cannot answer. The
  person fills `answerable` and `answer`, and on a sheet with
  `blind = FALSE`, `correct` (yes or no: is the model's answer, shown
  beside it, right).

- `"judge"`:

  Candidates a judge scores, to validate the judge against. Items need
  `candidate`, the text being judged, and may give `question` or
  `criterion`. The person fills `verdict` (pass or fail).

Every sheet also has a free-text `note` column (`human_note` for
screening).

## Blind sheets

With `blind = TRUE` only the columns listed above for the kind are
copied from `items`; nothing else is, so no model output, score, verdict
or sampling detail reaches the sheet by accident. With `blind = FALSE`
the other columns are copied too, each named `model_<name>` unless it
already starts with `model_`. Columns about how items were sampled or
assigned (`cluster`, `split`, `stratum`, `strata`, `inclusion_prob`,
`weight`, `frame_n`, `screened_n`, `sampled_from`) are never written,
except on a screening sheet. There a blind sheet carries the frame as
the opaque key a blind
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
sheet carries, made from plain frame names when `items` has them (a
stacked frame also needs `stratum`, `inclusion_prob`, `frame_n` and
`screened_n`), so the sheet read back without `items` still tells
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
what was sampled; with `blind = FALSE` the columns are written as they
are. Give the same `items` to
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
to join the rest back.

Calibration grading needs the model's answer, so a blind calibration
sheet has no `correct` column: the person records the reference answer,
and the model's answers are scored against it afterwards.

## Several reviewers

With `reviewers = k` above 1, each reviewer gets a sheet of their own,
`<name>_r1.csv` to `<name>_r<k>.csv`, with a `reviewer` column already
filled, so that no reviewer sees another's decisions.
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
reads them together.

## How many items each set needs

These are the sizes harnessr's development plan budgets for its own
evaluation, given here as a starting point, not as rules.

- QA:

  About 480 questions over 88 documents, plus 88 explanatory questions,
  labelled by two people and adjudicated, with quotes. At an intraclass
  correlation of 0.2 for the paired difference between two settings
  within a document, this supports about an 8 point margin before a Holm
  correction; a contrast that sets a default needs about 136 scored
  documents, or a margin of about 10.5 points.

- Screening reference:

  7 to 9 reviews, about 200 eligible and 1,800 ineligible records, with
  two blind reviewers on one recent review. See
  [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
  for the sample a recall target needs.

- Extraction:

  60 documents by 10 fields, two people, with Krippendorff's alpha per
  field at its level of measurement
  ([`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md)).

- Calibration graded set:

  Sized from the error count it needs, not from the QA set: n \>= 100 /
  (1 - accuracy) items, so that about 100 are wrong, with accuracy from
  a pilot. At 85% accuracy that is about 670 items, on top of the QA
  set; at 80-90% accuracy the 480 QA questions hold only about 48 to 96
  errors.

- Judge validation:

  100 to 200 blind labels with at least 50 positive and 50 negative
  items, plus 50 labelled by two people for the agreement between them.
  A bare total is not enough: at 10% prevalence 100 labels hold 10
  positives.

The default shares of
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
put 10% of documents in `dev`, 10% in `exploratory`, 30% in
`calibration` and 50% in `test`.

## The file

The CSV is UTF-8 with a byte-order mark, as
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
writes it, so a spreadsheet opens accented text correctly; save it back
as "CSV UTF-8". Leave a decision empty only for an item not yet
labelled.

## See also

[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md),
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md),
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)

Other reference sets:
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md),
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)

## Examples

``` r
qa <- data.frame(document = c("a.pdf", "a.pdf", "b.pdf"),
                 question = c("What was revenue?", "Who audited it?",
                              "When did the trial start?"),
                 model_answer = c("45.2 million", "Not stated", "2019"))
gr_label_sheet("qa", qa)
#>   item_id document                  question answerable answer quote note
#> 1 qa-0001    a.pdf         What was revenue?       <NA>   <NA>  <NA> <NA>
#> 2 qa-0002    a.pdf           Who audited it?       <NA>   <NA>  <NA> <NA>
#> 3 qa-0003    b.pdf When did the trial start?       <NA>   <NA>  <NA> <NA>

path <- file.path(tempdir(), "qa-labels.csv")
gr_label_sheet("qa", qa, path = path)
#> Wrote 3 item(s) to '/tmp/Rtmp4M7RcG/qa-labels.csv', with instructions in '/tmp/Rtmp4M7RcG/qa-labels_instructions.txt'. Read the filled sheet back with gr_read_labels().
readLines(sub("[.]csv$", "_instructions.txt", path))
#>  [1] "Labelling instructions: qa sheet"                                             
#>  [2] ""                                                                             
#>  [3] "Each row is a question about one document. Read the document and fill in:"    
#>  [4] "  answerable  yes or no: does the document answer the question?"              
#>  [5] "  answer      the answer, in your own words (required when answerable is yes)"
#>  [6] "  quote       the passage of the document that gives the answer"              
#>  [7] ""                                                                             
#>  [8] "Use the `note` column for anything worth recording about a row."              
#>  [9] "Leave a row's decisions empty only if you have not labelled it yet."          
#> [10] "Do not change, add or delete `item_id` values or rows."                       
#> [11] "The sheet is blind: it does not show what the model said. Do not look it up." 
#> [12] ""                                                                             
#> [13] "Save the file as CSV UTF-8, keeping its name and columns."                    
#> [14] "Read it back in R with gr_read_labels()."                                     
```
