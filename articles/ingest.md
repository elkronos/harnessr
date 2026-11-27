# Getting text out of files

Before a model can read a document, harnessr has to get the text out of
the file. That step, *ingestion*, is easy to overlook and hard to undo.
Text lost here, or damaged by too much clean-up, stays lost or damaged:
no later step restores it. This guide covers what harnessr can read,
what it keeps and removes, and how to check a folder before you spend
anything on it.

Ingestion makes no model calls, so it rests on only two pieces of the
core. The token counts in `doc$stats` and in
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
come from the counter that “Counting tokens” in
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)
describes. The cost floor that
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
reports uses the prices you set, as “Prices” in
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)
shows.
[`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md)
covers the model calls that later steps make, and
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
introduces the package.

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
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

This record, the *provenance*, lets an answer point back to its source:
`ans$evidence` reports the page and section of every chunk an answer
rests on. `page` is `NA` here because Markdown has no pages; a PDF fills
it in.

`doc$text` is all the blocks joined, and `doc$stats` summarises the
document:

``` r

unlist(doc$stats[c("blocks", "chars", "tokens", "chars_removed")])
#>        blocks         chars        tokens chars_removed 
#>            17          1846           574            12
```

[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
calls
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
for you, so you rarely need it yourself. Call it directly to see what
the model will get.

## What harnessr can read

harnessr reads each file type with an *extractor*, chosen by the file’s
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
| `html` | the text of the page in reading order, with `<h1>` to `<h6>` as sections and each table row as one block, its cells joined by a vertical bar; scripts, styles, navigation bars and footers are dropped | `xml2` |
| `docx` | paragraphs, with headings as sections in any interface language; each table row as one block, its cells joined by a vertical bar; footnotes and endnotes after the paragraph that cites them; images inside the file are read by OCR when `tesseract` is installed | `xml2` |
| `pdf` | the text of each page in reading order, with its page number and headings as sections; pages with no text are read by OCR | `pdftools` (and `tesseract` and `magick` for OCR) |
| `image` | the text in a picture, by OCR | `tesseract` |

harnessr does not read a file whose extension no extractor claims, such
as an old `.doc` or a spreadsheet.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
below, finds those files before a run, not during one.

You can also pass text directly.
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
reads a string that is not the path of an existing file as the document
itself:

``` r

memo <- gr_ingest("Revenue rose to 45.2 million dollars.\n\nHeadcount grew to 1,204.")
memo$blocks[, c("block_id", "text")]
#>   block_id                                  text
#> 1        1 Revenue rose to 45.2 million dollars.
#> 2        2              Headcount grew to 1,204.
```

A string that ends in an extension some extractor claims, but names no
file, is an error:

``` r

gr_ingest("anual-report.pdf")
#> Error in `gr_ingest()`:
#> ! File not found: 'anual-report.pdf'. If you meant to pass document text rather than a path, it must not end in something that looks like a file extension.
```

[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
reads any other string as text, including a path whose extension is
mistyped or is one no extractor claims. If the string looks like a path
(it has a `/` and an extension), you also get a warning, because the
answer that follows would be about a file name:

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

`source` tells the two apart. It holds the path when
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
read a file, and `<inline text>` when it read the string itself.

[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
downloads a web address and reads it with the extractor for what the
server sent back. It looks, in order, at:

1.  a specific type the server declares;
2.  the extension in the address;
3.  the first bytes of the file, which identify a PDF, a Word file or an
    HTML page however they were labelled.

[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
refuses a download no extractor reads; it does not fall back to reading
it as text. `source` holds the address, and a failed download is an
error that says why:

``` r

doc <- gr_ingest("https://example.org/reports/annual-report-2024.pdf")
doc$source
#> [1] "https://example.org/reports/annual-report-2024.pdf"
```

Within a session, harnessr downloads an address once and serves later
reads of it from the cache, as it does for a file.

## Sections and headings

In Markdown, HTML, Word and PDF files, each block records the heading it
falls under (the next section says how harnessr finds a PDF’s headings).
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

Later steps use them. The `structural` way of cutting a document into
chunks never lets a chunk straddle two sections
([`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md)),
and the `preview` reading strategy plans its reading section by section.
A plain text file has no headings, so its blocks have no section.

## PDFs

harnessr reads a PDF page by page, and every block carries its page
number, so you can trace a quotation to “page 12” rather than to
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

A PDF’s text comes out in the order of the page layout, which is not
always the order a person reads in. harnessr puts it back in reading
order:

- A page set in two columns is read one column after the other. Without
  this, each line would join the start of a line from each column.
- Running heads and feet (short lines repeated at the top or bottom of
  many pages, such as a journal name or “Page 3 of 12”) are removed.
