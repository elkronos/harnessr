# Count what happened to every document

The numbers a flow diagram is made of, from what a run already recorded.
Every source is accounted for at every stage it reached, so the
arithmetic closes: nothing leaves the count without a row saying why.

## Usage

``` r
gr_flow(screening = NULL, extraction = NULL, records = NULL, claims = NULL)
```

## Arguments

- screening:

  A `gr_screening` from
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
  or `NULL`.

- extraction:

  A `gr_extraction` from
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  or `NULL`.

- records:

  A
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
  so the counts begin where the search did: records identified,
  duplicates removed, reports sought and reports never retrieved.
  Without one the diagram starts at "sources given", which is already
  past the step that decides whether the review can be repeated.

- claims:

  A
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  result, to add the claim-level counts.

## Value

A data frame of `stage`, `n` and `note`.

## Details

For a screening, the records screened split into include, exclude,
unclear, could not be read (no screening call was made) and screening
call failed, and those five rows sum to "screened". "resolved by a
person" counts the decisions above that a person made with
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md).
"kept for full text" is `$forward` (include and unclear), and "deferred
to full text" the unclear part of it, `$deferred`.

## See also

[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md),
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)

## Examples

``` r
cl <- gr_mock_client(function(messages, params) {
  '{"decision":"include","reason":"Reports a revenue figure.",
    "criterion":"Reports a revenue figure","quote":null}'
})
f <- tempfile(fileext = ".txt"); writeLines("Revenue was 45.2 million.", f)
s <- gr_screen(f, question = "What was revenue?",
               include = "Reports a revenue figure", client = cl)
#> [1/1] file1baf2e55ad0b.txt
#> Extracting 'file1baf2e55ad0b.txt' with the 'txt' extractor.
#> Ingested 1 block(s), ~11 tokens (0 chars removed by cleaning).
#> Segmenting with 'structural' (cap 900 tokens, overlap 90).
#> Reading with 'screen' (head|1|none) over 1 chunk(s).
gr_flow(s)
#>                      stage n
#> 1            sources given 1
#> 2       duplicates removed 0
#> 3                 screened 1
#> 4                  include 1
#> 5                  exclude 0
#> 6                  unclear 0
#> 7        could not be read 0
#> 8    screening call failed 0
#> 9     resolved by a person 0
#> 10      kept for full text 1
#> 11   deferred to full text 0
#>                                                                                                                                  note
#> 1                                                                                                                                    
#> 2                                                                                        same cleaned text as a document already seen
#> 3                                                                                                                                    
#> 4                                                                                                                                    
#> 5                                                                                                                                    
#> 6                                                                                 the excerpt did not settle it; deferred to a person
#> 7  no decision was recorded; these are outstanding. No screening call was made: the document could not be read, or a limit stopped it
#> 8                            no decision was recorded; these are outstanding. The call failed or its reply was not the form asked for
#> 9                                                                decided with gr_resolve(); counted above under the person's decision
#> 10                                                                                                      include and unclear: $forward
#> 11         unclear: $deferred. gr_extract(screening) reads only the included ones in this release, and warns when it leaves these out
```
