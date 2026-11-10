# core-bench-drift.R: rerun an arm live on a frozen sample and test whether
# it still behaves as it did when the sample was recorded.
#
# Hosted models change under a stable name, so an arm that passed a gate
# last month may not be the arm running today. The frozen benchmark is the
# record of how the arm behaved; this file runs the same arm again, on the
# same items and with the same scorer, and asks two questions fixed before
# the rerun: did accuracy change, and do items flip between the frozen and
# the live runs more often than they flip between the frozen runs
# themselves. Both answers resample whole clusters, because items from one
# document share their errors.

#' Check an arm for drift against a frozen benchmark
#'
#' Reruns `arm` live on the items of a frozen [hr_benchmark()] and compares
#' the live runs with the frozen ones item by item. The live rerun is itself
#' an [hr_benchmark()] of the arm, with the frozen benchmark's split and
#' fresh draws, and is returned in `$live`; it can be reported with
#' [hr_report()] or kept as the next frozen sample.
#'
#' Two tests are run, with `alpha` and `alert` fixed in the call before
#' anything is rerun, so neither can be chosen after the result is seen.
#'
#' **(a) Accuracy change.** For item i, p_i is the share of the frozen runs
#' that were correct and q_i the share of the live runs. The change is
#' mean(q_i - p_i) over items, live minus frozen. Its two-sided interval at
#' level 1 - `alpha` is a BCa cluster bootstrap (Efron 1987): each of the `B`
#' resamples draws whole clusters with replacement, with all their items and
#' runs, so the frozen and live values of an item stay paired. Accuracy
#' changed when the interval excludes 0.
#'
#' As a cross-check the clustered McNemar test of Obuchowski (1998) is run
#' on the same item accuracies. With x_1k and x_2k the sums of p_i and q_i
#' over the items of cluster k, n_k its items, N the items and K the
#' clusters, the estimates are P_j = sum_k x_jk / N and
#'
#' X^2 = (P_1 - P_2)^2 / (V_1 + V_2 - 2 V_12),
#'
#' V_j = K / ((K - 1) N^2) sum_k (x_jk - n_k P_j)^2,
#' V_12 = K / ((K - 1) N^2) sum_k (x_1k - n_k P_1) (x_2k - n_k P_2),
#'
#' referred to a chi-squared distribution on 1 degree of freedom. An
#' unclustered McNemar test is not offered: it treats items from one document
#' as independent and overstates the evidence.
#'
#' **(b) Excess instability.** A model that answers differently from run to
#' run flips items between any two runs, frozen or live. So the flips
#' between frozen and live runs are compared with the flips among replicate
#' runs. With R_f frozen runs of which k_i were correct on item i, and R_l
#' live runs of which m_i were,
#'
#' f_i = 2 k_i (R_f - k_i) / (R_f (R_f - 1))
#'
#' is the share of pairs of frozen runs that disagree on item i,
#'
#' h_i = 2 m_i (R_l - m_i) / (R_l (R_l - 1))
#'
#' the same share among the live runs, and
#'
#' g_i = (k_i (R_l - m_i) + (R_f - k_i) m_i) / (R_f R_l)
#'
#' the share of frozen-live pairs that disagree. With frozen accuracy p and
#' live accuracy q on the item, f_i, h_i and g_i estimate 2 p (1 - p),
#' 2 q (1 - q) and p (1 - q) + q (1 - p) without bias, so the item's excess
#'
#' e_i = g_i - (f_i + h_i) / 2
#'
#' estimates (p - q)^2. It is 0 in expectation when nothing changed and
#' above 0 for any move, in either direction and from any starting
#' accuracy, so it sees losses and gains that cancel in the accuracy change
#' and noisy items that turn deterministic. The live replicate flips h_i
#' enter beside the frozen ones because g_i - f_i alone estimates
#' (q - p) (1 - 2 p), which is 0 for an item at p = 0.5 whatever q is and
#' below 0 when an item settles toward 0 or 1. The test is one-sided:
#' instability is in excess when the lower BCa bound of mean(e_i) at
#' one-sided level `alpha`, from the same cluster resamples, is above 0. The
#' flip rate of every pair of frozen runs and of every frozen-live pair is
#' returned too, so the frozen replicate distribution can be read directly.
#'
#' **P-values** of the bootstrap tests are the smallest level at which the
#' test rejects, found by bisection over \[1 / (B + 1), 0.5\]; 1 when it does
#' not reject even at 0.5.
#'
#' **Drift and alert.** `drift` is `TRUE` when either test rejects. Each test
#' runs at `alpha`, so the chance that `drift` is `TRUE` with no change at
#' all can reach 2 `alpha`; pass `alpha / 2` to hold it at `alpha`. `alert`,
#' when given, is the accuracy change, in points as a proportion, that may
#' not go unnoticed, and it is read two ways. The alert is crossed
#' (`alert_crossed`) when the whole interval of test (a) lies beyond
#' -`alert` or `alert`: a change at least that large is shown. A change of
#' `alert` is not ruled out (`alert_not_ruled_out`) when the interval reaches
#' beyond -`alert` or `alert`. A small or noisy frozen sample often cannot
#' rule it out even with no change at all, which says the sample cannot
#' vouch for the arm, not that the arm moved. Size the sample with
#' [hr_n_needed()].
#'
#' **What is refused.** Fewer than 5 frozen runs of the arm (class
#' `hr_drift_few_runs`): with fewer, the replicate flips are too few pairs to
#' compare against. An arm whose hash is not the frozen arm's, a reference
#' or scorer other than the frozen benchmark's (class `hr_drift_mismatch`):
#' those would compare two configurations, which is [hr_report()]'s job. A
#' live run any of whose requests a cache or a recording answered (class
#' `hr_drift_not_live`): that is the frozen reply again, not the model
#' today. Turn cache reads off for the drift check.
#'
#' The cluster bootstrap can undercover below 300 items or 30 clusters, and
#' the result notes it. With one cluster there is nothing to resample, and
#' both tests are left `NA`.
#'
#' @param frozen An `hr_bench` from [hr_benchmark()] holding at least 5 runs
#'   of `arm`: the frozen sample.
#' @param arm The [hr_arm()] to rerun, the same arm (by hash) that the
#'   frozen benchmark ran.
#' @param runs The number of live runs, a whole number, at least 2, so that
#'   the live runs have replicate flips of their own. As many as the frozen
#'   runs compares like with like.
#' @param alpha The level of each test, in (0, 0.5): two-sided for (a),
#'   one-sided for (b).
#' @param alert The accuracy change that must not go unnoticed, a proportion
#'   in (0, 1), or `NULL` for no alert.
#' @param client The client the live runs call; see [hr_benchmark()].
#' @param reference The [hr_reference()] the frozen benchmark scored.
#' @param scorer The scorer the frozen benchmark used; checked by name.
#' @param governor An [hr_governor()] the live rerun is held to, or `NULL`
#'   to take the limits from [gr_options()].
#' @param B The number of cluster resamples, at least 100.
#' @param seed The seed of the live runs' private random stream and of the
#'   resamples. `NULL` takes the frozen benchmark's seed plus 1, so an arm
#'   that samples makes fresh draws rather than replaying the frozen ones.
#' @param x An `hr_drift_check`.
#' @param digits Digits to print.
#' @param ... Ignored.
#' @return An object of class `hr_drift_check`, a list with
#' \describe{
#'   \item{`arm`, `arm_hash`, `reference_hash`, `frozen_runs`, `live_runs`,
#'     `n_items`, `n_clusters`, `alpha`, `alert`, `B`, `seed`}{What was
#'     compared and how.}
#'   \item{`items`}{One row per labelled item: `cluster`, `item`,
#'     `frozen_accuracy` (p_i), `live_accuracy` (q_i), `change` (`"lost"`
#'     when most frozen runs were right and most live runs wrong, `"gained"`
#'     the reverse, `"worse"` or `"better"` for a smaller move, `"same"`
#'     when p_i = q_i), `frozen_outcome` and `live_outcome` (the most common
#'     scored output, or the failure kind in angle brackets), and
#'     `replicate_flip` (f_i), `live_flip` (h_i), `cross_flip` (g_i) and
#'     `excess` (e_i). `change` compares shares of runs only: on an item
#'     whose frozen or live runs disagree among themselves (`replicate_flip`
#'     or `live_flip` above 0), a move can be ordinary run-to-run variation,
#'     and only test (b) says whether the moves as a whole exceed it. An
#'     item that was stable before (`replicate_flip` 0) and moved is a real
#'     flip.}
#'   \item{`accuracy`}{Test (a): `frozen`, `live`, `change`, `lower`,
#'     `upper`, `bca` (`FALSE` when the percentile interval stood in),
#'     `p_value`, `detected`.}
#'   \item{`mcnemar`}{The cross-check: `statistic`, `df`, `p_value`,
#'     `detected`, and `agrees`, whether it reaches the same decision as
#'     test (a).}
#'   \item{`instability`}{Test (b): `replicate_flip`, `live_flip`,
#'     `cross_flip`, `excess`, `lower` (the one-sided bound), `bca`, `p_value`,
#'     `detected`.}
#'   \item{`replicate_pairs`, `cross_pairs`}{The flip rate over items of each
#'     pair of frozen runs, and of each frozen run with each live run.}
#'   \item{`drift`}{Whether either test rejected.}
#'   \item{`alert_crossed`}{Whether the interval of test (a) lies wholly
#'     beyond the alert, a change at least that large; `NA` without `alert`
#'     or without an interval.}
#'   \item{`alert_not_ruled_out`}{Whether the interval of test (a) reaches
#'     beyond the alert, so a change that large cannot be ruled out; `NA` as
#'     for `alert_crossed`.}
#'   \item{`live`}{The live `hr_bench`.}
#'   \item{`notes`}{What the reader should know about the result.}
#' }
#' @references
#' Efron, B. (1987). Better bootstrap confidence intervals. *Journal of the
#' American Statistical Association* 82(397), 171-185.
#'
#' Obuchowski, N. A. (1998). On the comparison of correlated proportions for
#' clustered data. *Statistics in Medicine* 17(13), 1495-1507.
#' @seealso [hr_benchmark()], [hr_report()], [hr_n_needed()]
#' @family harness
#' @export
#' @examples
#' ref <- hr_reference(
#'   items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji",
#'                q5 = "Chile", q6 = "Laos"),
#'   labels = c("Paris", "Lima", "N'Djamena", "Suva", "Santiago", "Vientiane"),
#'   cluster = c("a", "a", "b", "b", "c", "c"), split = "test")
#' capitals <- c(France = "Paris", Peru = "Lima", Chad = "N'Djamena", Fiji = "Suva",
#'               Chile = "Santiago", Laos = "Vientiane")
#' answer <- function(capitals) {
#'   gr_mock_client(function(messages, params) {
#'     capitals[[sub("Capital of ", "", messages[[1]]$content)]]
#'   })
#' }
#' ask <- hr_arm("ask", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
#' frozen <- hr_benchmark(ask, ref, runs = 5, client = answer(capitals))
#'
#' # Months later the model gets two capitals wrong.
#' today <- capitals
#' today[c("Chad", "Laos")] <- c("Ndjamena", "Luang Prabang")
#' drift <- hr_drift_check(frozen, ask, client = answer(today), reference = ref,
#'                         alert = 0.1, B = 500)
#' drift
#' drift$items[drift$items$change != "same", ]
hr_drift_check <- function(frozen, arm, runs = 5, alpha = 0.05, alert = NULL, client,
                           reference, scorer = hr_scorer_exact(), governor = NULL,
                           B = 2000, seed = NULL) {
  if (!inherits(frozen, "hr_bench") ||
      !all(c("cluster", "item", "arm", "run", "correct") %in% names(frozen))) {
    gr_abort("`frozen` must be an hr_benchmark() result.", class = "hr_bad_bench")
  }
  if (missing(arm)) gr_abort("`arm` is required: the arm to rerun.", class = "hr_bad_arm")
  arm <- check_arms(arm)
  if (length(arm) != 1L) {
    gr_abort("`arm` must be one hr_arm(): a drift check reruns one arm.", class = "hr_bad_arm")
  }
  arm <- arm[[1L]]
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) || alpha <= 0 || alpha >= 0.5) {
    gr_abort("`alpha` must be one number in (0, 0.5).", class = "gr_bad_setting")
  }
  if (!is.null(alert) && (!is.numeric(alert) || length(alert) != 1L || is.na(alert) ||
                          alert <= 0 || alert >= 1)) {
    gr_abort("`alert` must be one proportion in (0, 1), or NULL.", class = "gr_bad_setting")
  }
  if (!is.numeric(runs) || length(runs) != 1L || is.na(runs) || !is.finite(runs) ||
      runs < 2 || runs != round(runs)) {
    gr_abort(paste0("`runs` must be one whole number, at least 2: test (b) needs the flips ",
                    "between live runs."), class = "gr_bad_setting")
  }
  if (is.null(seed)) seed <- as_num1(attr(frozen, "seed"), 0) + 1
  check_boot(B, seed, min = 100L)
  if (missing(client)) client <- NULL
  if (missing(reference)) {
    gr_abort("`reference` is required: the hr_reference() the frozen benchmark scored.",
             class = "hr_bad_reference")
  }
  check_reference(reference)

  # The rerun must be the same arm on the same items under the same scorer;
  # anything else is a comparison of two configurations, not a drift check.
  arms_tab <- attr(frozen, "arms")
  if (!arm$name %in% frozen$arm) {
    gr_abort(sprintf("The frozen benchmark has no runs of arm '%s'.", arm$name),
             class = "hr_drift_mismatch")
  }
  if (is.data.frame(arms_tab) && arm$name %in% arms_tab$arm &&
      !identical(arms_tab$hash[match(arm$name, arms_tab$arm)], arm$hash)) {
    gr_abort(sprintf(paste0(
      "Arm '%s' is not the arm the frozen benchmark ran: its hash differs, so its code, ",
      "settings or version changed. Compare two arms with hr_report(); a drift check reruns ",
      "the same one."), arm$name), class = "hr_drift_mismatch")
  }
  if (!identical(attr(frozen, "reference_hash"), reference$hash)) {
    gr_abort(paste0("`reference` is not the reference the frozen benchmark scored (its hash ",
                    "differs or the benchmark records none)."), class = "hr_drift_mismatch")
  }
  if (!inherits(scorer, "hr_scorer")) {
    gr_abort("`scorer` must come from hr_scorer() or hr_scorer_exact().",
             class = "hr_bad_scorer")
  }
  if (!is.null(attr(frozen, "scorer")) && !identical(attr(frozen, "scorer"), scorer$name)) {
    gr_abort(sprintf("The frozen benchmark was scored by '%s', not '%s'.",
                     attr(frozen, "scorer"), scorer$name), class = "hr_drift_mismatch")
  }

  fz <- drift_matrix(frozen, arm$name, "frozen")
  if (ncol(fz$y) < 5L) {
    gr_abort(sprintf(paste0(
      "The frozen benchmark has %d run(s) of arm '%s'; a drift check needs at least 5, so ",
      "that the flips between frozen runs give a baseline to compare the live flips with."),
      ncol(fz$y), arm$name), class = "hr_drift_few_runs")
  }

  split <- attr(frozen, "split") %||% unique(as.character(frozen$split))
  live <- hr_benchmark(arm, reference, runs = runs, client = client, scorer = scorer,
                       split = split, governor = governor, seed = seed)
  served <- unlist(lapply(attr(live, "traces"), function(tr) {
    vapply(request_steps(tr$steps), function(s) isTRUE(s$cached), logical(1))
  }), use.names = FALSE)
  if (any(served)) {
    gr_abort(sprintf(paste0(
      "%d request(s) of the live rerun were answered from a cache or a recording, so they ",
      "show the stored reply, not the model today. Rerun with cache reads off and a live ",
      "client."), sum(served)), class = "hr_drift_not_live")
  }
  lv <- drift_matrix(live, arm$name, "live")
  miss <- setdiff(fz$items, lv$items)
  if (length(miss)) {
    gr_abort(sprintf("The live rerun did not score %d frozen item(s) (first: %s).",
                     length(miss), miss[1L]), class = "hr_drift_mismatch")
  }
  m <- match(fz$items, lv$items)
  drift_compare(fz, list(y = lv$y[m, , drop = FALSE], key = lv$key[m, , drop = FALSE],
                         failure = lv$failure[m, , drop = FALSE]),
                arm = arm, reference_hash = reference$hash, alpha = alpha, alert = alert,
                B = B, seed = seed, live = live)
}

