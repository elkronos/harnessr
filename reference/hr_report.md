# Report a benchmark with intervals

Turns the scored rows of an
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
into accuracy with intervals that respect clustering, paired differences
between arms, stability across runs, pass^k, cost, the cost-accuracy
frontier, failure counts and variance components. Only rows with
`reportable = TRUE` are used, so the dev split never enters a report,
and items with no label are left out.

## Usage

``` r
hr_report(
  bench,
  contrasts = NULL,
  B = 2000,
  conf = 0.95,
  k = c(1, 3, 5),
  seed = 1,
  method = c("auto", "bootstrap", "cluster_t", "bayes", "exact"),
  confirmatory = FALSE,
  registration = NULL
)

# S3 method for class 'hr_bench_report'
print(x, digits = 3, ...)

# S3 method for class 'hr_bench_report'
as_json(x, pretty = TRUE, ...)
```

## Arguments

- bench:

  An
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  result, or a data frame with at least the columns `cluster`, `item`,
  `arm`, `run` and `correct`. Optional columns (`reportable`, `outcome`,
  `failure_kind`, `usd`, `usd_provenance`, `tokens_in`, `tokens_out`)
  are used when present. Every arm must have every run on every item,
  and an item is scored on every run or on none.

- contrasts:

  Pairs of arms to compare: a two-column character matrix of arm names,
  each row giving first minus second. `NULL` compares every pair, in
  benchmark order.

- B:

  Number of cluster bootstrap resamples, at least 100.

- conf:

  Confidence level of every interval.

- k:

  The values of k for pass^k.

- seed:

  Seed of the private random stream the resamples are drawn from; the
  caller's random state is left as it was.

- method:

  `"auto"`, `"bootstrap"`, `"cluster_t"`, `"bayes"` or `"exact"`, as
  above.

- confirmatory:

  `TRUE` for a confirmatory report, which raises the default `B` to 5000
  and refuses dev-split rows. Left unset, it is `TRUE` when
  `registration` holds a confirmatory contrast.

