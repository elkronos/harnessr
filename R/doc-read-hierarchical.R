# doc-read-hierarchical.R: the hierarchical reader.

# ---------------------------------------------------------------------------
# hierarchical: all | N + tree + 1 | tree
# Genuinely recursive: summarise, then summarise the summaries, until what
# remains fits, then answer. The old "Hierarchical" mode did exactly one
# summarisation level and then concatenated -- so on a 40-chunk document its
# final prompt was 40 x 512 = 20,480 tokens against a 16,385-token window.
# ---------------------------------------------------------------------------
#' @noRd
read_hierarchical <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  summary_failures <- 0L
  cut <- 0L
  summary_model <- spec$summary_model %||% spec$model
  summarise <- function(texts, level) {
    # The longest text with its summary at the cap; see map_reduce.
    worst <- batch_item_usd(client, summary_model, max_tokens_of(gr_count_tokens(texts)) +
                              prompt_overhead(question, .gr_prompts$summarise_system, "never"),
                            spec$max_summary_tokens)
    got <- gr_lapply(seq_along(texts), function(i, trace) {
      r <- gr_call(client, list(
        list(role = "system", content = .gr_prompts$summarise_system),
        list(role = "user", content = paste0("Question: ", question)),
        list(role = "user", content = paste0("<text>\n", texts[i], "\n</text>"))
      ), model = summary_model, max_output = spec$max_summary_tokens,
         temperature = spec$temperature, trace = trace,
         label = sprintf("hier.summarise.L%d", level), effort = spec$effort)
      # Not sent is not failed; see map_reduce.
      if (is_refused(r)) return(list(text = "", capped = TRUE))
      list(text = if (usable_text(r)) r$text else "", capped = FALSE,
           cut = usable_text(r) && reply_cut_off(r))
    }, parallel = spec$parallel, label = sprintf("summary L%d", level), trace = trace,
       client = client, item_usd = worst)
    # A summary cut off at the cap is passed up the tree like any other, so the
    # answer rests on part of it; counted at every level, not just the last.
    cut <<- cut + sum(vapply(got, function(g) isTRUE(g$cut), logical(1)))
    structure(vapply(got, function(g) as_chr1(g$text), character(1)),
              capped = vapply(got, function(g) isTRUE(g$capped), logical(1)))
  }
  count_failures <- function(texts, got) {
    summary_failures <<- summary_failures + sum(!has_content(got) & !attr(got, "capped"))
    got
  }

  # FALSE, not spec$cite: the merge call below asks for summaries without
  # citation markers, so that is the system prompt it sends. The premise rule
  # does go with it: a summary keeps the figures a contradiction rests on.
  overhead <- prompt_overhead(question, answer_system(FALSE, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)

  level <- 1L
  current <- count_failures(d$text, summarise(d$text, level))
  current <- current[has_content(current)]
  if (!length(current)) {
    return(new_answer(.NOT_FOUND, "hierarchical", question, integer(0), trace, partial = TRUE,
                      notes = list(chunks = nrow(d), levels = 1L,
                                   reason = "every summarisation call failed")))
  }
  # Recurse until the combined summary fits, capping the depth so a model that
  # refuses to compress cannot spin forever.
  while (gr_count_tokens(paste(current, collapse = "\n\n")) > bud$input && level < spec$max_levels) {
    level <- level + 1L
    fan <- as.integer(spec$fan_in)
    groups <- split(current, ceiling(seq_along(current) / fan))
    prev_n <- length(current)
    grouped <- vapply(groups, paste, character(1), collapse = "\n\n")
    # Counted at every level, as at the first. A group whose summary failed
    # was filtered out uncounted, and the fan_in summaries in it -- five chunks
    # at level 2, twenty-five at level 3 -- left the answer with nothing in the
    # notes or the flag to say so.
    nxt <- count_failures(grouped, summarise(grouped, level))
    got <- has_content(nxt)
    gr_msg(sprintf("Hierarchical level %d: %d -> %d summaries.", level, prev_n, sum(got)))
    # A level that produced nothing, because a limit stopped it or every call
    # failed, leaves the summaries already paid for; they are cut to fit below.
    if (!any(got)) break
    # A group with no summary goes up as its input rather than vanishing: the
    # next level, or the cut to fit below, deals with it. The answer is partial
    # either way, by the count above or, for a request a limit stopped, by
    # gr_read().
    nxt[!got] <- grouped[!got]
    current <- unname(as.character(nxt))
    if (length(current) >= prev_n) break
  }

  body <- paste(current, collapse = "\n\n")
  # Cutting the summaries to fit drops part of the document from the answer, the
  # same loss `stuff` reports as dropped chunks, so it is partial and not only a
  # warning.
  truncated <- gr_count_tokens(body) > bud$input
  if (truncated) {
    body <- gr_truncate_tokens(body, bud$input)
    gr_warn(sprintf("Hierarchical summaries still exceed the budget after %d level(s); truncating.", level),
            class = "gr_overflow")
  }
  # cite = FALSE, always. This reader answers from SUMMARIES, which carry no
  # [chunk N] ids. Asking for citations here asks the model to invent ids that
  # are not in front of it, which is how a citing reader starts citing chunks
  # it never saw. A limit refuses the request, and the summaries are handed
  # back below.
  res <- gr_call(client, answer_messages(question, body, cite = FALSE, label = "Summaries",
                                         restate = spec$restate, premise = spec$premise),
                 model = spec$model, max_output = spec$max_answer_tokens,
                 temperature = spec$temperature, trace = trace, label = "hier.answer",
                 effort = spec$effort)
  if (usable_text(res) && reply_cut_off(res)) cut <- cut + 1L
  # Summaries handed back in place of an answer are no reply to classify.
  out <- if (usable_text(res)) premise_reply(res$text, spec$premise)
         else list(text = body, premise = NULL)
  new_answer(out$text, "hierarchical", question, d$chunk_id, trace, premise = out$premise,
             partial = !usable_text(res) || summary_failures > 0 || truncated || cut > 0L,
             notes = list(chunks = nrow(d), levels = level, final_summaries = length(current),
                          failed_summaries = summary_failures, truncated_calls = cut,
                          summaries_truncated = truncated))
}
