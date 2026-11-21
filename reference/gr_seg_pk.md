# Pk and WindowDiff: how far a segmentation's boundaries are from a reference

Both slide a window of `k` positions along two boundary sequences of the
same length and count the windows where they disagree, as a share of the
`L - k + 1` windows of a sequence of length `L`. `gr_seg_pk()`
(Beeferman, Berger and Lafferty 1999) counts a window as an error when
one sequence has a boundary in it and the other has none.
`gr_seg_windowdiff()` (Pevzner and Hearst 2002) counts it when the two
have a different number of boundaries in it, so it also sees a window
where the hypothesis puts two boundaries and the reference one. Both are
0 for identical sequences and rise towards 1; lower is better.

## Usage

``` r
gr_seg_pk(reference, hypothesis, k = NULL)

gr_seg_windowdiff(reference, hypothesis, k = NULL)
```

## Arguments

- reference, hypothesis:

  Boundary sequences of the same length: strings of `"0"` and `"1"`, or
  vectors of 0 and 1 (or `TRUE` and `FALSE`), as
  [`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md)
  returns.

- k:

  The window, a whole number from 1 to the sequence length. `NULL` takes
  the default above, which needs at least one reference boundary.

## Value

One number from 0 to 1, with the window used as attribute `k`.

## Details

These are the definitions of NLTK's `pk()` and `windowdiff()`, with the
same windows and the same default `k`, `round(L / (2 * boundaries))`,
rounded half to even as Python rounds. That is NLTK's approximation of
half the mean reference segment length. Half the mean length itself, as
Beeferman et al. define `k`, is `(L + 1) / (2 * (boundaries + 1))`,
since `L` positions describe `L + 1` units in `boundaries + 1` segments.
For `"0100"` the default is 2: the reference has 5 units in 2 segments,
a mean length of 2.5, and half of that, 1.25, would round to 1. Give `k`
to use that figure.

The default `k` matches NLTK's except in one case: when every position
of the reference is a boundary, `round(L / (2 * L))` is `round(0.5)`,
which is 0. NLTK then uses a window of 0 positions and returns 0 for any
hypothesis; this function raises `k` to 1. With that exception, and
whenever `k` is given, values agree with NLTK's on the same strings.

They measure whether chunk edges fall where topics change. A chunker
held to a token cap much smaller than the topics has to cut inside them,
and both measures count those cuts as errors; that is a cost of the size
as much as of the segmenter, so compare segmenters at one size.

## References

Beeferman, D., Berger, A. and Lafferty, J. (1999). Statistical models
for text segmentation. *Machine Learning* 34, 177-210.

Pevzner, L. and Hearst, M. A. (2002). A critique and improvement of an
evaluation metric for text segmentation. *Computational Linguistics*
28(1), 19-36.

## See also

[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)

Other segmentation functions:
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md),
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md),
[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
gr_seg_pk("000100000010", "000010000100", k = 3)
#> [1] 0.3
#> attr(,"k")
#> [1] 3
gr_seg_windowdiff("000100000010", "000010000100", k = 3)
#> [1] 0.3
#> attr(,"k")
#> [1] 3
# A window where the hypothesis has one boundary and the reference two is
# an error for WindowDiff only.
gr_seg_pk("0110", "0100", k = 2)
#> [1] 0.3333333
#> attr(,"k")
#> [1] 2
gr_seg_windowdiff("0110", "0100", k = 2)
#> [1] 0.6666667
#> attr(,"k")
#> [1] 2
```
