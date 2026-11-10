# core-stats-agreement.R: agreement between raters.

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

#' Agreement between raters, with every measure that should go with it
#'
#' One call for agreement between two raters on nominal labels, or among any
#' number of coders at a declared level of measurement.
#'
#' **Two raters** (`x` and `y`, nominal). The result holds the count table
#' and, from it:
#' * `po`, the observed agreement, with a Wilson interval;
#' * Cohen's kappa, its large-sample standard error (Fleiss, Cohen and Everitt
#'   1969) and a percentile bootstrap interval over items;
#' * the prevalence index PI = (a - d) / n and bias index BI = (b - c) / n of
#'   Byrt, Bishop and Carlin (1993), for two categories only;
#' * PABAK = (k po - 1) / (k - 1) for k categories (2 po - 1 for two), whose
#'   interval is the Wilson interval on po mapped the same way;
#' * Gwet's AC1 with the variance of Gwet (2008) and a t interval on n - 1
#'   degrees of freedom, held to between -1 and 1;
#' * positive and negative specific agreement, 2a / (2a + b + c) and
#'   2d / (2d + b + c), for two categories;
#' * when `positive` is given, `y` is read as the reference and sensitivity,
#'   specificity, PPV and NPV are reported with Wilson intervals (one category
#'   against the rest when there are more than two).
#'
#' The categories are the labels either rater used. Factor levels that
#' neither rater used are left out, with a note naming them, so a spare level
#' does not change k (and with it PABAK and AC1) or hide PI, BI and specific
#' agreement. The one exception is `positive`, which stays in the table when
#' it is a declared level, so an all-negative 2x2 stays 2x2. A `positive` that
#' is neither a declared level nor a used label is an error.
#'
#' In the table rows are `x` and columns `y`. With two categories the first
#' is `positive` when it is given (otherwise the first level), so a is "both
#' positive", b "x positive only", c "y positive only" and d "both negative".
#'
#' Kappa is never reported alone. At a low prevalence it moves with the
#' marginals as much as with agreement, so two raters who agree on 95 of 100
#' items can score a kappa near zero (Feinstein and Cicchetti 1990); AC1 has
#' the opposite weakness, a value near 1 from shared absence. The print method
#' always shows the table and the full set together.
#'
#' `paradox_flag` is TRUE when abs(PI) > 0.8, or when po >= 0.8 and
#' kappa <= 0.4. Either marks a table where kappa should not be compared with
#' a kappa from another sample. Both thresholds are heuristics, not cited
#' cut-offs.
#'
#' **Several coders** (a matrix or data frame in `coders`, or in `x` with `y`
#' left out; items in rows, coders in columns, `NA` where a coder did not label
#' an item), or two raters at a level other than nominal. The result is
#' Krippendorff's alpha from the coincidence matrix (Krippendorff 2011) with
#' the difference function of `level`:
#' * nominal: 0 for equal values, 1 otherwise;
#' * ordinal: the squared number of values ranked between the two, counting
#'   each end as half, (sum of n_g from c to k - (n_c + n_k) / 2)^2;
#' * interval: (c - k)^2;
#' * ratio: ((c - k) / (c + k))^2.
#'
#' Only items with at least two values are pairable. Alpha comes with a
#' percentile bootstrap interval over items. Below 30 pairable items, or when
#' every value is the same so that alpha is undefined, alpha is `NA` and only
#' percent agreement (the share of matching pairs, from the coincidence
#' matrix) is reported, with a note saying why: alpha from a handful of items
#' is too unstable to be read (Hayes and Krippendorff 2007).
#'
#' Ordinal levels follow the factor levels when the labels are a factor, and
#' sorted order otherwise. When coders' factors carry different level sets
#' (one coder never used "mid" and its factor has only low and high), the
#' levels are merged keeping each coder's order, so low, high and low, mid,
#' high give low, mid, high. Levels that conflict, or that leave the order of
#' two levels open, are an error for the ordinal level. Interval and ratio levels need numeric labels.
#'
#' The bootstrap runs under `seed`, so the same data give the same interval
#' every time, and the caller's random state is left as it was.
#'
#' @param x Labels from the first rater, or a matrix or data frame of coders
#'   with `y` left `NULL`.
#' @param y Labels from the second rater, the same length as `x`. Read as the
#'   reference when `positive` is given. Items where either is `NA` are left
#'   out, and the result says how many.
#' @param coders A matrix or data frame with items in rows and coders in
#'   columns, `NA` for a missing label. Used in place of `x` and `y`.
#' @param level Level of measurement of the labels: `"nominal"`, `"ordinal"`,
#'   `"interval"` or `"ratio"`. Anything but nominal is reported as alpha.
#' @param positive For two raters, the label that counts as positive. Turns on
#'   sensitivity, specificity, PPV and NPV, with `y` as the reference.
#' @param B Number of bootstrap resamples for the kappa and alpha intervals.
#'   0 skips them.
#' @param conf Confidence level for every interval.
#' @param seed Seed for the bootstrap.
#' @return An object of class `hr_agreement`: a list with `type`
#'   (`"two_raters"` or `"coders"`), `level`, `n` (items used), `dropped`
#'   (items left out for missing labels), `categories`, `table` (the count
#'   table for two raters, the coincidence matrix for coders), `stats` (a data
#'   frame with columns `statistic`, `estimate`, `se`, `lower` and `upper`),
#'   `po`, `kappa`, `alpha`, `paradox_flag`, `positive`, `notes`, `conf` and
#'   `bootstrap` (`B` and `seed`). It has `print()` and [as_json()] methods.
#' @references
#' Byrt, T., Bishop, J. and Carlin, J. B. (1993). Bias, prevalence and kappa.
#' *Journal of Clinical Epidemiology* 46(5), 423-429.
#'
#' Feinstein, A. R. and Cicchetti, D. V. (1990). High agreement but low kappa:
#' I. The problems of two paradoxes. *Journal of Clinical Epidemiology* 43(6),
#' 543-549.
#'
#' Fleiss, J. L., Cohen, J. and Everitt, B. S. (1969). Large sample standard
#' errors of kappa and weighted kappa. *Psychological Bulletin* 72(5), 323-327.
#'
#' Gwet, K. L. (2008). Computing inter-rater reliability and its variance in
#' the presence of high agreement. *British Journal of Mathematical and
#' Statistical Psychology* 61(1), 29-48.
#'
#' Hayes, A. F. and Krippendorff, K. (2007). Answering the call for a standard
#' reliability measure for coding data. *Communication Methods and Measures*
#' 1(1), 77-89.
#'
#' Krippendorff, K. (2011). Computing Krippendorff's alpha-reliability.
#' University of Pennsylvania, Annenberg School for Communication.
#' @family statistics
#' @export
#' @examples
#' # Two raters on a screening decision, the second as the reference.
#' screener <- rep(c("keep", "drop", "keep", "drop"), c(40, 9, 6, 45))
#' person <- rep(c("keep", "keep", "drop", "drop"), c(40, 9, 6, 45))
#' ag <- hr_agreement(screener, person, positive = "keep", B = 200)
#' ag
#'
#' # Three coders, one item each left blank, ordinal labels.
#' set.seed(4)
#' truth <- sample(1:4, 40, replace = TRUE)
#' codes <- sapply(1:3, function(j) pmin(4, pmax(1, truth + sample(-1:1, 40, TRUE,
#'                                                               c(0.1, 0.8, 0.1)))))
#' codes[cbind(1:3, 1:3)] <- NA
#' hr_agreement(coders = codes, level = "ordinal", B = 200)
hr_agreement <- function(x, y = NULL, coders = NULL,
                         level = c("nominal", "ordinal", "interval", "ratio"),
                         positive = NULL, B = 2000, conf = 0.95, seed = 1) {
  level <- match.arg(level)
  check_conf(conf)
  check_boot(B, seed)
  if (is.null(coders) && (is.matrix(x) || is.data.frame(x))) {
    if (!is.null(y)) {
      gr_abort("Give a matrix of coders on its own, or two label vectors `x` and `y`.",
               class = "gr_bad_setting")
    }
    coders <- x
  } else if (is.null(coders)) {
    if (missing(x) || is.null(y)) {
      gr_abort("Give two label vectors `x` and `y`, or a matrix or data frame in `coders`.",
               class = "gr_bad_setting")
    }
    if (length(x) != length(y)) {
      gr_abort(sprintf("`x` and `y` must have the same length, not %d and %d.",
                       length(x), length(y)), class = "gr_bad_setting")
    }
    if (level == "nominal") {
      return(agreement_two(x, y, positive = positive, B = B, conf = conf, seed = seed))
    }
    coders <- data.frame(x = x, y = y)
  }
  if (!is.null(positive)) {
    gr_abort("`positive` applies to two raters on nominal labels only.",
             class = "gr_bad_setting")
  }
  agreement_coders(coders, level = level, B = B, conf = conf, seed = seed)
}

