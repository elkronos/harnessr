# doc-screen-result.R: the screening result and how it prints.

#' @export
print.gr_screening <- function(x, ...) {
  tab <- x$table
  cat(sprintf("<gr_screening> %d document(s) screened against %d criteri%s\n",
              nrow(tab), length(x$include) + length(x$exclude),
              if (length(x$include) + length(x$exclude) == 1L) "on" else "a"))
  dec <- table(factor(tab$decision, levels = c("include", "exclude", "unclear")))
  cat(sprintf("  %s\n", paste(sprintf("%d %s", as.integer(dec), names(dec)), collapse = ", ")))
  undecided <- sum(is.na(tab$decision))
  if (undecided) {
    cat(sprintf("  %d could not be read and have NO decision; these are outstanding\n",
                undecided))
  }
  if (sum(tab$decision == "unclear", na.rm = TRUE)) {
    cat("  'unclear' means the excerpt did not settle it; those are for a person\n")
  }
  dup <- sum(!is.na(tab$duplicate_of))
  if (dup) cat(sprintf("  %d were duplicates of a document already screened\n", dup))
  trunc <- sum(tab$truncated, na.rm = TRUE)
  if (trunc) {
    cat(sprintf("  %d decided on the opening of the document, not all of it\n", trunc))
  }
  cost <- gr_trace_cost(x$trace)
  total <- if (nrow(cost)) sum(cost$usd) else 0
  # format_call_counts(), not trace$calls: `calls` counts embeddings requests
  # too, so a run with 2 model calls and 4 embeddings requests printed "6 model
  # call(s)" above a trace that said 2.
  cat(sprintf("  this run: %s, %s\n", format_call_counts(x$trace),
              if (!nrow(cost)) "no cost recorded"
              else if (is.na(total)) "cost unknown (unpriced model)"
              else sprintf("$%.4f", total)))
  invisible(x)
}

#' @noRd
screening_table <- function(docs, answers, summary, include = character(0),
                            exclude = character(0)) {
  note <- function(d, field, default) {
    a <- answers[[d]]
    if (is.null(a)) default else {
      v <- a$notes[[field]]
      if (is.null(v)) default else v
    }
  }
  ev_of <- function(d) {
    a <- answers[[d]]
    if (is.null(a) || !is.data.frame(a$evidence) || !nrow(a$evidence)) NULL else a$evidence[1, ]
  }
  tab <- data.frame(
    document    = as.character(docs),
    document_id = as.character(summary$document_id %||% NA_character_),
    # NA, not "unclear", when the document was never read. "Unclear" is a
    # judgement about a document someone looked at; this is the absence of one.
    decision    = vapply(docs, function(d) as_chr1(note(d, "decision", NA_character_),
                                                   NA_character_),
                         character(1), USE.NAMES = FALSE),
    reason      = vapply(docs, function(d) as_chr1(note(d, "reason", NA_character_),
                                                   NA_character_),
                         character(1), USE.NAMES = FALSE),
    criterion   = vapply(docs, function(d) as_chr1(note(d, "criterion", NA_character_),
                                                   NA_character_),
                         character(1), USE.NAMES = FALSE),
    criterion_valid = rep(NA, length(docs)),   # filled in below
    quote       = vapply(docs, function(d) {
                    e <- ev_of(d); if (is.null(e)) NA_character_ else as_chr1(e$text)
                  }, character(1), USE.NAMES = FALSE),
    verified    = vapply(docs, function(d) {
                    e <- ev_of(d)
                    if (is.null(e) || is.null(e$verified)) NA else as.logical(e$verified)
                  }, logical(1), USE.NAMES = FALSE),
    seen_tokens = vapply(docs, function(d) as_int1(note(d, "seen_tokens", NA_integer_)),
                         integer(1), USE.NAMES = FALSE),
    document_tokens = vapply(docs, function(d) as_int1(note(d, "document_tokens", NA_integer_)),
                             integer(1), USE.NAMES = FALSE),
    truncated   = vapply(docs, function(d) {
                    v <- note(d, "truncated", NA); if (is.null(v)) NA else isTRUE(v)
                  }, logical(1), USE.NAMES = FALSE),
    status      = as.character(summary$status),
    duplicate_of = as.character(summary$duplicate_of %||% NA_character_),
    error       = as.character(summary$error),
    stringsAsFactors = FALSE
  )
  unread <- !summary$status %in% c("ok", "restored", "duplicate")
  tab$decision[unread] <- NA_character_
  tab$truncated[unread] <- NA
  # Checked again here, for answers a store restored from a run made before
  # read_screen() checked them. On an answer it did check this changes nothing.
  crit <- screen_criterion(tab$decision, tab$criterion, include, exclude)
  if (any(crit$downgraded)) {
    tab$reason[crit$downgraded] <- downgrade_reason(tab$criterion[crit$downgraded],
                                                    tab$reason[crit$downgraded])
  }
  tab$decision <- crit$decision
  tab$criterion <- crit$criterion
  tab$criterion_valid <- crit$valid
  rownames(tab) <- NULL
  tab
}
