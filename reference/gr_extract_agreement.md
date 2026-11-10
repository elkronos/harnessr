# Agreement between two extraction tables, field by field

Compares two tables that filled one schema for the same documents: a
model's
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
result against a person's, or two people's. Rows are matched on the `by`
column and each field is compared on its own, with Krippendorff's alpha
at the level of measurement the field has.

## Usage

``` r
gr_extract_agreement(
  x,
  y,
  fields = NULL,
  levels = NULL,
  by = "document",
  B = 2000,
  conf = 0.95,
  seed = 1
)
```

## Arguments

- x, y:

  The two tables:
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  results, or data frames with a `by` column and one column per field.
  Which is the reference does not matter, since alpha and percent
  agreement are symmetric.

- fields:

  Which fields to compare: a character vector of column names, a
  [`gr_fields()`](https://elkronos.github.io/harnessr/reference/gr_fields.md)
  schema or a
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md).
  A schema or protocol also gives each field's type, from which its
  level and the way its values are read follow. `NULL` takes the schema
  of `x` (or `y`) when it is a
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result, and otherwise every column the two tables share other than
  `by` and the extraction table's bookkeeping columns.

- levels:

  The level of measurement of each field: `"nominal"`, `"ordinal"`,
  `"interval"` or `"ratio"`. A character vector named by field, or one
  unnamed value for every field. A field not named takes its level from
  its type: `"interval"` for `integer` and `number` fields, `"nominal"`
  for `string`, `enum` and `boolean` ones. An ordinal `enum` field is
  ordered as its `values` are declared; the ordinal level is an error
  for a field with no declared order (a `string` field, or a column with
  no schema that is not numeric or logical). The interval and ratio
  levels are an error for `enum` and `boolean` fields.

- by:

  The column that names the document in both tables.

- B, conf, seed:

  Bootstrap resamples for the alpha interval (0 for none), the
  confidence level, and the seed. The caller's random state is left as
  it was.

## Value

An object of class `gr_extract_agreement`:

- `table`:

  One row per field and part: `field`, `part`, `level`, `n` (documents
  compared), `percent_agreement`, `alpha`, `lower`, `upper`,
  `not_reported_x`, `not_reported_y`, `unknown` (matched documents left
  out because a cell was unknown) and `note`, which says why alpha is
  `NA` when it is.

- `pairs`:

  Long form, one row per document and field: `document`, `field`, the
  two values as text (`x`, `y`) and whether each was a value, not
  reported or unknown (`x_state`, `y_state`). Filter it on `x != y` to
  read the disagreements.

- `unmatched`:

  The documents only one table has, as a list with `x` and `y`. They are
  not compared.

- `notes`, `conf`, `bootstrap`:

  As in
  [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md).

## Not reported

A cell that is empty, `NA`, or says "not reported", "not stated", "N/A"
or the like is read as the document not reporting the field. In a
nominal field that is one more category, so one side filling a field the
other found unreported is a disagreement like any other. An ordinal,
interval or ratio field cannot place "not reported" on its scale, so it
gets two rows: `part = "reported"`, the nominal agreement on whether the
field is reported at all, and `part = "value"`, the agreement on the
value among the documents where both tables report it. A nominal field
has the single row `part = "value"`.

A cell is unknown, and left out of that field, when the value is there
but cannot be read as the field's type ("120 (60 per arm)" in an integer
field, an undeclared `enum` value), and in a
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
result when the document was not read in full: a `"failed"` or
`"skipped"` row is unknown in every field, and an empty cell of an
`"incomplete"` row is unknown rather than not reported. A row that
duplicates another document is left out, so no document counts twice. A
data frame with a `status` column is read the same way.

## How values are compared

A `string` value is compared after folding case, quote marks, spaces and
a trailing full stop, as
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
does when two parts of one document give one value two ways. Nothing
else is folded, so "RCT" and "randomised controlled trial" are two
values. An `enum` value is matched to the declared values ignoring case.
Numbers are read as
[`gr_field()`](https://elkronos.github.io/harnessr/reference/gr_field.md)
describes and compared exactly, so percent agreement on a numeric field
counts identical values; alpha at the interval or ratio level gives
partial credit for near misses.

## Alpha

Krippendorff's alpha is 1 - D_o / D_e, observed over expected
disagreement computed from the coincidence matrix with the difference
function of the level (Krippendorff 2011). Its interval is a percentile
bootstrap over documents (Hayes and Krippendorff 2007). Alpha is
reported only when at least 30 documents are compared and the field is
not constant; otherwise it is `NA`, `note` says why, and percent
agreement is the figure to read. Agreement between a model and a person
measures how far the model's table could stand in for a person's, not
which of the two is right.

## References

Hayes, A. F. and Krippendorff, K. (2007). Answering the call for a
standard reliability measure for coding data. *Communication Methods and
Measures*, 1(1), 77-89.

Krippendorff, K. (2011). Computing Krippendorff's alpha-reliability.
University of Pennsylvania, Annenberg School for Communication.

## See also

[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md),
[`gr_fields()`](https://elkronos.github.io/harnessr/reference/gr_fields.md)

## Examples

``` r
fields <- gr_fields(
  design = gr_field("Study design", type = "enum",
                    values = c("rct", "cohort", "case series")),
  n      = gr_field("Number randomised", type = "integer")
)
model <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf", "d.pdf"),
                    design = c("rct", "cohort", "rct", NA),
                    n = c(120, 85, NA, 40))
person <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf", "d.pdf"),
                     design = c("RCT", "cohort", "rct", "case series"),
                     n = c(120, 58, NA, 40))
ag <- gr_extract_agreement(model, person, fields = fields, B = 0)
ag
#> <gr_extract_agreement> 2 field(s), 4 document(s) matched
#> 
#>   field     part    level n percent_agreement alpha lower upper not_reported_x
#>  design    value  nominal 4             0.750    NA    NA    NA              1
#>       n reported  nominal 4             1.000    NA    NA    NA              1
#>       n    value interval 3             0.667    NA    NA    NA              1
#>  not_reported_y unknown
#>               0       0
#>               1       0
#>               1       0
#> 
#> Alpha intervals at 95%; bootstrap over documents, B = 0, seed 1.
#> Note (design, value): Only 4 pairable item(s); alpha needs at least 30, so percent agreement is reported instead.
#> Note (n, reported): Only 4 pairable item(s); alpha needs at least 30, so percent agreement is reported instead.
#> Note (n, value): Only 3 pairable item(s); alpha needs at least 30, so percent agreement is reported instead.
subset(ag$pairs, x != y)
#>   document  field            x           y      x_state y_state
#> 4    d.pdf design not reported case series not reported   value
#> 6    b.pdf      n           85          58        value   value
```
