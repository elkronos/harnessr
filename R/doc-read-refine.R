# doc-read-refine.R: the refine reader.

# ---------------------------------------------------------------------------
# refine: all | N | forward
# Strictly sequential: build a draft from the first chunk, then revise it
# against each subsequent chunk. Order matters, cannot be parallelised, and it
# is the only strategy where late evidence can overturn an early conclusion.
# ---------------------------------------------------------------------------
#' @noRd
read_refine <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  draft <- NULL; used <- integer(0); revisions <- 0L; failures <- 0L; truncated <- 0L
  cut <- 0L
  dropped <- 0L
  # The draft grows with every revision, so unlike the other readers this one
  # can outgrow the context window mid-run. Budget for it explicitly.
  # Two different system prompts go out of this reader -- answer_messages() for
  # the first chunk, refine_system for every revision after it -- so budget
  # against the longer of the two rather than whichever is named here.
  # Both with the premise rule when the spec checks it, since both carry it.
  refine_system <- refine_system_prompt(spec$premise)
  overhead <- max(prompt_overhead(question, refine_system, spec$restate),
                  prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate))
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  p <- progress_start(nrow(d), "chunk", trace)
  with_progress(p, for (i in seq_len(nrow(d))) {
    if (i > 1L) progress_tick(p, i - 1L)
    if (!trace_can_call(trace)) break
    excerpt <- render_chunks(d[i, , drop = FALSE])
    # Halve the budget between the running draft and the incoming excerpt.
    half <- max(as.integer(bud$input / 2), 64L)
    # Each cut goes into the trace with the tokens it dropped: the draft's cut
    # loses its end, which no later revision can see again.
    if (gr_count_tokens(excerpt) > half) {
      t <- truncate_logged(excerpt, half, "refine.excerpt", trace, chunk_id = d$chunk_id[i])
      excerpt <- t$text; truncated <- truncated + 1L; dropped <- dropped + t$dropped
    }
    if (!is.null(draft) && gr_count_tokens(draft) > half) {
      t <- truncate_logged(draft, half, "refine.draft", trace, chunk_id = d$chunk_id[i])
      draft <- t$text; truncated <- truncated + 1L; dropped <- dropped + t$dropped
    }
    # The draft as this request carries it, for the state length below.
    state_in <- if (is.null(draft)) 0L else gr_count_tokens(draft)
    from <- length(trace$steps)
    msgs <- if (is.null(draft)) {
      answer_messages(question, excerpt, cite = spec$cite, restate = spec$restate,
                      premise = spec$premise)
    } else {
      # A draft that is a premise verdict is carried forward as it came, with
      # its sentinel, so the next revision can see it is one (read-premise.R).
      list(
        list(role = "system", content = refine_system),
        list(role = "user", content = paste0("Question: ", question)),
        list(role = "user", content = paste0("<draft>\n", draft, "\n</draft>")),
        list(role = "user", content = paste0("<new_excerpt>\n", excerpt, "\n</new_excerpt>")),
        list(role = "user", content = paste0(
          "Return the revised answer. If the excerpt adds nothing, return the draft unchanged. ",
          "If neither the draft nor the excerpt answers the question, return exactly ", .NOT_FOUND, "."))
      )
    }
    step_label <- if (is.null(draft)) "refine.draft" else "refine.revise"
    res <- gr_call(client, msgs, model = spec$model, max_output = spec$max_answer_tokens,
                   temperature = spec$temperature, trace = trace,
                   label = step_label, effort = spec$effort)
    # The state length at every step: the draft sent and the draft carried on,
    # which is the old one when the reply was unusable. A draft that shrinks
    # sharply in one revision is the collapse a whole rewrite can cause.
    trace_state(trace, from, step_label, tokens_in = state_in,
                tokens_out = if (usable_text(res)) gr_count_tokens(res$text) else state_in)
    if (!usable_text(res)) { failures <- failures + 1L; next }
    # A draft cut off at the output cap is carried forward as the draft, so
    # whatever it lost is lost from every revision after it.
    if (reply_cut_off(res)) cut <- cut + 1L
    used <- c(used, d$chunk_id[i])
    if (is.null(draft)) { draft <- res$text } else {
      if (!identical(trimws(res$text), trimws(draft))) revisions <- revisions + 1L
      draft <- res$text
    }
    if (spec$delay_between_calls > 0) Sys.sleep(spec$delay_between_calls)
  })
  # The last draft is the verdict: a premise flag that a later excerpt
  # overturned is gone from it, as any other revised claim is.
  out <- premise_reply(draft %||% .NOT_FOUND, spec$premise)
  new_answer(out$text, "refine", question, used, trace,
             # A cut excerpt or draft is text no request saw. `preview` applies
             # the same rule to a truncated skim.
             partial = failures > 0 || length(used) < nrow(d) || truncated > 0L || cut > 0L,
             notes = list(chunks = nrow(d), visited = length(used),
                          revisions = revisions, failed_calls = failures,
                          truncated_calls = cut, truncations = truncated,
                          tokens_truncated = dropped),
             premise = out$premise)
}
