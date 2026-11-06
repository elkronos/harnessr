# core-stats-agreement.R: agreement between two raters.

#' Cohen's kappa between two labellings.
#'
#' Chance-corrected, which is the point: at a 5% inclusion rate a screener that
#' excluded everything agrees with a person 95% of the time, and only kappa
#' reports that as the nothing it is.
#' @noRd
cohen_kappa <- function(a, b) {
  lv <- union(unique(a), unique(b))
  m <- table(factor(a, levels = lv), factor(b, levels = lv))
  n <- sum(m)
  if (!n) return(NA_real_)
  po <- sum(diag(m)) / n
  pe <- sum(rowSums(m) * colSums(m)) / n^2
  if (isTRUE(all.equal(pe, 1))) return(NA_real_)
  as.numeric((po - pe) / (1 - pe))
}

#' Agreement between two raters on one binary decision.
#'
#' `x` and `y` are logical: TRUE where each rater said positive. Rows of the
#' table are `x`, columns `y`, so with x the screener and y a person, a is
#' kept by both, b kept by the screener alone, c by the person alone and d by
#' neither.
#'
#' Kappa never travels alone. At screening prevalence (a few eligible records
#' in a hundred) kappa moves with the marginals as much as with agreement, so
#' a screener and a person who agree on 95 of 100 records can score a kappa
#' near zero (Feinstein and Cicchetti 1990). The prevalence and bias indices
#' (Byrt et al. 1993) say how far the table is from balanced, and PABAK and
#' Gwet's AC1 are the figures that do not collapse there. AC1 has the opposite
#' weakness, a value near 1 from shared absence, which is why the table and the
#' class-wise rates go with all of them.
#'
#' Intervals:
#' * kappa: a percentile bootstrap over documents, B = 2000. Each replicate
#'   draws n documents with replacement, which for a 2x2 is one multinomial
#'   draw of the four cells. It runs under a fixed seed (with the session's
#'   RNG kind), so the same table prints the same interval every time, and the
#'   caller's random state is left as it was. B and the seed are in `$bootstrap`.
#' * AC1: the linearised variance of Gwet (2008) with f = 0, as the irrCAC
#'   package does (gwet.ac1.table), with a t quantile on n - 1 degrees of
#'   freedom and the bounds held to [-1, 1].
#' * PABAK is 2 po - 1, a linear map of the observed agreement, so its interval
#'   is the Wilson interval on po mapped the same way.
#' * The class-wise rates are Wilson intervals, as everywhere else here.
#'
#' Neither the kappa nor the AC1 interval can say anything when one diagonal
#' of the table is empty: every resample then agrees completely (or not at
#' all), the variance is zero, and the interval is a point such as [1, 1]
#' that reads as certainty from a handful of records. Below `min_n` records
#' the same holds in practice. Both bounds are NA there, and `$note` says why.
#' `min_n` = 10 is a floor chosen here, not a cited one.
#'
#' `paradox` is TRUE when abs(PI) exceeds `paradox_at`. That threshold is a
#' heuristic with no cited source; it marks a table where kappa should not be
#' compared with kappa from another sample.
#' @noRd
agreement_binary <- function(x, y, conf = 0.95, paradox_at = 0.8, min_n = 10L) {
  x <- as.logical(x); y <- as.logical(y)
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]; y <- y[ok]
  a <- sum(x & y); b <- sum(x & !y); c <- sum(!x & y); d <- sum(!x & !y)
  agreement_2x2(a, b, c, d, conf = conf, paradox_at = paradox_at, min_n = min_n)
}

# The kappa bootstrap's size and seed. Fixed, so a calibration is reproducible
# from its table alone.
.gr_agreement_boot <- list(B = 2000L, seed = 19930501L)

