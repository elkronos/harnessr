# doc-read-skim.R: the skim reader.

# ---------------------------------------------------------------------------
# skim: all | N + 1 | none
# The map step extracts EVIDENCE, not answers, and the single synthesis step
# sees the verbatim source text rather than N paraphrases. This is what the old
# "Retrieval" mode was trying to be.
# ---------------------------------------------------------------------------
#' @noRd
read_skim <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  skim_model <- spec$skim_model %||% spec$model
  # The largest chunk with its reply at the cap; see map_reduce.
  worst <- batch_item_usd(client, skim_model, max_tokens_of(d$tokens) +
                            prompt_overhead(question, .gr_prompts$extract_system, "never"),
                          spec$max_chunk_tokens)
  res <- gr_lapply(seq_len(nrow(d)), function(i, trace) {
    r <- gr_call(client, list(
      list(role = "system", content = .gr_prompts$extract_system),
      list(role = "user", content = paste0("Question: ", question)),
      list(role = "user", content = paste0("<excerpt>\n", render_chunks(d[i, , drop = FALSE]),
                                           "\n</excerpt>"))
    ), model = skim_model, max_output = spec$max_chunk_tokens,
       temperature = spec$temperature, trace = trace, label = "skim.extract", effort = spec$effort)
    if (is_refused(r)) return(list(ok = FALSE, text = "", capped = TRUE))
    if (spec$delay_between_calls > 0) Sys.sleep(spec$delay_between_calls)
    list(ok = usable_text(r), text = r$text, cut = reply_cut_off(r))
  }, parallel = spec$parallel, label = "skim chunk", trace = trace,
     client = client, item_usd = worst)

  ok <- vapply(res, function(r) isTRUE(r$ok), logical(1))
  # Not sent is not failed; see map_reduce.
  capped <- vapply(res, function(r) isTRUE(r$capped), logical(1))
  txt <- vapply(res, function(r) as_chr1(r$text), character(1))
  # is_none_reply(): NONE decorated in any script. The ASCII-only pattern kept
  # "NONE" with an ideographic full stop as a passage, which then failed to
  # verify and marked a complete read partial.
  keep <- ok & !is_none_reply(txt) & has_content(txt)
  # Evidence cut off at the output cap is kept, and is part of what was there.
  cut <- sum(keep & vapply(res, function(r) isTRUE(r$cut), logical(1)))
  if (!any(keep)) {
    return(new_answer(.NOT_FOUND, "skim", question, integer(0), trace,
                      partial = any(!ok),
                      notes = list(chunks = nrow(d), failed_calls = sum(!ok & !capped),
                                   reason = "no chunk contained relevant evidence")))
  }
  # `skim` is the one reader whose evidence is written by the model rather than
  # copied out of the document, so it is the one that has to prove its quotes.
  # Against the document's text, not the chunk's where a segmenter wrote into
  # it: a quotation of a model-written header or proposition is not one.
  ev <- evidence_table(d$chunk_id[keep], txt[keep], d$page[keep], d$section[keep],
                       source_text = reader_source_text(d)[keep], kind = "extracted")
  # The extraction step copies passages and judges nothing, so the premise
  # rule goes only to the request that answers.
  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  pieces <- sprintf("[chunk %d]\n%s", ev$chunk_id, ev$text)
  body <- paste(pieces, collapse = "\n\n")
  consolidated <- FALSE
  merge_ok <- TRUE
  merge_failed <- 0L
  merge_cut <- 0L
  merge_error <- NULL
  sent <- d$chunk_id
  cite <- spec$cite
  if (gr_count_tokens(body) > bud$input) {
    # Evidence itself can exceed the window on a large document. Consolidate it
    # tree-wise rather than truncating blind. Each passage keeps its label, so
    # a consolidation that carries one forward says where it came from.
    m <- tree_merge(client, question, pieces, spec, trace, label = "skim.consolidate",
                    system_prompt = .gr_prompts$summarise_system, kind = "evidence")
    body <- m$text
    consolidated <- TRUE
    cut <- cut + m$truncated_calls
    # A failed consolidation hands back the passages joined and cut short, and
    # a failed group below the last level passes its passages up unmerged:
    # either way the answer is written from part of the evidence.
    merge_ok <- isTRUE(m$ok)
    merge_error <- m$error
    merge_failed <- as.integer(as_num1(m$failed, 0))
    merge_cut <- as.integer(as_num1(m$truncated, 0))
    # Only the labels still in the text are in front of the model. Checked
    # against every chunk, a citation it invented for a consolidation that
    # kept no label passed; with none to cite, it is not asked for any, as
    # `hierarchical` is not.
    sent <- intersect(ev$chunk_id, cited_chunks(body))
    cite <- isTRUE(spec$cite) && length(sent) > 0L
  }
  res2 <- gr_call(client, answer_messages(question, body, cite = cite, label = "Evidence",
                                          restate = spec$restate, premise = spec$premise),
                  model = spec$model, max_output = spec$max_answer_tokens,
                  temperature = spec$temperature, trace = trace, label = "skim.answer",
                  effort = spec$effort)
  if (usable_text(res2) && reply_cut_off(res2)) cut <- cut + 1L
  out <- premise_reply(if (usable_text(res2)) res2$text else .NOT_FOUND, spec$premise)
  # No answer, no evidence; see stuff. The passages found are counted in the
  # notes all the same.
  new_answer(out$text, "skim", question, ev$chunk_id, trace, premise = out$premise,
             chunks_sent = sent, evidence = if (usable_text(res2)) ev,
             partial = any(!ok) || !res2$ok || cut > 0L || !merge_ok || merge_failed > 0L ||
               merge_cut > 0L,
             notes = c(list(chunks = nrow(d), with_evidence = nrow(ev),
                            failed_calls = sum(!ok & !capped) + merge_failed,
                            truncated_calls = cut, truncations = merge_cut,
                            evidence_consolidated = consolidated,
                            evidence_verified = sum(isTRUE_vec(ev$verified))),
                       if (consolidated) list(merge_ok = merge_ok,
                                              cite_dropped = isTRUE(spec$cite) && !cite),
                       # Why the consolidation gave up, when no request of it
                       # failed; when one did, the trace's error says more
                       # than "merge made no progress".
                       if (!is.null(merge_error) && !merge_failed)
                         list(error = as_chr1(merge_error))))
}
