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
  rule <- as_chr1(spec[["semantic_threshold"]], "percentile")
  if (identical(rule, "texttiling")) {
    tt <- texttiling_cuts(emb, win)
    cut_after <- tt$cut_after
    thresh <- tt$cutoff
  } else {
    d <- vapply(seq_len(nrow(emb) - 1L), function(i)
      1 - cosine_similarity(emb[i, ], emb[i + 1L, ]), numeric(1))
    pct <- spec$semantic_percentile %||% 90
    thresh <- stats::quantile(d, pct / 100, names = FALSE)
    cut_after <- which(d >= thresh)
  }

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
             c(list(units = length(units), boundaries = length(cut_after),
                    threshold = round(thresh, 4), embedding_source = src),
               if (identical(rule, "texttiling")) list(rule = rule)))
  # On lexical vectors the boundaries follow word overlap, not meaning, and
  # the method says so, as "semantic->paragraph" does for its fallback. A
  # label only: the requests and the chunks are what they were.
  out <- new_chunks(packed$text, if (identical(src, "lexical")) "semantic->lexical" else "semantic",
                    spec,
                    page = packed$meta$page %||% NA_integer_,
                    section = packed$meta$section %||% NA_character_,
                    block_id = packed$meta$block_id %||% NA_integer_)
  out$extra <- list(boundaries = length(cut_after), embedding_source = src,
                    distance_threshold = thresh)
  out
}

#' Boundaries by TextTiling's depth score (Hearst 1997), for
#' semantic_threshold = "texttiling".
#'
#' `emb` holds one row per sentence unit: the embedding of the `win` units
#' ending at it. The similarity at the gap after unit i is the cosine between
#' the block of units ending at i and the block ending at i + win, which are
#' the `win` units on each side of the gap: Hearst's block comparison, from
#' the same vectors. Only gaps with a full block on each side are scored.
#' A gap's depth is how far its similarity sits below the highest point
#' reached climbing left from it, plus the same to the right. A gap is cut
#' when it is a valley (lower than its scored neighbours), its depth exceeds
#' Hearst's cutoff, the mean of the depths less half their standard
#' deviation, and its depth exceeds the spread of the similarities (largest
#' less smallest). The last test is not Hearst's: his cutoff is relative, so
#' it cuts a text on a single topic as often as one on many.
#' @return `list(cut_after, cutoff, similarity, depth)`; `cut_after` are unit
#'   indices, as the percentile rule gives them.
#' @noRd
texttiling_cuts <- function(emb, win) {
  n <- nrow(emb)
  gaps <- seq_len(n - 1L)
  gaps <- gaps[gaps >= win & gaps + win <= n]
  none <- list(cut_after = integer(0), cutoff = NA_real_, similarity = numeric(0),
               depth = numeric(0))
  if (length(gaps) < 3L) return(none)
  s <- vapply(gaps, function(i) cosine_similarity(emb[i, ], emb[i + win, ]), numeric(1))
  k <- length(s)
  depth <- vapply(seq_len(k), function(i) {
    l <- s[i]; j <- i
    while (j > 1L && s[j - 1L] >= l) { l <- s[j - 1L]; j <- j - 1L }
    r <- s[i]; j <- i
    while (j < k && s[j + 1L] >= r) { r <- s[j + 1L]; j <- j + 1L }
    (l - s[i]) + (r - s[i])
  }, numeric(1))
  valley <- c(FALSE, s[-c(1L, k)] < s[-c(k - 1L, k)] & s[-c(1L, k)] <= s[-c(1L, 2L)], FALSE)
  cutoff <- mean(depth) - stats::sd(depth) / 2
  spread <- max(s) - min(s)
  cut <- valley & depth > cutoff & depth > spread
  list(cut_after = as.integer(gaps[cut]), cutoff = cutoff, similarity = s, depth = depth)
}