#' The two-rater nominal set behind hr_agreement().
#' @noRd
agreement_two <- function(x, y, positive, B, conf, seed) {
  if (is.factor(x) || is.factor(y)) {
    lv <- union(if (is.factor(x)) levels(x) else sort(unique(as.character(x[!is.na(x)]))),
                if (is.factor(y)) levels(y) else sort(unique(as.character(y[!is.na(y)]))))
  } else {
    lv <- sort(unique(c(as.character(x[!is.na(x)]), as.character(y[!is.na(y)]))))
  }
  if (!is.null(positive)) {
    if (length(positive) != 1L || is.na(positive)) {
      gr_abort("`positive` must be one label.", class = "gr_bad_setting")
    }
    positive <- as.character(positive)
    # A label nobody used would add an empty category, which changes k and
    # with it PABAK and AC1 without any sign of the mistake.
    if (!positive %in% lv) {
      gr_abort(sprintf("`positive` (%s) is not one of the labels: %s.",
                       positive, paste(lv, collapse = ", ")),
               class = "gr_bad_setting")
    }
  }
  # Categories are the labels the raters used. A spare factor level would
  # count towards k and turn a 2x2 decision into a 3x3, so unused levels are
  # dropped, except `positive`, which keeps an all-negative table 2x2.
  used <- unique(c(as.character(x[!is.na(x)]), as.character(y[!is.na(y)])))
  unused <- setdiff(lv, c(used, positive))
  lv <- setdiff(lv, unused)
  if (!is.null(positive)) lv <- c(positive, setdiff(lv, positive))
  ok <- !is.na(x) & !is.na(y)
  dropped <- sum(!ok)
  xs <- factor(as.character(x[ok]), levels = lv)
  ys <- factor(as.character(y[ok]), levels = lv)
  tab <- table(x = xs, y = ys)
  n <- sum(tab)
  k <- length(lv)
  notes <- character(0)
  if (dropped) notes <- c(notes, sprintf("%d item(s) with a missing label left out.", dropped))
  if (length(unused)) {
    notes <- c(notes, sprintf("Factor level(s) neither rater used left out of the table: %s.",
                              paste(unused, collapse = ", ")))
  }
  if (!n) gr_abort("No item has a label from both raters.", class = "gr_bad_setting")
  if (k < 2L) notes <- c(notes, "Only one category was used, so kappa and AC1 are undefined.")

  p <- unclass(tab) / n
  r <- rowSums(p); s <- colSums(p)
  po <- sum(diag(p))
  na2 <- c(NA_real_, NA_real_)

  # Cohen's kappa, with the non-null standard error of Fleiss, Cohen and
  # Everitt (1969).
  pe <- sum(r * s)
  kappa <- kappa_se <- NA_real_
  kappa_ci <- na2
  if (k >= 2L && abs(1 - pe) > 1e-12) {
    kappa <- (po - pe) / (1 - pe)
    term1 <- sum(diag(p) * ((1 - pe) - (s + r) * (1 - po))^2)
    off <- p; diag(off) <- 0
    term2 <- (1 - po)^2 * sum(off * outer(s, r, "+")^2)
    term3 <- (po * pe - 2 * pe + po)^2
    kappa_se <- sqrt(max(0, term1 + term2 - term3) / (n * (1 - pe)^4))
    if (po == 1 || po == 0) {
      # Every resample then agrees completely (or not at all): the interval
      # would be a point that reads as certainty.
      notes <- c(notes, sprintf("The raters %s on every item, so the kappa and AC1 intervals are not estimated.",
                                if (po == 1) "agree" else "disagree"))
    } else if (B > 0) {
      kappa_ci <- kappa_boot_table(as.vector(unclass(tab)), k, n, B, conf, seed)
    }
  }

  # Gwet's AC1 and the variance of Gwet (2008), with pi_k the mean of the two
  # raters' marginals.
  pik <- (r + s) / 2
  ac1 <- ac1_se <- NA_real_
  ac1_ci <- na2
  if (k >= 2L) {
    pe_g <- sum(pik * (1 - pik)) / (k - 1)
    ac1 <- (po - pe_g) / (1 - pe_g)
    v <- po * (1 - po) -
      4 * (1 - ac1) * (sum(diag(p) * (1 - pik)) / (k - 1) - po * pe_g) +
      4 * (1 - ac1)^2 * (sum(p * (1 - outer(pik, pik, "+") / 2)^2) / (k - 1)^2 - pe_g^2)
    ac1_se <- sqrt(max(v, 0) / (n * (1 - pe_g)^2))
    if (n > 1L && po > 0 && po < 1) {
      tq <- stats::qt(1 - (1 - conf) / 2, n - 1L)
      ac1_ci <- c(max(-1, ac1 - tq * ac1_se), min(1, ac1 + tq * ac1_se))
    }
  }

  po_ci <- hr_prop_ci(round(po * n), n, conf = conf)
  map <- function(v) if (k >= 2L) (k * v - 1) / (k - 1) else NA_real_
  row <- function(name, est, se = NA_real_, lo = NA_real_, hi = NA_real_) {
    data.frame(statistic = name, estimate = est, se = se, lower = lo, upper = hi,
               stringsAsFactors = FALSE)
  }
  rows <- list(
    row("observed agreement", po, NA_real_, po_ci$lower, po_ci$upper),
    row("kappa", kappa, kappa_se, kappa_ci[1], kappa_ci[2]),
    row("PABAK", map(po), NA_real_, map(po_ci$lower), map(po_ci$upper)),
    row("AC1", ac1, ac1_se, ac1_ci[1], ac1_ci[2]))
  pi_ <- NA_real_
  if (k == 2L) {
    a <- tab[1, 1]; b <- tab[1, 2]; c <- tab[2, 1]; d <- tab[2, 2]
    pi_ <- (a - d) / n
    rows <- c(rows, list(
      row("prevalence index", pi_),
      row("bias index", (b - c) / n),
      row("positive agreement", if (2 * a + b + c) 2 * a / (2 * a + b + c) else NA_real_),
      row("negative agreement", if (2 * d + b + c) 2 * d / (2 * d + b + c) else NA_real_)))
  } else {
    notes <- c(notes, "PI, BI and specific agreement need two categories; they are left out.")
  }
  if (!is.null(positive)) {
    # y is the reference: sensitivity is x's positives among y's.
    tp <- tab[1, 1]; fp <- sum(tab[1, -1]); fn <- sum(tab[-1, 1]); tn <- n - tp - fp - fn
    rate <- function(name, hits, total) {
      w <- hr_prop_ci(hits, total, conf = conf)
      row(name, w$est, NA_real_, w$lower, w$upper)
    }
    rows <- c(rows, list(rate("sensitivity", tp, tp + fn), rate("specificity", tn, tn + fp),
                         rate("PPV", tp, tp + fp), rate("NPV", tn, tn + fn)))
  }
  stats <- do.call(rbind, rows)
  rownames(stats) <- NULL
  # The small tolerance keeps po = 80 / 100, which sums to 0.7999999999999999
  # in floating point, on the side of the rule it is on.
  flag <- (!is.na(pi_) && abs(pi_) > 0.8) ||
    (!is.na(kappa) && po >= 0.8 - 1e-12 && kappa <= 0.4 + 1e-12)
  structure(list(type = "two_raters", level = "nominal", n = as.integer(n),
                 dropped = as.integer(dropped), categories = lv, table = tab, stats = stats,
                 po = po, kappa = kappa, alpha = NA_real_, paradox_flag = flag,
                 positive = positive, notes = notes, conf = conf,
                 bootstrap = list(B = as.integer(B), seed = seed)),
            class = "hr_agreement")
}

