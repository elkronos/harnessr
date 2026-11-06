# doc-claims-verify.R: claims checked against the studies, and moderators found.

#' Verify a claim against the table it says it rests on.
#'
#' Four rules, each dropping or clearing rather than repairing:
#'
#'   * A study number that is not in the table is removed. This is the same check
#'     `cited_ids()` makes on finished prose, one link earlier -- and it is the
#'     one that matters most, because everything downstream trusts these numbers.
#'     So is one that IS in the table but was not in the batch the claim came
#'     from (`.shown`, when the rows carry it): the model never saw that study,
#'     so naming it is the same fabrication with a number that happens to exist.
#'   * A claim left with no supporting study is dropped. A claim attached to
#'     nothing is an opinion.
#'   * A study cannot both support and contradict one claim, so it is removed
#'     from the contradicting side and noted.
#'   * A `moderator` naming a column the table does not have is cleared. The
#'     claim may still be sound; the EXPLANATION was invented, and an invented
#'     explanation for a real disagreement is the most convincing kind of error
#'     this layer can make. So is a moderator that names a real column which
#'     does not tell the claim's two sides apart; see moderator_split().
#' @noRd
claims_verify <- function(got, used, cols = study_fields(used)) {
  ids <- used$study
  drops <- list()
  note <- rep(NA_character_, nrow(got))
  add <- function(claim, reason, detail) {
    drops[[length(drops) + 1L]] <<- data.frame(claim = claim, reason = reason, detail = detail,
                                               stringsAsFactors = FALSE)
  }
  keep <- rep(TRUE, nrow(got))
  for (i in seq_len(nrow(got))) {
    sup <- got$.support[[i]]; con <- got$.contradict[[i]]
    bad <- setdiff(c(sup, con), ids)
    if (length(bad)) {
      add(got$claim[i], "study number not in the table", paste(sort(bad), collapse = ", "))
      note[i] <- sprintf("dropped study number(s) %s", paste(sort(bad), collapse = ", "))
    }
    sup <- intersect(sup, ids); con <- intersect(con, ids)
    # Checked against the whole table alone, a claim from batch 2 naming a study
    # only batch 1 was shown was kept as support, with nothing in `$dropped`.
    shown <- if (is.null(got[[".shown"]])) NULL else got[[".shown"]][[i]]
    unseen <- if (is.null(shown)) integer(0) else setdiff(c(sup, con), shown)
    if (length(unseen)) {
      add(got$claim[i], "study number not shown to the batch that wrote the claim",
          paste(sort(unseen), collapse = ", "))
      note[i] <- paste(stats::na.omit(c(note[i], sprintf(
        "dropped study number(s) %s, not shown to its batch", paste(sort(unseen), collapse = ", ")))),
        collapse = "; ")
      sup <- setdiff(sup, unseen); con <- setdiff(con, unseen)
    }
    both <- intersect(sup, con)
    if (length(both)) {
      con <- setdiff(con, both)
      note[i] <- paste(stats::na.omit(c(note[i], sprintf(
        "study %s listed on both sides; kept as supporting", paste(both, collapse = ", ")))),
        collapse = "; ")
    }
    if (!length(sup)) {
      add(got$claim[i], "no supporting study left after verification", "")
      keep[i] <- FALSE
      next
    }
    if (!is.na(got$moderator[i]) && !got$moderator[i] %in% cols) {
      add(got$claim[i], "moderator is not a column in the table", got$moderator[i])
      note[i] <- paste(stats::na.omit(c(note[i], sprintf("cleared moderator '%s'", got$moderator[i]))),
                       collapse = "; ")
      got$moderator[i] <- NA_character_
    }
    if (!got$kind[i] %in% .gr_claim_kinds) got$kind[i] <- "finding"
    got$.support[[i]] <- sort(sup); got$.contradict[[i]] <- sort(con)
  }
  got$note <- note
  got[[".shown"]] <- NULL
  # Existing is not explaining. A moderator naming `design` when every study is
  # an RCT was kept, printed to the writer as "distinguished by: design", and
  # took the claim out of gr_gaps()' unexplained disagreements -- while the same
  # gr_gaps() reported that design never varies.
  split <- claims_moderators(got[keep, , drop = FALSE], used)
  list(claims = split$claims,
       dropped = rbind(if (length(drops)) do.call(rbind, drops) else empty_dropped(),
                       split$dropped))
}

