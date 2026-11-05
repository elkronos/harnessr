# doc-read-ensemble.R: the ensemble reader.

# ---------------------------------------------------------------------------
# ensemble: ensemble | sum+1 | none
# Runs several DIFFERENT readers and adjudicates. Distinct only if its members
# are distinct -- which is enforced, because the old "MultiPass" was just
# Retrieval + Chunked re-run verbatim and merged.
# ---------------------------------------------------------------------------
#' @noRd
read_ensemble <- function(chunks, question, client, spec, trace) {
  members <- spec$members %||% c("retrieve", "map_reduce")
  members <- unique(members[nzchar(members)])
  if ("ensemble" %in% members) {
    gr_abort("An ensemble cannot contain 'ensemble'.", class = "gr_bad_ensemble")
  }
  if (length(members) < 2L) {
    gr_abort(paste0("An ensemble needs at least two DISTINCT members; got ",
                    if (!length(members)) "none." else sprintf("only '%s'.", members[1]),
                    " See gr_readers() for the available strategies and their signatures."),
             class = "gr_bad_ensemble")
  }
  sigs <- vapply(members, function(m) gr_reader_signature(m), character(1))
  if (anyDuplicated(sigs)) {
    dup <- members[duplicated(sigs) | duplicated(sigs, fromLast = TRUE)]
    gr_abort(sprintf(paste0("Ensemble members %s share the traversal signature '%s', so they would ",
                            "issue the same calls and produce the same answer at temperature 0. ",
                            "Pick members with different signatures; see gr_readers()."),
                     paste(sprintf("'%s'", dup), collapse = " and "), sigs[duplicated(sigs)][1]),
             class = "gr_bad_ensemble")
  }

  # Distinct signatures guarantee the members traverse differently *when there is
  # something to traverse*. On a one-chunk document every selection strategy
  # selects the same single chunk and every reader issues the same prompt, so
  # 'stuff' and 'rerank' return byte-identical answers however different their
  # signatures are. Say so rather than presenting agreement as corroboration.
  if (nrow(chunks$chunks) <= 1L) {
    gr_warn(paste0("This document produced ", nrow(chunks$chunks), " chunk(s). Every ensemble ",
                   "member will read the same text and issue the same prompt, so their ",
                   "agreement carries no independent evidence. Lower `max_tokens` in the ",
                   "segment spec, or use a single reader."),
            class = "gr_ensemble_degenerate")
  }

  results <- lapply(members, function(m) {
    sub <- spec; sub$reader <- m; sub$members <- NULL
    r <- registry_get("readers", m, "readers", state = gr_state)
    tryCatch(r$fn(chunks, question, client, sub, trace),
             error = function(e) {
               # A missing key fails every member the same way; recording it as
               # one member's failure would let the run carry on to the next.
               # Re-raised from inside this handler: a separate `gr_auth_error =`
               # handler would re-raise into this one and be recorded after all.
               if (inherits(e, "gr_auth_error")) stop(e)
               new_answer(.NOT_FOUND, m, question, integer(0), trace, partial = TRUE,
                          notes = list(error = conditionMessage(e)))
             })
  })
  names(results) <- members
  usable <- vapply(results, function(r) !is_not_found(r$answer), logical(1))
  # The members' failed requests, of every kind they count, summed here:
  # print() and partial_reasons() read the answer's own notes, not the
  # members'.
  member_count <- function(r, k) as_num1(as.list(r$notes %||% list())[[k, exact = TRUE]], 0)
  failed <- sum(vapply(results, function(r) {
    member_count(r, "failed_calls") + member_count(r, "scoring_failures") +
      member_count(r, "failed_summaries")
  }, numeric(1)))
  if (!any(usable)) {
    return(new_answer(.NOT_FOUND, "ensemble", question, integer(0), trace, partial = TRUE,
                      notes = list(members = members, failed_calls = failed,
                                   reason = "no member produced an answer")))
  }
  # Replies a member took cut off at the output cap are in what it answered,
  # and so in what is adjudicated here.
  member_cut <- function(r) as_num1(as.list(r$notes %||% list())[["truncated_calls"]], 0)
  cut <- as.integer(sum(vapply(results[usable], member_cut, numeric(1))))
  # Members whose reply was a premise verdict: their answer is the correction,
  # and only the field says it is one.
  flagged <- isTRUE(spec$premise) & vapply(results, premise_flagged, logical(1)) & usable
  premise_notes <- if (isTRUE(spec$premise)) list(premise_members = members[flagged])
  if (sum(usable) == 1L) {
    only <- results[[which(usable)]]
    return(new_answer(only$answer, "ensemble", question, only$chunks_used, trace,
                      evidence = only$evidence, partial = TRUE,
                      notes = c(list(members = members, adjudication = "single member answered",
                                     answered_by = members[usable], truncated_calls = cut,
                                     failed_calls = failed), premise_notes),
                      premise = only[["premise", exact = TRUE]]))
  }
  # A member that reported the premise false goes to the adjudication as a
  # finding that says so, with the sentinel the merge rule looks for; without
  # it, the correction would read as one more answer to the question asked.
  findings <- vapply(results[usable], function(r) {
    if (premise_flagged(r) && isTRUE(spec$premise)) premise_finding(r$premise) else r$answer
  }, character(1))
  body <- paste(sprintf("<finding source=\"%s\">\n%s\n</finding>", members[usable], findings),
                collapse = "\n\n")
  res <- if (trace_can_call(trace)) {
    gr_call(client, list(
      list(role = "system", content = paste0(
        merge_system_prompt(spec$premise),
        " These findings come from different reading strategies over the same document. Where they ",
        "agree, state it once. Where they conflict, say which strategy found what and which claim ",
        "has the more specific support.")),
      list(role = "user", content = body),
      list(role = "user", content = paste0("Question: ", question))
    ), model = spec$model, max_output = spec$max_answer_tokens, temperature = spec$temperature,
       trace = trace, label = "ensemble.adjudicate", effort = spec$effort)
  } else gr_result(FALSE, error = paste(cap_name(trace), "reached before adjudication"))

  ev <- rbind_evidence(lapply(results[usable], function(r) r$evidence))

  # Observed, not assumed, distinctness. Two members that read the same chunks
  # and returned the same text did not corroborate each other -- they were the
  # same run twice. Record which, so `gr_compare()` and the report can say so.
  ans <- vapply(results[usable], function(r) trimws(as_chr1(r$answer)), character(1))
  seen <- vapply(results[usable], function(r) paste(sort(unique(r$chunks_used)), collapse = ","),
                 character(1))
  fp <- paste(ans, seen, sep = "")
  collapsed <- if (anyDuplicated(fp)) {
    unname(lapply(split(members[usable], factor(fp, levels = unique(fp))),
                  function(g) g)[vapply(split(fp, factor(fp, levels = unique(fp))), length, integer(1)) > 1L])
  } else list()
  if (length(collapsed)) {
    gr_warn(sprintf(paste0("Ensemble members %s read the same chunks and returned the same answer. ",
                           "Their agreement is not independent corroboration."),
                    paste(vapply(collapsed, function(g) paste(sprintf("'%s'", g), collapse = " and "),
                                 character(1)), collapse = "; ")),
            class = "gr_ensemble_degenerate")
  }

  if (res$ok && reply_cut_off(res)) cut <- cut + 1L
  # A member's own flag is part of what is adjudicated. Left out, a map_reduce
  # member that read 3 of 10 chunks (7 requests failed) was merged with the
  # other member's answer and the ensemble said it rested on the whole
  # document.
  member_partial <- members[usable][vapply(results[usable], function(r) isTRUE(r$partial),
                                           logical(1))]
  # The adjudication's reply is the verdict. Answers joined because it failed
  # are none, as for a map_reduce merge that gave up; `premise_members` names
  # the members that flagged it either way. Joined from the findings, which
  # keep the sentinel on a member's correction, as a map_reduce merge that
  # gave up keeps it: from the answers, the correction read as one more answer
  # to the question asked. Without the check the two are the same text.
  out <- if (res$ok) premise_reply(res$text, spec$premise)
         else list(text = paste(trimws(findings), collapse = "\n\n---\n\n"), premise = NULL)
  new_answer(out$text,
             "ensemble", question,
             unique(unlist(lapply(results[usable], function(r) r$chunks_used))), trace,
             evidence = ev,
             partial = !res$ok || any(!usable) || cut > 0L || length(member_partial) > 0L,
             notes = c(list(members = members, signatures = unname(sigs), truncated_calls = cut,
                            answered = members[usable],
                            adjudication = if (res$ok) "llm" else "concatenated",
                            collapsed_members = collapsed,
                            failed_calls = failed, partial_members = member_partial,
                            member_notes = lapply(results, function(r) r$notes)),
                       premise_notes,
                       if (length(member_partial))
                         list(reason = sprintf("member(s) %s returned a partial answer",
                                               paste(sprintf("'%s'", member_partial),
                                                     collapse = ", ")))),
             premise = out$premise)
}
