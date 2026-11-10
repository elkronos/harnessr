# Check an arm for drift against a frozen benchmark

Reruns `arm` live on the items of a frozen
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
and compares the live runs with the frozen ones item by item. The live
rerun is itself an
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
of the arm, with the frozen benchmark's split and fresh draws, and is
returned in `$live`; it can be reported with
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
or kept as the next frozen sample.

## Usage

``` r
hr_drift_check(
  frozen,
  arm,
  runs = 5,
  alpha = 0.05,
  alert = NULL,
  client,
  reference,
  scorer = hr_scorer_exact(),
  governor = NULL,
  B = 2000,
  seed = NULL
)

# S3 method for class 'hr_drift_check'
print(x, digits = 3, ...)
```

## Arguments

- frozen:

  An `hr_bench` from
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  holding at least 5 runs of `arm`: the frozen sample.

- arm:

  The
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
  to rerun, the same arm (by hash) that the frozen benchmark ran.

- runs:

  The number of live runs, a whole number, at least 2, so that the live
  runs have replicate flips of their own. As many as the frozen runs
  compares like with like.

- alpha:

  The level of each test, in (0, 0.5): two-sided for (a), one-sided for
  (b).

- alert:

  The accuracy change that must not go unnoticed, a proportion in (0,
  1), or `NULL` for no alert.

- client:

  The client the live runs call; see
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md).

- reference:

  The
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  the frozen benchmark scored.

- scorer:

  The scorer the frozen benchmark used; checked by name.

- governor:

  An
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  the live rerun is held to, or `NULL` to take the limits from
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md).

- B:

  The number of cluster resamples, at least 100.

- seed:

  The seed of the live runs' private random stream and of the resamples.
  `NULL` takes the frozen benchmark's seed plus 1, so an arm that
  samples makes fresh draws rather than replaying the frozen ones.

- x:

  An `hr_drift_check`.

- digits:

  Digits to print.

- ...:

  Ignored.

## Value

An object of class `hr_drift_check`, a list with

- `arm`, `arm_hash`, `reference_hash`, `frozen_runs`, `live_runs`,
  `n_items`, `n_clusters`, `alpha`, `alert`, `B`, `seed`:

  What was compared and how.

- `items`:

  One row per labelled item: `cluster`, `item`, `frozen_accuracy` (p_i),
  `live_accuracy` (q_i), `change` (`"lost"` when most frozen runs were
  right and most live runs wrong, `"gained"` the reverse, `"worse"` or
  `"better"` for a smaller move, `"same"` when p_i = q_i),
  `frozen_outcome` and `live_outcome` (the most common scored output, or
  the failure kind in angle brackets), and `replicate_flip` (f_i),
  `live_flip` (h_i), `cross_flip` (g_i) and `excess` (e_i). `change`
  compares shares of runs only: on an item whose frozen or live runs
  disagree among themselves (`replicate_flip` or `live_flip` above 0), a
  move can be ordinary run-to-run variation, and only test (b) says
  whether the moves as a whole exceed it. An item that was stable before
  (`replicate_flip` 0) and moved is a real flip.

- `accuracy`:

  Test (a): `frozen`, `live`, `change`, `lower`, `upper`, `bca` (`FALSE`
  when the percentile interval stood in), `p_value`, `detected`.

- `mcnemar`:

  The cross-check: `statistic`, `df`, `p_value`, `detected`, and
  `agrees`, whether it reaches the same decision as test (a).

- `instability`:

  Test (b): `replicate_flip`, `live_flip`, `cross_flip`, `excess`,
  `lower` (the one-sided bound), `bca`, `p_value`, `detected`.

- `replicate_pairs`, `cross_pairs`:

  The flip rate over items of each pair of frozen runs, and of each
  frozen run with each live run.

- `drift`:

  Whether either test rejected.

- `alert_crossed`:

  Whether the interval of test (a) lies wholly beyond the alert, a
  change at least that large; `NA` without `alert` or without an
  interval.

