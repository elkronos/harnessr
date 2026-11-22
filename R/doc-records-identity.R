# doc-records-identity.R: is the file matched to a record the paper it names?
#
# match_files() gives a record a file by the path the export recorded, by the
# DOI in a filename, by a filename that spells the title, or by one that names
# the first author and the year. The last can pick the wrong paper by the
# same author in the same year, and a library's attachment can be the wrong
# PDF. Either way every later stage reads one paper and reports it as another.
# The paper's own first page names it: its title, and usually its DOI. So the
# opening of the extracted text is checked for them. Nothing is dropped on a
# mismatch; the run warns and the result says which documents failed.

#' How much of the start of a document is searched for its title and DOI.
#'
#' A title page, with a publisher's cover sheet before it: about two pages of
#' text. Set when the check was written; untested.
#' @noRd
.gr_identity_chars <- 6000L

#' Whether a document's opening names the record it was matched to.
#'
#' `TRUE` when the record's DOI or its title (as title_key(), the key
#' deduplication compares) occurs in the first .gr_identity_chars characters
#' of the text. `FALSE` when the record has a title of 12 or more letters or
#' digits, the floor deduplication uses, and neither it nor the DOI occurs
#' there. `NA` when there is nothing to check: no text, or a record with only
#' a DOI the opening does not print (many older papers never print theirs),
#' or only a short title.
#' @noRd
record_identity <- function(text, title = NA_character_, doi = NA_character_) {
  txt <- as_chr1(text, "")
  if (!nzchar(trimws(txt))) return(NA)
  head <- substr(txt, 1L, .gr_identity_chars)
  doi <- lower_text(trimws(as_chr1(doi, NA_character_)))
  if (!is.na(doi) && nzchar(doi) && grepl(doi, lower_text(head), fixed = TRUE)) return(TRUE)
  tk <- title_key(as_chr1(title, NA_character_))
  if (is.na(tk) || nchar(tk) < 12L) return(NA)
  hk <- title_key(head)
  if (!is.na(hk) && grepl(tk, hk, fixed = TRUE)) return(TRUE)
  FALSE
}

#' The record a corpus source was matched to, as a one-row frame, or NULL.
#'
#' A source from a record set is the `file` of a kept record (see
#' corpus_sources()). Compared as given, then as normalised paths, so a
#' screening's `included` paths written another way still find their record.
#' @noRd
source_record <- function(src, record_set) {
  if (!inherits(record_set, "gr_records") || !is.character(src) || length(src) != 1L ||
      is.na(src)) return(NULL)
  r <- record_set$records
  if (is.null(r$file)) return(NULL)
  kept <- which(is.na(r$duplicate_of %||% rep(NA, nrow(r))) & !is.na(r$file))
  if (!length(kept)) return(NULL)
  hit <- kept[r$file[kept] == src]
  if (!length(hit)) {
    norm <- function(p) tryCatch(normalizePath(p, winslash = "/", mustWork = FALSE),
                                 error = function(e) p)
    hit <- kept[vapply(r$file[kept], norm, character(1), USE.NAMES = FALSE) == norm(src)]
  }
  if (length(hit) != 1L) return(NULL)
  r[hit, , drop = FALSE]
}

#' Check one ingested document against its record: the result of
#' record_identity(), or NA without a record, with the sentence to warn with
#' on a mismatch as its `message` attribute. The caller warns, so the
#' warning names the function the user called.
#' @noRd
check_record_identity <- function(doc_text, record, label) {
  if (is.null(record)) return(NA)
  ok <- record_identity(doc_text, record$title, record$doi)
  if (identical(ok, FALSE)) {
    attr(ok, "message") <- sprintf(paste0(
      "'%s' may not be the paper its record names: the opening of its text has neither the ",
      "record's title%s. It is read and kept; check the file by hand (the `identity` column ",
      "is FALSE)."), label, if (is.na(record$doi)) "" else " nor its DOI")
  }
  ok
}