#' One arm's labelled rows of a benchmark as item x run matrices of
#' correctness, outcome keys and failure kinds, items in benchmark order.
#' @noRd
drift_matrix <- function(bench, arm, what) {
  df <- unclass(bench)
  sel <- which(df$arm == arm)
  item <- as.character(df$item[sel]); run <- df$run[sel]
  correct <- as.logical(df$correct[sel])
  labelled <- unique(item[!is.na(correct)])
  part <- intersect(labelled, unique(item[is.na(correct)]))
  if (length(part)) {
    gr_abort(sprintf(paste0("%d %s item(s) have NA correctness on some runs but not all ",
                            "(first: %s)."), length(part), what, part[1L]),
             class = "hr_bad_bench")
  }
  if (!length(labelled)) {
    gr_abort(sprintf("The %s runs have no labelled items.", what), class = "hr_bad_bench")
  }
  keep <- item %in% labelled
  sel <- sel[keep]; item <- item[keep]; run <- run[keep]; correct <- correct[keep]
  items <- unique(item); runs <- sort(unique(run))
  ii <- match(item, items); rr <- match(run, runs)
  cell <- ii + length(items) * (rr - 1L)
  if (anyDuplicated(cell) || length(cell) != length(items) * length(runs)) {
    gr_abort(sprintf("The %s runs must hold every run of the arm on every item, once.", what),
             class = "hr_bad_bench")
  }
  fill <- function(v) {
    out <- matrix(v[1L], length(items), length(runs))
    out[cell] <- v
    out
  }
  fk <- if ("failure_kind" %in% names(df)) as.character(df$failure_kind[sel]) else
    rep(NA_character_, length(sel))
  fk[is.na(fk) & !correct] <- "wrong"
  outc <- if ("outcome" %in% names(df)) as.character(df$outcome[sel]) else
    ifelse(correct, "correct", "wrong")
  key <- ifelse(is.na(outc), paste0("<", ifelse(is.na(fk), "none", fk), ">"), outc)
  cl <- as.character(df$cluster[sel])[match(items, item)]
  list(items = items, cluster = cl, y = fill(as.numeric(correct)), key = fill(key),
       failure = fill(fk))
}

