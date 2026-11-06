# doc-read-stuff.R: the stuff reader.

# ---------------------------------------------------------------------------
# stuff: all | 1 | none
# The whole document in one prompt. The right answer when it fits, and the
# baseline every other strategy should be measured against.
# ---------------------------------------------------------------------------
#' @noRd
read_stuff <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  fit <- fit_chunks(d, bud$input)

  if (length(fit$dropped)) {
    msg <- sprintf(paste0("The document is ~%d tokens but only ~%d fit in one '%s' prompt; ",
                          "%d of %d chunks were dropped."),
                   sum(d$tokens), bud$input, spec$model, length(fit$dropped), nrow(d))
    if (identical(spec$on_overflow, "error")) {
      gr_abort(paste0(msg, " Use reader = 'map_reduce', 'retrieve' or 'hierarchical', or set ",
                      "on_overflow = 'warn' to answer from the part that fits."),
               class = "gr_overflow")
    }
    gr_warn(paste0(msg, " This answer is based on a truncated document."), class = "gr_overflow")
  }
  if (!length(fit$idx)) {
    return(new_answer(.NOT_FOUND, "stuff", question, integer(0), trace, partial = TRUE,
                      notes = list(reason = "no chunk fits the context window")))
  }
  sub <- d[fit$idx, , drop = FALSE]
  res <- gr_call(client, answer_messages(question, render_chunks(sub), cite = spec$cite,
                                    restate = spec$restate, premise = spec$premise),
                 model = spec$model, max_output = spec$max_answer_tokens,
                 temperature = spec$temperature, trace = trace, label = "stuff.answer",
                 effort = spec$effort)
  # One request, but not one past a limit: as an ensemble member this can run
  # after another member has spent the budget, and the governor refuses it.
  if (is_refused(res)) {
    return(new_answer(.NOT_FOUND, "stuff", question, integer(0), trace, partial = TRUE,
                      chunks_sent = integer(0),
                      notes = list(dropped_chunks = length(fit$dropped),
                                   reason = paste(cap_name(trace), "reached before the request"))))
  }
  ok <- usable_text(res)
  # An answer cut off at the output cap is still text, and still partial.
  cut <- as.integer(ok && reply_cut_off(res))
  # A premise verdict becomes its correction (read-premise.R); without the
  # check, the reply as it came.
  out <- premise_reply(if (ok) res$text else .NOT_FOUND, spec$premise)
  # The chunks are what an answer rests on. With no answer they are not
  # evidence of anything.
  new_answer(out$text, "stuff", question, sub$chunk_id, trace,
             evidence = if (ok) evidence_table(sub$chunk_id, reader_source_text(sub), sub$page,
                                               sub$section, kind = "verbatim"),
             partial = !ok || length(fit$dropped) > 0 || cut > 0L,
             notes = list(dropped_chunks = length(fit$dropped), truncated_calls = cut,
                          error = res$error),
             premise = out$premise)
}
