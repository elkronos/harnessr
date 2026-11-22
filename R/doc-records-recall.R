# doc-records-recall.R: how much of a known set of papers a search found.
#
# A search cannot be checked against every relevant paper, because nobody
# knows them all. It can be checked against the papers the review team already
# knows are relevant: the seed set. The share of those the search returned is
# relative recall. A seed that helped write the search says nothing about it,
# since the search was built to find it, so those are left out and counted.
#
# Which seed is which record is decided by dedupe_records(), the rules
# gr_records() uses to decide that two records are one work. A seed those
# rules refuse to match (a short title, a title and year shared by records
# with different DOIs) counts as not found and is listed with the reason, as a
# record they refuse to merge is kept apart: a wrong match is worse than none.

#' Measure a search against papers you already know are relevant
#'
#' Known-item recall: the share of a seed set of relevant papers that a search
#' returned. Each seed is matched to the search's records by the rules
#' [gr_records()] uses to find duplicates, so a seed counts as found when those
#' rules would call it the same work as one of the records. The figure comes
#' with an exact (Clopper-Pearson) interval from [hr_prop_ci()], overall and
#' for each tier when `tier` is given.
#'
#' Nothing here calls a model.
#'
#' @section Relative recall:
#' The figure is recall relative to the seed set: the share of the papers you
#' already knew that the search found, not the share of every relevant paper
#' that exists. Seeds are rarely a random sample of the relevant literature.
#' They tend to be the well-known, well-indexed papers a search finds most
#' easily, so the figure is usually higher than recall against everything
#' relevant. Report it as relative recall, with the number of seeds and how
#' they were chosen, as PRISMA-S asks a review to describe how its search was
#' tested.
#'
#' A seed used to write the search (to pick its terms, or to test drafts of
#' it) is found because the search was built to find it. Mark those with a
#' logical `used_to_build` column in `known`, or give the seeds kept out of
#' the search in `held_out`. They are left out of the figure and listed in
#' `$excluded`.
#'
#' @section Seeds that cannot be matched:
#' A seed is matched exactly as [gr_records()] merges duplicates (see its
#' `dedupe` argument, `"doi+title"`): by DOI, or by title and year with the
#' first author or the venue agreeing. Where those rules refuse a match, the
#' seed counts as not found, and `$missed` says why in `reason`:
#' \describe{
#'   \item{`"short_title"`}{A record has the seed's title and year, but the
#'     title has fewer than 12 letters or digits ("Reply", "Editorial"), which
#'     the rules never match on.}
#'   \item{`"multi_doi"`}{Records with the seed's title and year carry two or
#'     more different DOIs between them and the seed, so the title cannot say
#'     which work the seed is.}
#'   \item{`"not_confirmed"`}{A record has the seed's title and year, but the
#'     first author or the venue disagrees, nothing beyond the title confirms
#'     it, or it could be either of two records.}
#'   \item{`"no_identifier"`}{The seed has no DOI and no title with a year.}
#'   \item{`"not_in_records"`}{No record has the seed's DOI, or its title and
#'     year.}
#' }
#' The first three are listed again in `$refused`: a search that returned the
#' paper under another record can show as a miss there, and a person should
#' look at those rows before the figure is reported.
#'
#' @param records The search's results: a [gr_records()], or a data frame
#'   with its columns (`title`, `year`, `doi`, `authors` and `venue` are the
#'   ones used). Every row counts, duplicates included.
#' @param known The seed set: a [gr_records()] read from an export of the
#'   papers, or a data frame with `doi`, or `title` and `year`, and where it
#'   has them `authors` and `venue`. A logical `used_to_build` column marks
#'   the seeds used to write the search. An empty seed set is refused.
#' @param tier `NULL`, the name of a column of `known`, or one value per seed:
#'   a grouping set by a person (say, core papers and the rest), to report
#'   recall for each group as well as overall. A seed without a tier, and a
#'   tier left with no seed once the seeds used to build the search are out,
#'   are refused.
#' @param held_out `NULL`, or the seeds kept out of the search: a logical
#'   vector with one value per seed, or their row numbers. Every other seed is
#'   counted as used to build the search. A seed marked both `held_out` and
#'   `used_to_build` is refused.
#' @param conf Confidence level of the intervals.
#' @return An object of class `gr_search_recall`:
#'   \describe{
#'     \item{`recall`}{One row for all seeds (`tier` is `"all"`) and one per
#'       tier: `found`, `n` (seeds counted), `estimate`, `lower`, `upper`,
#'       `method` (`"clopper_pearson"`) and `conf`.}
#'     \item{`seeds`}{One row per seed: `seed` (its row in `known`), `label`,
#'       `tier`, `used_to_build`, `found` (`NA` for a seed left out),
#'       `record_id` (the record it matched) and `reason`.}
#'     \item{`missed`}{The seeds counted and not found, with `reason`.}
#'     \item{`refused`}{The missed seeds the matching rules refused, as
#'       described above.}
#'     \item{`excluded`}{The seeds left out as used to build the search.}
#'     \item{`note`}{The sentence saying what the figure is relative to.}
#'   }
#' @references
#' Sampson, M., Zhang, L., Morrison, A., Barrowman, N. J., Clifford, T. J.,
#' Platt, R. W., Klassen, T. P. and Moher, D. (2006). An alternative to the
#' hand searching gold standard: validating methodological search filters
#' using relative recall. *BMC Medical Research Methodology* 6, 33.
#'
#' Rethlefsen, M. L., Kirtley, S., Waffenschmidt, S., Ayala, A. P., Moher, D.,
#' Page, M. J., Koffel, J. B. and PRISMA-S Group (2021). PRISMA-S: an
#' extension to the PRISMA Statement for Reporting Literature Searches in
#' Systematic Reviews. *Systematic Reviews* 10, 39.
#'
#' Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or fiducial
#' limits illustrated in the case of the binomial. *Biometrika* 26(4),
#' 404-413.
#' @seealso [gr_records()], [gr_search()], [gr_audit_report()], [hr_prop_ci()]
#' @family corpus functions
#' @export
#' @examples
#' found <- data.frame(
#'   title = c("Spaced practice and long-term retention in adults",
#'             "Retrieval practice in the classroom: a field trial",
#'             "Interleaving mathematics problems improves test scores"),
#'   year = c("2019", "2021", "2015"),
#'   doi = c("10.1000/sp1", NA, "10.1000/il3"),
#'   authors = c("Smith, J.", "Okafor, A.", "Lee, K."),
#'   stringsAsFactors = FALSE)
#' seeds <- data.frame(
#'   title = c("Spaced practice and long-term retention in adults",
#'             "Retrieval practice in the classroom: a field trial",
#'             "Sleep and memory consolidation in students",
#'             "Interleaving mathematics problems improves test scores"),
#'   year = c("2019", "2021", "2020", "2015"),
#'   doi = c(NA, NA, "10.1000/sl9", "10.1000/il3"),
#'   authors = c("Smith, J.", "Okafor, A.", "Diaz, M.", "Lee, K."),
#'   used_to_build = c(FALSE, FALSE, FALSE, TRUE),
#'   tier = c("core", "core", "other", "other"),
#'   stringsAsFactors = FALSE)
#' r <- gr_search_recall(found, seeds, tier = "tier")
#' r
#' r$missed
gr_search_recall <- function(records, known, tier = NULL, held_out = NULL, conf = 0.95) {
  check_conf(conf)
  recs <- recall_frame(records, "records")
  seeds_raw <- if (inherits(known, "gr_records")) known$records else known
  if (!is.data.frame(seeds_raw)) {
    gr_abort("`known` must be a gr_records() or a data frame of seed papers.",
             class = "gr_bad_seeds")
  }
  n <- nrow(seeds_raw)
  if (!n) {
    gr_abort(paste0("`known` holds no seed papers. Recall against an empty set is not a ",
                    "figure: give the papers you already know are relevant."),
             class = "gr_bad_seeds")
  }
  used <- seed_used(seeds_raw, held_out, n)
  tiers <- seed_tiers(seeds_raw, tier, n)
  seeds <- recall_frame(seeds_raw, "known")

  match <- seed_matches(recs, seeds)
  found <- !is.na(match$record_id)
  label <- seed_label(seeds)
  tab <- data.frame(seed = seq_len(n), label = label,
                    tier = if (is.null(tiers)) NA_character_ else tiers,
                    used_to_build = used, found = ifelse(used, NA, found),
                    record_id = match$record_id, reason = match$reason,
                    stringsAsFactors = FALSE)
  tab$reason[found] <- NA_character_
  counted <- !used
  if (!any(counted)) {
    gr_abort(sprintf(paste0("All %d seed(s) were used to build the search, so none is left to ",
                            "measure it with. Keep some known papers out of the search's ",
                            "design and give them in `held_out`."), n),
             class = "gr_bad_seeds")
  }
  groups <- list(all = counted)
  if (!is.null(tiers)) {
    lv <- if (is.factor(tiers)) levels(tiers) else unique(as.character(tiers))
    for (t in lv) groups[[t]] <- counted & as.character(tiers) == t
    empty <- names(groups)[-1][vapply(groups[-1], function(g) !any(g), logical(1))]
    if (length(empty)) {
      gr_abort(sprintf(paste0("Tier %s has no seed left to count once the seeds used to build ",
                              "the search are out. A recall for an empty tier is not a figure: ",
                              "add seeds to it, or drop the tier."),
                       paste(sprintf("'%s'", empty), collapse = ", ")),
               class = "gr_bad_seeds")
    }
  }
  k <- vapply(groups, function(g) sum(found & g), integer(1))
  m <- vapply(groups, sum, integer(1))
  ci <- hr_prop_ci(k, m, method = "clopper_pearson", conf = conf)
  recall <- data.frame(tier = names(groups), found = unname(k), n = unname(m),
                       estimate = ci$est, lower = ci$lower, upper = ci$upper,
                       method = "clopper_pearson", conf = conf, stringsAsFactors = FALSE)
  if (is.null(tiers)) tab$tier <- NULL
  missed <- tab[counted & !found, , drop = FALSE]
  refused <- missed[missed$reason %in% c("short_title", "multi_doi", "not_confirmed"), ,
                    drop = FALSE]
  rownames(missed) <- NULL; rownames(refused) <- NULL
  excluded <- tab[used, , drop = FALSE]
  rownames(excluded) <- NULL
  structure(list(
    recall = recall, seeds = tab, missed = missed, refused = refused, excluded = excluded,
    n_records = nrow(recs),
    note = paste0("Recall is relative to the seed set: the share of the papers already known ",
                  "to be relevant that the search found, not the share of every relevant paper.")
  ), class = "gr_search_recall")
}