#' The most common value in each row of a character matrix; ties go to the
#' value seen first.
#' @noRd
row_mode <- function(m) {
  apply(m, 1L, function(v) {
    u <- unique(v)
    u[which.max(tabulate(match(v, u), nbins = length(u)))]
  })
}

#' The clustered McNemar statistic of Obuchowski (1998) for paired
#' proportions, from per-cluster sums `x1` and `x2` of the two scores and the
#' units per cluster `n`.
#' @noRd
obuchowski_test <- function(x1, x2, n) {
  K <- length(n); N <- sum(n)
  if (K < 2L) return(list(statistic = NA_real_, p_value = NA_real_))
  p1 <- sum(x1) / N; p2 <- sum(x2) / N
  e1 <- x1 - n * p1; e2 <- x2 - n * p2
  # V_1 + V_2 - 2 V_12 is the same sum over clusters of (e1 - e2)^2.
  v <- K / ((K - 1) * N^2) * sum((e1 - e2)^2)
  d <- p1 - p2
  if (v <= 1e-15) {
    # No spread between clusters: no difference is no evidence, and a
    # difference shared exactly by every cluster is as strong as it gets.
    if (abs(d) <= 1e-12) return(list(statistic = 0, p_value = 1))
    return(list(statistic = Inf, p_value = 0))
  }
  x2s <- d^2 / v
  list(statistic = x2s, p_value = stats::pchisq(x2s, df = 1, lower.tail = FALSE))
}

