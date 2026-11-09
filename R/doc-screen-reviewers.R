# doc-screen-reviewers.R: references judged by more than one person.
#
# A reference standard is people, and people miss eligible studies too. When
# two or three reviewers judge the same records, how far they agree with each
# other is the yardstick the screener's agreement with them is read against,
# and each reviewer's sensitivity against their consensus says what one person
# screening alone would have missed on the same sample. Neither needs anything
# the sheet does not already hold, so both are reported whenever it holds more
# than one reviewer.

#' The ways a consensus can be formed from several reviewers' decisions.
#' @noRd
.gr_consensus_rules <- c("majority", "any_include", "adjudicated")

#' Column names that start with `human_decision_` but hold something about
#' the decisions rather than one reviewer's decision, such as a note or a date
#' added beside them.
#' @noRd
.gr_reviewer_column_skip <- "_(note|notes|comment|comments|date)$"

#' The reviewer decision columns of a sheet: every name that starts with
#' `human_decision_`, in sheet order, other than those ending in `_note`,
#' `_notes`, `_comment`, `_comments` or `_date`.
#' @noRd
reviewer_columns <- function(ref) {
  cols <- grep("^human_decision_.+$", names(ref), value = TRUE)
  cols[!grepl(.gr_reviewer_column_skip, cols)]
}

#' A decision column read the way gr_calibrate() reads `human_decision`:
#' trimmed, lower case, blank as NA. Anything other than include or exclude
#' stops here, naming the column.
#' @noRd
reviewer_decisions <- function(v, name) {
  if (is.null(v)) return(NULL)
  d <- lower_text(trimws(to_utf8(as.character(v))))
  d[is.na(d) | !nzchar(d)] <- NA_character_
  bad <- !is.na(d) & !d %in% .gr_reference_decisions
  if (any(bad)) {
    gr_abort(sprintf("`%s` must be 'include', 'exclude' or empty; found %s.", name,
                     paste(sprintf("'%s'", utils::head(unique(d[bad]), 5)), collapse = ", ")),
             class = "gr_bad_reference")
  }
  d
}

