# Getting text out of files

Before a model can read a document, the text has to come out of the
file. That step, *ingestion*, is easy to overlook and hard to undo. Text
lost here, or damaged by too much clean-up, is text no model will see,
however good the rest of the pipeline is. This guide covers what
harnessr can read, what it keeps, what it removes, and how to check a
folder before spending anything on it.

[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
introduces the package and the ideas used here.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE)
```

## What ingestion produces

[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
reads a file and returns a *document*: the text split into *blocks*,
which are the paragraphs, headings and list items as the file has them.
harnessr includes a short example, an annual report written in Markdown:

``` r

doc <- gr_ingest(gr_example())
doc
#> <gr_document> /home/runner/work/_temp/Library/harnessr/extdata/annual_report.md
#>   17 blocks, ~574 tokens, 1846 chars (12 removed by cleaning)
#>   cleaners: page_numbers, hyphenation, control_chars, ligatures, collapse_whitespace
#>   first block: # Northwind Instruments — Annual Report 2024
```

Each block records where it came from: the page, for formats that have
pages, and the section heading it sits under:

``` r

doc$blocks[1:6, c("block_id", "page", "section", "kind")]
#>   block_id page                                    section    kind
#> 1        1   NA Northwind Instruments — Annual Report 2024 heading
#> 2        2   NA                                    Summary heading
#> 3        3   NA                                    Summary    body
#> 4        4   NA                                    Summary    body
#> 5        5   NA                                 Operations heading
#> 6        6   NA                                 Operations    body
```

This *provenance* is what lets an answer point back to where it came
from: `ans$evidence` reports the page and section of every chunk an
answer rests on. `page` is `NA` here because Markdown has no pages; a
PDF fills it in.

`doc$text` is all the blocks joined, and `doc$stats` summarises the
document:

``` r

unlist(doc$stats[c("blocks", "chars", "tokens", "chars_removed")])
#>        blocks         chars        tokens chars_removed 
#>            17          1846           574            12
```

You rarely need to call
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
yourself, since
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
does it for you. Calling it directly shows you what the model will get.

## What harnessr can read

Each file type is handled by an *extractor*, chosen by the file’s
extension. `available` says whether the packages it needs are installed:

``` r

gr_extractors()[, c("name", "extensions", "available")]
#>        name                          extensions available
#> txt     txt            txt, text, log, csv, tsv      TRUE
#> md       md              md, markdown, rmd, qmd      TRUE
#> html   html                    html, htm, xhtml      TRUE
#> pdf     pdf                                 pdf      TRUE
#> docx   docx                          docx, dotx      TRUE
#> image image png, jpg, jpeg, tif, tiff, bmp, gif      TRUE
```

| extractor | what it keeps | needs |
|----|----|----|
| `txt` | paragraphs, split at blank lines | nothing |
| `md` | paragraphs, plus headings as sections and code blocks and tables marked as such | nothing |
| `html` | text inside `<h1>` to `<h4>`, `<p>`, `<li>`, `<td>`, `<pre>` and `<blockquote>`; text anywhere else (a bare `<div>`, `<h5>`, `<th>`) is dropped, as are scripts, styles, navigation bars and footers | `xml2` |
| `docx` | paragraphs, with headings as sections in any interface language; each table row as one block, its cells joined by a vertical bar; footnotes and endnotes after the paragraph that cites them; images inside the file are read by OCR when `tesseract` is installed | `xml2` |
| `pdf` | the text of each page in reading order, with its page number and headings as sections; pages with no text are read by OCR | `pdftools` (and `tesseract` and `magick` for OCR) |
| `image` | the text in a picture, by OCR | `tesseract` |

A file whose extension no extractor claims, such as an old `.doc` or a
spreadsheet, is not read.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
below, finds those before a run rather than during one.

You can also pass text directly. A string that is not the path of an
existing file is read as the document itself:

``` r

memo <- gr_ingest("Revenue rose to 45.2 million dollars.\n\nHeadcount grew to 1,204.")
memo$blocks[, c("block_id", "text")]
#>   block_id                                  text
#> 1        1 Revenue rose to 45.2 million dollars.
#> 2        2              Headcount grew to 1,204.
```

The exception is a string that ends in an extension some extractor
claims but names no file. That is an error:

``` r

