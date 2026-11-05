# doc-read-rerank.R: the rerank reader.

#' The candidates `rerank` asks the model to score: the `m` chunks BM25 ranks
#' highest, or the best that can be done when BM25 cannot rank them.
#'
#' A question that shares no word with any chunk, such as a paraphrase ("How
#' much did the firm bring in?" of a document that says "turnover"), scores
#' every chunk 0, and `order()` breaks the tie in document order. The first m
#' chunks were scored as if they were the best, and a document whose answer sat
#' further in came back NOT_IN_DOCUMENT, partial = FALSE, with nothing to say
#' the ranking had been blind.
#'
#' Embeddings rank instead: they do not need a shared word, and the model still
#' judges every candidate they pick. When they cannot rank either (lexical
#' vectors are word overlap too, a failed embedding falls back to them, and
#' vectors that all tie say nothing), the candidates are one chunk from the
#' middle of each of `m` equal stretches of the document. That is a sample, not
#' a ranking, and the answer says so by being partial; but it looks across the
#' whole document instead of only at its opening, which is all a first-m pick
#' ever sees. Either fallback warns (`gr_rerank_prefilter`) and is recorded in
#' `notes$prefilter`. With every chunk a candidate, order does not matter and
#' nothing changes.
#' @return `list(cand, scores, method)`: `method` is "bm25", "embedding" or
#'   "spread", and `scores` are what the chunks were ranked by, which the
#'   reader falls back to when no model score comes back.
#' @noRd
rerank_prefilter <- function(d, question, client, trace, pre, m) {
  n <- nrow(d)
  if (m >= n || any(pre > 0)) {
    return(list(cand = order(pre, decreasing = TRUE)[seq_len(m)], scores = pre, method = "bm25"))
  }
  emb <- gr_embed(client, c(question, d$text), trace = trace)
  sim <- if (nrow(emb) == n + 1L) cosine_against(emb[-1, , drop = FALSE], emb[1, ]) else numeric(0)
  semantic <- !identical(attr(emb, "embedding_source"), "lexical") &&
    !isTRUE(attr(emb, "embedding_fallback")) &&
    length(sim) == n && all(is.finite(sim)) && diff(range(sim)) > 0
  if (semantic) {
    gr_warn(sprintf(paste0("No chunk shares a word with the question, so the word-matching ",
                           "prefilter cannot rank them; the %d rerank candidates were picked by ",
                           "embedding similarity instead."), m),
            class = "gr_rerank_prefilter")
    return(list(cand = order(sim, decreasing = TRUE)[seq_len(m)], scores = sim,
                method = "embedding"))
  }
  gr_warn(sprintf(paste0("No chunk shares a word with the question and embeddings could not rank ",
                         "them either, so the %d rerank candidates are spread evenly over the %d ",
                         "chunks. The answer rests on that sample and is marked partial."), m, n),
          class = "gr_rerank_prefilter")
  list(cand = as.integer(ceiling((seq_len(m) - 0.5) * n / m)), scores = pre, method = "spread")
}

