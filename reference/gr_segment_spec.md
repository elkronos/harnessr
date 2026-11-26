# Describe a segmentation configuration

Describe a segmentation configuration

## Usage

``` r
gr_segment_spec(
  method = "paragraph",
  max_tokens = 1200L,
  overlap_tokens = 0L,
  min_tokens = 0L,
  separators = NULL,
  prefix_section = TRUE,
  semantic_window = 2L,
  semantic_percentile = 90,
  context_source = c("metadata", "llm"),
  proposition_batch_tokens = 900L,
  parallel = NULL,
  context_reply_tokens = 90L,
  context_document_tokens = 1500L,
  proposition_reply_tokens = 2000L,
  semantic_threshold = c("percentile", "texttiling"),
  table_packing = c("rows", "grouped"),
  proposition_check = c("count", "drop"),
  proposition_context_tokens = 0L,
  packing = c("greedy", "balanced"),
  runt_merge = c("backward", "both"),
  ...
)
```

## Arguments

- method:

  Segmenter name; see
  [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md).

- max_tokens:

  Hard cap on chunk size, in tokens. Always enforced: a segmenter cannot
  emit an oversized chunk, which the old `chunk_text_semantic()`
  routinely did. An oversized chunk is re-split, down to single
  characters if it has to be; if the active tokenizer counts even one
  character as more than the cap,
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
  stops with an error of class `"gr_cap_unenforceable"` rather than pass
  the chunk on.

- overlap_tokens:

  Tokens of trailing context copied into the start of the next chunk.
  Overlap is what stops an answer straddling a boundary from being lost
  by both chunks. Honoured by every segmenter except `page` (a page is
  the unit) and `proposition` (propositions are already self-contained).
  It is cut at sentences, then words; text written without spaces
  (Chinese, Japanese, Thai) is cut by characters. A chunk's page,
  section and block count the overlap it opens with, so one that carries
  a sentence from the page before reports `NA` rather than the page it
  goes on to.

- min_tokens:

  A chunk smaller than this is merged **backward** into the chunk before
  it (and, with `runt_merge = "both"`, a first chunk smaller than this
  forward into the one after it). Ignored by `page` and `fixed`.

- separators:

  For `method = "recursive"`: the cascade, strongest first. Each piece
  keeps the separator it was cut at; past the last one, text is cut at
  sentence ends, then whitespace, then characters, the same way. With no
  overlap, the chunks joined end to end are the document text exactly.

- prefix_section:

  For `method = "structural"`: prepend the heading. When the extractor
  supplies no sections, headings are found inline: a markdown `#` line,
  or a short line that is numbered and starts with a capital of any
  script (or a letter of a script without case), or is in capitals.

- semantic_window, semantic_percentile:

  For `method = "semantic"`: how many sentences to embed together, and
  how extreme a distance counts as a boundary (higher = fewer, larger
  chunks).

- context_source:

  For `method = "contextual"`: `"metadata"` (free) or `"llm"` (one call
  per chunk, never more: `$extra$cost` declares `calls_max` as the
  number of chunks, and a `segment.cost` trace step records it). Under
  `"llm"` each request carries the opening of the document
  (`context_document_tokens`) and the chunk's section path, as
  `"Methods > Participants"`, from the document's headings. Room for the
  context line is held back from each chunk's text before packing
  (`context_reply_tokens` for `"llm"`, the longest header the document
  could need for `"metadata"`, never more than half of `max_tokens`), so
  no chunk is cut again once its header is added, and a header that
  still does not fit is shortened, never the text. Under `"llm"`, a
  chunk whose call failed or was skipped at the run's limits keeps its
  text without a context line; `$extra$blurbs_missing` counts them and a
  `"gr_segment_fallback"` warning says so, which also reaches the
  answer's warnings.

- proposition_batch_tokens:

  For `method = "proposition"`: batch size. A proposition with no
  support in its batch (a number the batch does not give, or fewer than
  half of its words found in the batch and any context it was sent with)
  is counted in `$extra$propositions_unsupported`; see
  `proposition_check`. The chunks keep the page and section of the
  batches they come from.

- parallel:

  Parallelise per-chunk model work in segmenters that do any.

- context_reply_tokens:

  For `method = "contextual"` with `context_source = "llm"`: the output
  cap of each context-line request, and the room held back for the line
  in each chunk. \[16, 4000\], default 90. Untested.

- context_document_tokens:

  For `context_source = "llm"`: how much of the document, from its
  start, each context-line request carries so the model can place the
  excerpt. \[100, 1e6\], default 1500. Untested.

- proposition_reply_tokens:

  For `method = "proposition"`: the output cap of each batch's request.
  \[100, 1e6\], default 2000. Untested.

- semantic_threshold:

  For `method = "semantic"`: how boundaries are chosen. `"percentile"`
  (the default) cuts wherever the distance between two consecutive
  windows reaches the `semantic_percentile` of all of them, so about one
  gap in ten is cut whatever the text is about. `"texttiling"` cuts by
  depth score, as TextTiling does (Hearst, M. A. 1997, "TextTiling:
  segmenting text into multi-paragraph subtopic passages", Computational
  Linguistics 23(1), 33-64): each gap's similarity is the cosine between
  the `semantic_window` sentences before it and the `semantic_window`
  after it (the same windows, so no extra embedding request), its depth
  is how far that similarity sits below the nearest peak on each side,
  summed, and a gap is cut when it is a valley whose depth exceeds
  Hearst's cutoff (the mean depth less half its standard deviation) and
  also exceeds the spread of the similarities (largest less smallest).
  That second test is added here, not Hearst's, so a text on one topic
  gets at most about one cut. `semantic_percentile` is not used under
  `"texttiling"`. Untested.

