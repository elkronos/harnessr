# Describe an ingestion configuration

Describe an ingestion configuration

## Usage

``` r
gr_ingest_spec(
  clean = "standard",
  ocr = c("auto", "always", "never"),
  ocr_lang = "eng",
  ocr_dpi = 300,
  ocr_min_chars = 40L,
  min_chars = 20L,
  extractor = NULL,
  parallel = NULL,
  cleaner_opts = list(),
  layout = c("auto", "raw"),
  layout_opts = list(),
  ocr_trigger = c("raw_text", "after_running_lines"),
  ocr_confidence = FALSE
)
```

## Arguments

- clean:

  A preset name (`"none"`, `"minimal"`, `"standard"`, `"academic"`,
  `"scan"`, `"legacy"`) or a character vector of cleaner names from
  [`gr_cleaners()`](https://elkronos.github.io/harnessr/reference/gr_cleaners.md).

- ocr:

  `"auto"` (OCR pages with no text layer), `"always"`, or `"never"`.

- ocr_lang:

  Tesseract language code.

- ocr_dpi:

  Render density for PDF OCR.

- ocr_min_chars:

  A page with fewer characters than this is treated as needing OCR under
  `ocr = "auto"`. Zero or more; `Inf` marks every page. Anything else
  warns and uses 40.

- min_chars:

  Refuse the document if less than this much text survives.

- extractor:

  Force a specific extractor name instead of dispatching on the file
  extension.

- parallel:

  Parallelise page-level OCR.

- cleaner_opts:

  Extra options passed to individual cleaners, as a named list. The
  built-in cleaners read these:

  `references_after` (0.4)

  :   For the `references` cleaner (in the `academic` and `legacy`
      presets): a References, Bibliography or Works cited heading, on a
      line of its own and optionally numbered or a Markdown heading such
      as `## References`, and not inside a fenced code block, ends the
      text only when it starts at or after this share of the text, so an
      entry in a table of contents does not cut the document. A number
      in \[0, 1\]; a value that cannot be read warns and uses 0.4.
      Untested: set when the cleaner was written.

  `header_max_chars` (80)

  :   For the `headers_footers` cleaner (in the `scan` preset): the
      longest line, in characters, that can be taken for a running head
      or foot. Untested.

  `header_min_repeats` (3)

  :   For `headers_footers`: how many times a line must recur to be
      taken for one. Values below 3 are read as 3, and a text of fewer
      than 8 lines is left alone. Untested.

- layout:

  How a PDF page's text is put in reading order. `"auto"` drops running
  heads and feet (short lines repeated at the top or bottom of many
  pages), reads a page set in two columns one column after the other,
  and marks headings, taken from the PDF's bookmarks or recognised as a
  standard section name ("Introduction", "Methods" and so on), so blocks
  carry sections. `"raw"` keeps each page as pdftools lays it out. Other
  formats are not affected. Stored in the spec only when it is not
  `"auto"`, so a default spec keeps the cache and store keys it had
  before the setting existed.

- layout_opts:

  Under `layout = "auto"`, a named list that changes how running heads
  and feet are found on PDF pages: `depth` (2, lines at each edge of a
  page that are candidates), `share` (0.4, the share of pages a line
  must recur on), `min_pages` (3, the fewest pages a document needs
  before any line is dropped, and the fewest a line must recur on),
  `max_chars` (200, the longest candidate line) and `max_words` (5,
  above which a numbered line must carry its number where a page number
  is set). Names left out keep these defaults, which were set when the
  PDF reader was written and are untested. An unknown name is an error.
  Stored in the spec only when it is not empty.

- ocr_trigger:

  Under `ocr = "auto"`, which of a PDF page's text `ocr_min_chars` is
  counted on. `"raw_text"` (the default) counts the whole text layer, as
  before. `"after_running_lines"` counts what is left once the running
  heads, feet and stamps that `layout = "auto"` drops are taken out
  (with `layout_opts`), so a scanned page whose text layer holds only a
  60-character fax header or Bates stamp repeated on every page is
  OCR-ed. Untested.

- ocr_confidence:

  `TRUE` gives each block of a PDF page that OCR read an
  `ocr_confidence` column: Tesseract's mean word confidence for the
  page, from 0 to 100, from a second Tesseract pass over the page.
  `FALSE` (the default) skips that pass, so OCR takes the time it did
  before, and the blocks have no such column. Untested.

## Value

A list of class `gr_ingest_spec`.

## Where the defaults come from

Each setting's default, its tier and the evidence behind the value, as
in
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).

