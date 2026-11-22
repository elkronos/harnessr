# doc-synth-recheck.R: what a write-up leaves uncited, sentences that cite a
# contradicting study without a hedge, and the checks run again on a text a
# person edited.

#' The studies the text as published cites nowhere.
#'
#' `cited` is the final cited set: the studies the published text cites by a
#' rendered citation (what the reference list follows). `section_studies` is
#' the studies each section was shown, so `shown` says whether a section's
#' prompt held the study at all: an uncited study that was shown is one the
#' writer passed over; one that was not was never put in front of it. A count,
#' not a quota: nothing asks that every study be cited. `shown` is NA when
#' `section_studies` is not a table, as for a synthesis saved before it was
#' kept: what each section was shown is then unknown.
#' @noRd
synth_uncited <- function(used, cited, section_studies) {
  left <- !used$study %in% cited
  known <- is.data.frame(section_studies)
  shown_any <- if (known) unique(as.integer(section_studies$study)) else integer(0)
  data.frame(study = used$study[left],
             document = if (is.null(used$document)) rep(NA_character_, sum(left))
                        else as.character(used$document[left]),
             document_id = if (is.null(used$document_id)) rep(NA_character_, sum(left))
                           else as.character(used$document_id[left]),
             shown = if (known) used$study[left] %in% shown_any else rep(NA, sum(left)),
             stringsAsFactors = FALSE)
}

