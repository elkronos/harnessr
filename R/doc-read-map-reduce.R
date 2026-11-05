# doc-read-map-reduce.R: the map-reduce reader.

# ---------------------------------------------------------------------------
# map_reduce: all | N + log(N) | tree
# Ask every chunk the question independently, then consolidate. Parallelisable,
# order-independent, and the tree reduce means the merge prompt cannot overflow.
# ---------------------------------------------------------------------------
#' @noRd
read_map_reduce <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  if (!trace_can_call(trace, nrow(d))) {
    warn_capped_batch(trace, "map_reduce", nrow(d), "reduce the chunk count")
  }
  # The largest chunk with its reply at the cap: what gr_lapply() holds a
  # parallel batch to, since the workers cannot see what the run spends.
  worst <- batch_item_usd(client, spec$model, max_tokens_of(d$tokens) +
                            prompt_overhead(question, answer_system(spec$cite, spec$premise),
                                            spec$restate),
                          spec$max_chunk_tokens)
  res <- gr_lapply(seq_len(nrow(d)), function(i, trace) {
    if (!trace_can_call(trace)) return(list(ok = FALSE, text = "", capped = TRUE))
    r <- gr_call(client, answer_messages(question, render_chunks(d[i, , drop = FALSE]),
                                         cite = spec$cite, restate = spec$restate,
                                         premise = spec$premise),
                 model = spec$model, max_output = spec$max_chunk_tokens,
                 temperature = spec$temperature, trace = trace, label = "map.answer",
                 effort = spec$effort)
    if (spec$delay_between_calls > 0) Sys.sleep(spec$delay_between_calls)
    list(ok = usable_text(r), text = r$text, capped = FALSE, cut = reply_cut_off(r))
  }, parallel = spec$parallel, label = "chunk", trace = trace, client = client, item_usd = worst)

  ok <- vapply(res, function(r) isTRUE(r$ok), logical(1))
  texts <- vapply(res, function(r) as_chr1(r$text), character(1))
  # A failed call contributes NOTHING. The old code let `sapply` collapse a NULL
  # into the literal string "NULL" and spliced it into the merge prompt as if it
  # were a finding.
  useful <- ok & !vapply(texts, is_not_found, logical(1))
  # With the premise checked, a chunk's reply is one of three things, and the
  # two that are not answers are not alike. A chunk that only lacked the answer
  # is silent and is dropped, as it always was; on a long document most are.
  # A chunk whose excerpt CONTRADICTS the question is a finding, the one the
  # question most needs, and goes to the merge as one, opening with the
  # sentinel so the merge prompt knows it for what it is. The merge then weighs
  # it against the chunks that answered, and may itself reply that the premise
  # is false. Which chunks flagged it is kept in the notes whatever the merge
  # decides, so a correction the merge overruled is not lost without a trace.
  pieces <- texts
  flagged <- rep(FALSE, length(texts))
  if (isTRUE(spec$premise)) {
    pr <- lapply(texts, premise_reply, check = TRUE)
    flagged <- useful & vapply(pr, function(p) !is.na(p$premise), logical(1))
    # "FALSE_PREMISE: NOT_IN_DOCUMENT" is a chunk that found nothing.
    useful <- useful & !vapply(pr, function(p) is_not_found(p$text), logical(1))
    flagged <- flagged & useful
    pieces[flagged] <- vapply(pr[flagged], function(p) premise_finding(p$premise), character(1))
  }
  # A finding cut off at the output cap goes into the merge all the same, and
  # the answer rests on part of it.
  cut <- sum(useful & vapply(res, function(r) isTRUE(r$cut), logical(1)))
  # A request a limit stopped was not sent, so it did not fail: gr_read() names
  # the limit, and counting it here as well said "68 request(s) failed" of a
  # run that had spent its budget.
  capped <- vapply(res, function(r) isTRUE(r$capped), logical(1))
  n_failed <- sum(!ok & !capped)

  if (!any(useful)) {
    # No chunk contributed, so none is listed as used (the gr_answer contract):
    # listing every chunk id said the answer rested on chunks that had
    # answered "not in this excerpt", or on requests that never came back.
    # What was sent is what a citation is checked against. A run with nothing
    # back is not a run that found nothing, and the reason says which it was.
    why <- if (!nrow(d)) "there are no chunks to read"
           else if (any(ok)) "no chunk yielded an answer"
           else if (n_failed == 0L) "a limit stopped every request"
           else if (any(capped)) "every request that was sent failed"
           else "every request failed"
    return(new_answer(.NOT_FOUND, "map_reduce", question, integer(0), trace,
                      chunks_sent = d$chunk_id[!capped],
                      partial = n_failed > 0 || any(capped),
                      notes = list(chunks = nrow(d), failed_calls = n_failed, reason = why)))
  }
  # merge_system_prompt(FALSE) is the prompt tree_merge() defaults to.
  merged <- tree_merge(client, question, pieces[useful], spec, trace, label = "reduce",
                       system_prompt = merge_system_prompt(spec$premise))
  cut <- cut + merged$truncated_calls
  # A merge request that failed below the last level passes its group up
  # unmerged and leaves `merged$ok` alone, and a finding cut to fit a merge
  # lost its end; both are part of what the answer rests on.
  merge_failed <- as.integer(as_num1(merged$failed, 0))
  merge_cut <- as.integer(as_num1(merged$truncated, 0))
  # The merge's reply, or the one finding that needed no merge, is the verdict.
  # A merge that gave up returns the findings joined, which is no verdict even
  # when the first of them flagged the premise: gr_read() records NA, the
  # findings keep their sentinels in the text, and `premise_chunks` names them.
  out <- premise_reply(merged$text, isTRUE(spec$premise) && isTRUE(merged$ok))
  new_answer(out$text, "map_reduce", question, d$chunk_id[useful], trace,
             chunks_sent = d$chunk_id,
             # These are the model's ANSWER for each chunk, not quotations
             # from it, which is why verification reports NA for them.
             evidence = evidence_table(d$chunk_id[useful], texts[useful],
                                       d$page[useful], d$section[useful],
                                       kind = "answer"),
             partial = n_failed > 0 || any(capped) || !merged$ok || cut > 0L ||
               merge_failed > 0L || merge_cut > 0L,
             notes = c(list(chunks = nrow(d), answered = sum(useful),
                            failed_calls = n_failed + merge_failed,
                            merge_failures = merge_failed,
                            truncated_calls = cut, truncations = merge_cut,
                            merge_levels = merged$levels, merge_ok = merged$ok),
                       if (isTRUE(spec$premise)) list(premise_chunks = d$chunk_id[flagged])),
             premise = out$premise)
}