gr_ingest("anual-report.pdf")
#> Error in `gr_ingest()`:
#> ! File not found: 'anual-report.pdf'. If you meant to pass document text rather than a path, it must not end in something that looks like a file extension.
```

Any other string is read as text, including a path whose extension is
mistyped or is one no extractor claims. A string that looks like a path
(it has a `/` and an extension) also raises a warning, since the answer
that follows would be about a file name:

``` r

typo <- gr_ingest("reports/2024/annual-report.pfd")
#> Warning in gr_ingest("reports/2024/annual-report.pfd"):
#> 'reports/2024/annual-report.pfd' is not an existing file, and '.pfd' is not an
#> extension harnessr reads, so the string itself is being read as the document.
#> If it is a path, check it; harnessr reads .bmp, .csv, .docx, .dotx, .gif, .htm,
#> .html, .jpeg, .jpg, .log, .markdown, .md, .pdf, .png, .qmd, .rmd, .text, .tif,
#> .tiff, .tsv, .txt, .xhtml.
typo$text
#> [1] "reports/2024/annual-report.pfd"
typo$source
#> [1] "<inline text>"
```

`source` is how to tell the two apart: it holds the path when a file was
read, and `<inline text>` when the string itself was.

A web address is downloaded and read with the extractor for what the
server sent back: a specific type it declares, else the extension in the
address, else the first bytes of the file, which settle a PDF, a Word
file or an HTML page however they were labelled. A download no extractor
reads is refused rather than read as text. `source` holds the address,
and a download that fails is an error that says why:

``` r

doc <- gr_ingest("https://example.org/reports/annual-report-2024.pdf")
doc$source
#> [1] "https://example.org/reports/annual-report-2024.pdf"
```

Within a session an address is downloaded once; the next read of it
comes from the cache, as a file does.

## Sections and headings

For Markdown, HTML, Word and PDF files, each block records the heading
it falls under (the next section says how a PDF’s headings are found).
The example report has these sections:

``` r

unique(doc$blocks$section)
#> [1] "Northwind Instruments — Annual Report 2024"
#> [2] "Summary"                                   
#> [3] "Operations"                                
#> [4] "Risk factors"                              
#> [5] "Outlook"                                   
#> [6] "References"
```

Sections matter later. The `structural` way of cutting a document into
chunks never lets a chunk straddle two sections
([`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md)),
and the `preview` reading strategy plans its reading section by section.
A plain text file has no headings, so its blocks have no section.

## PDFs

A PDF is read page by page, and every block carries its page number.
That is what lets a quotation be traced to “page 12” rather than to
“somewhere in the file”.

``` r

pdf_file <- tempfile(fileext = ".pdf")
grDevices::pdf(pdf_file, width = 8.5, height = 11)
for (page in list(c("Summary", "Revenue was 45.2 million dollars in fiscal 2024."),
                  c("Outlook", "The board expects revenue of 50 million dollars in 2025."))) {
  graphics::plot.new()
  graphics::text(0, c(0.95, 0.9), page, adj = 0)
}
invisible(grDevices::dev.off())

report <- gr_ingest(pdf_file)
report$blocks[, c("page", "section", "kind", "text")]
#>   page section    kind                                                     text
#> 1    1 Summary heading                                                  Summary
#> 2    1 Summary    body         Revenue was 45.2 million dollars in fiscal 2024.
#> 3    2 Summary    body                                                  Outlook
#> 4    2 Summary    body The board expects revenue of 50 million dollars in 2025.
```

A PDF’s text comes out as the page looks, which is not always the order
a person reads in, so harnessr puts it back in reading order:

- A page set in two columns is read one column after the other. Without
  this, each line would join the start of a line from each column.
- Running heads and feet (short lines repeated at the top or bottom of
  many pages, such as a journal name or “Page 3 of 12”) are removed.
- Headings are found, so blocks carry sections as they do for Markdown
  and Word. They come from the PDF’s bookmarks when it has them.
  Otherwise a line that is only a standard section name (“Introduction”,
  “2. Methods”, “Results”) counts. That is how “Summary” was found
  above; “Outlook” is not a standard name, so it stayed text.

