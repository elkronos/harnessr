# core-bench-ni.R: non-inferiority contrasts and the minimum detectable
# difference.
#
# A contrast says in advance which arm must not be worse than which, by how
# much, and whether it must also be cheaper. It is registered against a
# reference before any benchmark scores that reference, and the registration
# is hashed, so the margin cannot be loosened once the results are known. A
# confirmatory margin the design cannot detect is refused at registration:
# a non-inferiority claim at a margin below the minimum detectable difference
# says more than the items can support.

#' The minimum detectable difference of a paired, clustered design
#'
#' `hr_mdd()` gives the smallest paired accuracy difference a benchmark of
#' `n_items` items can detect, and `hr_n_needed()` the number of items needed
#' to detect a given one. Both use the closed form for a paired comparison of
#' two proportions with a true difference of 0:
#'
#' n_eff = (z_(1 - alpha') + z_power)^2 x p_disc / Delta^2,
#'
#' where p_disc is the share of items on which the two arms disagree, so
#' p_disc / n_eff is the variance of the mean paired difference. Items in one
#' cluster are not independent, so the effective number of items is
#' n_eff = n_items / DE with the design effect DE = 1 + (m - 1) x ICC_D
#' (Kish 1965), where m is the mean cluster size and ICC_D the intra-cluster
#' correlation of the paired item difference, not of raw accuracy. With
#' unequal cluster sizes of coefficient of variation `cv`, m is replaced by
#' (cv^2 + 1) x m (Eldridge, Ashby and Kerry 2006). `hr_mdd()` solves for
#' Delta:
#'
#' Delta = (z_(1 - alpha') + z_power) x sqrt(p_disc / n_eff).
#'
#' With `holm = TRUE` and more than one contrast, alpha' = alpha /
#' n_contrasts, the level Holm's procedure tests its first contrast at: the
#' worst case, since later steps test at larger levels. With `holm = FALSE`,
#' alpha' = alpha.
#'
#' The closed form is a first estimate. Power for a study is better planned
#' by simulation from a pilot fitted on the dev split.
#'
#' @param n_items The number of scored items.
#' @param n_clusters The number of clusters the items fall in, or `NULL`.
#'   With `m` left `NULL`, m = n_items / n_clusters.
#' @param m The mean number of items per cluster, or `NULL`. With both `m`
#'   and `n_clusters` left `NULL` the items are taken as independent (m = 1).
#' @param icc ICC_D, the intra-cluster correlation of the paired item
#'   difference, in \[0, 1). Required when m > 1; take it from a pilot on the
#'   dev split.
#' @param p_disc The share of items on which the two arms disagree, in
#'   (0, 1]. Required.
#' @param cv The coefficient of variation of cluster sizes, 0 for equal
#'   clusters.
#' @param power The power, in (0, 1).
#' @param alpha The one-sided significance level, in (0, 0.5). 0.025 matches
#'   a one-sided 97.5% bound.
#' @param n_contrasts The number of confirmatory contrasts in the Holm family.
#' @param holm Whether to adjust alpha for Holm over `n_contrasts`.
#' @param delta The difference to detect, as a proportion (0.08 for 8
#'   points).
#' @param true_diff The true difference assumed for a non-inferiority test,
#'   at most 0: the test must then tell -delta from `true_diff`, so the gap
#'   is delta + true_diff.
#' @param x An `hr_mdd` or `hr_n_needed`.
#' @param ... Ignored.
#' @return `hr_mdd()` returns an object of class `hr_mdd`, a list with
#'   `mdd` and the design it rests on: `n_items`, `n_clusters`, `m`, `m_adj`
#'   (the size after the cv correction), `icc`, `cv`, `de`, `n_eff`,
#'   `p_disc`, `power`, `alpha`, `alpha_adj`, `n_contrasts`, `holm`,
#'   `z_alpha` and `z_power`. `hr_n_needed()` returns an object of class
#'   `hr_n_needed` with `n_eff`, `n_items` (n_eff x DE) and `n_clusters`
#'   (n_items / m, `NA` when `m` is not given), unrounded, beside the same
#'   design values; `print()` rounds them up.
#' @references
#' Eldridge, S. M., Ashby, D. and Kerry, S. (2006). Sample size for cluster
#' randomized trials: effect of coefficient of variation of cluster size and
#' analysis method. *International Journal of Epidemiology* 35(5), 1292-1300.
#'
#' Kish, L. (1965). *Survey Sampling*. Wiley.
#' @seealso [hr_register_contrasts()], [hr_report()]
#' @family harness
#' @export
#' @examples
#' # 480 scored questions in 80 documents, ICC of the paired difference 0.2,
#' # the arms disagreeing on 20% of items.
#' hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
#'
#' # The same design after Holm over nine confirmatory contrasts.
#' hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#'
#' # Items and documents needed for an 8-point margin under that Holm family.
#' hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
hr_mdd <- function(n_items, n_clusters = NULL, m = NULL, icc = NULL, p_disc = NULL, cv = 0,
                   power = 0.8, alpha = 0.025, n_contrasts = 1, holm = TRUE) {
  check_positive(n_items, "n_items")
  check_whole(n_items, "n_items")
  if (!is.null(n_clusters)) {
    check_positive(n_clusters, "n_clusters")
    check_whole(n_clusters, "n_clusters")
    if (n_clusters > n_items) {
      gr_abort("`n_clusters` cannot exceed `n_items`.", class = "gr_bad_setting")
    }
  }
  if (is.null(m) && !is.null(n_clusters)) m <- n_items / n_clusters
  if (!is.null(m) && !is.null(n_clusters) &&
      abs(m - n_items / n_clusters) > 1e-8 * max(1, m)) {
    gr_abort(sprintf("`m` (%s) does not match n_items / n_clusters (%s); give one of them.",
                     format(m), format(n_items / n_clusters)), class = "gr_bad_setting")
  }
  d <- mdd_design(m, icc, p_disc, cv, power, alpha, n_contrasts, holm)
  n_eff <- n_items / d$de
  mdd <- (d$z_alpha + d$z_power) * sqrt(d$p_disc / n_eff)
  structure(c(list(mdd = mdd, n_items = n_items,
                   n_clusters = if (is.null(n_clusters)) n_items / d$m else n_clusters,
                   n_eff = n_eff), d), class = "hr_mdd")
}

