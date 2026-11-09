# doc-screen-calibrate.R -- how often the screener is wrong, measured rather
# than assumed.
#
# WHY THIS FILE EXISTS
# Everything else here makes a run auditable: what was read, what was cited,
# what could not be verified. None of it says whether the screening DECISIONS
# were any good, and no amount of provenance substitutes for that. A screener
# that excludes a fifth of the eligible studies produces a beautifully audited
# review of the wrong corpus.
#
# The tempting substitute is agreement between two model passes. It measures the
# wrong thing. Two passes of one model share weights, priors and blind spots, so
# their errors are correlated: they agree most confidently exactly where they are
# both wrong, and a high figure would read as reliability while meaning
# self-consistency. Repeated sampling does help with careless reasoning, and it
# does nothing for a systematic misreading -- and which of those you have is not
# knowable from the passes themselves.
#
# Only a reference standard settles it. Screen a sample by hand, compare, and
# report what that sample can support. That is also the number a methods section
# needs, and the one a reader can argue with.
#
# WHY PREVALENCE MAKES ACCURACY USELESS HERE
# Inclusion rates in a real search run at a few per cent. A screener that
# excluded everything would be about 95% accurate and would find nothing. So
# accuracy is not reported. Sensitivity is, because a missed study is invisible
# and permanent; specificity is, because it is what the saved effort is made of;
# and Cohen's kappa is, because it is the one that notices the do-nothing
# screener.

#' The decisions a person can record, and what they mean here.
#' @noRd
.gr_reference_decisions <- c("include", "exclude")

#' The widest interval a one-stratum sample's headline rate may have and still
#' be called adequate: ten percentage points, a margin of five either way.
#' @noRd
.gr_frame_max_width <- 0.10

#' Draw a sample to screen by hand
#'
#' Picks documents out of a [gr_screen()] run for a person to judge without
#' seeing what the model said, and writes them to a CSV to fill in. Feeding the
#' completed file back to [gr_calibrate()] is what turns "we used an LLM" into a
#' claim with a number attached.
#'
#' @section Which rows to sample:
#' `of = "excluded"` is usually the right answer and is not the obvious one.
#' Sensitivity failures hide among the exclusions: a study the screener threw
#' away is gone, and nothing downstream will ever mention it, while the records
#' it kept are going to be read by a person anyway. Sampling everything at a
#' realistic inclusion rate spends most of the sample confirming exclusions that
#' were never in doubt, and leaves two or three positives to estimate
#' sensitivity from, which is no estimate at all.
#'
#' The design that matches how people actually work is to judge *every* record
#' the screener kept, plus a sample of what it discarded. `of = "stacked"` draws
#' exactly that in one sheet: every kept record, and `n` of the excluded ones.
#' Each row records its stratum and its inclusion probability (1 for a kept
#' record, `n` / N for an excluded one, N being the number excluded), and
#' [gr_calibrate()] weights each stratum by it to estimate recall. Drawn as two
#' sheets (`of = "kept"` with `n = Inf`, and `of = "excluded"`) and stacked by
#' hand, the same reference needs `of = "stacked"` in [gr_calibrate()].
#' [gr_screen_sample_size()] says how large `n` should be.
#' [gr_calibrate()] knows which frame it was given and will not compute a
#' corpus-wide figure from a sample that cannot support one.
#'
#' A blind stacked sheet keeps each row's stratum and probability inside the
#' `sampled_from` key, one key per row, so that neither gives away what the
#' model decided; the rows are in the run's order, not grouped by stratum.
#'
#' @section The file:
#' The CSV is written as UTF-8 with a byte-order mark, which is what makes
#' Excel open accented names and titles correctly; save it back as "CSV UTF-8".
#' [gr_calibrate()] reads it the same way in any locale, reads a sheet a
#' spreadsheet re-saved as Windows-1252 as that, and matches a row whose name
#' still does not agree by its `document_id`.
#'
#' @param screening A `gr_screening` from [gr_screen()].
#' @param n How many to draw: a whole number of at least 1. `Inf` takes the
#'   whole frame, as does any `n` larger than it. For `of = "stacked"`, how
#'   many of the excluded records to draw; the kept ones are all taken.
#' @param of Which rows to sample from: `"excluded"`, `"kept"` (include and
#'   unclear), `"all"`, or `"stacked"` (every kept record and a sample of the
#'   excluded ones).
#' @param seed A seed for the draw, so it is reproducible: the sample is drawn
#'   after `set.seed(seed)` and your session's random number stream is put back
#'   afterwards. A calibration sample is part of the method and has to be
#'   re-drawable.
#' @param path Where to write the CSV. `NULL` returns the frame without writing.
#' @param blind Leave the model's decision and reason out of the file. On by
#'   default: a person shown the answer agrees with it, and the resulting figure
#'   measures nothing. A blind sheet does not name its frame either, since
#'   "excluded" on every row says what the model decided: `sampled_from` holds
#'   an opaque key that [gr_calibrate()] reads back as the frame and its size.
#'   With `blind = FALSE` the file has `model_decision`, `model_reason`, and the
#'   frame in plain words (`sampled_from`, `frame_n`, `screened_n`, and for a
#'   stacked sheet `stratum` and `inclusion_prob`, with `frame_n` the size of
#'   the row's stratum).
#' @param frame The same as `of`, under the name [gr_screen_sample_size()]
#'   uses. Give one or the other.
#' @param reviewers How many people will judge each record. Above 1 the sheet
#'   has one decision column per reviewer, `human_decision_1` to
#'   `human_decision_<reviewers>`, in place of `human_decision`, and a
#'   `consensus` column for an adjudicator to fill where they disagree. See
#'   [gr_reference_consensus()] for how their decisions become one.
#' @return A data frame of class `gr_reference_frame`, invisibly when written.
#'   The `human_decision` column is empty and is yours to fill with `include` or
#'   `exclude` (with several reviewers, each `human_decision_<reviewer>`
#'   column is).
#' @seealso [gr_calibrate()], [gr_reference_consensus()], [gr_screen()]
#' @family corpus functions
#' @export
#' @examples
#' tab <- data.frame(document = paste0("d", 1:6, ".pdf"),
#'                   decision = c("include", "exclude", "exclude",
#'                                "unclear", "exclude", "include"),
#'                   reason = "because", stringsAsFactors = FALSE)
#' gr_reference(structure(list(table = tab), class = "gr_screening"),
#'              n = 3, of = "excluded", seed = 1)
#'
#' # Every kept record, and two of the four excluded ones.
#' gr_reference(structure(list(table = tab), class = "gr_screening"),
#'              n = 2, of = "stacked", seed = 1, blind = FALSE)
gr_reference <- function(screening, n = 50, of = c("excluded", "kept", "all", "stacked"),
                         seed = NULL, path = NULL, blind = TRUE, frame = NULL,
                         reviewers = 1L) {
  if (!is.null(frame)) {
    frame <- match.arg(frame, c("excluded", "kept", "all", "stacked"))
    if (!missing(of) && !identical(match.arg(of), frame)) {
      gr_abort(sprintf("`frame = \"%s\"` and `of = \"%s\"` name different frames; give one.",
                       frame, match.arg(of)), class = "gr_bad_setting")
    }
    of <- frame
  }
  of <- match.arg(of)
  rv <- suppressWarnings(as.numeric(reviewers))
  if (length(rv) != 1L || is.na(rv) || !is.finite(rv) || rv < 1 || rv != floor(rv)) {
    gr_abort("`reviewers` must be a single whole number of at least 1.", class = "gr_bad_setting")
  }
  # A number, compared as a number, for the reason min_positives is below:
  # `"5" >= 30` is TRUE because R compares as strings, so n = "5" from a config
  # file took the whole frame, and NA stopped with "missing value where
  # TRUE/FALSE needed".
  n_num <- suppressWarnings(as.numeric(n))
  if (length(n_num) != 1L || is.na(n_num) || n_num < 1 ||
      (is.finite(n_num) && n_num != floor(n_num))) {
    gr_abort(sprintf("`n` must be a single whole number of at least 1, or Inf; got %s.",
                     paste(format(n), collapse = ", ")), class = "gr_bad_setting")
  }
  n <- n_num
  tab <- as_screening_table(screening)
  # A row with no decision was never read. It is not an exclusion and cannot be
  # compared with a human judgement of the document's eligibility.
  judged <- !is.na(tab$decision)
  is_kept <- judged & tab$decision %in% c("include", "unclear")
  in_frame <- switch(of,
                     excluded = judged & tab$decision == "exclude",
                     kept     = is_kept,
                     all      = judged,
                     stacked  = judged)
  pool <- tab[in_frame, , drop = FALSE]
  if (!nrow(pool)) {
    gr_abort(sprintf("No rows to sample: nothing in this run was %s.",
                     switch(of, excluded = "excluded", kept = "kept", "screened")),
             class = "gr_no_reference_frame")
  }
  draw <- function(idx, size) {
    if (is.infinite(size) || size >= length(idx)) return(idx)
    # with_private_rng(), not withr::with_seed(): withr is only suggested, so a
    # default install stopped here with "there is no package called 'withr'".
    # It is the same draw -- set.seed() under the session's RNG kind, the
    # caller's stream restored afterwards -- so a seed keeps its sample.
    # idx[sample.int()] rather than sample(idx): sample() of one number draws
    # from 1:idx instead.
    pick <- function() idx[sample.int(length(idx), size)]
    if (is.null(seed)) pick() else with_private_rng(seed, pick())
  }
  if (of == "stacked") {
    # Every kept record, and `n` of the excluded ones. The rows stay in the
    # run's order, so where a row sits on the sheet does not say which stratum
    # it came from.
    pool_kept <- is_kept[in_frame]
    n_strata <- c(kept = sum(pool_kept), excluded = sum(!pool_kept))
    take <- c(which(pool_kept), draw(which(!pool_kept), n))
    drawn_strata <- c(kept = n_strata[["kept"]],
                      excluded = length(take) - n_strata[["kept"]])
  } else {
    take <- draw(seq_len(nrow(pool)), n)
  }
  take <- sort(take)
  out <- pool[take, , drop = FALSE]

  keep <- intersect(c("document", "document_id", "title", "authors", "year"), names(out))
  ref <- out[, keep, drop = FALSE]
  if (!blind) {
    ref$model_decision <- out$decision
    ref$model_reason <- out$reason
  }
  ref$human_decision <- NA_character_
  ref$human_note <- NA_character_
  # As a COLUMN, not only an attribute, because the file is the thing that gets
  # emailed, opened in Excel and read back a fortnight later, and an attribute
  # does not survive any of that. Without it a sample of exclusions comes back
  # looking like a sample of everything, and gr_calibrate() would then report a
  # sensitivity of 0% and a specificity of 100% -- both artifacts of the frame.
  # screened_n as a column for the same reason, which it was missing: without
  # it gr_calibrate() fell back to nrow(tab), which counts rows the screener
  # never decided, and the printed denominator quietly changed meaning between
  # the in-memory frame and the file read back.
  #
  # In a blind sheet the three travel as one opaque key. Written out plainly,
  # sampled_from = "excluded" on every row told the person filling it in that
  # the model had rejected each record -- the answer `blind` exists to keep from
  # them -- and frame_n against screened_n said the same by its ratio.
  if (of == "stacked") {
    # Each row says which stratum it came from and with what probability, the
    # design weights gr_calibrate() estimates recall with. A blind sheet keeps
    # them inside a key per row, padded to one length: a stratum written out,
    # or an inclusion probability of 1, would tell the person which records
    # the model kept.
    stratum <- ifelse(pool_kept[take], "kept", "excluded")
    size <- unname(n_strata[stratum])
    got <- unname(drawn_strata[stratum])
    if (blind) {
      ref$sampled_from <- vapply(seq_along(stratum), function(i) {
        stacked_key(stratum[i], size[i], got[i], sum(judged), out$document[i])
      }, character(1))
    } else {
      ref$sampled_from <- "stacked"
      ref$stratum <- stratum
      ref$inclusion_prob <- got / size
      ref$frame_n <- size
      ref$screened_n <- sum(judged)
    }
  } else if (blind) {
    ref$sampled_from <- frame_key(of, nrow(pool), sum(judged), out$document)
  } else {
    ref$sampled_from <- of
    ref$frame_n <- nrow(pool)
    ref$screened_n <- sum(judged)
  }
  if (rv > 1) {
    # One decision column per reviewer, and one for an adjudicator, in place of
    # the single `human_decision`: each person fills their own column, and the
    # document stays on one row, so a sheet split between reviewers and put
    # back together cannot count a record twice.
    at <- match("human_decision", names(ref))
    dec <- stats::setNames(rep(list(NA_character_), rv), paste0("human_decision_", seq_len(rv)))
    ref <- cbind(ref[, seq_len(at - 1L), drop = FALSE], as.data.frame(dec),
                 consensus = NA_character_, ref[, -seq_len(at), drop = FALSE],
                 stringsAsFactors = FALSE)
  }
  rownames(ref) <- NULL
  attr(ref, "of") <- of
  attr(ref, "frame_n") <- nrow(pool)
  attr(ref, "screened_n") <- sum(judged)
  attr(ref, "seed") <- seed
  class(ref) <- c("gr_reference_frame", "data.frame")
  # See `[.gr_reference_frame` below: subsetting a classed data frame keeps the
  # class and drops every other attribute, so a column subset used to hand
  # gr_calibrate() a frame that still claimed to know where it came from.

  if (!is.null(path)) {
    write_reference_csv(ref, path)
    gr_msg(sprintf(paste0("Wrote %d row(s) to '%s'. Fill in `human_decision` with 'include' or ",
                          "'exclude', then read it back with gr_calibrate()."),
                   nrow(ref), path))
    return(invisible(ref))
  }
  ref
}

