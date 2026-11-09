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
#' benchmark:
#' * At least 300 items and at least 30 clusters: a BCa cluster bootstrap.
#'   Each of the `B` resamples draws whole clusters with replacement, with all
#'   their items, runs and arms. The bias correction is z0 = qnorm(share of
#'   resamples below the estimate) and the acceleration is
#'   a = sum(L^3) / (6 sum(L^2)^1.5), with L the leave-one-cluster-out
#'   jackknife influence values (Efron 1987; Efron and Tibshirani 1993,
#'   chapter 14). Quantiles are interpolated on the normal scale as in
#'   `boot::boot.ci()`. When BCa is undefined (the estimate lies outside every
#'   resample) the percentile interval is given and the method column says so.
#' * Below either threshold: a Bayesian beta-binomial model with a cluster
#'   random effect, which held its coverage in small clustered samples where
#'   the bootstrap and the normal interval did not (Bowyer et al. 2025).
#'   Cluster c has m_c scored runs over its items, x_c of them correct. Its
#'   accuracy is Beta with mean mu and intra-cluster correlation rho, so
#'   alpha = mu (1 - rho) / rho and beta = (1 - mu) (1 - rho) / rho, and its
#'   runs are binomial given it; runs of one item agreeing more than runs of
#'   different items shows up as overdispersion, which rho takes up.
#'   The priors on mu and rho are flat (uniform on 0 to 1). The posterior is
#'   computed on a grid over mu and rho, and the interval is the equal-tailed
#'   credible interval of mu. Note that mu is the mean of cluster
#'   accuracies, each cluster weighted alike, while the estimate printed
#'   beside it weights clusters by their items; with unequal cluster sizes
#'   the interval can sit slightly off the estimate. When an arm's accuracy
#'   is exactly 0 or 1 an equal-tailed interval would leave out the boundary,
#'   so the interval is one-sided there: from 0 to the `conf` quantile of mu,
#'   or from the `1 - conf` quantile to 1.
#' * `method = "exact"` selects instead a Clopper-Pearson interval on the
#'   effective number of items computed from cluster totals of item
#'   accuracy, with Korn and Graubard's (1998) degrees-of-freedom adjustment.
#'   Items, not runs, are the trials, since runs of one item mostly agree.
#'
#' No Wald or normal-approximation interval is given for accuracy at any
#' size. `method = "bootstrap"` or `"bayes"` forces that method at any size,
#' with a note when the bootstrap is used below the thresholds.
#'
#' **Paired differences.** For each contrast, accuracy of the first arm minus
#' the second, item by item, so each difference is paired. Its interval is
#' BCa from the same cluster resamples as everything else, whatever the
#' method for accuracy; below 300 items or 30 clusters the report notes that
#' it may undercover.
#'
#' **Rankings.** No leaderboard by point estimate: arms are listed in the
#' order of the benchmark. Simultaneous intervals over all pairwise
#' differences use the max-t method on the bootstrap resamples (each
#' difference standardised by its bootstrap standard deviation, the critical
#' value the `conf` quantile of the largest one), with the same small-sample
#' note. Rank intervals are the `(1 - conf) /
#' 2` and `(1 + conf) / 2` quantiles of each arm's rank over the bootstrap
#' resamples (rank 1 is the most accurate).
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
#' Below 5 runs the report is descriptive only: point estimates without
#' intervals, resamples or rank intervals. Cost, pass^k and frontier
#' intervals come from the cluster bootstrap in both regimes; below the
#' thresholds the report says to read them as rough.
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
#' @param method `"auto"`, `"bootstrap"`, `"bayes"` or `"exact"`, as above.
#' @param confirmatory `TRUE` for a confirmatory report, which raises the
#'   default `B` to 5000.
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
#'   \item{`accuracy`}{Per arm: `estimate`, `lower`, `upper`, `method`, and
#'     the rank interval `rank_lower`, `rank_upper`.}
#'   \item{`bayes`}{Per arm, in the Bayesian regime: posterior mean and
#'     median of mu and posterior mean of rho.}
#'   \item{`contrasts`}{Per contrast: `arm1`, `arm2`, `estimate` (arm1 minus
#'     arm2), `lower`, `upper`, `method`.}
#'   \item{`simultaneous`}{Every pairwise difference with simultaneous
#'     `lower` and `upper` bounds and the critical value.}
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
#'   \item{`notes`}{What the reader should know.}
#' }
#' @references
#' Atil, B. et al. (2025). Non-determinism of "deterministic" LLM settings.
#' arXiv:2408.04667.
#'
#' Bowyer, S. et al. (2025). Position: Don't use the CLT in LLM evals with
#' fewer than a few hundred datapoints. *ICML 2025*.
#'
#' Efron, B. (1987). Better bootstrap confidence intervals. *Journal of the
#' American Statistical Association* 82(397), 171-185.
#'
#' Efron, B. and Tibshirani, R. J. (1993). *An Introduction to the
#' Bootstrap*. Chapman and Hall.
#'
#' Kapoor, S., Stroebl, B., Siegel, Z. S., Nadgir, N. and Narayanan, A.
#' (2024). arXiv:2407.01502.
#'
#' Korn, E. L. and Graubard, B. I. (1998). Confidence intervals for
#' proportions with small expected number of positive counts estimated from
#' survey data. *Survey Methodology* 24(2), 193-201.
#'
#' Miller, E. (2024). Adding error bars to evals: a statistical approach to
#' language model evaluations. arXiv:2411.00640.
#'
#' Yao, S., Shinn, N., Razavi, P. and Narasimhan, K. (2024). tau-bench.
#' arXiv:2406.12045.
#' @seealso [hr_benchmark()], [hr_prop_ci()]
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
                      seed = 1, method = c("auto", "bootstrap", "bayes", "exact"),
                      confirmatory = FALSE) {
  method <- match.arg(method)
  if (!is.logical(confirmatory) || length(confirmatory) != 1L || is.na(confirmatory)) {
    gr_abort("`confirmatory` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  if (confirmatory && missing(B)) B <- 5000
  check_conf(conf)
  check_boot(B, seed, min = 100L)
  if (!is.numeric(k) || !length(k) || anyNA(k) || any(k < 1) || any(k != round(k))) {
    gr_abort("`k` must be whole numbers, at least 1.", class = "gr_bad_setting")
  }
  d <- report_design(bench)
  arms <- d$arms
  A <- length(arms); I <- length(d$items); C <- length(d$n); R <- length(d$runs)
  pairs <- report_pairs(contrasts, arms)
  notes <- d$notes

  descriptive <- R < 5L
  intervals <- !descriptive && C >= 2L
  big <- I >= 300L && C >= 30L
  chosen <- if (!intervals) "none" else if (method == "auto") (if (big) "bootstrap" else "bayes")
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
    notes <- c(notes, paste0("The cluster bootstrap was asked for below 300 items or 30 ",
                             "clusters, where it can undercover."))
  }

  p <- d$p
  S <- rowsum(p, d$cluster_index, reorder = TRUE)
  nmat <- matrix(d$n, C, A)
  est <- colSums(S) / I
  names(est) <- arms

  # Correct runs and scored runs per item and arm, and their cluster sums:
  # the Bayesian model counts runs as trials, so an item whose runs agree
  # adds the variance it carries, and run-to-run agreement within an item is
  # part of the cluster's overdispersion. The exact interval counts items
  # instead: runs of one item mostly agree, so counting them as trials would
  # claim far more information than the items hold.
  cnt <- matrix(0, I, A); nr <- matrix(0, I, A)
  for (a in seq_len(A)) {
    ya <- matrix(d$y[, a, ], I, R)
    cnt[, a] <- rowSums(ya, na.rm = TRUE)
    nr[, a] <- rowSums(!is.na(ya))
  }
  Xc <- rowsum(cnt, d$cluster_index, reorder = TRUE)
  Mc <- rowsum(nr, d$cluster_index, reorder = TRUE)

  counts <- if (intervals) with_private_rng(seed, cluster_counts(C, B)) else NULL
  acc_t <- if (intervals) (counts %*% S) / (counts %*% nmat) else NULL

  # Accuracy per arm.
  acc <- data.frame(arm = arms, estimate = unname(est), lower = NA_real_, upper = NA_real_,
                    method = "descriptive", stringsAsFactors = FALSE)
  bayes <- NULL
  if (chosen == "bootstrap") {
    tab <- bca_table(ratio_boot(S, nmat, counts), conf)
    acc$lower <- tab$lower; acc$upper <- tab$upper
    acc$method <- ifelse(tab$bca, "bca_cluster_bootstrap", "percentile_cluster_bootstrap")
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
    # Every regime takes its difference intervals from the same cluster
    # resamples: a normal model on cluster differences collapses to zero
    # width when the differences agree, which says nothing about the arms.
    if (simultaneous) {
      Dt <- acc_t[, i1, drop = FALSE] - acc_t[, i2, drop = FALSE]
      se <- apply(Dt, 2L, stats::sd)
      use <- se > 0
      crit <- if (any(use)) {
        dev <- abs(sweep(Dt[, use, drop = FALSE], 2L, out$estimate[use])) /
          rep(se[use], each = nrow(Dt))
        stats::quantile(apply(dev, 1L, max), conf, names = FALSE)
      } else NA_real_
      out$lower <- out$estimate - ifelse(use, crit * se, 0)
      out$upper <- out$estimate + ifelse(use, crit * se, 0)
      out$method <- "max_t_cluster_bootstrap"
      out$critical <- crit
    } else {
      tab <- bca_table(ratio_boot(D, matrix(d$n, C, ncol(D)), counts), level)
      out$lower <- tab$lower; out$upper <- tab$upper
      out$method <- ifelse(tab$bca, "bca_cluster_bootstrap", "percentile_cluster_bootstrap")
    }
    out
  }
  all_pairs <- report_pairs(NULL, arms)
  contr <- diff_rows(pairs, conf)
  simult <- diff_rows(all_pairs, conf, simultaneous = TRUE)
  if (!is.null(contr) && any(contr$lower == contr$upper, na.rm = TRUE)) {
    notes <- c(notes, paste0(
      "A paired difference has an interval of zero width: every cluster gives the same ",
      "difference, so the resamples show no spread. That is a property of these items, ",
      "not evidence that the difference is known."))
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

  if (descriptive) {
    notes <- c(notes, sprintf(paste0(
      "Descriptive only: %d run(s) cannot separate run-to-run spread from differences ",
      "between arms, so no interval is given. Use runs = 5 or more."), R))
  } else if (intervals && chosen != "bootstrap" && !big) {
    notes <- c(notes, paste0(
      "Paired differences, simultaneous intervals, cost, pass^k, frontier share and ",
      "rank intervals come from the cluster bootstrap, ",
      "which can undercover below 300 items or 30 clusters; read them as rough."))
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
              switch(x$method, none = "none", bootstrap = sprintf("cluster bootstrap, B = %d",
                                                                   x$B),
                     bayes = "Bayesian beta-binomial with a cluster effect",
                     exact = "Clopper-Pearson on the cluster effective size"),
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
    sm <- match(paste(x$contrasts$arm1, x$contrasts$arm2), paste(s$arm1, s$arm2))
    print(data.frame(contrast = paste(x$contrasts$arm1, "-", x$contrasts$arm2),
                     difference = f(x$contrasts$estimate),
                     interval = iv(x$contrasts$lower, x$contrasts$upper),
                     simultaneous = iv(s$lower[sm], s$upper[sm]),
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