- harnessr finds headings, so blocks carry sections as they do for
  Markdown and Word. It takes them from the PDF’s bookmarks when the PDF
  has them. Otherwise a line that is only a standard section name
  (“Introduction”, “2. Methods”, “Results”) counts. That is how harnessr
  found “Summary” above; “Outlook” is not a standard name, so it stayed
  text.

`gr_ingest_spec(layout = "raw")` turns all three off and keeps each page
as it is laid out. Footnotes, tables and pages in three or more columns
can still come out in an order that reads oddly, so check a few pages of
`report$text` before relying on a new kind of PDF.

## Scanned pages and OCR

A scanned PDF is a picture of text, with no text inside it to extract.
To read it, harnessr needs *optical character recognition* (OCR), which
turns the picture back into text. OCR is slow (seconds per page) and
never perfect, so by default harnessr runs it only on pages that need
it:

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
The document lists those pages in `doc$stats$unread_pages`, and harnessr
marks an answer drawn from it as partial. The same holds with
`ocr = "never"`: harnessr lists a page with no text, or only a stamp or
a running head, as unread. A document with too little text left is
refused outright, as “When too little text is left” below shows. The
`"scanned"` recipe is set up for this kind of document.

## Cleaning

Extracted text is rarely clean. PDFs break words across lines with
hyphens, repeat the page number on every page, and use typographic
ligatures (“ﬁ” for “fi”). harnessr tidies this with *cleaners*. Each
does one job, and you can turn each on or off:

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

The five marked `default_on` run unless you turn them off. The others
are off by default. The ones below are off for these reasons:

- `remove_numbers` replaces every digit with a space, which makes any
  question about a figure, date or percentage unanswerable.
- `captions` removes lines that look like figure and table captions,
  which destroys documents made mostly of tables.
- `urls` and `emails` remove links and addresses, which are sometimes
  the answer.
