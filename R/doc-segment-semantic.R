# doc-segment-semantic.R: the semantic segmenter.

#' @noRd
seg_semantic <- function(doc, spec, client, trace) {
  if (is.null(client)) {
    gr_warn("Semantic segmentation needs a client for embeddings; falling back to 'paragraph'.",
            class = "gr_segment_fallback")
    out <- seg_paragraph(doc, spec, client, trace); out$method <- "semantic->paragraph"
    return(out)
  }
  # Work at sentence-group granularity: embed small windows, then cut where
  # consecutive windows are most dissimilar.
  unit_list <- lapply(seq_len(nrow(doc$blocks)), function(i) {
    s <- sentences_of(doc$blocks$text[i]); if (length(s)) s else doc$blocks$text[i]
  })
  units <- unlist(unit_list, use.names = FALSE)
  # Keep each unit's source block so page/section survive into the chunks.
  umeta <- doc$blocks[rep(seq_len(nrow(doc$blocks)), vapply(unit_list, length, integer(1))),
                      c("page", "section", "block_id"), drop = FALSE]
  keep_u <- has_content(units)
  units <- units[keep_u]; umeta <- umeta[keep_u, , drop = FALSE]
  if (length(units) < 3L) {
    out <- seg_paragraph(doc, spec, client, trace); out$method <- "semantic->paragraph"
    return(out)
  }
  win <- as.integer(spec$semantic_window %||% 2L)
  ctx <- vapply(seq_along(units), function(i) {
    paste(units[max(1L, i - win + 1L):i], collapse = " ")
  }, character(1))
  emb <- gr_embed(client, ctx, trace = trace)
  src <- attr(emb, "embedding_source") %||% "api"
  if (identical(src, "lexical")) {
    gr_msg("Semantic segmentation is running on lexical fallback vectors, so boundaries reflect word overlap, not meaning.")
  }
  d <- vapply(seq_len(nrow(emb) - 1L), function(i)
    1 - cosine_similarity(emb[i, ], emb[i + 1L, ]), numeric(1))
  pct <- spec$semantic_percentile %||% 90
  thresh <- stats::quantile(d, pct / 100, names = FALSE)
  cut_after <- which(d >= thresh)

  starts <- c(1L, cut_after + 1L)
  ends <- c(cut_after, length(units))
  pieces <- vapply(seq_along(starts), function(i)
    paste(units[starts[i]:ends[i]], collapse = " "), character(1))
  # Each piece takes the provenance its WHOLE span agrees on, by meta_over()'s
  # rule, not its first sentence's. Semantic boundaries ignore pages, so a
  # piece often runs from one page onto the next, and naming the first page
  # sent a citation of a sentence on page 2 to page 1. Done column by column
  # rather than one meta_over() per piece, which is slow on a long document.
  pmeta <- umeta[starts, , drop = FALSE]
  multi <- which(ends > starts)
  for (nm in names(pmeta)) {
    v <- umeta[[nm]]
    mixed <- vapply(multi, function(k) {
      u <- v[starts[k]:ends[k]]
      length(unique(u[!is.na(u)])) > 1L
    }, logical(1))
    pmeta[[nm]][multi[mixed]] <- NA
  }
  # Respect the hard cap and the minimum: semantic boundaries decide *where*,
  # the packer decides *how much*.
  packed <- pack_units(pieces, spec$max_tokens, spec$overlap_tokens, spec$min_tokens,
                       joiner = " ", meta = pmeta)
  trace_note(trace, "segment.semantic",
             list(units = length(units), boundaries = length(cut_after),
                  threshold = round(thresh, 4), embedding_source = src))
  out <- new_chunks(packed$text, "semantic", spec,
                    page = packed$meta$page %||% NA_integer_,
                    section = packed$meta$section %||% NA_character_,
                    block_id = packed$meta$block_id %||% NA_integer_)
  out$extra <- list(boundaries = length(cut_after), embedding_source = src,
                    distance_threshold = thresh)
  out
}
