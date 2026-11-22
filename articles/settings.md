# Settings reference

This page lists every setting harnessr has, stage by stage, and the
building blocks the settings choose between. The tables are made from
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
and the registries when the page is built, so they say what the
installed code does. A setting with a walkthrough links to it: the
section of a guide that says what the setting trades off, the signs that
point to changing it, where its default came from and how to test a
change.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")
settings <- gr_settings_table()
table(settings$stage, settings$tier)[unique(settings$stage), ]
#>             
#>              advanced basic
#>   ingest           18     3
#>   segment          17     3
#>   read             39     8
#>   screen           22    11
#>   extract           7     3
#>   synthesise       23     5
#>   evaluate         18     9
#>   options          29     5
```

## Reading the tables

Each row is one setting. `where` is the function that takes it.
`default` is the value used when you give none: a string without quotes,
the first of a set of choices, anything else as R code. `tier` is
`basic` for the few settings most runs change and `advanced` for the
rest. `status` says where the default came from: `measured` (a
measurement backs it), `cited` (a published source gives it) or
`untested` (it was chosen, and nothing has measured it); a blank means
nothing is declared, which is the case for switches, limits and most
function arguments.
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
adds the `source` behind each status, and
[`?gr_read_spec`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
[`?gr_segment_spec`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`?gr_ingest_spec`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
and
[`?gr_options`](https://elkronos.github.io/harnessr/reference/gr_options.md)
give the full help.

A setting is given where its stage takes it. Ingest, segment and read
settings go in a spec (`gr_read_spec(top_k = 4)`), in a recipe, or by
name to
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
and
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
which put each on the step it belongs to. The review and evaluation
settings are arguments of their functions. Options are set for the
session with
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md).

To find out whether a value is better for your documents, build one arm
per value with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
and compare them with
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
and
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
as
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
does;
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
says which values sent the same requests.

``` r

