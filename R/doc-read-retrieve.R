# doc-read-retrieve.R: the retrieve reader.

# ---------------------------------------------------------------------------
# retrieve: topk | 1 | none
# Embed once, rank by cosine similarity, answer from the top k only. The cheapest
# strategy on a large corpus, and the only one whose cost does not scale with
# document length.
# ---------------------------------------------------------------------------
#' How the retrieve reader scores chunk texts for a question: cosine
#' similarity of their embeddings, blended with BM25 by `lexical_blend` when
#' the embeddings are lexical. Returns the scores, the embedding matrix
#' (question first), its source and whether it fell back to lexical.
#' gr_seg_recall() ranks with this too, so both rank alike.
#' @noRd
retrieve_scores <- function(texts, question, client, spec, trace) {
  emb <- gr_embed(client, c(question, texts), trace = trace)
  src <- attr(emb, "embedding_source") %||% "api"
  scores <- if (nrow(emb) >= 2L) cosine_against(emb[-1, , drop = FALSE], emb[1, ])
            else rep(0, length(texts))
  # Blend in BM25 on the offline path, so it is at least a real lexical
  # retriever (fuse_scores()).
  scores <- fuse_scores(scores, texts, question, spec, lexical = identical(src, "lexical"))
  list(scores = scores, emb = emb, source = src,
       degraded = isTRUE(attr(emb, "embedding_fallback")))
}

#' The chunks `retrieve` selects, in rank order: scored by retrieve_scores(),
#' floored by `min_score`, and picked by mmr_select() up to `top_k`. Shared
#' with gr_step_retrieve(), which returns them without an answer request.
#' @return `list(keep, scores, source, degraded, k, mmr)`; `keep` are row
#'   indices of `d`.
#' @noRd
retrieve_select <- function(d, question, client, spec, trace) {
  ranked <- retrieve_scores(d$text, question, client, spec, trace)
  emb <- ranked$emb
  scores <- ranked$scores
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
  list(keep = keep, scores = scores, source = ranked$source, degraded = ranked$degraded,
       k = k, mmr = lambda)
}

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
  sel <- retrieve_select(d, question, client, spec, trace)
  src <- sel$source
  degraded_embed <- sel$degraded
  scores <- sel$scores
  k <- sel$k
  lambda <- sel$mmr
  keep <- sel$keep

  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate,
                              structure = answer_structure(spec))
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
  res <- answer_request(client, answer_messages(question, render_chunks(sub), cite = spec$cite,
                                         restate = restate_how(spec), premise = spec$premise,
                                         structure = answer_structure(spec)),
                 spec, trace, "retrieve.answer", spec$max_answer_tokens,
                 sources = reader_source_text(sub))
  cut <- as.integer(res$ok && reply_cut_off(res))
  out <- premise_reply(if (res$ok) res$text else .NOT_FOUND, spec$premise)
  with_structure(new_answer(out$text, "retrieve", question, sub$chunk_id, trace, premise = out$premise,
             evidence = if (res$ok) evidence_table(sub$chunk_id, reader_source_text(sub), sub$page,
                                                   sub$section, scores[fit$idx],
                                                   kind = "verbatim"),
             partial = !res$ok || length(fit$dropped) > 0 || degraded_embed || cut > 0L,
             notes = list(chunks = nrow(d), top_k = k, used = nrow(sub), truncated_calls = cut,
                          embedding_source = src, embedding_fallback = degraded_embed,
                          mmr = lambda,
                          context_order = as_chr1(spec$context_order, "relevance"),
                          error = res$error)), res)
}

#' The one ranking `retrieve` and `iterative` both use: embedding similarity
#' fused with BM25 word matching, by `spec$fusion`.
#'
#' `"default"` keeps each reader's 0.6.0 ranking: the cosine scores as they
#' are, blended with min-max scaled BM25 by `lexical_blend` when `lexical` is
#' TRUE. `retrieve` passes `lexical = TRUE` when its embeddings are lexical;
#' `iterative` never blended, and passes FALSE, so its ranking is unchanged.
#' On the same scores, texts and query the two then rank alike whenever the
#' embeddings are not lexical.
#'
#' `"rrf"` is reciprocal rank fusion (Cormack, Clarke and Buettcher 2009):
#' each chunk scores the sum of `1 / (rrf_k + rank)` over the cosine ranking
#' and the BM25 ranking, with ties sharing the better rank. Both readers fuse
#' the same way under it, whatever the embeddings, so they rank alike.
#' @return Numeric scores, one per text, higher is better.
#' @noRd
fuse_scores <- function(dense, texts, query, spec, lexical = FALSE) {
  fusion <- as_chr1(spec$fusion, "default")
  bm25 <- function() bm25_scores(texts, query, k1 = as_num1(spec$bm25_k1, 1.5),
                                 b = as_num1(spec$bm25_b, 0.75))
  if (identical(fusion, "rrf")) {
    if (!length(dense)) return(dense)
    return(rrf_scores(list(dense, bm25()), as_num1(spec$rrf_k, 60)))
  }
  if (!isTRUE(lexical)) return(dense)
  w <- as_num1(spec$lexical_blend, 0.5)
  w * dense + (1 - w) * scale01(bm25())
}

#' Reciprocal rank fusion of several score vectors over the same items:
#' `sum(1 / (k + rank))`, rank 1 the highest score, ties at the lowest rank
#' they share. A non-finite score ranks last.
#' @noRd
rrf_scores <- function(scores, k = 60) {
  out <- numeric(length(scores[[1]]))
  for (s in scores) {
    s <- as.numeric(s)
    s[!is.finite(s)] <- -Inf
    out <- out + 1 / (k + rank(-s, ties.method = "min"))
  }
  out
}

#' @noRd
scale01 <- function(x) {
  if (!length(x)) return(x)
  r <- range(x, na.rm = TRUE)
  if (!is.finite(r[1]) || diff(r) == 0) return(rep(0.5, length(x)))
  (x - r[1]) / diff(r)
}
