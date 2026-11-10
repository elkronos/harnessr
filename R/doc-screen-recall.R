# doc-screen-recall.R: recall of the screener against a stated target, with
# bounds that hold at the counts a reference sample actually produces.
#
# The usual reference is every record the screener kept plus a sample of what
# it excluded. The excluded sample nearly always holds zero or one eligible
# record, and at those counts a normal or bootstrap interval says nothing
# useful: with none found every resample also finds none and the interval is
# [1, 1]. So the bounds here are exact. The number of eligible records in a
# sampled stratum is bounded with the hypergeometric distribution of the
# draw, and recall, which falls as that number rises, is bounded by mapping
# the stratum bounds through it.

#' Exact one-sided bounds on the number of eligible records in a finite frame.
#'
#' `x` eligible were found in a simple random sample of `n` from `N`. The
#' upper bound is the largest D for which seeing `x` or fewer still has
#' probability above `alpha`, and the lower bound the smallest D for which
#' seeing `x` or more does. Each holds at 1 - alpha on its own side.
#' @noRd
hyper_bounds <- function(x, n, N, alpha) {
  if (N == 0) return(c(0, 0))
  if (n >= N) return(c(x, x))
  if (n == 0) return(c(0, N))
  D <- seq.int(x, N - (n - x))
  up <- stats::phyper(x, D, N - D, n) > alpha
  lo <- stats::phyper(x - 1, D, N - D, n, lower.tail = FALSE) > alpha
  c(min(D[lo]), max(D[up]))
}

#' K / (K + M), with 0 / 0 read as `empty`.
#' @noRd
recall_of <- function(K, M, empty = NA_real_) {
  if (is.na(K) || is.na(M)) return(NA_real_)
  if (K + M == 0) empty else K / (K + M)
}

#' Stop unless a recall target is one number strictly between 0 and 1.
#' @noRd
check_recall_target <- function(recall_target) {
  if (!is.numeric(recall_target) || length(recall_target) != 1L || is.na(recall_target) ||
      recall_target <= 0 || recall_target >= 1) {
    gr_abort("`recall_target` must be one number strictly between 0 and 1.",
             class = "gr_bad_setting")
  }
  invisible(recall_target)
}

#' NULL, or one whole number of at least `min`.
#' @noRd
check_count_arg <- function(v, name, min = 0) {
  if (is.null(v)) return(NULL)
  if (!is.numeric(v) || length(v) != 1L || is.na(v) || !is.finite(v) || v < min ||
      v != round(v)) {
    gr_abort(sprintf("`%s` must be NULL or one whole number of at least %s.", name, format(min)),
             class = "gr_bad_setting")
  }
  as.numeric(v)
}

