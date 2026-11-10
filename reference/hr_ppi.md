# Prediction-powered inference for a mean

Estimates the mean of an outcome from many units that have only a
model's prediction and a few that also have the true value, without
inheriting the model's bias. Use it to report a judge-scored accuracy,
or any rate where a model labelled everything and people labelled a
sample.

## Usage

``` r
hr_ppi(
  yhat_unlabelled,
  yhat_labelled,
  y_labelled,
  pi = NULL,
  conf = 0.95,
  tune = TRUE
)
```

## Arguments

- yhat_unlabelled:

  Predictions on the units without a true value.

- yhat_labelled:

  Predictions on the labelled units.

- y_labelled:

  True values on the labelled units (numeric or logical).

- pi:

  Optional probability with which each labelled unit was chosen for
  labelling, in (0, 1\].

- conf:

  Confidence level.

- tune:

  Whether to tune lambda (PPI++). `FALSE` fixes it at 1.

## Value

A one-row data frame: `estimate`, `se`, `lower`, `upper`, `n`
(labelled), `N` (unlabelled), `lambda` and `method` (`"ppi"`, `"ppi++"`,
`"dsl"` or `"dsl tuned"`).

## Details

With `tune = FALSE` this is the estimator of Angelopoulos et al. (2023):

    estimate = mean(yhat_U) + mean(y_L - yhat_L)
    variance = var(yhat_U) / N + var(y_L - yhat_L) / n

where U are the `N` unlabelled units and L the `n` labelled ones. The
second term (the rectifier) removes the predictions' bias.

With `tune = TRUE` (PPI++, Angelopoulos, Duchi and Zrnic 2023) the
predictions are scaled by lambda:

    estimate = mean(y_L) + lambda * (mean(yhat_U) - mean(yhat_L))
    lambda   = cov(y_L, yhat_L) / ((1 + n / N) * var(yhat_L))

clipped to `[0, 1]`. lambda = 0 is the mean of the labelled units alone
and lambda = 1 the untuned estimator, so tuning never does worse than
either in large samples: poor predictions get little weight.

When `pi` is given and varies, the labelled units were drawn with
unequal probabilities from the whole set (U and L together, N + n
units), and the rectifier is inverse-probability weighted as in
design-based supervised learning (Egami et al. 2023). Each unit gets the
pseudo-outcome

    ytilde_i = lambda * yhat_i + R_i * (y_i - lambda * yhat_i) / pi_i

with R_i = 1 for labelled units, and the estimate is the mean of ytilde
over all N + n units with variance var(ytilde) / (N + n). Tuning chooses
the lambda in `[0, 1]` that minimises that variance. Equal `pi` gives
the unweighted form above.

The interval is normal: estimate +/- z \* se.

## References

Angelopoulos, A. N., Bates, S., Fannjiang, C., Jordan, M. I. and Zrnic,
T. (2023). Prediction-powered inference. *Science* 382(6671), 669-674.

Angelopoulos, A. N., Duchi, J. C. and Zrnic, T. (2023). PPI++: Efficient
prediction-powered inference. arXiv:2311.01453.

Egami, N., Hinck, M., Stewart, B. M. and Wei, H. (2023). Using imperfect
surrogates for downstream inference: design-based supervised learning
for social science applications of large language models. *Advances in
Neural Information Processing Systems* 36.

## See also

Other statistics:
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md),
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md),
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md),
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)

## Examples

``` r
set.seed(2)
truth <- rbinom(2100, 1, 0.3)
# A judge that is right 85% of the time.
judged <- ifelse(runif(2100) < 0.85, truth, 1 - truth)
lab <- 1:100
hr_ppi(judged[-lab], judged[lab], truth[lab])
#>   estimate         se     lower     upper   n    N  lambda method
#> 1 0.318293 0.03625286 0.2472387 0.3893473 100 2000 0.59236  ppi++
hr_ppi(judged[-lab], judged[lab], truth[lab], tune = FALSE)
#>   estimate         se     lower     upper   n    N lambda method
#> 1    0.324 0.04142234 0.2428137 0.4051863 100 2000      1    ppi
```