#' A multi-reviewer sheet in wide form (one row per document, one
#' `human_decision_<id>` column per reviewer), or NULL for a sheet that holds
#' one decision per document.
#'
#' A wide sheet is one with two or more reviewer columns. A long sheet is one
#' with a `reviewer` column in which some document was judged by two or more
#' different reviewers; it is turned into the wide form here. Two sheets
#' stacked without a `reviewer` column are not read as reviewers, since nothing
#' says the copies came from different people: gr_calibrate() treats them as
#' it always has.
#' @noRd
reviewer_sheet <- function(ref) {
  if (length(reviewer_columns(ref)) >= 2L) return(ref)
  if (is.null(ref$reviewer) || is.null(ref$human_decision)) return(NULL)
  rv <- trimws(to_utf8(as.character(ref$reviewer)))
  rv[is.na(rv)] <- ""
  doc <- to_utf8(as.character(ref$document))
  per_doc <- tapply(rv[nzchar(rv)], doc[nzchar(rv)], function(r) length(unique(r)))
  if (!length(per_doc) || all(per_doc < 2L)) return(NULL)
  if (any(!nzchar(rv))) {
    gr_abort(sprintf(paste0("%d row(s) of this sheet have no `reviewer`, so their decisions ",
                            "cannot be told apart from the others' on the same document."),
                     sum(!nzchar(rv))), class = "gr_bad_reference")
  }
  dec <- reviewer_decisions(ref$human_decision, "human_decision")
  ids <- unique(rv)
  # A reviewer id such as "notes" would give a column that reviewer_columns()
  # passes over, and that reviewer's decisions would be dropped unseen.
  skipped <- ids[grepl(.gr_reviewer_column_skip, paste0("human_decision_", ids))]
  if (length(skipped)) {
    gr_abort(sprintf(paste0("Reviewer '%s' cannot be told apart from a note column. Give ",
                            "reviewers ids that do not end in note, notes, comment, comments ",
                            "or date."), skipped[1]), class = "gr_bad_reference")
  }
  num <- suppressWarnings(as.numeric(ids))
  if (!anyNA(num)) ids <- ids[order(num)]
  docs <- unique(doc)
  first <- match(docs, doc)
  saved <- attributes(ref)
  saved <- saved[intersect(names(saved), c("of", "frames", "frame_n", "screened_n", "seed"))]
  drop <- c("reviewer", "human_decision", "human_note", "consensus")
  wide <- as.data.frame(lapply(ref[, setdiff(names(ref), drop), drop = FALSE],
                               function(v) v[first]),
                        stringsAsFactors = FALSE, optional = TRUE)
  # One value per document from the rows that hold it, refusing two that
  # differ: the same reviewer judging a record twice, differently, or two
  # adjudicated decisions for one record, is not something to pick between.
  one_per_doc <- function(v, rows, what) {
    out <- rep(NA_character_, length(docs))
    seen <- !is.na(v[rows])
    if (!any(seen)) return(out)
    vals <- tapply(v[rows][seen], match(doc[rows], docs)[seen], function(x) unique(x))
    split_on <- lengths(vals) > 1L
    if (any(split_on)) {
      gr_abort(sprintf("%d document(s) have more than one %s, starting with '%s'.",
                       sum(split_on), what, docs[as.integer(names(vals)[split_on][1])]),
               class = c("gr_reference_conflict", "gr_bad_reference"))
    }
    out[as.integer(names(vals))] <- unlist(vals, use.names = FALSE)
    out
  }
  for (id in ids) {
    rows <- which(rv == id)
    wide[[paste0("human_decision_", id)]] <- one_per_doc(dec, rows,
                                                         sprintf("decision from reviewer %s", id))
  }
  if (!is.null(ref$consensus)) {
    wide$consensus <- one_per_doc(reviewer_decisions(ref$consensus, "consensus"),
                                  seq_along(doc), "`consensus` decision")
  }
  if (!is.null(ref$human_note)) {
    note <- trimws(to_utf8(as.character(ref$human_note)))
    note[is.na(note)] <- ""
    wide$human_note <- vapply(seq_along(docs), function(i) {
      n <- unique(note[doc == docs[i] & nzchar(note)])
      if (length(n)) paste(n, collapse = "; ") else NA_character_
    }, character(1))
  }
  for (a in names(saved)) attr(wide, a) <- saved[[a]]
  wide
}

#' Form the consensus of a wide sheet into `human_decision`, with the way
#' each row's was reached in `consensus_from`.
#'
#' `calling` names the function to put in the message when a disagreement is
#' left unsettled.
#' @noRd
form_consensus <- function(wide, rule, calling = "gr_reference_consensus") {
  cols <- reviewer_columns(wide)
  D <- do.call(cbind, lapply(cols, function(cl) reviewer_decisions(wide[[cl]], cl)))
  n_inc <- rowSums(D == "include", na.rm = TRUE)
  n_exc <- rowSums(D == "exclude", na.rm = TRUE)
  # The adjudicator's decision. A sheet that already has `human_decision`
  # filled and no `consensus` column is read as that decision, so a sheet
  # reconciled by hand in the old column still counts.
  adj <- reviewer_decisions(wide$consensus %||% wide$human_decision %||%
                              rep(NA_character_, nrow(wide)),
                            if (is.null(wide$consensus)) "human_decision" else "consensus")
  split_on <- n_inc > 0 & n_exc > 0
  out <- ifelse(n_inc > 0 & !split_on, "include", ifelse(n_exc > 0 & !split_on, "exclude",
                                                          NA_character_))
  from <- ifelse(n_inc + n_exc == 0, "no decision",
                 ifelse(n_inc + n_exc == 1, "one reviewer", "unanimous"))
  from[split_on] <- NA_character_
  if (rule == "majority") {
    out[split_on & n_inc > n_exc] <- "include"
    out[split_on & n_exc > n_inc] <- "exclude"
    from[split_on & n_inc != n_exc] <- "majority"
    # A tie is settled by the adjudicator where there is one, and otherwise
    # as include: a reference that excludes a record half its reviewers
    # included would credit the screener for excluding it too.
    tie <- split_on & n_inc == n_exc
    settled <- tie & !is.na(adj)
    out[settled] <- adj[settled]; from[settled] <- "adjudicated"
    out[tie & is.na(adj)] <- "include"; from[tie & is.na(adj)] <- "tie kept"
  } else if (rule == "any_include") {
    out[split_on] <- "include"; from[split_on] <- "any include"
  } else {
    # The adjudicator has the last word wherever they gave one.
    given <- !is.na(adj)
    out[given] <- adj[given]; from[given] <- "adjudicated"
    open <- split_on & !given
    if (any(open)) {
      gr_abort(sprintf(paste0("%d of %d document(s) were judged differently by the reviewers and ",
                              "have no `consensus` decision, starting with '%s'. Fill `consensus` ",
                              "where they disagree, or form one with %s(rule = \"majority\") or ",
                              "rule = \"any_include\"."),
                       sum(open), nrow(wide), wide$document[which(open)[1]], calling),
               class = c("gr_reference_conflict", "gr_bad_reference"))
    }
  }
  wide$human_decision <- out
  wide$consensus_from <- from
  attr(wide, "consensus_rule") <- rule
  attr(wide, "conflicts") <- sum(split_on)
  wide
}