#' @rdname hr_mdd
#' @export
hr_n_needed <- function(delta, m = NULL, icc = NULL, p_disc = NULL, cv = 0, power = 0.8,
                        alpha = 0.025, n_contrasts = 1, holm = TRUE, true_diff = 0) {
  if (!is.numeric(delta) || length(delta) != 1L || is.na(delta) || delta <= 0 || delta >= 1) {
    gr_abort("`delta` must be one number in (0, 1).", class = "gr_bad_setting")
  }
  if (!is.numeric(true_diff) || length(true_diff) != 1L || is.na(true_diff) ||
      true_diff > 0 || delta + true_diff <= 0) {
    gr_abort("`true_diff` must be one number, at most 0 and above -delta.",
             class = "gr_bad_setting")
  }
  m_given <- !is.null(m)
  d <- mdd_design(m, icc, p_disc, cv, power, alpha, n_contrasts, holm)
  gap <- delta + true_diff
  n_eff <- (d$z_alpha + d$z_power)^2 * d$p_disc / gap^2
  n_items <- n_eff * d$de
  structure(c(list(n_eff = n_eff, n_items = n_items,
                   n_clusters = if (m_given) n_items / d$m else NA_real_,
                   delta = delta, true_diff = true_diff), d), class = "hr_n_needed")
}