`gr_ingest_spec(layout = "raw")` turns all three off and keeps each page
as it is laid out. Footnotes, tables and pages in three or more columns
can still come out in an order that reads oddly, so check a few pages of
`report$text` before relying on a new kind of PDF.

## Scanned pages and OCR

A scanned PDF is a picture of text, with no text inside it to extract.
Reading it needs *optical character recognition* (OCR), which turns the
picture back into text. OCR is slow (seconds per page) and never
perfect, so harnessr uses it only where it is needed:

``` r

# The default: OCR any page with fewer than 40 characters of text.
gr_ingest("scan.pdf", gr_ingest_spec(ocr = "auto"))

# A page with a little text but mostly scanned content: raise the threshold.
gr_ingest("scan.pdf", gr_ingest_spec(ocr = "auto", ocr_min_chars = 200))

# Everything, or nothing.
gr_ingest("scan.pdf", gr_ingest_spec(ocr = "always"))
gr_ingest("born-digital.pdf", gr_ingest_spec(ocr = "never"))

# Another language, at a higher resolution.
gr_ingest("scan.pdf", gr_ingest_spec(ocr_lang = "deu", ocr_dpi = 400))
```

OCR on PDFs needs both `tesseract` and `magick`. Without them a scanned
page comes back nearly empty and harnessr warns (`gr_ocr_unavailable`).
The document lists those pages in `doc$stats$unread_pages`, and an
answer drawn from it is marked partial. The same holds with
`ocr = "never"`: a page with no text, or only a stamp or a running head,
is listed as unread. A document with too little text left is refused
outright, as the next section shows. The `"scanned"` recipe is set up
for this kind of document.

## Cleaning

Extracted text is rarely clean. PDFs break words across lines with
hyphens, repeat the page number on every page, and use typographic
ligatures (“ﬁ” for “fi”). harnessr tidies this with *cleaners*. Each
does one job and can be turned on or off:

``` r

gr_cleaners()[, c("name", "stage", "default_on")]
#>                   name stage default_on
#> 1             captions early      FALSE
#> 2               emails early      FALSE
#> 3      headers_footers early      FALSE
#> 4          hyphenation early       TRUE
#> 5         page_numbers early       TRUE
#> 6           references early      FALSE
#> 7                 urls early      FALSE
#> 8           ascii_only  late      FALSE
#> 9  collapse_whitespace  late       TRUE
#> 10       control_chars  late       TRUE
#> 11           ligatures  late       TRUE
#> 12           lowercase  late      FALSE
#> 13      remove_numbers  late      FALSE
#> 14  remove_punctuation  late      FALSE
```

The five marked `default_on` run unless you say otherwise. The ones
below are off by default, for these reasons:

- `remove_numbers` replaces every digit with a space, which makes any
  question about a figure, date or percentage unanswerable.
- `captions` removes lines that look like figure and table captions,
  which destroys documents made mostly of tables.
- `urls` and `emails` remove links and addresses, which are sometimes
  the answer.
- `references` cuts everything from a line reading just “References”,
  “Bibliography” or “Works cited” to the end of the document, when that
  line starts at or after 40% of the text, so a table of contents near
  the start does not cut the document.
  `cleaner_opts = list(references_after = )` moves that share, a number
  from 0 to 1. The cut loses the reference list if your question is
  about the sources. A Markdown heading such as `## References` is not
  such a line, so it does not trigger the cut.

Cleaning cannot be undone later: no reader can recover what it removes.
Know what each choice costs before you make it.

### Presets

Instead of naming cleaners one by one, use a *preset*:

| preset | what it runs |
|----|----|
| `"none"` | nothing |
| `"minimal"` | control characters and whitespace only |
| `"standard"` | the default: page numbers, broken hyphens, control characters, ligatures, whitespace |
| `"academic"` | standard, plus `captions` and `references` |
| `"scan"` | standard, plus repeated page headers and footers |
| `"legacy"` | what the first version of this package did, number stripping included; for comparison only |

Here is how much text each leaves of the example report:

``` r

presets <- c("none", "minimal", "standard", "academic", "scan", "legacy")
vapply(presets, function(p) gr_ingest(gr_example(), gr_ingest_spec(clean = p))$stats$chars,
       integer(1))
#>     none  minimal standard academic     scan   legacy 
#>     1858     1858     1846     1765     1846     1659
```