#' @noRd
as_screening_table <- function(screening) {
  tab <- if (inherits(screening, "gr_screening")) screening$table else screening
  if (!is.data.frame(tab) || !nrow(tab)) {
    gr_abort("`screening` must be a gr_screening, or a data frame shaped like its $table.",
             class = "gr_bad_screening")
  }
  if (is.null(tab$document) || is.null(tab$decision)) {
    gr_abort("`screening` needs `document` and `decision` columns.", class = "gr_bad_screening")
  }
  # Read back the way the human decisions are. A table saved with
  # write.csv(na = "") -- the convention gr_reference() uses -- comes back with
  # "" where a document was never read, and a spreadsheet capitalises; kept
  # as they were, every value other than "include" and "unclear" counted as an
  # exclusion, so unread documents a person judged eligible were listed in
  # `missed` as studies the screener threw away.
  # to_utf8() first: lower_text() needs text it can decode, and it turns NA
  # into "", which is then NA again below.
  # The screener's decision, not a person's. Once gr_resolve() has settled a
  # record, `decision` holds what the person said and `screener_decision` what
  # the model said; calibrated on the first, the screener was credited with
  # every call a person had already corrected.
  dec <- lower_text(trimws(to_utf8(tab$screener_decision %||% tab$decision)))
  dec[!nzchar(dec)] <- NA_character_
  bad <- !is.na(dec) & !dec %in% c("include", "exclude", "unclear")
  if (any(bad)) {
    gr_abort(sprintf(paste0("`decision` must be 'include', 'exclude', 'unclear' or empty (never ",
                            "read); found %s."),
                     paste(sprintf("'%s'", utils::head(unique(dec[bad]), 5)), collapse = ", ")),
             class = "gr_bad_screening")
  }
  # A row the run could not read has no decision whatever the column says.
  if (!is.null(tab$status)) {
    st <- lower_text(trimws(to_utf8(tab$status)))
    dec[nzchar(st) & !st %in% c("ok", "restored", "duplicate")] <- NA_character_
  }
  tab$decision <- dec
  # Duplicates were decided once, under the row they repeat. Blank is not a
  # duplicate: read back from a CSV, a non-duplicate's NA is "".
  if (!is.null(tab$duplicate_of)) {
    dup <- as.character(tab$duplicate_of)
    tab <- tab[is.na(dup) | !nzchar(trimws(dup)), , drop = FALSE]
  }
  tab
}

