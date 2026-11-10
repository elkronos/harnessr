# Calibrate a self-signal against graded items

Measures how well a signal predicts that an item came out right, on a
graded set, and fits a map from the signal to a probability. The result
is a calibration record: it says how good the signal is, and it is the
only thing
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
and
[`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
accept as grounds for letting a signal gate an action. A new record is
always `advisory`.

## Usage

``` r
hr_calibrate_signal(
  signal,
  graded,
  key,
  method = c("platt", "isotonic", "none"),
  bins = 10L,
  split = 0.5,
  seed,
  B = 2000L
)
```

## Arguments

- signal:

  The signal's name, as recorded by
  [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md).

- graded:

  The graded set, a data frame; see "The graded set".

- key:

  A named list with the fields the record is valid for: `served_model`
  (the model the provider said answered, not the one asked for),
  `version` (the model version or snapshot), `task`, `format`,
  `prompt_hash` (of the prompt or template), `effort`, `module` (the
  reader or stage) and `contract_version`. Each is one string; `NA` is
  allowed except for `served_model`. A missing `contract_version` is
  filled with the running package's contract version.

- method:

  `"platt"`, `"isotonic"` or `"none"`.

- bins:

  Number of equal-mass bins for the ECE and the decomposition, held
  between 5 and 10.

- split:

  Share of each cluster's items that goes to the fit half, strictly
  between 0 and 1.

- seed:

  Seed for the split and the bootstrap. Required, so the same graded set
  always gives the same record. The caller's random state is left as it
  was.

- B:

  Number of bootstrap resamples; 0 for no intervals.

## Value

An `hr_calibration`: a list with `signal`, `key`, `method`, `n_items`,
`n_errors`, `n_unanswerable`, `n_clusters`, `accuracy` (on the
calibration half), `metrics` (a data frame of `metric`, `estimate`,
`lower`, `upper`), `selective_risk`, `decomposition`, `map` (the fitted
map), `grid` (the default thresholds for
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
from the fit half), `data` (the graded items with their half and mapped
`p`), `sample_design`, `bins` (the number of ECE bins formed), `B`,
`seed`, `created_utc`, `created_by`, `status` (`"advisory"` or
`"gating"`), `reasons`, `notes` (remarks that do not stop a record from
gating, such as a small cluster count behind the intervals) and `gate`
(`NULL` until
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
sets it). It has [`print()`](https://rdrr.io/r/base/print.html) and
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
methods.

## The graded set

One row per item, with these columns:

- `score` (or `value`):

  The signal: a number, or a logical read as 1 and 0. Higher means more
  confident the item is right. The `score` column of
  [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  is in this form.

- `correct`:

  Whether the item came out right (logical, or 1 and 0). For an action
  such as "stop reading" or "accept", right means acting on the item was
  right.

- `answerable`:

  Whether the item has an answer in its source. The set must include
  unanswerable items: a signal calibrated only on answerable questions
  has never been asked about the case where saying "I can answer" is
  most often wrong.

- `cluster`:

  Optional: the document (or other unit) the item comes from. Without it
  each item is its own cluster.

- `item_id`, `signal`:

  Optional. When `signal` is present only the rows for this signal are
  used.

- `split`:

  Optional, as
  [`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
  and
  [`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
  give it. When present only the rows in the `calibration` split are
  used: dev items were tuned on, and test items must stay unseen until
  they are scored. The rows left out are counted in `notes` and in a
  message, and a set with no calibration row stops with
  `hr_bad_calibration`.

Columns are matched by their exact names, so a column such as
`cluster_size` is never read as `cluster`.

## How it is computed

Within each cluster, a share `split` of the items goes to the fit half
and the rest to the calibration half (a cluster's odd item goes to
either side at random). The map is fitted on the fit half. Every metric,
and the threshold search in
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
uses the calibration half, so the map is never judged on the items it
was fitted to.

- **Platt scaling** (Platt 1999) fits `p = plogis(a + b * score)` by
  logistic regression on the targets `(N+ + 1) / (N+ + 2)` for a right
  item and `1 / (N- + 2)` for a wrong one, which keeps the fit finite
  when the halves separate. It is the default and the only fitted map
  allowed below 1000 graded items.

- **Isotonic regression** (pool adjacent violators, weighted by the
  number of items at each score) needs at least 1000 graded items. The
  count is of the whole graded set before the split, so the map itself
  is fitted on about `split` of them (500 at the minimum with the
  default `split`). Between fitted scores it interpolates linearly;
  beyond them it holds the end values.

- **`"none"`** takes the score as the probability, so it must lie in
  \[0, 1\]. It is the comparison that shows what fitting a map gained.

On the calibration half, with `p` the mapped probability and `y` 1 for a
right item. The Brier score, its decomposition and the ECE judge `p`;
AUROC2 and AURC judge the signal's own score, so they describe the
signal and not the map. A Platt slope is free to be negative, and a map
fitted to a signal that points the wrong way would otherwise rank well
and hide it.

- **Brier score** `mean((p - y)^2)`, with its decomposition over bins of
  `p` (Murphy 1973; the two within-bin terms of Stephenson et al. 2008):
  `brier = reliability - resolution + uncertainty + within_var - 2 * within_cov`.
  `reliability` is the weighted mean of `(mean p - mean y)^2` per bin,
  `resolution` the weighted mean of `(mean y in bin - mean y)^2`,
  `uncertainty` is `mean(y) * (1 - mean(y))`, and `within_var` and
  `within_cov` are the weighted within-bin variance of `p` and
  covariance of `p` and `y`. When `p` takes no more distinct values than
  `bins`, each value is its own bin, both within-bin terms are 0, and
  this is Murphy's three-part decomposition exactly.

- **AUROC2**, the type-2 area under the ROC curve: the probability that
  a right item scores above a wrong one, ties counting half (the
  Mann-Whitney statistic), on the raw score. It measures ranking alone,
  and is below 0.5 for a signal that is higher when the item is wrong.

- **AURC**, the area under the risk-coverage curve (Geifman and El-Yaniv
  2017): items are accepted from the most to the least confident, and
  the error rate among the first `k` is averaged over `k = 1, ..., n`,
  in the order of the raw score. Tied scores enter together, each
  position taking the expected error rate under a random order within
  the tie. `selective_risk` gives the same error rate at 50, 80 and 90
  percent coverage. Lower is better.

- **ECE**, the debiased L2 calibration error over equal-mass bins
  (Kumar, Liang and Ma 2019):
  `sqrt(max(0, sum_k w_k * ((mean p - mean y)^2 - mean y * (1 - mean y) / (n_k - 1))))`.
  The plug-in error is biased upward by the noise in each bin's mean,
  and the subtracted term removes that bias, so a perfectly calibrated
  signal scores near 0 rather than at the noise floor. `bins` is held
  between 5 and 10. A calibration half of fewer than 10 items is lowered
  to fewer bins so each bin has at least two items. The ECE and the
  decomposition use the same bins, and items with the same `p` always
  share one: when `p` takes no more distinct values than `bins`, each
  value is its own bin, and otherwise an item's bin follows the average
  rank of its `p`. So the ECE does not depend on the order of the rows,
  and a signal with two values (a logical one, or any map of it) is
  measured over 2 bins. The record's `bins` is the number of bins
  formed, and `reasons` says so when it is below 5.

Intervals are 95 percent percentile intervals from a bootstrap that
resamples whole clusters of the calibration half, `B` times. With fewer
than two clusters in that half, or when every resample gives the same
value, there is nothing to resample and the bounds are `NA`. With fewer
than 20 clusters percentile intervals cover poorly, and `notes` says how
many clusters they rest on.

A record is `advisory` until
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
finds a threshold that passes. It also stays advisory when the graded
set has fewer than 100 wrong items, when the fitted map does not
increase with the signal (a Platt slope of 0 or less, or a flat isotonic
fit), or when the ECE used fewer than 5 bins, as it does for a signal
with fewer than 5 distinct values, such as a logical one; `reasons` says
why.

## References

Geifman, Y. and El-Yaniv, R. (2017). Selective classification for deep
neural networks. *Advances in Neural Information Processing Systems* 30.

Kumar, A., Liang, P. and Ma, T. (2019). Verified uncertainty
calibration. *Advances in Neural Information Processing Systems* 32.

Murphy, A. H. (1973). A new vector partition of the probability score.
*Journal of Applied Meteorology* 12(4), 595-600.

Platt, J. (1999). Probabilistic outputs for support vector machines and
comparisons to regularized likelihood methods. In *Advances in Large
Margin Classifiers*, 61-74.

Stephenson, D. B., Coelho, C. A. S. and Jolliffe, I. T. (2008). Two
extra components in the Brier score decomposition. *Weather and
Forecasting* 23(4), 752-757.

## See also

[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
[`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md),
[`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)

Other signals:
[`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md),
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md),
[`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

## Examples

``` r
# A simulated graded set: 40 documents, 10 questions each, a quarter of
# them unanswerable, and a signal that is informative but overconfident.
set.seed(1)
n <- 400
answerable <- rep(c(TRUE, TRUE, TRUE, FALSE), length.out = n)
truth <- stats::runif(n, 0.2, 0.95) * answerable
graded <- data.frame(
  cluster = rep(sprintf("doc%02d", 1:40), each = 10),
  score = pmin(1, truth + 0.15),
  correct = stats::runif(n) < truth,
  answerable = answerable)
key <- list(served_model = "mock-model-2026-01-01", version = "2026-01-01",
            task = "qa", format = "pdf", prompt_hash = "a1b2c3", effort = "low",
            module = "iterative")
cal <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, seed = 7, B = 200)
cal
#> <hr_calibration> gr.iterative.can_answer: advisory
#>   400 items (235 wrong, 100 unanswerable) in 40 clusters; map: platt
#>   key: served_model=mock-model-2026-01-01, version=2026-01-01, task=qa, format=pdf, prompt_hash=a1b2c3, effort=low, module=iterative, contract_version=0.1
#>   calibration half: 200 items, accuracy 0.410
#>   brier   0.1598  [0.1305, 0.1920]
#>   auroc2  0.8393  [0.7791, 0.8918]
#>   aurc    0.3514  [0.2717, 0.4426]
#>   ece     0.0552  [0.0000, 0.1964]
#>   advisory: no gate threshold has been set

# The same split with no map shows what Platt scaling bought.
raw <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, method = "none",
                           seed = 7, B = 0)
raw$metrics[raw$metrics$metric %in% c("brier", "ece"), ]
#>   metric  estimate lower upper
#> 1  brier 0.1843548    NA    NA
#> 4    ece 0.1690354    NA    NA
```