- `alert_not_ruled_out`:

  Whether the interval of test (a) reaches beyond the alert, so a change
  that large cannot be ruled out; `NA` as for `alert_crossed`.

- `live`:

  The live `hr_bench`.

- `notes`:

  What the reader should know about the result.

## Details

Two tests are run, with `alpha` and `alert` fixed in the call before
anything is rerun, so neither can be chosen after the result is seen.

**(a) Accuracy change.** For item i, p_i is the share of the frozen runs
that were correct and q_i the share of the live runs. The change is
mean(q_i - p_i) over items, live minus frozen. Its two-sided interval at
level 1 - `alpha` is a BCa cluster bootstrap (Efron 1987): each of the
`B` resamples draws whole clusters with replacement, with all their
items and runs, so the frozen and live values of an item stay paired.
Accuracy changed when the interval excludes 0.

As a cross-check the clustered McNemar test of Obuchowski (1998) is run
on the same item accuracies. With x_1k and x_2k the sums of p_i and q_i
over the items of cluster k, n_k its items, N the items and K the
clusters, the estimates are P_j = sum_k x_jk / N and

X^2 = (P_1 - P_2)^2 / (V_1 + V_2 - 2 V_12),

V_j = K / ((K - 1) N^2) sum_k (x_jk - n_k P_j)^2, V_12 = K / ((K - 1)
N^2) sum_k (x_1k - n_k P_1) (x_2k - n_k P_2),

referred to a chi-squared distribution on 1 degree of freedom. An
unclustered McNemar test is not offered: it treats items from one
document as independent and overstates the evidence.

**(b) Excess instability.** A model that answers differently from run to
run flips items between any two runs, frozen or live. So the flips
between frozen and live runs are compared with the flips among replicate
runs. With R_f frozen runs of which k_i were correct on item i, and R_l
live runs of which m_i were,

f_i = 2 k_i (R_f - k_i) / (R_f (R_f - 1))

is the share of pairs of frozen runs that disagree on item i,

h_i = 2 m_i (R_l - m_i) / (R_l (R_l - 1))

the same share among the live runs, and

g_i = (k_i (R_l - m_i) + (R_f - k_i) m_i) / (R_f R_l)

the share of frozen-live pairs that disagree. With frozen accuracy p and
live accuracy q on the item, f_i, h_i and g_i estimate 2 p (1 - p), 2 q
(1 - q) and p (1 - q) + q (1 - p) without bias, so the item's excess

e_i = g_i - (f_i + h_i) / 2

estimates (p - q)^2. It is 0 in expectation when nothing changed and
above 0 for any move, in either direction and from any starting
accuracy, so it sees losses and gains that cancel in the accuracy change
and noisy items that turn deterministic. The live replicate flips h_i
enter beside the frozen ones because g_i - f_i alone estimates (q - p)
(1 - 2 p), which is 0 for an item at p = 0.5 whatever q is and below 0
when an item settles toward 0 or 1. The test is one-sided: instability
is in excess when the lower BCa bound of mean(e_i) at one-sided level
`alpha`, from the same cluster resamples, is above 0. The flip rate of
every pair of frozen runs and of every frozen-live pair is returned too,
so the frozen replicate distribution can be read directly.

**P-values** of the bootstrap tests are the smallest level at which the
test rejects, found by bisection over \[1 / (B + 1), 0.5\]; 1 when it
does not reject even at 0.5.