#' Measure the screener against a hand-screened sample
#'
#' Compares [gr_screen()]'s decisions with a person's on the same documents, and
#' reports what that sample supports: how much of the eligible literature the
#' screener kept, how much of the irrelevant literature it removed, and how much
#' reading it saved. Each comes with an interval, and each is refused when the
#' sample is too small to say.
#'
#' @section Two sensitivities, and the gap between them:
#' `"unclear"` is a deferral, not a miss. A record the screener could not settle
#' goes to a person, so it is not lost, and counting it as a failure would
#' punish the screener for the one behaviour that makes it safe.
#'
#' So two figures are reported. **Sensitivity as deployed** asks what fraction of
#' the eligible studies survived: kept, whether by `"include"` or by
#' `"unclear"`. That is the number that matters, because it is the one where a
#' shortfall is permanent. **Strict sensitivity** asks what fraction were
#' actively included. The gap between them is the reading a person still has to
#' do, and reporting only the first would flatter a screener that defers
#' everything.
#'
#' @section Why accuracy is not reported:
#' Inclusion rates run at a few per cent, so a screener that excluded every
#' record would score around 95% accurate and find nothing. Chance-corrected
#' agreement is reported instead, and never as one number.
#'
#' @section Agreement, on the decision that matters:
#' The primary agreement table is the one sensitivity uses: kept (`"include"`
#' or `"unclear"`) against excluded, by the person's eligible against not. An
#' `"unclear"` on an eligible record is agreement there, since the record was
#' kept. The secondary table is strict: `"include"` against everything else.
#'
#' Each table reports Cohen's kappa beside the statistics that say whether it
#' can be read: the prevalence index (PI) and bias index (BI) of Byrt et al.
#' (1993), the prevalence- and bias-adjusted kappa (PABAK, 2 po - 1) and
#' Gwet's AC1, with intervals, and the class-wise sensitivity, specificity,
#' PPV and NPV. At a few eligible records in a hundred, kappa moves with the
#' marginals as much as with agreement, and can sit near zero where the two
#' raters agree on almost every record; `$agreement$kept$paradox` is `TRUE`
#' when abs(PI) is above 0.8, a heuristic threshold that marks such a table.
#' AC1 has the opposite weakness, a value near 1 from records both raters
#' left out, so it is not read alone either.
#'
#' The kappa interval is a percentile bootstrap that resamples documents,
#' B = 2000, under a fixed seed so the same sample gives the same interval
#' (`$agreement$kept$bootstrap` holds B and the seed; the session's random
#' stream is left as it was). The AC1 interval uses the variance of Gwet
#' (2008), as the irrCAC package does, with a t quantile on n - 1 degrees of
#' freedom. The PABAK interval is the Wilson interval on the observed
#' agreement, mapped onto the same scale. Where the two raters agree on every
#' record, disagree on every record, or the sample has fewer than 10 records,
#' the kappa and AC1 intervals would be a point or close to one, so they are
#' left empty and `$agreement$kept$note` says why.
#'
#' 0.6.0 computed kappa on the screener's three labels against the person's
#' two, so every `"unclear"` counted as a disagreement. That figure is kept as
#' `$kappa_legacy` for this release only, so a number already quoted can be
#' traced; it is not the screener's agreement with a person.
#'
#' The rate of `"unclear"` decisions is the metric `"deferred to a person"`,
#' with its interval, and the 3x2 counts behind both tables are in
#' `$decisions`.
#'
#' A decision a person settled with [gr_resolve()] is not the screener's, so
#' the comparison uses the screener's own decision, from
#' `screener_decision`, wherever the table has one.
#'
#' @section What a small sample cannot do:
#' Sensitivity is estimated from the eligible studies in the sample and from
#' nothing else. Twelve hand-screened records containing two eligible studies
#' estimate it from two observations, and "1.00" from two observations is not a
#' finding. The intervals are Wilson score intervals, which stay sensible at
#' zero and one where the textbook interval collapses to a point, and
#' `$adequate` says whether there was enough to support a claim at all.
#'
#' What "enough" means depends on the frame, because what the headline rate
#' rests on does. In an `"all"` sample it is sensitivity, estimated from the
#' eligible studies alone, so the sample needs `min_positives` of them. In an
#' `"excluded"` or `"kept"` sample the headline rate ("eligible among the
#' excluded", "eligible among those kept") is taken over every row sampled, so
#' a sample of 500 clean exclusions is a good one, not one resting on no
#' observations. There the sample is adequate when that rate's interval is at
#' most 10 percentage points wide, or when every record in the stratum was
#' judged (nothing is left to sample, and the rate is a count for this run).
#' The bar is a floor, not a verdict: 10 points is wide for an omission rate
#' near zero across a large pile of exclusions, and the projected count of lost
#' studies, printed with its interval, is the figure to judge that by.
#' `$adequacy$note` says in a sentence why a sample fell short.
#'
#' @section Recall against a target:
#' Every calibration also reports recall, the share of eligible records the
#' screener kept, against `recall_target`, with bounds that stay valid at the
#' zero or one misses a reference usually finds.
#'
#' On a stacked reference (every kept record, and a simple random sample of n
#' of the N excluded ones; `of = "stacked"`) the eligible count is K among the
#' kept and x in the sample, and recall is estimated with the design weights,
#' the ratio of Horvitz-Thompson totals from [hr_ht_estimate()]:
#' K / (K + M), with M = N x / n the projected number of eligible records
#' excluded. M is bounded exactly from the hypergeometric distribution of x:
#' its upper bound M_U is the largest M for which drawing x or fewer has
#' probability above alpha = 1 - `conf`, and the lower bound the smallest M
#' for which drawing x or more does. Recall falls as M rises, so its one-sided
#' lower bound is K / (K + M_U). If the kept records were sampled too, each
#' sampled stratum is bounded the same way with alpha split equally between
#' them (Bonferroni). The interval in `$recall` is two-sided at `conf`, with
#' alpha / 2 on each side; `$recall$bound` is the one-sided bound at `conf`.
#' No bootstrap is used: with x = 0 every resample also gives M = 0, and the
#' interval would be `[1, 1]`.
#'
#' On a sample of everything screened (`"all"`) the eligible records in the
#' sample are a random sample of all of them, and recall is the share kept
#' with a Clopper-Pearson bound (Lewis, Yang and Frieder 2021). A sample of
#' the exclusions alone bounds M and the false-exclusion rate but not recall,
#' since it does not count the eligible records kept, and a sample of the
#' kept records alone holds none of the misses.
#'
#' The verdict in `$verdict` says the target is met when the one-sided lower
#' bound on recall is at least `recall_target`, or, when `max_lost` is given,
#' when the upper bound on M is at most `max_lost`. On a stacked reference
#' this verdict is also `$adequate`.
#'
#' Weights come from the run: N is the number of records the screening
#' excluded (or kept), and n the rows of that stratum with a human decision.
#' On a complete sheet that is the inclusion probability the sheet records; a
#' sheet whose recorded probabilities disagree is weighted by the run, with a
#' warning. Agreement statistics are not computed on a stacked reference,
#' since unweighted they are distorted in the same direction as unweighted
#' sensitivity.
#'
#' @section One row per document:
#' The reference is matched to the screening by document name, compared as
#' UTF-8 whatever the session's locale, and by `document_id` for a row whose
#' name still does not match. A document judged twice (two sheets stacked
#' with no `reviewer` column, say) is counted once when the copies agree, with
#' a warning, and is refused when they disagree.
#'
#' @section Several reviewers:
#' A sheet with one `human_decision_<reviewer>` column per reviewer (from
#' `gr_reference(reviewers = k)`), or a long sheet with a `reviewer` column, is
#' compared on the reviewers' consensus. Where it has been formed with
#' [gr_reference_consensus()] that is used; otherwise records the reviewers
#' agreed on take their decision, records they disagreed on take the
#' `consensus` column, and the calibration stops if any disagreement has none,
#' saying how many there were.
#'
#' `$reviewers` then reports how far the people agree with each other, the
#' yardstick for the screener's agreement with them, with
#' [hr_agreement()]: for every pair of reviewers the observed agreement,
#' Cohen's kappa, PABAK, Gwet's AC1 and the prevalence and bias indices, never
#' kappa alone, and with three reviewers or more Krippendorff's alpha over all
#' of them. It also reports each reviewer's sensitivity and specificity
#' against the consensus, the share of consensus-eligible records they
#' included and of consensus-ineligible records they excluded, which says what
#' one person screening alone would have missed. A reviewer is scored on the
#' records they judged. Note that a reviewer is part of the consensus they
#' are scored against, so these figures are higher than against an
#' independent reference, and more so with fewer reviewers.
#'
#' On a stacked reference both are weighted the way recall is, each record by
#' N_h / n_h for its stratum h (the screener's kept or excluded records), so
#' they describe every record screened rather than the sample. Sensitivity
#' is sum_h (N_h / n_h) a_h / sum_h (N_h / n_h) (a_h + b_h), with a_h the
#' consensus-eligible records the reviewer included in stratum h and b_h those
#' they excluded; its interval bounds each count in a sampled stratum exactly
#' with the hypergeometric distribution, alpha split equally over them
#' (Bonferroni), and maps them through the ratio, which rises with a and falls
#' with b. Specificity is the same with the consensus-ineligible records.
#' Agreement is computed on the 2x2 table built with the same weights, with
#' percentile intervals from a bootstrap within each sampled stratum
#' (B = 2000, seed 1), and [hr_agreement()] is also reported within each
#' stratum. The weighted kappa interval is approximate and runs narrow when
#' the sampled exclusion stratum holds fewer than about 100 records (near 80%
#' coverage for a nominal 95% at 30), and `$reviewers$notes` says so; the
#' observed agreement, PABAK and AC1 intervals hold up better there. On any other
#' frame the sample is one simple random sample, the figures are unweighted,
#' and sensitivity and specificity have Wilson intervals, as in `$metrics`.
#'
#' @param screening A `gr_screening` from [gr_screen()], or a data frame shaped
#'   like its `$table`, for instance read back from a CSV. Its `decision` must
#'   be `"include"`, `"exclude"`, `"unclear"` or empty (never read), in any
#'   case; a row whose `status` says it was not read counts as never read.
#' @param reference The completed frame from [gr_reference()], a path to the
#'   filled-in CSV, or any data frame with `document` and `human_decision`
#'   (or one `human_decision_<reviewer>` column per reviewer; see "Several
#'   reviewers").
#' @param positive Which human decision counts as eligible: `"include"` or
#'   `"exclude"`.
#' @param of Which part of the screening run the reference was drawn from:
#'   `"excluded"`, `"kept"`, `"all"` or `"stacked"`; anything else is an
#'   error. `"stacked"` also reads a kept sheet and an excluded sheet stacked
#'   with `rbind()` as one stratified reference. Normally
#'   recovered from the file [gr_reference()] wrote; give it explicitly for a
#'   reference built by hand. Given over a file that records a different
#'   frame, it wins with a warning, and the file's frame size is not used.
#' @param min_positives For an `"all"` sample: below this many eligible studies
#'   the sensitivity estimate is reported but marked inadequate. A sample of
#'   one stratum is judged by its interval instead; see "What a small sample
#'   cannot do".
#' @param recall_target The recall the screener should reach, strictly between
#'   0 and 1.
#' @param conf Confidence level of the recall and loss bounds.
#' @param max_lost Optional: the most eligible records the screener may have
#'   excluded. When given, an upper bound on records lost at or below it also
#'   meets the target.
#' @return An object of class `gr_calibration`:
#'   \describe{
#'     \item{`counts`}{The confusion matrix, as kept/excluded by eligible/not.}
#'     \item{`metrics`}{One row per statistic: `estimate`, `lower`, `upper`, `n`.}
#'     \item{`kappa`}{Cohen's kappa on kept against excluded; `NA` for a
#'       sample of one stratum.}
#'     \item{`agreement`}{`kept` (the primary table) and `strict` (include
#'       against the rest), each a list of `table`, `n`, `stats` (one row per
#'       statistic: `statistic`, `estimate`, `lower`, `upper`) and `paradox`.
#'       `NULL` for a sample of one stratum.}
#'     \item{`kappa_legacy`}{Deprecated: the 0.6.0 kappa on the screener's
#'       three labels against the person's two. Removed in the next release.}
#'     \item{`decisions`}{The 3x2 counts: the screener's include, unclear and
#'       exclude by the person's eligible and not.}
#'     \item{`missed`}{The eligible studies the screener excluded: the rows
#'       themselves, because a list of the misses says more than a rate.}
#'     \item{`disagreements`}{Every row where the two differ, in either
#'       direction.}
#'     \item{`adequate`}{Whether the sample supports a claim from its frame's
#'       headline rate: sensitivity in an `"all"` sample, the frame's own rate
#'       in an `"excluded"` or `"kept"` one.}
#'     \item{`adequacy`}{How that was judged: `rule` (`"positives"`,
#'       `"interval"` or `"whole frame"`), `bar`, `width`, and `note`, a
#'       sentence saying why the sample fell short (`NA` when it did not).}
#'     \item{`frame`}{Which rows the sample was drawn from, and how many.}
#'     \item{`recall`}{Recall: `estimate`, `lower` and `upper` (two-sided at
#'       `conf`), `bound` (the one-sided lower bound), `method`, `conf`, `n`
#'       (eligible records in the sample) and `note`. `NA` where the frame
#'       cannot estimate it.}
#'     \item{`lost`}{M, the projected number of eligible records excluded:
#'       `estimate`, `lower`, `upper`, `bound` (the one-sided upper bound),
#'       `frame_n` (records excluded) and `conf`.}
#'     \item{`false_exclusion`}{The share of excluded records that are
#'       eligible: `estimate`, `lower`, `upper` (exact) and `n`.}
#'     \item{`work_saved`}{The share of screened records the screener
#'       excluded, which nobody reads: `estimate`, `excluded`, `screened`.}
#'     \item{`unclear_rate`}{The share of screened records left unclear:
#'       `estimate`, `unclear`, `screened`.}
#'     \item{`strata`}{One row per stratum the frame drew from: `N`, `n`,
#'       `eligible`, `inclusion_prob`, and the estimated eligible count with
#'       its exact two-sided bounds.}
#'     \item{`verdict`}{`met` (`TRUE`, `FALSE`, or `NA` when nothing bounds
#'       recall or M), `rule`, `recall_target`, `conf`, `max_lost` and
#'       `note`.}
#'     \item{`reviewers`}{Only for a sheet with several reviewers:
#'       `reviewers` (their labels), `n_reviewers`, `rule` (how the consensus
#'       was formed), `conflicts` (documents they disagreed on), `consensus`
#'       (how each document's consensus was reached, counted), `weighted`,
#'       `sensitivity` (one row per reviewer and statistic: `estimate`,
#'       `lower`, `upper`, `n`, `method`), `agreement` (one row per pair of
#'       reviewers, scope and statistic, the scope being the frame, a stratum
#'       or `"weighted"`), `notes` and `conf`.}
#'   }
#' @references
#' Lewis, D. D., Yang, E. and Frieder, O. (2021). Certifying one-phase
#' technology-assisted reviews. *Proceedings of the 30th ACM International
#' Conference on Information and Knowledge Management*, 893-902.
#'
#' Horvitz, D. G. and Thompson, D. J. (1952). A generalization of sampling
#' without replacement from a finite universe. *Journal of the American
#' Statistical Association* 47(260), 663-685.
#'
#' Byrt, T., Bishop, J. and Carlin, J. B. (1993). Bias, prevalence and kappa.
#' *Journal of Clinical Epidemiology* 46(5), 423-429.
#'
#' Gwet, K. L. (2008). Computing inter-rater reliability and its variance in
#' the presence of high agreement. *British Journal of Mathematical and
#' Statistical Psychology* 61(1), 29-48.
#' @seealso [gr_reference()], [gr_reference_consensus()], [gr_screen_sample_size()], [gr_screen()],
#'   [gr_audit_report()]
#' @family corpus functions
#' @export
#' @examples
#' tab <- data.frame(document = paste0("d", 1:8, ".pdf"),
#'                   decision = c("include", "include", "unclear", "exclude",
#'                                "exclude", "exclude", "include", "exclude"),
#'                   stringsAsFactors = FALSE)
#' ref <- data.frame(document = paste0("d", 1:8, ".pdf"),
#'                   human_decision = c("include", "exclude", "include", "exclude",
#'                                      "exclude", "include", "include", "exclude"),
#'                   stringsAsFactors = FALSE)
#' gr_calibrate(structure(list(table = tab), class = "gr_screening"), ref)
gr_calibrate <- function(screening, reference, positive = "include", min_positives = 10L,
                         of = NULL, recall_target = 0.95, conf = 0.95, max_lost = NULL) {
  check_recall_target(recall_target)
  check_conf(conf)
  max_lost <- check_count_arg(max_lost, "max_lost", 0)
  tab <- as_screening_table(screening)
  ref <- read_reference(reference)
  # Several reviewers: one row per document with their consensus in
  # `human_decision`, the reviewers' own decisions kept beside it.
  panel <- reviewer_panel(ref)
  if (!is.null(panel)) ref <- panel
  # Normalised the way the human decisions are. A positive the decisions can
  # never equal ("Include") made every study ineligible without a word.
  positive <- lower_text(trimws(as_chr1(positive, "")))
  if (!positive %in% .gr_reference_decisions) {
    gr_abort(sprintf("`positive` must be 'include' or 'exclude', not '%s'.", positive),
             class = "gr_bad_setting")
  }

  hit <- reference_rows(ref, tab)
  if (anyNA(hit)) {
    gr_abort(sprintf(paste0("%d row(s) in the reference name documents this screening run does ",
                            "not contain, starting with '%s'. A calibration compares the two on ",
                            "the same documents; a name that is in one and not the other means ",
                            "they are not the same run, or that the names were changed on the ",
                            "way (retyped, or re-saved by a spreadsheet in another encoding)."),
                     sum(is.na(hit)), ref$document[which(is.na(hit))[1]]),
             class = "gr_reference_mismatch")
  }
  model <- tab$decision[hit]
  human <- lower_text(trimws(to_utf8(ref$human_decision)))

  blank <- !nzchar(human)
  if (any(blank)) {
    gr_warn(sprintf(paste0("%d of %d reference row(s) have no `human_decision` and are left out. ",
                           "An unfilled row is not an exclusion."), sum(blank), length(human)),
            class = "gr_reference_incomplete")
  }
  bad <- !blank & !human %in% .gr_reference_decisions
  if (any(bad)) {
    gr_abort(sprintf("`human_decision` must be 'include' or 'exclude'; found %s.",
                     paste(sprintf("'%s'", unique(human[bad])), collapse = ", ")),
             class = "gr_bad_reference")
  }
  # One judgement per document. Two reviewers' sheets stacked with rbind() --
  # dual screening is standard practice -- doubled n, counted a disagreement
  # once each way, and narrowed every interval as if the sample were twice the
  # size. Copies that agree say nothing more and are counted once; copies that
  # disagree are a conflict for the reviewers to settle, not for a rate to
  # average.
  key <- ifelse(blank, -seq_along(hit), hit)
  again <- duplicated(key)
  if (any(again)) {
    n_views <- tapply(human[!blank], key[!blank], function(h) length(unique(h)))
    split_on <- as.integer(names(n_views)[n_views > 1L])
    if (length(split_on)) {
      gr_abort(sprintf(paste0("%d document(s) have more than one `human_decision` and the copies ",
                              "disagree, starting with '%s'. Reconcile them first (the consensus ",
                              "decision, one row per document); a calibration against both ",
                              "counts the document as eligible and as not."),
                       length(split_on), tab$document[split_on[1]]),
               class = c("gr_reference_conflict", "gr_bad_reference"))
    }
    gr_warn(sprintf(paste0("%d reference row(s) repeat a document already judged the same way, ",
                           "and are counted once."), sum(again)),
            class = "gr_reference_duplicate")
  }
  use <- !blank & !again & !is.na(model)
  model <- model[use]; human <- human[use]; rows <- ref[use, , drop = FALSE]
  if (!length(model)) {
    gr_abort("Nothing to compare: no reference row has both a human decision and a model one.",
             class = "gr_bad_reference")
  }

  eligible <- human == positive
  kept <- model %in% c("include", "unclear")
  strict <- model == "include"

  counts <- c(tp = sum(eligible & kept), fn = sum(eligible & !kept),
              fp = sum(!eligible & kept), tn = sum(!eligible & !kept))

  # WHICH STATISTICS THE SAMPLE CAN SUPPORT depends entirely on where it was
  # drawn from, and computing all of them regardless is worse than computing
  # none. A sample of exclusions contains no kept records by construction, so
  # sensitivity comes out 0%, specificity 100% and "reading avoided" 100% -- all
  # three artifacts of the frame, all three alarming or flattering, and none of
  # them a fact about the screener. What that frame DOES estimate is the false
  # omission rate, which is the most useful number here anyway: of everything
  # thrown away, how much should not have been.
  #
  # So `of` is checked, not taken as given. Any value but the two strata fell
  # through to the corpus-wide branch: of = "exclude" (the decision's label)
  # printed specificity 100% and "reading avoided" 100% from a sample of
  # exclusions, with no warning at all.
  recorded <- attr(ref, "of")
  frame_n <- attr(ref, "frame_n") %||% NA_integer_
  overridden <- NULL
  if (!is.null(of)) {
    of <- lower_text(trimws(as_chr1(of, "")))
    if (!of %in% c("excluded", "kept", "all", "stacked")) {
      gr_abort(sprintf("`of` must be \"excluded\", \"kept\", \"all\" or \"stacked\", not '%s'.",
                       of), class = "gr_bad_setting")
    }
    # Named over a file that records otherwise, the file is what gr_reference()
    # did and `of` is a claim about it. Said out loud (below, once the rows are
    # known to fit the claim), and the file's frame size dropped: it counts the
    # frame the file names, not this one, and a projection multiplied by it
    # would be the wrong pile.
    # A file that stacks kept and excluded samples, read as one stacked
    # reference, is what `of = "stacked"` is for and not an override.
    stacking <- identical(of, "stacked") && identical(recorded, "mixed") &&
      all(attr(ref, "frames") %in% c("kept", "excluded", "stacked"))
    if (!is.null(recorded) && !identical(recorded, of) && !stacking) {
      overridden <- paste(attr(ref, "frames") %||% recorded, collapse = " and ")
      frame_n <- NA_integer_
    }
  }
  of <- as_chr1(of %||% recorded %||% "unknown", "unknown")
  if (identical(of, "mixed")) {
    # Two strata stacked into one file. This is not a corner case: it is what
    # following this package's own advice produces -- judge everything kept AND
    # a sample of what was discarded -- and gr_calibrate() takes one reference,
    # so people rbind() them. The kept stratum is then sampled at 100% and the
    # excluded stratum at a few percent, and the unweighted figures are not
    # merely imprecise, they are wrong in a flattering direction: on a screener
    # that really missed 14% of eligible studies, this reported sensitivity
    # 100% with a 95% interval that excluded the truth.
    gr_abort(paste0("This reference stacks more than one sampling frame (",
                    paste(attr(ref, "frames") %||% sort(unique(as.character(ref$sampled_from))),
                          collapse = " and "),
                    "). An unweighted figure over stratified samples is wrong, not just ",
                    "imprecise. Pass `of = \"stacked\"` to weight each stratum by how ",
                    "much of it was sampled (or draw the sheet with ",
                    "gr_reference(of = \"stacked\")), calibrate each frame separately, ",
                    "or pass `of =` if the rows are one frame."),
             class = "gr_mixed_frame")
  }
  if (identical(of, "unknown")) {
    gr_warn(paste0("This reference does not say which part of the screening run it came ",
                   "from, so the figures below assume a sample of EVERYTHING screened. If ",
                   "it is a sample of one stratum (the exclusions, say), sensitivity ",
                   "and specificity are artifacts of that frame rather than facts about ",
                   "the screener. Pass `of = \"excluded\"`, `\"kept\"` or `\"all\"` to say which."),
            class = "gr_unknown_frame")
  }
  # A frame is a claim about the model's decisions, so check it against them.
  # The per-frame rates count every row as belonging to the frame: "eligible
  # among the excluded" is eligible rows over ALL rows, and the projection
  # multiplies that by the number of exclusions. A kept row in an exclusions
  # sample -- stacked frames with `of =` given, or a reference drawn from an
  # earlier run whose decisions have since changed -- was therefore scored as a
  # study thrown away, and "projected lost" reported studies the screener kept
  # while `missed` listed none of them.
  fits <- switch(of, excluded = model == "exclude",
                 kept = model %in% c("include", "unclear"), rep(TRUE, length(model)))
  if (identical(of, "stacked")) {
    # A stacked row says which stratum it came from; it has to be the one the
    # run puts it in, or its weight is the other stratum's.
    claim <- lower_text(trimws(to_utf8(as.character(rows$stratum %||% rows$sampled_from %||%
                                                      rep(NA, length(model))))))
    named <- claim %in% c("kept", "excluded")
    fits <- !named | (claim == ifelse(model == "exclude", "excluded", "kept"))
    if (!all(fits)) {
      gr_abort(sprintf(paste0("%d of %d stacked reference row(s) name a stratum this screening run ",
                              "did not put them in, starting with '%s' (now '%s'). The reference ",
                              "was drawn from a different run, or its decisions have changed ",
                              "since; calibrate against the run the sample was drawn from."),
                       sum(!fits), length(fits), rows$document[which(!fits)[1]],
                       model[which(!fits)[1]]),
               class = "gr_reference_mismatch")
    }
  }
  if (!all(fits)) {
    gr_abort(sprintf(paste0("%d of %d reference row(s) are said to come from the %s records, but ",
                            "this screening run did not %s them, starting with '%s' (now '%s'). ",
                            "Either the reference was drawn from a different run, or it stacks ",
                            "frames; scoring those rows as %s would misstate what was %s. ",
                            "Calibrate against the run the sample was drawn from, one frame at ",
                            "a time."),
                     sum(!fits), length(fits), of, if (of == "excluded") "exclude" else "keep",
                     rows$document[which(!fits)[1]], model[which(!fits)[1]],
                     if (of == "excluded") "exclusions" else "kept records",
                     if (of == "excluded") "lost" else "kept"),
             class = "gr_reference_mismatch")
  }
  if (!is.null(overridden)) {
    gr_warn(sprintf(paste0("`of = \"%s\"` overrides the reference, which records that it was ",
                           "drawn from %s. The figures below are computed as if it were not; ",
                           "if the file is right, leave `of` out."), of, overridden),
            class = "gr_frame_override")
  }
  if (identical(of, "stacked")) check_stacked(tab, ref, hit, kept, use)
  # Recall, records lost and the run's rates, from the strata the frame drew
  # on. Added beside the figures above, which are unchanged for every frame
  # that had them.
  rec <- screening_recall(of, kept, eligible, tab, recall_target, conf, max_lost)
  metrics <- switch(
    of,
    stacked = stacked_metrics(rec, sum(eligible)),
    excluded = rbind(
      prop_row("eligible among the excluded", sum(eligible), length(model)),
      prop_row("correctly excluded", sum(!eligible), length(model))),
    kept = rbind(
      prop_row("eligible among those kept", sum(eligible), length(model)),
      prop_row("deferred to a person", sum(model == "unclear"), length(model))),
    rbind(
      prop_row("sensitivity (as deployed)", counts[["tp"]], counts[["tp"]] + counts[["fn"]]),
      prop_row("sensitivity (strict include)", sum(eligible & strict), sum(eligible)),
      prop_row("specificity", counts[["tn"]], counts[["tn"]] + counts[["fp"]]),
      prop_row("deferred to a person", sum(model == "unclear"), length(model)),
      prop_row("reading avoided", sum(!kept), length(model))))
  # Kept before rounding, because the projection multiplies by the frame size:
  # 1/30 rounded to 0.0333 across 30,000 exclusions reports 999 studies lost
  # where the arithmetic says 1000, and the gap grows with the corpus.
  exact <- metrics
  metrics$estimate <- round(metrics$estimate, 4)
  metrics$lower <- round(metrics$lower, 4); metrics$upper <- round(metrics$upper, 4)

  n_pos <- sum(eligible)
  # Agreement needs both kinds of decision from both raters to mean anything. On
  # a single-stratum sample the model said one thing throughout, so it is not
  # chance-corrected agreement, it is arithmetic on a constant.
  #
  # The primary table is kept (include or unclear) against excluded, the same
  # definition of a positive decision that sensitivity uses. Kappa used to be
  # taken over the screener's three labels against the person's two, so every
  # "unclear" on an eligible record counted as a disagreement while the
  # sensitivity above counted the same record as kept. The strict table
  # (include against the rest) is the secondary one: its gap from the primary is
  # the deferral, as with the two sensitivities.
  # A stacked sample is two strata, but drawn at different rates: agreement
  # counted over its rows unweighted is distorted the way unweighted
  # sensitivity is, so it is left out with the one-stratum frames.
  one_stratum <- of %in% c("excluded", "kept", "stacked")
  agreement <- if (one_stratum) NULL else list(
    kept = agreement_binary(kept, eligible),
    strict = agreement_binary(strict, eligible))
  kappa <- if (one_stratum) NA_real_ else
    agreement$kept$stats$estimate[agreement$kept$stats$statistic == "kappa"]
  # The 3x2 figure 0.6.0 reported, kept for one release so a number already
  # quoted can be traced. It is not the screener's agreement with a person.
  kappa_legacy <- if (one_stratum) NA_real_ else
    cohen_kappa(model, ifelse(eligible, "include", "exclude"))
  decisions <- table(screener = factor(model, levels = c("include", "unclear", "exclude")),
                     person = factor(ifelse(eligible, "eligible", "not eligible"),
                                     levels = c("eligible", "not eligible")))
  # A number, compared as a number. `4 >= "10"` is TRUE because R compares as
  # STRINGS, and as_int1() then turned Inf and anything above 2^31 into the
  # default of 10 -- so asking for more eligible studies than the sample could
  # have declared the calibration adequate. A bar that cannot be read falls
  # back to the default, and says so.
  min_pos <- suppressWarnings(as.numeric(min_positives))
  if (length(min_pos) != 1L || is.na(min_pos)) {
    gr_warn("`min_positives` must be a single number; using the default (10).",
            class = "gr_bad_setting")
    min_pos <- 10
  }
  # ADEQUACY IS PER FRAME, because what the headline rate rests on is. In an
  # "all" sample sensitivity rests on the eligible studies alone, so it needs
  # min_positives of them. In a one-stratum sample the rate is taken over every
  # row sampled: judged by the eligible count instead, a clean sample of 500
  # exclusions -- 0.0% [0.0%, 0.8%] -- was "inadequate", said to rest on "those
  # 0 observations", and the better the screener the surer that verdict. There
  # the question is whether the interval is narrow enough to say something, or
  # whether the whole frame was judged, when nothing is left to sample and the
  # rate is a count for this run.
  headline <- switch(of, excluded = "eligible among the excluded",
                     kept = "eligible among those kept", NA_character_)
  adequacy <- if (identical(of, "stacked")) {
    list(rule = "recall target", bar = recall_target, width = NA_real_,
         note = if (isTRUE(rec$verdict$met)) NA_character_ else rec$verdict$note)
  } else if (is.na(headline)) {
    list(rule = "positives", bar = min_pos, width = NA_real_,
         note = if (n_pos >= min_pos) NA_character_ else
           sprintf("Only %d eligible stud%s in the sample, below the %s this calibration asks for.",
                   n_pos, if (n_pos == 1L) "y" else "ies", format(min_pos)))
  } else {
    h <- exact[exact$metric == headline, ]
    width <- h$upper - h$lower
    in_frame <- which(!is.na(tab$decision) &
                        switch(of, excluded = tab$decision == "exclude",
                               tab$decision %in% c("include", "unclear")))
    whole <- length(in_frame) > 0L && all(in_frame %in% hit[use])
    list(rule = if (whole) "whole frame" else "interval", bar = .gr_frame_max_width,
         width = width,
         note = if (whole || width <= .gr_frame_max_width) NA_character_ else
           sprintf(paste0("The interval on '%s' is %.1f points wide, from %d hand-screened ",
                          "row(s); a sample of one stratum needs it within %.0f points (or the ",
                          "whole stratum judged) before the figure says much."),
                   headline, 100 * width, length(model), 100 * .gr_frame_max_width))
  }
  reviewers <- if (!is.null(panel)) {
    reviewer_summary(rows, eligible, kept, of, tab, positive, conf,
                     attr(panel, "consensus_rule"), attr(panel, "conflicts"))
  }
  out <- structure(list(
    counts = counts,
    metrics = metrics,
    kappa = kappa,
    kappa_legacy = kappa_legacy,
    agreement = agreement,
    decisions = decisions,
    missed = rows[eligible & !kept, , drop = FALSE],
    disagreements = rows[(eligible & !kept) | (!eligible & strict), , drop = FALSE],
    n = length(model),
    n_positives = n_pos,
    # as_int1() first. `4 >= "10"` is TRUE -- R compares as STRINGS -- so a
    # character min_positives declared an inadequate calibration adequate, and
    # the "too few eligible studies to quote a figure" warning vanished from
    # print() while the object still displayed 10.
    adequate = is.na(adequacy$note),
    adequacy = adequacy,
    min_positives = min_pos,
    frame = list(of = of,
                 frame_n = if (identical(of, "stacked")) sum(rec$strata$N) else frame_n,
                 screened_n = attr(ref, "screened_n") %||% nrow(tab)),
    # What the rate implies for the part of the frame nobody checked. The whole
    # reason to sample exclusions is to find out how much was lost, and a rate
    # without that multiplication leaves the reader to do it.
    projected = if (identical(of, "excluded") && !is.na(frame_n)) {
      fr <- frame_n
      m <- exact[exact$metric == "eligible among the excluded", ]
      list(frame_n = fr, lost = fr * m$estimate,
           lower = fr * m$lower, upper = fr * m$upper)
    } else if (identical(of, "stacked")) {
      list(frame_n = rec$lost$frame_n, lost = rec$lost$estimate,
           lower = rec$lost$lower, upper = rec$lost$upper)
    } else NULL,
    recall = rec$recall,
    lost = rec$lost,
    false_exclusion = rec$false_exclusion,
    work_saved = rec$work_saved,
    unclear_rate = rec$unclear_rate,
    strata = rec$strata,
    verdict = rec$verdict
  ), class = "gr_calibration")
  # Only with several reviewers, so a one-reviewer calibration is the object it
  # was before.
  if (!is.null(reviewers)) out$reviewers <- reviewers
  out
}