- registration:

  An
  [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  result for the reference this benchmark scored, or `NULL`.

- x:

  An `hr_bench_report`.

- digits:

  Digits to print.

- ...:

  Ignored by [`print()`](https://rdrr.io/r/base/print.html); passed on
  by
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md).

- pretty:

  Whether to indent the JSON.

## Value

An object of class `hr_bench_report`, a list with

- `method`, `method_reason`, `descriptive`:

  The interval method used for accuracy, why it was chosen, and whether
  the report is descriptive only.

- `n_items`, `n_clusters`, `runs`, `arms`, `conf`, `B`, `seed`,
  `confirmatory`:

  The design and settings.

- `accuracy`:

  Per arm: `estimate`, `lower`, `upper`, `method`
  (`"studentised_cluster_bootstrap"`, `"logit_cluster_robust_t"`,
  `"korn_graubard_clopper_pearson"`, `"beta_binomial_bayes"` or
  `"descriptive"`), and the rank interval `rank_lower`, `rank_upper`.

- `bayes`:

  Per arm, in the Bayesian regime: posterior mean and median of mu and
  posterior mean of rho.

- `contrasts`:

  Per contrast: `arm1`, `arm2`, `estimate` (arm1 minus arm2), `lower`,
  `upper`, `method` (`"cluster_robust_t"`, or `"tango_items"` when the
  cluster variance is 0).

- `simultaneous`:

  Every pairwise difference with simultaneous `lower` and `upper`
  bounds, `method` (`"max_t_cluster_robust"`, or `"tango_items"` when
  the cluster variance is 0) and the max-t `critical` value (`NA` on
  `"tango_items"` rows, which do not use it).

- `stability`:

  Per arm: `flip_rate`, `tara`, `run_sd`.

- `pass_k`:

  Per arm and k: `pass_k` with `lower` and `upper`.

- `cost`:

  Per arm: `usd_per_item`, `usd_per_correct`, `tokens_per_item`,
  `tokens_per_correct`, each with `_lower` and `_upper`,
  `usd_estimated_share` and `estimated_flag`.

- `frontier`:

  Per arm: `usd_per_item`, `accuracy`, `on_frontier`, `frontier_share`.

- `failures`:

  Per arm: counts by failure kind, `accuracy` and
  `accuracy_without_parse_refusal`.

- `variance`:

  `within`, `between`, `within_share` overall and per arm, and
  `recommend_runs`.

- `ni`:

  With a registration, per registered contrast: `new`, `reference`,
  `label`, `margin`, `estimate`, the one-sided `lower` bound at the
  one-sided `level` it was tested at, `accuracy_holds`, `cost_test`,
  `cost_diff`, `cost_upper`, `cost_holds`, `verdict`, `mdd_design`,
  `mdd_achieved`, and Tango's `tango_lower` and `tango_upper` with
  `tango_agrees` (whether it reaches the same accuracy conclusion), the
  effective number of pairs `n_eff` it rests on, and `p_value`, the
  smallest one-sided level at which the contrast passes, found by
  bisection. The search stops at 1e-6, and for a contrast with
  `cost_test = TRUE` at 1 / (B + 1), the smallest level the B bootstrap
  resamples of the cost bound resolve (1 / 2001, about 5.0e-4, at B =
  2000); a value at that floor means at most the floor. `NULL` without
  one.

- `registration`:

  The registration's hash, time and reference hash, or `NULL`.

- `notes`:

  What the reader should know.

## Details

**Accuracy.** For each arm, the mean correctness over runs within each
item, then the mean over items.

**Intervals.** With `method = "auto"` the method follows the size of the
benchmark. Both rest on the cluster sums of item accuracy: accuracy is
the ratio estimator r = sum_c S_c / sum_c n_c, with S_c the summed item
accuracy and n_c the items of cluster c, and its cluster-robust
(linearised) variance is V = C / (C - 1) \* sum_c (S_c - r n_c)^2 / N^2,
with the small-sample factor C / (C - 1) for C clusters and N items
(Cochran 1977, chapter 6; Cameron and Miller 2015).

- At least 300 items and at least 30 clusters (`method = "bootstrap"`):
  a studentised (bootstrap-t) cluster bootstrap (Efron and Tibshirani
  1993, chapter 12; Davison and Hinkley 1997, chapters 2 and 5). Each of
  the `B` resamples draws whole clusters with replacement, with all
  their items, runs and arms, and gives t\* = (r\* - r) / se\*, with
  se\* the linearised standard error of the resample. The interval is
  \[r - q_hi se, r - q_lo se\], with q_lo and q_hi the (1 - conf) / 2
  and (1 + conf) / 2 quantiles of t\* and se = sqrt(V), cut to \[0, 1\].
  Studentising corrects the skew of a proportion near a bound, where the
  BCa interval this replaces undercovered (93.5% at a true accuracy of
  0.75 in the coverage simulation of `dev/sim-coverage.R`, 386 items in
  40 clusters); the studentised interval covered 95.5% and 95.0% there.

- Below either threshold (`method = "cluster_t"`): a cluster-robust t
  interval on the logit scale, logit(r) plus and minus t\_(C - 1, (1 +
  conf) / 2) x sqrt(V) / (r (1 - r)), mapped back to (0, 1) (the delta
  method on the logit scale, Agresti 2013; t quantiles with C - 1
  degrees of freedom for few clusters, Cameron and Miller 2015). In the
  coverage simulation (50 items in 10 clusters, 2000 replicates) it
  covered 95.7% and 95.8%, and 95.2% and 95.8% over 6000 further
  replicates: slightly conservative, as a t interval is when cluster
  means are bounded.

- Where those intervals are not defined, because accuracy is 0 or 1 or
  every cluster has the same accuracy (V = 0), the arm gets the
  Korn-Graubard interval below, one-sided from the bound at 0 or 1 at
  level `conf`, and its method column and a note say so.

- `method = "exact"` selects instead a Clopper-Pearson interval on the
  effective number of items computed from cluster totals of item
  accuracy, with Korn and Graubard's (1998) degrees-of-freedom
  adjustment. Items, not runs, are the trials, since runs of one item
  mostly agree. It is conservative: 98.4% to 98.8% coverage in the small
  simulated design.

- `method = "bayes"` selects a Bayesian beta-binomial model with a
  cluster random effect (Bowyer et al. 2025). Cluster c has m_c scored
  runs over its items, x_c of them correct. Its accuracy is Beta with
  mean mu and intra-cluster correlation rho, so alpha = mu (1 - rho) /
  rho and beta = (1 - mu) (1 - rho) / rho, and its runs are binomial
  given it. The priors on mu and rho are flat (uniform on 0 to 1), the
  posterior is computed on a grid, and the interval is the equal-tailed
  credible interval of mu, one-sided from the bound when accuracy is 0
  or 1. It is not the default: in the small simulated design it covered
  96.5% to 96.6% and its misses fell mostly below the truth (2.9% to
  3.2% below, 0.2% to 0.5% above). The prior on rho drives this: the
  flat prior keeps much of its mass on strong clustering (posterior mean
  of rho 0.23), which widens the interval and spreads mu toward 0.5. In
  a check of 600 replicates, a Beta(1, 10) prior on rho balanced the
  misses but undercovered (91.7% to 92.0%), and a prior uniform on
  log((1 - rho) / rho) covered 94.5% to 94.8% with misses still lopsided
  (3.2% to 3.5% below, 2.0% above); counting items instead of runs as
  trials made it more conservative (98.0% to 98.2% over 2000
  replicates), not less lopsided. A prior chosen to hit 95% in one
  design would not carry to others, so the model is kept as it was, as
  an option, and a note gives its calibration when it is used. Note that
  mu is the mean of cluster accuracies, each cluster weighted alike,
  while the estimate printed beside it weights clusters by their items.

No interval treats items or runs as independent trials (the Wald
interval on n items). `method = "bootstrap"` or `"cluster_t"` forces
that method at any size, with a note when the bootstrap is used below
the thresholds, where it is unstable.

**Paired differences.** For each contrast, accuracy of the first arm
minus the second, item by item, so each difference is paired. The mean
paired difference is the ratio estimator of the cluster sums of item
differences, and its interval is the cluster-robust t interval d plus
and minus t\_(C - 1, (1 + conf) / 2) x sqrt(V_d), with V_d the
linearised variance above applied to the differences, whatever the
method for accuracy (Cameron and Miller 2015), cut to \[-1, 1\] as the
accuracy intervals are cut to \[0, 1\] (with few clusters the t quantile
can reach past either end). It covered 94.7% (40 clusters) and 95.7% (10
clusters) in the coverage simulation, where the BCa cluster bootstrap it
replaces covered 92.9% and 89.2%. When every cluster gives the same mean
difference per item, V_d is 0 and the t interval is not defined. That is
a property of the items, not evidence that the difference is known, so
the interval then takes the items, not the clusters, as the sampling
units: Tango's (1998) score interval for paired proportions with the
discordant shares q10 and q01 described under non-inferiority below, on
n_eff = I x (z\_(1 - a) / t\_(C - 1, 1 - a))^2 pairs for one-sided level
a = (1 - conf) / 2, the I items scaled for the C - 1 degrees of freedom
as Korn and Graubard's effective size is. Its `method` is
`"tango_items"`, and a note says so.

**Rankings.** No leaderboard by point estimate: arms are listed in the
order of the benchmark. Simultaneous intervals over all pairwise
differences use the single-step max-t method (Hothorn, Bretz and
Westfall 2008) on the same cluster-robust t statistics: the critical
value is the `conf` quantile of the largest absolute value of a
multivariate t with C - 1 degrees of freedom and the correlation matrix
of the linearised covariance of the differences, from 100000 draws of
the private random stream. With one pair it is the t quantile of the
paired interval. A pair whose V_d is 0 gets the Tango interval above at
the Bonferroni level a = (1 - conf) / (2 x number of pairs), and the
max-t critical value over the other pairs is then taken at 1 - (1 -
conf) x (pairs with V_d \> 0) / (number of pairs), so the error rates of
the two parts add up to at most 1 - conf over the whole family. With 3
pairs of which 1 has V_d = 0 and conf = 0.95, the max-t part runs at 1 -
0.05 x 2 / 3, about 0.967. These intervals are cut to \[-1, 1\] too.
Rank intervals are the `(1 - conf) / 2` and `(1 + conf) / 2` quantiles
of each arm's rank over the cluster bootstrap resamples (rank 1 is the
most accurate).

