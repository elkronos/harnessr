# Where a segmentation puts its boundaries, sentence by sentence

Turns a segmentation into the boundary sequence
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
and
[`gr_seg_windowdiff()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
compare: the document is split into sentences, each sentence is placed
in a segment, and position `j` is 1 when sentence `j + 1` is in a later
segment than sentence `j`. Two segmentations of one document mapped this
way are on the same units and can be compared.

## Usage

``` r
gr_seg_boundaries(x, doc)
```

## Arguments

- x:

  A
  [gr_chunks](https://elkronos.github.io/harnessr/reference/gr_chunks.md)
  from
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
  or a character vector of segments in document order (a reference
  segmentation, for example the document's topics as a person split
  them).

- doc:

  The document `x` segments: a `gr_document` from
  [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md),
  or text.

## Value

An integer vector of 0 and 1 with one element per pair of neighbouring
sentences (the number of sentences less one), with attributes `units`
(the number of sentences) and `unplaced`.

## Details

A segment is matched on its text with runs of white space made one
space, and on a chunk's `source_text` when it has one, so the context
line of a `contextual` chunk is not part of the match. When every
segment is a verbatim part of the document, each segment and each
sentence is located in the document, in order, and a sentence goes to
the first segment that holds its first character. A sentence the
document repeats, such as "See note 3." at the start of two sections,
therefore goes to the segment it occurs in, not to the first segment
whose text contains it. A boundary inside a sentence counts at the end
of that sentence, and overlap does not add boundaries: a sentence
carried into the next chunk stays in the first chunk that holds its
start.

When a segment is not verbatim (a segmenter that rewrites text, or a
reference typed by hand), sentences are matched on text instead: each in
the current segment after the text the sentences before it took, or in a
later segment; failing that, by its opening, its first 40 characters or
its first half when that is shorter. A sentence placed neither way stays
in the segment before it and is counted in the `unplaced` attribute.

## See also

[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_seg_windowdiff()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)

Other segmentation functions:
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
doc <- paste("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
             "The chair retired.", sep = "\n\n")
gr_seg_boundaries(c("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
                    "The chair retired."), doc)
#> [1] 0 1 0 1
#> attr(,"units")
#> [1] 5
#> attr(,"unplaced")
#> [1] 0
ch <- gr_segment(doc, list(method = "sentence", max_tokens = 32))
#> Ingested 3 block(s), ~26 tokens (0 chars removed by cleaning).
#> Segmenting with 'sentence' (cap 32 tokens, overlap 0).
gr_seg_boundaries(ch, doc)
#> [1] 0 0 0 1
#> attr(,"units")
#> [1] 5
#> attr(,"unplaced")
#> [1] 0
```
