# doc-synth-render.R: the studies table written into a prompt.

#' The fields `render_studies()` actually shows the model.
#'
#' Shared so that a check on what the model may name cannot drift from what the
#' model was shown. `claims_verify()` used the reserved-field list instead, which
#' differs from this in both directions, and accepted a moderator naming a column
#' that had been withheld from the prompt.
#' @noRd
study_fields <- function(used, hide = character(0)) {
  meta <- c("document", "document_id", "status", "duplicate_of", "error",
            "n_filled", "n_unverified", "conflicts", "study")
  setdiff(names(used), c(meta, hide))
}

#' The table as text the model can cite.
#'
#' One block per row, numbered, with the field values and the document it came
#' from. The number is what a section cites, and it is positional within THIS
#' synthesis -- `$studies` carries it alongside `document_id` so a citation can
#' always be resolved back to a document.
#'
#' `values` is value_status(): with it each extracted value is shown with its
#' check and its quote, `n: 120 (verified quote: "We enrolled 120 people.")`,
#' so the writer can tell a value the document was found to state from one it
#' was not. `withhold` (withheld_values()) names the values left out entirely,
#' by study: gr_claims() leaves out the unverified ones by default. A table
#' with no evidence (a bare data frame) has no `values`, and is shown as
#' before.
#' @noRd
render_studies <- function(used, hide = character(0), values = NULL, withhold = list()) {
  fields <- study_fields(used, hide)
  # Every value and name labelled UTF-8, as gr_synthesise() labels the question
  # and the headings these blocks are sent after. A table read in under a
  # non-UTF-8 locale holds unlabelled bytes, and paste() joining them to
  # labelled text -- another column, or the brief restated after the studies
  # -- escaped them to "<c3><a9>".
  txt <- vapply(fields, function(f) is.character(used[[f]]) || is.factor(used[[f]]), logical(1))
  for (f in fields[txt]) used[[f]] <- mark_utf8(as.character(used[[f]]))
  labels <- stats::setNames(mark_utf8(fields), fields)
  has_values <- NROW(values) > 0L
  if (has_values) values$quote <- mark_utf8(as.character(values$quote))
  vapply(seq_len(nrow(used)), function(i) {
    gone <- withhold[[as.character(used$study[i])]] %||% character(0)
    keep <- fields[!fields %in% gone]
    vals <- vapply(keep, function(f) {
      v <- used[[f]][i]
      if (is.na(v)) return(sprintf("%s: not reported", labels[[f]]))
      line <- sprintf("%s: %s", labels[[f]], as_chr1(v))
      if (!has_values) return(line)
      at <- which(values$study == used$study[i] & values$field == f)
      if (!length(at)) return(line)
      q <- values$quote[at[1]]
      paste0(line, switch(values$status[at[1]],
        verified = sprintf(" (verified quote: \"%s\")", q),
        unverified = if (is.na(q)) " (unverified: no quote given)"
                     else sprintf(" (unverified: the quote given, \"%s\", did not verify)", q),
        ""))
    }, character(1), USE.NAMES = FALSE)
    # The study NUMBER and nothing else. The filename used to be here, and
    # academic PDFs are routinely called "Smith2019_CognitiveLoad.pdf" -- which
    # hands a model asked to cite `[study 1]` an author and a year anyway,
    # through the one field nobody thought of as bibliographic. `$citations`
    # resolves the number back to its document for the audit; the writing model
    # has no use for it.
    paste0("[study ", used$study[i], "]\n", paste(vals, collapse = "\n"))
  }, character(1), USE.NAMES = FALSE)
}
