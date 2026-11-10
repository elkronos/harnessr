# core-bench-sim.R: simulations that check the report's intervals and the
# MDD formula on data whose answer is known.
#
# dev/sim-coverage.R and dev/sim-power.R run these as a nightly job, not in
# the test suite: 2000 replicates of a report take minutes. The functions
# live in the package so the test suite can run a few replicates of each and
# keep them working, and so the nightly job checks the installed code.
#
# Replicate r is drawn from its own seed (seed + r - 1), so a run split into
# chunks across processes gives the same replicates as one run in a single
# process.

#' The design of a coverage simulation.
#'
#' Correctness of run r of arm a on item i in cluster c follows a threshold
#' model on a latent normal scale:
#'
#'   correct = (mu_a + u_c + u_ca + v_i + v_ia + e_iar > 0),
#'
#' with every term independent, normal with mean 0, and variances `var_doc`
#' (the document effect both arms share), `var_doc_arm` (each arm's own
#' document effect, which gives the paired difference its clustering),
#' `var_item`, `var_item_arm` and `var_run`, scaled to sum to 1. The latent
#' total then has variance 1, so the true accuracy of arm a is pnorm(mu_a)
#' and mu_a = qnorm(accuracy[a]) fixes it; the true paired difference is
#' accuracy[2] - accuracy[1]. The document ICC on the latent scale is
#' var_doc + var_doc_arm and the run share is var_run.
#'
#' The large regime has 40 clusters of 5 to 15 items (386 items), above the
#' 300 items and 30 clusters where hr_report() uses the studentised cluster
#' bootstrap for accuracy. The small regime has 10 clusters of 5 items, where
#' it uses the cluster-robust t interval on the logit scale.
#' @noRd
sim_design <- function(regime = c("large", "small"), accuracy = c(ref = 0.70, new = 0.75),
                       runs = 5L, var_doc = 0.15, var_doc_arm = 0.05, var_item = 0.35,
                       var_item_arm = 0.25, var_run = 0.20, sizes = NULL) {
  regime <- match.arg(regime)
  if (is.null(sizes)) {
    sizes <- if (regime == "large") rep_len(5:15, 40L) else rep(5L, 10L)
  }
  if (!is.numeric(accuracy) || length(accuracy) != 2L || anyNA(accuracy) ||
      any(accuracy <= 0 | accuracy >= 1) || is.null(names(accuracy)) ||
      anyDuplicated(names(accuracy))) {
    gr_abort("`accuracy` must be two named numbers in (0, 1): reference first, then new.",
             class = "gr_bad_setting")
  }
  v <- c(doc = var_doc, doc_arm = var_doc_arm, item = var_item, item_arm = var_item_arm,
         run = var_run)
  if (anyNA(v) || any(v < 0) || sum(v) <= 0) {
    gr_abort("The variance components must be numbers, at least 0, not all 0.",
             class = "gr_bad_setting")
  }
  if (!is.numeric(sizes) || !length(sizes) || any(sizes < 1) || any(sizes != round(sizes))) {
    gr_abort("`sizes` must be whole numbers, at least 1.", class = "gr_bad_setting")
  }
  check_positive(runs, "runs")
  check_whole(runs, "runs")
  v <- v / sum(v)
  structure(list(regime = regime, accuracy = accuracy, mu = stats::qnorm(accuracy),
                 runs = as.integer(runs), sizes = as.integer(sizes), var = v,
                 icc_doc = unname(v[["doc"]] + v[["doc_arm"]]), run_share = unname(v[["run"]]),
                 truth = c(accuracy, diff = unname(accuracy[[2]] - accuracy[[1]]))),
            class = "hr_sim_design")
}

