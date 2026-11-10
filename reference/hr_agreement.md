# Agreement between raters, with every measure that should go with it

One call for agreement between two raters on nominal labels, or among
any number of coders at a declared level of measurement.

## Usage

``` r
hr_agreement(
  x,
  y = NULL,
  coders = NULL,
  level = c("nominal", "ordinal", "interval", "ratio"),
  positive = NULL,
  B = 2000,
  conf = 0.95,
  seed = 1
)
```

## Arguments

- x:

  Labels from the first rater, or a matrix or data frame of coders with
  `y` left `NULL`.

- y:

  Labels from the second rater, the same length as `x`. Read as the
  reference when `positive` is given. Items where either is `NA` are
  left out, and the result says how many.

- coders:

  A matrix or data frame with items in rows and coders in columns, `NA`
  for a missing label. Used in place of `x` and `y`.

- level:

  Level of measurement of the labels: `"nominal"`, `"ordinal"`,
  `"interval"` or `"ratio"`. Anything but nominal is reported as alpha.

- positive:

  For two raters, the label that counts as positive. Turns on
  sensitivity, specificity, PPV and NPV, with `y` as the reference.

- B:

  Number of bootstrap resamples for the kappa and alpha intervals. 0
  skips them.

- conf:

  Confidence level for every interval.

- seed:

  Seed for the bootstrap.

## Value

An object of class `hr_agreement`: a list with `type` (`"two_raters"` or
`"coders"`), `level`, `n` (items used), `dropped` (items left out for
missing labels), `categories`, `table` (the count table for two raters,
the coincidence matrix for coders), `stats` (a data frame with columns
`statistic`, `estimate`, `se`, `lower` and `upper`), `po`, `kappa`,
`alpha`, `paradox_flag`, `positive`, `notes`, `conf` and `bootstrap`
(`B` and `seed`). It has [`print()`](https://rdrr.io/r/base/print.html)
and
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
methods.

## Details

**Two raters** (`x` and `y`, nominal). The result holds the count table
and, from it:

- `po`, the observed agreement, with a Wilson interval;

- Cohen's kappa, its large-sample standard error (Fleiss, Cohen and
  Everitt 1969) and a percentile bootstrap interval over items;

- the prevalence index PI = (a - d) / n and bias index BI = (b - c) / n
  of Byrt, Bishop and Carlin (1993), for two categories only;

- PABAK = (k po - 1) / (k - 1) for k categories (2 po - 1 for two),
  whose interval is the Wilson interval on po mapped the same way;

- Gwet's AC1 with the variance of Gwet (2008) and a t interval on n - 1
  degrees of freedom, held to between -1 and 1;

- positive and negative specific agreement, 2a / (2a + b + c) and 2d /
  (2d + b + c), for two categories;

- when `positive` is given, `y` is read as the reference and
  sensitivity, specificity, PPV and NPV are reported with Wilson
  intervals (one category against the rest when there are more than
  two).

The categories are the labels either rater used. Factor levels that
neither rater used are left out, with a note naming them, so a spare
level does not change k (and with it PABAK and AC1) or hide PI, BI and
specific agreement. The one exception is `positive`, which stays in the
table when it is a declared level, so an all-negative 2x2 stays 2x2. A
`positive` that is neither a declared level nor a used label is an
error.

In the table rows are `x` and columns `y`. With two categories the first
is `positive` when it is given (otherwise the first level), so a is
"both positive", b "x positive only", c "y positive only" and d "both
negative".

Kappa is never reported alone. At a low prevalence it moves with the
marginals as much as with agreement, so two raters who agree on 95 of
100 items can score a kappa near zero (Feinstein and Cicchetti 1990);
AC1 has the opposite weakness, a value near 1 from shared absence. The
print method always shows the table and the full set together.

`paradox_flag` is TRUE when abs(PI) \> 0.8, or when po \>= 0.8 and kappa
\<= 0.4. Either marks a table where kappa should not be compared with a
kappa from another sample. Both thresholds are heuristics, not cited
cut-offs.

**Several coders** (a matrix or data frame in `coders`, or in `x` with
`y` left out; items in rows, coders in columns, `NA` where a coder did
not label an item), or two raters at a level other than nominal. The
result is Krippendorff's alpha from the coincidence matrix (Krippendorff
2011) with the difference function of `level`:

- nominal: 0 for equal values, 1 otherwise;

- ordinal: the squared number of values ranked between the two, counting
  each end as half, (sum of n_g from c to k - (n_c + n_k) / 2)^2;