#' Stop unless a stacked reference can be weighted: rows from each stratum
#' that has records, and inclusion probabilities, where recorded, that agree
#' with the rows drawn.
#' @noRd
check_stacked <- function(tab, ref, hit, kept, use) {
  judged <- !is.na(tab$decision)
  N <- c(kept = sum(judged & tab$decision %in% c("include", "unclear")),
         excluded = sum(judged & tab$decision == "exclude"))
  n <- c(kept = sum(kept), excluded = sum(!kept))
  empty <- names(N)[N > 0 & n == 0]
  if (length(empty)) {
    gr_abort(sprintf(paste0("This stacked reference has no judged row from the %s records (%d in ",
                            "the run), so their eligible count, and recall, cannot be estimated. ",
                            "Judge every kept record and a sample of the excluded ones."),
                     empty[1], N[[empty[1]]]), class = "gr_bad_reference")
  }
  if (!is.null(ref$inclusion_prob)) {
    # The weights used are N / n from the rows judged, which equal the
    # recorded probabilities on a complete sheet. They part when rows were
    # added, dropped or left blank, and the sheet then no longer describes
    # the draw.
    # Only the filled rows count, as in the weights: a blank row was drawn
    # but not judged, so it lowers n without the sheet saying so.
    used <- hit[use]
    rows <- unique(used[!is.na(tab$decision[used])])
    drawn_kept <- tab$decision[rows] %in% c("include", "unclear")
    expect <- ifelse(drawn_kept, sum(drawn_kept) / N[["kept"]],
                     sum(!drawn_kept) / N[["excluded"]])
    recorded <- suppressWarnings(as.numeric(ref$inclusion_prob[use][match(rows, used)]))
    off <- !is.na(recorded) & abs(recorded - expect) > 1e-6
    if (any(off)) {
      gr_warn(sprintf(paste0("%d row(s) record an inclusion probability that does not match the ",
                             "rows drawn from their stratum. Recall is weighted by the rows ",
                             "judged in each stratum against the stratum's size in this run."),
                      sum(off)), class = "gr_inclusion_mismatch")
    }
  }
  invisible(TRUE)
}

