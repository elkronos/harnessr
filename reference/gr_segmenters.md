# List registered segmentation strategies

The catalogue for axis 2. Use it to see which strategies are free, which
spend an embedding pass or a model call, and which need a client at all.
The last is checkable here rather than only in prose, because a
segmenter that needs a client and does not get one falls back to a
different strategy.

## Usage

``` r
gr_segmenters()
```

## Value

A data frame with one row per registered segmenter: `name`, `cost`
(`"free"`, `"embedding"` or `"llm"`), `needs_client`
(`"TRUE"`/`"FALSE"`; when `TRUE` and no client is supplied,
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
warns and the segmenter falls back), `description`, and `calls`, the
stems of the labels its model calls carry, joined by commas (empty for
one that makes none). The last two columns are `version` and `contract`,
`NA` for a segmenter registered with
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
and filled for one registered with
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md).

## See also

[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)
to compare what they produce

Other segmentation functions:
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md),
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
gr_segmenters()
#>           name      cost needs_client
#> 1    by_bullet      free        FALSE
#> 2   contextual      free        FALSE
#> 3        fixed      free        FALSE
#> 4         page      free        FALSE
#> 5    paragraph      free        FALSE
#> 6  proposition       llm         TRUE
#> 7    recursive      free        FALSE
#> 8     semantic embedding         TRUE
#> 9     sentence      free        FALSE
#> 10  structural      free        FALSE
#>                                                                                                                        description
#> 1                                                                                                             one chunk per bullet
#> 2  Paragraph chunks prefixed with where they sit; context_source='llm' writes it per chunk, one request each (calls_max = chunks).
#> 3                                                                Uniform token windows, ignoring structure. The control condition.
#> 4                                                                     One chunk per page. For forms, invoices and scanned records.
#> 5                                                                         Greedy packing of the author's paragraphs up to the cap.
#> 6                                            Rewrite into standalone factual statements. Expensive; best for dense factual recall.
#> 7                                                                   Cascade through separators, using the strongest one that fits.
#> 8                                                               Cut where consecutive embeddings diverge most. One embedding pass.
#> 9                                                                  Sentence-boundary packing; tighter, more chunks, cleaner edges.
#> 10                                                                Never merge across headings; each chunk keeps its section title.
#>                  calls version contract
#> 1            by_bullet    <NA>     <NA>
#> 2      segment.context    <NA>      0.2
#> 3                         <NA>      0.2
#> 4                         <NA>      0.2
#> 5                         <NA>      0.2
#> 6  segment.proposition    <NA>      0.2
#> 7                         <NA>      0.2
#> 8                         <NA>      0.2
#> 9                         <NA>      0.2
#> 10                        <NA>      0.2

# The ones that cost money, and the ones that need a client to work at all.
subset(gr_segmenters(), cost != "free" | needs_client == "TRUE")[, 1:3]
#>          name      cost needs_client
#> 6 proposition       llm         TRUE
#> 8    semantic embedding         TRUE
```
