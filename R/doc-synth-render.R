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
#' @noRd
render_studies <- function(used, hide = character(0)) {
  fields <- study_fields(used, hide)
  # Every value and name labelled UTF-8, as gr_synthesise() labels the question
  # and the headings these blocks are sent after. A table read in under a
  # non-UTF-8 locale holds unlabelled bytes, and paste() joining them to
  # labelled text -- another column, or the brief restated after the studies
  # -- escaped them to "<c3><a9>".
  txt <- vapply(fields, function(f) is.character(used[[f]]) || is.factor(used[[f]]), logical(1))
  for (f in fields[txt]) used[[f]] <- mark_utf8(as.character(used[[f]]))
  labels <- stats::setNames(mark_utf8(fields), fields)
  vapply(seq_len(nrow(used)), function(i) {
    vals <- vapply(fields, function(f) {
      v <- used[[f]][i]
      if (is.na(v)) sprintf("%s: not reported", labels[[f]])
      else sprintf("%s: %s", labels[[f]], as_chr1(v))
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