#' @export
print.gr_search_recall <- function(x, ...) {
  pct <- function(v) if (is.na(v)) "--" else sprintf("%.1f%%", 100 * v)
  r <- x$recall
  cat(sprintf("<gr_search_recall> %d of %d seed(s) found among %d record(s)\n",
              r$found[1], r$n[1], as.integer(x$n_records)))
  for (i in seq_len(nrow(r))) {
    cat(sprintf("  %-14s %3d/%-3d %6s  [%s, %s]\n", r$tier[i], r$found[i], r$n[i],
                pct(r$estimate[i]), pct(r$lower[i]), pct(r$upper[i])))
  }
  cat(sprintf("  (%.0f%% Clopper-Pearson intervals)\n", 100 * r$conf[1]))
  cat(sprintf("  %s\n", paste(strwrap(x$note, width = 74, exdent = 2), collapse = "\n")))
  if (nrow(x$excluded)) {
    cat(sprintf("  %d seed(s) used to build the search are left out (see $excluded)\n",
                nrow(x$excluded)))
  }
  if (nrow(x$refused)) {
    cat(sprintf(paste0("  ! %d missed seed(s) were refused by the matching rules, not absent: ",
                       "check them by hand\n"), nrow(x$refused)))
  }
  for (i in utils::head(seq_len(nrow(x$missed)), 8)) {
    cat(sprintf("    missed: %s (%s)\n", x$missed$label[i], x$missed$reason[i]))
  }
  if (nrow(x$missed) > 8L) cat(sprintf("    ... and %d more\n", nrow(x$missed) - 8L))
  invisible(x)
}