#' The smallest level in [floor, 0.5] at which `rejects(level)` holds, by
#' bisection on the log scale; 1 when it does not hold at 0.5. Rejection is
#' monotone in the level because bounds widen as the level falls.
#' @noRd
boot_level <- function(rejects, floor) {
  if (!isTRUE(rejects(0.5))) return(1)
  lo <- log(floor); hi <- log(0.5)
  if (isTRUE(rejects(floor))) return(floor)
  for (it in seq_len(40L)) {
    mid <- (lo + hi) / 2
    if (isTRUE(rejects(exp(mid)))) hi <- mid else lo <- mid
  }
  exp(hi)
}

#' Both drift tests on aligned frozen and live matrices.
#' @noRd
drift_compare <- function(fz, lv, arm, reference_hash, alpha, alert, B, seed, live) {
  Y <- fz$y; Z <- lv$y
  Rf <- ncol(Y); Rl <- ncol(Z); I <- nrow(Y)
  k <- rowSums(Y); mm <- rowSums(Z)
  p <- k / Rf; q <- mm / Rl
  f0 <- 2 * k * (Rf - k) / (Rf * (Rf - 1))
  h <- 2 * mm * (Rl - mm) / (Rl * (Rl - 1))
  g <- (k * (Rl - mm) + (Rf - k) * mm) / (Rf * Rl)
  # g - f0 alone has expectation (q - p) (1 - 2 p), blind at p = 0.5 and
  # negative when an item settles; subtracting the mean of both replicate
  # flips leaves (p - q)^2.
  ex <- g - (f0 + h) / 2
  tol <- 1e-12
  change <- ifelse(abs(q - p) <= tol, "same",
            ifelse(p > 0.5 & q < 0.5, "lost",
            ifelse(p < 0.5 & q > 0.5, "gained",
            ifelse(q < p, "worse", "better"))))
  items <- data.frame(cluster = fz$cluster, item = fz$items, frozen_accuracy = p,
                      live_accuracy = q, change = change,
                      frozen_outcome = row_mode(fz$key), live_outcome = row_mode(lv$key),
                      replicate_flip = f0, live_flip = h, cross_flip = g, excess = ex,
                      stringsAsFactors = FALSE, row.names = NULL)

  clusters <- unique(fz$cluster)
  ci <- match(fz$cluster, clusters)
  C <- length(clusters)
  n <- tabulate(ci, nbins = C)
  sums <- rowsum(cbind(p, q, q - p, ex), ci, reorder = TRUE)
  notes <- character(0)

  acc <- data.frame(frozen = mean(p), live = mean(q), change = mean(q - p),
                    lower = NA_real_, upper = NA_real_, bca = NA, p_value = NA_real_,
                    detected = NA)
  ins <- data.frame(replicate_flip = mean(f0), live_flip = mean(h), cross_flip = mean(g),
                    excess = mean(ex),
                    lower = NA_real_, bca = NA, p_value = NA_real_, detected = NA)
  if (C >= 2L) {
    counts <- with_private_rng(seed, cluster_counts(C, B))
    rb <- ratio_boot(sums[, 3:4, drop = FALSE], matrix(n, C, 2L), counts)
    floor <- 1 / (B + 1)
    two_sided <- function(a) {
      iv <- bca_interval(rb$t[, 1], rb$t0[[1]], rb$jack[, 1], conf = 1 - a)
      list(iv = iv, rejects = is.finite(iv$lower) && (iv$lower > 0 || iv$upper < 0))
    }
    one_sided <- function(a) {
      iv <- bca_interval(rb$t[, 2], rb$t0[[2]], rb$jack[, 2], conf = 1 - 2 * a)
      list(iv = iv, rejects = is.finite(iv$lower) && iv$lower > 0)
    }
    ta <- two_sided(alpha)
    acc$lower <- ta$iv$lower; acc$upper <- ta$iv$upper; acc$bca <- ta$iv$bca
    acc$detected <- ta$rejects
    acc$p_value <- boot_level(function(a) two_sided(a)$rejects, floor)
    tb <- one_sided(alpha)
    ins$lower <- tb$iv$lower; ins$bca <- tb$iv$bca; ins$detected <- tb$rejects
    ins$p_value <- boot_level(function(a) one_sided(a)$rejects, floor)
    if (I < 300L || C < 30L) {
      notes <- c(notes, sprintf(paste0(
        "%d items in %d clusters fall short of 300 items and 30 clusters, where the cluster ",
        "bootstrap can undercover; read the tests as approximate."), I, C))
    }
  } else {
    notes <- c(notes, "One cluster: there is nothing to resample, so neither test was run.")
  }
  ob <- obuchowski_test(sums[, 1], sums[, 2], n)
  mc <- data.frame(statistic = ob$statistic, df = 1L, p_value = ob$p_value,
                   detected = if (is.na(ob$p_value)) NA else ob$p_value < alpha)
  mc$agrees <- if (is.na(mc$detected) || is.na(acc$detected)) NA else
    mc$detected == acc$detected
  if (isFALSE(mc$agrees)) {
    notes <- c(notes, paste0("The clustered McNemar test and the cluster bootstrap disagree ",
                             "on the accuracy change; the evidence is near the threshold."))
  }

  pairs <- utils::combn(Rf, 2L)
  replicate_pairs <- data.frame(run1 = pairs[1, ], run2 = pairs[2, ],
                                flip_rate = colMeans(Y[, pairs[1, ], drop = FALSE] !=
                                                       Y[, pairs[2, ], drop = FALSE]))
  cg <- expand.grid(live_run = seq_len(Rl), frozen_run = seq_len(Rf))
  cross_pairs <- data.frame(frozen_run = cg$frozen_run, live_run = cg$live_run,
                            flip_rate = colMeans(Y[, cg$frozen_run, drop = FALSE] !=
                                                   Z[, cg$live_run, drop = FALSE]))

  bad <- sum(lv$failure %in% c("budget_stop", "error"))
  if (bad) {
    notes <- c(notes, sprintf(paste0(
      "%d live run(s) ended in a budget stop or an error and count as wrong, so part of any ",
      "change may be theirs."), bad))
  }
  if (Rl != Rf) {
    notes <- c(notes, sprintf(paste0(
      "%d live run(s) against %d frozen: the flip comparison stays unbiased, but equal ",
      "numbers compare like with like."), Rl, Rf))
  }
  judged <- !is.null(alert) && !is.na(acc$lower)
  alert_crossed <- if (judged) acc$upper < -alert || acc$lower > alert else NA
  alert_not_ruled_out <- if (judged) acc$lower < -alert || acc$upper > alert else NA
  structure(list(
    arm = arm$name, arm_hash = arm$hash, reference_hash = reference_hash,
    frozen_runs = Rf, live_runs = Rl, n_items = I, n_clusters = C, alpha = alpha,
    alert = alert, B = B, seed = seed, items = items, accuracy = acc, mcnemar = mc,
    instability = ins, replicate_pairs = replicate_pairs, cross_pairs = cross_pairs,
    drift = isTRUE(acc$detected) || isTRUE(ins$detected),
    alert_crossed = alert_crossed, alert_not_ruled_out = alert_not_ruled_out, live = live, notes = notes),
    class = "hr_drift_check")
}