**Drift and alert.** `drift` is `TRUE` when either test rejects. Each
test runs at `alpha`, so the chance that `drift` is `TRUE` with no
change at all can reach 2 `alpha`; pass `alpha / 2` to hold it at
`alpha`. `alert`, when given, is the accuracy change, in points as a
proportion, that may not go unnoticed, and it is read two ways. The
alert is crossed (`alert_crossed`) when the whole interval of test (a)
lies beyond -`alert` or `alert`: a change at least that large is shown.
A change of `alert` is not ruled out (`alert_not_ruled_out`) when the
interval reaches beyond -`alert` or `alert`. A small or noisy frozen
sample often cannot rule it out even with no change at all, which says
the sample cannot vouch for the arm, not that the arm moved. Size the
sample with
[`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md).

**What is refused.** Fewer than 5 frozen runs of the arm (class
`hr_drift_few_runs`): with fewer, the replicate flips are too few pairs
to compare against. An arm whose hash is not the frozen arm's, a
reference or scorer other than the frozen benchmark's (class
`hr_drift_mismatch`): those would compare two configurations, which is
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)'s
job. A live run any of whose requests a cache or a recording answered
(class `hr_drift_not_live`): that is the frozen reply again, not the
model today. Turn cache reads off for the drift check.

The cluster bootstrap can undercover below 300 items or 30 clusters, and
the result notes it. With one cluster there is nothing to resample, and
both tests are left `NA`.

## References

Efron, B. (1987). Better bootstrap confidence intervals. *Journal of the
American Statistical Association* 82(397), 171-185.

Obuchowski, N. A. (1998). On the comparison of correlated proportions
for clustered data. *Statistics in Medicine* 17(13), 1495-1507.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
ref <- hr_reference(
  items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji",
               q5 = "Chile", q6 = "Laos"),
  labels = c("Paris", "Lima", "N'Djamena", "Suva", "Santiago", "Vientiane"),
  cluster = c("a", "a", "b", "b", "c", "c"), split = "test")
capitals <- c(France = "Paris", Peru = "Lima", Chad = "N'Djamena", Fiji = "Suva",
              Chile = "Santiago", Laos = "Vientiane")
answer <- function(capitals) {
  gr_mock_client(function(messages, params) {
    capitals[[sub("Capital of ", "", messages[[1]]$content)]]
  })
}
ask <- hr_arm("ask", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
frozen <- hr_benchmark(ask, ref, runs = 5, client = answer(capitals))

# Months later the model gets two capitals wrong.
today <- capitals
today[c("Chad", "Laos")] <- c("Ndjamena", "Luang Prabang")
drift <- hr_drift_check(frozen, ask, client = answer(today), reference = ref,
                        alert = 0.1, B = 500)
drift
#> <hr_drift_check> arm 'ask': 5 frozen run(s) vs 5 live, 6 item(s) in 3 cluster(s); alpha 0.05
#> (a) Accuracy: frozen 1.000, live 0.667, change -0.333 [-0.500, -0.167], p 0.0122; changed: yes
#>     Clustered McNemar (Obuchowski): X^2 4.000, p 0.0455; agrees: yes
#> (b) Flips: between frozen runs 0.000, between live runs 0.000, frozen vs live 0.333, excess 0.333 (one-sided lower 0.000), p 0.333; in excess: no
#>     Frozen pairs flip 0.000 to 0.000; frozen-live pairs 0.333 to 0.333
#> Drift: yes; alert at 0.100: crossed
#> Items: lost 2, gained 0, worse 0, better 0, same 4 
#>  item cluster change frozen live  frozen_outcome live_outcome 
#>  q3   b       lost   1.000  0.000 n'djamena      ndjamena     
#>  q6   c       lost   1.000  0.000 vientiane      luang prabang
#> Note: 6 items in 3 clusters fall short of 300 items and 30 clusters, where the cluster bootstrap can undercover; read the tests as approximate. 
drift$items[drift$items$change != "same", ]
#>   cluster item frozen_accuracy live_accuracy change frozen_outcome
#> 3       b   q3               1             0   lost      n'djamena
#> 6       c   q6               1             0   lost      vientiane
#>    live_outcome replicate_flip live_flip cross_flip excess
#> 3      ndjamena              0         0          1      1
#> 6 luang prabang              0         0          1      1
```