#' Recall, records lost and the run's own rates for a calibration.
#'
#' `kept` and `eligible` are the reference rows used, `tab` the screening
#' table with its decisions read. The strata are the screener's kept and
#' excluded records, with sizes counted from `tab`. A stratum is used only when
#' the frame drew from it, and a stratum that was drawn from is treated as a
#' simple random sample of its records, which is what gr_reference() takes.
#' @noRd
screening_recall <- function(of, kept, eligible, tab, recall_target, conf, max_lost) {
  alpha <- 1 - conf
  dec <- tab$decision
  judged <- !is.na(dec)
  screened <- sum(judged)
  N <- c(kept = sum(judged & dec %in% c("include", "unclear")),
         excluded = sum(judged & dec == "exclude"))
  drawn <- c(kept = of %in% c("kept", "all", "unknown", "stacked"),
             excluded = of %in% c("excluded", "all", "unknown", "stacked"))
  n <- c(kept = sum(kept), excluded = sum(!kept))
  x <- c(kept = sum(eligible & kept), excluded = sum(eligible & !kept))
  # A drawn stratum with no row in the sample (an "all" sample that happened
  # to miss every kept record) bounds nothing, which hyper_bounds() gives as
  # 0 to N.
  known <- drawn & (n > 0 | N == 0)

  strata <- data.frame(stratum = names(N), N = unname(N), n = unname(n),
                       eligible = unname(x), stringsAsFactors = FALSE)
  strata$inclusion_prob <- ifelse(N > 0, n / N, NA_real_)
  strata$estimate <- ifelse(known, ifelse(n > 0, N * x / pmax(n, 1), 0), NA_real_)
  b2 <- lapply(names(N), function(h) hyper_bounds(x[[h]], n[[h]], N[[h]], alpha / 2))
  strata$lower <- ifelse(drawn, vapply(b2, `[`, 0, 1), NA_real_)
  strata$upper <- ifelse(drawn, vapply(b2, `[`, 0, 2), NA_real_)
  strata <- strata[drawn, , drop = FALSE]
  rownames(strata) <- NULL

  na_row <- list(estimate = NA_real_, lower = NA_real_, upper = NA_real_, bound = NA_real_)
  recall <- c(na_row, list(method = NA_character_, conf = conf, n = sum(eligible),
                           note = NA_character_))
  if (of == "stacked") {
    # Only strata that were sampled, not judged whole, spend any of alpha. With
    # the kept records judged in full, the whole of it goes to the exclusions.
    sampled <- sum(N > 0 & n < N)
    split <- max(sampled, 1L)
    one <- function(a) lapply(c(kept = "kept", excluded = "excluded"),
                              function(h) hyper_bounds(x[[h]], n[[h]], N[[h]], a / split))
    b1 <- one(alpha); bt <- one(alpha / 2)
    pi <- ifelse(kept, n[["kept"]] / N[["kept"]], n[["excluded"]] / N[["excluded"]])
    est <- hr_ht_estimate(eligible & kept, pi, strata = kept, estimand = "ratio",
                          den = eligible, B = 0, conf = conf)$estimate
    recall$estimate <- est
    recall$lower <- recall_of(bt$kept[1], bt$excluded[2], 0)
    recall$upper <- recall_of(bt$kept[2], bt$excluded[1], 1)
    recall$bound <- recall_of(b1$kept[1], b1$excluded[2], 0)
    recall$method <- if (sampled > 1L) "hypergeometric, Bonferroni over strata" else
      "hypergeometric"
    if (is.na(est)) recall$note <- "No eligible record in the sample, so recall has no estimate."
  } else if (of %in% c("all", "unknown")) {
    # One simple random sample of everything screened: the eligible records in
    # it are a random sample of all eligible records, and the share kept is
    # bounded with Clopper-Pearson (Lewis, Yang and Frieder 2021). That bound
    # treats the frame as infinite. When the sample is every screened record
    # there is no sampling error, recall is known exactly and is its own
    # bound, as hyper_bounds() gives for n = N in the stacked branch.
    tp <- x[["kept"]]; pos <- sum(eligible)
    if (pos > 0 && all(n >= N)) {
      recall$estimate <- recall$lower <- recall$upper <- recall$bound <- tp / pos
      recall$method <- "census"
    } else if (pos > 0) {
      two <- hr_prop_ci(tp, pos, method = "clopper_pearson", conf = conf)
      recall$estimate <- tp / pos
      recall$lower <- two$lower; recall$upper <- two$upper
      recall$bound <- hr_prop_ci(tp, pos, method = "clopper_pearson", side = "lower",
                                 conf = conf)$lower
      recall$method <- "clopper_pearson"
    } else {
      recall$note <- "No eligible record in the sample, so recall has no estimate."
    }
  } else {
    recall$note <- if (of == "excluded") {
      paste0("A sample of the exclusions alone does not count the eligible records ",
             "kept. Judge every kept record as well (gr_reference(of = \"stacked\")).")
    } else {
      paste0("A sample of the kept records holds none of the misses, so it cannot ",
             "estimate recall.")
    }
  }

  lost <- c(na_row, list(frame_n = N[["excluded"]], conf = conf))
  false_exclusion <- list(estimate = NA_real_, lower = NA_real_, upper = NA_real_,
                          n = n[["excluded"]])
  if (known[["excluded"]]) {
    bx2 <- hyper_bounds(x[["excluded"]], n[["excluded"]], N[["excluded"]], alpha / 2)
    bx1 <- hyper_bounds(x[["excluded"]], n[["excluded"]], N[["excluded"]], alpha)
    lost$estimate <- if (n[["excluded"]] > 0)
      N[["excluded"]] * x[["excluded"]] / n[["excluded"]] else 0
    lost$lower <- bx2[1]; lost$upper <- bx2[2]; lost$bound <- bx1[2]
    if (N[["excluded"]] > 0) {
      false_exclusion$estimate <- x[["excluded"]] / n[["excluded"]]
      false_exclusion$lower <- bx2[1] / N[["excluded"]]
      false_exclusion$upper <- bx2[2] / N[["excluded"]]
    }
  }

  # A tiny tolerance, so that a bound landing on the target to the last bit
  # (285 / 300 against 0.95) is not failed by rounding.
  recall_ok <- if (is.na(recall$bound)) NA else recall$bound >= recall_target - 1e-12
  lost_ok <- if (is.null(max_lost) || is.na(lost$bound)) NA else lost$bound <= max_lost
  met <- if (is.na(recall_ok) && is.na(lost_ok)) NA else isTRUE(recall_ok) || isTRUE(lost_ok)
  rule <- c(if (!is.na(recall_ok)) "recall bound", if (!is.na(lost_ok)) "lost bound")
  note <- if (isTRUE(met)) NA_character_ else if (is.na(met)) {
    if (!is.na(recall$note)) recall$note else
      "Nothing in this sample bounds recall or the number of records lost."
  } else {
    paste0(sprintf("The %.0f%% one-sided lower bound on recall is %.1f%%, below the target of %.1f%%.",
                   100 * conf, 100 * recall$bound, 100 * recall_target)[!is.na(recall_ok)],
           if (!is.na(lost_ok) && !is.na(recall_ok)) " " else "",
           sprintf("The %.0f%% upper bound on records lost is %.0f, above the %s allowed.",
                   100 * conf, lost$bound, format(max_lost))[!is.na(lost_ok)])
  }
  verdict <- list(met = met, rule = if (length(rule)) paste(rule, collapse = " or ") else NA_character_,
                  recall_target = recall_target, conf = conf, max_lost = max_lost %||% NA_real_,
                  note = note)

  list(recall = recall, lost = lost, false_exclusion = false_exclusion,
       work_saved = list(estimate = if (screened) N[["excluded"]] / screened else NA_real_,
                         excluded = N[["excluded"]], screened = screened),
       unclear_rate = list(estimate = if (screened) sum(judged & dec == "unclear") / screened
                           else NA_real_,
                           unclear = sum(judged & dec == "unclear"), screened = screened),
       strata = strata, verdict = verdict)
}

