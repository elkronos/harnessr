# Cutting documents into chunks

A model reads a long document in pieces, called *chunks*, and chunking
decides what it can see together. A figure in one chunk and the sentence
that explains it in the next may never be read side by side. This guide
covers the nine ways harnessr cuts a document, the settings every one of
them shares, and how to compare chunkings before you pay for any
reading.

Six of the nine segmenters make no model calls, and a seventh makes none
by default, so you can try them for nothing.
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
introduces the package and the ideas used here, and
[`vignette("ingest")`](https://elkronos.github.io/harnessr/articles/ingest.md)
covers the step before this one.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")
```

`embedder = "lexical"` makes the one segmenter that embeds text,
`semantic`, use hashed bag-of-words vectors rather than an embeddings
endpoint, so this guide runs offline and gives the same chunks every
time.

## What segmentation produces

[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
takes a document from
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
(or anything
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
accepts) and a segmentation, and returns a chunk set:

``` r

doc <- gr_ingest(gr_example())
ch <- gr_segment(doc, list(method = "structural", max_tokens = 120))
ch
#> <gr_chunks> method=structural  n=8
#>   tokens: min 16 / median 76.5 / mean 70 / max 102 / total 557
#>   cap=120  over-cap chunks: 0
#>   sections: 6 distinct
#>   first: # Northwind Instruments — Annual Report 2024
```

The segmentation can be a segmenter’s name, a named list as above, or a
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md).
Each chunk records where it came from:

``` r

ch$chunks[, c("chunk_id", "tokens", "page", "section", "block_id")]
#>   chunk_id tokens page                                    section block_id
#> 1        1     16   NA Northwind Instruments — Annual Report 2024        1
#> 2        2    101   NA                                    Summary       NA
#> 3        3     69   NA                                 Operations        6
#> 4        4     84   NA                                 Operations       NA
#> 5        5     62   NA                               Risk factors       10
#> 6        6    102   NA                               Risk factors       NA
#> 7        7     84   NA                                    Outlook       NA
#> 8        8     39   NA                                 References       17
```

`page` is `NA` here because the example is Markdown, which has no pages;
a PDF fills it in. `block_id` is `NA` on a chunk built from several
blocks, and so is `page` on a chunk that runs from one page onto the
next. A chunk that is not from one place says so rather than naming the
first place it touches. This provenance is what `ans$evidence` reports
for every chunk an answer rests on.

You rarely call
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
yourself.
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
does it, using the `segment` part of a recipe:

``` r

gr_recipe("survey")$segment[c("method", "max_tokens", "overlap_tokens")]
#> $method
#> [1] "paragraph"
#> 
#> $max_tokens
#> [1] 1200
#> 
#> $overlap_tokens
#> [1] 0
```

To change it, build a recipe of your own with
`gr_recipe(segment = list(...))`;
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
covers recipes.

## The nine segmenters

Each segmenter is a different hypothesis about where meaning breaks:

| segmenter | boundary hypothesis | cost | needs client | provenance |
|----|----|----|----|----|
| `fixed` | meaning is uniform; cut on a ruler (the control condition) | free | no | none |
| `paragraph` | the author’s paragraph breaks are real | free | no | page, section, block |
| `sentence` | sentences are atomic; pack tightly | free | no | page, section, block |
| `recursive` | use the strongest separator that still fits | free | no | none |
| `structural` | headings are boundaries; never merge across sections | free | no | page, section, block |
| `page` | the page is the unit: forms, invoices, scanned records | free | no | page, section, block |
| `semantic` | cut where consecutive embeddings diverge most | 1 embedding pass | yes | page, section, block |
| `contextual` | chunks prefixed with where they sit | free, or 1 call/chunk | only for `context_source = "llm"` | page, section, block |
| `proposition` | rewrite into standalone factual statements | 1 call per ~900-token batch | yes | none |

The cost and client columns come from the registry, so you can check
them rather than trust them:

``` r

gr_segmenters()[, c("name", "cost", "needs_client", "calls")]
#>          name      cost needs_client               calls
#> 1  contextual      free        FALSE     segment.context
#> 2       fixed      free        FALSE                    
#> 3        page      free        FALSE                    
#> 4   paragraph      free        FALSE                    
#> 5 proposition       llm         TRUE segment.proposition
#> 6   recursive      free        FALSE                    
#> 7    semantic embedding         TRUE                    
#> 8    sentence      free        FALSE                    
#> 9  structural      free        FALSE
```

`paragraph` is the default. It packs the author’s paragraphs, in order,
into chunks up to the cap. `sentence` packs sentences instead, which
gives more, smaller chunks with cleaner edges. `structural` never lets a
chunk cross a heading, and by default (`prefix_section = TRUE`) starts
every chunk with its section’s heading, so the fourth chunk of a long
“Methods” section still says it is about methods. When the extractor
found no sections, `structural` finds headings itself: a Markdown `#`
line, or a short line that is numbered or written in capitals. `page`
makes one chunk per page, splitting only a page too long for the cap,
and says so when it does.

`fixed` cuts the text into windows of equal size and ignores its
structure, which makes it the baseline to measure the others against.
`recursive` splits on the strongest separator that still gives pieces
under the cap: by default blank lines, then line breaks, then sentence
ends, semicolons, commas and spaces. Set your own cascade, strongest
first, with `separators`.

`fixed` and `recursive` work on the whole document joined into one
string, by design, so their chunks carry no page or section. That is the
cost of ignoring structure, and it is reported as `NA` rather than
guessed at:

``` r

fx <- gr_segment(doc, list(method = "fixed", max_tokens = 120))
fx$chunks[1:3, c("chunk_id", "page", "section", "block_id")]
#>   chunk_id page section block_id
#> 1        1   NA    <NA>       NA
#> 2        2   NA    <NA>       NA
#> 3        3   NA    <NA>       NA
```

The last three segmenters, `semantic`, `contextual` and `proposition`,
are covered below, under the settings and model calls they add.

## When a segmenter cannot run as asked

A segmenter that cannot do what was asked falls back to one that can,
warns, and records the change. `page` on a source with no page numbers
falls back to `paragraph`:

``` r

pg <- gr_segment(doc, "page")
pg$method
#> [1] "page->paragraph"
```

`semantic` without a client falls back to `paragraph`, and `proposition`
without one falls back to `sentence`. The fallback shows in `$method`
(`"semantic->paragraph"`, `"proposition->sentence"`) and in the `method`
column of
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
so a comparison never reports a chunking that did not run. `contextual`
keeps its name when `context_source = "llm"` has no client, because only
the source of its context lines changed; `$extra$context_source` records
`"metadata"`, the one that ran.

Every one of these warnings has the class `gr_segment_fallback`, and it
is carried onto the answer of any read that uses the chunks.

## Chunk size

`max_tokens` is the cap on a chunk’s size, and every segmenter is held
to it, including one you register yourself. After a segmenter returns,
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
splits any chunk over the cap (at sentences, then words, then
characters) and counts how many it had to split in
`$extra$cap_enforced`. The pieces keep the page, section and block of
the chunk they came from. If the active tokenizer counts a single
character as more than the cap,
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
stops with an error of class `gr_cap_unenforceable` rather than send a
chunk the model will reject.

A setting out of range is corrected and the correction is announced:

``` r

tryCatch(gr_segment_spec("paragraph", max_tokens = 100, overlap_tokens = 500),
         warning = conditionMessage)
#> [1] "`overlap_tokens` 500 is outside [0, 99]; using 99."
```

`max_tokens` is held to between 32 and 1,000,000, `overlap_tokens` to
less than `max_tokens`, and `min_tokens` to no more than `max_tokens`.

What the right size is depends on the reader. A reader that sends every
chunk pays for each request, so small chunks multiply the bill; one that
picks the best few chunks needs chunks small enough that the best few
hold the answer and little else.
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
compares them.

## Overlap

Without overlap, an answer that straddles a boundary is split between
two chunks and may be lost by both. `overlap_tokens` copies the end of
each chunk into the start of the next. It costs duplicated tokens, which
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)
shows as a larger `total_tokens`:

``` r

do.call(rbind, lapply(c(0, 30, 60), function(ov)
  gr_chunk_stats(gr_segment(doc, list(method = "sentence", max_tokens = 120,
                                      overlap_tokens = ov)))))
#>     method n total_tokens min median mean max over_cap
#> 1 sentence 6          534  47   92.5 89.0 107        0
#> 2 sentence 7          668  74   99.0 95.4 107        0
#> 3 sentence 9          863  79   94.0 95.9 109        0
```

The document is the same 534 tokens each time: at 60 tokens of overlap
the model would be sent 863, about 60% more. The carried text is cut at
a sentence boundary when one is close, otherwise at a word; text written
without spaces (Chinese, Japanese, Thai) is cut by characters. The
overlap is trimmed so that the chunk it opens still fits the cap.

Provenance counts the overlap. A chunk that opens with a sentence
carried from page 3 and goes on to page 4 reports page `NA`, since it is
not wholly from either.

Overlap applies to every segmenter except `page`, where the page is the
unit, and `proposition`, whose statements are written to stand alone, so
its overlap is always 0. `structural` applies it within a section, never
across a heading.

## Minimum size

`min_tokens` merges a chunk smaller than this into the chunk before it,
so a one-line paragraph between two headings does not become a request
of its own. The merge happens only when the result still fits the cap.
With a cap of 60 tokens the example’s paragraphs give fourteen chunks,
the smallest of 8 tokens; `min_tokens = 30` folds one of them away:

``` r

do.call(rbind, lapply(c(0, 30), function(m)
  gr_chunk_stats(gr_segment(doc, list(method = "paragraph", max_tokens = 60,
                                      min_tokens = m)))))
#>      method  n total_tokens min median mean max over_cap
#> 1 paragraph 14          565   8   42.5 40.4  57        0
#> 2 paragraph 13          562  21   45.0 43.2  57        0
```

`fixed` and `page` ignore `min_tokens`. `structural` applies it within a
section only, because it never merges across headings: its 16-token
first chunk, the report’s title, stays as it is whatever you set.

``` r

gr_chunk_stats(gr_segment(doc, list(method = "structural", max_tokens = 120,
                                    min_tokens = 40)))
#>       method n total_tokens min median mean max over_cap
#> 1 structural 8          557  16   76.5 69.6 102        0
```

## Context lines

A chunk retrieved on its own can be hard to place: “it rose 17 percent”
means little without the section it came from. `contextual` packs
paragraphs as `paragraph` does, then starts each chunk with a bracketed
line saying where it sits. By default (`context_source = "metadata"`)
the line is built from the file name, section, page and position, for
nothing:

``` r

ctx <- gr_segment(doc, list(method = "contextual", max_tokens = 120))
cat(ctx$chunks$text[2])
#> [Source: annual_report.md | Section: Summary | Part 2 of 11]
#> 
#> Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024,
#> up from 38.7 million in 2023. Gross margin improved to 41 percent from 37
#> percent. Operating income was 6.9 million dollars against 4.1 million the year
#> before.
```

With `context_source = "llm"` a model writes the line instead, one call
per chunk, from the chunk and the document’s first 1,500 tokens. The
mock client below stands in for that model:

``` r

writer <- gr_mock_client(function(messages, params) "This excerpt reports the 2024 results.")
ctx_llm <- gr_segment(doc, list(method = "contextual", max_tokens = 120,
                                context_source = "llm"), client = writer)
cat(ctx_llm$chunks$text[2])
#> [This excerpt reports the 2024 results.]
#> 
#> Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024,
#> up from 38.7 million in 2023. Gross margin improved to 41 percent from 37
#> percent.
```

Room for the line is held back from each chunk before packing (90 tokens
for `"llm"`, the longest header the document could need for
`"metadata"`, never more than half of `max_tokens`), so adding the line
never pushes a chunk over the cap. A line that still does not fit is
shortened; the document text is not.

When a context call fails or is skipped at the run’s limits, the chunk
keeps its text without a line. `$extra$blurbs_missing` counts those
chunks, and a `gr_segment_fallback` warning says so.

The context line is not the document’s text, and a model may have
written it. So the chunk also keeps its body alone in a `source_text`
column, and a quotation from the chunk is checked against that, never
against the line:

``` r

ctx_llm$chunks$source_text[2]
#> [1] "Northwind Instruments reported revenue of 45.2 million dollars in fiscal 2024,\nup from 38.7 million in 2023. Gross margin improved to 41 percent from 37\npercent."
```

## Segmenters that call a model

Three segmenters spend something, and each takes a `client`:

- `semantic` embeds the text a few sentences at a time
  (`semantic_window`, default 2) and cuts where two neighbouring windows
  differ most: at distances above the `semantic_percentile` (default 90;
  higher gives fewer, larger chunks). The packer then holds the pieces
  to the cap and the minimum.
