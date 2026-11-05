# doc-segment-basic.R: the fixed, paragraph, sentence, recursive and page
# segmenters.

# ---------------------------------------------------------------------------

#' @noRd
seg_fixed <- function(doc, spec, client, trace) {
  # Deliberately structure-blind: a sliding window over the token stream.
  w <- words_of(doc$text)
  if (!length(w)) return(new_chunks(character(0), "fixed", spec))
  # Convert the token cap into a word count via the live tokenizer instead of
  # assuming 1 word == 1 token (the assumption that made every old limit wrong).
  # Build each window by measuring, not by assuming a constant token/word ratio.
  # The ratio estimate produced windows over the cap, which the enforcement pass
  # then re-cut, destroying the overlap.
  # Each window's end and each overlap are found by longest_fit(), not by
  # growing one word at a time: that re-counted the whole window at every word,
  # so a window cost O(W^2) and a 1e5-token cap took minutes on a long report.
  n <- length(w)
  count_words <- function(a, b) gr_count_tokens(paste(w[a:b], collapse = " "))
  txt <- list()
  i <- 1L
  while (i <= n) {
    # Always consume at least one word.
    last <- i - 1L + max(longest_fit(n - i + 1L, function(k)
      count_words(i, i + k - 1L) <= spec$max_tokens), 1L)
    txt[[length(txt) + 1L]] <- paste(w[i:last], collapse = " ")
    if (last >= n) break
    # Step forward by the window minus the requested overlap, measured in
    # words: the longest tail of the window under overlap_tokens, leaving at
    # least one word of progress.
    back <- longest_fit(last - i, function(k)
      count_words(last - k + 1L, last) < spec$overlap_tokens)
    i <- max(last - back + 1L, i + 1L)
  }
  # No dedupe of the final window. It checked whether that window's TEXT
  # occurred inside the one before, but the final window always ends at the
  # last word, past where the one before ended, so it is never a positional
  # duplicate: every time the check fired it deleted text found in no other
  # chunk -- a closing "Motion carried." that repeats earlier wording.
  new_chunks(unlist(txt, use.names = FALSE), "fixed", spec)
}

#' @noRd
seg_paragraph <- function(doc, spec, client, trace) {
  b <- doc$blocks
  packed <- pack_units(b$text, spec$max_tokens, spec$overlap_tokens, spec$min_tokens,
                       meta = b[, c("page", "section", "block_id")])
  new_chunks(packed$text, "paragraph", spec,
             page = packed$meta$page %||% NA_integer_,
             section = packed$meta$section %||% NA_character_,
             block_id = packed$meta$block_id %||% NA_integer_)
}

#' @noRd
seg_sentence <- function(doc, spec, client, trace) {
  b <- doc$blocks
  sents <- list(); meta <- list()
  for (i in seq_len(nrow(b))) {
    s <- sentences_of(b$text[i])
    if (!length(s)) next
    sents[[length(sents) + 1L]] <- s
    meta[[length(meta) + 1L]] <- b[rep(i, length(s)), c("page", "section", "block_id")]
  }
  if (!length(sents)) return(new_chunks(character(0), "sentence", spec))
  packed <- pack_units(unlist(sents, use.names = FALSE), spec$max_tokens,
                       spec$overlap_tokens, spec$min_tokens, joiner = " ",
                       meta = do.call(rbind, meta))
  new_chunks(packed$text, "sentence", spec,
             page = packed$meta$page %||% NA_integer_,
             section = packed$meta$section %||% NA_character_,
             block_id = packed$meta$block_id %||% NA_integer_)
}

