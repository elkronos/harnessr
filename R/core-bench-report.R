# core-bench-report.R: intervals, stability, reliability and cost for a
# benchmark.
#
# One rule runs through this file: items in the same cluster (the same
# document, the same task) are not independent, and runs of an arm on one
# item are not independent of each other either. So every interval resamples
# or models whole clusters, with all their items, runs and arms together, and
# the runs of an item are averaged before anything is compared. Runs are never
# resampled apart from their items: arms derived from shared draws keep them.

#' Report a benchmark with intervals
#'
#' Turns the scored rows of an [hr_benchmark()] into accuracy with intervals
#' that respect clustering, paired differences between arms, stability across
#' runs, pass^k, cost, the cost-accuracy frontier, failure counts and
#' variance components. Only rows with `reportable = TRUE` are used, so the
#' dev split never enters a report, and items with no label are left out.
#'
#' **Accuracy.** For each arm, the mean correctness over runs within each
#' item, then the mean over items.
#'
#' **Intervals.** With `method = "auto"` the method follows the size of the
#' benchmark. Both rest on the cluster sums of item accuracy: accuracy is the
#' ratio estimator r = sum_c S_c / sum_c n_c, with S_c the summed item
#' accuracy and n_c the items of cluster c, and its cluster-robust
#' (linearised) variance is V = C / (C - 1) * sum_c (S_c - r n_c)^2 / N^2,
#' with the small-sample factor C / (C - 1) for C clusters and N items
#' (Cochran 1977, chapter 6; Cameron and Miller 2015).
#' * At least 300 items and at least 30 clusters (`method = "bootstrap"`): a
#'   studentised (bootstrap-t) cluster bootstrap (Efron and Tibshirani 1993,
#'   chapter 12; Davison and Hinkley 1997, chapters 2 and 5). Each of the `B`
#'   resamples draws whole clusters with replacement, with all their items,
#'   runs and arms, and gives t* = (r* - r) / se*, with se* the linearised
#'   standard error of the resample. The interval is
#'   \[r - q_hi se, r - q_lo se\], with q_lo and q_hi the (1 - conf) / 2 and
#'   (1 + conf) / 2 quantiles of t* and se = sqrt(V), cut to \[0, 1\].
#'   Studentising corrects the skew of a proportion near a bound, where the
#'   BCa interval this replaces undercovered (93.5% at a true accuracy of
#'   0.75 in the coverage simulation of `dev/sim-coverage.R`, 386 items in 40
#'   clusters); the studentised interval covered 95.5% and 95.0% there.
#' * Below either threshold (`method = "cluster_t"`): a cluster-robust t
#'   interval on the logit scale, logit(r) plus and minus
#'   t_(C - 1, (1 + conf) / 2) x sqrt(V) / (r (1 - r)), mapped back to
#'   (0, 1) (the delta method on the logit scale, Agresti 2013; t quantiles
#'   with C - 1 degrees of freedom for few clusters, Cameron and Miller
#'   2015). In the coverage simulation (50 items in 10 clusters, 2000
#'   replicates) it covered 95.7% and 95.8%, and 95.2% and 95.8% over 6000
#'   further replicates: slightly conservative, as a t interval is when
#'   cluster means are bounded.
#' * Where those intervals are not defined, because accuracy is 0 or 1 or
#'   every cluster has the same accuracy (V = 0), the arm gets the
#'   Korn-Graubard interval below, one-sided from the bound at 0 or 1 at
#'   level `conf`, and its method column and a note say so.
#' * `method = "exact"` selects instead a Clopper-Pearson interval on the
#'   effective number of items computed from cluster totals of item
#'   accuracy, with Korn and Graubard's (1998) degrees-of-freedom adjustment.
#'   Items, not runs, are the trials, since runs of one item mostly agree.
#'   It is conservative: 98.4% to 98.8% coverage in the small simulated
#'   design.
#' * `method = "bayes"` selects a Bayesian beta-binomial model with a
#'   cluster random effect (Bowyer et al. 2025). Cluster c has m_c scored
#'   runs over its items, x_c of them correct. Its accuracy is Beta with
#'   mean mu and intra-cluster correlation rho, so
#'   alpha = mu (1 - rho) / rho and beta = (1 - mu) (1 - rho) / rho, and its
#'   runs are binomial given it. The priors on mu and rho are flat (uniform
#'   on 0 to 1), the posterior is computed on a grid, and the interval is
#'   the equal-tailed credible interval of mu, one-sided from the bound when
#'   accuracy is 0 or 1. It is not the default: in the small simulated design
#'   it covered 96.5% to 96.6% and its misses fell mostly below the truth
#'   (2.9% to 3.2% below, 0.2% to 0.5% above). The prior on rho drives
#'   this: the flat prior keeps much of its mass on strong clustering
#'   (posterior mean of rho 0.23), which widens the interval and spreads mu
#'   toward 0.5. In a check of 600 replicates, a Beta(1, 10) prior on rho
#'   balanced the misses but undercovered (91.7% to 92.0%), and a prior
#'   uniform on log((1 - rho) / rho) covered 94.5% to 94.8% with misses still
#'   lopsided (3.2% to 3.5% below, 2.0% above); counting items instead of
#'   runs as trials made it more conservative (98.0% to 98.2% over 2000
#'   replicates), not less lopsided. A prior chosen to hit 95% in one design
#'   would not carry to others, so the model is kept as it was, as an
#'   option, and a note gives its calibration when it is used. Note that mu
#'   is the mean of cluster accuracies, each cluster weighted alike, while
#'   the estimate printed beside it weights clusters by their items.
#'
#' No interval treats items or runs as independent trials (the Wald interval
#' on n items). `method = "bootstrap"` or `"cluster_t"` forces that method at
#' any size, with a note when the bootstrap is used below the thresholds,
#' where it is unstable.
#'
#' **Paired differences.** For each contrast, accuracy of the first arm minus
#' the second, item by item, so each difference is paired. The mean paired
#' difference is the ratio estimator of the cluster sums of item
#' differences, and its interval is the cluster-robust t interval
#' d plus and minus t_(C - 1, (1 + conf) / 2) x sqrt(V_d), with V_d the
#' linearised variance above applied to the differences, whatever the method
#' for accuracy (Cameron and Miller 2015), cut to \[-1, 1\] as the accuracy
#' intervals are cut to \[0, 1\] (with few clusters the t quantile can reach
#' past either end). It covered 94.7% (40 clusters) and
#' 95.7% (10 clusters) in the coverage simulation, where the BCa cluster
#' bootstrap it replaces covered 92.9% and 89.2%. When every cluster gives
#' the same mean difference per item, V_d is 0 and the t interval is not
#' defined. That is a property of the items, not evidence that the
#' difference is known, so the interval then takes the items, not the
#' clusters, as the sampling units: Tango's (1998) score interval for paired
#' proportions with the discordant shares q10 and q01 described under
#' non-inferiority below, on n_eff = I x (z_(1 - a) / t_(C - 1, 1 - a))^2
#' pairs for one-sided level a = (1 - conf) / 2, the I items scaled for the
#' C - 1 degrees of freedom as Korn and Graubard's effective size is. Its
#' `method` is `"tango_items"`, and a note says so.
#'
#' **Rankings.** No leaderboard by point estimate: arms are listed in the
#' order of the benchmark. Simultaneous intervals over all pairwise
#' differences use the single-step max-t method (Hothorn, Bretz and Westfall
#' 2008) on the same cluster-robust t statistics: the critical value is the
#' `conf` quantile of the largest absolute value of a multivariate t with
#' C - 1 degrees of freedom and the correlation matrix of the linearised
#' covariance of the differences, from 100000 draws of the private random
#' stream. With one pair it is the t quantile of the paired interval. A
#' pair whose V_d is 0 gets the Tango interval above at the Bonferroni level
#' a = (1 - conf) / (2 x number of pairs), and the max-t critical value over
#' the other pairs is then taken at 1 - (1 - conf) x (pairs with V_d > 0) /
#' (number of pairs), so the error rates of the two parts add up to at most
#' 1 - conf over the whole family. With 3 pairs of which 1 has V_d = 0 and
#' conf = 0.95, the max-t part runs at 1 - 0.05 x 2 / 3, about 0.967. These
#' intervals are cut to \[-1, 1\] too.
#' Rank intervals are the `(1 - conf) / 2` and `(1 + conf) / 2` quantiles of
#' each arm's rank over the cluster bootstrap resamples (rank 1 is the most
#' accurate).
#'
#' **Stability** (Atil et al. 2025): the flip rate is the share of items
#' whose correctness differs across runs; TARa is the share of items whose
#' scored output (`outcome`, or the failure kind when there is none) is the
#' same on every run; the run-level SD is the standard deviation over runs
#' of each run's accuracy. Agreement of one arm with itself is stability, not
#' accuracy.
#'
#' **Reliability**: pass^k (Yao et al. 2024), the chance that k runs drawn
#' without replacement from an item's runs are all correct, estimated without
#' bias as the mean over items of choose(c_i, k) / choose(R, k), with c_i the
#' item's correct runs out of R. Values of `k` above the number of runs are
#' left out. An item must be scored on every run or on none, so R is the
#' same for every item.
#'
#' **Cost** (Kapoor et al. 2024): dollars and tokens (in plus out) per item,
#' the mean over runs and then items, and per correct item, the total over
#' runs divided by the correct runs. An arm whose dollars rest on estimated
#' token counts for more than 5% of its spend is flagged.
#'
#' **Frontier**: the Pareto set on dollars per item and accuracy, and for each
#' arm the share of bootstrap resamples in which it is on the frontier. The
#' share is an extension of Kapoor et al., not a published standard.
#'
#' **Failures**: counts by failure kind. Every failure counts as wrong in the
#' accuracy above; a sensitivity line gives accuracy with parse failures and
#' refusals left out instead.
#'
#' **Variance components**, on the probability scale. With p_ia the accuracy
#' of item i under arm a over runs, the within-item run variance is the mean
#' of p_ia (1 - p_ia) over item-arm cells, and the between-item variance is
#' the variance of p_ia over items, averaged over arms. When the within share
#' exceeds 10%, runs = 10 is recommended.
#'
#' **Non-inferiority.** With a `registration` from [hr_register_contrasts()],
#' each registered contrast is tested. The verdict holds only if (1) the
#' one-sided lower bound of the accuracy difference (new minus reference) is
#' above -margin and (2), when the contrast has `cost_test = TRUE`, the
#' one-sided upper bound of the paired difference in dollars per item is
#' below 0. The accuracy bound is the cluster-robust t bound of the paired
#' differences above, taken one-sided: d - t_(C - 1, 1 - level) x sqrt(V_d),
#' or, when V_d is 0, the lower end of the Tango interval with items as
#' pairs above at one-sided `level`. At a one-sided level of 0.025 that is
#' the 97.5% bound, the lower end of the 95% contrast interval, so the
#' verdict and the printed interval agree. The cost bound is the BCa cluster
#' bootstrap of the cost intervals. Each contrast's p-value is the smallest
#' one-sided level at which both conditions hold (an intersection-union
#' test, so each condition runs at that full level). The confirmatory
#' contrasts are tested with Holm's (1979) step-down procedure at the
#' registration's alpha: in order of their p-values, the j-th of k is tested
#' at alpha / (k - j + 1), and the first that fails stops the procedure.
#' Exploratory contrasts are tested at alpha alone. Beside every verdict the
#' report gives the design MDD the contrast was registered against and the
#' achieved MDD,
#' (t_(C - 1, 1 - alpha') + t_(C - 1, power)) x SE, with SE = sqrt(V_d) the
#' linearised standard error of the paired difference (the [hr_mdd()]
#' formula with p_disc / n_eff taken from the data) and
#' alpha' = alpha / (number of confirmatory contrasts), or alpha for an
#' exploratory one; it is `NA` when V_d is 0, since the data then give no
#' variance to base it on. A verdict that passed its registered test
#' is shown as passed even when the achieved MDD exceeds the margin; a note
#' says so. As a cross-check, Tango's (1998) score interval for paired
#' proportions is computed on effective counts. The discordant shares are
#' the means over items of the chance that a run of the new arm is right and
#' a run of the reference wrong (q10), and the reverse (q01). The effective
#' number of pairs is (q10 + q01 - estimate^2) / SE^2, the size of a simple
#' paired sample with the linearised variance V_d (the effective
#' size of Korn and Graubard 1998, applied to the paired difference), at most
#' the number of items (runs of one item mostly agree, so they are not
#' independent pairs); the counts are q10 and q01 times it. Tango's
#' interval is reported at the level the contrast was tested at, beside
#' whether it reaches the same accuracy conclusion, and is not used in the
#' verdict.
#'
#' A registration, or `confirmatory = TRUE`, makes the report evidence: a
#' `bench` with any row outside the test and final splits (dev, exploratory
#' or calibration) or marked not reportable is then refused with an error of
#' class `hr_dev_not_evidence`. The `bench` must
#' carry the hash of the reference the registration names, as an
#' [hr_benchmark()] result does (error class `hr_registration_mismatch`),
#' and a registration changed after it was made is refused (class
#' `hr_registration_changed`).
#'
#' Below 5 runs the report is descriptive only: point estimates without
#' intervals, resamples or rank intervals. Cost and pass^k intervals (BCa),
#' rank intervals and the frontier share come from the cluster bootstrap in
#' both regimes; below the thresholds the report says to read them as rough.
#'
#' @param bench An [hr_benchmark()] result, or a data frame with at least the
#'   columns `cluster`, `item`, `arm`, `run` and `correct`. Optional columns
#'   (`reportable`, `outcome`, `failure_kind`, `usd`, `usd_provenance`,
#'   `tokens_in`, `tokens_out`) are used when present. Every arm must have
#'   every run on every item, and an item is scored on every run or on none.
#' @param contrasts Pairs of arms to compare: a two-column character matrix
#'   of arm names, each row giving first minus second. `NULL` compares every
#'   pair, in benchmark order.
#' @param B Number of cluster bootstrap resamples, at least 100.
#' @param conf Confidence level of every interval.
#' @param k The values of k for pass^k.
#' @param seed Seed of the private random stream the resamples are drawn
#'   from; the caller's random state is left as it was.
#' @param method `"auto"`, `"bootstrap"`, `"cluster_t"`, `"bayes"` or
#'   `"exact"`, as above.
#' @param confirmatory `TRUE` for a confirmatory report, which raises the
#'   default `B` to 5000 and refuses dev-split rows. Left unset, it is `TRUE`
#'   when `registration` holds a confirmatory contrast.
#' @param registration An [hr_register_contrasts()] result for the reference
#'   this benchmark scored, or `NULL`.
#' @param x An `hr_bench_report`.
#' @param digits Digits to print.
#' @param pretty Whether to indent the JSON.
#' @param ... Ignored by `print()`; passed on by `as_json()`.
#' @return An object of class `hr_bench_report`, a list with
#' \describe{
#'   \item{`method`, `method_reason`, `descriptive`}{The interval method used
#'     for accuracy, why it was chosen, and whether the report is descriptive
#'     only.}
#'   \item{`n_items`, `n_clusters`, `runs`, `arms`, `conf`, `B`, `seed`,
#'     `confirmatory`}{The design and settings.}
#'   \item{`accuracy`}{Per arm: `estimate`, `lower`, `upper`, `method`
#'     (`"studentised_cluster_bootstrap"`, `"logit_cluster_robust_t"`,
#'     `"korn_graubard_clopper_pearson"`, `"beta_binomial_bayes"` or
#'     `"descriptive"`), and the rank interval `rank_lower`, `rank_upper`.}
#'   \item{`bayes`}{Per arm, in the Bayesian regime: posterior mean and
#'     median of mu and posterior mean of rho.}
#'   \item{`contrasts`}{Per contrast: `arm1`, `arm2`, `estimate` (arm1 minus
#'     arm2), `lower`, `upper`, `method` (`"cluster_robust_t"`, or
#'     `"tango_items"` when the cluster variance is 0).}
#'   \item{`simultaneous`}{Every pairwise difference with simultaneous
#'     `lower` and `upper` bounds, `method` (`"max_t_cluster_robust"`, or
#'     `"tango_items"` when the cluster variance is 0) and the max-t
#'     `critical` value (`NA` on `"tango_items"` rows, which do not use it).}
#'   \item{`stability`}{Per arm: `flip_rate`, `tara`, `run_sd`.}
#'   \item{`pass_k`}{Per arm and k: `pass_k` with `lower` and `upper`.}
#'   \item{`cost`}{Per arm: `usd_per_item`, `usd_per_correct`,
#'     `tokens_per_item`, `tokens_per_correct`, each with `_lower` and
#'     `_upper`, `usd_estimated_share` and `estimated_flag`.}
#'   \item{`frontier`}{Per arm: `usd_per_item`, `accuracy`, `on_frontier`,
#'     `frontier_share`.}
#'   \item{`failures`}{Per arm: counts by failure kind, `accuracy` and
#'     `accuracy_without_parse_refusal`.}
#'   \item{`variance`}{`within`, `between`, `within_share` overall and per
#'     arm, and `recommend_runs`.}
#'   \item{`ni`}{With a registration, per registered contrast: `new`,
#'     `reference`, `label`, `margin`, `estimate`, the one-sided `lower`
#'     bound at the one-sided `level` it was tested at, `accuracy_holds`,
#'     `cost_test`, `cost_diff`, `cost_upper`, `cost_holds`, `verdict`,
#'     `mdd_design`, `mdd_achieved`, and Tango's `tango_lower` and
#'     `tango_upper` with `tango_agrees` (whether it reaches the same
#'     accuracy conclusion), the effective number of pairs `n_eff` it
#'     rests on, and `p_value`, the smallest one-sided level at which the
#'     contrast passes, found by bisection. The search stops at 1e-6, and
#'     for a contrast with `cost_test = TRUE` at 1 / (B + 1), the smallest
#'     level the B bootstrap resamples of the cost bound resolve (1 / 2001,
#'     about 5.0e-4, at B = 2000); a value at that floor means at most the
#'     floor. `NULL` without one.}
#'   \item{`registration`}{The registration's hash, time and reference
#'     hash, or `NULL`.}
#'   \item{`notes`}{What the reader should know.}
#' }
#' @references
#' Atil, B. et al. (2025). Non-determinism of "deterministic" LLM settings.
#' arXiv:2408.04667.
#'
#' Agresti, A. (2013). *Categorical Data Analysis*, 3rd edition. Wiley.
#'
#' Bowyer, S. et al. (2025). Position: Don't use the CLT in LLM evals with
#' fewer than a few hundred datapoints. *ICML 2025*.
#'
#' Cameron, A. C. and Miller, D. L. (2015). A practitioner's guide to
#' cluster-robust inference. *Journal of Human Resources* 50(2), 317-372.
#'
#' Cochran, W. G. (1977). *Sampling Techniques*, 3rd edition. Wiley.
#'
#' Davison, A. C. and Hinkley, D. V. (1997). *Bootstrap Methods and their
#' Application*. Cambridge University Press.
#'
#' Efron, B. (1987). Better bootstrap confidence intervals. *Journal of the
#' American Statistical Association* 82(397), 171-185.
#'
#' Efron, B. and Tibshirani, R. J. (1993). *An Introduction to the
#' Bootstrap*. Chapman and Hall.
#'
#' Hothorn, T., Bretz, F. and Westfall, P. (2008). Simultaneous inference in
#' general parametric models. *Biometrical Journal* 50(3), 346-363.
#'
#' Kapoor, S., Stroebl, B., Siegel, Z. S., Nadgir, N. and Narayanan, A.
#' (2024). arXiv:2407.01502.
#'
#' Korn, E. L. and Graubard, B. I. (1998). Confidence intervals for
#' proportions with small expected number of positive counts estimated from
#' survey data. *Survey Methodology* 24(2), 193-201.
#'
#' Holm, S. (1979). A simple sequentially rejective multiple test procedure.
#' *Scandinavian Journal of Statistics* 6(2), 65-70.
#'
#' Miller, E. (2024). Adding error bars to evals: a statistical approach to
#' language model evaluations. arXiv:2411.00640.
#'
#' Tango, T. (1998). Equivalence test and confidence interval for the
#' difference in proportions for the paired-sample design. *Statistics in
#' Medicine* 17(8), 891-908.
#'
#' Yao, S., Shinn, N., Razavi, P. and Narasimhan, K. (2024). tau-bench.
#' arXiv:2406.12045.
#' @seealso [hr_benchmark()], [hr_prop_ci()], [hr_register_contrasts()],
#'   [hr_mdd()]
#' @family harness
#' @export
#' @examples
#' # 12 documents with 3 questions each, two arms, 5 runs.
#' set.seed(2)
#' grid <- expand.grid(run = 1:5, arm = c("short", "long"), item = 1:36,
#'                     stringsAsFactors = FALSE)
#' grid$cluster <- paste0("doc", (grid$item - 1) %/% 3 + 1)
#' grid$item <- paste0("q", grid$item)
#' grid$correct <- runif(nrow(grid)) < ifelse(grid$arm == "long", 0.8, 0.7)
#' grid$usd <- ifelse(grid$arm == "long", 0.004, 0.001)
#' rpt <- hr_report(grid, B = 500)
#' rpt
#' rpt$accuracy
hr_report <- function(bench, contrasts = NULL, B = 2000, conf = 0.95, k = c(1, 3, 5),
                      seed = 1, method = c("auto", "bootstrap", "cluster_t", "bayes", "exact"),
                      confirmatory = FALSE, registration = NULL) {
  method <- match.arg(method)
  if (!is.null(registration)) {
    check_registration(registration)
    if (missing(confirmatory)) confirmatory <- registration$n_confirmatory > 0L
  }
  if (!is.logical(confirmatory) || length(confirmatory) != 1L || is.na(confirmatory)) {
    gr_abort("`confirmatory` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  if (confirmatory && missing(B)) B <- 5000
  check_conf(conf)
  check_boot(B, seed, min = 100L)
  if (!is.numeric(k) || !length(k) || anyNA(k) || any(k < 1) || any(k != round(k))) {
    gr_abort("`k` must be whole numbers, at least 1.", class = "gr_bad_setting")
  }
  if (confirmatory || !is.null(registration)) check_no_dev(bench)
  if (!is.null(registration) &&
      !identical(attr(bench, "reference_hash"), registration$reference_hash)) {
    gr_abort(paste0("The benchmark did not score the reference the contrasts were registered ",
                    "against (its reference hash differs or is missing), so the ",
                    "registration does not apply to it."), class = "hr_registration_mismatch")
  }
  d <- report_design(bench)
  arms <- d$arms
  A <- length(arms); I <- length(d$items); C <- length(d$n); R <- length(d$runs)
  pairs <- report_pairs(contrasts, arms)
  notes <- d$notes

  descriptive <- R < 5L
  intervals <- !descriptive && C >= 2L
  big <- I >= 300L && C >= 30L
  chosen <- if (!intervals) "none" else if (method == "auto") (if (big) "bootstrap" else "cluster_t")
            else method
  reason <- if (descriptive) {
    sprintf("%d run(s), below 5: descriptive only, without intervals", R)
  } else if (C < 2L) {
    "one cluster: no interval can be drawn from clusters"
  } else if (method == "auto") {
    sprintf("%d items in %d clusters %s 300 items and 30 clusters", I, C,
            if (big) "reach" else "fall short of")
  } else {
    sprintf("method = \"%s\" was asked for (%d items in %d clusters)", method, I, C)
  }
  if (chosen == "bootstrap" && !big) {
    notes <- c(notes, paste0("The studentised cluster bootstrap was asked for below 300 items ",
                             "or 30 clusters; with few clusters its intervals are unstable and ",
                             "can undercover or overcover (in 2000 simulated benchmarks of 50 ",
                             "items in 10 clusters it covered 96.0% and 96.1% and was 13% to 16% ",
                             "wider than the cluster-robust t interval)."))
  }
  if (chosen == "bayes") {
    notes <- c(notes, paste0("The Bayesian beta-binomial interval was asked for. In the ",
                             "coverage simulation (50 items in 10 clusters, 2000 replicates) ",
                             "it covered 96.5% to 96.6% and missed mostly below the truth ",
                             "(2.9% to 3.2% below, 0.2% to 0.5% above); the default there is ",
                             "the cluster-robust t interval."))
  }

  p <- d$p
  S <- rowsum(p, d$cluster_index, reorder = TRUE)
  nmat <- matrix(d$n, C, A)
  est <- colSums(S) / I
  names(est) <- arms

  # Correct runs and scored runs per item and arm, and their cluster sums:
  # the Bayesian model counts runs as trials, and run-to-run agreement within
  # an item is part of the cluster's overdispersion. Every other interval
  # works on items' mean correctness: runs of one item mostly agree, so
  # counting them as trials would claim far more information than the items
  # hold.
  cnt <- matrix(0, I, A); nr <- matrix(0, I, A)
  for (a in seq_len(A)) {
    ya <- matrix(d$y[, a, ], I, R)
    cnt[, a] <- rowSums(ya, na.rm = TRUE)
    nr[, a] <- rowSums(!is.na(ya))
  }
  Xc <- rowsum(cnt, d$cluster_index, reorder = TRUE)
  Mc <- rowsum(nr, d$cluster_index, reorder = TRUE)

  # The cluster resamples, then the multivariate t draws of the simultaneous
  # intervals, from one private stream: the resamples are the ones the seed
  # gave before the draws were added. One pair needs no draws.
  n_pairs <- A * (A - 1L) / 2L
  n_draws <- if (n_pairs > 1L) 100000L else 0L
  rng <- if (intervals) {
    with_private_rng(seed, list(counts = cluster_counts(C, B),
                                z = matrix(stats::rnorm(n_draws * n_pairs), n_draws, n_pairs),
                                w = stats::rchisq(n_draws, C - 1L)))
  } else NULL
  counts <- rng$counts
  acc_t <- if (intervals) (counts %*% S) / (counts %*% nmat) else NULL

  # Korn and Graubard's interval for the arms where the t intervals are not
  # defined: accuracy 0 or 1, or every cluster at the same accuracy (cluster
  # variance 0). At 0 or 1 an equal-tailed interval would leave out the
  # estimate itself, so the interval there is one-sided at level `conf`.
  kg_fallback <- function(acc, rows) {
    for (a in which(rows)) {
      e <- acc$estimate[[a]]
      edge <- e <= 0 || e >= 1
      lvl <- if (edge) max(2 * conf - 1, conf / 2) else conf
      k <- korn_graubard(S[, a], d$n, lvl)
      acc$lower[[a]] <- if (e <= 0) 0 else k$lower
      acc$upper[[a]] <- if (e >= 1) 1 else k$upper
      acc$method[[a]] <- "korn_graubard_clopper_pearson"
    }
    acc
  }

  # Accuracy per arm.
  acc <- data.frame(arm = arms, estimate = unname(est), lower = NA_real_, upper = NA_real_,
                    method = "descriptive", stringsAsFactors = FALSE)
  bayes <- NULL
  if (chosen == "bootstrap") {
    tab <- studentised_table(S, nmat, counts, conf, bounds = c(0, 1))
    acc$lower <- tab$lower; acc$upper <- tab$upper
    acc$method <- "studentised_cluster_bootstrap"
    acc <- kg_fallback(acc, !tab$defined)
  } else if (chosen == "cluster_t") {
    tab <- cluster_t_table(S, nmat, conf, scale = "logit")
    acc$lower <- tab$lower; acc$upper <- tab$upper
    acc$method <- "logit_cluster_robust_t"
    acc <- kg_fallback(acc, !tab$defined)
  } else if (chosen == "bayes") {
    post <- lapply(seq_len(A), function(a) bayes_betabin(Xc[, a], Mc[, a], conf))
    acc$lower <- vapply(post, `[[`, numeric(1), "lower")
    acc$upper <- vapply(post, `[[`, numeric(1), "upper")
    # At 0 or 1 an equal-tailed interval leaves out the estimate itself, so
    # the interval there is one-sided, from the boundary.
    at0 <- est == 0; at1 <- est == 1
    acc$lower[at0] <- 0
    acc$upper[at0] <- vapply(post[at0], `[[`, numeric(1), "upper_one_sided")
    acc$lower[at1] <- vapply(post[at1], `[[`, numeric(1), "lower_one_sided")
    acc$upper[at1] <- 1
    acc$method <- "beta_binomial_bayes"
    bayes <- data.frame(arm = arms, mu_mean = vapply(post, `[[`, numeric(1), "mean"),
                        mu_median = vapply(post, `[[`, numeric(1), "median"),
                        rho_mean = vapply(post, `[[`, numeric(1), "rho_mean"),
                        stringsAsFactors = FALSE)
  } else if (chosen == "exact") {
    kg <- lapply(seq_len(A), function(a) korn_graubard(S[, a], d$n, conf))
    acc$lower <- vapply(kg, `[[`, numeric(1), "lower")
    acc$upper <- vapply(kg, `[[`, numeric(1), "upper")
    acc$method <- "korn_graubard_clopper_pearson"
  }
  acc$rank_lower <- NA_real_; acc$rank_upper <- NA_real_
  if (intervals) {
    ranks <- t(apply(-acc_t, 1L, rank, ties.method = "min"))
    if (A == 1L) ranks <- matrix(ranks, ncol = 1L)
    a2 <- (1 - conf) / 2
    acc$rank_lower <- apply(ranks, 2L, stats::quantile, probs = a2, type = 1, names = FALSE)
    acc$rank_upper <- apply(ranks, 2L, stats::quantile, probs = 1 - a2, type = 1,
                            names = FALSE)
  }

  # Paired differences, and simultaneous intervals over every pair.
  diff_rows <- function(pr, level, simultaneous = FALSE) {
    if (!nrow(pr)) return(NULL)
    i1 <- match(pr[, 1], arms); i2 <- match(pr[, 2], arms)
    D <- S[, i1, drop = FALSE] - S[, i2, drop = FALSE]
    out <- data.frame(arm1 = pr[, 1], arm2 = pr[, 2], estimate = colSums(D) / I,
                      lower = NA_real_, upper = NA_real_, method = "descriptive",
                      stringsAsFactors = FALSE, row.names = NULL)
    if (!intervals) return(out)
    # The mean paired difference is a ratio of cluster sums: its interval is
    # the cluster-robust t interval in every regime. A difference whose
    # clusters all agree has cluster variance 0, where that interval is not
    # defined; it gets Tango's score interval with items as pairs
    # (paired_items_interval()), the interval the non-inferiority bound uses
    # there too, and a note below.
    den <- matrix(d$n, C, ncol(D))
    v <- cluster_ratio_se(D, den)
    se <- unname(v$se)
    use <- se > 0
    if (simultaneous) {
      # The pairs with V_d = 0 take a Bonferroni share (1 - level) / npairs
      # each below, so the max-t part over the rest runs at the remaining
      # error, (1 - level) x n_use / npairs, and the family stays at level.
      lev_t <- 1 - (1 - level) * sum(use) / nrow(pr)
      crit <- if (any(use)) {
        max_t_critical(v$vcov[use, use, drop = FALSE], v$df, lev_t, rng$z, rng$w)
      } else NA_real_
      out$lower <- out$estimate - crit * se
      out$upper <- out$estimate + crit * se
      out$method <- "max_t_cluster_robust"
      out$critical <- ifelse(use, crit, NA_real_)
      # Bonferroni over all pairs for the rows the max-t method cannot take.
      a_zero <- (1 - level) / (2 * nrow(pr))
    } else {
      tab <- cluster_t_table(D, den, level)
      out$lower <- tab$lower; out$upper <- tab$upper
      out$method <- "cluster_robust_t"
      a_zero <- (1 - level) / 2
    }
    if (any(!use)) {
      sh <- discordant_shares(p, i1, i2)
      for (j in which(!use)) {
        iv <- paired_items_interval(sh$q10[[j]], sh$q01[[j]], I, v$df, a_zero)
        out$lower[j] <- iv[["lower"]]; out$upper[j] <- iv[["upper"]]
        out$method[j] <- "tango_items"
      }
    }
    # A difference of proportions lies in [-1, 1]; with few clusters (df 1)
    # the t intervals can reach past that, so they are cut to it, as the
    # accuracy intervals are cut to [0, 1].
    out$lower <- pmax(out$lower, -1)
    out$upper <- pmin(out$upper, 1)
    out
  }
  all_pairs <- report_pairs(NULL, arms)
  contr <- diff_rows(pairs, conf)
  simult <- diff_rows(all_pairs, conf, simultaneous = TRUE)
  if (any(c(contr$method, simult$method) == "tango_items")) {
    notes <- c(notes, paste0(
      "A paired difference has cluster variance 0: every cluster gives the same mean ",
      "difference per item, where the t interval is not defined. That is a property of ",
      "these items, not evidence that the difference is known; its interval (and its ",
      "non-inferiority bound) is Tango's score interval with items as pairs, the item count ",
      "scaled for C - 1 degrees of freedom."))
  }

  # Stability.
  stab <- data.frame(arm = arms, stringsAsFactors = FALSE)
  stab$flip_rate <- colMeans(p > 0 & p < 1)
  stab$tara <- vapply(seq_len(A), function(a) {
    o <- matrix(d$key[, a, ], I, R)
    mean(rowSums(o == o[, 1L]) == R)
  }, numeric(1))
  stab$run_sd <- vapply(seq_len(A), function(a) {
    if (R < 2L) return(NA_real_)
    stats::sd(colMeans(matrix(d$y[, a, ], I, R), na.rm = TRUE))
  }, numeric(1))

  # Reliability: pass^k.
  ks <- sort(unique(as.integer(k)))
  if (any(ks > R)) {
    notes <- c(notes, sprintf("pass^k for k = %s left out: there are only %d run(s).",
                              paste(ks[ks > R], collapse = ", "), R))
  }
  ks <- ks[ks <= R]
  passk <- do.call(rbind, lapply(ks, function(kk) {
    v <- choose(cnt, kk) / choose(nr, kk)
    num <- rowsum(v, d$cluster_index, reorder = TRUE)
    out <- data.frame(arm = arms, k = kk, pass_k = colSums(v) / I, lower = NA_real_,
                      upper = NA_real_, stringsAsFactors = FALSE)
    if (intervals) {
      tab <- bca_table(ratio_boot(num, nmat, counts), conf)
      out$lower <- tab$lower; out$upper <- tab$upper
    }
    out
  }))

  # Cost.
  ubar <- rowMeans(d$usd, dims = 2L)
  tbar <- rowMeans(d$tokens, dims = 2L)
  U <- rowsum(ubar, d$cluster_index, reorder = TRUE)
  Tk <- rowsum(tbar, d$cluster_index, reorder = TRUE)
  cost <- data.frame(arm = arms, stringsAsFactors = FALSE)
  cost_stat <- function(name, num, den) {
    val <- colSums(num) / colSums(den)
    cost[[name]] <<- unname(val)
    lo <- hi <- rep(NA_real_, A)
    if (intervals) {
      tab <- bca_table(ratio_boot(num, den, counts), conf)
      lo <- tab$lower; hi <- tab$upper
    }
    cost[[paste0(name, "_lower")]] <<- lo
    cost[[paste0(name, "_upper")]] <<- hi
  }
  cost_stat("usd_per_item", U, nmat)
  cost_stat("usd_per_correct", U, S)
  cost_stat("tokens_per_item", Tk, nmat)
  cost_stat("tokens_per_correct", Tk, S)
  cost$usd_estimated_share <- d$estimated_share
  cost$estimated_flag <- !is.na(d$estimated_share) & d$estimated_share > 0.05
  if (any(cost$estimated_flag)) {
    notes <- c(notes, sprintf(paste0(
      "More than 5%% of the cost of %s rests on estimated token counts; read its cost ",
      "as approximate."), paste(cost$arm[cost$estimated_flag], collapse = ", ")))
  }

  # Frontier.
  front <- data.frame(arm = arms, usd_per_item = cost$usd_per_item, accuracy = unname(est),
                      stringsAsFactors = FALSE)
  front$on_frontier <- pareto_set(front$usd_per_item, front$accuracy)
  front$frontier_share <- NA_real_
  if (intervals) {
    usd_t <- (counts %*% U) / (counts %*% nmat)
    on <- vapply(seq_len(nrow(usd_t)), function(b) pareto_set(usd_t[b, ], acc_t[b, ]),
                 logical(A))
    on <- matrix(on, nrow = A)
    front$frontier_share <- ifelse(is.na(front$usd_per_item), NA_real_, rowMeans(on))
  }

  # Failures.
  fk <- d$failure
  kinds <- unique(c("wrong", .hr_failure_kinds, sort(unique(fk[!is.na(fk)]))))
  fail <- data.frame(arm = arms, stringsAsFactors = FALSE)
  for (kd in kinds) {
    fail[[kd]] <- vapply(seq_len(A), function(a) sum(fk[, a, ] %in% kd), integer(1))
  }
  fail$accuracy <- unname(est)
  drop <- array(fk %in% c("parse_failure", "refusal"), dim(fk))
  y2 <- d$y
  y2[drop] <- NA
  p2 <- rowMeans(y2, dims = 2L, na.rm = TRUE)
  fail$accuracy_without_parse_refusal <- vapply(seq_len(A), function(a) {
    v <- p2[, a]
    if (all(is.nan(v))) NA_real_ else mean(v[!is.nan(v)])
  }, numeric(1))
  fail$runs_dropped <- vapply(seq_len(A), function(a) sum(drop[, a, ]), integer(1))

  # Variance components on the probability scale.
  within_a <- colMeans(p * (1 - p))
  between_a <- apply(p, 2L, function(v) mean((v - mean(v))^2))
  share <- function(w, b) if (w + b > 0) w / (w + b) else NA_real_
  within <- mean(within_a); between <- mean(between_a)
  var_tab <- data.frame(arm = arms, within = within_a, between = between_a,
                        within_share = mapply(share, within_a, between_a),
                        stringsAsFactors = FALSE, row.names = NULL)
  wshare <- share(within, between)
  recommend <- if (!is.na(wshare) && wshare > 0.10) 10L else NA_integer_
  if (!is.na(recommend) && R < 10L) {
    notes <- c(notes, sprintf(paste0(
      "Run-to-run variance is %.0f%% of the total, above 10%%: use runs = 10."), 100 * wshare))
  }

  ni <- NULL
  if (!is.null(registration)) {
    ni <- report_ni(registration, arms, S, U, d$n, p, counts)
    if (!intervals) {
      notes <- c(notes, paste0("The registered contrasts were not tested: the report has no ",
                               "intervals."))
    } else {
      under <- ni$verdict %in% TRUE & (ni$mdd_achieved > ni$margin) %in% TRUE
      if (any(under)) {
        notes <- c(notes, sprintf(paste0(
          "%s passed the registered test although the achieved MDD exceeds the margin; the ",
          "verdict stands, and the MDD beside it says how fine a difference these items ",
          "resolve."), paste(ni$new[under], "vs", ni$reference[under], collapse = ", ")))
      }
      if (any(ni$cost_test & is.na(ni$cost_diff))) {
        notes <- c(notes, paste0("A contrast with a cost test has arms with unknown cost; ",
                                 "its cost condition cannot hold."))
      }
      if (any(ni$tango_agrees %in% FALSE)) {
        notes <- c(notes, paste0("Tango's interval on effective counts reaches a different ",
                                 "accuracy conclusion from the non-inferiority bound (the ",
                                 "cluster-robust t bound, or Tango's with items as pairs where ",
                                 "the cluster variance is 0) for at least one contrast; the ",
                                 "verdict follows that bound."))
      }
    }
  }

  if (descriptive) {
    notes <- c(notes, sprintf(paste0(
      "Descriptive only: %d run(s) cannot separate run-to-run spread from differences ",
      "between arms, so no interval is given. Use runs = 5 or more."), R))
  } else if (intervals && !big) {
    notes <- c(notes, paste0(
      "Cost, pass^k, frontier share and rank intervals come from the cluster bootstrap, ",
      "which can undercover below 300 items or 30 clusters; read them as rough."))
  }
  if (intervals && any(acc$method == "korn_graubard_clopper_pearson") && chosen != "exact") {
    notes <- c(notes, sprintf(paste0(
      "Accuracy of %s is 0, 1 or the same in every cluster, where the t interval is not ",
      "defined; its interval is Korn and Graubard's, one-sided from 0 or 1 at those bounds."),
      paste(acc$arm[acc$method == "korn_graubard_clopper_pearson"], collapse = ", ")))
  }
  if (intervals) {
    notes <- c(notes, paste0(
      "The frontier share (how often an arm is on the cost-accuracy frontier over ",
      "resamples) is an extension, not a published standard."))
  }

  structure(list(
    method = chosen, method_reason = reason, descriptive = descriptive,
    n_items = I, n_clusters = C, runs = R, arms = arms, conf = conf,
    B = if (intervals) as.integer(B) else NA_integer_, seed = seed,
    confirmatory = confirmatory,
    accuracy = acc, bayes = bayes, contrasts = contr, simultaneous = simult,
    stability = stab, pass_k = passk, cost = cost, frontier = front, failures = fail,
    variance = list(within = within, between = between, within_share = wshare,
                    by_arm = var_tab, recommend_runs = recommend),
    ni = ni,
    registration = if (!is.null(registration)) {
      list(hash = registration$hash, registered_at = registration$registered_at,
           reference_hash = registration$reference_hash, alpha = registration$alpha,
           power = registration$power, n_confirmatory = registration$n_confirmatory)
    },
    notes = unique(notes)), class = "hr_bench_report")
}

#' Which points are on the Pareto frontier of lower cost and higher accuracy:
#' those no other point matches or beats on both with one strictly better.
#' A point with no cost is neither on it nor considered.
#' @noRd
pareto_set <- function(cost, acc) {
  ok <- is.finite(cost) & is.finite(acc)
  vapply(seq_along(cost), function(i) {
    if (!ok[i]) return(NA)
    !any(ok & cost <= cost[i] & acc >= acc[i] & (cost < cost[i] | acc > acc[i]))
  }, logical(1))
}

#' The pairs of arms to compare, as a two-column character matrix.
#' @noRd
report_pairs <- function(contrasts, arms) {
  if (is.null(contrasts)) {
    if (length(arms) < 2L) return(matrix(character(0), 0L, 2L))
    cmb <- utils::combn(length(arms), 2L)
    return(matrix(arms[cmb], ncol = 2L, byrow = TRUE))
  }
  if (is.data.frame(contrasts)) contrasts <- as.matrix(contrasts)
  if (is.character(contrasts) && is.null(dim(contrasts)) && length(contrasts) == 2L) {
    contrasts <- matrix(contrasts, 1L)
  }
  if (!is.matrix(contrasts) || !is.character(contrasts) || ncol(contrasts) != 2L ||
      anyNA(contrasts)) {
    gr_abort("`contrasts` must be a two-column character matrix of arm names, or NULL.",
             class = "gr_bad_setting")
  }
  bad <- setdiff(as.vector(contrasts), arms)
  if (length(bad)) {
    gr_abort(sprintf("`contrasts` names arm(s) not in the benchmark: %s.",
                     paste(bad, collapse = ", ")), class = "gr_bad_setting")
  }
  if (any(contrasts[, 1] == contrasts[, 2])) {
    gr_abort("A contrast compares an arm with itself.", class = "gr_bad_setting")
  }
  unname(contrasts)
}

#' The reportable, labelled part of a benchmark as arrays: correctness,
#' outcome keys, failure kinds, dollars and tokens by item x arm x run, with
#' the cluster of each item.
#' @noRd
report_design <- function(bench) {
  if (!is.data.frame(bench)) {
    gr_abort("`bench` must be an hr_benchmark() result or a data frame.",
             class = "hr_bad_bench")
  }
  cols <- names(bench)
  need <- c("cluster", "item", "arm", "run", "correct")
  miss <- setdiff(need, cols)
  if (length(miss)) {
    gr_abort(sprintf("`bench` lacks the column(s) %s.", paste(miss, collapse = ", ")),
             class = "hr_bad_bench")
  }
  df <- unclass(bench)
  n_all <- length(df$item)
  rep_ok <- if ("reportable" %in% cols) df$reportable %in% TRUE else rep(TRUE, n_all)
  notes <- character(0)
  if (any(!rep_ok)) {
    notes <- c(notes, sprintf("%d row(s) not reportable (the dev split) were left out.",
                              sum(!rep_ok)))
  }
  if (!any(rep_ok)) {
    gr_abort("`bench` has no reportable rows: dev-split scores are not evidence.",
             class = "hr_bad_bench")
  }
  get <- function(name, default) {
    if (name %in% cols) df[[name]][rep_ok] else rep(default, sum(rep_ok))
  }
  item <- as.character(get("item", NA)); cluster <- as.character(get("cluster", NA))
  arm <- as.character(get("arm", NA)); run <- get("run", NA)
  correct <- as.logical(get("correct", NA))
  if (anyNA(item) || anyNA(cluster) || anyNA(arm) || anyNA(run)) {
    gr_abort("`cluster`, `item`, `arm` and `run` must not be NA.", class = "hr_bad_bench")
  }
  # Items with no label (every run NA) cannot be scored and are left out.
  labelled <- unique(item[!is.na(correct)])
  unl <- setdiff(unique(item), labelled)
  if (length(unl)) {
    notes <- c(notes, sprintf("%d item(s) with no label were left out.", length(unl)))
  }
  if (!length(labelled)) gr_abort("`bench` has no labelled items.", class = "hr_bad_bench")
  # An item scored on some runs but not others would enter accuracy over
  # fewer runs than pass^k assumes; hr_benchmark() never writes one.
  part <- intersect(labelled, unique(item[is.na(correct)]))
  if (length(part)) {
    gr_abort(sprintf(paste0("%d item(s) have NA correctness on some runs but not all ",
                            "(first: %s); label every run or none."),
                     length(part), part[1L]), class = "hr_bad_bench")
  }
  keep <- item %in% labelled
  idx <- which(rep_ok)[keep]
  item <- item[keep]; cluster <- cluster[keep]; arm <- arm[keep]; run <- run[keep]
  correct <- correct[keep]
  items <- unique(item)
  clus_of <- tapply(cluster, item, function(v) length(unique(v)))
  if (any(clus_of > 1L)) {
    gr_abort("Each item must belong to one cluster.", class = "hr_bad_bench")
  }
  arms <- unique(arm); runs <- sort(unique(run))
  I <- length(items); A <- length(arms); R <- length(runs)
  ii <- match(item, items); aa <- match(arm, arms); rr <- match(run, runs)
  cell <- ii + I * (aa - 1L) + I * A * (rr - 1L)
  if (anyDuplicated(cell)) {
    gr_abort("`bench` has more than one row for some item, arm and run.",
             class = "hr_bad_bench")
  }
  if (length(cell) != I * A * R) {
    gr_abort(paste0("Every arm must have every run on every item: arms compared on ",
                    "different items or runs are not paired."), class = "hr_bad_bench")
  }
  fill <- function(v, na) {
    out <- array(na, c(I, A, R))
    out[cell] <- v
    out
  }
  y <- fill(as.numeric(correct), NA_real_)
  fk_raw <- if ("failure_kind" %in% cols) as.character(df$failure_kind[idx]) else
    rep(NA_character_, length(idx))
  # A wrong run that names no failure kind (a table without the column) is
  # plain wrong.
  fk_raw[is.na(fk_raw) & correct %in% FALSE] <- "wrong"
  fk <- fill(fk_raw, NA_character_)
  out_raw <- if ("outcome" %in% cols) as.character(df$outcome[idx]) else
    ifelse(correct, "correct", "wrong")
  # A run with no outcome is keyed by its failure kind, so two refusals agree.
  key <- ifelse(is.na(out_raw), paste0("<", ifelse(is.na(fk_raw), "none", fk_raw), ">"),
                paste0("=", out_raw))
  usd_raw <- if ("usd" %in% cols) as.numeric(df$usd[idx]) else rep(NA_real_, length(idx))
  tok_raw <- if (all(c("tokens_in", "tokens_out") %in% cols)) {
    as.numeric(df$tokens_in[idx]) + as.numeric(df$tokens_out[idx])
  } else rep(NA_real_, length(idx))
  share <- vapply(arms, function(a) {
    if (!"usd_provenance" %in% cols) return(NA_real_)
    sel <- which(arm == a)
    u <- usd_raw[sel]; pv <- as.character(df$usd_provenance[idx][sel])
    if (anyNA(u)) return(NA_real_)
    if (sum(u) <= 0) return(0)
    sum(u[pv %in% "estimated"]) / sum(u)
  }, numeric(1))
  cl <- unname(vapply(items, function(i) cluster[match(i, item)], character(1)))
  clusters <- unique(cl)
  ci <- match(cl, clusters)
  y_mat <- rowMeans(y, dims = 2L, na.rm = TRUE)
  list(items = items, arms = arms, runs = runs, clusters = clusters, cluster_index = ci,
       n = tabulate(ci, nbins = length(clusters)), y = y,
       p = matrix(y_mat, I, A), key = fill(key, NA_character_), failure = fk,
       usd = fill(usd_raw, NA_real_), tokens = fill(tok_raw, NA_real_),
       estimated_share = unname(share), notes = notes)
}

#' @rdname hr_report
#' @export
print.hr_bench_report <- function(x, digits = 3, ...) {
  f <- function(v) ifelse(is.na(v), "-", formatC(v, digits = digits, format = "f"))
  iv <- function(lo, hi) ifelse(is.na(lo), "-", sprintf("[%s, %s]", f(lo), f(hi)))
  cat(sprintf("<hr_bench_report> %d arm(s), %d item(s) in %d cluster(s), %d run(s)\n",
              length(x$arms), x$n_items, x$n_clusters, x$runs))
  cat(sprintf("Intervals: %s at %g%% (%s).\n",
              switch(x$method, none = "none",
                     bootstrap = sprintf("studentised cluster bootstrap, B = %d", x$B),
                     cluster_t = "cluster-robust t on the logit scale, C - 1 df",
                     bayes = "Bayesian beta-binomial with a cluster effect",
                     exact = "Korn-Graubard (Clopper-Pearson on the cluster effective size)"),
              100 * x$conf, x$method_reason))
  a <- x$accuracy
  cat("\nAccuracy (arms in benchmark order, not ranked):\n")
  print(data.frame(arm = a$arm, accuracy = f(a$estimate), interval = iv(a$lower, a$upper),
                   rank_interval = ifelse(is.na(a$rank_lower), "-",
                                          sprintf("%d-%d", as.integer(a$rank_lower),
                                                  as.integer(a$rank_upper))),
                   stringsAsFactors = FALSE), row.names = FALSE, right = FALSE)
  if (!is.null(x$contrasts) && nrow(x$contrasts)) {
    cat("\nPaired differences (first minus second):\n")
    s <- x$simultaneous
    if (is.null(s)) s <- data.frame(arm1 = character(0), arm2 = character(0),
                                    lower = numeric(0), upper = numeric(0))
    # The simultaneous rows hold each pair once, in benchmark order. A
    # contrast written the other way round takes the negated interval of its
    # pair, [-upper, -lower], which holds for the max-t and Tango rows alike.
    key <- paste(x$contrasts$arm1, x$contrasts$arm2)
    sm <- match(key, paste(s$arm1, s$arm2))
    rv <- match(key, paste(s$arm2, s$arm1))
    flip <- is.na(sm) & !is.na(rv)
    s_lo <- ifelse(flip, -s$upper[rv], s$lower[sm])
    s_hi <- ifelse(flip, -s$lower[rv], s$upper[sm])
    print(data.frame(contrast = paste(x$contrasts$arm1, "-", x$contrasts$arm2),
                     difference = f(x$contrasts$estimate),
                     interval = iv(x$contrasts$lower, x$contrasts$upper),
                     simultaneous = iv(s_lo, s_hi),
                     stringsAsFactors = FALSE), row.names = FALSE, right = FALSE)
  }
  st <- x$stability
  cat("\nStability across runs:\n")
  print(data.frame(arm = st$arm, flip_rate = f(st$flip_rate), TARa = f(st$tara),
                   run_sd = f(st$run_sd)), row.names = FALSE, right = FALSE)
  if (!is.null(x$pass_k) && nrow(x$pass_k)) {
    pk <- x$pass_k
    wide <- data.frame(arm = x$arms, stringsAsFactors = FALSE)
    for (kk in unique(pk$k)) {
      r <- pk[pk$k == kk, ]
      wide[[sprintf("pass^%d", kk)]] <- f(r$pass_k[match(x$arms, r$arm)])
    }
    cat("\nReliability:\n")
    print(wide, row.names = FALSE, right = FALSE)
  }
  co <- x$cost
  cat("\nCost:\n")
  g <- function(v) ifelse(is.na(v), "-", formatC(v, digits = 4, format = "g"))
  print(data.frame(arm = co$arm, usd_per_item = g(co$usd_per_item),
                   usd_per_correct = g(co$usd_per_correct),
                   interval = ifelse(is.na(co$usd_per_correct_lower), "-",
                                     sprintf("[%s, %s]", g(co$usd_per_correct_lower),
                                             g(co$usd_per_correct_upper))),
                   tokens_per_item = g(co$tokens_per_item),
                   estimated = ifelse(is.na(co$usd_estimated_share), "-",
                                      paste0(f(100 * co$usd_estimated_share), "%",
                                             ifelse(co$estimated_flag, " (flag)", ""))),
                   on_frontier = ifelse(is.na(x$frontier$on_frontier), "-",
                                        ifelse(x$frontier$on_frontier, "yes", "no")),
                   frontier_share = f(x$frontier$frontier_share),
                   stringsAsFactors = FALSE), row.names = FALSE, right = FALSE)
  fa <- x$failures
  shown <- setdiff(names(fa), c("arm", "accuracy", "accuracy_without_parse_refusal",
                                "runs_dropped"))
  shown <- shown[colSums(fa[, shown, drop = FALSE]) > 0 | shown == "wrong"]
  cat("\nFailures (all counted wrong):\n")
  print(cbind(fa[c("arm", shown)],
              without_parse_refusal = f(fa$accuracy_without_parse_refusal)),
        row.names = FALSE, right = FALSE)
  if (!is.null(x$ni) && nrow(x$ni)) {
    ni <- x$ni
    pt <- function(v) ifelse(is.na(v), "-", sprintf("%.1f", 100 * v))
    cat(sprintf("\nNon-inferiority (registered %s, hash %s; points):\n",
                x$registration$registered_at, substr(x$registration$hash, 1, 12)))
    print(data.frame(
      contrast = paste(ni$new, "vs", ni$reference), label = ni$label, margin = pt(ni$margin),
      difference = pt(ni$estimate),
      lower = ifelse(is.na(ni$lower), "-", sprintf("%s (%s)", pt(ni$lower),
                                                  formatC(ni$level, digits = 3, format = "g"))),
      cost_upper = ifelse(!ni$cost_test, "not tested",
                          ifelse(is.na(ni$cost_upper), "-",
                                 formatC(ni$cost_upper, digits = 3, format = "g"))),
      verdict = ifelse(is.na(ni$verdict), "not tested",
                       ifelse(ni$verdict, "non-inferior", "not shown")),
      mdd_design = pt(ni$mdd_design), mdd_achieved = pt(ni$mdd_achieved),
      tango = ifelse(is.na(ni$tango_lower), "-",
                     sprintf("[%s, %s]", pt(ni$tango_lower), pt(ni$tango_upper))),
      stringsAsFactors = FALSE), row.names = FALSE, right = FALSE)
    cat(paste0("  lower: one-sided bound of the accuracy difference at the level in brackets ",
               "(Holm for confirmatory contrasts); cost_upper: upper bound of the paired ",
               "dollars per item.\n"))
  }
  v <- x$variance
  cat(sprintf("\nVariance on the probability scale: within-item runs %s, between items %s, within share %s.\n",
              f(v$within), f(v$between), f(v$within_share)))
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}

#' @rdname hr_report
#' @export
as_json.hr_bench_report <- function(x, pretty = TRUE, ...) {
  out <- unclass(x)
  out$arms <- I(out$arms)
  out$notes <- I(out$notes)
  as_json.default(out, pretty = pretty, ...)
}