#' Percentile bootstrap interval for kappa on a k x k table.
#'
#' Resampling n items from the table is one multinomial draw of its k^2
#' cells, the same thing as drawing rows and much cheaper. Replicates where
#' kappa is undefined are left out.
#' @noRd
kappa_boot_table <- function(cells, k, n, B, conf, seed) {
  draws <- with_private_rng(seed, stats::rmultinom(B, n, cells / n)) / n
  kap <- apply(draws, 2L, function(v) {
    m <- matrix(v, k, k)
    pe <- sum(rowSums(m) * colSums(m))
    if (abs(1 - pe) < 1e-12) NA_real_ else (sum(diag(m)) - pe) / (1 - pe)
  })
  if (all(is.na(kap))) return(c(NA_real_, NA_real_))
  a <- 1 - conf
  stats::quantile(kap, c(a / 2, 1 - a / 2), names = FALSE, na.rm = TRUE, type = 7)
}

#' @export
print.hr_agreement <- function(x, digits = 3, ...) {
  if (x$type == "two_raters") {
    cat(sprintf("<hr_agreement> two raters, nominal, %d item(s)", x$n))
    if (x$dropped) cat(sprintf(", %d left out", x$dropped))
    cat("\n\nCounts (rows x, columns y):\n")
  } else {
    cat(sprintf("<hr_agreement> %d coders, %s, %d pairable item(s)\n\nCoincidence matrix:\n",
                x$coders, x$level, x$n))
  }
  print(x$table)
  cat("\n")
  st <- x$stats
  num <- vapply(st, is.numeric, logical(1))
  st[num] <- lapply(st[num], round, digits = digits)
  print(st, row.names = FALSE)
  cat(sprintf("\nIntervals at %g%%; bootstrap B = %d, seed %s.\n", 100 * x$conf,
              x$bootstrap$B, format(x$bootstrap$seed)))
  if (x$type == "two_raters") {
    if (!is.null(x$positive)) cat(sprintf("Positive label: %s; y is the reference.\n", x$positive))
    if (isTRUE(x$paradox_flag)) {
      cat("Paradox flag: abs(PI) > 0.8, or po >= 0.8 with kappa <= 0.4. Do not compare this kappa with another sample's.\n")
    }
  }
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}

#' @export
as_json.hr_agreement <- function(x, pretty = TRUE, ...) {
  tab <- unclass(x$table)
  as_json.default(list(
    type = x$type, level = x$level, n = x$n, dropped = x$dropped,
    coders = x[["coders", exact = TRUE]],
    categories = I(as.character(x$categories)),
    # Rows as arrays, so a one-category table is still a matrix in JSON.
    table = lapply(seq_len(nrow(tab)), function(i) I(as.numeric(tab[i, ]))),
    stats = x$stats, po = x$po, kappa = x$kappa, alpha = x$alpha,
    paradox_flag = x$paradox_flag, positive = x$positive, notes = I(x$notes),
    conf = x$conf, bootstrap = x$bootstrap), pretty = pretty, ...)
}