#' Form one decision per document from several reviewers
#'
#' Turns a sheet that several people filled in into the reference
#' [gr_calibrate()] compares the screener with: one consensus decision per
#' document in `human_decision`, beside each reviewer's own.
#'
#' The sheet is the one [gr_reference()] writes with `reviewers` above 1, one
#' `human_decision_<reviewer>` column per reviewer and a `consensus` column for
#' an adjudicator. Reviewer columns can be renamed (`human_decision_AB` for a
#' reviewer's initials, say): every `human_decision_<x>` column is read as one
#' reviewer, except names ending in `_note`, `_notes`, `_comment`, `_comments`
#' or `_date`, which are left alone, so give any other column of notes a name
#' that does not start with `human_decision_`. A long sheet with one row per
#' document per reviewer, a `reviewer` column and `human_decision`, is read
#' too.
#'
#' Where the reviewers who judged a record agree, that is its decision, under
#' every rule; a record only one reviewer judged takes theirs. Where they
#' disagree:
#' * `"majority"`: the decision of more than half of them. A tie is settled by
#'   the `consensus` column where it is filled, and otherwise as `"include"`,
#'   so a reference never excludes a record half its reviewers included. With
#'   two reviewers every disagreement is a tie.
#' * `"any_include"`: `"include"` if any reviewer included it, the
#'   dual-screening convention of carrying a record forward unless both
#'   reviewers exclude it.
#' * `"adjudicated"`: the decision in `consensus`, which an adjudicator fills
#'   in; a disagreement with none is an error. A filled `consensus` takes
#'   precedence on every row, agreed or not.
#'
#' [gr_calibrate()] given a multi-reviewer sheet without a consensus applies
#' `"adjudicated"`, so it stops on a disagreement nobody settled and says how
#' many there were.
#'
#' @param reference The filled-in sheet: a data frame or a path to the CSV.
#' @param rule How a disagreement is settled: `"majority"`, `"any_include"` or
#'   `"adjudicated"`.
#' @return The sheet in wide form, one row per document, with `human_decision`
#'   holding the consensus and `consensus_from` how each row's was reached
#'   (`"unanimous"`, `"one reviewer"`, `"majority"`, `"tie kept"`,
#'   `"any include"`, `"adjudicated"` or `"no decision"`). The rule is kept in
#'   the attribute `consensus_rule`, and the number of documents the reviewers
#'   disagreed on in `conflicts`.
#' @seealso [gr_reference()], [gr_calibrate()]
#' @family corpus functions
#' @export
#' @examples
#' sheet <- data.frame(document = paste0("d", 1:4, ".pdf"),
#'                     human_decision_1 = c("include", "include", "exclude", "exclude"),
#'                     human_decision_2 = c("include", "exclude", "exclude", "include"),
#'                     human_decision_3 = c("include", "exclude", "exclude", "exclude"),
#'                     stringsAsFactors = FALSE)
#' gr_reference_consensus(sheet, "majority")[, c("document", "human_decision",
#'                                               "consensus_from")]
#' gr_reference_consensus(sheet, "any_include")$human_decision
gr_reference_consensus <- function(reference, rule = c("majority", "any_include", "adjudicated")) {
  rule <- match.arg(rule)
  ref <- read_reference(reference)
  wide <- reviewer_sheet(ref)
  if (is.null(wide)) {
    gr_abort(paste0("This sheet holds one decision per document. A consensus needs two or more ",
                    "reviewers: `human_decision_<reviewer>` columns, or a `reviewer` column ",
                    "with each document on one row per reviewer."),
             class = "gr_bad_reference")
  }
  out <- form_consensus(wide, rule)
  if (!inherits(out, "gr_reference_frame")) {
    class(out) <- c("gr_reference_frame", "data.frame")
  }
  out
}