#' The same, from the four cell counts.
#' @noRd
agreement_2x2 <- function(a, b, c, d, conf = 0.95, paradox_at = 0.8, min_n = 10L) {
  tab <- matrix(as.integer(c(a, c, b, d)), 2L, 2L,
                dimnames = list(rater1 = c("positive", "negative"),
                                rater2 = c("positive", "negative")))
  n <- sum(tab)
  row <- function(name, est, lo = NA_real_, hi = NA_real_) {
    data.frame(statistic = name, estimate = est, lower = lo, upper = hi,
               stringsAsFactors = FALSE)
  }
  rate <- function(name, hits, total) {
    w <- prop_row(name, hits, total, conf = conf)
    row(name, w$estimate, w$lower, w$upper)
  }
  if (!n) {
    stats <- do.call(rbind, lapply(c("observed agreement", "kappa", "PABAK", "AC1",
                                     "prevalence index", "bias index", "sensitivity",
                                     "specificity", "PPV", "NPV"),
                                   function(s) row(s, NA_real_)))
    return(list(table = tab, n = 0L, stats = stats, paradox = NA,
                bootstrap = .gr_agreement_boot, note = "No records in the table."))
  }
  p <- tab / n
  p1 <- rowSums(p); p2 <- colSums(p)          # rater 1, rater 2 marginals
  po <- sum(diag(p))
  tq <- if (n > 1L) stats::qt(1 - (1 - conf) / 2, n - 1L) else NA_real_
  bounds <- function(est, v) {
    if (is.na(est) || is.na(v) || is.na(tq)) return(c(NA_real_, NA_real_))
    se <- sqrt(max(v, 0))
    c(max(-1, est - tq * se), min(1, est + tq * se))
  }
  w <- diag(2L)

  # Cohen's kappa. Chance agreement from each rater's own marginals.
  pe_k <- sum(p1 * p2)
  kappa <- if (isTRUE(all.equal(pe_k, 1))) NA_real_ else (po - pe_k) / (1 - pe_k)
  # Where an interval would be a point or close to it, there is none.
  note <- if (b + c == 0) {
    "The two raters agree on every record, so no interval can be estimated from this table."
  } else if (a + d == 0) {
    "The two raters disagree on every record, so no interval can be estimated from this table."
  } else if (n < min_n) {
    sprintf("Only %d record(s); the kappa and AC1 intervals need at least %d.", n, min_n)
  } else NA_character_
  open <- is.na(note)
  kappa_ci <- if (is.na(kappa) || !open) c(NA_real_, NA_real_) else
    kappa_boot(c(a, b, c, d), n, conf)

  # Gwet's AC1. Chance agreement from the pooled marginal pi_k, two categories.
  pik <- (p1 + p2) / 2
  pe_g <- sum(pik * (1 - pik))
  ac1 <- if (isTRUE(all.equal(pe_g, 1))) NA_real_ else (po - pe_g) / (1 - pe_g)
  ac1_ci <- if (is.na(ac1) || !open) c(NA_real_, NA_real_) else {
    s <- 0
    for (k in 1:2) for (l in 1:2) {
      s <- s + p[k, l] * (w[k, l] - 2 * (1 - ac1) * (1 - (pik[k] + pik[l]) / 2))^2
    }
    bounds(ac1, (s - (po - 2 * (1 - ac1) * pe_g)^2) / (n * (1 - pe_g)^2))
  }

  po_w <- prop_row("po", a + d, n, conf = conf)
  pi_ <- (a - d) / n
  stats <- rbind(
    row("observed agreement", po, po_w$lower, po_w$upper),
    row("kappa", kappa, kappa_ci[1], kappa_ci[2]),
    row("PABAK", 2 * po - 1, 2 * po_w$lower - 1, 2 * po_w$upper - 1),
    row("AC1", ac1, ac1_ci[1], ac1_ci[2]),
    row("prevalence index", pi_),
    row("bias index", (b - c) / n),
    # Rater 2 is the reference: sensitivity is rater 1's positives among
    # rater 2's, PPV rater 2's positives among rater 1's.
    rate("sensitivity", a, a + c),
    rate("specificity", d, b + d),
    rate("PPV", a, a + b),
    rate("NPV", d, c + d))
  rownames(stats) <- NULL
  list(table = tab, n = as.integer(n), stats = stats, paradox = abs(pi_) > paradox_at,
       bootstrap = .gr_agreement_boot, note = note)
}

#' Percentile bootstrap interval for kappa, resampling documents.
#'
#' `cells` is a, b, c, d. Resampling n documents from the table is one
#' multinomial draw of the four cells per replicate, which is the same thing
#' as drawing rows and much cheaper at a corpus of thousands. Replicates where
#' kappa is undefined (every record in one marginal) are left out.
#' @noRd
kappa_boot <- function(cells, n, conf) {
  bt <- .gr_agreement_boot
  # with_private_rng(), not withr::with_seed(): withr is only suggested. The
  # caller's random stream is put back afterwards either way.
  draws <- with_private_rng(bt$seed, stats::rmultinom(bt$B, n, cells / n))
  a <- draws[1, ] / n; b <- draws[2, ] / n; c <- draws[3, ] / n; d <- draws[4, ] / n
  po <- a + d
  pe <- (a + b) * (a + c) + (c + d) * (b + d)
  k <- ifelse(abs(1 - pe) < 1e-12, NA_real_, (po - pe) / (1 - pe))
  if (all(is.na(k))) return(c(NA_real_, NA_real_))
  alpha <- 1 - conf
  stats::quantile(k, c(alpha / 2, 1 - alpha / 2), names = FALSE, na.rm = TRUE, type = 7)
}