# --- internals -------------------------------------------------------------

#' A gr_records or a data frame of records, as the record columns.
#' @noRd
recall_frame <- function(x, arg) {
  df <- if (inherits(x, "gr_records")) x$records else x
  if (!is.data.frame(df)) {
    gr_abort(sprintf("`%s` must be a gr_records() or a data frame of records.", arg),
             class = "gr_bad_seeds")
  }
  if (!any(c("doi", "title") %in% names(df))) {
    gr_abort(sprintf("`%s` has neither a `doi` nor a `title` column, so nothing can be matched.",
                     arg), class = "gr_bad_seeds")
  }
  if (!nrow(df)) return(empty_records())
  finish_records(df[, intersect(names(df), .gr_record_cols), drop = FALSE])
}

#' Which seeds were used to build the search: the `used_to_build` column,
#' every seed not in `held_out`, or both, which must not contradict.
#' @noRd
seed_used <- function(seeds, held_out, n) {
  col <- seeds[["used_to_build"]]
  used <- rep(FALSE, n)
  if (!is.null(col)) {
    if (!is.logical(col) || anyNA(col)) {
      gr_abort("`used_to_build` must be TRUE or FALSE for every seed.", class = "gr_bad_seeds")
    }
    used <- col
  }
  if (is.null(held_out)) return(used)
  keep <- if (is.logical(held_out)) {
    if (length(held_out) != n || anyNA(held_out)) {
      gr_abort(sprintf("A logical `held_out` needs one TRUE or FALSE per seed (%d).", n),
               class = "gr_bad_seeds")
    }
    held_out
  } else if (is.numeric(held_out) && !anyNA(held_out) && all(held_out == round(held_out)) &&
             all(held_out >= 1 & held_out <= n)) {
    seq_len(n) %in% held_out
  } else {
    gr_abort(sprintf("`held_out` must be NULL, one TRUE or FALSE per seed, or row numbers from 1 to %d.",
                     n), class = "gr_bad_seeds")
  }
  clash <- keep & used
  if (any(clash)) {
    gr_abort(sprintf(paste0("%d seed(s) are marked both held out and used to build the search, ",
                            "starting with row %d. Say which it was."), sum(clash),
                     which(clash)[1]), class = "gr_bad_seeds")
  }
  !keep
}

