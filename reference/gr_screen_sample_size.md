# How many records to judge by hand to show a recall target

Sizes a reference sample for
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
so that, if the sample turns up no missed eligible record, the one-sided
bound clears the target at the confidence asked for. One miss or more
widens the bound, so treat the result as the least that could be enough.

## Usage

``` r
gr_screen_sample_size(
  recall_target = 0.95,
  conf = 0.95,
  prevalence = NULL,
  frame = "all",
  max_lost = NULL,
  frame_n = NULL
)
```

## Arguments

- recall_target:

  The recall to show, strictly between 0 and 1. Used by `frame = "all"`;
  for the other frames it enters through `max_lost`.

- conf:

  Confidence level of the one-sided bound.

- prevalence:

  Expected share of eligible records among those drawn, for
  `frame = "all"`: turns the eligible records needed into records to
  draw. `NULL` leaves the record count `NA`.

- frame:

  `"all"`, `"excluded"` or `"stacked"`, as in
  [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md).

- max_lost:

  For `"excluded"` and `"stacked"`: the most eligible records the
  screener may have excluded while still meeting the target.

- frame_n:

  Number of records in the frame sampled: the excluded records for
  `"excluded"` and `"stacked"`, everything screened for `"all"`, where
  with `prevalence` it caps the draw at the whole frame.

## Value

A one-row data frame: the settings, `positives` (eligible records
needed, for `"all"`), `n` (records to draw), `n_binomial`, `n_exact`,
`rule` and `note`.

## A sample of everything screened (`frame = "all"`)

Recall is bounded from the eligible records the sample happens to
contain. With none of `k` eligible records missed, the one-sided
Clopper-Pearson lower bound on recall is alpha^(1/k), where alpha = 1 -
`conf`, so the target T is shown once

    k >= ln(alpha) / ln(T)

eligible records have been judged: 29 for T = 0.90, 59 for 0.95 and 299
for 0.99 at 95% confidence (Lewis, Yang and Frieder 2021). Divided by
the expected `prevalence` it gives the number of records to draw (59 /
0.05 = 1180). The ten eligible records 0.6.0 asked for support a lower
bound of only 0.74, even with all ten found.

## Every kept record plus a sample of the exclusions

With the kept records judged in full (`frame = "stacked"`, or
`frame = "excluded"` for the exclusions sample on its own) recall is K /
(K + M), where K is the eligible records kept and M those excluded, so a
recall target is a cap on M: with K eligible kept, recall T is met when
M is at most floor(K (1 - T) / T). Give that cap as `max_lost`, using a
pilot estimate of K, and the excluded frame's size as `frame_n`.

The exact size is the smallest n for which a frame holding `max_lost` +
1 eligible records would show none of them in a sample of n with
probability at most alpha, from the hypergeometric distribution. This is
the bound
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
reports. The binomial version, n \>= ln(alpha) / ln(1 - u) with u =
`max_lost` / `frame_n` (299 for u = 1%), is given beside it; it ignores
the finite frame and so asks for a few more records.

## A finite frame

For `frame = "all"`,
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
bounds a sample smaller than the frame with Clopper-Pearson, which
treats the frame as infinite, so the eligible records needed do not fall
with the frame's size. When the whole frame is judged, recall is known
exactly and is its own bound. So with `frame_n` given, `n` is the
binomial draw when it fits in the frame, and otherwise `frame_n` itself:
at 95% recall, 95% confidence and 5% prevalence, a frame of 500 records
holds about 25 eligible records, fewer than the 59 needed, and only
judging all 500 can show the target. `n_exact` is `NA` for
`frame = "all"`.

## References

Lewis, D. D., Yang, E. and Frieder, O. (2021). Certifying one-phase
technology-assisted reviews. *Proceedings of the 30th ACM International
Conference on Information and Knowledge Management*, 893-902.

Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or
fiducial limits illustrated in the case of the binomial. *Biometrika*
26(4), 404-413.

## See also

[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)

Other corpus functions:
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)

## Examples

``` r
# Eligible records to judge for recall of at least 95%, at 95% confidence.
gr_screen_sample_size(0.95, 0.95)
#>   frame recall_target conf prevalence max_lost frame_n positives  n n_binomial
#> 1   all          0.95 0.95         NA       NA      NA        59 NA         NA
#>   n_exact                                                   rule
#> 1      NA zero misses among the eligible: k >= ln(alpha) / ln(T)
#>                                                                          note
#> 1 Give `prevalence` to turn the eligible records needed into records to draw.

# At 5% prevalence that many eligible records means drawing about 1180.
gr_screen_sample_size(0.95, 0.95, prevalence = 0.05)
#>   frame recall_target conf prevalence max_lost frame_n positives    n
#> 1   all          0.95 0.95       0.05       NA      NA        59 1180
#>   n_binomial n_exact                                                   rule
#> 1       1180      NA zero misses among the eligible: k >= ln(alpha) / ln(T)
#>   note
#> 1 <NA>

# Every kept record judged, 285 of them eligible, and 9000 exclusions: at
# most floor(285 * 0.05 / 0.95) = 15 may have been lost.
gr_screen_sample_size(frame = "stacked", max_lost = 15, frame_n = 9000)
#>     frame recall_target conf prevalence max_lost frame_n positives    n
#> 1 stacked          0.95 0.95         NA       15    9000        NA 1536
#>   n_binomial n_exact
#> 1       1796    1536
#>                                                               rule note
#> 1 zero misses in the excluded sample: hypergeometric, finite frame <NA>
```