#' The metric rows of a stacked calibration: recall and the excluded and kept
#' rates with their exact intervals, and the run's own deferral and reading
#' avoided, which are counts and carry no sampling error.
#' @noRd
stacked_metrics <- function(rec, n_pos) {
  st <- rec$strata
  sk <- st[st$stratum == "kept", ]
  row <- function(name, est, lo, hi, n) {
    data.frame(metric = name, estimate = est, lower = lo, upper = hi, n = as.integer(n),
               stringsAsFactors = FALSE)
  }
  fx <- rec$false_exclusion
  kept_rate <- if (sk$N > 0 && sk$n > 0) c(sk$eligible / sk$n, sk$lower / sk$N, sk$upper / sk$N)
               else rep(NA_real_, 3)
  rbind(
    row("sensitivity (as deployed)", rec$recall$estimate, rec$recall$lower, rec$recall$upper,
        n_pos),
    row("eligible among the excluded", fx$estimate, fx$lower, fx$upper, fx$n),
    row("eligible among those kept", kept_rate[1], kept_rate[2], kept_rate[3], sk$n),
    row("deferred to a person", rec$unclear_rate$estimate, rec$unclear_rate$estimate,
        rec$unclear_rate$estimate, rec$unclear_rate$screened),
    row("reading avoided", rec$work_saved$estimate, rec$work_saved$estimate,
        rec$work_saved$estimate, rec$work_saved$screened))
}