- `ocr` (default `"auto"`, basic): untested. OCR only where a page has
  no text layer; not compared.

- `layout` (default `"auto"`, advanced): untested. The layout pass is
  on; checked on the PDFs in the tests, with no measured comparison
  against "raw".

- `clean` (default `"standard"`, basic): untested. The preset meant for
  born-digital text; not compared.

- `ocr_lang` (default `"eng"`, advanced): untested. English, the
  language of the package's own examples.

- `ocr_dpi` (default `300`, advanced): cited. Tesseract's documentation
  on improving output quality recommends images of at least 300 DPI; not
  measured here.

- `ocr_min_chars` (default `40`, advanced): untested. Set when OCR was
  added; not tuned.

- `min_chars` (default `20`, basic): untested. A floor that catches an
  empty extraction; not tuned.

- `extractor` (default `NULL`, advanced): untested. Not a tuned value:
  NULL chooses by file type.

- `parallel` (default `NULL`, advanced): untested. Not a tuned value:
  NULL follows gr_options("parallel"). It does not change output.

- `cleaner_opts` (default [`list()`](https://rdrr.io/r/base/list.html),
  advanced): untested. Empty: each cleaner uses its own defaults, listed
  under `cleaner_opts`.

- `layout_opts` (default [`list()`](https://rdrr.io/r/base/list.html),
  advanced): untested. Empty: the pass uses the values it was written
  with, listed under `layout_opts`; none was tuned.

- `ocr_trigger` (default `"raw_text"`, advanced): untested. "raw_text"
  counts the whole text layer, as before; not compared with
  "after_running_lines".

- `ocr_confidence` (default `FALSE`, advanced): untested. FALSE: OCR
  runs one Tesseract pass per page, as before. Not compared with TRUE.

## See also

[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md),
[`gr_cleaners()`](https://elkronos.github.io/harnessr/reference/gr_cleaners.md)
for the individual step names,
[`gr_clean()`](https://elkronos.github.io/harnessr/reference/gr_clean.md)
to preview a configuration on your own text

Other ingest functions:
[`gr_clean()`](https://elkronos.github.io/harnessr/reference/gr_clean.md),
[`gr_cleaners()`](https://elkronos.github.io/harnessr/reference/gr_cleaners.md),
[`gr_document`](https://elkronos.github.io/harnessr/reference/gr_document.md),
[`gr_extractors()`](https://elkronos.github.io/harnessr/reference/gr_extractors.md),
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md),
[`gr_register_cleaner()`](https://elkronos.github.io/harnessr/reference/gr_register_cleaner.md),
[`gr_register_extractor()`](https://elkronos.github.io/harnessr/reference/gr_register_extractor.md)

## Examples

``` r
# What each preset costs you, on a real document, before any model call.
vapply(c("none", "minimal", "standard", "academic", "scan"),
       function(p) gr_ingest(gr_example(), gr_ingest_spec(clean = p))$stats$chars,
       integer(1))
#> Using cached ingestion for this document + settings.
#> Extracting 'annual_report.md' with the 'md' extractor.
#> Ingested 19 block(s), ~586 tokens (0 chars removed by cleaning).
#> Using cached ingestion for this document + settings.
#> Extracting 'annual_report.md' with the 'md' extractor.
#> Ingested 13 block(s), ~499 tokens (203 chars removed by cleaning).
#> Extracting 'annual_report.md' with the 'md' extractor.
#> Ingested 17 block(s), ~574 tokens (12 chars removed by cleaning).
#>     none  minimal standard academic     scan 
#>     1858     1858     1846     1655     1846 

# Or name the steps yourself; see gr_cleaners() for what is available.
gr_ingest_spec(clean = c("page_numbers", "references"), ocr = "never")$clean
#> [1] "page_numbers" "references"  

# A bibliography heading counts only in the last half of the text.
gr_ingest_spec(clean = "academic", cleaner_opts = list(references_after = 0.5))
#> $clean
#> [1] "academic"
#> 
#> $ocr
#> [1] "auto"
#> 
#> $ocr_lang
#> [1] "eng"
#> 
#> $ocr_dpi
#> [1] 300
#> 
#> $ocr_min_chars
#> [1] 40
#> 
#> $min_chars
#> [1] 20
#> 
#> $extractor
#> NULL
#> 
#> $parallel
#> NULL
#> 
#> $cleaner_opts
#> $cleaner_opts$references_after
#> [1] 0.5
#> 
#> 
#> attr(,"class")
#> [1] "gr_ingest_spec"
```