#' Each seed's tier, or NULL.
#' @noRd
seed_tiers <- function(seeds, tier, n) {
  if (is.null(tier)) return(NULL)
  v <- if (is.character(tier) && length(tier) == 1L && !is.na(tier) && tier %in% names(seeds)) {
    seeds[[tier]]
  } else if (is.character(tier) && length(tier) == 1L && n != 1L) {
    gr_abort(sprintf("`known` has no column '%s' to read tiers from.", tier),
             class = "gr_bad_seeds")
  } else tier
  if (length(v) != n) {
    gr_abort(sprintf("`tier` must name a column of `known` or give one value per seed (%d).", n),
             class = "gr_bad_seeds")
  }
  if (!is.factor(v)) v <- as.character(v)
  blank <- is.na(v) | !nzchar(trimws(as.character(v)))
  if (any(blank)) {
    gr_abort(sprintf("%d seed(s) have no tier, starting with row %d. Give every seed one.",
                     sum(blank), which(blank)[1]), class = "gr_bad_seeds")
  }
  if (any(as.character(v) == "all")) {
    gr_abort("\"all\" is the name of the overall row; call that tier something else.",
             class = "gr_bad_seeds")
  }
  v
}

#' A short name for each seed: first author, year and the start of the title,
#' or the DOI.
#' @noRd
seed_label <- function(seeds) {
  fa <- record_first_author(seeds$authors)$surname
  ti <- ifelse(is.na(seeds$title), NA_character_,
               ifelse(nchar(seeds$title) > 60, paste0(substr(seeds$title, 1, 57), "..."),
                      seeds$title))
  lab <- ifelse(is.na(ti), seeds$doi, ti)
  who <- ifelse(is.na(fa), "", paste0(fa, " ", ifelse(is.na(seeds$year), "", seeds$year), ": "))
  lab <- paste0(who, ifelse(is.na(lab), "(no title or DOI)", lab))
  trimws(lab)
}