show_settings <- function(stage) {
  s <- settings[settings$stage == stage, ]
  esc <- function(x) gsub("|", "\\|", ifelse(is.na(x), "", x), fixed = TRUE)
  name <- ifelse(is.na(s$guide), paste0("`", s$name, "`"),
                 sprintf("[`%s`](%s.html#%s)", s$name, sub("#.*", "", s$guide),
                         sub(".*#", "", s$guide)))
  knitr::kable(data.frame(setting = name, where = paste0("`", s$where, "`"),
                          default = paste0("`", esc(s$default), "`"),
                          tier = s$tier, status = esc(s$status),
                          description = esc(s$description)),
               row.names = FALSE)
}
```

## Ingest

What comes out of a file: cleaning, OCR, the PDF layout pass, and the
floor on how much text must survive. The entries of `cleaner_opts` and
`layout_opts` are listed with their parent’s name.
[`vignette("ingest")`](https://elkronos.github.io/harnessr/articles/ingest.md)
covers them.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| [`ocr`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `auto` | basic | untested | When to OCR a page: with no text layer, always, or never. |
| `layout` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `auto` | advanced | untested | How a PDF page’s text is put in reading order. |
| [`clean`](https://elkronos.github.io/harnessr/articles/ingest.html#set-clean) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `standard` | basic | untested | A cleaning preset, or cleaner names. |
| [`ocr_lang`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `eng` | advanced | untested | Tesseract language code. |
| [`ocr_dpi`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `300` | advanced | cited | Render density for PDF OCR. |
| [`ocr_min_chars`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `40` | advanced | untested | A page with fewer characters is OCRed under ocr = ‘auto’. |
| `min_chars` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `20` | basic | untested | Refuse the document if less text than this survives. |
| `extractor` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `NULL` | advanced | untested | Force an extractor instead of choosing by file type. |
| `parallel` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `NULL` | advanced | untested | Parallelise page-level OCR. |
| [`cleaner_opts`](https://elkronos.github.io/harnessr/articles/ingest.html#set-clean) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | [`list()`](https://rdrr.io/r/base/list.html) | advanced | untested | Extra options passed to individual cleaners. |
| `layout_opts` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | [`list()`](https://rdrr.io/r/base/list.html) | advanced | untested | Settings of the PDF running-head pass under layout = ‘auto’. |
| [`ocr_trigger`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `raw_text` | advanced | untested | Which text of a PDF page ocr_min_chars is counted on under ocr = ‘auto’. |
| [`ocr_confidence`](https://elkronos.github.io/harnessr/articles/ingest.html#set-ocr) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `FALSE` | advanced | untested | Record Tesseract’s confidence on a PDF page’s OCR blocks (a second pass). |
| [`cleaner_opts.references_after`](https://elkronos.github.io/harnessr/articles/ingest.html#set-clean) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `0.4` | advanced | untested | For the references cleaner: the share of the text after which a References heading ends the text. |
| [`cleaner_opts.header_max_chars`](https://elkronos.github.io/harnessr/articles/ingest.html#set-clean) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `80` | advanced | untested | For the headers_footers cleaner: the longest line that can be taken for a running head or foot. |
| [`cleaner_opts.header_min_repeats`](https://elkronos.github.io/harnessr/articles/ingest.html#set-clean) | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `3` | advanced | untested | For headers_footers: how many times a line must recur to be taken for a running head; values below 3 are read as 3. |
| `layout_opts.depth` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `2` | advanced | untested | Lines at each edge of a PDF page that are candidates for a running head or foot. |
| `layout_opts.share` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `0.4` | advanced | untested | The share of pages a line must recur on to be dropped as a running head or foot. |
| `layout_opts.min_pages` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `3` | advanced | untested | The fewest pages a document needs before any line is dropped, and the fewest a line must recur on. |
| `layout_opts.max_chars` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `200` | advanced | untested | The longest line, in characters, that can be a running head or foot. |
| `layout_opts.max_words` | [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | `5` | advanced | untested | Above this many words, a numbered line must carry its number where a page number is set. |

## Segment

How the text is cut into chunks.
[`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md)
covers them.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| [`context_source`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `metadata` | advanced | untested | For contextual: where the context line comes from. |
| [`max_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-max-tokens) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `1200` | basic | untested | Hard cap on chunk size, in tokens. |
| [`overlap_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-overlap) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `0` | basic | untested | Tokens of trailing context copied into the start of the next chunk. |
| [`min_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-packing) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `0` | advanced | untested | A smaller chunk is merged into the one before it. |
| [`method`](https://elkronos.github.io/harnessr/articles/segment.html#set-method) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `paragraph` | basic | untested | The segmentation strategy. |
| `separators` | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `NULL` | advanced | untested | For recursive: the separator cascade, strongest first. |
| `prefix_section` | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `TRUE` | advanced | untested | For structural: prepend the heading. |
| `semantic_window` | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `2` | advanced | untested | For semantic: sentences embedded together. |
| `semantic_percentile` | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `90` | advanced | untested | For semantic: how extreme a distance counts as a boundary. |
| [`proposition_batch_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `900` | advanced | untested | For proposition: the size of each batch sent to the model. |
| `parallel` | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `NULL` | advanced | untested | Parallelise per-chunk model work. |
| [`context_reply_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `90` | advanced | untested | For contextual under llm: the output cap of each context-line request. |
| [`context_document_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `1500` | advanced | untested | For contextual under llm: how much of the document each request carries. |
| [`proposition_reply_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `2000` | advanced | untested | For proposition: the output cap of each batch’s request. |
| [`semantic_threshold`](https://elkronos.github.io/harnessr/articles/segment.html#set-semantic) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `percentile` | advanced | untested | For semantic: how the distances between windows are cut into boundaries. |
| [`table_packing`](https://elkronos.github.io/harnessr/articles/segment.html#set-tables) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `rows` | advanced | untested | For paragraph: how the rows of a table are packed into chunks. |
| [`proposition_check`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `count` | advanced | untested | For proposition: whether a proposition with no support in its batch is dropped. |
| [`proposition_context_tokens`](https://elkronos.github.io/harnessr/articles/segment.html#set-contextual) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `0` | advanced | untested | For proposition: tokens of the batch before that each batch’s request carries. |
| [`packing`](https://elkronos.github.io/harnessr/articles/segment.html#set-packing) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `greedy` | advanced | untested | How units are packed into chunks under the cap. |
| [`runt_merge`](https://elkronos.github.io/harnessr/articles/segment.html#set-packing) | [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md) | `backward` | advanced | untested | Which way a chunk under min_tokens is merged. |

## Read

How the model reads the chunks, and the settings
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
adds for a folder.
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
covers them.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `on_overflow` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `warn` | advanced | untested | For stuff: truncate with a warning, or stop, when the document does not fit. |
| [`context_order`](https://elkronos.github.io/harnessr/articles/readers.html#set-context-order) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `relevance` | advanced | untested | Where the selected chunks sit in the prompt. |
| [`restate`](https://elkronos.github.io/harnessr/articles/readers.html#set-context-order) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `auto` | advanced | untested | Whether to repeat the question before the excerpts as well as after. |
| [`premise`](https://elkronos.github.io/harnessr/articles/readers.html#set-premise) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `FALSE` | advanced | untested | Check the question’s assumptions against the document. |
| [`verify`](https://elkronos.github.io/harnessr/articles/readers.html#set-verify) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `FALSE` | basic | untested | Check the answer’s quotations against the chunks they cite. |
| [`effort`](https://elkronos.github.io/harnessr/articles/readers.html#set-effort) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | Reasoning effort, one level or a map named by call stem. |
| [`reader`](https://elkronos.github.io/harnessr/articles/readers.html#set-reader) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `map_reduce` | basic | untested | The reading strategy. |
| `model` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | basic | untested | Chat model id; NULL means the client’s. |
| `temperature` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | Sampling temperature. |
| `max_answer_tokens` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `1500` | advanced | untested | Output cap for final answers and merges. |
| `max_chunk_tokens` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `700` | advanced | untested | Output cap for per-chunk calls. |
| `max_summary_tokens` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `500` | advanced | untested | Output cap for summarisation calls. |
| [`top_k`](https://elkronos.github.io/harnessr/articles/readers.html#set-top-k) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `6` | basic | untested | Chunks to use, for retrieve, rerank and iterative. |
| [`min_score`](https://elkronos.github.io/harnessr/articles/readers.html#set-top-k) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `-Inf` | advanced | untested | For retrieve: chunks scoring below this are dropped. |
| [`mmr`](https://elkronos.github.io/harnessr/articles/readers.html#set-mmr) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `1` | advanced | untested | Relevance against diversity when selecting chunks; 1 is plain top-k. |
| [`rerank_candidates`](https://elkronos.github.io/harnessr/articles/readers.html#set-low-score) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `20` | advanced | untested | For rerank: how many chunks to score. |
| [`rerank_min_score`](https://elkronos.github.io/harnessr/articles/readers.html#set-low-score) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `4` | advanced | untested | For rerank: the score below which a chunk is discarded. |
| [`fan_in`](https://elkronos.github.io/harnessr/articles/readers.html#set-merge-levels) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `5` | advanced | untested | For hierarchical: summaries combined per call. |
| [`max_levels`](https://elkronos.github.io/harnessr/articles/readers.html#set-merge-levels) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `5` | advanced | untested | For hierarchical: the recursion depth cap. |
| `max_rounds` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `4` | advanced | untested | For iterative: retrieve-assess cycles. |
| `preview_tokens` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `1200` | advanced | untested | For preview: the cap on the outline the planner sees. |
| `members` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | For ensemble: the reader names to combine. |
| [`cite`](https://elkronos.github.io/harnessr/articles/readers.html#set-verify) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `FALSE` | basic | untested | Ask for chunk-level citations in the answer. |
| [`skim_model`](https://elkronos.github.io/harnessr/articles/readers.html#set-reader) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | A cheaper model for skim’s extraction and rerank’s scoring. |
| [`summary_model`](https://elkronos.github.io/harnessr/articles/readers.html#set-reader) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | A cheaper model for hierarchical’s summaries. |
| `parallel` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `NULL` | advanced | untested | Run per-chunk calls in parallel. |
| `delay_between_calls` | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `0` | advanced | untested | Seconds to sleep between sequential calls. |
| [`accept_near_verbatim`](https://elkronos.github.io/harnessr/articles/readers.html#set-verify) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `FALSE` | advanced | untested | Under verify, let a near-verbatim quotation stop the iterative reader. |
| [`max_merge_levels`](https://elkronos.github.io/harnessr/articles/readers.html#set-merge-levels) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `6` | advanced | untested | Most merge levels a reader runs before it returns its findings unmerged. |
| [`restate_tokens`](https://elkronos.github.io/harnessr/articles/readers.html#set-context-order) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `1200` | advanced | untested | Under restate = ‘auto’, the body length above which the question is repeated. |
| [`bm25_k1`](https://elkronos.github.io/harnessr/articles/readers.html#set-lexical) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `1.5` | advanced | cited | BM25 term-frequency saturation, for rerank’s prefilter and lexical retrieve. |
| [`bm25_b`](https://elkronos.github.io/harnessr/articles/readers.html#set-lexical) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `0.75` | advanced | cited | BM25 length normalisation, for rerank’s prefilter and lexical retrieve. |
| [`lexical_blend`](https://elkronos.github.io/harnessr/articles/readers.html#set-lexical) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `0.5` | advanced | untested | For retrieve on lexical embeddings: the weight of cosine against BM25. |
| [`unskip_k`](https://elkronos.github.io/harnessr/articles/readers.html#set-preview) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `0` | advanced | untested | For preview: the sections that best match the question’s words, read even when the plan skips them. |
| [`reread_on`](https://elkronos.github.io/harnessr/articles/readers.html#set-preview) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `never` | advanced | untested | For preview: under “not_found”, an answer that found nothing reads the sections not read in full in one more request. |
| [`low_score`](https://elkronos.github.io/harnessr/articles/readers.html#set-low-score) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `not_found` | advanced | untested | For rerank: when every candidate scores below rerank_min_score, answer not found, or send the 5 best to the answer request. |
| [`fusion`](https://elkronos.github.io/harnessr/articles/readers.html#set-lexical) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `default` | advanced | untested | For retrieve and iterative: how embedding similarity and BM25 are combined into one ranking. |
| [`rrf_k`](https://elkronos.github.io/harnessr/articles/readers.html#set-lexical) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `60` | advanced | cited | Under fusion = ‘rrf’: the constant k in 1 / (k + rank). |
| [`answer_format`](https://elkronos.github.io/harnessr/articles/readers.html#set-answer-format) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `parsed` | advanced | untested | How answering requests report their outcome: parsed from free text, or in a JSON schema the request forces. |
| [`premise_verdict`](https://elkronos.github.io/harnessr/articles/readers.html#set-premise) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md) | `sentence` | advanced | untested | Under premise = TRUE: the verdict as a sentence in the reply, or as schema fields with a quote that is checked against the excerpts. |
| `recipe` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `thorough` | basic |  | One recipe, applied to every document. |
| `store` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `NULL` | basic |  | Optional directory. |
| `on_error` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `continue` | advanced |  | “continue” (default) records the failure and moves on; “stop” aborts. |
| `max_total_usd` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `NULL` | basic |  | Stop once the run has spent this much, marking the remaining documents “skipped”, except any restored from store, which costs nothing. |
| `max_total_calls` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `NULL` | advanced |  | Stop before a document once the run has made this many requests, marking the rest “skipped”, except any restored from store, which makes no request. |
| `keep_answers` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `TRUE` | advanced |  | Keep every gr_answer in the result. |
| `recursive` | [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) | `FALSE` | advanced |  | Descend into subdirectories when sources is a directory. |

## Screening

The arguments of
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
of
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
and
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
which measure the screening against a person, and of the sample size and
stopping tests.
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
covers them.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `recipe` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `research` | basic |  | The ingest and segmentation to use. |
| `store` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `NULL` | advanced |  | Optional directory. |
| `screen_tokens` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `NULL` | basic | untested | Cap what the model is shown, in tokens, counted from the start of the document. |
| `on_error` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `continue` | advanced |  | “continue” (default) records the failure and moves on; “stop” aborts. |
| `max_total_usd` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `NULL` | basic |  | Stop once the run has spent this much, marking the remaining documents “skipped”, except any restored from store, which costs nothing. |
| `max_total_calls` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `NULL` | advanced |  | Stop before a document once the run has made this many requests, marking the rest “skipped”, except any restored from store, which makes no request. |
| `keep_answers` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `FALSE` | advanced |  | Keep the underlying gr_answer objects in \$answers. |
| `recursive` | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `FALSE` | advanced |  | Descend into subdirectories when sources is a directory. |
| [`criteria_schema`](https://elkronos.github.io/harnessr/articles/review.html#set-screen-reply) | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `decision` | advanced | untested | What each screening reply holds. |
| [`samples`](https://elkronos.github.io/harnessr/articles/review.html#set-screen-reply) | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `1` | advanced | untested | How many times each document’s screening request is sent, from 1 to 20. |
| [`sample_rule`](https://elkronos.github.io/harnessr/articles/review.html#set-screen-reply) | [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md) | `include_if_any` | advanced | untested | How draws are combined when samples is above 1. |
| `n` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `50` | basic |  | How many to draw: a whole number of at least 1. |
| `of` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `excluded` | basic |  | Which rows to sample from: “excluded”, “kept” (include and unclear), “all”, or “stacked” (every kept record and a sample of the excluded ones). |
| `seed` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `NULL` | advanced |  | A seed for the draw, so it is reproducible: the sample is drawn after set.seed(seed) and your session’s random number stream is put back afterwards. |
| `blind` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `TRUE` | advanced |  | Leave the model’s decision and reason out of the file. |
| `frame` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `NULL` | advanced |  | The same as of, under the name gr_screen_sample_size() uses. |
| `reviewers` | [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md) | `1` | advanced |  | How many people will judge each record. |
| `positive` | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `include` | advanced |  | Which human decision counts as eligible: “include” or “exclude”. |
| `min_positives` | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `10` | advanced |  | For an “all” sample: below this many eligible studies the sensitivity estimate is reported but marked inadequate. |
| `of` | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `NULL` | advanced |  | Which part of the screening run the reference was drawn from: “excluded”, “kept”, “all” or “stacked”; anything else is an error. |
| [`recall_target`](https://elkronos.github.io/harnessr/articles/review.html#set-calibration) | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `0.95` | basic | untested | The recall the screener should reach, strictly between 0 and 1. |
| [`conf`](https://elkronos.github.io/harnessr/articles/review.html#set-calibration) | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `0.95` | basic | untested | Confidence level of the recall and loss bounds. |
| `max_lost` | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `NULL` | advanced |  | Optional: the most eligible records the screener may have excluded. |
| [`max_width`](https://elkronos.github.io/harnessr/articles/review.html#set-calibration) | [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md) | `0.1` | advanced | untested | For a sample of one stratum: the widest interval, as a proportion, its headline rate may have for the sample to be adequate. |
| [`recall_target`](https://elkronos.github.io/harnessr/articles/review.html#set-calibration) | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `0.95` | basic | untested | The recall to show, strictly between 0 and 1. |
| [`conf`](https://elkronos.github.io/harnessr/articles/review.html#set-calibration) | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `0.95` | basic | untested | Confidence level of the one-sided bound. |
| `prevalence` | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `NULL` | basic |  | Expected share of eligible records among those drawn, for frame = “all”: turns the eligible records needed into records to draw. |
| `frame` | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `all` | advanced |  | “all”, “excluded” or “stacked”, as in gr_reference(). |
| `max_lost` | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `NULL` | advanced |  | For “excluded” and “stacked”: the most eligible records the screener may have excluded while still meeting the target. |
| `frame_n` | [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md) | `NULL` | advanced |  | Number of records in the frame sampled: the excluded records for “excluded” and “stacked”, everything screened for “all”, where with prevalence it caps the draw at the whole frame. |
| `target` | [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md) | `0.95` | basic |  | Recall level, strictly between 0 and 1. |
| `alpha` | [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md) | `0.05` | advanced |  | Significance level, strictly between 0 and 1. |
| `n_total` | [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md) | `NULL` | advanced |  | Total number of records, screened or not. |

## Extraction

The arguments of
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).
Recipe settings passed to it in `...` are the ingest and segment
settings above.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `recipe` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `research` | basic |  | The ingest and segmentation to use. |
| `store` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `NULL` | advanced |  | Optional directory. |
| [`resolve`](https://elkronos.github.io/harnessr/articles/review.html#set-extract) | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `first` | basic | untested | What to do when two parts of one document give different values for the same field. |
| [`require_quote`](https://elkronos.github.io/harnessr/articles/review.html#set-extract) | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `FALSE` | basic | untested | Discard any value that is not verified: one with no quote, a quote that is not verbatim in the chunk it cited, or a quote that does not state the value (see “Verifying it” below). |
| `on_error` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `continue` | advanced |  | “continue” (default) records the failure and moves on; “stop” aborts. |
| `max_total_usd` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `NULL` | advanced |  | Stop once the run has spent this much, marking the remaining documents “skipped”, except any restored from store, which costs nothing. |
| `max_total_calls` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `NULL` | advanced |  | Stop before a document once the run has made this many requests, marking the rest “skipped”, except any restored from store, which makes no request. |
| `keep_answers` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `FALSE` | advanced |  | Keep the underlying gr_answer objects in \$answers. |
| `recursive` | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `FALSE` | advanced |  | Descend into subdirectories when sources is a directory. |
| [`agreement_columns`](https://elkronos.github.io/harnessr/articles/review.html#set-extract) | [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md) | `FALSE` | advanced | untested | Add two columns per field to table, after the field columns: \_agreement, how many of the chunks that reported the field give its most common value, of all that reported it (“2/3”), and \_conflict, TRUE when they gave more than one value. |

## Synthesis

The arguments of
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
[`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md).

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `model` | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `NULL` | basic |  | Passed to the model call. |
| `temperature` | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `NULL` | advanced |  | Passed to the model call. |
| `max_claim_tokens` | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `1600` | advanced |  | Passed to the model call. |
| `include_unclear` | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `FALSE` | advanced |  | Keep rows with nothing extracted. |
| `effort` | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `NULL` | advanced |  | Reasoning effort, or NULL (the default) to send none: one string, or a character vector named by stage, as effort in gr_read_spec(). |
| [`unverified`](https://elkronos.github.io/harnessr/articles/review.html#set-synthesis) | [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) | `exclude` | advanced | untested | What the claims prompt does with an extracted value whose quote did not verify, or that came with no quote (see gr_extract(), “Verifying it”). |
| `model` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `NULL` | advanced |  | Passed to the model call. |
| `temperature` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `NULL` | advanced |  | Passed to the model call. |
| `max_sections` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `6` | basic |  | Upper bound on sections, before the closing one. |
| `closing` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `What is missing` | advanced |  | The heading of the closing section, which receives gap claims and anything unplaced. |
| `max_outline_tokens` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `NULL` | advanced |  | The reply limit for the outline call. |
| `effort` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `NULL` | advanced |  | Reasoning effort, or NULL (the default) to send none: one string, or a character vector named by stage, as effort in gr_read_spec(). |
| `alternatives` | [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md) | `1` | advanced |  | How many outlines to ask for, from 1 to 10. |
| `max_cells` | [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md) | `40` | advanced |  | Cap on reported empty combinations, which grow as the product of two fields’ sizes. |
| `min_reported` | [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md) | `0.5` | advanced |  | A field missing for more than this fraction of studies is reported as not reported. |
| `model` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `NULL` | basic |  | Overrides for the writing calls. |
| `max_section_tokens` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `1200` | advanced |  | Overrides for the writing calls. |
| `temperature` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `NULL` | advanced |  | Overrides for the writing calls. |
| `include_unclear` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `FALSE` | advanced |  | Write from rows whose extraction was incomplete. |
| `cite_style` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `auto` | basic |  | How citations appear in the finished prose. |
| `style` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `NULL` | advanced |  | A register instruction appended to the writing prompts, such as “formal academic; hedge claims; past tense for findings”. |
| [`coherence`](https://elkronos.github.io/harnessr/articles/review.html#set-synthesis) | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `FALSE` | basic | untested | Revision passes over the finished draft: TRUE for all three, FALSE for none, or any of “structure” (reorder and merge), “cut” (remove repetition) and “register” (polish sentences) by name. |
| `references` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `TRUE` | advanced |  | Append a \## References section built from the studies the finished text actually cites. |
| `effort` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `NULL` | advanced |  | Reasoning effort, or NULL (the default) to send none: one string, or a character vector named by stage, as effort in gr_read_spec(). |
| [`coherence_rounds`](https://elkronos.github.io/harnessr/articles/review.html#set-synthesis) | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `1` | advanced | untested | How many rounds each coherence pass may run: each round revises the text the round before it kept, and the pass stops at the first round that is discarded or changes nothing. |
| [`figure_bands`](https://elkronos.github.io/harnessr/articles/review.html#set-synthesis) | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `c(about = 0.1, over = 0.25, under = 0.25)` | advanced | untested | How near a value a qualified figure must be to count as found in the check of figures (see “Figures”): a named numeric vector of about (the share either way that “about 1,200” covers), over (the share above that “more than 1,000” covers) and under (the share below that “fewer than 1,000” covers). |
| [`prominence`](https://elkronos.github.io/harnessr/articles/review.html#set-synthesis) | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `c(top = 1/3, middle = 1/3)` | advanced | untested | How much of the writing prompt’s sentence budget the claims of a section get, by rank: c(top = , middle = ), the shares of a section’s claims (ranked by the sign test of their direction tally, lowest p first, with a claim more of whose studies contradict it than support it last, then by the weight of the studies behind them; see gr_claims(), “Direction of effect”) asked for “two or three sentences” and “one or two sentences”; the rest get “one sentence”, and a section of three claims or fewer gives each “two or three”. |
| `study_weights` | [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) | `NULL` | advanced |  | How much each study counts when claims are ranked, among claims whose sign tests tie (and so which tier each claim gets, see prominence): NULL (the default) for the package’s weight, 0.5 + 0.5 \* size + 0.5 \* filled, where size is log1p(n) over its largest value (the mean of the known ones when n is missing) and filled the share of a row’s filled cells whose quotations verified (0.5 when unknown). |

## Evaluation

The arguments of
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
and
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md).
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
and
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
cover them.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `runs` | [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | `5` | basic |  | How many times each arm runs on each item: a whole number, at least 1. |
| `scorer` | [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | [`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md) | basic |  | An hr_scorer(); hr_scorer_exact() by default. |
| `split` | [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | `test` | advanced |  | The split or splits of the reference to run on. |
| [`governor`](https://elkronos.github.io/harnessr/articles/runs.html#set-governor) | [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | `NULL` | basic |  | An hr_governor() the whole benchmark is held to, or NULL to take the limits from gr_options(). |
| `seed` | [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | `1` | advanced |  | The seed of the arms’ private random stream. |
| `contrasts` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `NULL` | advanced |  | Pairs of arms to compare: a two-column character matrix of arm names, each row giving first minus second. |
| `B` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `2000` | advanced |  | Number of cluster bootstrap resamples, at least 100. |
| `conf` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `0.95` | basic |  | Confidence level of every interval. |
| `k` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `c(1, 3, 5)` | advanced |  | The values of k for pass^k. |
| `seed` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `1` | advanced |  | Seed of the private random stream the resamples are drawn from; the caller’s random state is left as it was. |
| `method` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `auto` | basic |  | “auto”, “bootstrap”, “cluster_t”, “bayes” or “exact”, as above. |
| `confirmatory` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `FALSE` | advanced |  | TRUE for a confirmatory report, which raises the default B to 5000 and refuses dev-split rows. |
| `auto_bootstrap_at` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `c(items = 300, clusters = 30)` | advanced |  | Under method = “auto”, the size at which the report switches from the cluster-robust t interval to the studentised cluster bootstrap: c(items = , clusters = ), both reached. |
| `min_runs` | [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | `5` | advanced |  | The fewest runs for which the report gives intervals; below it the report is descriptive only. |
| `mode` | [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | `select` | basic |  | “select”, “grade” or “pairwise”. |
| `model` | [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | `NULL` | basic |  | The judge’s model; the client’s model when NULL. |
| `orders` | [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | `2` | basic |  | Presentation orders. |
| [`governor`](https://elkronos.github.io/harnessr/articles/runs.html#set-governor) | [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | `NULL` | advanced |  | Optional hr_governor() for the judge’s requests. |
| `draw_index` | [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | `0` | advanced |  | Draw index passed to every request (see gr_call()). |
| `recipes` | [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md) | `c("fast", "needle", "thorough")` | basic |  | A character vector of recipe names, or a list of gr_recipes. |
| `allow_duplicates` | [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md) | `FALSE` | advanced |  | Run duplicates anyway (useful at temperature \> 0 to measure variance). |
| `on_error` | [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md) | `continue` | advanced |  | “continue” keeps going and records the failure; “stop” aborts the whole comparison. |
| [`strata`](https://elkronos.github.io/harnessr/articles/evaluate.html#set-errcorr) | [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | `NULL` | advanced | untested | NULL to stratify by difficulty, or each item’s stratum: a vector named by item, or one value per item in the order of unique(bench\$item). |
| [`n_strata`](https://elkronos.github.io/harnessr/articles/evaluate.html#set-errcorr) | [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | `3` | advanced | untested | How many difficulty strata, when strata is NULL: a whole number from 1 to 10, default 3. |
| [`n_check`](https://elkronos.github.io/harnessr/articles/evaluate.html#set-errcorr) | [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | `10` | advanced | untested | How many items every arm got wrong to sample for a hand check: a whole number, 0 or more, default 10. |
| [`held_out`](https://elkronos.github.io/harnessr/articles/evaluate.html#set-errcorr) | [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | `TRUE` | advanced | untested | TRUE (the default) reads only the rows that count as evidence (reportable, so not the dev split); FALSE reads every row. |
| [`seed`](https://elkronos.github.io/harnessr/articles/evaluate.html#set-errcorr) | [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | `1` | advanced | untested | The seed of the private random stream the sample is drawn with; the caller’s random state is left as it was. |

## Options

Session settings, set with
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
and read when a run starts.
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
covers the limits.

| setting | where | default | tier | status | description |
|:---|:---|:---|:---|:---|:---|
| `verbose` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `TRUE` | basic |  | Print a line for each ingest, segment and read stage. |
| `tokenizer` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `heuristic` | advanced |  | Token counter: “heuristic” (conservative, no dependencies), “words”, “chars”, “tiktoken” (needs reticulate), or a name registered via gr_set_tokenizer(). |
| `model` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `gpt-5.6-terra` | basic |  | Default chat model. |
| `embedding_model` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `text-embedding-3-small` | advanced |  | Default embedding model. |
| `api_base` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `https://api.openai.com/v1` | advanced |  | API root; point this at a proxy or a compatible endpoint. |
| `api_headers` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `character(0)` | advanced |  | Named character vector of extra HTTP headers sent with every request, for gateways that do not authenticate with a bearer token. |
| `api` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `responses` | advanced |  | “responses” or “chat” request shape. |
| `temperature` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | advanced | untested | Default sampling temperature. |
| `max_retries` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `4` | advanced | untested | Retries for transient failures. |
| `retry_pause_base` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `2` | advanced | untested | Seconds; exponential backoff base. |
| `request_timeout` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `120` | advanced | untested | Per-request timeout, seconds. |
| `safety_margin` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `0.1` | advanced | untested | Fraction of the context window left unused to absorb tokenizer error. |
| `min_output_tokens` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `256` | advanced | untested | Floor on the completion room gr_budget() reserves when reserve_output is not given explicitly. |
| `cache_documents` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `TRUE` | advanced |  | Cache ingestion per file + settings. |
| `cache_embeddings` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `TRUE` | advanced |  | Cache embeddings per text + model. |
| `cache_dir` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | basic |  | Directory gr_cache() stores model responses in. |
| `embedder` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | advanced |  | Which registered embedder to use. |
| `parallel` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `FALSE` | advanced |  | Run per-chunk calls concurrently. |
| `workers` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `4` | advanced | untested | Worker processes when parallel is TRUE. |
| [`max_cost_usd`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `5` | basic |  | Spending limit per run, in USD. |
| [`max_calls`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `400` | basic |  | Hard cap on model calls per run, checked before every request. |
| [`max_tokens_total`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | advanced |  | Most tokens one run may use: the prompt and reply tokens of every call, cache hits included, and the text sent to be embedded. |
| [`max_output_tokens`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | advanced |  | The largest output cap one request may be sent with. |
| [`allowed_models`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `NULL` | advanced |  | Character vector of the model ids a run may call, chat and embedding models alike. |
| [`allow_unpriced`](https://elkronos.github.io/harnessr/articles/runs.html#set-limits) | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `FALSE` | advanced |  | Whether a chat model with no registered price may be called while max_cost_usd is set. |
| `unknown_model_action` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `warn` | advanced |  | “warn” or “error” when a model id is not in the registry. |
| `actor` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | [`list()`](https://rdrr.io/r/base/list.html) | advanced |  | A named list (or character vector) of the actor fields every gr_trace() records: system, owner, run_by, purpose and approved_by, each one string. |
| `auto_max_tokens` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `50000` | advanced | untested | The largest document, in tokens, that answer_document() with recipe = “auto” reads with “fast” (one request); a larger one is read with “thorough”. |
| `auto_room_share` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `0.5` | advanced | untested | The second condition of that choice: the document must fill at most this share of the input room gr_budget() leaves on every model of the run. |
| `reasoning_floor` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `2048` | advanced | untested | The smallest output cap a request to a reasoning model is sent with. |
| `output_reserve_share` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `0.25` | advanced | untested | The share of the usable window gr_budget() reserves for the reply when no reserve_output is given, between min_output_tokens and the model’s output limit. |
| `near_verbatim_sim` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `0.9` | advanced | measured | The least similarity a quotation of at least near_verbatim_short_chars characters (after normalising), and one shorter than that, needs for the edit-distance matcher to score it near_verbatim (see gr_verify_evidence()). |
| `near_verbatim_sim_short` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `0.95` | advanced | measured | The least similarity a quotation of at least near_verbatim_short_chars characters (after normalising), and one shorter than that, needs for the edit-distance matcher to score it near_verbatim (see gr_verify_evidence()). |
| `near_verbatim_short_chars` | [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md) | `40` | advanced | measured | The least similarity a quotation of at least near_verbatim_short_chars characters (after normalising), and one shorter than that, needs for the edit-distance matcher to score it near_verbatim (see gr_verify_evidence()). |

## Building blocks

Some settings choose a module from a registry: `extractor`, `clean`,
`method`, `reader`, `gr_options(embedder = )`, and the recipe given to
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md).
The tables below are the registries as installed, so a module you
register with
[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
and the like
([`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md))
appears in them too.

### Extractors

An extractor turns one kind of file into text. It is chosen by the
file’s extension unless `extractor` names one.

``` r

knitr::kable(gr_extractors()[, c("name", "extensions", "needs", "description")])
```

|  | name | extensions | needs | description |
|:---|:---|:---|:---|:---|
| txt | txt | txt, text, log, csv, tsv |  | Plain text, including delimited files |
| md | md | md, markdown, rmd, qmd |  | Markdown, keeping heading structure |
| html | html | html, htm, xhtml | xml2 | HTML via xml2, keeping heading structure |
| pdf | pdf | pdf | pdftools | PDF with per-page OCR fallback and page provenance |
| docx | docx | docx, dotx | xml2 | Word: headings, tables by row, footnotes and endnotes; OCRs embedded images |
| image | image | png, jpg, jpeg, tif, tiff, bmp, gif | tesseract | Image OCR |

### Cleaners and presets

A cleaner removes one kind of noise from the text. Those marked
`default_on` run unless the preset or list you give leaves them out;
`early` cleaners run before `late` ones whatever order they are named
in.

``` r

knitr::kable(gr_cleaners()[, c("name", "stage", "default_on", "description")])
```

| name | stage | default_on | description |
|:---|:---|:---|:---|
| captions | early | FALSE | Drop figure/table caption lines: ‘Table 2.’, ‘Figure 3:’, ‘Fig. 3 \|’, ‘Table 2 Baseline …’ or the label alone, not ‘Table 2 shows …’ (OFF by default: a caption can be the only statement of a result) |
| emails | early | FALSE | Remove email addresses |
| headers_footers | early | FALSE | Drop running heads and feet: short lines repeated at the top or bottom of many pages, or at the edge of blocks where pages are not known |
| hyphenation | early | TRUE | Rejoin words split across line breaks by PDF layout (‘mito-’, ‘LIA-’ in capitals); a compound the document writes with its hyphen elsewhere (‘follow-up’) keeps it; number ranges (‘18-’) and compounds (‘Anglo-’) are left alone |
| page_numbers | early | TRUE | Drop decorated page-number lines (‘Page 4’, ‘- 12 -’, ‘\[12\]’, and ‘12.’ unless the line before runs on into it); bare numbers are kept |
| references | early | FALSE | Drop a trailing bibliography, from a References/Bibliography heading to the end; in a Markdown file a line indented 4 or more spaces is code, not a heading |
| urls | early | FALSE | Remove URLs (OFF by default: URLs are often the answer) |
| ascii_only | late | FALSE | Transliterate to ASCII (drops accents and non-Latin scripts) |
| collapse_whitespace | late | TRUE | Collapse runs of spaces/tabs and 2+ consecutive blank lines, and trim block edges; preserves paragraph breaks |
| control_chars | late | TRUE | Strip control and zero-width characters that survive PDF extraction |
| ligatures | late | TRUE | Expand typographic ligatures and straighten smart quotes; en and em dashes are kept |
| lowercase | late | FALSE | Lowercase everything (loses proper-noun and acronym signal) |
| remove_numbers | late | FALSE | Replace every digit with a space. OFF by default: this makes figures, dates and percentages unanswerable |
| remove_punctuation | late | FALSE | Replace punctuation with spaces. OFF by default: destroys sentence boundaries |

A preset is a named list of cleaners. The steps each one runs, read from
what it did to the example report:

``` r

presets <- c("none", "minimal", "standard", "academic", "scan", "legacy")
knitr::kable(data.frame(preset = presets, cleaners = vapply(presets, function(p) {
  steps <- names(gr_ingest(gr_example(), gr_ingest_spec(clean = p))$stats$clean_log)
  if (length(steps)) paste(steps, collapse = ", ") else "(none)"
}, character(1)), row.names = NULL))
```

| preset | cleaners |
|:---|:---|
| none | (none) |
| minimal | control_chars, collapse_whitespace |
| standard | page_numbers, hyphenation, control_chars, ligatures, collapse_whitespace |
| academic | page_numbers, captions, references, hyphenation, control_chars, ligatures, collapse_whitespace |
| scan | page_numbers, headers_footers, hyphenation, control_chars, ligatures, collapse_whitespace |
| legacy | page_numbers, captions, urls, emails, references, remove_numbers, collapse_whitespace |

### Segmenters

A segmenter decides where chunks are cut. `cost` says what it spends:
`free`, one embedding pass, or model requests.

``` r

knitr::kable(gr_segmenters()[, c("name", "cost", "needs_client", "description")])
```

| name | cost | needs_client | description |
|:---|:---|:---|:---|
| contextual | free | FALSE | Paragraph chunks prefixed with where they sit; context_source=‘llm’ writes it per chunk, one request each (calls_max = chunks). |
| fixed | free | FALSE | Uniform token windows, ignoring structure. The control condition. |
| page | free | FALSE | One chunk per page. For forms, invoices and scanned records. |
| paragraph | free | FALSE | Greedy packing of the author’s paragraphs up to the cap. |
| proposition | llm | TRUE | Rewrite into standalone factual statements. Expensive; best for dense factual recall. |
| recursive | free | FALSE | Cascade through separators, using the strongest one that fits. |
| semantic | embedding | TRUE | Cut where consecutive embeddings diverge most. One embedding pass. |
| sentence | free | FALSE | Sentence-boundary packing; tighter, more chunks, cleaner edges. |
| structural | free | FALSE | Never merge across headings; each chunk keeps its section title. |

### Readers

A reader decides how the chunks reach the model. `signature` is which
chunks are sent, how many requests, and how information passes between
them; `cost_calls` is the number of requests.

``` r

knitr::kable(gr_readers()[, c("name", "signature", "cost_calls", "description")])
```

| name | signature | cost_calls | description |
|:---|:---|:---|:---|
| ensemble | ensemble\|sum+1\|none | sum of members + 1 | Run several distinct readers and adjudicate. Members must have different signatures. |
| extract | all\|N+conflicts\|none | N (+1 per conflict with resolve = ‘model’) | Fill a typed schema from every chunk, then reconcile. Needs `fields`. |
| hierarchical | all\|N+tree+1\|tree | N + fan-in levels + 1 | Recursively summarise until the summaries fit, then answer. Truly recursive. |
| iterative | topk\|rounds\*2\|forward | up to 2 x max_rounds | Agentic loop: the model names what it still needs and that drives the next retrieval. |
| map_reduce | all\|N+logN\|tree | N + merges | Answer each chunk independently, then tree-reduce. Parallel, order-independent. |
| preview | planned\|1+s+1\|none | 1 + skimmed sections + 1 | Plan from an outline first, then read only what the plan says to. Sections it skips are named. |
| refine | all\|N\|forward | N | Sequential draft-and-revise down the document. Order matters; not parallelisable. |
| rerank | topk\|m+1\|none | m + 1 | BM25 prefilter, then the model scores candidates, then answer from the winners. |
| retrieve | topk\|1\|none | 1 + embeddings | Embed, rank by cosine similarity, answer from the top k. Cost independent of length. |
| screen | head\|1\|none | 1 | Decide whether one document meets a review’s criteria, from its opening. Needs `include`/`exclude`. |
| skim | all\|N+1\|none | N + 1 | Extract verbatim evidence per chunk, then answer once from the evidence. |
| stuff | all\|1\|none | 1 | Whole document in one prompt. The baseline; errors or truncates if it does not fit. |

### Embedders

An embedder turns text into vectors for `retrieve`, `iterative` and the
`semantic` segmenter. A deterministic one gives the same vectors every
run, which a replay needs.

``` r

knitr::kable(gr_embedders()[, c("name", "deterministic", "description")])
```

| name | deterministic | description |
|:---|:---|:---|
| api | FALSE | Embeddings endpoint on the client’s base URL |
| lexical | TRUE | Hashed bag-of-words; free, offline, word overlap not meaning |

### Recipes

A recipe names an ingestion, a segmentation and a reader with their
settings. These are the values each built-in recipe sets; any of them
can be overridden by name.

``` r

knitr::kable(do.call(rbind, lapply(names(gr_recipes()), function(n) {
  r <- gr_recipes(n)
  data.frame(recipe = n, clean = paste(r$ingest$clean, collapse = ", "),
             method = r$segment$method, max_tokens = r$segment$max_tokens,
             overlap_tokens = r$segment$overlap_tokens, reader = r$read$reader,
             top_k = r$read$top_k)
})))
```

| recipe    | clean    | method     | max_tokens | overlap_tokens | reader       | top_k |
|:----------|:---------|:-----------|-----------:|---------------:|:-------------|------:|
| fast      | standard | paragraph  |       4000 |              0 | stuff        |     6 |
| precise   | standard | sentence   |        600 |             60 | skim         |     6 |
| needle    | standard | semantic   |        500 |             50 | retrieve     |     8 |
| thorough  | standard | paragraph  |       1200 |            120 | map_reduce   |     6 |
| survey    | standard | structural |       1500 |              0 | hierarchical |     6 |
| narrative | standard | paragraph  |       1500 |              0 | refine       |     6 |
| scanned   | scan     | page       |       2000 |              0 | rerank       |     6 |
| research  | academic | structural |        900 |             90 | iterative    |     5 |
| consensus | standard | recursive  |       1000 |            100 | ensemble     |     6 |
| legacy    | legacy   | paragraph  |       3000 |              0 | map_reduce   |     6 |

## Next

- [`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md):
  the basic settings of each stage, with when to change each.
- [`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md):
  testing a setting on a reference with dev and test splits, and reading
  the result with intervals.
- [`?gr_settings_table`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md):
  how the table is built, and its columns.