Or name the cleaners yourself:

``` r

tidy <- gr_ingest(gr_example(),
                  gr_ingest_spec(clean = c("page_numbers", "hyphenation", "collapse_whitespace")))
tidy$stats$chars
#> [1] 1846
```

### Seeing what cleaning removed

Every document records what each cleaner took out, in characters:

``` r

vapply(doc$stats$clean_log, function(step) step$chars_removed, integer(1))
#>        page_numbers         hyphenation       control_chars           ligatures 
#>                  12                   0                   0                   0 
#> collapse_whitespace 
#>                   0
```

A negative number means a cleaner added characters, for example by
expanding “ﬁ” to “fi”. If a cleaner removed far more than you expected,
turn it off and compare.

[`gr_clean()`](https://elkronos.github.io/harnessr/reference/gr_clean.md)
runs cleaners on any text, so you can try a configuration on a few of
your own lines first. Cleaners always run in two stages, `early` before
`late`, whatever order you list them in; otherwise number removal would
strip the “1” from “Page 1” before the page-number cleaner could
recognise the line:

``` r

cleaned <- gr_clean(c("Page 1", "Revenue rose to 45.2 million in 2024."),
                    steps = c("remove_numbers", "page_numbers"))
as.character(cleaned)
#> [1] ""                                  "Revenue rose to  .  million in  ."
```

The second line shows why `remove_numbers` is off by default.

## When too little text is left

A document with almost no text after cleaning (a scan read without OCR,
an empty file, a PDF of images) is refused rather than sent to the
model. A model shown nothing would answer “not in the document” for a
document that may well contain the answer:

``` r

gr_ingest("Tiny.")
#> Error in `gr_ingest()`:
#> ! Only 5 characters survived ingestion of '<inline text>' (minimum 20). The file may be empty, image-only with OCR disabled, or your cleaning steps may be too aggressive: 0 characters were removed by cleaners: page_numbers(-0) hyphenation(-0) control_chars(-0) ligatures(-0) collapse_whitespace(-0).
```

The limit is `min_chars` (20 characters by default) in
[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md).

## Reading the same file twice

Ingestion is cached for the rest of the R session. Asking a second
question of the same file, or trying a different way of cutting it into
chunks, reuses the extracted text instead of reading the file again. The
cache notices when the file changes (its size or modification time) and
when any ingestion setting changes. Turn it off with
`gr_options(cache_documents = FALSE)`.

## Before reading a whole folder

A folder of documents hides problems that a single file makes obvious: a
few old `.doc` files nobody can read, scanned PDFs without text, an
empty file, or a subfolder you forgot about.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
finds all of these in seconds, without calling a model and without an
API key:

``` r

inbox <- file.path(tempdir(), "inbox")
dir.create(inbox, showWarnings = FALSE)
invisible(file.copy(gr_example(), file.path(inbox, "annual_report.md"),
                    overwrite = TRUE))
writeLines("Headcount grew to 1,204 employees across nine sites.",
           file.path(inbox, "notes.txt"))
writeLines("(a Word 97 document)", file.path(inbox, "minutes.doc"))
invisible(file.create(file.path(inbox, "empty.txt")))

inv <- gr_inventory(inbox)
inv
#> <gr_inventory> /tmp/RtmpDwZCJ1/inbox
#>   4 file(s), 1.9 KB; 2 readable
#>   2 ready, 1 no_extractor, 1 empty
#>   tokens: 549   cost floor: $0.01 (gpt-5.6-terra, one call per document)
#>   ! 1 file(s) would be skipped: .doc (1). gr_register_extractor() adds a format.
```

It lists every file, including the ones that will not be read, because
“one file will be skipped” is exactly what you need to know before the
run:

``` r

inv$files[, c("file", "extractor", "status", "tokens")]
#>               file extractor       status tokens
#> 1 annual_report.md        md        ready    531
#> 2        empty.txt       txt        empty     NA
#> 3      minutes.doc      <NA> no_extractor     NA
#> 4        notes.txt       txt        ready     18
```

The statuses:

| status | meaning |
|----|----|
| `ready` | an extractor can read it, and there is text |
| `needs_ocr` | a PDF whose pages have no text; it needs OCR |
| `needs_package` | an extractor can read it, but its package is not installed |
| `no_extractor` | no extractor reads this kind of file |
| `empty` | nothing to read |
| `unreadable` | it could not be opened; `note` says why |

It shows three things a corpus run would otherwise hide:

| what it shows | why it matters |
|----|----|
| files no extractor claims | they were dropped without appearing anywhere, so a folder of `.doc` files read as an empty corpus |
| PDFs with no text layer | they extract to nothing, then answer `NOT_IN_DOCUMENT`, which looks the same as a document that does not say |
| files in subfolders | they are listed with their `folder`, so a subfolder you forgot is visible; `recursive = FALSE` scans one level only |

`folder` is a column, so `split(inv$files, inv$files$folder)` gives you
the piles.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
does not choose a recipe for you. A router that quietly reads one
document with `retrieve` and another with `stuff` hands you a plausible
answer built on part of a file with nothing saying so. It also makes
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
meaningless, because the corpus no longer had one configuration. Group
the rows yourself and pass each group the recipe you picked; reading a
whole folder is in
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md).

