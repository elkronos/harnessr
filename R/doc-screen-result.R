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
    cat("  (they are in $forward with the included ones, and listed in $deferred)\n")
  }
  # Records, not rows: a duplicate takes its first copy's resolution, and
  # gr_flow() counts the first copy alone.
  resolved <- sum(!is.na(tab$resolved_by %||% rep(NA, nrow(tab))) & is.na(tab$duplicate_of))
  if (resolved) cat(sprintf("  %d decided by a person with gr_resolve()\n", resolved))
  dup <- sum(!is.na(tab$duplicate_of))
  if (dup) cat(sprintf("  %d were duplicates of a document already screened\n", dup))
  trunc <- sum(tab$truncated, na.rm = TRUE)
  if (trunc) {
    cat(sprintf("  %d decided on the opening of the document, not all of it\n", trunc))
  }
  # The cost with the month of its prices, or the models that have none.
  cost <- hr_trace_cost(x$trace)
  # format_call_counts(), not trace$calls: `calls` counts embeddings requests
  # too, so a run with 2 model calls and 4 embeddings requests printed "6 model
  # call(s)" above a trace that said 2.
  cat(sprintf("  this run: %s, %s\n", format_call_counts(x$trace),
              format_trace_cost(cost)))
  invisible(x)
}

#' @noRd
screening_table <- function(docs, answers, summary, include = character(0),
                            exclude = character(0), criteria_status = FALSE,
                            draws = FALSE) {
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
  # criteria_schema = "per_criterion": each criterion's status, after the
  # deciding criterion's columns.
  if (isTRUE(criteria_status)) {
    st <- vapply(docs, function(d) {
      v <- note(d, "criteria_status", NULL)
      if (is.null(v) || !length(v)) NA_character_
      else paste(sprintf("%s: %s", names(v), v), collapse = "; ")
    }, character(1), USE.NAMES = FALSE)
    st[unread] <- NA_character_
    at <- match("criterion_valid", names(tab))
    tab <- cbind(tab[, seq_len(at), drop = FALSE], criteria_status = st,
                 tab[, -seq_len(at), drop = FALSE], stringsAsFactors = FALSE)
  }
  # samples above 1: what each draw decided, and the share that included.
  if (isTRUE(draws)) {
    sd <- vapply(docs, function(d) as_chr1(note(d, "sample_decisions", NA_character_),
                                           NA_character_), character(1), USE.NAMES = FALSE)
    sh <- vapply(docs, function(d) as_num1(note(d, "include_share", NA_real_), NA_real_),
                 numeric(1), USE.NAMES = FALSE)
    sd[unread] <- NA_character_; sh[unread] <- NA_real_
    at <- match("criterion_valid", names(tab))
    if ("criteria_status" %in% names(tab)) at <- at + 1L
    tab <- cbind(tab[, seq_len(at), drop = FALSE], sample_decisions = sd, include_share = sh,
                 tab[, -seq_len(at), drop = FALSE], stringsAsFactors = FALSE)
  }
  rownames(tab) <- NULL
  tab
}