#' @noRd
read_reference <- function(reference) {
  ref <- if (is.character(reference) && length(reference) == 1L && file.exists(reference)) {
    read_reference_csv(reference)
  } else reference
  if (!is.data.frame(ref) || !nrow(ref)) {
    gr_abort("`reference` must be a data frame, or a path to the CSV gr_reference() wrote.",
             class = "gr_bad_reference")
  }
  # Several reviewers' sheets have one `human_decision_<reviewer>` column each
  # in place of `human_decision`.
  if (is.null(ref$document) ||
      (is.null(ref$human_decision) && length(reviewer_columns(ref)) < 2L)) {
    gr_abort(paste0("`reference` needs `document` and `human_decision` columns (or one ",
                    "`human_decision_<reviewer>` column per reviewer). gr_reference() writes ",
                    "a file with them."), class = "gr_bad_reference")
  }
  # A blind sheet's frame is an opaque key (see frame_key()); read it back as
  # the frame's name and sizes, which is what everything below works with.
  # Names in plain words -- a sheet written with blind = FALSE, or before the
  # key -- are read as they always were.
  keys <- list()
  if (!is.null(ref$sampled_from)) {
    raw <- as.character(ref$sampled_from)
    seen <- unique(raw[!is.na(raw) & nzchar(trimws(raw))])
    decoded <- lapply(seen, frame_unkey)
    named <- vapply(seq_along(seen), function(i) {
      if (is.null(decoded[[i]])) lower_text(trimws(to_utf8(seen[i]))) else decoded[[i]]$of
    }, character(1))
    ref$sampled_from <- named[match(raw, seen)]
    keys <- Filter(Negate(is.null), decoded)
    # A stacked key carries the row's stratum and its inclusion probability,
    # which a blind sheet keeps out of plain sight.
    stacked <- vapply(decoded, function(k) !is.null(k$stratum), logical(1))
    if (any(stacked) && is.null(ref$stratum)) {
      at <- match(raw, seen)
      strat <- vapply(decoded, function(k) k$stratum %||% NA_character_, character(1))
      prob <- vapply(decoded, function(k) {
        if (is.null(k$stratum) || !k$frame_n) NA_real_ else k$drawn / k$frame_n
      }, numeric(1))
      ref$stratum <- strat[at]
      ref$inclusion_prob <- prob[at]
    }
  }
  # The COLUMNS say where each row came from; the attributes only say where the
  # first row did. rbind() keeps its first argument's attributes, so a sample
  # of the kept records stacked under a sample of the exclusions -- the design
  # gr_reference() recommends, combined the obvious way -- still claimed to be
  # one sample of exclusions, and was scored as one: every kept eligible study
  # counted as an eligible study thrown away, projected across the whole
  # discarded pile. The same rows read back from a CSV were refused. So the
  # columns are read whenever they are there, and the attributes are what is
  # left when they are not.
  if (!is.null(ref$sampled_from)) {
    v <- unique(as.character(ref$sampled_from))
    v <- v[!is.na(v) & nzchar(v)]
    a <- attr(ref, "of")
    frames <- unique(c(v, a))
    # More than one stratum in one file is reported as such rather than left to
    # fall through to "unknown", which took the corpus-wide branch and computed
    # sensitivity and specificity from a stratified sample without a word.
    if (length(frames) > 1L && length(v)) {
      attr(ref, "of") <- "mixed"
      attr(ref, "frames") <- sort(frames)
    } else if (length(v) == 1L && v %in% c("excluded", "kept", "all", "stacked")) {
      attr(ref, "of") <- v
    }
  }
  for (col in c("frame_n", "screened_n")) {
    from_keys <- vapply(keys, function(k) k[[col]], integer(1))
    if (is.null(ref[[col]]) && !length(from_keys)) next
    v <- unique(c(suppressWarnings(as.integer(ref[[col]])), from_keys))
    v <- v[!is.na(v)]
    # Two sizes means rows from two frames or two runs, and there is no one
    # frame to project onto; nothing is better than the first argument's.
    if (length(v) == 1L) attr(ref, col) <- v
    else if (length(v) > 1L) attr(ref, col) <- NULL
  }
  ref
}