#' The reference gr_calibrate() works with when the sheet has several
#' reviewers: one row per document with the consensus in `human_decision`.
#' NULL for a sheet with one decision per document, which is left as it was.
#' @noRd
reviewer_panel <- function(ref) {
  wide <- reviewer_sheet(ref)
  if (is.null(wide)) return(NULL)
  if (!is.null(wide$consensus_from) && !is.null(wide$human_decision)) {
    # Formed already, by gr_reference_consensus(), and perhaps read back from
    # a file: the rule is whatever the rows say it was.
    if (is.null(attr(wide, "consensus_rule"))) {
      from <- as.character(wide$consensus_from)
      attr(wide, "consensus_rule") <- if (any(from %in% c("majority", "tie kept"))) "majority"
        else if (any(from %in% "any include")) "any_include"
        else if (any(from %in% "adjudicated")) "adjudicated" else NA_character_
    }
    if (is.null(attr(wide, "conflicts"))) {
      cols <- reviewer_columns(wide)
      D <- do.call(cbind, lapply(cols, function(cl) reviewer_decisions(wide[[cl]], cl)))
      attr(wide, "conflicts") <- sum(rowSums(D == "include", na.rm = TRUE) > 0 &
                                       rowSums(D == "exclude", na.rm = TRUE) > 0)
    }
    return(wide)
  }
  form_consensus(wide, "adjudicated", calling = "gr_reference_consensus")
}