#' One simulated benchmark from a sim_design(), as the data frame hr_report()
#' reads: cluster, item, arm, run, correct. Draws from the current RNG.
#' @noRd
sim_corpus <- function(design) {
  sizes <- design$sizes
  C <- length(sizes); cl <- rep(seq_len(C), sizes); I <- length(cl)
  R <- design$runs; v <- design$var
  shared <- stats::rnorm(C, 0, sqrt(v[["doc"]]))[cl] + stats::rnorm(I, 0, sqrt(v[["item"]]))
  arms <- names(design$accuracy)
  rows <- lapply(seq_along(arms), function(a) {
    own <- design$mu[[a]] + shared + stats::rnorm(C, 0, sqrt(v[["doc_arm"]]))[cl] +
      stats::rnorm(I, 0, sqrt(v[["item_arm"]]))
    lat <- own + matrix(stats::rnorm(I * R, 0, sqrt(v[["run"]])), I, R)
    data.frame(cluster = sprintf("doc%03d", rep(cl, R)), item = sprintf("q%04d", rep(seq_len(I), R)),
               arm = arms[[a]], run = rep(seq_len(R), each = I), correct = as.vector(lat > 0),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Coverage replicates: for each, simulate a benchmark, report it with
#' hr_report() (method "auto", the contrast new minus reference) and check
#' whether each interval holds the true value.
#'
#' Rows with `gate = TRUE` are the intervals hr_report() prints by default:
#' accuracy per arm by the method its size selects, and the paired difference,
#' which is the cluster-robust t interval at every size. When the report did not
#' use the bootstrap, the Korn and Graubard interval that `method = "exact"`
#' would give is added per arm with `gate = FALSE`, from the same data.
#' `first` numbers the replicates, for runs split into chunks.
#' @noRd
sim_coverage <- function(design, reps, seed = 1L, B = 2000L, conf = 0.95, first = 1L) {
  if (!inherits(design, "hr_sim_design")) {
    gr_abort("`design` must come from sim_design().", class = "gr_bad_setting")
  }
  check_positive(reps, "reps"); check_whole(reps, "reps")
  check_positive(first, "first"); check_whole(first, "first")
  arms <- names(design$accuracy)
  out <- lapply(first - 1L + seq_len(reps), function(r) {
    s <- seed + r - 1L
    # hr_report() restarts the stream at the seed it is given, so seed s
    # would draw the resamples from the uniforms that made the data. The
    # report gets a seed drawn after the corpus instead.
    drawn <- with_private_rng(s, list(bench = sim_corpus(design),
                                      seed = sample.int(.Machine$integer.max, 1L)))
    bench <- drawn$bench
    rpt <- hr_report(bench, contrasts = c(arms[[2]], arms[[1]]), B = B, conf = conf, k = 1,
                      seed = drawn$seed)
    acc <- rpt$accuracy
    rows <- data.frame(rep = r, quantity = "accuracy", arm = acc$arm, method = acc$method,
                       gate = TRUE, truth = unname(design$accuracy[acc$arm]),
                       estimate = acc$estimate, lower = acc$lower, upper = acc$upper,
                       stringsAsFactors = FALSE)
    ct <- rpt$contrasts
    rows <- rbind(rows, data.frame(rep = r, quantity = "difference",
                                   arm = paste(ct$arm1, "-", ct$arm2), method = ct$method,
                                   gate = TRUE, truth = design$truth[["diff"]],
                                   estimate = ct$estimate, lower = ct$lower, upper = ct$upper,
                                   stringsAsFactors = FALSE))
    if (rpt$method != "bootstrap") {
      # Cluster sums of item accuracy, the input hr_report(method = "exact")
      # gives korn_graubard().
      item_acc <- stats::aggregate(correct ~ cluster + item + arm, data = bench, FUN = mean)
      kg <- lapply(arms, function(a) {
        ia <- item_acc[item_acc$arm == a, ]
        x <- tapply(ia$correct, ia$cluster, sum)
        n <- tapply(ia$correct, ia$cluster, length)
        k <- korn_graubard(as.vector(x), as.vector(n), conf)
        data.frame(rep = r, quantity = "accuracy", arm = a,
                   method = "korn_graubard_clopper_pearson", gate = FALSE,
                   truth = design$accuracy[[a]], estimate = sum(x) / sum(n),
                   lower = k$lower, upper = k$upper, stringsAsFactors = FALSE)
      })
      rows <- rbind(rows, do.call(rbind, kg))
    }
    rows
  })
  out <- do.call(rbind, out)
  out$covered <- out$lower <= out$truth & out$truth <= out$upper
  out$below <- out$upper < out$truth
  out$above <- out$lower > out$truth
  rownames(out) <- NULL
  out
}

#' Coverage per quantity and method with its Monte Carlo interval, and the
#' pass rule: the Wilson `mc_conf` interval of coverage contains `target`
#' and its lower end is at least `floor`.
#'
#' `below` and `above` are the shares of intervals lying wholly below or
#' above the truth; their balance shows which side an interval misses on.
#' `pass` is computed for every row but only rows with `gate = TRUE` decide
#' the run.
#' @noRd
sim_coverage_summary <- function(x, target = 0.95, floor = 0.93, mc_conf = 0.95) {
  key <- unique(x[c("quantity", "arm", "method", "gate")])
  rows <- lapply(seq_len(nrow(key)), function(j) {
    k <- key[j, ]
    s <- x[x$quantity == k$quantity & x$arm == k$arm & x$method == k$method &
             x$gate == k$gate, ]
    ok <- !is.na(s$covered)
    n <- sum(ok); hit <- sum(s$covered[ok])
    ci <- hr_prop_ci(hit, max(n, 1L), method = "wilson", conf = mc_conf)
    data.frame(quantity = k$quantity, arm = k$arm, method = k$method, gate = k$gate,
               reps = n, coverage = if (n) hit / n else NA_real_,
               mc_lower = if (n) ci$lower else NA_real_, mc_upper = if (n) ci$upper else NA_real_,
               below = mean(s$below[ok]), above = mean(s$above[ok]),
               width = mean(s$upper[ok] - s$lower[ok]), bias = mean(s$estimate - s$truth),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$pass <- !is.na(out$mc_lower) & out$mc_lower <= target & target <= out$mc_upper &
    out$mc_lower >= floor
  rownames(out) <- NULL
  out
}

#' The design of a power simulation for hr_mdd().
#'
#' Cluster sizes are equal when `cv` is 0 and otherwise spread around
#' n_items / n_clusters along normal quantiles scaled by `cv`, at least 1,
#' and adjusted to total `n_items`. The `cv` of the sizes made is the one
#' given to hr_mdd(), so the formula sees the design that is simulated.
#' @noRd
sim_power_design <- function(n_items, n_clusters, icc, p_disc, cv = 0, power = 0.8,
                             alpha = 0.025, n_contrasts = 1L, label = NULL) {
  check_positive(n_items, "n_items"); check_whole(n_items, "n_items")
  check_positive(n_clusters, "n_clusters"); check_whole(n_clusters, "n_clusters")
  if (!is.numeric(cv) || length(cv) != 1L || is.na(cv) || cv < 0) {
    gr_abort("`cv` must be one number, at least 0.", class = "gr_bad_setting")
  }
  m <- n_items / n_clusters
  if (cv == 0) {
    sizes <- rep(n_items %/% n_clusters, n_clusters)
    extra <- n_items - sum(sizes)
    if (extra) sizes[seq_len(extra)] <- sizes[seq_len(extra)] + 1L
  } else {
    z <- stats::qnorm(stats::ppoints(n_clusters))
    sizes <- pmax(1L, as.integer(round(m * (1 + cv * z / stats::sd(z)))))
    # Take the rounding difference off the largest clusters, or add it to
    # the smallest, one item at a time.
    while (sum(sizes) != n_items) {
      if (sum(sizes) > n_items) {
        j <- which.max(sizes); sizes[j] <- sizes[j] - 1L
      } else {
        j <- which.min(sizes); sizes[j] <- sizes[j] + 1L
      }
    }
  }
  cv_made <- if (cv == 0) 0 else stats::sd(sizes) / mean(sizes)
  mdd <- hr_mdd(n_items, n_clusters = n_clusters, icc = icc, p_disc = p_disc, cv = cv_made,
                power = power, alpha = alpha, n_contrasts = n_contrasts)
  if (is.null(label)) {
    label <- sprintf("%d items / %d clusters, ICC_D %s, p_disc %s, cv %s, %d contrast(s)",
                     n_items, n_clusters, format(icc), format(p_disc), format(round(cv_made, 2)),
                     as.integer(n_contrasts))
  }
  structure(list(label = label, n_items = n_items, n_clusters = n_clusters, sizes = sizes,
                 icc = icc, p_disc = p_disc, cv = cv_made, power = power, alpha = alpha,
                 n_contrasts = as.integer(n_contrasts), mdd = mdd),
            class = "hr_sim_power_design")
}

#' Power replicates for hr_mdd().
#'
#' Each item gets one paired difference d in {-1, 0, 1}, as hr_mdd()
#' assumes (an item scored once, or runs that agree). Cluster c draws
#' (P+, P-, P0) from a Dirichlet with mean (p_disc / 2, p_disc / 2,
#' 1 - p_disc) and precision kappa = 1 / ICC_D - 1, and its items draw d
#' from those shares. For any function of a categorical outcome the
#' Dirichlet-multinomial gives a within-cluster correlation of exactly
#' 1 / (kappa + 1), so ICC_D and p_disc are the values given and the true
#' difference is 0.
#'
#' The test is the report's non-inferiority bound: the one-sided
#' cluster-robust t lower bound of the mean paired difference at level
#' 1 - alpha', estimate - t_(C - 1, 1 - alpha') x SE with
#' SE^2 = C / (C - 1) x sum((S_c - n_c x estimate)^2) / N^2, and alpha' the
#' Holm worst case hr_mdd() uses. When SE is 0 it is the report's bound
#' there, Tango's score interval with items as pairs (paired_items_interval()).
#' Treating the MDD as a non-inferiority margin with a true difference of 0,
#' power at margin M is P(lower > -M). hr_mdd() takes the same t quantiles
#' on C - 1 degrees of freedom. The bound with the normal quantile,
#' estimate - z_(1 - alpha') x SE, is kept beside it as a cross-check (with
#' SE 0, the same Tango bound without the degrees-of-freedom scaling).
#' @noRd
sim_power <- function(design, reps, seed = 1L, first = 1L) {
  if (!inherits(design, "hr_sim_power_design")) {
    gr_abort("`design` must come from sim_power_design().", class = "gr_bad_setting")
  }
  check_positive(reps, "reps"); check_whole(reps, "reps")
  check_positive(first, "first"); check_whole(first, "first")
  sizes <- design$sizes; C <- length(sizes); N <- sum(sizes)
  cl <- rep(seq_len(C), sizes)
  a_adj <- design$mdd$alpha_adj
  z <- stats::qnorm(1 - a_adj)
  q <- stats::qt(1 - a_adj, C - 1L)
  rows <- lapply(first - 1L + seq_len(reps), function(r) {
    d <- sim_power_draw(design, seed + r - 1L)
    S <- as.vector(rowsum(d, cl, reorder = TRUE))
    v <- cluster_ratio_se(matrix(S, C, 1L), matrix(sizes, C, 1L))
    est <- unname(v$estimate); se <- unname(v$se)
    if (se > 0) {
      lower <- est - q * se; lower_normal <- est - z * se
    } else {
      q10 <- mean(d == 1); q01 <- mean(d == -1)
      lower <- paired_items_interval(q10, q01, N, C - 1L, a_adj)[["lower"]]
      lower_normal <- paired_items_interval(q10, q01, N, Inf, a_adj)[["lower"]]
    }
    data.frame(rep = r, estimate = est, lower = lower, lower_normal = lower_normal,
               p_disc_seen = mean(d != 0))
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' One replicate of sim_power(): the paired item differences d in
#' {-1, 0, 1}, items in cluster order, drawn from the private stream of
#' seed `s`.
#' @noRd
sim_power_draw <- function(design, s) {
  sizes <- design$sizes; C <- length(sizes); N <- sum(sizes)
  cl <- rep(seq_len(C), sizes)
  shares <- c(design$p_disc / 2, design$p_disc / 2, 1 - design$p_disc)
  with_private_rng(s, {
    P <- if (design$icc > 0) {
      kappa <- 1 / design$icc - 1
      g <- matrix(stats::rgamma(3L * C, shape = rep(kappa * shares, C)), C, 3L, byrow = TRUE)
      tot <- rowSums(g)
      # A cluster whose three draws all underflow to 0 keeps the mean shares.
      g[tot == 0, ] <- rep(shares, each = sum(tot == 0))
      g / rowSums(g)
    } else {
      matrix(shares, C, 3L, byrow = TRUE)
    }
    u <- stats::runif(N)
    Pi <- P[cl, , drop = FALSE]
    ifelse(u < Pi[, 1], 1, ifelse(u < Pi[, 1] + Pi[, 2], -1, 0))
  })
}

#' The MDD a power simulation implies, set against hr_mdd().
#'
#' Power at margin M is P(lower > -M), so the margin with power `power` is
#' minus the (1 - power) quantile of the lower bounds: `mdd_sim`. Its Monte
#' Carlo interval is distribution-free: with k_lo and k_hi the `mc_conf`
#' bounds of a Binomial(reps, 1 - power) count, the sorted lower bounds at
#' ranks k_lo and k_hi + 1 bracket the quantile. `power_at_mdd` is the share
#' of replicates that pass at the formula's MDD, with its Wilson interval.
#' The run passes when mdd_sim is within `tol` of the formula. That rule can
#' pass while the simulation shows the formula off by more than Monte Carlo
#' error, so `power_check` says so without deciding the run: "below target"
#' or "above target" when the Wilson interval of power_at_mdd leaves out
#' `power`, "" otherwise.
#' @noRd
sim_power_summary <- function(x, design, tol = 0.01, mc_conf = 0.95) {
  mdd <- design$mdd$mdd
  q <- 1 - design$power
  lo <- sort(x$lower)
  n <- length(lo)
  a <- (1 - mc_conf) / 2
  k <- stats::qbinom(c(a, 1 - a), n, q)
  k <- pmin(pmax(k, 1L), n)
  pw <- hr_prop_ci(sum(x$lower > -mdd), n, method = "wilson", conf = mc_conf)
  sim <- -stats::quantile(lo, q, names = FALSE)
  check <- if (pw$upper < design$power) "below target"
    else if (pw$lower > design$power) "above target" else ""
  data.frame(design = design$label, reps = n, mdd_formula = mdd, mdd_sim = sim,
             mdd_sim_lower = -lo[min(n, k[2] + 1L)], mdd_sim_upper = -lo[k[1]],
             mdd_sim_normal = -stats::quantile(x$lower_normal, q, names = FALSE),
             power_at_mdd = pw$est, power_lower = pw$lower, power_upper = pw$upper,
             power_check = check, difference = sim - mdd, pass = abs(sim - mdd) <= tol,
             stringsAsFactors = FALSE)
}
