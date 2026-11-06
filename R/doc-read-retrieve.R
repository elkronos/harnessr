# doc-read-retrieve.R: the retrieve reader.

# ---------------------------------------------------------------------------
# retrieve: topk | 1 | none
# Embed once, rank by cosine similarity, answer from the top k only. The cheapest
# strategy on a large corpus, and the only one whose cost does not scale with
# document length.
# ---------------------------------------------------------------------------
#' @noRd
read_retrieve <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  # Nothing to rank. Carried on, the top-1 fallback below took order() of no
  # scores, which is NA, and `[chunk NA]\nNA` went out as the only excerpt: the
  # model answered from its own prior, partial = FALSE.
  if (!nrow(d)) {
    return(new_answer(.NOT_FOUND, "retrieve", question, integer(0), trace, partial = TRUE,
                      notes = list(chunks = 0L, reason = "there are no chunks to read")))
  }
  emb <- gr_embed(client, c(question, d$text), trace = trace)
  src <- attr(emb, "embedding_source") %||% "api"
  degraded_embed <- isTRUE(attr(emb, "embedding_fallback"))
  scores <- if (nrow(emb) >= 2L) cosine_against(emb[-1, , drop = FALSE], emb[1, ]) else rep(0, nrow(d))
  if (identical(src, "lexical")) {
    # Blend in BM25 so the offline path is at least a real lexical retriever.
    scores <- 0.5 * scores + 0.5 * scale01(bm25_scores(d$text, question))
  }
  k <- as.integer(clamp(spec$top_k, 1, nrow(d)))
  min_score <- as_num1(spec$min_score, -Inf)
  # The floor is applied BEFORE selection, not after. Applied after, a chunk
  # below the floor could still displace one above it and then be dropped,
  # leaving fewer chunks than asked for and no way to see why.
  rel <- scores
  if (is.finite(min_score)) rel[rel < min_score] <- -Inf
  chunk_emb <- if (nrow(emb) >= 2L) emb[-1, , drop = FALSE] else NULL
  lambda <- as_num1(spec$mmr, 1)
  keep <- mmr_select(rel, chunk_emb, k, lambda)
  # head(), not [1]: of no scores that is nothing rather than NA, and d[NA, ]
  # is a row of NAs that fits any budget.
  if (!length(keep)) keep <- utils::head(order(scores, decreasing = TRUE), 1L)

  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  fit <- fit_chunks(d, bud$input, order = keep)
  # Fit first, then arrange: what gets in is a relevance question, where it sits
  # in the prompt is a positional-attention one, and answering them in the other
  # order would let placement decide what gets dropped.
  fit$idx <- arrange_context(fit$idx, spec$context_order)
  sub <- d[fit$idx, , drop = FALSE]
  if (!nrow(sub)) {
    return(new_answer(.NOT_FOUND, "retrieve", question, integer(0), trace, partial = TRUE,
                      notes = list(reason = "top-ranked chunk does not fit the context window")))
  }
  trace_note(trace, "retrieve.rank",
             list(k = k, kept = nrow(sub), embedding_source = src,
                  mmr = lambda, context_order = as_chr1(spec$context_order, "relevance"),
                  top_scores = round(utils::head(sort(scores, decreasing = TRUE), 5), 4)))
  # Checked by the governor, as every request is: as an ensemble member this
  # can run after another member has spent the budget.
  res <- gr_call(client, answer_messages(question, render_chunks(sub), cite = spec$cite,
                                         restate = spec$restate, premise = spec$premise),
                 model = spec$model, max_output = spec$max_answer_tokens,
                 temperature = spec$temperature, trace = trace, label = "retrieve.answer",
                 effort = spec$effort)
  cut <- as.integer(res$ok && reply_cut_off(res))
  out <- premise_reply(if (res$ok) res$text else .NOT_FOUND, spec$premise)
  new_answer(out$text, "retrieve", question, sub$chunk_id, trace, premise = out$premise,
             evidence = if (res$ok) evidence_table(sub$chunk_id, reader_source_text(sub), sub$page,
                                                   sub$section, scores[fit$idx],
                                                   kind = "verbatim"),
             partial = !res$ok || length(fit$dropped) > 0 || degraded_embed || cut > 0L,
             notes = list(chunks = nrow(d), top_k = k, used = nrow(sub), truncated_calls = cut,
                          embedding_source = src, embedding_fallback = degraded_embed,
                          mmr = lambda,
                          context_order = as_chr1(spec$context_order, "relevance"),
                          error = res$error))
}

#' @noRd
scale01 <- function(x) {
  if (!length(x)) return(x)
  r <- range(x, na.rm = TRUE)
  if (!is.finite(r[1]) || diff(r) == 0) return(rep(0.5, length(x)))
  (x - r[1]) / diff(r)
}