#' Human-human agreement and each reviewer's sensitivity and specificity
#' against the consensus, on the rows a calibration used.
#'
#' `rows` are those rows (one per document, the consensus in
#' `human_decision`), `eligible` the consensus as eligible or not, `kept` the
#' screener's decision on each. On a stacked frame each row is weighted by
#' N_h / n_h of its stratum (the screener's kept or excluded records), the
#' weights the recall estimate uses.
#' @noRd
reviewer_summary <- function(rows, eligible, kept, of, tab, positive, conf, rule, conflicts) {
  cols <- reviewer_columns(rows)
  ids <- sub("^human_decision_", "", cols)
  D <- do.call(cbind, lapply(cols, function(cl) reviewer_decisions(rows[[cl]], cl)))
  weighted <- identical(of, "stacked")
  judged <- !is.na(tab$decision)
  N <- c(kept = sum(judged & tab$decision %in% c("include", "unclear")),
         excluded = sum(judged & tab$decision == "exclude"))
  stratum <- ifelse(kept, "kept", "excluded")
  notes <- character(0)

  # Each reviewer against the consensus. A stratum of the frame a reviewer
  # judged nothing in leaves their weighted rates without an estimate, which
  # the notes say rather than leave an unexplained NA.
  if (weighted) {
    for (j in seq_along(cols)) for (h in names(N)) {
      if (N[[h]] > 0 && !any(!is.na(D[, j]) & stratum == h)) {
        notes <- c(notes, sprintf(paste0("Reviewer %s judged no record in the %s stratum, so ",
                                         "their weighted rates cannot be estimated."), ids[j], h))
      }
    }
  }
  sens <- do.call(rbind, lapply(seq_along(cols), function(j) {
    ok <- !is.na(D[, j])
    r_pos <- D[ok, j] == positive
    c_pos <- eligible[ok]
    if (weighted) {
      by <- function(sel) vapply(c("kept", "excluded"), function(h) sum(sel & stratum[ok] == h), 0)
      n <- by(rep(TRUE, sum(ok)))
      s <- weighted_rate(by(r_pos & c_pos), by(!r_pos & c_pos), n, N, conf)
      p <- weighted_rate(by(!r_pos & !c_pos), by(r_pos & !c_pos), n, N, conf)
      method <- "design-weighted, hypergeometric"
    } else {
      s <- hr_prop_ci(sum(r_pos & c_pos), sum(c_pos), conf = conf)
      p <- hr_prop_ci(sum(!r_pos & !c_pos), sum(!c_pos), conf = conf)
      s <- c(s$est, s$lower, s$upper); p <- c(p$est, p$lower, p$upper)
      method <- "wilson"
    }
    data.frame(reviewer = ids[j], statistic = c("sensitivity", "specificity"),
               estimate = c(s[1], p[1]), lower = c(s[2], p[2]), upper = c(s[3], p[3]),
               n = c(sum(c_pos), sum(!c_pos)), method = method, stringsAsFactors = FALSE)
  }))
  rownames(sens) <- NULL

  # Reviewer against reviewer, never kappa alone. The two decisions are
  # factors with include first, so the prevalence index is both-include less
  # both-exclude, the same way round in every table here.
  as_fac <- function(v) factor(v, levels = c("include", "exclude"))
  stat_rows <- function(ag, pair, scope) {
    st <- ag$stats
    data.frame(pair = pair, scope = scope, statistic = st$statistic, estimate = st$estimate,
               lower = st$lower, upper = st$upper, n = ag$n, stringsAsFactors = FALSE)
  }
  scopes <- if (weighted) c("kept", "excluded") else of
  pairs <- utils::combn(seq_along(cols), 2L)
  out <- list()
  for (p in seq_len(ncol(pairs))) {
    i <- pairs[1, p]; j <- pairs[2, p]
    pair <- sprintf("%s vs %s", ids[i], ids[j])
    both <- !is.na(D[, i]) & !is.na(D[, j])
    for (sc in scopes) {
      sel <- both & (if (weighted) stratum == sc else TRUE)
      if (!any(sel)) next
      ag <- hr_agreement(as_fac(D[sel, i]), as_fac(D[sel, j]), B = 2000, conf = conf, seed = 1)
      out[[length(out) + 1L]] <- stat_rows(ag, pair, sc)
      notes <- c(notes, sprintf("%s (%s): %s", pair, sc, ag$notes))
    }
    unseen <- names(N)[N > 0 & !names(N) %in% stratum[both]]
    if (weighted && any(both) && length(unseen)) {
      # Weighting cannot stand in for a stratum with no record judged by both.
      notes <- c(notes, sprintf(paste0("%s (weighted): no record in the %s stratum was judged ",
                                       "by both, so no weighted agreement is given."),
                                pair, unseen[1]))
    } else if (weighted && any(both)) {
      w <- weighted_agreement(D[both, i] == "include", D[both, j] == "include",
                              stratum[both], N, conf)
      out[[length(out) + 1L]] <- data.frame(pair = pair, scope = "weighted", w$stats,
                                            n = sum(both), stringsAsFactors = FALSE)
      if (!is.na(w$note)) notes <- c(notes, sprintf("%s (weighted): %s", pair, w$note))
      # The percentile bootstrap undercovers kappa when a sampled stratum is
      # small: about 80% for a nominal 95% at 30 sampled exclusions, close to
      # nominal from 100 on.
      n_h <- table(factor(stratum[both], levels = names(N)))
      for (h in names(N)) {
        if (!is.na(w$stats$lower[w$stats$statistic == "kappa"]) &&
            n_h[[h]] > 0 && n_h[[h]] < N[[h]] && n_h[[h]] < 100) {
          notes <- c(notes, sprintf(paste0("%s (weighted): the %s sample is %d records, so the ",
                                           "kappa interval is approximate and may be too narrow."),
                                    pair, h, n_h[[h]]))
        }
      }
    }
  }
  if (length(cols) >= 3L) {
    # Krippendorff's alpha over every reviewer at once, per stratum on a
    # stacked frame, since unweighted it would mix the two.
    for (sc in scopes) {
      sel <- if (weighted) stratum == sc else rep(TRUE, nrow(D))
      if (sum(rowSums(!is.na(D[sel, , drop = FALSE])) >= 2L) == 0L) next
      ag <- hr_agreement(coders = D[sel, , drop = FALSE], B = 2000, conf = conf, seed = 1)
      out[[length(out) + 1L]] <- stat_rows(ag, "all reviewers", sc)
      notes <- c(notes, sprintf("all reviewers (%s): %s", sc, ag$notes))
    }
  }
  agreement <- if (length(out)) do.call(rbind, out) else NULL
  if (!is.null(agreement)) rownames(agreement) <- NULL
  from <- as.character(rows$consensus_from %||% rep(NA_character_, nrow(rows)))
  list(reviewers = ids, n_reviewers = length(ids), rule = rule %||% NA_character_,
       conflicts = conflicts %||% NA_integer_,
       consensus = table(factor(from[!is.na(from)])),
       weighted = weighted, sensitivity = sens, agreement = agreement, notes = unique(notes),
       conf = conf)
}