- interval: (c - k)^2;

- ratio: ((c - k) / (c + k))^2.

Only items with at least two values are pairable. Alpha comes with a
percentile bootstrap interval over items. Below 30 pairable items, or
when every value is the same so that alpha is undefined, alpha is `NA`
and only percent agreement (the share of matching pairs, from the
coincidence matrix) is reported, with a note saying why: alpha from a
handful of items is too unstable to be read (Hayes and Krippendorff
2007).

Ordinal levels follow the factor levels when the labels are a factor,
and sorted order otherwise. When coders' factors carry different level
sets (one coder never used "mid" and its factor has only low and high),
the levels are merged keeping each coder's order, so low, high and low,
mid, high give low, mid, high. Levels that conflict, or that leave the
order of two levels open, are an error for the ordinal level. Interval
and ratio levels need numeric labels.

The bootstrap runs under `seed`, so the same data give the same interval
every time, and the caller's random state is left as it was.

## References

Byrt, T., Bishop, J. and Carlin, J. B. (1993). Bias, prevalence and
kappa. *Journal of Clinical Epidemiology* 46(5), 423-429.

Feinstein, A. R. and Cicchetti, D. V. (1990). High agreement but low
kappa: I. The problems of two paradoxes. *Journal of Clinical
Epidemiology* 43(6), 543-549.

Fleiss, J. L., Cohen, J. and Everitt, B. S. (1969). Large sample
standard errors of kappa and weighted kappa. *Psychological Bulletin*
72(5), 323-327.

Gwet, K. L. (2008). Computing inter-rater reliability and its variance
in the presence of high agreement. *British Journal of Mathematical and
Statistical Psychology* 61(1), 29-48.

Hayes, A. F. and Krippendorff, K. (2007). Answering the call for a
standard reliability measure for coding data. *Communication Methods and
Measures* 1(1), 77-89.

Krippendorff, K. (2011). Computing Krippendorff's alpha-reliability.
University of Pennsylvania, Annenberg School for Communication.

## See also

Other statistics:
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md),
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md),
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md),
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)

## Examples

``` r
# Two raters on a screening decision, the second as the reference.
screener <- rep(c("keep", "drop", "keep", "drop"), c(40, 9, 6, 45))
person <- rep(c("keep", "keep", "drop", "drop"), c(40, 9, 6, 45))
ag <- hr_agreement(screener, person, positive = "keep", B = 200)
ag
#> <hr_agreement> two raters, nominal, 100 item(s)
#> 
#> Counts (rows x, columns y):
#>       y
#> x      keep drop
#>   keep   40    6
#>   drop    9   45
#> 
#>           statistic estimate    se lower upper
#>  observed agreement    0.850    NA 0.767 0.907
#>               kappa    0.700 0.071 0.562 0.838
#>               PABAK    0.700    NA 0.534 0.814
#>                 AC1    0.701 0.071 0.559 0.842
#>    prevalence index   -0.050    NA    NA    NA
#>          bias index   -0.030    NA    NA    NA
#>  positive agreement    0.842    NA    NA    NA
#>  negative agreement    0.857    NA    NA    NA
#>         sensitivity    0.816    NA 0.686 0.900
#>         specificity    0.882    NA 0.766 0.945
#>                 PPV    0.870    NA 0.743 0.939
#>                 NPV    0.833    NA 0.713 0.910
#> 
#> Intervals at 95%; bootstrap B = 200, seed 1.
#> Positive label: keep; y is the reference.

# Three coders, one item each left blank, ordinal labels.
set.seed(4)
truth <- sample(1:4, 40, replace = TRUE)
codes <- sapply(1:3, function(j) pmin(4, pmax(1, truth + sample(-1:1, 40, TRUE,
                                                              c(0.1, 0.8, 0.1)))))
codes[cbind(1:3, 1:3)] <- NA
hr_agreement(coders = codes, level = "ordinal", B = 200)
#> <hr_agreement> 3 coders, ordinal, 40 pairable item(s)
#> 
#> Coincidence matrix:
#>    1  2  3  4
#> 1 25  3  1  0
#> 2  3  7 10  0
#> 3  1 10 23  4
#> 4  0  0  4 26
#> 
#>             statistic estimate se lower upper
#>     percent agreement    0.692 NA    NA    NA
#>  Krippendorff's alpha    0.858 NA 0.739 0.924
#> 
#> Intervals at 95%; bootstrap B = 200, seed 1.
```