`inv$totals` adds up the tokens and prices one request per readable file
with your model: its tokens in, and an assumed 500-token answer out.
Treat `cost_floor_usd` as a rough guide rather than a bound. Reading
strategies that make several requests per document cost more, and short
answers cost less. Files whose size is unknown until they are read by
OCR are not in the total; `tokens_unknown` counts them.

``` r

unlist(inv$totals[c("readable", "tokens", "cost_floor_usd")])
#>       readable         tokens cost_floor_usd 
#>       2.000000     549.000000       0.013098
```

## Choosing the settings

Two groups of ingest settings change what the model is given: cleaning
and OCR. Each walkthrough below says what the setting controls and what
it trades off, the signs in your results that point to changing it,
where its default came from, and how to test a change.
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
lists every ingest setting with its default.

The tests use
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
which builds one arm per value of a setting, and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
which runs every arm on a reference of questions. Here they run on one
question and a stand-in model that always gives the right answer, so
they show how a sweep is built and read, not which value is better.
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
runs sweeps on a reference with dev and test splits and reads them with
intervals.

``` r

qa <- gr_qa_reference(questions = c(revenue = "What was revenue in 2024?"),
                      documents = gr_example(), answers = list("45.2 million"),
                      split = "dev")
says <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

### Cleaning presets and `references_after`

**What it controls.** `clean` chooses the cleaners that run on the
extracted text, by preset or by name (see “Presets” above), and
`cleaner_opts = list(references_after = )` sets where the `references`
cleaner may cut. Cleaning trades noise against loss: page numbers,
running heads and captions cost tokens and can mislead retrieval, but a
cleaner that removes too much removes it for good, and no later setting
can bring it back.

**Signs it needs changing.** An answer of `NOT_IN_DOCUMENT` for a fact
you can see in the file, or a quotation that fails verification, can
mean a cleaner removed the text; look in `doc$stats$clean_log` for a
cleaner that removed far more than the others. Answers that quote page
headers or figure captions as if they were findings point the other way,
to `"academic"` or `"scan"`. Under `"academic"`, an answer about a
paper’s sources that says they are not in the document means the
reference list was cut. A document whose table of contents has a
“References” line after the first 40% of its text is cut there; raise
`references_after` for such documents.

**Where the defaults came from.** `"standard"` was chosen as the preset
for born-digital text and has not been compared with the others.
`references_after` is 0.4, set when the cleaner was written. Both are
`untested` in `gr_settings_table("ingest")`.

**How to test it.** Sweep the presets and look at what was sent:

``` r

arms <- hr_sweep(gr_arm("fast"), list(clean = c("standard", "academic", "scan", "none")))
bench <- hr_benchmark(arms, qa, runs = 5, client = says, split = "dev",
                      scorer = gr_scorer_answer())
aggregate(tokens_in ~ param.clean, bench, mean)
#>   param.clean tokens_in
#> 1    academic       585
#> 2        none       619
#> 3        scan       611
#> 4    standard       611
hr_sweep_check(bench)
#>               arm             same_as runs requests                settings
#> 1 fast:clean=scan fast:clean=standard    5        5 clean: standard vs scan
```

On the example report, `"academic"` sends 26 fewer prompt tokens than
`"standard"`, because it drops the caption lines, and `"none"` sends 8
more.
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
finds that `"scan"` sent exactly the requests `"standard"` sent: the
example has no running heads, so on it that comparison would measure
nothing but run-to-run spread. The same check tells you whether a
`references_after` sweep reaches your documents at all:

``` r