#' The studies each section was shown, long: `section`, `study`.
#' @noRd
section_studies_table <- function(rows) {
  parts <- lapply(rows, function(r) {
    s <- as.integer(r$shown %||% integer(0))
    if (!length(s)) return(NULL)
    data.frame(section = r$row$section[1], study = sort(unique(s)), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, parts)
  if (is.null(out)) out <- data.frame(section = character(0), study = integer(0),
                                      stringsAsFactors = FALSE)
  rownames(out) <- NULL
  out
}

#' Words that say a sentence reports a disagreement rather than a finding.
#' @noRd
.gr_contrast_words <- c("however", "but", "although", "though", "whereas", "while",
                        "contrast", "except", "mixed", "inconsistent", "conflict",
                        "contradict", "disagree", "differ", "unlike", "despite")

#' The content words of a text, cut to their first five letters so that
#' "improves" and "improved" are one word.
#' @noRd
content_stems <- function(text) {
  low <- lower_text(gsub(cite_grammar("study")$marker, " ", as_chr1(text, ""), perl = TRUE,
                         ignore.case = TRUE))
  w <- strsplit(low, "[^\\p{L}\\p{N}]+", perl = TRUE)[[1]]
  w <- w[nchar(w) >= 4L & !w %in% .gr_revise_stopwords]
  unique(substr(w, 1L, 5L))
}

#' Sentences that state a claim and cite a study that contradicts it,
#' without a hedge or a word of contrast. No model is asked.
#'
#' A sentence states claim C when it stands in a section C was given (any
#' section, for a heading that is not one of `sections`, the write-up's
#' own), cites a study C rests
#' on either way, points in C's direction in one of its clauses
#' (claim_polarity(), clause_points()), and shares at
#' least two content words with C (one, for a claim with fewer than two). If
#' it then cites a study on C's contradicting side and carries no hedge
#' (`.gr_hedges`) and no word of contrast ("however", "but", "mixed"), it
#' reports that study as agreeing with a claim it contradicts. One row per
#' sentence, claim and study: `section`, `sentence`, `claim_id`, `study`.
#' @noRd
contradiction_flags <- function(text_marked, claims, claim_sections = NULL,
                                sections = character(0), word = "study") {
  empty <- data.frame(section = character(0), sentence = character(0), claim_id = integer(0),
                      study = integer(0), stringsAsFactors = FALSE)
  if (!inherits(claims, "gr_claims") || !NROW(claims$claims)) return(empty)
  cw <- claims$claims
  sup <- claims$support
  con_ids <- unique(sup$claim_id[sup$role == "contradicts"])
  if (!length(con_ids)) return(empty)
  stems <- lapply(cw$claim, content_stems)
  pols <- claim_polarity(cw$claim)
  pc <- figure_pieces(text_marked)
  rows <- list()
  for (k in seq_along(pc$text)) {
    head <- pc$heading[k]
    given <- if (is.data.frame(claim_sections) && !is.na(head) &&
                 head %in% as.character(claim_sections$section)) {
      as.integer(claim_sections$claim_id[as.character(claim_sections$section) == head])
    } else if (!is.na(head) && head %in% sections) integer(0) else cw$claim_id
    for (s in measured_sentences(pc$text[k], word)) {
      ids <- cited_ids(s, word)
      if (!length(ids)) next
      low <- lower_text(s)
      hedged <- sum(count_marks(low, .gr_hedges)) > 0L ||
        any(vapply(.gr_contrast_words, function(w) grepl(paste0("\\b", w, "\\b"), low,
                                                           perl = TRUE), logical(1)))
      if (hedged) next
      # Read clause by clause: "improved mood, with no adverse events" or
      # "improved mood and lowered anxiety" still states that mood improved,
      # though the whole sentence holds a negation or a decrease.
      spol <- claim_polarity(sentence_clauses(s, word))
      sst <- content_stems(s)
      for (i in which(cw$claim_id %in% intersect(given, con_ids))) {
        id <- cw$claim_id[i]
        against <- intersect(ids, sup$study[sup$claim_id == id & sup$role == "contradicts"])
        if (!length(against) || !clause_points(spol, pols[i, ])) next
        need <- if (length(stems[[i]]) < 2L) 1L else 2L
        if (sum(sst %in% stems[[i]]) < need) next
        rows[[length(rows) + 1L]] <- data.frame(section = head, sentence = trimws(s),
                                                claim_id = as.integer(id),
                                                study = as.integer(against),
                                                stringsAsFactors = FALSE)
      }
    }
  }
  out <- do.call(rbind, rows)
  if (is.null(out)) return(empty)
  rownames(out) <- NULL
  out
}

#' A sentence cut into its clauses, its citation markers removed: at commas,
#' semicolons, colons and brackets, and before "and", "while", "whereas" and
#' "with".
#' @noRd
sentence_clauses <- function(sentence, word = "study") {
  x <- gsub(cite_grammar(word)$marker, " ", as_chr1(sentence, ""), perl = TRUE,
            ignore.case = TRUE)
  parts <- strsplit(x, "[,;:()]|\\s(?=(?:and|while|whereas|with)\\b)", perl = TRUE)[[1]]
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) "" else parts
}

#' Whether any clause, read by claim_polarity() into `clauses`, points in
#' the direction of the claim read into `claim`: it agrees with it
#' (polarity_agree()), and says something about direction where the claim
#' does.
#' @noRd
clause_points <- function(clauses, claim) {
  known <- polarity_known(claim)
  any(vapply(seq_len(nrow(clauses)), function(k) {
    polarity_agree(clauses[k, ], claim) && (!known || polarity_known(clauses[k, ]))
  }, logical(1)))
}

#' Check and render an edited write-up again
#'
#' [gr_synthesise()] keeps `$text_marked`, the write-up with its `[study N]`
#' markers, so that the checks can be run again on the text as published.
#' Edit that text, by hand or with another tool, and pass it here: every
#' check that reads the text runs on it again, and the citations and the
#' reference list are rendered from it as `gr_synthesise()` renders them.
#' Nothing is sent to a model.
#'
#' The checks are those of `gr_synthesise()`. A marker naming a row that
#' does not exist, or a study the section under whose heading it stands was
#' not shown, is left as a marker and counted; one the check cannot read is
#' counted. Each is warned about (`gr_recheck_citations`). A heading the
#' write-up did not have is checked against every study any section was
#' shown. A study cited honestly under one heading keeps its rendered
#' citation and its reference even where another heading cites it without
#' being shown it. The figures are checked against the rows their sentence
#' cites, with the `style` and `figure_bands` the write-up was made with, as
#' the revised text of a write-up is (`stage` `"edited"` in `$figures`); the
#' sentences are linked to verified records again; and `$uncited` and
#' `$contradictions` are worked out again. The sections, their counts and
#' `$draft` are left as written: they describe the draft, not the edit.
#' For a synthesis saved before `$section_studies` was kept, `shown` in
#' `$uncited` is `NA`, since what each section was shown is not known.
#'
#' @param synthesis A [gr_synthesise()] result.
#' @param text_marked The edited write-up, in the marker form of
#'   `synthesis$text_marked`: citations as `[study N]`, sections under `## `
#'   headings, and no reference list (one is appended from what it cites).
#'   Defaults to `synthesis$text_marked`, which renders the write-up again.
#' @return The `gr_synthesis`, with `text_marked` the edited text, `text`
#'   rendered from it, and `references`, `figures`, `sentences`, `uncited`
#'   and `contradictions` worked out again, and `recheck`, a list of
#'   `unknown` (studies cited that are not in the table), `unsupplied`
#'   (studies cited under a heading whose section was not shown them) and
#'   `unparsed` (citations the check cannot read).
#' @seealso [gr_synthesise()]
#' @export
#' @examples
#' tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok",
#'                   n_filled = 1L, n_unverified = 0L, n = c(120L, 300L))
#' cl <- gr_mock_client(function(messages, params) "One trial enrolled 120 people [study 1].")
#' s <- gr_synthesise(tab, question = "How large were the trials?",
#'                    outline = c(Findings = "Sample sizes"), client = cl)
#' edited <- paste0(s$text_marked, " Another enrolled 300 [study 2]. A third [study 9].")
#' r <- suppressWarnings(gr_recheck(s, edited))
#' r$recheck$unknown
#' r$uncited
gr_recheck <- function(synthesis, text_marked = synthesis$text_marked) {
  if (!inherits(synthesis, "gr_synthesis")) {
    gr_abort("`synthesis` must come from gr_synthesise().", class = "gr_bad_synthesis")
  }
  if (!is.character(text_marked) || length(text_marked) != 1L || is.na(text_marked)) {
    gr_abort("`text_marked` must be one string: the write-up in its [study N] marker form.",
             class = "gr_bad_synthesis")
  }
  text_marked <- mark_utf8(text_marked)
  x <- synthesis
  used <- x$studies
  word <- "study"
  cols <- x$bib_columns %||% bib_columns(used)
  keys <- bib_keys(used, cols)
  style <- x$cite_style %||% "marker"
  sec_st <- x$section_studies
  shown_all <- if (is.data.frame(sec_st)) unique(sec_st$study) else used$study

  cited <- cited_ids(text_marked, word)
  unknown <- sort(setdiff(cited, used$study))
  unparsed <- unparsed_citations(text_marked, word)
  # Rendered piece by piece, each under its heading, leaving a marker for a
  # study that piece's section was not shown.
  lines <- strsplit(text_marked, "\n", fixed = TRUE)[[1]]
  is_head <- grepl("^#{1,6}[[:space:]]", lines)
  group <- cumsum(is_head)
  heads <- c(NA_character_,
             trimws(sub("[ \t]+#+[ \t]*$", "", sub("^#{1,6}[[:space:]]+", "", lines[is_head]))))
  unsupplied <- integer(0)
  # The studies some piece rendered: a study one heading cites without being
  # shown it, and another cites honestly, is cited by the published text and
  # keeps its reference, as in gr_synthesise().
  ok <- integer(0)
  pieces <- vapply(sort(unique(group)), function(g) {
    piece <- paste(lines[group == g], collapse = "\n")
    head <- heads[g + 1L]
    shown <- if (is.data.frame(sec_st) && !is.na(head) && head %in% sec_st$section)
      sec_st$study[sec_st$section == head] else shown_all
    here <- intersect(cited_ids(piece, word), used$study)
    leave <- setdiff(here, shown)
    unsupplied <<- c(unsupplied, leave)
    ok <<- c(ok, setdiff(here, leave))
    render_citations(piece, used, keys, style, leave = leave)
  }, character(1))
  unsupplied <- sort(unique(unsupplied))
  ok <- sort(unique(ok))
  published <- paste(pieces, collapse = "\n")
  refs <- if (length(x$references)) reference_list(used, keys, ok, cols, style) else NULL
  if (length(unknown) || length(unsupplied) || length(unparsed)) {
    gr_warn(sprintf(paste0("The edited text cites %s. Those markers are left as written and kept ",
                           "out of the reference list; see `$recheck`."),
                    paste(c(if (length(unknown)) sprintf("study %s, not in the table",
                                                         paste(unknown, collapse = ", ")),
                            if (length(unsupplied)) sprintf(
                              "study %s under a heading whose section was not shown %s",
                              paste(unsupplied, collapse = ", "),
                              if (length(unsupplied) == 1L) "it" else "them"),
                            if (length(unparsed)) sprintf("%d citation(s) the check cannot read",
                                                          length(unparsed))),
                          collapse = "; ")),
            class = "gr_recheck_citations")
  }

  hide <- unlist(cols, use.names = FALSE)
  rendered <- render_studies(used, hide = hide, values = x$values)
  # The register text and the bands the write-up was checked with, so an
  # unchanged text gets the figures gr_synthesise() gave it. A synthesis saved
  # before they were kept is checked with no style and the default bands.
  figs <- synth_figures(x$sections, text_marked, used, rendered, x$question, claims = x$claims,
                        assign_map = x$claim_sections, gaps = x$gaps,
                        closing = x$closing %||% NA_character_, style = x[["style", exact = TRUE]],
                        hide = hide, bands = x[["figure_bands", exact = TRUE]] %||% .gr_figure_bands)
  ft <- figs$table
  ft$stage[ft$stage == "final"] <- "edited"
  attr(ft, "published") <- "edited"

  x$text_marked <- text_marked
  x$text <- append_references(published, refs)
  x$references <- refs
  x$figures <- ft
  x$sentences <- sentence_links(text_marked, used, study_verified(used, x$values))
  x$uncited <- synth_uncited(used, ok, sec_st)
  x$contradictions <- contradiction_flags(text_marked, x$claims, x$claim_sections,
                                          sections = x$sections$section)
  x$recheck <- list(unknown = unknown, unsupplied = unsupplied, unparsed = unparsed)
  x
}
