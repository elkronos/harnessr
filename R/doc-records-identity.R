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
#'
#' The DOI counts only as a whole DOI: one that runs on into more DOI
#' characters ("10.1000/sp12" for the record's "10.1000/sp1") is another
#' paper in the same series. Inline HTML markup in the title ("<i>", as
#' Crossref, Scopus and Web of Science export it) is taken out before the key
#' is made, and the five basic HTML entities are read as their characters.
#' With `digits = FALSE`, for text a cleaner has taken the digits out of
#' (remove_numbers), the DOI is not looked for and the title is compared
#' without its digits.
#' @noRd
record_identity <- function(text, title = NA_character_, doi = NA_character_, digits = TRUE) {
  txt <- as_chr1(text, "")
  if (!nzchar(trimws(txt))) return(NA)
  head <- substr(txt, 1L, .gr_identity_chars)
  doi <- lower_text(trimws(as_chr1(doi, NA_character_)))
  if (digits && !is.na(doi) && nzchar(doi) &&
      grepl(paste0("(?<![\\p{L}\\p{N}])", literal_pattern(doi),
                   "(?![\\p{L}\\p{N}]|[-._;()/:]+[\\p{L}\\p{N}])"),
            lower_text(head), perl = TRUE)) return(TRUE)
  tk <- title_key(plain_title(as_chr1(title, NA_character_)))
  hk <- title_key(head)
  if (!digits) {
    tk <- gsub("\\p{N}+", "", tk, perl = TRUE)
    hk <- gsub("\\p{N}+", "", hk, perl = TRUE)
  }
  if (is.na(tk) || nchar(tk) < 12L) return(NA)
  if (!is.na(hk) && grepl(tk, hk, fixed = TRUE)) return(TRUE)
  FALSE
}

#' A record title without inline HTML markup: tags out, and &amp;, &lt;,
#' &gt;, &quot; and &#39; read as their characters.
#' @noRd
plain_title <- function(x) {
  if (is.na(x)) return(x)
  x <- gsub("</?[A-Za-z][A-Za-z0-9]*(?:\\s[^<>]*)?/?>", "", x, perl = TRUE)
  from <- c("&lt;", "&gt;", "&quot;", "&#39;", "&amp;")
  to <- c("<", ">", "\"", "'", "&")
  for (i in seq_along(from)) x <- gsub(from[i], to[i], x, fixed = TRUE)
  x
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
#' warning names the function the user called. `steps` are the cleaning steps
#' the text went through: after remove_numbers no digit is left, so the DOI
#' cannot be found and the title is compared without its digits.
#' @noRd
check_record_identity <- function(doc_text, record, label, steps = character(0)) {
  if (is.null(record)) return(NA)
  digits <- !("remove_numbers" %in% steps)
  ok <- record_identity(doc_text, record$title, record$doi, digits = digits)
  if (identical(ok, FALSE)) attr(ok, "message") <- identity_message(label, record$doi, digits)
  ok
}

#' The words every identity mismatch message starts with after the label.
#' restored_identity() finds an old run's message in a `warnings` cell by them.
#' @noRd
.gr_identity_marker <- "may not be the paper its record names: the opening of its text"

#' The sentence a mismatch warns with. It names what was looked for: the
#' title and the DOI, the title alone when the record has no DOI, or the
#' title alone with the reason when the cleaning took the digits out and the
#' DOI could not be looked for.
#' @noRd
identity_message <- function(label, doi, digits) {
  has_doi <- !is.na(as_chr1(doi, NA_character_)) && nzchar(trimws(doi))
  what <- if (has_doi && digits) {
    "has neither the record's title nor its DOI"
  } else if (has_doi) {
    paste0("does not have the record's title (its DOI was not looked for, because the ",
           "cleaning took the digits out)")
  } else {
    "does not have the record's title, and the record has no DOI"
  }
  sprintf(paste0("'%s' %s %s. It is read and kept; check the file by hand (the `identity` ",
                 "column is FALSE)."), label, .gr_identity_marker, what)
}

#' What a stored identity check was made against: a hash of the record's
#' title and DOI, or "none" for a source with no record. NULL for a run with
#' no record set, which made no check.
#' @noRd
identity_fingerprint <- function(record, check = TRUE) {
  if (!check) return(NULL)
  if (is.null(record)) return("none")
  gr_hash(list("readgpt-identity-v1", as_chr1(record$title, NA_character_),
               as_chr1(record$doi, NA_character_)))
}

#' A row restored from a store, with an identity check that fits this run.
#'
#' The store key does not depend on the record set, so the same entry
#' restores into runs that pair the file with different records, or with
#' none. The stored `identity` and its warning hold only for the record the
#' storing run checked. `stored` is that record's identity_fingerprint() as
#' the entry keeps it (NULL for an entry written before it was kept, or by a
#' run with no record set), and `record` is this run's record for the source.
#'
#' With the same record the row is kept as stored. Otherwise the old run's
#' mismatch warning is taken out of `warnings`, and in a run with a record set
#' `identity` is NA; when this run has a record for the source, a note in
#' `warnings` says that the check needs the document read again. The store
#' does not keep the document's text, so the check cannot be made here.
#' @noRd
restored_identity <- function(row, stored, record, check, label) {
  now <- identity_fingerprint(record, check)
  if (!is.null(now) && identical(stored, now)) return(row)
  w <- row[["warnings", exact = TRUE]]
  have <- if (is.null(w) || is.na(w)) character(0) else strsplit(w, " | ", fixed = TRUE)[[1]]
  have <- have[!grepl(.gr_identity_marker, have, fixed = TRUE)]
  if (check && !is.null(record)) {
    have <- c(have, sprintf(paste0(
      "'%s' was restored from `store`, and the stored result was not checked against this ",
      "run's record for it. Whether it is the paper its record names needs the document read ",
      "again: run without `store`, or delete its entry (the `identity` column is NA)."), label))
  }
  row$warnings <- corpus_warnings(have)
  row$identity <- if (check) NA else NULL
  row
}