#' Which screening row each reference row is about, NA where none is.
#'
#' By name, compared as UTF-8 on both sides: the same name read in another
#' locale, or marked differently, is otherwise a different string to match().
#' A name that still does not match falls back to the row's `document_id`,
#' which the sheet carries and which no spreadsheet re-encodes.
#' @noRd
reference_rows <- function(ref, tab) {
  hit <- match(to_utf8(ref$document), to_utf8(tab$document))
  if (anyNA(hit) && !is.null(ref$document_id) && !is.null(tab$document_id)) {
    id_of <- function(x) { x <- trimws(to_utf8(x)); x[!nzchar(x)] <- NA_character_; x }
    miss <- which(is.na(hit))
    hit[miss] <- match(id_of(ref$document_id)[miss], id_of(tab$document_id), incomparables = NA)
  }
  hit
}

#' An opaque key for the frame a blind sample was drawn from.
#'
#' The frame, its size and the run's screened count, as `"gr"`, a nonce, and
#' the three XORed with a pad the nonce derives. Not secret, only unreadable at
#' a glance, which is what blinding a person needs; the nonce, taken from the
#' sampled documents, keeps one frame from having the same key in every file.
#' @noRd
frame_key <- function(of, frame_n, screened_n, salt) {
  payload <- as.integer(charToRaw(sprintf("%s:%s:%s", of, frame_n, screened_n)))
  nonce <- substr(gr_hash(list("readgpt-frame-key", as.character(salt))), 1, 8)
  body <- bitwXor(payload, frame_pad(nonce, length(payload)))
  paste0("gr", nonce, paste(sprintf("%02x", body), collapse = ""))
}

#' The key for one row of a blind stacked sheet: its stratum, the stratum's
#' size, how many of the stratum were drawn and the run's screened count.
#'
#' Padded with spaces to a fixed length before it is masked, so that the key
#' of a kept row and of an excluded one are the same length; the nonce comes
#' from the row's own document, so no two rows share a key by stratum.
#' @noRd
stacked_key <- function(stratum, frame_n, drawn, screened_n, salt) {
  txt <- formatC(sprintf("stacked:%s:%s:%s:%s", stratum, format(frame_n, scientific = FALSE),
                         format(drawn, scientific = FALSE), format(screened_n, scientific = FALSE)),
                 width = -64L)
  payload <- as.integer(charToRaw(txt))
  nonce <- substr(gr_hash(list("readgpt-frame-key", as.character(salt))), 1, 8)
  body <- bitwXor(payload, frame_pad(nonce, length(payload)))
  paste0("gr", nonce, paste(sprintf("%02x", body), collapse = ""))
}

#' The frame a key stands for, as list(of, frame_n, screened_n); NULL for
#' anything that is not a key this package wrote. A stacked sheet's key also
#' gives the row's `stratum` and `drawn`, the number drawn from that stratum,
#' with `frame_n` the stratum's size.
#' @noRd
frame_unkey <- function(x) {
  x <- lower_text(trimws(as_chr1(x, "")))
  if (!grepl("^gr[0-9a-f]{8}([0-9a-f]{2})+$", x)) return(NULL)
  hex <- substring(x, 11L)
  at <- seq(1L, nchar(hex) - 1L, by = 2L)
  body <- strtoi(substring(hex, at, at + 1L), 16L)
  plain <- bitwXor(body, frame_pad(substr(x, 3L, 10L), length(body)))
  if (any(plain < 32L | plain > 126L)) return(NULL)
  txt <- rawToChar(as.raw(plain))
  st <- regmatches(txt, regexec("^stacked:(kept|excluded):([0-9]+):([0-9]+):([0-9]+) *$",
                                txt))[[1]]
  if (length(st)) {
    return(list(of = "stacked", frame_n = as.integer(st[3]), screened_n = as.integer(st[5]),
                stratum = st[2], drawn = as.integer(st[4])))
  }
  m <- regmatches(txt, regexec("^(excluded|kept|all):([0-9]+|NA):([0-9]+|NA)$", txt))[[1]]
  if (!length(m)) return(NULL)
  list(of = m[2], frame_n = suppressWarnings(as.integer(m[3])),
       screened_n = suppressWarnings(as.integer(m[4])))
}

#' The pad behind a frame key: bytes from a 32-bit linear congruential
#' generator seeded by the nonce. Plain arithmetic on doubles (every value stays
#' below 2^53), so a key written on one machine reads back on any other.
#' @noRd
frame_pad <- function(nonce, n) {
  state <- as.numeric(strtoi(substr(nonce, 1L, 4L), 16L)) * 65536 +
    strtoi(substr(nonce, 5L, 8L), 16L)
  out <- integer(n)
  for (i in seq_len(n)) {
    state <- (state * 69069 + 1) %% 4294967296
    out[i] <- as.integer(state %/% 16777216)
  }
  out
}

#' Write a reference sheet as UTF-8 with a byte-order mark, in any locale.
#'
#' write.csv() translates to the session's encoding before it writes, so in a C
#' locale an accented name went out as "<U+00C9>vora.txt" -- irreversibly, and
#' gr_calibrate() then refused its own file -- and with fileEncoding = "UTF-8"
#' it went out as nothing at all. So the cells are quoted here, as write.csv()
#' quotes them, and written as bytes. The mark is what makes Excel read the
#' file as UTF-8 rather than as its own code page.
#' @noRd
write_reference_csv <- function(df, path) {
  cell <- function(v) {
    if (is.factor(v)) v <- as.character(v)
    if (is.character(v)) {
      out <- paste0("\"", gsub("\"", "\"\"", to_utf8(v), fixed = TRUE), "\"")
    } else {
      out <- as.character(v)
    }
    out[is.na(v)] <- ""
    out
  }
  body <- if (ncol(df)) do.call(paste, c(lapply(unclass(df), cell), sep = ",")) else character(0)
  head <- paste0("\"", gsub("\"", "\"\"", to_utf8(names(df)), fixed = TRUE), "\"",
                 collapse = ",")
  text <- to_utf8(paste0(paste(c(head, body), collapse = "\n"), "\n"))
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw(text)), con)
  invisible(path)
}

