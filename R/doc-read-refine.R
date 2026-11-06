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
    excerpt <- render_chunks(d[i, , drop = FALSE])
    # Halve the budget between the running draft and the incoming excerpt.
    # The cuts are counted once the request is known to have gone out.
    half <- max(as.integer(bud$input / 2), 64L)
    cuts <- 0L
    kept_draft <- draft
    if (gr_count_tokens(excerpt) > half) {
      excerpt <- gr_truncate_tokens(excerpt, half); cuts <- cuts + 1L
    }
    if (!is.null(draft) && gr_count_tokens(draft) > half) {
      draft <- gr_truncate_tokens(draft, half); cuts <- cuts + 1L
    }
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
    res <- gr_call(client, msgs, model = spec$model, max_output = spec$max_answer_tokens,
                   temperature = spec$temperature, trace = trace,
                   label = if (is.null(draft)) "refine.draft" else "refine.revise",
                   effort = spec$effort)
    # A limit ends the pass, with the draft as it was before this chunk.
    if (is_refused(res)) { draft <- kept_draft; break }
    truncated <- truncated + cuts
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
                          truncated_calls = cut, truncations = truncated),
             premise = out$premise)
}