#' The parts of an MDD calculation that do not depend on the number of
#' items: the design effect and the two normal quantiles.
#' @noRd
mdd_design <- function(m, icc, p_disc, cv, power, alpha, n_contrasts, holm) {
  if (is.null(m)) m <- 1
  if (!is.numeric(m) || length(m) != 1L || is.na(m) || m < 1) {
    gr_abort("`m` must be one number, at least 1.", class = "gr_bad_setting")
  }
  if (is.null(icc)) {
    if (m > 1 || (is.numeric(cv) && length(cv) == 1L && !is.na(cv) && cv > 0)) {
      gr_abort(paste0("Give `icc`, the intra-cluster correlation of the paired item ",
                      "difference, for clustered items; estimate it from a pilot on the ",
                      "dev split."), class = "gr_bad_setting")
    }
    icc <- 0
  }
  if (!is.numeric(icc) || length(icc) != 1L || is.na(icc) || icc < 0 || icc >= 1) {
    gr_abort("`icc` must be one number in [0, 1).", class = "gr_bad_setting")
  }
  if (is.null(p_disc)) {
    gr_abort(paste0("Give `p_disc`, the share of items on which the two arms disagree; ",
                    "estimate it from a pilot on the dev split."), class = "gr_bad_setting")
  }
  if (!is.numeric(p_disc) || length(p_disc) != 1L || is.na(p_disc) || p_disc <= 0 ||
      p_disc > 1) {
    gr_abort("`p_disc` must be one number in (0, 1].", class = "gr_bad_setting")
  }
  if (!is.numeric(cv) || length(cv) != 1L || is.na(cv) || cv < 0) {
    gr_abort("`cv` must be one number, at least 0.", class = "gr_bad_setting")
  }
  if (!is.numeric(power) || length(power) != 1L || is.na(power) || power <= 0 || power >= 1) {
    gr_abort("`power` must be one number in (0, 1).", class = "gr_bad_setting")
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) || alpha <= 0 ||
      alpha >= 0.5) {
    gr_abort("`alpha` must be one number in (0, 0.5).", class = "gr_bad_setting")
  }
  if (!is.numeric(n_contrasts) || length(n_contrasts) != 1L || is.na(n_contrasts) ||
      n_contrasts < 1 || n_contrasts != round(n_contrasts)) {
    gr_abort("`n_contrasts` must be one whole number, at least 1.", class = "gr_bad_setting")
  }
  if (!is.logical(holm) || length(holm) != 1L || is.na(holm)) {
    gr_abort("`holm` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  m_adj <- (cv^2 + 1) * m
  alpha_adj <- if (holm) alpha / n_contrasts else alpha
  list(m = m, m_adj = m_adj, icc = icc, cv = cv, de = 1 + (m_adj - 1) * icc, p_disc = p_disc,
       power = power, alpha = alpha, alpha_adj = alpha_adj,
       n_contrasts = as.integer(n_contrasts), holm = holm,
       z_alpha = stats::qnorm(1 - alpha_adj), z_power = stats::qnorm(power))
}

#' Stop unless `x` is one positive number.
#' @noRd
check_positive <- function(x, what) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x <= 0) {
    gr_abort(sprintf("`%s` must be one positive number.", what), class = "gr_bad_setting")
  }
  invisible(x)
}

#' Stop unless `x` is a whole number.
#' @noRd
check_whole <- function(x, what) {
  if (x != round(x)) {
    gr_abort(sprintf("`%s` must be a whole number, not %s.", what, format(x)),
             class = "gr_bad_setting")
  }
  invisible(x)
}

#' @rdname hr_mdd
#' @export
print.hr_mdd <- function(x, ...) {
  cat(sprintf("<hr_mdd> %.1f points at %.0f%% power, one-sided alpha %s%s\n", 100 * x$mdd,
              100 * x$power, format(signif(x$alpha_adj, 4)),
              if (x$holm && x$n_contrasts > 1L) {
                sprintf(" (%s / %d contrasts, Holm worst case)", format(x$alpha), x$n_contrasts)
              } else ""))
  cat(sprintf("  %s items in %s clusters (m = %s, %s after cv %s), ICC_D %s: DE %s, n_eff %s\n",
              format(x$n_items), format(signif(x$n_clusters, 4)), format(signif(x$m, 4)),
              format(signif(x$m_adj, 4)), format(x$cv), format(x$icc),
              format(signif(x$de, 4)), format(signif(x$n_eff, 4))))
  cat(sprintf("  p_disc %s\n", format(x$p_disc)))
  invisible(x)
}

#' @rdname hr_mdd
#' @export
print.hr_n_needed <- function(x, ...) {
  cat(sprintf("<hr_n_needed> %.1f points%s at %.0f%% power, one-sided alpha %s%s\n",
              100 * x$delta,
              if (x$true_diff < 0) sprintf(" (true difference %.1f points)", 100 * x$true_diff)
              else "", 100 * x$power, format(signif(x$alpha_adj, 4)),
              if (x$holm && x$n_contrasts > 1L) {
                sprintf(" (%s / %d contrasts, Holm worst case)", format(x$alpha), x$n_contrasts)
              } else ""))
  cat(sprintf("  n_eff %d effective items; DE %s, so %d items%s\n", ceiling(x$n_eff),
              format(signif(x$de, 4)), ceiling(x$n_items),
              if (is.na(x$n_clusters)) "" else sprintf(" in %d clusters of %s",
                                                       ceiling(x$n_clusters), format(x$m))))
  invisible(x)
}