#' Read a reference sheet back as UTF-8, whatever the locale and whatever a
#' spreadsheet did to it.
#'
#' read.csv() reads bytes in the session's encoding: under a C locale a UTF-8
#' name came back as bytes match() did not equate with the marked name in the
#' screening, a sheet Excel saved as Windows-1252 stopped with "invalid
#' multibyte string", and a byte-order mark became part of the first column's
#' name ("X...document"). So the bytes are read here: the mark dropped, each
#' line kept as UTF-8 where it is valid and read as Windows-1252 where it is not
#' (to_utf8()), and the text parsed from memory, which read.csv() marks UTF-8.
#' `na.strings` and `...` go to read.csv(): a label sheet reads every column
#' as text, so an id such as "007" keeps its zeros, and only an empty cell
#' as missing, so an answer of "NA" stays an answer.
#' @noRd
read_reference_csv <- function(path, na.strings = c("", "NA"), ...) {
  bytes <- readBin(path, "raw", n = max(file.size(path), 0))
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) {
    bytes <- bytes[-(1:3)]
  }
  bytes <- bytes[bytes != as.raw(0L)]
  lines <- strsplit(rawToChar(bytes), "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  lines <- to_utf8(sub("\r$", "", lines, useBytes = TRUE))
  if (!length(lines)) return(data.frame())
  utils::read.csv(text = lines, stringsAsFactors = FALSE, na.strings = na.strings, ...)
}

#' Subsetting a reference frame gives a plain data frame.
#'
#' `[` on an object whose class extends `data.frame` keeps the CLASS and drops
#' every other attribute, so `ref[, cols]` came back still claiming to be a
#' `gr_reference_frame` while `of`, `frame_n`, `screened_n` and `seed` were gone,
#' and gr_calibrate() then computed the corpus-wide metric set from a stratified
#' sample. The same trap, and the same fix, as `[.gr_gaps`.
#' @param x A `gr_reference_frame`.
#' @param ... Passed to the data frame method.
#' @return A plain data frame.
#' @export
`[.gr_reference_frame` <- function(x, ...) {
  out <- NextMethod()
  if (is.data.frame(out)) {
    class(out) <- "data.frame"
    for (a in c("of", "frame_n", "screened_n", "seed")) attr(out, a) <- NULL
  }
  out
}

#' @export
print.gr_calibration <- function(x, ...) {
  cat(sprintf("<gr_calibration> %d hand-screened row(s), %d eligible\n", x$n, x$n_positives))
  cat(sprintf("  sampled from: %s (%s of %s screened)\n", x$frame$of,
              format(x$frame$frame_n), format(x$frame$screened_n)))
  for (i in seq_len(nrow(x$metrics))) {
    m <- x$metrics[i, ]
    cat(sprintf("  %-30s %s  [%s, %s]  n=%d\n", m$metric,
                if (is.na(m$estimate)) "  --" else sprintf("%5.1f%%", 100 * m$estimate),
                if (is.na(m$lower)) "--" else sprintf("%.1f%%", 100 * m$lower),
                if (is.na(m$upper)) "--" else sprintf("%.1f%%", 100 * m$upper), m$n))
  }
  # The 3x2 counts on every sample, one stratum included: they are what the
  # rates above and any agreement below are made from.
  if (!is.null(x$decisions)) print_calibration_decisions(x$decisions)
  if (!is.null(x$agreement)) print_calibration_agreement(x)
  if (!is.null(x$projected)) {
    p <- x$projected
    cat(sprintf(paste0("  -> across all %d excluded record(s) that rate implies about %.0f\n",
                       "     eligible stud%s lost (%.0f to %.0f on the interval above).\n"),
                p$frame_n, p$lost, if (round(p$lost) == 1) "y" else "ies", p$lower, p$upper))
  }
  print_calibration_recall(x)
  print_calibration_reviewers(x)
  if (identical(x$frame$of, "stacked")) {
    cat("  (every kept record and a sample of the exclusions: each stratum weighted by\n")
    cat("   how much of it was judged, with exact hypergeometric bounds)\n")
  } else if (identical(x$frame$of, "excluded")) {
    cat("  (sampled from exclusions only: this frame estimates what was lost, not\n")
    cat("   sensitivity or specificity: it contains no kept records to compute them from)\n")
  } else if (identical(x$frame$of, "kept")) {
    cat("  (sampled from kept records only: this frame estimates how much of what was\n")
    cat("   kept is worth keeping, not sensitivity: the misses are not in it)\n")
  }
  if (nrow(x$missed)) {
    cat(sprintf("  ! %d eligible stud%s excluded by the screener:\n", nrow(x$missed),
                if (nrow(x$missed) == 1L) "y was" else "ies were"))
    for (d in utils::head(x$missed$document, 5)) cat(sprintf("      %s\n", d))
    if (nrow(x$missed) > 5L) cat(sprintf("      ... and %d more\n", nrow(x$missed) - 5L))
  }
  rule <- x$adequacy$rule %||% "positives"
  if (!x$adequate && identical(rule, "recall target")) {
    cat(sprintf("  ! %s\n", paste(strwrap(x$adequacy$note, width = 72, exdent = 4),
                                     collapse = "\n")))
  } else if (!x$adequate && !identical(rule, "positives")) {
    # One stratum: the rate is over every row, so the eligible count is not
    # what it rests on, and saying so told the owner of a clean 500-row sample
    # that it rested on nothing.
    cat(sprintf(paste0("  ! the interval on '%s' is %.1f points wide\n",
                       "    (n=%d). A sample of one stratum needs it within %.0f points, or the\n",
                       "    whole stratum judged. Hand-screen more before quoting a figure.\n"),
                if (identical(x$frame$of, "kept")) "eligible among those kept"
                else "eligible among the excluded",
                100 * x$adequacy$width, x$n, 100 * x$adequacy$bar))
  } else if (!x$adequate) {
    cat(sprintf(paste0("  ! only %d eligible stud%s in the sample. Every rate above rests on\n",
                       "    %s, which is why the intervals are as wide as they are.\n",
                       "    Hand-screen more before quoting a figure.\n"),
                x$n_positives, if (x$n_positives == 1L) "y" else "ies",
                if (x$n_positives == 1L) "that one observation"
                else sprintf("those %d observations", x$n_positives)))
  }
  invisible(x)
}

#' The recall part of a calibration's print: recall with its interval and
#' one-sided bound, the exact bound on records lost, and whether the target
#' was met. Silent for a calibration saved before these fields existed.
#' @noRd
print_calibration_recall <- function(x) {
  pct <- function(v) if (is.na(v)) "--" else sprintf("%.1f%%", 100 * v)
  r <- x[["recall", exact = TRUE]]
  if (is.list(r) && !is.na(r$estimate)) {
    cat(sprintf("  recall %s  [%s, %s]; %.0f%% one-sided lower bound %s\n",
                pct(r$estimate), pct(r$lower), pct(r$upper), 100 * r$conf, pct(r$bound)))
  }
  l <- x[["lost", exact = TRUE]]
  if (is.list(l) && !is.na(l$bound)) {
    cat(sprintf("  eligible records excluded: about %.0f of %d; %.0f%% upper bound %.0f\n",
                l$estimate, as.integer(l$frame_n), 100 * l$conf, l$bound))
  }
  v <- x[["verdict", exact = TRUE]]
  if (is.list(v) && !is.na(v$met)) {
    cat(sprintf("  recall target %s at %.0f%% confidence%s: %s\n", pct(v$recall_target),
                100 * v$conf,
                if (is.na(v$max_lost)) "" else sprintf(" (or at most %s lost)", format(v$max_lost)),
                if (v$met) "met" else "not met"))
  }
  invisible(NULL)
}

#' The 3x2 counts of a calibration's print: the screener's three labels
#' against the person's two.
#' @noRd
print_calibration_decisions <- function(d) {
  cat(sprintf("  %-10s %9s %13s\n", "screener", "eligible", "not eligible"))
  for (r in rownames(d)) {
    cat(sprintf("  %-10s %9d %13d\n", r, d[r, "eligible"], d[r, "not eligible"]))
  }
  invisible(NULL)
}

#' The agreement part of a calibration's print: each table's kappa beside
#' PABAK and AC1, never alone.
#' @noRd
print_calibration_agreement <- function(x) {
  fmt <- function(v) if (is.na(v)) "  --" else sprintf("%5.2f", v)
  for (nm in c("kept", "strict")) {
    a <- x$agreement[[nm]]
    if (is.null(a)) next
    st <- a$stats
    g <- function(s) st[st$statistic == s, ]
    cat(sprintf("  agreement, %s:\n",
                if (nm == "kept") "kept (include + unclear) vs excluded"
                else "strict include vs the rest"))
    for (s in c("kappa", "PABAK", "AC1")) {
      r <- g(s)
      cat(sprintf("    %-8s %s  [%s, %s]\n", s, fmt(r$estimate),
                  trimws(fmt(r$lower)), trimws(fmt(r$upper))))
    }
    cat(sprintf("    PI %s, BI %s\n", trimws(fmt(g("prevalence index")$estimate)),
                trimws(fmt(g("bias index")$estimate))))
    note <- a[["note", exact = TRUE]]
    if (is.character(note) && length(note) == 1L && !is.na(note)) {
      cat(sprintf("    (no kappa or AC1 interval: %s)\n", note))
    }
    if (isTRUE(a$paradox)) {
      cat("    ! abs(PI) is above 0.8: kappa here reflects prevalence as much as\n")
      cat("      agreement; read it beside PABAK and AC1, not against another kappa\n")
    }
  }
  invisible(NULL)
}
