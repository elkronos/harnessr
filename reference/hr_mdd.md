# The minimum detectable difference of a paired, clustered design

`hr_mdd()` gives the smallest paired accuracy difference a benchmark of
`n_items` items can detect, and `hr_n_needed()` the number of items
needed to detect a given one. Both use the closed form for a paired
comparison of two proportions with a true difference of 0:

## Usage

``` r
hr_mdd(
  n_items,
  n_clusters = NULL,
  m = NULL,
  icc = NULL,
  p_disc = NULL,
  cv = 0,
  power = 0.8,
  alpha = 0.025,
  n_contrasts = 1,
  holm = TRUE
)

hr_n_needed(
  delta,
  m = NULL,
  icc = NULL,
  p_disc = NULL,
  cv = 0,
  power = 0.8,
  alpha = 0.025,
  n_contrasts = 1,
  holm = TRUE,
  true_diff = 0
)

# S3 method for class 'hr_mdd'
print(x, ...)

# S3 method for class 'hr_n_needed'
print(x, ...)
```

## Arguments

- n_items:

  The number of scored items.

- n_clusters:

  The number of clusters the items fall in, or `NULL`. With `m` left
  `NULL`, m = n_items / n_clusters.

- m:

  The mean number of items per cluster, or `NULL`. With both `m` and
  `n_clusters` left `NULL` the items are taken as independent (m = 1).

- icc:

  ICC_D, the intra-cluster correlation of the paired item difference, in
  \[0, 1). Required when m \> 1; take it from a pilot on the dev split.

- p_disc:

  The share of items on which the two arms disagree, in (0, 1\].
  Required.

- cv:

  The coefficient of variation of cluster sizes, 0 for equal clusters.

- power:

  The power, in (0, 1).

- alpha:

  The one-sided significance level, in (0, 0.5). 0.025 matches a
  one-sided 97.5% bound.

- n_contrasts:

  The number of confirmatory contrasts in the Holm family.

- holm:

  Whether to adjust alpha for Holm over `n_contrasts`.

- delta:

  The difference to detect, as a proportion (0.08 for 8 points).

- true_diff:

  The true difference assumed for a non-inferiority test, at most 0: the
  test must then tell -delta from `true_diff`, so the gap is delta +
  true_diff.

- x:

  An `hr_mdd` or `hr_n_needed`.

- ...:

  Ignored.

## Value

`hr_mdd()` returns an object of class `hr_mdd`, a list with `mdd` and
the design it rests on: `n_items`, `n_clusters`, `m`, `m_adj` (the size
after the cv correction), `icc`, `cv`, `de`, `n_eff`, `p_disc`, `power`,
`alpha`, `alpha_adj`, `n_contrasts`, `holm`, `df` (C - 1), the t
quantiles `t_alpha` and `t_power` the MDD uses, and the normal quantiles
`z_alpha` and `z_power` beside them. `hr_n_needed()` returns an object
of class `hr_n_needed` with `n_eff`, `n_items` (n_eff x DE) and
`n_clusters` (n_items / m, `NA` when `m` is not given), unrounded,
beside the same design values, `df` (n_items / m - 1) and the quantiles.
[`print()`](https://rdrr.io/r/base/print.html) rounds them up: with `m`
given it rounds the clusters up first and prints that many clusters of m
as the items, so n_items 837.8 at m = 6 prints as 840 items in 140
clusters.

## Details

n_eff = (t\_(C - 1, 1 - alpha') + t\_(C - 1, power))^2 x p_disc /
Delta^2,

with t quantiles on C - 1 degrees of freedom for C clusters: the degrees
of freedom of the cluster-robust t bound that
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
tests non-inferiority with. p_disc is the share of items on which the
two arms disagree, so p_disc / n_eff is the variance of the mean paired
difference. Items in one cluster are not independent, so the effective
number of items is n_eff = n_items / DE with the design effect DE = 1 +
(m - 1) x ICC_D (Kish 1965), where m is the mean cluster size and ICC_D
the intra-cluster correlation of the paired item difference, not of raw
accuracy. With unequal cluster sizes of coefficient of variation `cv`, m
is replaced by (cv^2 + 1) x m (Eldridge, Ashby and Kerry 2006).
`hr_mdd()` solves for Delta:

Delta = (t\_(C - 1, 1 - alpha') + t\_(C - 1, power)) x sqrt(p_disc /
n_eff).

C is `n_clusters`, or n_items / m when only `m` is given, or n_items
when the items are independent; it must be above 1. `hr_n_needed()`
finds the number of items whose C = n_items / m satisfies the formula,
by root finding, since the quantiles depend on it.

With `holm = TRUE` and more than one contrast, alpha' = alpha /
n_contrasts, the level Holm's procedure tests its first contrast at: the
worst case, since later steps test at larger levels. With
`holm = FALSE`, alpha' = alpha.

The closed form is a first estimate. Power for a study is better planned
by simulation from a pilot fitted on the dev split. Set against the
report's cluster-robust t bound (`dev/sim-power.R`, 2000 replicates,
seed 1), the MDD at 80% power was 0.16 and 0.17 points below the
simulated one at 80 equal clusters (one and nine contrasts; simulated
power at the formula's MDD 78.55% and 78.30%) and 0.25 points above it
at 40 unequal clusters (81.60%). Normal quantiles in place of the t
quantiles were 0.26 and 0.41 points below at 80 clusters (77.20% and
76.05%) and 0.04 points below at 40 (79.85%).

## References

Eldridge, S. M., Ashby, D. and Kerry, S. (2006). Sample size for cluster
randomized trials: effect of coefficient of variation of cluster size
and analysis method. *International Journal of Epidemiology* 35(5),
1292-1300.

Kish, L. (1965). *Survey Sampling*. Wiley.

## See also

[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
# 480 scored questions in 80 documents, ICC of the paired difference 0.2,
# the arms disagreeing on 20% of items.
hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
#> <hr_mdd> 8.2 points at 80% power, one-sided alpha 0.025
#>   480 items in 80 clusters (m = 6, 6 after cv 0), ICC_D 0.2: DE 2, n_eff 240
#>   p_disc 0.2

# The same design after Holm over nine confirmatory contrasts.
hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#> <hr_mdd> 10.7 points at 80% power, one-sided alpha 0.002778 (0.025 / 9 contrasts, Holm worst case)
#>   480 items in 80 clusters (m = 6, 6 after cv 0), ICC_D 0.2: DE 2, n_eff 240
#>   p_disc 0.2

# Items and documents needed for an 8-point margin under that Holm family.
hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#> <hr_n_needed> 8.0 points at 80% power, one-sided alpha 0.002778 (0.025 / 9 contrasts, Holm worst case)
#>   n_eff 419 effective items; DE 2, so 840 items in 140 clusters of 6
```
