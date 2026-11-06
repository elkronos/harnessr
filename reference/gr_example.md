# Path to the bundled example document

A short Markdown report with headings, figures and dates, used by the
examples in this package so they run without an API key or a file of
your own.

## Usage

``` r
gr_example()
```

## Value

Absolute path to the file.

## See also

[`readgpt_example()`](https://elkronos.github.io/readgpt/reference/readgpt_example.md),
its name before the package was renamed.

## Examples

``` r
gr_ingest(gr_example())
#> Using cached ingestion for this document + settings.
#> <gr_document> /home/runner/work/_temp/Library/harnessr/extdata/annual_report.md
#>   17 blocks, ~574 tokens, 1846 chars (12 removed by cleaning)
#>   cleaners: page_numbers, hyphenation, control_chars, ligatures, collapse_whitespace
#>   first block: # Northwind Instruments — Annual Report 2024
```