**Stability** (Atil et al. 2025): the flip rate is the share of items
whose correctness differs across runs; TARa is the share of items whose
scored output (`outcome`, or the failure kind when there is none) is the
same on every run; the run-level SD is the standard deviation over runs
of each run's accuracy. Agreement of one arm with itself is stability,
not accuracy.

**Reliability**: pass^k (Yao et al. 2024), the chance that k runs drawn
without replacement from an item's runs are all correct, estimated
without bias as the mean over items of choose(c_i, k) / choose(R, k),
with c_i the item's correct runs out of R. Values of `k` above the
number of runs are left out. An item must be scored on every run or on
none, so R is the same for every item.

**Cost** (Kapoor et al. 2024): dollars and tokens (in plus out) per
item, the mean over runs and then items, and per correct item, the total
over runs divided by the correct runs. An arm whose dollars rest on
estimated token counts for more than 5% of its spend is flagged.

**Frontier**: the Pareto set on dollars per item and accuracy, and for
each arm the share of bootstrap resamples in which it is on the
frontier. The share is an extension of Kapoor et al., not a published
standard.

**Failures**: counts by failure kind. Every failure counts as wrong in
the accuracy above; a sensitivity line gives accuracy with parse
failures and refusals left out instead.

**Variance components**, on the probability scale. With p_ia the
accuracy of item i under arm a over runs, the within-item run variance
is the mean of p_ia (1 - p_ia) over item-arm cells, and the between-item
variance is the variance of p_ia over items, averaged over arms. When
the within share exceeds 10%, runs = 10 is recommended.