#' A design-weighted rate hit / (hit + miss) over the kept and excluded
#' strata, with exact bounds.
#'
#' `hit`, `miss` and `n` are per-stratum counts among the rows judged and `N`
#' the stratum sizes. The estimate weights each stratum by N / n, as the
#' recall estimate does. Each count in a stratum that was sampled rather than
#' judged whole is bounded with hyper_bounds(), alpha split equally over the
#' counts bounded (Bonferroni), and the rate, which rises with `hit` and falls
#' with `miss`, is bounded by the low hits over the low hits plus the high
#' misses, and the other way round.
#' @noRd
weighted_rate <- function(hit, miss, n, N, conf) {
  alpha <- (1 - conf) / 2
  live <- N > 0
  if (any(live & n == 0)) return(c(NA_real_, NA_real_, NA_real_))
  w <- ifelse(n > 0, N / pmax(n, 1), 0)
  den <- sum(w * (hit + miss))
  est <- if (den > 0) sum(w * hit) / den else NA_real_
  sampled <- live & n < N
  a <- alpha / max(1L, 2L * sum(sampled))
  bh <- vapply(names(N), function(h) hyper_bounds(hit[[h]], n[[h]], N[[h]], a), numeric(2))
  bm <- vapply(names(N), function(h) hyper_bounds(miss[[h]], n[[h]], N[[h]], a), numeric(2))
  c(est, recall_of(sum(bh[1, ]), sum(bm[2, ]), 0), recall_of(sum(bh[2, ]), sum(bm[1, ]), 1))
}

