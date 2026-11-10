# Form one decision per document from several reviewers

Turns a sheet that several people filled in into the reference
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
compares the screener with: one consensus decision per document in
`human_decision`, beside each reviewer's own.

## Usage

``` r
gr_reference_consensus(
  reference,
  rule = c("majority", "any_include", "adjudicated")
)
```

## Arguments

- reference:

  The filled-in sheet: a data frame or a path to the CSV.

- rule:

  How a disagreement is settled: `"majority"`, `"any_include"` or
  `"adjudicated"`.

## Value

The sheet in wide form, one row per document, with `human_decision`
holding the consensus and `consensus_from` how each row's was reached
(`"unanimous"`, `"one reviewer"`, `"majority"`, `"tie kept"`,
`"any include"`, `"adjudicated"` or `"no decision"`). The rule is kept
in the attribute `consensus_rule`, and the number of documents the
reviewers disagreed on in `conflicts`.

## Details

The sheet is the one
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
writes with `reviewers` above 1, one `human_decision_<reviewer>` column
per reviewer and a `consensus` column for an adjudicator. Reviewer
columns can be renamed (`human_decision_AB` for a reviewer's initials,
say): every `human_decision_<x>` column is read as one reviewer, except
names ending in `_note`, `_notes`, `_comment`, `_comments` or `_date`,
which are left alone, so give any other column of notes a name that does
not start with `human_decision_`. A long sheet with one row per document
per reviewer, a `reviewer` column and `human_decision`, is read too.

Where the reviewers who judged a record agree, that is its decision,
under every rule; a record only one reviewer judged takes theirs. Where
they disagree:

- `"majority"`: the decision of more than half of them. A tie is settled
  by the `consensus` column where it is filled, and otherwise as
  `"include"`, so a reference never excludes a record half its reviewers
  included. With two reviewers every disagreement is a tie.

- `"any_include"`: `"include"` if any reviewer included it, the
  dual-screening convention of carrying a record forward unless both
  reviewers exclude it.

- `"adjudicated"`: the decision in `consensus`, which an adjudicator
  fills in; a disagreement with none is an error. A filled `consensus`
  takes precedence on every row, agreed or not.

[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
given a multi-reviewer sheet without a consensus applies
`"adjudicated"`, so it stops on a disagreement nobody settled and says
how many there were.

## See also

[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)

Other corpus functions:
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)

## Examples

``` r
sheet <- data.frame(document = paste0("d", 1:4, ".pdf"),
                    human_decision_1 = c("include", "include", "exclude", "exclude"),
                    human_decision_2 = c("include", "exclude", "exclude", "include"),
                    human_decision_3 = c("include", "exclude", "exclude", "exclude"),
                    stringsAsFactors = FALSE)
gr_reference_consensus(sheet, "majority")[, c("document", "human_decision",
                                              "consensus_from")]
#>   document human_decision consensus_from
#> 1   d1.pdf        include      unanimous
#> 2   d2.pdf        exclude       majority
#> 3   d3.pdf        exclude      unanimous
#> 4   d4.pdf        exclude       majority
gr_reference_consensus(sheet, "any_include")$human_decision
#> [1] "include" "include" "exclude" "include"
```