- table_packing:

  For `method = "paragraph"`: how the rows of a table are packed.
  `"rows"` (the default) packs them as any other blocks, as before.
  `"grouped"` packs each table on its own: its first row, taken for the
  header, opens every chunk of the table, followed by as many rows as
  fit under `max_tokens`, joined by line breaks and with no overlap, so
  a 60-row table that needs three chunks gives three, each starting with
  the header. A table that fits is one chunk. Under either, the chunks
  of a document with a table carry `table_id` and `table_rows` (as
  `"2-21"`) saying which table and rows they hold. Untested.

- proposition_check:

  For `method = "proposition"`: what happens to a proposition with no
  support in its batch. `"count"` (the default) keeps it, as before, and
  counts it in `$extra$propositions_unsupported`. `"drop"` drops it as
  invented, counts it in `$extra$propositions_dropped` as well, and
  warns (`gr_proposition_dropped`); a batch left with no proposition is
  kept as written. Untested.

- proposition_context_tokens:

  For `method = "proposition"`: how many tokens from the end of the
  batch before each batch's request carries, as context the model may
  use to resolve what the batch refers back to but is told not to
  decompose. Taken from the document, so the batches still run
  independently. \[0, 2000\], default 0, which sends each batch alone,
  as before. Untested.

- packing:

  How `paragraph`, `sentence`, `recursive`, `structural` and `semantic`
  pack their units into chunks. `"greedy"` (the default) fills each
  chunk to `max_tokens` and leaves the remainder in the last, as before:
  1,250 tokens under a 500 cap become 500, 500 and 250. `"balanced"`
  keeps the number of chunks greedy packing makes, k, and evens their
  sizes: it cuts the units at the unit boundaries nearest to each k-th
  of the total tokens (about 420 each in that example). No unit is split
  for it: when a unit is longer than `max_tokens`, or a run between two
  cuts does not fit under it, the greedy chunks are kept. Untested.

- runt_merge:

  Which way a chunk under `min_tokens` is merged. `"backward"` (the
  default) merges it into the chunk before, as before, so a runt that is
  the first chunk stays on its own. `"both"` also merges a first chunk
  under `min_tokens` forward into the second, when the two fit under
  `max_tokens`. Nothing is merged at `min_tokens = 0`. Untested.

- ...:

  Extra fields for custom segmenters.

## Value

A list of class `gr_segment_spec`.

## Out-of-range values

Arguments are clamped into a usable range and the change is warned
about, never applied silently: `max_tokens` \[32, 1e6\],
`overlap_tokens` \[0, max_tokens - 1\], `min_tokens` \[0, max_tokens\],
`semantic_window` \[1, 10\], `semantic_percentile` \[50, 99.5\],
`proposition_batch_tokens` \[200, 4000\].

## Where the defaults come from

Each setting's default, its tier and the evidence behind the value, as
in
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).
`context_reply_tokens`, `context_document_tokens` and
`proposition_reply_tokens` were constants in the code; they are stored
in the spec only when they are not their default, so a default spec
keeps the store and cache keys it had before they existed.

- `context_source` (default `"metadata"`, advanced): untested. The
  source that makes no request; not compared with "llm".

- `max_tokens` (default `1200`, basic): untested. Set when the
  segmenters were written; not tuned.

- `overlap_tokens` (default `0`, basic): untested. No overlap, so no
  text is sent twice; not compared.

- `min_tokens` (default `0`, advanced): untested. No merging of small
  chunks; not compared.

- `method` (default `"paragraph"`, basic): untested. A segmenter that
  needs no model or embedder; not compared with the others.

- `separators` (default `NULL`, advanced): untested. Not a tuned value:
  NULL takes recursive's own cascade.

- `prefix_section` (default `TRUE`, advanced): untested. Set when
  structural was written; not compared.

- `semantic_window` (default `2`, advanced): untested. Set when semantic
  was written; not tuned.

- `semantic_percentile` (default `90`, advanced): untested. Set when
  semantic was written; not tuned.

- `proposition_batch_tokens` (default `900`, advanced): untested. Set
  when proposition was written; not tuned.

- `parallel` (default `NULL`, advanced): untested. Not a tuned value:
  NULL follows hr_options("parallel"). It does not change output.

- `context_reply_tokens` (default `90`, advanced): untested. The cap the
  code had as a constant; not tuned.

- `context_document_tokens` (default `1500`, advanced): untested. The
  length the code had as a constant; not tuned.

- `proposition_reply_tokens` (default `2000`, advanced): untested. The
  cap the code had as a constant; not tuned.

- `semantic_threshold` (default `"percentile"`, advanced): untested.
  "percentile" is the rule semantic was written with; not compared with
  "texttiling".

- `table_packing` (default `"rows"`, advanced): untested. "rows" packs a
  table's rows as any other blocks, as before; not compared with
  "grouped".

- `proposition_check` (default `"count"`, advanced): untested. "count"
  keeps every proposition, as before, and counts the unsupported; not
  compared with "drop".

- `proposition_context_tokens` (default `0`, advanced): untested. 0
  sends each batch alone, as before; not tuned.

- `packing` (default `"greedy"`, advanced): untested. "greedy" fills
  each chunk to the cap, as before; not compared with "balanced".

- `runt_merge` (default `"backward"`, advanced): untested. "backward"
  merges into the chunk before, as before; not compared with "both".

## See also

[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md)
for the available methods and their costs,
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)

Other segmentation functions:
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md),
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
gr_segment_spec("semantic", max_tokens = 800, overlap_tokens = 80)$overlap_tokens
#> [1] 80

# An impossible setting is corrected loudly.
suppressWarnings(gr_segment_spec("paragraph", max_tokens = 100,
                                 overlap_tokens = 500)$overlap_tokens)
#> [1] 99
```