# ---------------------------------------------------------------------------
# rerank: topk | m + 1 | none
# Cheap lexical prefilter (free), then the model scores each candidate for
# relevance (m small calls), then one answer call. Distinct from `retrieve`
# because relevance is judged by the model, not by vector distance.
# ---------------------------------------------------------------------------
#' @noRd
read_rerank <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  pre <- bm25_scores(d$text, question)
  m <- as.integer(clamp(spec$rerank_candidates, 1, nrow(d)))
  prefilter <- rerank_prefilter(d, question, client, trace, pre, m)
  cand <- prefilter$cand
  pre <- prefilter$scores

  schema <- list(type = "object", additionalProperties = FALSE,
                 required = list("score", "reason"),
                 properties = list(
                   score = list(type = "integer", minimum = 0, maximum = 10),
                   reason = list(type = "string")))
  score_system <- paste0(
    "Rate how useful an excerpt is for answering a question. 0 = irrelevant, ",
    "10 = contains the answer directly. Judge only what is written in the excerpt.")
  score_model <- spec$skim_model %||% spec$model
  # The largest candidate with its reply at the 200-token cap; see map_reduce.
  worst <- batch_item_usd(client, score_model, max_tokens_of(d$tokens[cand]) +
                            prompt_overhead(question, score_system, "never"), 200L)
  # `status` records what happened to each candidate. It is kept apart from
  # `reason`, which is the model's own words and can say anything -- including
  # "unscorable" -- so counting outcomes by matching it counted a judged chunk
  # as an unjudged one.
  scored <- gr_lapply(cand, function(i, trace) {
    # A call that was never made judged nothing: NA, like a failed one.
    if (!trace_can_call(trace)) return(list(i = i, score = NA_real_, status = "capped"))
    out <- gr_call_json(client, list(
      list(role = "system", content = score_system),
      list(role = "user", content = paste0("Question: ", question)),
      list(role = "user", content = paste0("<excerpt>\n", d$text[i], "\n</excerpt>"))
    ), schema = schema, schema_name = "relevance",
       model = score_model, max_output = 200L,
       temperature = spec$temperature, trace = trace, label = "rerank.score", effort = spec$effort)
    # NA, not 0. A failed call judged nothing, and scoring it 0 put it through
    # the threshold at rerank_min_score = 0 as a model-judged score for a chunk
    # no model had read -- and kept it out of the "was anything judged?" test
    # below, so a run of failed calls mixed with unusable replies neither
    # degraded nor warned.
    if (!out$ok) return(list(i = i, score = NA_real_, status = "failed"))
    # A score that is not a number is not a score. as.numeric("high") is NA, and
    # NA then went through `keep_sc >= thresh` as an NA LOGICAL -- which selects
    # rather than drops -- so `[chunk NA]` reached the prompt and the model
    # answered the question with no document in front of it, partial = FALSE.
    sc <- json_num(out$value, "score", NA_real_)
    list(i = i, score = sc, status = if (is.na(sc)) "unscorable" else "scored")
  }, parallel = spec$parallel, label = "rerank candidate", trace = trace,
     client = client, item_usd = worst)

  sc <- vapply(scored, function(s) as.numeric(s$score)[1], numeric(1))
  ii <- vapply(scored, function(s) s$i, numeric(1))
  status <- vapply(scored, function(s) as_chr1(s$status, "failed"), character(1))
  n_failed <- sum(status == "failed")
  n_unscorable <- sum(status == "unscorable")
  n_capped <- sum(status == "capped")
  degraded <- FALSE
  # ONE test: was anything judged at all? Testing "every call failed" and
  # "every score was unusable" separately left the mixed case -- some of each --
  # falling through both, so the run returned NOT_IN_DOCUMENT with no warning
  # for a document no model had scored.
  if (all(is.na(sc))) {
    # Every scoring call failed, typically an endpoint without structured output
    # support, or every reply was unusable. Degrade to the BM25 prefilter order
    # and SAY SO, rather than reporting "nothing relevant" for a document that
    # was never actually scored.
    why <- c(if (n_failed) sprintf("%d call(s) failed", n_failed),
             if (n_unscorable) sprintf("%d returned a value that is not a number between 0 and 10",
                                       n_unscorable),
             if (n_capped) sprintf("%d not made because the %s was reached", n_capped, cap_name(trace)))
    ranking <- switch(prefilter$method,
      embedding = "the embedding ranking the prefilter fell back to, which is ",
      spread = "the evenly spread sample the prefilter fell back to, which is not a ranking and ",
      "the BM25 prefilter ranking, which is lexical, ")
    gr_warn(if (n_failed == length(scored))
              paste0("Every rerank scoring call failed (does this endpoint support JSON schema ",
                     "output?). Falling back to ", ranking, "not model-judged.")
            else paste0("No rerank score came back usable (", paste(why, collapse = ", "),
                        "). Falling back to ", ranking, "not model-judged."),
            class = "gr_rerank_degraded")
    sc <- pre[cand]
    degraded <- TRUE
  }
  # Some candidates were never judged: the ranking is incomplete, and whatever
  # it concludes -- including "nothing relevant" -- rests on part of the list.
  unjudged <- !degraded && (n_failed + n_unscorable + n_capped) > 0L
  ord <- order(sc, decreasing = TRUE)
  keep_ord <- ii[ord]
  keep_sc <- sc[ord]
  thresh <- if (degraded) -Inf else clamp(spec$rerank_min_score, 0, 10)
  # !is.na() FIRST. `NA >= thresh` is NA, and an NA logical subscript SELECTS an
  # NA element rather than dropping it -- so the vector kept its length, the
  # "nothing scored high enough" guard below did not fire, and d[NA, ] put
  # `[chunk NA]` in the prompt. The model then answered from the question alone
  # and the answer came back partial = FALSE.
  keep_ord <- keep_ord[!is.na(keep_sc) & keep_sc >= thresh]
  if (!length(keep_ord)) {
    # Partial only when something was not judged. Every candidate scored and
    # every score low is a CORRECT negative, and marking it partial put a right
    # answer and a broken one in the same bucket -- the distinction the screen
    # reader draws for "unclear", and the one `partial` exists to make.
    # Nor is a negative from a sample: the chunks that were not in it were
    # never looked at.
    return(new_answer(.NOT_FOUND, "rerank", question, integer(0), trace,
                      partial = unjudged || identical(prefilter$method, "spread"),
                      notes = list(candidates = m, scoring_failures = n_failed,
                                   unscorable = n_unscorable, prefilter = prefilter$method,
                                   reason = sprintf("no candidate scored >= %g", thresh))))
  }
  keep_ord <- utils::head(keep_ord, as.integer(clamp(spec$top_k, 1, length(keep_ord))))

  # The relevance scores judge usefulness, not truth, so the premise rule goes
  # only to the request that answers.
  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  fit <- fit_chunks(d, bud$input, order = as.integer(keep_ord))
  fit$idx <- arrange_context(fit$idx, spec$context_order)
  sub <- d[fit$idx, , drop = FALSE]
  # Checked as `retrieve` checks it. Unchecked, a chunk the model had judged
  # relevant and that did not fit was dropped without a word, and when none
  # fitted the answer call went out with an empty <excerpts></excerpts> and
  # the model's own prior came back as the document's answer.
  if (!nrow(sub)) {
    return(new_answer(.NOT_FOUND, "rerank", question, integer(0), trace, partial = TRUE,
                      notes = list(chunks = nrow(d), candidates = m, used = 0L,
                                   dropped_chunks = length(fit$dropped),
                                   scoring_failures = n_failed, unscorable = n_unscorable,
                                   prefilter = prefilter$method, degraded_to_bm25 = degraded,
                                   reason = "no selected chunk fits the context window")))
  }
  trace_note(trace, "rerank.select", list(candidates = m, kept = nrow(sub),
                                          prefilter = prefilter$method,
                                          degraded_to_bm25 = degraded,
                                          context_order = as_chr1(spec$context_order, "relevance"),
                                          scores = round(utils::head(keep_sc, 10), 2)))
  res <- if (trace_can_call(trace)) {
    gr_call(client, answer_messages(question, render_chunks(sub), cite = spec$cite,
                                    restate = spec$restate, premise = spec$premise),
            model = spec$model, max_output = spec$max_answer_tokens,
            temperature = spec$temperature, trace = trace, label = "rerank.answer",
            effort = spec$effort)
  } else gr_result(FALSE, error = paste(cap_name(trace), "reached before the answer step"))
  cut <- as.integer(res$ok && reply_cut_off(res))
  out <- premise_reply(if (res$ok) res$text else .NOT_FOUND, spec$premise)
  # No answer, no evidence; see stuff.
  new_answer(out$text, "rerank", question, sub$chunk_id, trace, premise = out$premise,
             evidence = if (res$ok) evidence_table(sub$chunk_id, reader_source_text(sub), sub$page,
                                                   sub$section, sc[match(fit$idx, ii)],
                                                   kind = "verbatim"),
             partial = !res$ok || degraded || unjudged || cut > 0L ||
               identical(prefilter$method, "spread") || length(fit$dropped) > 0L,
             notes = list(chunks = nrow(d), candidates = m, used = nrow(sub),
                          dropped_chunks = length(fit$dropped),
                          scoring_failures = n_failed, unscorable = n_unscorable,
                          truncated_calls = cut, prefilter = prefilter$method,
                          degraded_to_bm25 = degraded))
}