#' Non-inferiority contrasts, registered before scoring
#'
#' `hr_contrast()` states that arm `new` is not worse than arm `reference` by
#' more than `margin` in accuracy and, with `cost_test = TRUE`, that it is
#' cheaper. `hr_register_contrasts()` fixes a set of contrasts against an
#' [hr_reference()] before any benchmark scores it, with the design MDD from
#' [hr_mdd()], and [hr_report()] tests them.
#'
#' **Registration.** A confirmatory contrast whose margin is below the design
#' MDD at 80% power after Holm over the confirmatory contrasts is refused
#' with an error of class `hr_margin_below_mdd`: a non-inferiority claim at a
#' margin finer than the design can detect says more than the items hold.
#' Registering it with `confirmatory = FALSE` labels it exploratory instead;
#' it is then tested at the unadjusted alpha and stays out of the Holm
#' family. The MDD checked is `mdd` recomputed with `n_contrasts` raised to
#' the number of confirmatory contrasts when it was lower, `holm = TRUE`,
#' `power` raised to 0.8 when it was lower, and `alpha` lowered to 0.025
#' when it was higher; [hr_report()] tests at that alpha. The design may not
#' hold more items or clusters than the reference has on the test and final
#' splits (an error of class `gr_bad_setting`).
#'
#' A reference that a benchmark has begun to score in this session, or one
#' rebuilt with the same content, is refused, with an error of class
#' `hr_registration_after_scoring`, since a margin chosen after the
#' results are seen is not pre-registered. The registration records the
#' reference's hash, the time and a SHA-256 hash of its own content;
#' [hr_report()] refuses a registration whose content no longer matches its
#' hash or that names another reference.
#'
#' @param new The name of the arm under test.
#' @param reference The name of the arm it is compared with.
#' @param margin The non-inferiority margin Delta, as a proportion (0.08 for
#'   8 points), in (0, 1). Pre-register it as min(0.5 x M1, the practical
#'   loss threshold), with M1 the reference's advantage over a minimal
#'   baseline from a pilot on the dev split.
#' @param confirmatory `TRUE` for a confirmatory contrast, in the Holm family
#'   and held to the MDD; `FALSE` for an exploratory one.
#' @param cost_test Whether the verdict also needs `new` to be cheaper than
#'   `reference`.
#' @param plan The [hr_reference()] the benchmark will score, before it is
#'   scored.
#' @param contrasts An `hr_contrast` or a list of them.
#' @param mdd An [hr_mdd()] for the planned design.
#' @param x An `hr_contrast` or `hr_contrast_registration`.
#' @param ... Ignored.
#' @return `hr_contrast()` returns an object of class `hr_contrast`, a list
#'   of its arguments. `hr_register_contrasts()` returns an object of class
#'   `hr_contrast_registration`, a list with `contrasts` (a data frame with
#'   `new`, `reference`, `margin`, `confirmatory`, `label`, `cost_test` and
#'   `mdd_design`, the MDD each contrast is held to), `mdd` (the
#'   [hr_mdd()] after Holm over the confirmatory contrasts), `mdd_single`
#'   (the same design without the Holm adjustment), `alpha`, `power`,
#'   `n_confirmatory`, `reference_hash`, `registered_at` and `hash`.
#' @seealso [hr_mdd()], [hr_report()], [hr_reference()]
#' @family harness
#' @export
#' @examples
#' ref <- hr_reference(paste0("q", 1:480), labels = rep("yes", 480),
#'                     cluster = rep(paste0("doc", 1:80), each = 6), split = "test")
#' design <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
#' design$mdd
#'
#' # A 10-point margin can be registered; a 5-point one only as exploratory.
#' reg <- hr_register_contrasts(ref, list(
#'   hr_contrast("short", "long", margin = 0.10),
#'   hr_contrast("skim", "long", margin = 0.05, confirmatory = FALSE)), design)
#' reg
#' try(hr_register_contrasts(ref, hr_contrast("skim", "long", margin = 0.05), design))
hr_contrast <- function(new, reference, margin, confirmatory = TRUE, cost_test = TRUE) {
  one_name <- function(x, what) {
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
      gr_abort(sprintf("`%s` must be one arm name.", what), class = "gr_bad_setting")
    }
    x
  }
  one_name(new, "new"); one_name(reference, "reference")
  if (identical(new, reference)) {
    gr_abort("A contrast compares an arm with itself.", class = "gr_bad_setting")
  }
  if (missing(margin) || !is.numeric(margin) || length(margin) != 1L || is.na(margin) ||
      margin <= 0 || margin >= 1) {
    gr_abort("`margin` must be one number in (0, 1), a proportion (0.08 for 8 points).",
             class = "gr_bad_setting")
  }
  for (nm in c("confirmatory", "cost_test")) {
    v <- get(nm)
    if (!is.logical(v) || length(v) != 1L || is.na(v)) {
      gr_abort(sprintf("`%s` must be TRUE or FALSE.", nm), class = "gr_bad_setting")
    }
  }
  structure(list(new = new, reference = reference, margin = margin,
                 confirmatory = confirmatory, cost_test = cost_test), class = "hr_contrast")
}

