# Confidence intervals for binomial proportions

Intervals for `x` successes out of `n` trials, vectorised over both.

## Usage

``` r
hr_prop_ci(
  x,
  n,
  method = c("wilson", "clopper_pearson", "jeffreys"),
  side = c("two", "lower", "upper"),
  conf = 0.95
)
```

## Arguments

- x:

  Number of successes: whole numbers from 0 to `n`.

- n:

  Number of trials: whole numbers. Recycled against `x`. A row with
  `n = 0` has `NA` for the estimate and both bounds.

- method:

  One of `"wilson"`, `"clopper_pearson"` or `"jeffreys"`.

- side:

  `"two"` for a two-sided interval, `"lower"` for a lower bound only,
  `"upper"` for an upper bound only.

- conf:

  Confidence level, strictly between 0 and 1.

## Value

A data frame with one row per element: `x`, `n`, `est` (x / n), `lower`,
`upper`, `method`, `side` and `conf`.

## Details

Which method to use:

- **Wilson** (the default) for descriptive rates: a sensitivity, a share
  of records kept, an error rate reported alongside an estimate. It is
  close to nominal coverage on average and does not collapse to a point
  at 0 or n successes.

- **Clopper-Pearson** for any "at least" or "at most" guarantee, such as
  "recall is at least 0.95" or "the error rate is at most 2%". It never
  covers less than `conf`, where Wilson can dip below it when x or n - x
  is 0 to 3 (Brown, Cai and DasGupta 2001).

- **Jeffreys**, the equal-tailed interval of the Beta(x + 1/2, n - x +
  1/2) posterior, as a middle ground when a one-number comparison with
  other Bayesian summaries is wanted.

Wilson here has no continuity correction, so the two-sided interval is
the one `prop.test(x, n, correct = FALSE)` reports, with the lower bound
exactly 0 at `x = 0` and the upper exactly 1 at `x = n`. The
Clopper-Pearson interval is the one `binom.test(x, n)` reports. The
Jeffreys bounds are `qbeta(a, x + 0.5, n - x + 0.5)` and
`qbeta(1 - a, x + 0.5, n - x + 0.5)`, with the lower bound set to 0 at
`x = 0` and the upper to 1 at `x = n`.

A one-sided bound spends the whole of `1 - conf` on its side:
`side = "lower"` gives `[lower, 1]` and `side = "upper"` gives
`[0, upper]`, as `binom.test(..., alternative = "greater")` and `"less"`
do.

## References

Brown, L. D., Cai, T. T. and DasGupta, A. (2001). Interval estimation
for a binomial proportion. *Statistical Science* 16(2), 101-133.

Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or
fiducial limits illustrated in the case of the binomial. *Biometrika*
26(4), 404-413.

Wilson, E. B. (1927). Probable inference, the law of succession, and
statistical inference. *Journal of the American Statistical Association*
22(158), 209-212.

## See also

Other statistics:
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md),
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md),
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md),
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md)

## Examples

``` r
# A descriptive rate: 46 of 50 eligible records were kept.
hr_prop_ci(46, 50)
#>    x  n  est     lower     upper method side conf
#> 1 46 50 0.92 0.8116175 0.9684505 wilson  two 0.95

# A guarantee: is recall at least 0.90? Read the one-sided exact bound.
hr_prop_ci(46, 50, method = "clopper_pearson", side = "lower")
#>    x  n  est     lower upper          method  side conf
#> 1 46 50 0.92 0.8262088     1 clopper_pearson lower 0.95

# Vectorised: three rates at once.
hr_prop_ci(c(0, 5, 20), c(20, 20, 20), method = "jeffreys")
#>    x  n  est     lower     upper   method side conf
#> 1  0 20 0.00 0.0000000 0.1166390 jeffreys  two 0.95
#> 2  5 20 0.25 0.1023985 0.4641946 jeffreys  two 0.95
#> 3 20 20 1.00 0.8833610 1.0000000 jeffreys  two 0.95
```
