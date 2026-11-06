# doc-audit-flow.R: how many documents reached each stage of a review.

#' Count what happened to every document
#'
#' The numbers a flow diagram is made of, from what a run already recorded.
#' Every source is accounted for at every stage it reached, so the arithmetic
#' closes: nothing leaves the count without a row saying why.
#'
#' For a screening, the records screened split into include, exclude, unclear,
#' could not be read (no screening call was made) and screening call failed,
#' and those five rows sum to "screened". "resolved by a person" counts the
#' decisions above that a person made with [gr_resolve()]. "kept for full
#' text" is `$forward` (include and unclear), and "deferred to full text" the
#' unclear part of it, `$deferred`.
#'
#' @param screening A `gr_screening` from [gr_screen()], or `NULL`.
#' @param extraction A `gr_extraction` from [gr_extract()], or `NULL`.
#' @return A data frame of `stage`, `n` and `note`.
#' @param claims A [gr_claims()] result, to add the claim-level counts.
#' @param records A [gr_records()], so the counts begin where the search did:
#'   records identified, duplicates removed, reports sought and reports never
#'   retrieved. Without one the diagram starts at "sources given", which is
#'   already past the step that decides whether the review can be repeated.
#' @seealso [gr_audit_report()], [gr_screen()], [gr_extract()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(messages, params) {
#'   '{"decision":"include","reason":"Reports a revenue figure.",
#'     "criterion":"Reports a revenue figure","quote":null}'
#' })
#' f <- tempfile(fileext = ".txt"); writeLines("Revenue was 45.2 million.", f)
#' s <- gr_screen(f, question = "What was revenue?",
#'                include = "Reports a revenue figure", client = cl)
#' gr_flow(s)
gr_flow <- function(screening = NULL, extraction = NULL, records = NULL, claims = NULL) {
  rows <- list()
  add <- function(stage, n, note = "") {
    rows[[length(rows) + 1L]] <<- data.frame(stage = stage, n = as.integer(n),
                                             note = note, stringsAsFactors = FALSE)
  }
  # The rows above "screened", which a folder of PDFs cannot produce and which
  # PRISMA item 16 requires: how many records the search returned, how many were
  # the same work, and how many reports were sought but never obtained. Without
  # a record set the diagram starts at "sources given", which is already past
  # the step that decides whether the review can be repeated.
  if (inherits(records, "gr_records")) {
    for (i in seq_len(nrow(records$counts))) {
      st <- records$counts$stage[i]
      add(st, records$counts$n[i],
          switch(st,
                 "records identified" = paste(sprintf("%s %d", names(records$by_database),
                                                      as.integer(records$by_database)),
                                              collapse = ", "),
                 "duplicates removed" = sprintf("same work by %s", records$dedupe),
                 "reports not retrieved" = "no document was found for these records",
                 ""))
    }
  }
  if (!is.null(screening)) {
    t <- screening$table
    own <- is.na(t$duplicate_of)
    dup <- sum(!own)
    add("sources given", nrow(t))
    add("duplicates removed", dup, "same cleaned text as a document already seen")
    add("screened", nrow(t) - dup)
    for (d in c("include", "exclude", "unclear")) {
      add(sprintf("  %s", d), sum(!is.na(t$decision) & t$decision == d & own),
          if (d == "unclear") "the excerpt did not settle it; deferred to a person" else "")
    }
    # A record with no decision either never reached the model or reached it
    # and got nothing usable back. Both are outstanding, but they are fixed in
    # different places (the file, or the provider), so they are counted apart.
    # A request was made when the record's own trace counted one.
    none <- is.na(t$decision) & own
    calls <- screening$summary$calls
    asked <- if (length(calls) == nrow(t)) !is.na(calls) & calls > 0L else rep(FALSE, nrow(t))
    add("  could not be read", sum(none & !asked),
        paste0("no decision was recorded; these are outstanding. No screening call was ",
               "made: the document could not be read, or a limit stopped it"))
    add("  screening call failed", sum(none & asked),
        paste0("no decision was recorded; these are outstanding. The call failed or its ",
               "reply was not the form asked for"))
    # Counted under the decision the person gave, above; this row says how
    # many of those decisions are a person's rather than the screener's.
    add("  resolved by a person", sum(!is.na(t$resolved_by %||% rep(NA, nrow(t))) & own),
        "decided with gr_resolve(); counted above under the person's decision")
    fwd <- sum(!is.na(t$decision) & t$decision %in% c("include", "unclear") & own)
    add("kept for full text", fwd, "include and unclear: $forward")
    add("  deferred to full text", sum(!is.na(t$decision) & t$decision == "unclear" & own),
        paste0("unclear: $deferred. gr_extract(screening) reads only the included ones ",
               "in this release, and warns when it leaves these out"))
  }
  if (!is.null(extraction)) {
    t <- extraction$table
    dup <- sum(!is.na(t$duplicate_of))
    # Each row below counts distinct documents only, and no document twice, so
    # none can come to more than "extracted from".
    own <- is.na(t$duplicate_of %||% rep(NA, nrow(t)))
    add("extracted from", nrow(t) - dup)
    # And no value given that went unverified: a row with nothing filled can
    # still have had values, unreadable as their field's type, rejected, or
    # dropped under require_quote. Those are counted under "values
    # unsupported" below, and were also said here to be absent from the
    # document. An unknown count (NA, or no column) is not a zero either.
    nu <- t[["n_unverified"]] %||% rep(NA_integer_, nrow(t))
    add("  reported nothing", sum(t$status %in% c("ok", "restored") & !is.na(t$n_filled) &
                                    t$n_filled == 0L & nu %in% 0L & own),
        "read successfully; none of the fields are in the document")
    # "incomplete" has values, so it is not a failed read: counted there, it
    # was described as having none and a table of real values looked empty.
    # Its empty cells are the part that is outstanding.
    add("  read in part", sum(t$status %in% "incomplete" & own),
        "a request failed; the values are real, but an empty cell is unknown, not unreported")
    add("  failed to read", sum(!t$status %in% c("ok", "restored", "duplicate", "incomplete") &
                                  own),
        "no values; these are outstanding")
    # Not "no verbatim span": a sentence that is in the chunk word for word but
    # does not state the value is unverified too (verified = FALSE, match = 1).
    # Distinct documents only, as "extracted from" is: a duplicate row carries
    # its first copy's values and count, and summed with them it counted the
    # same unsupported values twice.
    add("values unsupported", sum(t$n_unverified[own], na.rm = TRUE),
        paste0("not verified: no quote, a quote not found in the chunk cited, or one that ",
               "does not state the value in any form the check reads"))
  }
  if (inherits(claims, "gr_claims")) {
    cw <- claims$claims
    # Studies whose claims batch came back with nothing. Without this row a
    # claims table missing most of the corpus read as complete here, although
    # gr_claims() had warned and recorded them. `%||%` for a claims table saved
    # before the field existed.
    add("studies lost to a claims batch", length(claims$lost %||% integer(0)),
        "their claims batch was cut off at the reply limit, failed or not sent; see $lost")
    # 1 when the claims of several batches were never reconciled into one
    # list, so the counts below may count one finding more than once.
    # isTRUE() for a claims table saved before the field existed.
    add("claims not reconciled across batches", as.integer(isTRUE(claims$unmerged)),
        "the reconcile pass could not run; one finding may appear as more than one claim")
    add("claims drawn", nrow(cw), "statements about the literature, each attached to studies")
    add("  contested", sum(cw$n_contradict > 0L), "studies on both sides")
    add("  unexplained", sum(cw$n_contradict > 0L & is.na(cw$moderator)),
        "contested with nothing in the table to explain the split")
    add("  on one study", sum(cw$n_support == 1L), "no replication in this corpus")
    # `$dropped` has a row for three different events, and only one of them
    # removes a claim: a bad study number is taken off a claim that is kept, a
    # moderator that is not a column is cleared from one. Counted as one
    # number, "claims dropped 3" was quoted for a run that dropped none.
    why <- as.character(claims$dropped$reason %||% character(0))
    detail <- as.character(claims$dropped$detail %||% rep(NA_character_, length(why)))
    refs <- grepl("^study number", why)
    add("claims dropped", sum(why == "no supporting study left after verification"),
        "no supporting study was left after verification; see the claims object's $dropped")
    add("study numbers removed", sum(lengths(strsplit(detail[refs & !is.na(detail)], ",",
                                                         fixed = TRUE))),
        paste0("cited a study not in the table, or one not shown to the batch; the claim ",
               "stays if others remain"))
    add("moderators cleared", sum(why == "moderator is not a column in the table"),
        "named a column the table does not have; the claim is kept without it")
  }
  if (!length(rows)) {
    return(data.frame(stage = character(0), n = integer(0), note = character(0),
                      stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