#' @rdname hr_contrast
#' @export
hr_register_contrasts <- function(plan, contrasts, mdd) {
  check_reference(plan)
  # A reference rebuilt with the same content has a fresh lock, so the
  # session record of scored hashes is checked as well.
  scored_at <- if (isTRUE(plan$.lock$locked)) plan$.lock$locked_at else
    .hr_locked_refs[[plan$hash]]
  if (!is.null(scored_at)) {
    gr_abort(sprintf(paste0(
      "A benchmark began scoring this reference at %s, so contrasts registered now are not ",
      "pre-registered: a margin chosen after the results are seen can be fitted to them. ",
      "Register contrasts before hr_benchmark() runs."), scored_at),
      class = "hr_registration_after_scoring")
  }
  if (inherits(contrasts, "hr_contrast")) contrasts <- list(contrasts)
  if (!is.list(contrasts) || !length(contrasts) ||
      !all(vapply(contrasts, inherits, logical(1), "hr_contrast"))) {
    gr_abort("`contrasts` must be an hr_contrast() or a list of them.", class = "gr_bad_setting")
  }
  if (!inherits(mdd, "hr_mdd")) {
    gr_abort("`mdd` must come from hr_mdd(), for the design the benchmark will run.",
             class = "gr_bad_setting")
  }
  # The design cannot hold more items or clusters than the reference has on
  # the splits that count as evidence; a larger one would shrink the MDD
  # below what the reference can detect.
  scored <- plan$split %in% c("test", "final")
  n_ref <- sum(scored)
  c_ref <- length(unique(plan$cluster[scored]))
  if (mdd$n_items > n_ref || mdd$n_clusters > c_ref + 1e-8) {
    gr_abort(sprintf(paste0(
      "The design has %s items in %s clusters, but the reference holds %d test or final ",
      "item(s) in %d cluster(s). Give hr_mdd() the design the benchmark will score."),
      format(mdd$n_items), format(signif(mdd$n_clusters, 4)), n_ref, c_ref),
      class = "gr_bad_setting")
  }
  tab <- data.frame(
    new = vapply(contrasts, `[[`, character(1), "new"),
    reference = vapply(contrasts, `[[`, character(1), "reference"),
    margin = vapply(contrasts, `[[`, numeric(1), "margin"),
    confirmatory = vapply(contrasts, `[[`, logical(1), "confirmatory"),
    cost_test = vapply(contrasts, `[[`, logical(1), "cost_test"),
    stringsAsFactors = FALSE)
  if (anyDuplicated(paste(tab$new, tab$reference, sep = "\r"))) {
    gr_abort("Each pair of arms may be registered once.", class = "gr_bad_setting")
  }
  k <- sum(tab$confirmatory)
  # The family is at least the confirmatory contrasts registered here, the
  # check is at 80% power or more, and the level is one-sided 0.025 or less,
  # the 97.5% bound the verdicts are tested at, whatever the design was
  # given at. A larger alpha would shrink the MDD and weaken the test.
  redo <- function(n_contrasts, holm) {
    hr_mdd(mdd$n_items, m = mdd$m, icc = mdd$icc, p_disc = mdd$p_disc, cv = mdd$cv,
           power = max(mdd$power, 0.8), alpha = min(mdd$alpha, 0.025),
           n_contrasts = n_contrasts, holm = holm)
  }
  held <- redo(max(mdd$n_contrasts, k, 1L), TRUE)
  single <- redo(1L, FALSE)
  tab$label <- ifelse(tab$confirmatory, "confirmatory", "exploratory")
  tab$mdd_design <- ifelse(tab$confirmatory, held$mdd, single$mdd)
  low <- tab$confirmatory & tab$margin < held$mdd
  if (any(low)) {
    gr_abort(sprintf(paste0(
      "The margin of %s is below the design MDD of %.1f points (80%% power, one-sided alpha ",
      "%s after Holm over %d contrast(s)), so the design cannot support a non-inferiority ",
      "claim at it. Widen the margin, enlarge the design, or register the contrast with ",
      "confirmatory = FALSE as exploratory."),
      paste(sprintf("%s vs %s (%.1f points)", tab$new[low], tab$reference[low],
                    100 * tab$margin[low]), collapse = ", "),
      100 * held$mdd, format(signif(held$alpha_adj, 4)), held$n_contrasts),
      class = "hr_margin_below_mdd")
  }
  out <- list(contrasts = tab, mdd = held, mdd_single = single, alpha = held$alpha,
              power = held$power, n_confirmatory = k, reference_hash = plan$hash,
              registered_at = utc_stamp(Sys.time()))
  out$hash <- registration_hash(out)
  structure(out, class = "hr_contrast_registration")
}