**Non-inferiority.** With a `registration` from
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
each registered contrast is tested. The verdict holds only if (1) the
one-sided lower bound of the accuracy difference (new minus reference)
is above -margin and (2), when the contrast has `cost_test = TRUE`, the
one-sided upper bound of the paired difference in dollars per item is
below 0. The accuracy bound is the cluster-robust t bound of the paired
differences above, taken one-sided: d - t\_(C - 1, 1 - level) x
sqrt(V_d), or, when V_d is 0, the lower end of the Tango interval with
items as pairs above at one-sided `level`. At a one-sided level of 0.025
that is the 97.5% bound, the lower end of the 95% contrast interval, so
the verdict and the printed interval agree. The cost bound is the BCa
cluster bootstrap of the cost intervals. Each contrast's p-value is the
smallest one-sided level at which both conditions hold (an
intersection-union test, so each condition runs at that full level). The
confirmatory contrasts are tested with Holm's (1979) step-down procedure
at the registration's alpha: in order of their p-values, the j-th of k
is tested at alpha / (k - j + 1), and the first that fails stops the
procedure. Exploratory contrasts are tested at alpha alone. Beside every
verdict the report gives the design MDD the contrast was registered
against and the achieved MDD, (t\_(C - 1, 1 - alpha') + t\_(C - 1,
power)) x SE, with SE = sqrt(V_d) the linearised standard error of the
paired difference (the
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
formula with p_disc / n_eff taken from the data) and alpha' = alpha /
(number of confirmatory contrasts), or alpha for an exploratory one; it
is `NA` when V_d is 0, since the data then give no variance to base it
on. A verdict that passed its registered test is shown as passed even
when the achieved MDD exceeds the margin; a note says so. As a
cross-check, Tango's (1998) score interval for paired proportions is
computed on effective counts. The discordant shares are the means over
items of the chance that a run of the new arm is right and a run of the
reference wrong (q10), and the reverse (q01). The effective number of
pairs is (q10 + q01 - estimate^2) / SE^2, the size of a simple paired
sample with the linearised variance V_d (the effective size of Korn and
Graubard 1998, applied to the paired difference), at most the number of
items (runs of one item mostly agree, so they are not independent
pairs); the counts are q10 and q01 times it. Tango's interval is
reported at the level the contrast was tested at, beside whether it
reaches the same accuracy conclusion, and is not used in the verdict.

A registration, or `confirmatory = TRUE`, makes the report evidence: a
`bench` with any row outside the test and final splits (dev, exploratory
or calibration) or marked not reportable is then refused with an error
of class `hr_dev_not_evidence`. The `bench` must carry the hash of the
reference the registration names, as an
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
result does (error class `hr_registration_mismatch`), and a registration
changed after it was made is refused (class `hr_registration_changed`).

Below 5 runs the report is descriptive only: point estimates without
intervals, resamples or rank intervals. Cost and pass^k intervals (BCa),
rank intervals and the frontier share come from the cluster bootstrap in
both regimes; below the thresholds the report says to read them as
rough.

## References

Atil, B. et al. (2025). Non-determinism of "deterministic" LLM settings.
arXiv:2408.04667.

Agresti, A. (2013). *Categorical Data Analysis*, 3rd edition. Wiley.

Bowyer, S. et al. (2025). Position: Don't use the CLT in LLM evals with
fewer than a few hundred datapoints. *ICML 2025*.

Cameron, A. C. and Miller, D. L. (2015). A practitioner's guide to
cluster-robust inference. *Journal of Human Resources* 50(2), 317-372.

