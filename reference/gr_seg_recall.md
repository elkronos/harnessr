# Retrieval recall at k, per segmenter

For each segmenter, cuts each document of a question-answering
reference, ranks its chunks for each question the way the `retrieve`
reader does, and counts the questions whose answer is in one of the
first `k` chunks. This is the share of questions a `retrieve` reader
with `top_k = k` could answer, before any model reads anything, so
segmenters and chunk sizes can be compared for nothing (with the lexical
embedder) or for one embedding request per question and segmenter.

## Usage

``` r
gr_seg_recall(
  reference,
  segmenters,
  k = c(1, 3, 5),
  client = NULL,
  read = list(),
  split = "test"
)
```

## Arguments

- reference:

  A reference from
  [`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md).

- segmenters:

  The segmentations: a character vector of segmenter names, or a list of
  names,
  [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  objects or named lists of its settings. One spec or one list of
  settings on its own is one segmentation. Unnamed entries are named by
  their method and size, as `"fixed_32"`.

- k:

  The cut-offs, whole numbers of at least 1.

- client:

  The client that embeds, or `NULL` for the lexical embedder (and for
  segmenters that call no model).

- read:

  Named list of
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  settings for the ranking.

- split:

  The split or splits of `reference` to use.

## Value

A data frame with one row per segmenter and `k`: `segmenter`, `k`,
`hits`, `questions`, `recall`, `no_chunk` (questions whose answer is in
no chunk), `chunks` (mean chunks per document) and `documents`.
Attribute `ranks` holds one row per segmenter and question with the rank
of the first chunk holding the answer (`NA` when none does).

## Details

A chunk holds the answer when its text (its `source_text`, when it has
one) contains one of the item's accepted answers, matched as
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
matches them: case, white space and thousands separators folded, numbers
matched whole. An answer cut in two by a chunk edge is in no chunk, and
the question counts as a miss at every `k`; the `no_chunk` column counts
those questions. Unanswerable items and items with no label are left
out.

The ranking is cosine similarity on the embeddings `client` gives (see
[`gr_embed()`](https://elkronos.github.io/harnessr/reference/gr_embed.md)),
blended with BM25 by `lexical_blend` when the embeddings are lexical, as
in
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md).
`read` takes those
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
settings (`lexical_blend`, `bm25_k1`, `bm25_b`). The `mmr` and
`min_score` settings of the reader are not applied: this is the ranking
alone.

The figures are descriptive. Questions about one document share its
chunking, so they are not independent, and no interval is given; compare
segmenters on the same questions, and on a split you did not tune on.

## See also

[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)

Other segmentation functions:
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md),
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
old <- gr_options(verbose = FALSE, embedder = "lexical")
doc <- paste("Revenue was 45.2 million dollars in fiscal 2024.",
             "The plant in Leeds made 12,400 units.",
             "Staff numbered 310 at year end.", sep = "\n\n")
ref <- gr_qa_reference(c(rev = "What was revenue?", units = "How many units?"),
                       documents = doc, answers = list("45.2 million", "12,400"),
                       split = "test")
gr_seg_recall(ref, list(sentence = list(method = "sentence", max_tokens = 40),
                        fixed = list(method = "fixed", max_tokens = 32)), k = 1:2)
#>   segmenter k hits questions recall no_chunk chunks documents
#> 1  sentence 1    2         2      1        0      2         1
#> 2  sentence 2    2         2      1        0      2         1
#> 3     fixed 1    2         2      1        0      2         1
#> 4     fixed 2    2         2      1        0      2         1
gr_options(old)
```