#' The content hash of a registration: everything but the hash.
#' @noRd
registration_hash <- function(reg) {
  x <- unclass(reg)[c("contrasts", "mdd", "mdd_single", "alpha", "power", "n_confirmatory",
                      "reference_hash", "registered_at")]
  x$mdd <- unclass(x$mdd); x$mdd_single <- unclass(x$mdd_single)
  x$contrasts <- as.list(x$contrasts)
  hr_hash(x)
}

#' A registration, checked: built by hr_register_contrasts() and unchanged.
#' @noRd
check_registration <- function(reg) {
  if (!inherits(reg, "hr_contrast_registration") || is.null(reg$hash)) {
    gr_abort("`registration` must come from hr_register_contrasts().",
             class = "hr_registration_changed")
  }
  if (!identical(registration_hash(reg), reg$hash)) {
    gr_abort(paste0("The registration was changed after hr_register_contrasts() recorded it, ",
                    "so its hash no longer matches its content. A pre-registered contrast ",
                    "cannot be altered after scoring."), class = "hr_registration_changed")
  }
  invisible(reg)
}

#' @rdname hr_contrast
#' @export
print.hr_contrast <- function(x, ...) {
  cat(sprintf("<hr_contrast> %s vs %s, margin %.1f points, %s%s\n", x$new, x$reference,
              100 * x$margin, if (x$confirmatory) "confirmatory" else "exploratory",
              if (x$cost_test) ", must be cheaper" else ""))
  invisible(x)
}

#' @rdname hr_contrast
#' @export
print.hr_contrast_registration <- function(x, ...) {
  cat(sprintf("<hr_contrast_registration> %d contrast(s), %d confirmatory; registered %s\n",
              nrow(x$contrasts), x$n_confirmatory, x$registered_at))
  t <- x$contrasts
  print(data.frame(contrast = paste(t$new, "vs", t$reference), label = t$label,
                   margin = sprintf("%.1f", 100 * t$margin),
                   mdd = sprintf("%.1f", 100 * t$mdd_design),
                   cost_test = ifelse(t$cost_test, "yes", "no"), stringsAsFactors = FALSE),
        row.names = FALSE, right = FALSE)
  cat(sprintf("  Margins and MDD in points; reference %s; hash %s\n",
              substr(x$reference_hash, 1, 12), substr(x$hash, 1, 12)))
  invisible(x)
}

#' Stop when a benchmark offered as confirmatory or non-inferiority evidence
#' holds rows from outside the test and final splits.
#' @noRd
check_no_dev <- function(bench) {
  if (!is.data.frame(bench)) return(invisible(bench))
  # Exploratory rows serve a first look and calibration rows set signal
  # thresholds; only the test and final splits are evidence.
  if ("split" %in% names(bench)) {
    other <- !is.na(bench$split) & !bench$split %in% c("dev", "test", "final")
    if (any(other)) {
      gr_abort(sprintf(paste0(
        "%d row(s) come from the %s split(s), which are not evidence: confirmatory and ",
        "non-inferiority reports rest on the test or final split alone. Run hr_benchmark() ",
        "on those splits."), sum(other), paste(unique(bench$split[other]), collapse = ", ")),
        class = "hr_dev_not_evidence")
    }
  }
  dev <- rep(FALSE, nrow(bench))
  if ("split" %in% names(bench)) dev <- dev | bench$split %in% "dev"
  if ("reportable" %in% names(bench)) dev <- dev | !bench$reportable %in% TRUE
  if (any(dev)) {
    gr_abort(sprintf(paste0(
      "%d row(s) come from the dev split (or are marked not reportable). Dev scores tune ",
      "arms and thresholds and are not evidence, so they cannot enter a confirmatory or ",
      "non-inferiority report. Run hr_benchmark() on the test split alone."), sum(dev)),
      class = "hr_dev_not_evidence")
  }
  invisible(bench)
}