- `contextual` with `context_source = "llm"` makes one call per chunk,
  as above.
- `proposition` sends the document in batches of about
  `proposition_batch_tokens` (default 900) and has the model rewrite
  each into standalone factual statements, with pronouns resolved and
  numbers kept as written. Its chunks are the model’s words, so
  `source_text` holds the passage each was written from, and quotes are
  checked against that. A batch that cannot be rewritten is kept as
  written rather than dropped, with a warning, and counted in
  `$extra$batches_kept_as_written`.

``` r

cl <- gr_mock_client(function(messages, params) "unused")
sem <- gr_segment(doc, list(method = "semantic", max_tokens = 120), client = cl)
gr_chunk_stats(sem)
#>     method n total_tokens min median  mean max over_cap
#> 1 semantic 5          528  93    106 105.6 116        0
sem$extra$embedding_source
#> [1] "lexical"
```

`embedding_source` is `"lexical"` here, so the boundaries reflect shared
words, not meaning. With a real embeddings endpoint it is `"api"`.

These requests count against the run’s limits,
`gr_options(max_calls =, max_cost_usd =)`, like any other. Called
without a `trace`,
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
makes its own and returns it as `$trace`, so you can see what segmenting
cost:

``` r

gr_trace_summary(ctx_llm$trace)[, c("calls", "tokens_in", "tokens_out")]
#>   calls tokens_in tokens_out
#> 1    14      8639        196
```

[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
covers limits and traces.

## Comparing segmentations

[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)
sums a chunk set up in one row, so comparing chunkings is an
[`rbind()`](https://rdrr.io/r/base/cbind.html):

``` r

do.call(rbind, lapply(c("fixed", "paragraph", "sentence", "structural"),
  function(m) gr_chunk_stats(gr_segment(doc, list(method = m, max_tokens = 120)))))
#>       method n total_tokens min median  mean max over_cap
#> 1      fixed 5          528  49  120.0 105.6 120        0
#> 2  paragraph 6          539  48   92.0  89.8 116        0
#> 3   sentence 6          534  47   92.5  89.0 107        0
#> 4 structural 8          557  16   76.5  69.6 102        0
```

`n` is the number of chunks, which is the number of requests for a
reader that sends every chunk. `total_tokens` grows with overlap and
with text a segmenter adds, such as the headings `structural` puts at
the top of its chunks. `over_cap` is 0 for anything
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
returns, since the cap is enforced; it is there for chunk sets built
some other way. `method` names any fallback.

To compare what different chunkings do to an answer, give
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
recipes that differ only in their `segment`. It extracts the document
once and reuses a segmentation across recipes whose segment settings
match, so only the reading is paid for more than once:

``` r

cmp <- gr_compare(gr_example(), "What was revenue?", list(
  gr_recipe("by_paragraph", segment = list(method = "paragraph", max_tokens = 120),
            read = list(reader = "retrieve", top_k = 2)),
  gr_recipe("by_section", segment = list(method = "structural", max_tokens = 120),
            read = list(reader = "retrieve", top_k = 2))), client = cl)
cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "chunks_used")]
#>         recipe  segmenter chunks   reader chunks_used
#> 1 by_paragraph  paragraph      6 retrieve           2
#> 2   by_section structural      8 retrieve           2
```

## Previewing chunks in the Shiny app

The bundled app has a control for every segmentation setting: segmenter,
`max_tokens`, overlap and minimum chunk size. Its “Preview chunking”
button shows how the current settings cut the document before anything
is spent on reading. For a segmenter that calls a model, the button says
so.

``` r

shiny::runApp(system.file("shiny", package = "harnessr"))
```

`GPTREAD_DOC_ROOTS` (colon-separated) sets which folders the app can
read. Unset, it defaults to `~/Documents`, falling back to your entire
home directory, so set it before exposing the app to anyone else. The
app opens only the PDF, Word, text, Markdown, HTML and image files under
those folders, never hidden files or hidden folders. `extract` and
`screen` are not offered, since they read against a protocol; use
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
and
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
([`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)).
A blank cost cap leaves `gr_options("max_cost_usd")` in force rather
than lifting the limit.

## Your own segmenter

[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
adds a segmenter that behaves like the built-ins: it appears in
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
can be named in a recipe, and is held to the same cap.
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)
builds the object it must return.
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
has a worked example.