#' How many records to judge by hand to show a recall target
#'
#' Sizes a reference sample for [gr_calibrate()] so that, if the sample turns
#' up no missed eligible record, the one-sided bound clears the target at the
#' confidence asked for. One miss or more widens the bound, so treat the
#' result as the least that could be enough.
#'
#' @section A sample of everything screened (`frame = "all"`):
#' Recall is bounded from the eligible records the sample happens to contain.
#' With none of `k` eligible records missed, the one-sided Clopper-Pearson
#' lower bound on recall is alpha^(1/k), where alpha = 1 - `conf`, so the
#' target T is shown once
#'
#'     k >= ln(alpha) / ln(T)
#'
#' eligible records have been judged: 29 for T = 0.90, 59 for 0.95 and 299
#' for 0.99 at 95% confidence (Lewis, Yang and Frieder 2021). Divided by the
#' expected `prevalence` it gives the number of records to draw (59 / 0.05 =
#' 1180). The ten eligible records 0.6.0 asked for support a lower bound of
#' only 0.74, even with all ten found.
#'
#' @section Every kept record plus a sample of the exclusions:
#' With the kept records judged in full (`frame = "stacked"`, or
#' `frame = "excluded"` for the exclusions sample on its own) recall is K /
#' (K + M), where K is the eligible records kept and M those excluded, so a
#' recall target is a cap on M: with K eligible kept, recall T is met when M
#' is at most floor(K (1 - T) / T). Give that cap as `max_lost`, using a pilot
#' estimate of K, and the excluded frame's size as `frame_n`.
#'
#' The exact size is the smallest n for which a frame holding `max_lost` + 1
#' eligible records would show none of them in a sample of n with probability
#' at most alpha, from the hypergeometric distribution. This is the bound
#' [gr_calibrate()] reports. The binomial version, n >= ln(alpha) / ln(1 - u)
#' with u = `max_lost` / `frame_n` (299 for u = 1%), is given beside it; it
#' ignores the finite frame and so asks for a few more records.
#'
#' @section A finite frame:
#' For `frame = "all"`, [gr_calibrate()] bounds a sample smaller than the frame
#' with Clopper-Pearson, which treats the frame as infinite, so the eligible
#' records needed do not fall with the frame's size. When the whole frame is
#' judged, recall is known exactly and is its own bound. So with `frame_n`
#' given, `n` is the binomial draw when it fits in the frame, and otherwise
#' `frame_n` itself: at 95% recall, 95% confidence and 5% prevalence, a frame
#' of 500 records holds about 25 eligible records, fewer than the 59 needed,
#' and only judging all 500 can show the target. `n_exact` is `NA` for
#' `frame = "all"`.
#'
#' @param recall_target The recall to show, strictly between 0 and 1. Used by
#'   `frame = "all"`; for the other frames it enters through `max_lost`.
#' @param conf Confidence level of the one-sided bound.
#' @param prevalence Expected share of eligible records among those drawn,
#'   for `frame = "all"`: turns the eligible records needed into records to
#'   draw. `NULL` leaves the record count `NA`.
#' @param frame `"all"`, `"excluded"` or `"stacked"`, as in [gr_reference()].
#' @param max_lost For `"excluded"` and `"stacked"`: the most eligible
#'   records the screener may have excluded while still meeting the target.
#' @param frame_n Number of records in the frame sampled: the excluded records
#'   for `"excluded"` and `"stacked"`, everything screened for `"all"`, where
#'   with `prevalence` it caps the draw at the whole frame.
#' @return A one-row data frame: the settings, `positives` (eligible records
#'   needed, for `"all"`), `n` (records to draw), `n_binomial`, `n_exact`,
#'   `rule` and `note`.
#' @references
#' Lewis, D. D., Yang, E. and Frieder, O. (2021). Certifying one-phase
#' technology-assisted reviews. *Proceedings of the 30th ACM International
#' Conference on Information and Knowledge Management*, 893-902.
#'
#' Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or fiducial
#' limits illustrated in the case of the binomial. *Biometrika* 26(4), 404-413.
#' @seealso [gr_reference()], [gr_calibrate()]
#' @family corpus functions
#' @export
#' @examples
#' # Eligible records to judge for recall of at least 95%, at 95% confidence.
#' gr_screen_sample_size(0.95, 0.95)
#'
#' # At 5% prevalence that many eligible records means drawing about 1180.
#' gr_screen_sample_size(0.95, 0.95, prevalence = 0.05)
#'
#' # Every kept record judged, 285 of them eligible, and 9000 exclusions: at
#' # most floor(285 * 0.05 / 0.95) = 15 may have been lost.
#' gr_screen_sample_size(frame = "stacked", max_lost = 15, frame_n = 9000)
gr_screen_sample_size <- function(recall_target = 0.95, conf = 0.95, prevalence = NULL,
                                  frame = "all", max_lost = NULL, frame_n = NULL) {
  check_recall_target(recall_target)
  check_conf(conf)
  frame <- lower_text(trimws(as_chr1(frame, "")))
  if (!frame %in% c("all", "excluded", "stacked")) {
    gr_abort(sprintf("`frame` must be \"all\", \"excluded\" or \"stacked\", not '%s'.", frame),
             class = "gr_bad_setting")
  }
  if (!is.null(prevalence) && (!is.numeric(prevalence) || length(prevalence) != 1L ||
                               is.na(prevalence) || prevalence <= 0 || prevalence > 1)) {
    gr_abort("`prevalence` must be NULL or one number in (0, 1].", class = "gr_bad_setting")
  }
  max_lost <- check_count_arg(max_lost, "max_lost", 0)
  frame_n <- check_count_arg(frame_n, "frame_n", 1)
  alpha <- 1 - conf
  # ceiling() with a little slack, so a ratio that is a whole number up to
  # rounding is not pushed to the next one.
  up <- function(v) ceiling(v - 1e-9)
  positives <- n <- n_binomial <- n_exact <- NA_real_
  note <- NA_character_
  if (frame == "all") {
    positives <- up(log(alpha) / log(recall_target))
    rule <- "zero misses among the eligible: k >= ln(alpha) / ln(T)"
    if (!is.null(prevalence)) {
      n <- n_binomial <- up(positives / prevalence)
      if (!is.null(frame_n) && n_binomial > frame_n) {
        # gr_calibrate() bounds a sample smaller than the frame with
        # Clopper-Pearson, which needs `positives` eligible records whatever
        # the frame's size. A frame too small to hold them can only show the
        # target by being judged whole, when recall is known exactly.
        n <- frame_n
        note <- sprintf(paste0("The binomial draw (%s) is larger than the frame (%s), which holds ",
                               "about %s eligible records, fewer than the %s needed. Only judging ",
                               "every record (n = Inf in gr_reference()) can show the target; ",
                               "recall is then known exactly."),
                        format(n_binomial), format(frame_n),
                        format(round(prevalence * frame_n, 1)), format(positives))
      }
    } else {
      note <- "Give `prevalence` to turn the eligible records needed into records to draw."
    }
  } else {
    if (is.null(max_lost) || is.null(frame_n)) {
      gr_abort(paste0("For a sample of the exclusions give `max_lost` and `frame_n`. With K ",
                      "eligible records among those kept, recall T allows at most ",
                      "floor(K * (1 - T) / T) lost."), class = "gr_bad_setting")
    }
    rule <- "zero misses in the excluded sample: hypergeometric, finite frame"
    if (max_lost >= frame_n) {
      n_exact <- 0
      n_binomial <- 0
      note <- "`max_lost` is at least the frame, so no sample is needed."
    } else {
      d <- max_lost + 1
      sizes <- seq_len(frame_n - d + 1)
      n_exact <- as.numeric(sizes[which(stats::phyper(0, d, frame_n - d, sizes) <= alpha)[1]])
      n_binomial <- if (max_lost == 0) Inf else up(log(alpha) / log(1 - max_lost / frame_n))
      if (max_lost == 0) {
        note <- "With no loss allowed the binomial rule has no finite size; use the exact one."
      }
    }
    n <- n_exact
  }
  data.frame(frame = frame, recall_target = recall_target, conf = conf,
             prevalence = prevalence %||% NA_real_, max_lost = max_lost %||% NA_real_,
             frame_n = frame_n %||% NA_real_, positives = positives, n = n,
             n_binomial = n_binomial, n_exact = n_exact, rule = rule, note = note,
             stringsAsFactors = FALSE)
}
