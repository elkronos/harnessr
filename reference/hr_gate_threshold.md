# Choose a gate threshold by Learn-then-Test

Finds the loosest threshold on a calibrated signal at which acting on
the items whose probability `p` is at or above it keeps a risk below
`alpha`, with confidence `1 - delta`, on the calibration half of the
record.

## Usage

``` r
hr_gate_threshold(
  cal,
  action,
  risk = c("error_among_accepted", "miss_rate"),
  alpha,
  delta = 0.05,
  grid = NULL
)
```

## Arguments

- cal:

  An `hr_calibration` from
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md).

- action:

  The action the signal would gate, such as `"stop"`, `"skip"`,
  `"accept"` or `"exclude"`. Recorded, and matched against the action of
  an
  [`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md).

- risk:

  `"error_among_accepted"` or `"miss_rate"`.

- alpha:

  The tolerated risk, strictly between 0 and 1. There is no default: it
  is a decision about the task, made before the data are seen.

- delta:

  The chance the guarantee fails, strictly between 0 and 1.

- grid:

  Thresholds on the probability scale, in any order; they are tested
  from the highest down. `NULL` uses 20 quantiles of `p` on the fit half
  (`cal$grid`).

## Value

`cal` with `$gate` set: a list of `action`, `risk`, `alpha`, `delta`,
`n_min`, `threshold` (`NA` when none passed), `n`, `k`, `deff` (the
design effect), `n_eff` (`n / deff`), `ucb` and `coverage` (the share of
the calibration half acted on) at that threshold, `status` (`"passed"`,
`"none passed"` or `"too few items"`) and `path`, a data frame of every
threshold with its `n`, `k`, `deff`, `ucb`, whether it was `tested` and
whether it `passed`. `$status` and `$reasons` are updated.

## The procedure

Learn-then-Test (Angelopoulos et al. 2021) with fixed-sequence testing:
each threshold `t` is a hypothesis "the risk at `t` exceeds `alpha`",
rejected when the one-sided Clopper-Pearson upper bound
`ucb = qbeta(1 - delta, k + 1, n - k)` is at most `alpha` (1 when
`k = n`), taken on the effective sample described under "Clustered
items". Thresholds are tested from strict to loose; the sequence stops
at the first that fails, and the loosest one that passed is kept.
Because the order is fixed before the labels are looked at, no
correction for testing many thresholds is needed.

The risk sets `n` and `k`:

- `"error_among_accepted"`:

  `n` is the number of items acted on at `t` (those with `p >= t`) and
  `k` the number of those that were wrong. For actions such as stopping,
  skipping or accepting.

- `"miss_rate"`:

  `n` is the number of items on which acting is wrong (for screening,
  the eligible records) and `k` the number of those acted on at `t`. The
  denominator does not depend on `t`. For screening exclusions.

## Clustered items

The Clopper-Pearson bound treats items as independent. Items from one
document are not: their errors go together, and
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
puts part of every document in the calibration half. With `n` and `k`
taken at face value the guarantee then fails for new documents (with 30
documents of 20 items, a true error rate of 0.12 and an intraclass
correlation of 0.3, a gate at `alpha = 0.10` and `delta = 0.05` passed
in 8.7 percent of draws, not at most 5 percent). So the bound is taken
on an effective sample:
`ucb = qbeta(1 - delta, k / deff + 1, (n - k) / deff)`, where `deff`,
the design effect at that threshold, is the cluster (linearisation)
variance of `k / n` over the calibration half's `cluster`s divided by
the variance the same formula gives with each item its own cluster, and
is never below 1 (Kish 1965). In the draws above the gate then passed in
2.4 percent of them. Items with no cluster, or in clusters of one, give
`deff = 1` and the exact Clopper-Pearson bound. So do a single cluster
and a threshold with no error (or no right item) among its units, where
there is no spread to measure; the bound is then only as good as the
assumption that the items are independent. With few clusters `deff` is
itself noisy and the guarantee is approximate.

Even with no errors the bound reaches `alpha` only from
`n_min = ceiling(log(delta) / log(1 - alpha))` items: 59 at
`alpha = 0.05` and 299 at `alpha = 0.01`, with `delta = 0.05`. For
`"error_among_accepted"` the sequence therefore starts at the strictest
threshold that acts on at least `n_min` items; that count uses only the
scores, not the labels, so starting there keeps the guarantee. For
`"miss_rate"` the set needs at least `n_min` items on which acting is
wrong.

The record becomes `"gating"` only when a threshold passes and none of
the reasons
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
gave holds: the graded set had at least 100 wrong items, the fitted map
increases with the signal and the ECE used at least 5 bins. Otherwise it
stays `"advisory"` and `reasons` says why.

## References

Angelopoulos, A. N., Bates, S., Candes, E. J., Jordan, M. I. and Lei, L.
(2021). Learn then test: calibrating predictive algorithms to achieve
risk control. arXiv:2110.01052.

Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or
fiducial limits illustrated in the case of the binomial. *Biometrika*
26(4), 404-413.

Kish, L. (1965). *Survey Sampling*. New York: Wiley.

## See also

[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

Other signals:
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md),
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md),
[`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

## Examples

``` r
set.seed(2)
n <- 2000
answerable <- stats::runif(n) < 0.8
score <- stats::runif(n)
graded <- data.frame(cluster = rep(1:200, each = 10), score = score,
                     correct = stats::runif(n) < ifelse(answerable, score, score / 4),
                     answerable = answerable)
key <- list(served_model = "m-2026", version = "2026", task = "qa", format = "pdf",
            prompt_hash = "abc", effort = NA, module = "iterative")
cal <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, seed = 3, B = 0)
cal <- hr_gate_threshold(cal, "stop", alpha = 0.1)
cal$gate[c("threshold", "n", "k", "ucb", "status")]
#> $threshold
#> [1] NA
#> 
#> $n
#> [1] NA
#> 
#> $k
#> [1] NA
#> 
#> $ucb
#> [1] NA
#> 
#> $status
#> [1] "none passed"
#> 
```
