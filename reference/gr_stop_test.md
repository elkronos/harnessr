# Hypergeometric stopping test for prioritised screening

After each screened record, tests the null hypothesis that recall is
still below `target`, given what has been screened and how many records
are left. Screening may stop at the first record where the p-value falls
below `alpha`. This is the test of Callaghan and Muller-Hansen (2020),
computed with
[`stats::phyper()`](https://rdrr.io/r/stats/Hypergeometric.html). It is
for prioritised screening only (records read in ranked order, as
[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
simulates); a one-pass screen that reads every record has no stopping
point to choose.

## Usage

``` r
gr_stop_test(screened_order, target = 0.95, alpha = 0.05, n_total = NULL)

# S3 method for class 'gr_stop_test'
print(x, ...)
```

## Arguments

- screened_order:

  The relevance of the records in the order they were screened: logical,
  or numeric 0 and 1 (1 = relevant). Records not yet screened may follow
  as `NA` at the end, and count toward `n_total`. An
  [`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
  result is also accepted, and its whole simulated order is tested.

- target:

  Recall level, strictly between 0 and 1.

- alpha:

  Significance level, strictly between 0 and 1.

- n_total:

  Total number of records, screened or not. Defaults to the length of
  `screened_order`.

- x:

  A `gr_stop_test`.

- ...:

  Not used.

## Value

A `gr_stop_test`, a list with:

- `steps`: one row per screened record, with `n_screened`,
  `relevant_found`, `p_value` and `reject` (p below `alpha`).

- `stop_at`: the first `n_screened` with `reject`, or `NA` when the test
  never rejects.

- `relevant_at_stop` and `recall_at_stop`: the relevant records found by
  then and, when every record's relevance is known, the recall reached
  there.

- `work_saved`: 1 - stop_at / n_total.

- `target`, `alpha`, `n_total` and `n_screened`.

## Details

**The test.** Let N be the number of records, t the number screened so
far and r the relevant records among them. Recall r / R is below
`target` only if the total number of relevant records R is at least K =
floor(r / target) + 1. Take the last m screened records as if they were
a random draw from the N - t + m records that were unscreened before
them, with k relevant among them. Under the null, at least K - (r - k)
of those N - t + m records are relevant, and the chance of seeing k or
fewer in the draw is at most the hypergeometric probability

p(m) = P(X \<= k), X ~ Hypergeometric(N - t + m records, K - (r - k)
relevant, m drawn),

which is `phyper(k, K - r + k, N - t + m - (K - r + k), m)`. The p-value
after t records is the smallest p(m) over m = 1, ..., t, as in the
authors' treatment of already screened records as a sample. When fewer
than K - r records are left unscreened, the null cannot hold and p is 0.

**Caveats.** The ranked records are not a random draw. A working ranker
reads the most likely relevant of the remaining records first, so the
window is richer in relevant records than a random draw from them would
be. That makes the test cautious when the ranker works and unreliable
when it ranks worse than chance. The minimum over m and the look after
every record are not corrected for repeated testing, as in the original
method. No stopping rule is standard; report the rule and its settings
with the result.

## References

Callaghan, M. W. and Muller-Hansen, F. (2020). Statistical stopping
criteria for automated screening in systematic reviews. *Systematic
Reviews* 9, 273.

## See also

[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
for a simulated screening order.

## Examples

``` r
# 1,000 records: 100 relevant found first, then 400 irrelevant in a row.
seen <- c(rep(1, 100), rep(0, 400), rep(NA, 500))
st <- gr_stop_test(seen)
st
#> <gr_stop_test> recall target 0.95, alpha 0.05, 500 of 1000 records screened
#>   safe to stop after 453 records (100 relevant found), work saved 0.547
# At 500 screened, the last 400 records hold no relevant ones; under the
# null at least 6 relevant records were among the 900 left before them.
prod((500 - 0:5) / (900 - 0:5))
#> [1] 0.02900956
st$steps$p_value[500]
#> [1] 0.02900956
```