arms <- hr_sweep(gr_arm("fast", list(clean = "academic")),
                 data.frame(cleaner_opts = I(list(list(references_after = 0.4),
                                                  list(references_after = 0.8)))))
hr_sweep_check(hr_benchmark(arms, qa, runs = 5, client = says, split = "dev",
                            scorer = gr_scorer_answer()))
#>                                              arm
#> 1 fast:cleaner_opts=list(references_after = 0.8)
#>                                          same_as runs requests
#> 1 fast:cleaner_opts=list(references_after = 0.4)    5        5
#>                                                                     settings
#> 1 cleaner_opts: list(references_after = 0.4) vs list(references_after = 0.8)
```

Both values sent the same requests, although the example report ends
with a `## References` heading. The `references` cleaner cuts only at a
line that reads “References”, “Bibliography” or “Works cited” alone,
optionally numbered, so a Markdown heading with its `#` marks is never
cut, wherever it falls. Run the sweep on documents whose heading stands
alone that way, as text extracted from a PDF usually does, with
questions whose answers sit near the end.

### OCR settings

**What it controls.** `ocr` decides which pages are read as pictures:
`"auto"` reads a page by OCR only when it has fewer than `ocr_min_chars`
characters of text (40), `"always"` reads every page that way and
`"never"` none. `ocr_dpi` is the resolution the page is rendered at, and
`ocr_lang` the Tesseract language. OCR costs seconds per page and adds
recognition errors; not running it on a scanned page leaves that page
empty.

**Signs it needs changing.** `doc$stats$unread_pages` lists pages that
came back empty, and an answer from such a document is marked partial. A
scanned page with a printed header or stamp can carry more than 40
characters of text and so skip OCR under `"auto"`: raise
`ocr_min_chars`. Misread numbers or letters in OCR text (a quotation
that fails verification against a page that plainly says it) point to a
higher `ocr_dpi` or the right `ocr_lang`.

**Where the defaults came from.** `ocr_dpi = 300` follows Tesseract’s
documentation on improving output quality (`cited`). `ocr = "auto"` runs
OCR only where a page has no text layer, and no other choice has been
compared. `ocr_min_chars = 40` was set when OCR was added and has not
been tuned, and `ocr_lang = "eng"` is English because the package’s own
examples are in English. All three are `untested`.

**How to test it.** OCR needs a scanned file and the tesseract and
magick packages, so this runs on your own documents, with a reference
built from them by
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
and your own client:

``` r

arms <- hr_sweep(gr_arm("scanned"), list(ocr_min_chars = c(40, 200, 1000)))
bench <- hr_benchmark(arms, my_reference, runs = 5, client = my_client, split = "dev",
                      scorer = gr_scorer_answer())
aggregate(correct ~ param.ocr_min_chars, bench, mean)
hr_sweep_check(bench)
```

A row from
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
means no page crossed the threshold between the two values, so they read
the documents the same way.

## Adding your own

A format harnessr does not know, or a clean-up step your documents need,
can be added and then used exactly like a built-in one. A cleaner that
drops lines marked “CONFIDENTIAL”:

``` r

gr_register_cleaner("drop_confidential", stage = "early",
  fn = function(x, opts) gsub("(?mi)^\\s*CONFIDENTIAL.*$", "", x, perl = TRUE),
  description = "Remove lines marked CONFIDENTIAL")

gr_ingest("CONFIDENTIAL - internal only\n\nRevenue rose to 45.2 million dollars.",
          gr_ingest_spec(clean = c("drop_confidential", "collapse_whitespace")))$text
#> [1] "Revenue rose to 45.2 million dollars."
```

[`?gr_register_extractor`](https://elkronos.github.io/harnessr/reference/gr_register_extractor.md)
shows how to add a file format, and
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
covers every kind of addition.

## Next

Once the text is out, the next decisions are how to cut it into chunks,
covered in
[`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md),
and how the model should read them, covered in
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md).
To read a whole folder once
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
has checked it, see
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md).