#' The title key dedupe_records() matches on, and the same key without its
#' floor on short titles.
#' @noRd
recall_keys <- function(recs) {
  tk <- title_key(recs$title)
  raw <- ifelse(is.na(tk) | is.na(recs$year), NA_character_, paste0(tk, "|", recs$year))
  key <- raw
  key[!is.na(tk) & nchar(tk) < 12L] <- NA_character_
  list(key = key, raw = raw)
}

#' The record each seed is the same work as, and why a seed has none.
#'
#' dedupe_records() is run on the seed after the records that share its DOI
#' or title key, and the records those share a DOI or key with, until no more
#' join. That is every record its decision can depend on: it groups rows only
#' through equal DOIs and equal title keys, so the result is the one a run on
#' all the records followed by the seed would give, without parsing every
#' author list once per seed.
#' @noRd
seed_matches <- function(recs, seeds) {
  n <- nrow(seeds)
  out <- list(record_id = rep(NA_integer_, n), reason = rep(NA_character_, n))
  rk <- recall_keys(recs)
  sk <- recall_keys(seeds)
  cols <- intersect(c("record_id", "authors", "year", "title", "venue", "doi"), .gr_record_cols)
  for (s in seq_len(n)) {
    doi <- seeds$doi[s]
    dois <- if (is.na(doi)) character(0) else doi
    keys <- if (is.na(sk$key[s])) character(0) else sk$key[s]
    cand <- rep(FALSE, nrow(recs))
    repeat {
      grow <- (!is.na(recs$doi) & recs$doi %in% dois) | (!is.na(rk$key) & rk$key %in% keys)
      if (identical(grow | cand, cand)) break
      cand <- grow | cand
      dois <- unique(c(dois, stats::na.omit(recs$doi[cand])))
      keys <- unique(c(keys, stats::na.omit(rk$key[cand])))
    }
    if (any(cand)) {
      sub <- rbind(recs[cand, cols, drop = FALSE], seeds[s, cols, drop = FALSE])
      sub$record_id <- c(which(cand), 0L)
      rownames(sub) <- NULL
      hit <- dedupe_records(sub, "doi+title")[nrow(sub)]
      if (!is.na(hit)) {
        out$record_id[s] <- as.integer(hit)
        next
      }
    }
    same_title <- !is.na(sk$raw[s]) & !is.na(rk$raw) & rk$raw == sk$raw[s]
    out$reason[s] <- if (is.na(doi) && is.na(sk$raw[s])) {
      "no_identifier"
    } else if (!any(same_title)) {
      "not_in_records"
    } else if (is.na(sk$key[s])) {
      "short_title"
    } else if (length(unique(stats::na.omit(c(doi, recs$doi[same_title])))) > 1L) {
      "multi_doi"
    } else {
      "not_confirmed"
    }
  }
  out
}
