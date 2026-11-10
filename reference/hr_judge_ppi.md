# Judge-scored accuracy corrected with human labels

A judge's accuracy figures are biased by its own errors. Given the
judge's score on every item and human labels on a sample of them, this
returns the prediction-powered estimate of the human-scored mean
(Angelopoulos et al. 2023), through
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md):

## Usage

``` r
hr_judge_ppi(
  judge_scores,
  human_labels,
  inclusion_prob = NULL,
  conf = 0.95,
  tune = TRUE
)
```

## Arguments

- judge_scores:

  The judge's score for every item, numeric or logical (1 or `TRUE` for
  right), no `NA`.

- human_labels:

  The human score on the same scale, the same length, `NA` on the items
  no person labelled.

- inclusion_prob:

  `NULL`, or the probability with which each item was chosen for human
  labelling: one per item, or one per labelled item.

- conf:

  Confidence level.

- tune:

  Whether to tune lambda (PPI++); see
  [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md).

## Value

The one-row data frame of
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md),
with `judge_mean`, the uncorrected mean of `judge_scores`, added.

## Details

    estimate = mean(judge on unlabelled) + mean(human - judge on labelled)

with PPI++ tuning by default. When `inclusion_prob` varies, the labelled
items were drawn with unequal probabilities and the correction is
inverse-probability weighted, the design-based supervised learning form
(Egami et al. 2023):

    estimate = mean over all items of
               lambda * judge_i + R_i * (human_i - lambda * judge_i) / pi_i

with R_i = 1 for labelled items. Equal probabilities give the plain
form.

The interval is a normal approximation and needs enough labelled items
in every inclusion stratum. Small inclusion probabilities with few
labels give intervals that are too narrow: with about 150 labels drawn
at 0.05 and 0.4, a nominal 95% interval covered the true mean about 91%
of the time in simulation.

## References

Angelopoulos, A. N., Bates, S., Fannjiang, C., Jordan, M. I. and Zrnic,
T. (2023). Prediction-powered inference. *Science* 382(6671), 669-674.

Egami, N., Hinck, M., Stewart, B. M. and Wei, H. (2023). Using imperfect
surrogates for downstream inference: design-based supervised learning
for social science applications of large language models. *Advances in
Neural Information Processing Systems* 36.

## See also

[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)

Other judges:
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

## Examples

``` r
set.seed(7)
truth <- rbinom(1000, 1, 0.6)
# A lenient judge: it passes 30% of wrong answers.
judge <- ifelse(truth == 1, rbinom(1000, 1, 0.95), rbinom(1000, 1, 0.3))
human <- rep(NA, 1000)
lab <- sample(1000, 150)
human[lab] <- truth[lab]
hr_judge_ppi(judge, human)
#>    estimate         se     lower     upper   n   N    lambda method judge_mean
#> 1 0.5668593 0.03135783 0.5053991 0.6283196 150 850 0.6349485  ppi++      0.698
```
