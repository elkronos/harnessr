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
  if (identical(as_chr1(spec[["table_packing"]], "rows"), "grouped") && block_has_table(b)) {
    return(seg_paragraph_grouped(doc, spec))
  }
  packed <- pack_units(b$text, spec$max_tokens, spec$overlap_tokens, spec$min_tokens,
                       meta = b[, c("page", "section", "block_id")],
                       balanced = pack_balanced(spec), runt_forward = pack_runt_forward(spec))
  out <- new_chunks(packed$text, "paragraph", spec,
                    page = packed$meta$page %||% NA_integer_,
                    section = packed$meta$section %||% NA_character_,
                    block_id = packed$meta$block_id %||% NA_integer_)
  # A document with a table: each chunk says which table its rows come from
  # and which rows, from the blocks it was packed from. Provenance only.
  if (block_has_table(b) && nrow(out$chunks) == nrow(packed$span)) {
    tp <- chunk_table_provenance(b, packed$span$first, packed$span$last)
    out$chunks$table_id <- tp$table_id
    out$chunks$table_rows <- tp$table_rows
  }
  out
}

#' Whether a document's blocks hold a table row with table provenance.
#' @noRd
block_has_table <- function(b) {
  !is.null(b[["table_id"]]) && any(!is.na(b$table_id))
}

#' The table a chunk's rows come from, for chunks packed from blocks
#' `first[i]:last[i]`: its `table_id` when every table block in the span is
#' from one table, and `table_rows`, from the first of their rows to the
#' last, as "3-20" (or "7" for one row). `NA` for a chunk with no table row,
#' and for one whose rows come from two tables.
#' @noRd
chunk_table_provenance <- function(b, first, last) {
  n <- length(first)
  id <- rep(NA_integer_, n); rows <- rep(NA_character_, n)
  rr <- table_rows_range(b$table_rows)
  for (i in seq_len(n)) {
    at <- seq.int(first[i], last[i])
    at <- at[!is.na(b$table_id[at])]
    t <- unique(b$table_id[at])
    if (length(t) != 1L) next
    id[i] <- t
    rows[i] <- rows_label(min(rr[at, "first"]), max(rr[at, "last"]))
  }
  list(table_id = id, table_rows = rows)
}

#' "3-20", or "7" when the first row is the last.
#' @noRd
rows_label <- function(a, b) if (a == b) as.character(a) else paste0(a, "-", b)

#' seg_paragraph() under table_packing = "grouped".
#'
#' The blocks outside tables are packed as `paragraph` packs them, run by run.
#' Each table is packed on its own, row by row (a Markdown table's block is
#' split into its rows, its separator line kept with the first): its first
#' row, taken for its header, opens every chunk of it, followed by as many of
#' the other rows as fit under the cap, joined by line breaks, with no
#' overlap, since the header is the context a chunk of rows needs. A header
#' that leaves fewer than 16 tokens for rows is not repeated: the rows are
#' then packed in order on their own.
#' @noRd
seg_paragraph_grouped <- function(doc, spec) {
  b <- doc$blocks
  is_tab <- !is.na(b$table_id)
  key <- ifelse(is_tab, paste0("t", b$table_id), "p")
  run <- cumsum(c(TRUE, key[-1L] != key[-length(key)]))
  txt <- character(0); pg <- integer(0); sc <- character(0); bid <- integer(0)
  tid <- integer(0); trows <- character(0)
  meta_cols <- c("page", "section", "block_id")
  for (idx in split(seq_len(nrow(b)), run)) {
    if (!is_tab[idx[1]]) {
      packed <- pack_units(b$text[idx], spec$max_tokens, spec$overlap_tokens, spec$min_tokens,
                           meta = b[idx, meta_cols, drop = FALSE],
                           balanced = pack_balanced(spec),
                           runt_forward = pack_runt_forward(spec))
      k <- length(packed$text)
      txt <- c(txt, packed$text)
      pg <- c(pg, packed$meta$page %||% rep(NA_integer_, k))
      sc <- c(sc, packed$meta$section %||% rep(NA_character_, k))
      bid <- c(bid, packed$meta$block_id %||% rep(NA_integer_, k))
      tid <- c(tid, rep(NA_integer_, k)); trows <- c(trows, rep(NA_character_, k))
      next
    }
    # One row per unit, each with the block it came from.
    lines <- lapply(idx, function(i) table_lines(b$text[i]))
    rows <- unlist(lines, use.names = FALSE)
    from <- rep(idx, vapply(lines, length, integer(1)))
    if (!length(rows)) next
    first_row <- table_rows_range(b$table_rows[idx[1]])[1, "first"]
    if (is.na(first_row)) first_row <- 1L
    num <- first_row + seq_along(rows) - 1L
    rest <- seq_along(rows)[-1L]
    room <- spec$max_tokens - gr_count_tokens(paste0(rows[1], "\n"))
    with_header <- length(rest) > 0L && room >= 16L
    # Each group keeps the text pack_units() gave it. A row longer than the
    # cap is split into pieces whose spans all point at that one row, so
    # pasting the group's rows again repeated the whole row in every piece.
    spans <- function(units, cap) {
      packed <- pack_units(rows[units], cap, 0L, 0L, joiner = "\n")
      lapply(seq_len(nrow(packed$span)),
             function(g) list(units = units[packed$span$first[g]:packed$span$last[g]],
                              text = packed$text[g]))
    }
    groups <- if (!length(rest)) list(list(units = 1L, text = rows[1L]))
              else if (with_header) spans(rest, room)
              else spans(seq_along(rows), spec$max_tokens)
    for (gp in groups) {
      g <- gp$units
      r <- if (with_header) c(1L, g) else g
      txt <- c(txt, if (with_header) paste(rows[1L], gp$text, sep = "\n") else gp$text)
      m <- meta_over(b[from[r], meta_cols, drop = FALSE], 1L, length(r))
      pg <- c(pg, m$page); sc <- c(sc, m$section); bid <- c(bid, m$block_id)
      tid <- c(tid, b$table_id[idx[1]])
      # The rows the chunk holds of its own: the header it repeats counts
      # only in the chunk that holds the rows right after it.
      own <- if (with_header && min(g) > 2L) g else r
      trows <- c(trows, rows_label(min(num[own]), max(num[own])))
    }
  }
  keep <- has_content(txt)
  out <- new_chunks(txt, "paragraph", spec, page = pg, section = sc, block_id = bid,
                    extra = list(table_packing = "grouped"))
  out$chunks$table_id <- tid[keep]
  out$chunks$table_rows <- trows[keep]
  out
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
                       meta = do.call(rbind, meta),
                       balanced = pack_balanced(spec), runt_forward = pack_runt_forward(spec))
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
                       joiner = joiner,
                       balanced = pack_balanced(spec), runt_forward = pack_runt_forward(spec))
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

#' Whether a segment spec asks for packing = "balanced".
#' @noRd
pack_balanced <- function(spec) identical(as_chr1(spec[["packing"]], "greedy"), "balanced")

#' Whether a segment spec asks for runt_merge = "both".
#' @noRd
pack_runt_forward <- function(spec) identical(as_chr1(spec[["runt_merge"]], "backward"), "both")