#' @noRd
seg_recursive <- function(doc, spec, client, trace) {
  seps <- spec$separators %||% c("\n\n\n", "\n\n", "\n", ". ", "; ", ", ", " ")
  seps <- seps[!is.na(seps)]
  # Every level cuts just AFTER its separator, which stays on the piece before
  # it, so the pieces joined with "" are the text exactly. strsplit() drops a
  # trailing empty field, so pasting the separator back onto all but the last
  # part lost the one a part ENDED with: a clause ending ". " re-split on " "
  # came back as "writing.", which met the next piece as "writing.Payment".
  # Past the caller's separators come sentence ends and then any whitespace,
  # cut the same way (by lookbehind, so the whitespace stays), then characters.
  # hard_split() rejoined its pieces with spaces of its own, which a ""
  # joiner then dropped.
  cuts <- c(seps, "(?<=[.!?]\\s)(?=\\S)", "(?<=\\s)(?=\\S)")
  split_at <- function(txt, depth) {
    if (depth > length(seps)) return(strsplit(txt, cuts[depth], perl = TRUE)[[1]])
    sep <- seps[depth]
    parts <- strsplit(txt, sep, fixed = TRUE)[[1]]
    paste0(parts, c(rep(sep, length(parts) - 1L), if (endsWith(txt, sep)) sep else ""))
  }
  # A blank part (the separator run on its own) joins the part before it, or
  # the one after when it comes first, so no whitespace between words is lost.
  glue_blank <- function(parts) {
    ok <- has_content(parts)
    if (all(ok) || !any(ok)) return(parts)
    grp <- pmax(cumsum(ok), 1L)
    vapply(split(parts, grp), paste, character(1), collapse = "", USE.NAMES = FALSE)
  }
  split_rec <- function(txt, depth) {
    if (gr_count_tokens(txt) <= spec$max_tokens) return(txt)
    if (depth > length(cuts)) {
      return(split_by_budget(strsplit(txt, "", fixed = TRUE)[[1]], "", spec$max_tokens))
    }
    parts <- glue_blank(split_at(txt, depth))
    if (length(parts) <= 1L) return(split_rec(txt, depth + 1L))
    unlist(lapply(parts, function(p) {
      if (gr_count_tokens(p) <= spec$max_tokens) p else split_rec(p, depth + 1L)
    }), use.names = FALSE)
  }
  pieces <- split_rec(mark_utf8(doc$text), 1L)
  # The separator is already attached to each piece, so pieces join with "".
  # But an overlap tail is rebuilt from words and carries no trailing separator,
  # so joining it with "" welded it onto the next word ("delta" + "alpha" ->
  # "deltaalpha"), destroying both real words. Use a space when overlap is on.
  joiner <- if (spec$overlap_tokens > 0L) " " else ""
  packed <- pack_units(pieces, spec$max_tokens, spec$overlap_tokens, spec$min_tokens,
                       joiner = joiner)
  new_chunks(packed$text, "recursive", spec)
}

#' @noRd
seg_page <- function(doc, spec, client, trace) {
  b <- doc$blocks
  if (all(is.na(b$page))) {
    gr_warn(paste0("The 'page' segmenter needs page provenance, which this source does not ",
                   "carry (only PDFs currently do). Falling back to 'paragraph'."),
            class = "gr_segment_fallback")
    out <- seg_paragraph(doc, spec, client, trace)
    out$method <- "page->paragraph"
    return(out)
  }
  has_page <- !is.na(b$page)
  pages <- split(which(has_page), b$page[has_page])
  # Blocks with no page when the rest have one (a registered extractor may do
  # this). split() on the page drops NA silently, so their text reached no
  # chunk. Each unbroken run of them becomes its own chunk, page NA, after the
  # page it follows in the document.
  pageless <- which(!has_page)
  groups <- unname(pages); label <- names(pages)
  if (length(pageless)) {
    runs <- unname(split(pageless, cumsum(c(TRUE, diff(pageless) != 1L))))
    after <- vapply(runs, function(r) {
      prev <- which(has_page[seq_len(r[1] - 1L)])
      if (length(prev)) as.character(b$page[max(prev)]) else ""
    }, character(1))
    groups <- runs[after == ""]; label <- rep(NA_character_, length(groups))
    for (nm in names(pages)) {
      extra <- runs[after == nm]
      groups <- c(groups, list(pages[[nm]]), extra)
      label <- c(label, nm, rep(NA_character_, length(extra)))
    }
    gr_warn(sprintf(paste0("%d block(s) have no page number, though the rest of the document ",
                           "does; each run of them is kept as a chunk of its own with page NA, ",
                           "so no text is lost."), length(pageless)))
  }
  out <- character(0); pg <- integer(0); sc <- character(0); bid <- integer(0)
  for (g in seq_along(groups)) {
    idx <- groups[[g]]
    nm <- label[g]
    joined <- paste(b$text[idx], collapse = "\n\n")
    # A page over the cap is split rather than sent oversized, but the split is
    # reported so the user knows the page/chunk correspondence broke.
    parts <- if (gr_count_tokens(joined) > spec$max_tokens) {
      gr_msg(sprintf("Page %s exceeds the %d-token cap; splitting it into parts.",
                     if (is.na(nm)) "(none)" else nm, spec$max_tokens))
      hard_split(joined, spec$max_tokens)
    } else joined
    out <- c(out, parts)
    pg <- c(pg, rep(as.integer(nm), length(parts)))
    sc <- c(sc, rep(as_chr1(b$section[idx[1]], NA_character_), length(parts)))
    # block_id was never passed, so every `page` chunk reported NA and citations
    # could not point below page granularity. A page chunk joins all of that
    # page's blocks, so it starts at the first of them.
    bid <- c(bid, rep(b$block_id[idx[1]], length(parts)))
  }
  new_chunks(out, "page", spec, page = pg, section = sc, block_id = bid)
}