#' Tango's (1998) score interval for the difference of two paired
#' proportions.
#'
#' With b items right under the first arm only, c right under the second
#' only, and n items, the difference is (b - c) / n and its score statistic
#' at Delta is
#'   Z(Delta) = (b - c - n Delta) / sqrt(n (2 q + Delta (1 - Delta))),
#' with q the restricted maximum likelihood estimate of the second
#' discordant cell, q = (sqrt(B^2 - 4 A C) - B) / (2 A), A = 2n,
#' B = -b - c + (2n - b + c) Delta, C = -c Delta (1 - Delta). The interval is
#' every Delta with |Z(Delta)| below z_(1 - (1 - conf) / 2). Counts may be
#' fractional (effective counts).
#' @noRd
tango_interval <- function(b, c, n, conf = 0.95) {
  if (!is.finite(n) || n <= 0 || !is.finite(b) || !is.finite(c) || b + c > n + 1e-9) {
    return(c(lower = NA_real_, upper = NA_real_))
  }
  z <- stats::qnorm(1 - (1 - conf) / 2)
  dhat <- (b - c) / n
  score <- function(d0) {
    A <- 2 * n
    B <- -b - c + (2 * n - b + c) * d0
    C <- -c * d0 * (1 - d0)
    q <- (sqrt(max(B^2 - 4 * A * C, 0)) - B) / (2 * A)
    (b - c - n * d0) / sqrt(n * (2 * q + d0 * (1 - d0)))
  }
  # Z falls from +Inf at -1 through 0 at the estimate to -Inf at 1; the ends
  # are given as large finite values, and the estimate as 0, where 0/0 can
  # arise when no item is discordant.
  big <- 1e10
  lower <- if (dhat <= -1) -1 else stats::uniroot(function(d) score(d) - z, c(-1, dhat),
                                                  f.lower = big, f.upper = -z,
                                                  tol = 1e-12)$root
  upper <- if (dhat >= 1) 1 else stats::uniroot(function(d) score(d) + z, c(dhat, 1),
                                                f.lower = z, f.upper = -big,
                                                tol = 1e-12)$root
  c(lower = lower, upper = upper)
}