- `references` cuts everything from a line reading just “References”,
  “Bibliography” or “Works cited” to the end of the document. It cuts
  only when that line starts at or after 40% of the text, so a table of
  contents near the start does not cut the document. The line may be
  numbered (“7. References”) or a Markdown heading (“## References”); a
  line inside a fenced code block is not a heading.
  `cleaner_opts = list(references_after = )` moves that share, a number
  from 0 to 1. If your question is about the sources, the cut loses the
  reference list you need.

No reader can recover what a cleaner removes, so know what each choice
costs before you make it.

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

Each preset leaves this many characters of the example report:

``` r

presets <- c("none", "minimal", "standard", "academic", "scan", "legacy")
vapply(presets, function(p) gr_ingest(gr_example(), gr_ingest_spec(clean = p))$stats$chars,
       integer(1))
#>     none  minimal standard academic     scan   legacy 
#>     1858     1858     1846     1655     1846     1558
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
`late`, whatever order you list them in. Without the stages, number
removal could strip the “1” from “Page 1” before the page-number cleaner
recognised the line:

``` r

cleaned <- gr_clean(c("Page 1", "Revenue rose to 45.2 million in 2024."),
                    steps = c("remove_numbers", "page_numbers"))
as.character(cleaned)
#> [1] ""                                  "Revenue rose to  .  million in  ."
```

The second line shows why `remove_numbers` is off by default.

## When too little text is left

harnessr refuses a document with almost no text after cleaning (a scan
read without OCR, an empty file, a PDF of images) instead of sending it
to the model. A model shown nothing would answer “not in the document”
for a document that may well contain the answer:

``` r

gr_ingest("Tiny.")
#> Error in `gr_ingest()`:
#> ! Only 5 characters survived ingestion of '<inline text>' (minimum 20). The file may be empty, image-only with OCR disabled, or your cleaning steps may be too aggressive: 0 characters were removed by cleaners: page_numbers(-0) hyphenation(-0) control_chars(-0) ligatures(-0) collapse_whitespace(-0).
```

`min_chars` in
[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
sets the limit, 20 characters by default.

## Reading the same file twice

harnessr caches each ingestion in memory for the R session. A second
question about the same file, or a different way of cutting it into
chunks, reuses the extracted text instead of reading the file again. The
cache key holds the file’s size and modification time and every
ingestion setting, so harnessr reads the file again when any of them
changes. The cache holds about 256 MB of documents; past that, harnessr
drops the ones used least recently and reads them again when next asked
for. Turn the cache off with `hr_options(cache_documents = FALSE)`.

## Before reading a whole folder

In a folder of documents, problems that a single file makes obvious are
easy to miss: a few old `.doc` files nobody can read, scanned PDFs
without text, an empty file, or a subfolder you forgot about.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
finds all of these in seconds, without calling a model and without an
API key. Its cost floor needs your model’s price, which harnessr does
not ship (“Prices” in
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)),
so the example sets one first:

``` r

# Illustrative figures, in USD per million tokens: use your provider's current
# prices.
hr_register_model(hr_options("model"), input_usd = 2, output_usd = 12)

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
#> <gr_inventory> /tmp/RtmpH7Q2zW/inbox
#>   4 file(s), 1.9 KB; 2 readable
#>   2 ready, 1 no_extractor, 1 empty
#>   tokens: 549   cost floor: $0.01 (gpt-5.6-terra, one call per document), prices as of 2026-11
#>   ! 1 file(s) would be skipped: .doc (1). gr_register_extractor() adds a format.
```

It lists every file, including the ones harnessr will not read, so you
learn before the run that a file will be skipped:

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

It shows three things you would not otherwise see in a corpus run:

| what it shows | why it matters |
|----|----|
| files no extractor claims | they were dropped without appearing anywhere, so a folder of `.doc` files read as an empty corpus |
| PDFs with no text layer | they extract to nothing, then answer `NOT_IN_DOCUMENT`, which looks the same as a document that does not say |
| files in subfolders | they are listed with their `folder`, so a subfolder you forgot is visible; `recursive = FALSE` scans one level only |

`folder` is a column, so `split(inv$files, inv$files$folder)` gives you
the piles.
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
does not choose a recipe for you. A router that quietly read one
document with `retrieve` and another with `stuff` would hand you a
plausible answer built on part of a file, with nothing to say so. It
would also make
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
meaningless, because the corpus would no longer have one configuration.
Group the rows yourself and pass each group the recipe you picked.
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
covers reading a whole folder.

`inv$totals` adds up the tokens and prices one request per readable file
with your model: the file’s tokens in, and an assumed 500-token answer
out.
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
gives the figure and its `priced`, `as_of` and `certain` columns (“What
a cost estimate says:
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)”
in
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)).
Treat `cost_floor_usd` as a rough guide, not a bound. Reading strategies
that make several requests per document cost more, and short answers
cost less. The total leaves out files whose size is unknown until OCR
reads them; `tokens_unknown` counts those.

``` r

unlist(inv$totals[c("readable", "tokens", "cost_floor_usd")])
#>       readable         tokens cost_floor_usd 
#>       2.000000     549.000000       0.013098
```

## Choosing the settings

Two groups of ingest settings change what the model gets: cleaning and
OCR. Each walkthrough below covers:

- what the setting controls and what it trades off;
- the signs in your results that point to changing it;
- where its default came from;
- how to test a change.

[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
lists every ingest setting with its default.

The tests use
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
which builds one arm per value of a setting, and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
which runs every arm on a reference of questions. Here they run on one
question and a stand-in model that always gives the right answer. That
shows how to build and read a sweep, but cannot show which value is
better.
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
runs sweeps on a reference with dev and test splits and reads them with
intervals.

``` r

qa <- gr_qa_reference(questions = c(revenue = "What was revenue in 2024?"),
                      documents = gr_example(), answers = list("45.2 million"),
                      split = "dev")
says <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

### Cleaning presets and `references_after`

**What it controls.** `clean` chooses the cleaners that run on the
extracted text, by preset or by name (see “Presets” above), and
`cleaner_opts = list(references_after = )` sets where the `references`
cleaner may cut. Cleaning trades noise against loss. Page numbers,
running heads and captions cost tokens and can mislead retrieval, but
text an overeager cleaner removes is gone for good, and no later setting
brings it back.

**Signs it needs changing.** An answer of `NOT_IN_DOCUMENT` for a fact
you can see in the file, or a quotation that fails verification, can
mean a cleaner removed the text. Look in `doc$stats$clean_log` for a
cleaner that removed far more than the others. If answers quote page
headers or figure captions as if they were findings, move the other way,
to `"academic"` or `"scan"`. Under `"academic"`, if an answer about a
paper’s sources says they are not in the document, the reference list
was cut. A document whose table of contents has a “References” line
after the first 40% of its text is cut at that line; raise
`references_after` for such documents.

**Where the defaults came from.** `"standard"` is the preset meant for
born-digital text and has not been compared with the others.
`references_after` is 0.4, the value set when the cleaner was written.
Both are `untested` in `gr_settings_table("ingest")`.

**How to test it.** Sweep the presets and look at what was sent:

``` r

arms <- hr_sweep(gr_arm("fast"), list(clean = c("standard", "academic", "scan", "none")))
bench <- hr_benchmark(arms, qa, runs = 5, client = says, split = "dev",
                      scorer = gr_scorer_answer())
aggregate(tokens_in ~ param.clean, bench, mean)
#>   param.clean tokens_in
#> 1    academic       549
#> 2        none       619
#> 3        scan       611
#> 4    standard       611
hr_sweep_check(bench)
#>               arm             same_as runs requests                settings
#> 1 fast:clean=scan fast:clean=standard    5        5 clean: standard vs scan
```

On the example report, `"academic"` sends 62 fewer prompt tokens than
`"standard"`, because it drops the caption lines and the reference list
after the `## References` heading. `"none"` sends 8 more.
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
finds that `"scan"` sent exactly the requests `"standard"` sent. The
example has no running heads, so on it that comparison would measure
only run-to-run spread. The same check tells you whether a
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

Both values sent the same requests. The example report’s `## References`
heading starts 94% of the way through its text, after both 40% and 80%,
so both values cut the text at the same line. A `references_after` sweep
changes what is sent only for a document whose heading falls between the
two values. Run it on your own documents, with questions whose answers
sit near the end.

### OCR settings

**What it controls.** `ocr` decides which pages harnessr reads as
pictures:

- `"auto"` reads a page by OCR only when it has fewer than
  `ocr_min_chars` characters of text (40);
- `"always"` reads every page that way;
- `"never"` reads none.

`ocr_trigger` says which text those characters are counted on:
`"raw_text"` counts the page’s whole text layer, and
`"after_running_lines"` counts what is left once the layout pass has
dropped running heads, feet and stamps. `ocr_dpi` is the resolution the
page is rendered at, and `ocr_lang` the Tesseract language. OCR costs
seconds per page and adds recognition errors; skipping it on a scanned
page leaves that page empty.

The blocks of a page read by OCR have `kind = "ocr"` (its headings keep
`"heading"`). `ocr_confidence = TRUE` gives them an `ocr_confidence`
column, Tesseract’s mean word confidence for the page, from 0 to 100. It
runs a second Tesseract pass over each OCR-ed page, so OCR takes about
twice as long. It is off by default.

**Signs it needs changing.** `doc$stats$unread_pages` lists pages that
came back empty, and harnessr marks an answer from such a document as
partial. A scanned page with a printed header or stamp can carry more
than 40 characters of text and so skip OCR under `"auto"`. Set
`ocr_trigger = "after_running_lines"` when the stamp repeats on every
page, or raise `ocr_min_chars` when it does not. Under
`ocr_confidence = TRUE`, if the blocks an answer cites have a low
`ocr_confidence`, read that page yourself. If OCR text has misread
numbers or letters (a quotation fails verification against a page that
plainly says it), try a higher `ocr_dpi` or the right `ocr_lang`.

**Where the defaults came from.** `ocr_dpi = 300` follows Tesseract’s
documentation on improving output quality (`cited`). `ocr = "auto"` runs
OCR only where a page has no text layer, and no other choice has been
compared. `ocr_min_chars = 40` was set when OCR was added and has not
been tuned, and `ocr_lang = "eng"` is English because the package’s own
examples are in English. `ocr_trigger = "raw_text"` is how pages were
chosen before the setting existed, and has not been compared with
`"after_running_lines"`. `ocr_confidence = FALSE` keeps OCR to the one
Tesseract pass it always ran. All of them except `ocr_dpi` are
`untested`.

**How to test it.** OCR needs a scanned file and the tesseract and
magick packages, so run this on your own documents, with a reference you
build from them with
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
means no page crossed the threshold between that arm’s value and an
earlier one, so the two arms read the documents the same way.

Sweep `ocr_trigger` the same way. It decides which pages OCR reads
before any request goes out, so `doc$stats$unread_pages` and the `"ocr"`
blocks of each ingestion show its effect at no cost:

``` r

arms <- hr_sweep(gr_arm("scanned"),
                 list(ocr_trigger = c("raw_text", "after_running_lines")))
bench <- hr_benchmark(arms, my_reference, runs = 5, client = my_client, split = "dev",
                      scorer = gr_scorer_answer())
aggregate(correct ~ param.ocr_trigger, bench, mean)
```

`ocr_confidence` changes no text and no request, so a sweep of it shows
the same answers. You get the column and pay for the second pass; wrap
each
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
in [`system.time()`](https://rdrr.io/r/base/system.time.html) to see
that cost:

``` r

arms <- hr_sweep(gr_arm("scanned"), list(ocr_confidence = c(FALSE, TRUE)))
```

## Adding your own

You can add a format harnessr does not know, or a clean-up step your
documents need, and then use it exactly like a built-in one. This
cleaner drops lines marked “CONFIDENTIAL”:

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

With the text out, you next decide how to cut it into chunks
([`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md))
and how the model should read them
([`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)).
To read a whole folder once
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
has checked it, see
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md).