#' Agreement between two binary raters on a stratified sample, from the 2x2
#' table built with weights N_h / n_h.
#'
#' The statistics are those of hr_agreement() on that table: observed
#' agreement po, Cohen's kappa (po - pe) / (1 - pe) with pe from the weighted
#' marginals, PABAK 2 po - 1, Gwet's AC1 (po - pe_g) / (1 - pe_g) with
#' pe_g = 2 q (1 - q), q the mean of the two raters' include shares, and the
#' prevalence and bias indices. Intervals are percentile bootstraps that
#' resample rows within each sampled stratum (B = 2000, seed 1); a stratum
#' judged whole is held fixed, since it has no sampling error. Where the raters
#' agree on every row, or disagree on every row, every resample does the same
#' and the interval would be a point, so none is given; the same holds when
#' every stratum was judged whole, or when the sampled rows alone all agree or
#' all disagree.
#' @noRd
weighted_agreement <- function(x, y, stratum, N, conf, B = 2000L, seed = 1) {
  n_h <- table(factor(stratum, levels = names(N)))
  w <- unname(N[stratum] / as.numeric(n_h[stratum]))
  one <- function(cw) {
    v <- cw * w
    tot <- sum(v)
    a <- sum(v[x & y]) / tot; b <- sum(v[x & !y]) / tot
    c <- sum(v[!x & y]) / tot; d <- sum(v[!x & !y]) / tot
    po <- a + d
    r <- a + b; s <- a + c
    pe <- r * s + (1 - r) * (1 - s)
    q <- (r + s) / 2
    pe_g <- 2 * q * (1 - q)
    c(po, if (abs(1 - pe) > 1e-12) (po - pe) / (1 - pe) else NA_real_, 2 * po - 1,
      if (abs(1 - pe_g) > 1e-12) (po - pe_g) / (1 - pe_g) else NA_real_, a - d, b - c)
  }
  names_ <- c("observed agreement", "kappa", "PABAK", "AC1", "prevalence index", "bias index")
  est <- one(rep(1, length(x)))
  lo <- hi <- rep(NA_real_, 6)
  note <- NA_character_
  groups <- split(seq_along(x), stratum)
  groups <- groups[as.numeric(n_h[names(groups)]) < N[names(groups)]]
  s_rows <- unlist(groups, use.names = FALSE)
  if (all(x == y) || all(x != y)) {
    note <- sprintf("The reviewers %s on every record, so no interval is given.",
                    if (all(x == y)) "agree" else "disagree")
  } else if (!length(groups)) {
    note <- "Every record was judged, so the figures have no sampling error and no interval."
  } else if (length(unique(x[s_rows] == y[s_rows])) == 1L) {
    # Only the sampled rows vary between resamples. If they all agree (or all
    # disagree) the observed agreement is the same in every resample, and the
    # interval would claim a precision the sample cannot show.
    note <- sprintf(paste0("The reviewers %s on every sampled record, so the resamples cannot ",
                           "show the sampling error and no interval is given."),
                    if (x[s_rows][1] == y[s_rows][1]) "agree" else "disagree")
  } else if (B > 0) {
    # Rows of a census stratum keep a weight of 1 in every resample.
    fixed <- rep(1, length(x))
    fixed[s_rows] <- 0
    reps <- with_private_rng(seed, vapply(seq_len(B), function(b) {
      cw <- fixed
      for (g in groups) cw <- cw + tabulate(g[sample.int(length(g), length(g), replace = TRUE)],
                                            length(x))
      one(cw)
    }, numeric(6)))
    a <- 1 - conf
    for (k in 1:4) {
      if (any(!is.na(reps[k, ]))) {
        q <- stats::quantile(reps[k, ], c(a / 2, 1 - a / 2), names = FALSE, na.rm = TRUE,
                             type = 7)
        lo[k] <- q[1]; hi[k] <- q[2]
      }
    }
  }
  list(stats = data.frame(statistic = names_, estimate = est, lower = lo, upper = hi,
                          stringsAsFactors = FALSE),
       note = note)
}

#' The reviewers part of a calibration's print.
#' @noRd
print_calibration_reviewers <- function(x) {
  r <- x[["reviewers", exact = TRUE]]
  if (!is.list(r)) return(invisible(NULL))
  fmt <- function(v) if (is.na(v)) "  --" else sprintf("%5.2f", v)
  pct <- function(v) if (is.na(v)) "--" else sprintf("%.1f%%", 100 * v)
  cat(sprintf("  reviewers: %d; consensus by %s; %s document(s) they disagreed on\n",
              r$n_reviewers, if (is.na(r$rule)) "hand" else r$rule, format(r$conflicts)))
  ag <- r$agreement
  if (!is.null(ag)) {
    scope <- if (r$weighted) "weighted" else unique(ag$scope)[1]
    for (pr in unique(ag$pair[ag$scope == scope])) {
      g <- ag[ag$pair == pr & ag$scope == scope, ]
      shown <- intersect(c("kappa", "PABAK", "AC1", "Krippendorff's alpha", "percent agreement"),
                         g$statistic)
      cat(sprintf("    %s%s:", pr, if (r$weighted) " (design-weighted)" else ""))
      for (s in shown) {
        v <- g[g$statistic == s, ]
        cat(sprintf(" %s %s [%s, %s]", s, trimws(fmt(v$estimate)), trimws(fmt(v$lower)),
                    trimws(fmt(v$upper))))
      }
      cat("\n")
    }
  }
  s <- r$sensitivity
  for (id in unique(s$reviewer)) {
    a <- s[s$reviewer == id & s$statistic == "sensitivity", ]
    b <- s[s$reviewer == id & s$statistic == "specificity", ]
    cat(sprintf("    reviewer %s vs consensus: sensitivity %s [%s, %s], specificity %s [%s, %s]\n",
                id, pct(a$estimate), pct(a$lower), pct(a$upper), pct(b$estimate), pct(b$lower),
                pct(b$upper)))
  }
  invisible(NULL)
}
