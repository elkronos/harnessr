# Record a person's decision on screened records

An `"unclear"` record is deferred to a person, and a record whose
screening call failed has no decision at all. `gr_resolve()` is how that
person's decision goes back into the run: the table takes the new
decision, keeps the screener's beside it, and says who decided and when,
and the trace records the same as a step of its own. `forward`,
`deferred` and `included` are rebuilt from the new decisions.

## Usage

``` r
gr_resolve(
  screening,
  document,
  decision,
  by,
  reason = NA_character_,
  at = Sys.time()
)
```

## Arguments

- screening:

  A `gr_screening` from
  [`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md).

- document:

  The records to resolve, by `document` (as in the table) or by
  `document_id`.

- decision:

  `"include"` or `"exclude"`: one for all of `document`, or one each.

- by:

  Who decided: a name or initials. Required, because a decision with no
  one behind it cannot be checked or reported.

- reason:

  Optional: why, one each or one for all.

- at:

  When the decision was made. Defaults to now, and is recorded in UTC.

## Value

The `gr_screening`, with `table` gaining `screener_decision`,
`resolved_by`, `resolved_at` and `resolved_reason` the first time a
record is resolved.

## Details

The screener's own decision is kept in `screener_decision`, and
[`gr_calibrate()`](https://elkronos.github.io/readgpt/reference/gr_calibrate.md)
compares against that one: a calibration over resolved records would
otherwise credit the screener with the person's calls.
[`gr_flow()`](https://elkronos.github.io/readgpt/reference/gr_flow.md)
counts the resolved records in a row of their own.

## See also

[`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md),
[`gr_flow()`](https://elkronos.github.io/readgpt/reference/gr_flow.md),
[`gr_calibrate()`](https://elkronos.github.io/readgpt/reference/gr_calibrate.md)

Other corpus functions:
[`gr_calibrate()`](https://elkronos.github.io/readgpt/reference/gr_calibrate.md),
[`gr_inventory()`](https://elkronos.github.io/readgpt/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/readgpt/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/readgpt/reference/gr_reference.md),
[`gr_search()`](https://elkronos.github.io/readgpt/reference/gr_search.md)

## Examples

``` r
cl <- gr_mock_client(function(messages, params) {
  '{"decision":"unclear","reason":"The excerpt does not say.",
    "criterion":null,"quote":null}'
})
f <- tempfile(fileext = ".txt")
writeLines("Participants were adults.", f)
s <- gr_screen(f, question = "Does the treatment work?",
               include = "Reports a randomised comparison", client = cl)
#> [1/1] file1c0c472d5e48.txt
#> Extracting 'file1c0c472d5e48.txt' with the 'txt' extractor.
#> Ingested 1 block(s), ~9 tokens (0 chars removed by cleaning).
#> Segmenting with 'structural' (cap 900 tokens, overlap 90).
#> Reading with 'screen' (head|1|none) over 1 chunk(s).
s$deferred
#> [1] "/tmp/RtmpMcWAVZ/file1c0c472d5e48.txt"
s <- gr_resolve(s, basename(f), "include", by = "A. Reviewer",
                reason = "Methods section describes randomisation.")
s$table[, c("document", "decision", "screener_decision", "resolved_by")]
#>               document decision screener_decision resolved_by
#> 1 file1c0c472d5e48.txt  include           unclear A. Reviewer
```
