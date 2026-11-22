# doc-synth-values.R: each extracted value's check, carried into the claims
# and the write-up, and each sentence of a write-up linked to a verified
# record.
#
# gr_extract() checks every value against the sentence it came from, and
# records the result in `$evidence`. The claims and synthesis prompts used to
# show the values alone, so a value whose quote did not verify reached a claim
# exactly as one whose quote did. These helpers carry the check forward.

#' The statuses a value can have, as `$values` reports them.
#' @noRd
.gr_value_status <- c("verified", "unverified", "not reported")

#' Each extracted value's status and quote, one row per study and field.
#'
#' `extraction` is what gr_claims() or gr_synthesise() was given. Only a
#' gr_extraction carries `$evidence`; a bare table has no quotes, and its
#' values get no status (NA), which render_studies() shows as before. Only the
#' schema's fields get a status: a column joined from the records (a title, a
#' DOI) was never extracted, so there is nothing to verify.
#'
#' A value is "verified" when any quote given for it verified, "unverified"
#' when none did or none was given, and "not reported" when the cell is NA.
#' `quote` is the verified quote, else the closest one given, else NA.
#' @noRd
value_status <- function(extraction, used, fields) {
  empty <- data.frame(study = integer(0), document = character(0), field = character(0),
                      value = character(0), status = character(0), quote = character(0),
                      stringsAsFactors = FALSE)
  if (!inherits(extraction, "gr_extraction") || !nrow(used)) return(empty)
  ev <- extraction$evidence
  schema <- names(extraction$fields %||% list())
  fields <- intersect(fields, schema)
  if (!length(fields)) return(empty)
  if (!is.data.frame(ev)) ev <- data.frame(document = character(0), field = character(0))
  key_used <- if (!is.null(used$document_id) && !all(is.na(used$document_id)))
    as.character(used$document_id) else as.character(used$document %||% rep(NA, nrow(used)))
  key_ev <- if (!is.null(ev$document_id) && !is.null(used$document_id) &&
                !all(is.na(used$document_id)))
    as.character(ev$document_id) else as.character(ev$document %||% rep(NA, nrow(ev)))
  rows <- lapply(seq_len(nrow(used)), function(i) {
    lapply(fields, function(f) {
      v <- used[[f]][i]
      if (is.na(v)) {
        return(data.frame(study = used$study[i], field = f, value = NA_character_,
                          status = "not reported", quote = NA_character_,
                          stringsAsFactors = FALSE))
      }
      hit <- which(key_ev == key_used[i] & as.character(ev$field) == f)
      ok <- hit[isTRUE_vec(ev$verified[hit])]
      q <- if (length(ok)) ev$quote[ok[1]] else if (length(hit)) {
        m <- suppressWarnings(as.numeric(ev$match[hit]))
        ev$quote[hit[order(-ifelse(is.na(m), -1, m))][1]]
      } else NA_character_
      data.frame(study = used$study[i], field = f, value = as_chr1(v),
                 status = if (length(ok)) "verified" else "unverified",
                 quote = if (is.null(q) || !nzchar(trimws(as_chr1(q, "")))) NA_character_
                         else as_chr1(q),
                 stringsAsFactors = FALSE)
    })
  })
  out <- do.call(rbind, unlist(rows, recursive = FALSE))
  out$document <- if (is.null(used$document)) NA_character_ else
    as.character(used$document)[match(out$study, used$study)]
  out <- out[, names(empty), drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The values a prompt withholds: the unverified ones, when `exclude` is TRUE.
#' A list, by study number as a string, of the fields withheld for it.
#' @noRd
withheld_values <- function(values, exclude) {
  if (!isTRUE(exclude) || !NROW(values)) return(list())
  un <- values[values$status == "unverified", , drop = FALSE]
  if (!nrow(un)) return(list())
  split(un$field, as.character(un$study))
}

#' The table with the withheld cells set to NA, which is what the model was
#' shown of them: a moderator is checked against that, not against values the
#' prompt left out.
#' @noRd
blank_withheld <- function(used, withheld) {
  for (s in names(withheld)) {
    i <- match(as.integer(s), used$study)
    for (f in withheld[[s]]) used[[f]][i] <- NA
  }
  used
}

#' Whether each study is a verified record: one with at least one value whose
#' quote verified. From `values` when the extraction carried its evidence;
#' else from the table's counts, `n_filled - n_unverified > 0`; else NA.
#' Named by study number.
#' @noRd
study_verified <- function(used, values = NULL) {
  if (NROW(values)) {
    v <- vapply(used$study, function(s) any(values$status[values$study == s] == "verified"),
                logical(1))
  } else if (!is.null(used$n_filled) && !is.null(used$n_unverified)) {
    filled <- suppressWarnings(as.numeric(used$n_filled))
    unver <- suppressWarnings(as.numeric(used$n_unverified))
    v <- filled - unver > 0
  } else {
    v <- rep(NA, nrow(used))
  }
  stats::setNames(as.logical(v), as.character(used$study))
}

#' Every sentence of a marked write-up, linked to the verified records it
#' cites, or flagged.
#'
#' One row per sentence (measured_sentences(): a run of markers after the full
#' stop belongs to the sentence before it): `section` (the heading it stands
#' under, NA before the first), `sentence`, `studies` (the studies it cites
#' that exist, comma-joined, or NA), `verified` (those of them that are
#' verified records), `linked` (TRUE when it cites at least one verified
#' record; NA when the table cannot say which records are verified) and
#' `flag`, why a sentence is not linked: "cites no study", "cites no verified
#' record", or NA.
#' @noRd
sentence_links <- function(text_marked, used, verified, word = "study") {
  empty <- data.frame(section = character(0), sentence = character(0), studies = character(0),
                      verified = character(0), linked = logical(0), flag = character(0),
                      stringsAsFactors = FALSE)
  pc <- figure_pieces(text_marked)
  rows <- lapply(seq_along(pc$text), function(k) {
    sents <- measured_sentences(pc$text[k], word)
    sents <- sents[nzchar(trimws(sents))]
    if (!length(sents)) return(NULL)
    do.call(rbind, lapply(sents, function(s) {
      ids <- intersect(cited_ids(s, word), used$study)
      ok <- verified[as.character(ids)]
      good <- ids[isTRUE_vec(ok)]
      linked <- if (!length(ids)) FALSE else if (length(good)) TRUE else
        if (anyNA(ok)) NA else FALSE
      data.frame(section = pc$heading[k], sentence = trimws(s),
                 studies = if (length(ids)) paste(sort(ids), collapse = ", ") else NA_character_,
                 verified = if (length(good)) paste(sort(good), collapse = ", ") else NA_character_,
                 linked = linked,
                 flag = if (!length(ids)) "cites no study"
                        else if (isFALSE(linked)) "cites no verified record" else NA_character_,
                 stringsAsFactors = FALSE)
    }))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) return(empty)
  rownames(out) <- NULL
  out
}