#' Test the registered contrasts of a benchmark report.
#'
#' `S` and `U` are cluster sums (C x A) of item accuracy and item mean
#' dollars, `n` the items per cluster, `p` the item x arm accuracies,
#' `counts` the cluster resamples (NULL when the report has no intervals),
#' `runs` the number of runs.
#' @noRd
report_ni <- function(reg, arms, S, U, n, p, counts, runs) {
  tab <- reg$contrasts
  bad <- setdiff(c(tab$new, tab$reference), arms)
  if (length(bad)) {
    gr_abort(sprintf("The registration names arm(s) not in the benchmark: %s.",
                     paste(unique(bad), collapse = ", ")), class = "hr_registration_mismatch")
  }
  K <- nrow(tab); I <- sum(n); C <- length(n)
  alpha <- reg$alpha
  z_power <- stats::qnorm(reg$power)
  i1 <- match(tab$new, arms); i2 <- match(tab$reference, arms)
  den <- matrix(n, C, K)
  D <- S[, i1, drop = FALSE] - S[, i2, drop = FALSE]
  Du <- U[, i1, drop = FALSE] - U[, i2, drop = FALSE]
  est <- colSums(D) / I
  cost_est <- colSums(Du) / I
  out <- data.frame(new = tab$new, reference = tab$reference, label = tab$label,
                    margin = tab$margin, estimate = est, lower = NA_real_, level = NA_real_,
                    accuracy_holds = NA, cost_test = tab$cost_test, cost_diff = cost_est,
                    cost_upper = NA_real_, cost_holds = NA, verdict = NA,
                    mdd_design = tab$mdd_design, mdd_achieved = NA_real_,
                    tango_lower = NA_real_, tango_upper = NA_real_, tango_agrees = NA,
                    n_eff = NA_real_, p_value = NA_real_, stringsAsFactors = FALSE, row.names = NULL)
  if (is.null(counts)) return(out)
  ra <- ratio_boot(D, den, counts)
  ru <- ratio_boot(Du, den, counts)
  se <- apply(ra$t, 2L, stats::sd)
  # The per-contrast test at one-sided level a: the lower bound of the
  # accuracy difference above -margin and, when asked, the upper bound of
  # the cost difference below 0. Requiring both is an intersection-union
  # test, so each part runs at the full level a.
  test_at <- function(j, a) {
    acc <- bca_interval(ra$t[, j], ra$t0[[j]], ra$jack[, j], conf = 1 - 2 * a)
    acc_ok <- is.finite(acc$lower) && acc$lower > -tab$margin[j]
    cu <- NA_real_; cost_ok <- NA
    if (tab$cost_test[j]) {
      cv <- bca_interval(ru$t[, j], ru$t0[[j]], ru$jack[, j], conf = 1 - 2 * a)
      cu <- cv$upper
      cost_ok <- is.finite(cu) && cu < 0
    }
    list(lower = acc$lower, acc_ok = acc_ok, cost_upper = cu, cost_ok = cost_ok,
         pass = acc_ok && (!tab$cost_test[j] || isTRUE(cost_ok)))
  }
  # The p-value of a contrast is the smallest one-sided level at which it
  # passes, found by bisection on the log scale; 1 when it fails even at
  # 0.5. Bounds widen as the level falls, so passing is monotone in it.
  pval <- function(j) {
    if (!test_at(j, 0.5)$pass) return(1)
    lo <- log(1e-6); hi <- log(0.5)
    if (test_at(j, exp(lo))$pass) return(exp(lo))
    for (it in seq_len(40L)) {
      mid <- (lo + hi) / 2
      if (test_at(j, exp(mid))$pass) hi <- mid else lo <- mid
    }
    exp(hi)
  }
  out$p_value <- vapply(seq_len(K), pval, numeric(1))
  level <- ifelse(tab$confirmatory, NA_real_, alpha)
  # Holm's step-down over the confirmatory contrasts (Holm 1979), in order of
  # their p-values: the j-th of k is tested at alpha / (k - j + 1), and the
  # first that fails stops the procedure, leaving it and every later one
  # untested at a smaller level and so not passed. The decision at each step
  # is the bound test itself; the p-values only set the order.
  conf_idx <- which(tab$confirmatory)
  ord <- conf_idx[order(out$p_value[conf_idx])]
  stopped <- FALSE
  holm_pass <- rep(NA, K)
  for (step in seq_along(ord)) {
    j <- ord[step]
    level[j] <- alpha / (length(ord) - step + 1L)
    holm_pass[j] <- !stopped && test_at(j, level[j])$pass
    if (!holm_pass[j]) stopped <- TRUE
  }
  k <- max(reg$n_confirmatory, 1L)
  for (j in seq_len(K)) {
    r <- test_at(j, level[j])
    out$lower[j] <- r$lower
    out$level[j] <- level[j]
    out$accuracy_holds[j] <- r$acc_ok
    out$cost_upper[j] <- r$cost_upper
    out$cost_holds[j] <- r$cost_ok
    out$verdict[j] <- if (tab$confirmatory[j]) holm_pass[j] else r$pass
    # The achieved MDD is the design formula with the variance of the mean
    # paired difference, p_disc / n_eff, taken from the cluster bootstrap.
    a_mdd <- if (tab$confirmatory[j]) alpha / k else alpha
    out$mdd_achieved[j] <- (stats::qnorm(1 - a_mdd) + z_power) * se[[j]]
    # Tango's interval on effective counts. Per item, q10 is the chance that
    # a run of the new arm is right and a run of the reference wrong, and q01
    # the reverse; their means give the discordant shares of one paired run.
    # The effective number of pairs is the count at which a simple paired
    # sample with those shares would have the variance the cluster bootstrap
    # found, (q10 + q01 - estimate^2) / SE^2, as Korn and Graubard (1998)
    # define an effective size for one proportion, and it is capped at the
    # number of paired runs.
    pn <- p[, i1[j]]; pr <- p[, i2[j]]
    q10 <- mean(pn * (1 - pr)); q01 <- mean((1 - pn) * pr)
    v1 <- q10 + q01 - est[[j]]^2
    ne <- if (se[[j]] > 0 && v1 > 0) min(I * runs, v1 / se[[j]]^2) else I * runs
    out$n_eff[j] <- ne
    tg <- tango_interval(ne * q10, ne * q01, ne,
                         conf = 1 - 2 * level[j])
    out$tango_lower[j] <- tg[["lower"]]
    out$tango_upper[j] <- tg[["upper"]]
    out$tango_agrees[j] <- (tg[["lower"]] > -tab$margin[j]) == r$acc_ok
  }
  out
}