#' Values that say a study did not report the field.
#' @noRd
.gr_unreported <- c("", "na", "n/a", "not reported")

#' Why a moderator column does NOT tell a claim's two sides apart, or NA if it does.
#'
#' The schema asks for "the field that distinguishes the supporting studies from
#' the contradicting ones", and that is a count: the values on one side must not
#' turn up on the other. Numbers must be separable by a threshold -- every
#' supporting value above every contradicting one, or below -- because two sets
#' of sample sizes are always different sets and that explains nothing. Checked
#' only on a contested claim; with nothing on the other side there is nothing
#' to separate, and nothing to count.
#'
#' Strict on purpose. A column that separates most of the studies is cleared,
#' and recorded in `$dropped`: a claim shown as an unexplained disagreement
#' that was mostly explained costs a sentence, while an explanation the table
#' does not bear out is exactly the error this layer exists to stop.
#' @noRd
moderator_split <- function(used, col, sup, con, vals = moderator_values(used, col)) {
  if (!length(con) || !length(sup)) return(NA_character_)
  if (is.null(vals)) return("it is not a column in the table")
  side <- function(ids) {
    x <- vals[match(ids, used$study)]
    x[!is.na(x)]
  }
  a <- side(sup); b <- side(con)
  if (!length(a) || !length(b)) {
    return(sprintf("the table does not report it for any %s study",
                   if (!length(a)) "supporting" else "contradicting"))
  }
  na <- suppressWarnings(as.numeric(a)); nb <- suppressWarnings(as.numeric(b))
  if (!anyNA(na) && !anyNA(nb)) {
    if (max(na) < min(nb) || max(nb) < min(na)) return(NA_character_)
    return(sprintf("its values overlap (%s to %s supporting, %s to %s contradicting)",
                   format(min(na)), format(max(na)), format(min(nb)), format(max(nb))))
  }
  both <- intersect(a, b)
  if (length(both)) {
    return(sprintf("studies on both sides report '%s'", both[1]))
  }
  NA_character_
}

#' A moderator column as moderator_split() compares it: numbers as they are,
#' text trimmed and lower-cased, and "not reported" in any spelling as NA.
#' NULL for a column the table does not have.
#' @noRd
moderator_values <- function(used, col) {
  if (!col %in% names(used)) return(NULL)
  v <- used[[col]]
  if (is.numeric(v)) return(v)
  v <- lower_text(trimws(as.character(v)))
  v[v %in% .gr_unreported] <- NA_character_
  v
}

#' Clear every moderator that does not separate its claim's two sides.
#'
#' For claims whose sides changed after claims_verify() looked at them, which
#' is what a reconcile merge does. Returns the claims and the `$dropped` rows.
#' @noRd
claims_moderators <- function(claims, used) {
  drops <- list()
  # Each column normalised once, not once per claim naming it.
  seen <- list()
  for (i in seq_len(nrow(claims))) {
    m <- claims$moderator[i]
    if (is.na(m)) next
    if (!m %in% names(seen)) seen[m] <- list(moderator_values(used, m))
    why <- moderator_split(used, m, claims$.support[[i]], claims$.contradict[[i]],
                           vals = seen[[m]])
    if (is.na(why)) next
    drops[[length(drops) + 1L]] <- data.frame(
      claim = claims$claim[i],
      reason = "moderator does not separate the supporting from the contradicting studies",
      detail = sprintf("%s: %s", m, why), stringsAsFactors = FALSE)
    claims$note[i] <- paste(stats::na.omit(c(claims$note[i], sprintf(
      "cleared moderator '%s': %s", m, why))), collapse = "; ")
    claims$moderator[i] <- NA_character_
  }
  list(claims = claims, dropped = if (length(drops)) do.call(rbind, drops) else empty_dropped())
}

#' @noRd
empty_dropped <- function() {
  data.frame(claim = character(0), reason = character(0), detail = character(0),
             stringsAsFactors = FALSE)
}
