# doc-segment-structural.R: the structural segmenter.

#' What `structural` writes where a chunk has no heading above it.
#'
#' A literal, not NA, because the column is also a display label. That made it
#' invisible to every downstream test of the form `all(is.na(section))` --
#' `preview` read it as "this document has structure" and planned one unit for
#' the whole thing. Named here so the producer and the consumers cannot disagree
#' about the spelling.
#' @noRd
.gr_no_section <- "[no section]"

#' @noRd
seg_structural <- function(doc, spec, client, trace) {
  b <- doc$blocks
  sec <- b$section
  # `is_head[i]` records that block i is ITSELF the heading line, not merely that
  # it belongs to that section. The prefix below re-states the heading, so the
  # heading block has to be dropped from the body or every section chunk begins
  # with the title twice.
  is_head <- rep(FALSE, nrow(b))
  # Fall back to detecting headings inline when the extractor found none.
  if (all(is.na(sec))) {
    # Capitals of any script, not A-Z: with ASCII classes a French heading
    # starting with an accented capital, or any Cyrillic one, was never a
    # heading, so its text was filed, and prefixed, under the heading before
    # it -- and a Russian document found none at all. After a number, a letter
    # of a script without case (Chinese, Arabic) also starts a heading.
    is_head <- grepl(paste0("^(#{1,6}[ \t]|\\d+(\\.\\d+)*[ \t.)]+[\\p{Lu}\\p{Lt}\\p{Lo}]|",
                            "\\p{Lu}[\\p{Lu}\\p{N} ,'\u2019&/-]{6,}$)"),
                     mark_utf8(b$text), perl = TRUE) & gr_count_tokens(b$text) < 30L
    # The label is the heading line as written, less any markdown hashes. The
    # heading block is dropped from the body below and this label is prefixed
    # in its place, so it has to carry the whole line: the normalised form
    # stripped leading numbers, and "2022 Results" and "2023 Results" both
    # became "## Results", leaving neither year in any chunk -- and a
    # year-led sentence taken for a heading lost its year the same way.
    cur <- NA_character_
    for (i in seq_len(nrow(b))) {
      if (is_head[i]) cur <- trimws(sub("^#{1,6}[ \t]*", "", trimws(b$text[i]), perl = TRUE))
      sec[i] <- cur
    }
  } else {
    # The extractor supplied sections. A block whose entire text is the section
    # label is the heading itself. Normalise BOTH sides: the extractor's label
    # for "## 3.1 Methods" is "3.1 Methods" while the block text still carries
    # the hashes, so comparing a normalised label against a raw one never
    # matched and the title was emitted twice.
    is_head <- !is.na(sec) & heading_label(b$text) == heading_label(sec)
  }
  sec[is.na(sec)] <- .gr_no_section
  # One group per unbroken run of a section, not per label. Grouping by label
  # gathered every section of the same name into the first one: a paper's two
  # studies each with a "Methods" gave one chunk holding both studies' methods,
  # placed before the second study's heading, and a document's preamble was
  # joined to trailing endnotes because both had no section. Order is the
  # document's, and a run never crosses a heading.
  run <- cumsum(c(TRUE, sec[-1L] != sec[-length(sec)]))[seq_along(sec)]
  groups <- split(seq_len(nrow(b)), run)
  out <- character(0); pg <- integer(0); sc <- character(0); bid <- integer(0)
  for (idx in groups) {
    nm <- sec[idx[1]]
    labelled <- isTRUE(spec$prefix_section) && !identical(nm, .gr_no_section)
    # Drop the heading block only when the prefix will carry it. Without the
    # prefix, dropping it would lose the heading text from the document.
    body_idx <- if (labelled) idx[!is_head[idx]] else idx
    if (!length(body_idx)) {
      # The section is nothing but its heading -- a document title, a part
      # divider. Skipping it dropped that text from the chunk set entirely, so
      # the document's own title reached no reader. Emit the heading as its own
      # chunk instead, unprefixed (the prefix would only repeat it).
      body_idx <- idx
      labelled <- FALSE
    }
    # Section title is prepended so a chunk retains its heading even when the
    # section is long enough to need several chunks.
    prefix <- if (labelled) paste0("## ", nm, "\n\n") else ""
    packed <- pack_units(b$text[body_idx],
                         max(spec$max_tokens - gr_count_tokens(prefix), 32L),
                         spec$overlap_tokens, spec$min_tokens,
                         meta = b[body_idx, c("page", "section", "block_id"), drop = FALSE])
    if (!length(packed$text)) next
    m <- packed$meta
    out <- c(out, paste0(prefix, packed$text))
    # Each chunk reports the block it STARTS at, not the section's first block:
    # a five-chunk section used to claim every chunk came from block 1.
    pg  <- c(pg,  if (is.null(m)) rep(b$page[body_idx[1]], length(packed$text)) else m$page)
    sc  <- c(sc,  rep(nm, length(packed$text)))
    bid <- c(bid, if (is.null(m)) rep(b$block_id[body_idx[1]], length(packed$text)) else m$block_id)
  }
  new_chunks(out, "structural", spec, page = pg, section = sc, block_id = bid)
}

#' Normalise a heading line into a bare label.
#'
#' Strips markdown hashes, section numbering and trailing colons. Used to
#' compare a block's text against its section label, which reach `seg_structural`
#' in different shapes: the markdown extractor stores "3.1 Methods" while the
#' block itself still reads "## 3.1 Methods". The label the segmenter PREFIXES
#' is the extractor's section string, or for a heading found inline the heading
#' line itself, never this normalised form.
#' @noRd
heading_label <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("^#{1,6}[ \t]*", "", x, perl = TRUE)
  x <- sub("^\\d+(?:\\.\\d+)*[ \t.)]+", "", x, perl = TRUE)
  x <- sub("[ \t:.\u2014-]+$", "", x, perl = TRUE)
  trimws(x)
}