#' @rdname hr_drift_check
#' @export
print.hr_drift_check <- function(x, digits = 3, ...) {
  f <- function(v) ifelse(is.na(v), "-", formatC(v, digits = digits, format = "f"))
  pv <- function(v) ifelse(is.na(v), "-", formatC(v, digits = 3, format = "g"))
  yn <- function(v) ifelse(is.na(v), "not run", ifelse(v, "yes", "no"))
  cat(sprintf(paste0("<hr_drift_check> arm '%s': %d frozen run(s) vs %d live, %d item(s) in ",
                     "%d cluster(s); alpha %g\n"),
              x$arm, x$frozen_runs, x$live_runs, x$n_items, x$n_clusters, x$alpha))
  a <- x$accuracy
  cat(sprintf("(a) Accuracy: frozen %s, live %s, change %s [%s, %s], p %s; changed: %s\n",
              f(a$frozen), f(a$live), f(a$change), f(a$lower), f(a$upper), pv(a$p_value),
              yn(a$detected)))
  m <- x$mcnemar
  cat(sprintf("    Clustered McNemar (Obuchowski): X^2 %s, p %s; agrees: %s\n",
              f(m$statistic), pv(m$p_value), yn(m$agrees)))
  s <- x$instability
  cat(sprintf(paste0("(b) Flips: between frozen runs %s, between live runs %s, frozen vs ",
                     "live %s, excess %s (one-sided lower %s), p %s; in excess: %s\n"),
              f(s$replicate_flip), f(s$live_flip), f(s$cross_flip), f(s$excess), f(s$lower),
              pv(s$p_value), yn(s$detected)))
  cat(sprintf("    Frozen pairs flip %s to %s; frozen-live pairs %s to %s\n",
              f(min(x$replicate_pairs$flip_rate)), f(max(x$replicate_pairs$flip_rate)),
              f(min(x$cross_pairs$flip_rate)), f(max(x$cross_pairs$flip_rate))))
  cat(sprintf("Drift: %s", if (x$drift) "yes" else "no"))
  if (!is.null(x$alert)) {
    cat(sprintf("; alert at %s: %s", f(x$alert),
                if (is.na(x$alert_crossed)) "not judged" else if (x$alert_crossed) "crossed"
                else if (x$alert_not_ruled_out) "not crossed, but cannot be ruled out"
                else "not crossed, ruled out"))
  }
  cat("\n")
  moved <- x$items[x$items$change != "same", , drop = FALSE]
  tab <- table(factor(x$items$change, levels = c("lost", "gained", "worse", "better", "same")))
  cat("Items:", paste(sprintf("%s %d", names(tab), as.integer(tab)), collapse = ", "), "\n")
  # On items whose runs disagreed, a moved share may be chance alone.
  noisy <- sum(moved$replicate_flip > 0 | moved$live_flip > 0)
  if (noisy) {
    cat(sprintf(paste0("  %d moved item(s) had runs that disagreed, where a move can be ",
                       "run-to-run variation\n"), noisy))
  }
  if (nrow(moved)) {
    shown <- utils::head(moved, 10L)
    print(data.frame(item = shown$item, cluster = shown$cluster, change = shown$change,
                     frozen = f(shown$frozen_accuracy), live = f(shown$live_accuracy),
                     frozen_outcome = shown$frozen_outcome, live_outcome = shown$live_outcome,
                     stringsAsFactors = FALSE), row.names = FALSE, right = FALSE)
    if (nrow(moved) > 10L) cat(sprintf("  ... and %d more in $items\n", nrow(moved) - 10L))
  }
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}