Cochran, W. G. (1977). *Sampling Techniques*, 3rd edition. Wiley.

Davison, A. C. and Hinkley, D. V. (1997). *Bootstrap Methods and their
Application*. Cambridge University Press.

Efron, B. (1987). Better bootstrap confidence intervals. *Journal of the
American Statistical Association* 82(397), 171-185.

Efron, B. and Tibshirani, R. J. (1993). *An Introduction to the
Bootstrap*. Chapman and Hall.

Hothorn, T., Bretz, F. and Westfall, P. (2008). Simultaneous inference
in general parametric models. *Biometrical Journal* 50(3), 346-363.

Kapoor, S., Stroebl, B., Siegel, Z. S., Nadgir, N. and Narayanan, A.
(2024). arXiv:2407.01502.

Korn, E. L. and Graubard, B. I. (1998). Confidence intervals for
proportions with small expected number of positive counts estimated from
survey data. *Survey Methodology* 24(2), 193-201.

Holm, S. (1979). A simple sequentially rejective multiple test
procedure. *Scandinavian Journal of Statistics* 6(2), 65-70.

Miller, E. (2024). Adding error bars to evals: a statistical approach to
language model evaluations. arXiv:2411.00640.

Tango, T. (1998). Equivalence test and confidence interval for the
difference in proportions for the paired-sample design. *Statistics in
Medicine* 17(8), 891-908.

Yao, S., Shinn, N., Razavi, P. and Narasimhan, K. (2024). tau-bench.
arXiv:2406.12045.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md),
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
# 12 documents with 3 questions each, two arms, 5 runs.
set.seed(2)
grid <- expand.grid(run = 1:5, arm = c("short", "long"), item = 1:36,
                    stringsAsFactors = FALSE)
grid$cluster <- paste0("doc", (grid$item - 1) %/% 3 + 1)
grid$item <- paste0("q", grid$item)
grid$correct <- runif(nrow(grid)) < ifelse(grid$arm == "long", 0.8, 0.7)
grid$usd <- ifelse(grid$arm == "long", 0.004, 0.001)
rpt <- hr_report(grid, B = 500)
rpt
#> <hr_bench_report> 2 arm(s), 36 item(s) in 12 cluster(s), 5 run(s)
#> Intervals: cluster-robust t on the logit scale, C - 1 df at 95% (36 items in 12 clusters fall short of 300 items and 30 clusters).
#> 
#> Accuracy (arms in benchmark order, not ranked):
#>  arm   accuracy interval       rank_interval
#>  short 0.644    [0.585, 0.700] 2-2          
#>  long  0.811    [0.744, 0.864] 1-1          
#> 
#> Paired differences (first minus second):
#>  contrast     difference interval         simultaneous    
#>  short - long -0.167     [-0.256, -0.077] [-0.256, -0.077]
#> 
#> Stability across runs:
#>  arm   flip_rate TARa  run_sd
#>  short 0.889     0.111 0.053 
#>  long  0.667     0.333 0.089 
#> 
#> Reliability:
#>  arm   pass^1 pass^3 pass^5
#>  short 0.644  0.253  0.111 
#>  long  0.811  0.528  0.333 
#> 
#> Cost:
#>  arm   usd_per_item usd_per_correct interval             tokens_per_item
#>  short 0.001        0.001552        [0.0014, 0.001651]   -              
#>  long  0.004        0.004932        [0.004615, 0.005217] -              
#>  estimated on_frontier frontier_share
#>  -         yes         1.000         
#>  -         yes         1.000         
#> 
#> Failures (all counted wrong):
#>  arm   wrong without_parse_refusal
#>  short 64    0.644                
#>  long  34    0.811                
#> 
#> Variance on the probability scale: within-item runs 0.158, between items 0.033, within share 0.825.
#> Note: Run-to-run variance is 83% of the total, above 10%: use runs = 10. 
#> Note: Cost, pass^k, frontier share and rank intervals come from the cluster bootstrap, which can undercover below 300 items or 30 clusters; read them as rough. 
#> Note: The frontier share (how often an arm is on the cost-accuracy frontier over resamples) is an extension, not a published standard. 
rpt$accuracy
#>     arm  estimate     lower     upper                 method rank_lower
#> 1 short 0.6444444 0.5845116 0.7001668 logit_cluster_robust_t          2
#> 2  long 0.8111111 0.7444507 0.8635697 logit_cluster_robust_t          1
#>   rank_upper
#> 1          2
#> 2          1
```
