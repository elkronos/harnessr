# doc-read-iterative.R: the iterative reader.

# ---------------------------------------------------------------------------
# iterative: topk | rounds x (1 + 1) | forward
# Agentic. The model states what it still needs, that becomes the next query,
# and the loop stops when it says it can answer or the budget runs out. The only
# strategy where the retrieval query is not the user's question.
# ---------------------------------------------------------------------------
#' The gathered chunks that fit one prompt, whole.
#'
#' `iterative` used to paste everything gathered and call `gr_truncate_tokens()`
#' on the result, which was wrong twice over. It cut the TAIL, so the chunks from
#' the most recent round were the ones dropped -- in a reader whose whole premise
#' is "that did not answer it, go and get more", it discarded the material it had
#' just decided it needed. And it cut mid-chunk, which breaks the audit chain: a
#' chunk cut in half no longer contains the sentence an answer quotes from it, so
#' `verified` comes back false for a reason that has nothing to do with the
#' document.
#'
#' Whole chunks, ranked by the score that justified taking them -- a chunk's
#' score at the round it was selected, not its score against the latest query,
#' because the earlier query is what it was chosen to answer. Everything that
#' reaches the prompt is intact and therefore still checkable, and what did not
#' fit is reported instead of being counted as read.
#' @noRd
iterative_fit <- function(d, seen, score, budget, how = "relevance") {
  sub <- d[seen, , drop = FALSE]
  fit <- fit_chunks(sub, budget, order = order(-score))
  keep <- fit$idx
  keep <- switch(as_chr1(how, "relevance"),
                 # Positional within `sub`, which is accumulation order, so
                 # document order has to come from the chunk ids themselves.
                 document = keep[order(sub$chunk_id[keep])],
                 edges = arrange_context(keep, "edges"),
                 keep)
  list(rows = seen[keep], dropped = seen[fit$dropped],
       body = if (length(keep)) render_chunks(sub[keep, , drop = FALSE]) else "")
}

#' @noRd
read_iterative <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  emb <- gr_embed(client, d$text, trace = trace)
  degraded_embed <- isTRUE(attr(emb, "embedding_fallback"))
  src <- attr(emb, "embedding_source") %||% "api"
  # The chunks on word overlap, for a round whose query could only be embedded
  # that way; made the first time one needs them.
  lex_emb <- if (identical(src, "lexical")) emb else NULL
  seen <- integer(0); seen_score <- numeric(0); queries <- as_chr1(question)
  dropped <- integer(0)
  rounds <- 0L; done_reason <- "max rounds"

  schema <- list(type = "object", additionalProperties = FALSE,
                 required = list("can_answer", "answer", "next_query"),
                 properties = list(
                   can_answer = list(type = "boolean"),
                   answer = list(type = "string"),
                   next_query = list(type = "string")))
  # The verdict as a field of its own, and only when it is asked for: the
  # schema is part of every request and of the cache key, so a spec that does
  # not check the premise sends the schema it always sent.
  if (isTRUE(spec$premise)) {
    schema$required <- c(schema$required, list("false_premise"))
    schema$properties$false_premise <- list(type = "boolean")
  }
  # With verify = TRUE a step that says it can answer has to show where: the
  # passages it rests on, word for word, each with the chunk it is from. The
  # loop stops only when every one is found in that chunk. Without it the
  # schema and prompt are the ones always sent.
  verify <- isTRUE(spec$verify)
  if (verify) {
    schema$required <- c(schema$required, list("quotes"))
    schema$properties$quotes <- list(
      type = "array",
      items = list(type = "object", additionalProperties = FALSE,
                   required = list("chunk_id", "text"),
                   properties = list(chunk_id = list(type = "integer"),
                                     text = list(type = "string"))))
  }
  feedback <- ""
  rejected <- 0L
  last_unverified <- NULL

  # Built once and used for BOTH the budget and the call. Budgeting against
  # `answer_system` alone while sending this understated the overhead by 88
  # tokens a round, and the excerpts were sized to fill the gap.
  # answer_system(spec$cite): this step is what writes the answer whenever the
  # model is satisfied, so a request for citations that reached only the
  # fallback answer call was dropped on the usual path.
  step_system <- paste0(
    answer_system(spec$cite, spec$premise),
    " You are reading iteratively. If the excerpts so far are sufficient, set can_answer ",
    "true and give the answer. If not, set can_answer false and put in next_query the ",
    "specific missing information to search for -- a phrase you would expect to appear in ",
    "the document, not a restatement of the question.",
    if (isTRUE(spec$premise)) .gr_premise_prompts$iterative,
    if (verify) .gr_iterative_quote_prompt)

  while (rounds < spec$max_rounds) {
    rounds <- rounds + 1L
    q <- queries[length(queries)]
    q_emb <- gr_embed(client, q, trace = trace)
    rank_emb <- emb
    q_vec <- if (nrow(q_emb)) q_emb[1, ] else numeric(0)
    # One space for the query and the chunks. The query is embedded on its own
    # each round, and one whose request failed came back as 512 hashed lexical
    # dimensions against the API's vectors for the chunks: cosine_against()
    # compared the first 512 of each, two unrelated spaces, and the round took
    # whatever that picked with partial = FALSE. `retrieve` embeds the question
    # with the chunks, in one request, and cannot mix them. Here both go onto
    # word overlap for the round, and the answer says so. A query that came
    # back with no vector at all goes the same way: cosine_against() now
    # refuses vectors of different lengths instead of scoring them 0.
    if (nrow(d) && (!nrow(q_emb) ||
                    !identical(attr(q_emb, "embedding_source") %||% "api", src) ||
                    NCOL(q_emb) != NCOL(emb))) {
      if (is.null(lex_emb)) lex_emb <- lexical_embed(d$text)
      rank_emb <- lex_emb
      q_vec <- lexical_embed(q)[1, ]
      degraded_embed <- TRUE
    }
    degraded_embed <- degraded_embed || isTRUE(attr(q_emb, "embedding_fallback"))
    sc <- if (nrow(rank_emb)) cosine_against(rank_emb, q_vec) else rep(0, nrow(d))
    # -Inf, not removal: mmr_select() treats a non-finite relevance as ineligible,
    # which is how a chunk already read stays out of this round without
    # renumbering everything around it.
    sc[seen] <- -Inf
    take <- mmr_select(sc, if (nrow(rank_emb) == nrow(d)) rank_emb else NULL,
                       as.integer(clamp(spec$top_k, 1, nrow(d))), as_num1(spec$mmr, 1))
    # Retrieval has run out, but a refused step is still owed its refusal: the
    # round goes on with the chunks already gathered, so the model can quote
    # them correctly. Without a refusal pending there is nothing new to read.
    if (!length(take) && !nzchar(feedback)) { done_reason <- "no unseen chunks"; break }
    if (length(take)) {
      seen <- c(seen, take)
      seen_score <- c(seen_score, sc[take])
    }

    obud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens,
                      overhead = prompt_overhead(question, step_system, spec$restate))
    # A refusal sent back under verify = TRUE is one message more to fit.
    room <- obud$input - if (nzchar(feedback)) gr_count_tokens(feedback) + 8L else 0L
    step <- iterative_fit(d, seen, seen_score, room, spec$context_order)
    body <- step$body
    dropped <- step$dropped

    # Nothing gathered fits one prompt. The call was made anyway, with an empty
    # <excerpts></excerpts>, and a model asked a question with no document in
    # front of it answers from its own prior -- which came back as the
    # document's answer, can_answer = true, chunks_used empty. An answer with no
    # excerpt behind it is the one thing this package must not return.
    if (!length(step$rows)) { done_reason <- "no gathered chunk fits one prompt"; break }

    step_messages <- list(
      list(role = "system", content = step_system),
      list(role = "user", content = paste0("Question: ", question)),
      # The question again after the excerpts when there are enough of them to
      # bury it. Every other reader asks last, through answer_messages(); this
      # one asked first and then handed over several thousand tokens.
      list(role = "user", content = paste0("<excerpts>\n", body, "\n</excerpts>",
                                           restate_tail(body, question, spec$restate))))
    # The quotations the last step gave that were not in their chunks, so the
    # model knows what was refused and where. Only under verify = TRUE, and
    # only after a refusal.
    if (nzchar(feedback)) {
      step_messages <- c(step_messages, list(list(role = "user", content = feedback)))
    }
    out <- gr_call_json(client, step_messages, schema = schema, schema_name = "iterative_step", model = spec$model,
       max_output = spec$max_answer_tokens, temperature = spec$temperature,
       trace = trace, label = "iterative.step", effort = spec$effort)
    # A limit ends the loop; what was gathered is answered from below.
    if (is_refused(out$result)) { done_reason <- cap_name(trace); break }

    if (!out$ok) {
      # A reply cut off at the cap is not parsable JSON, and saying so is more
      # use than asking whether the endpoint supports JSON schema output.
      cut_step <- reply_cut_off(out$result)
      done_reason <- if (cut_step) "step cut off at the output cap" else "step failed"
      if (rounds == 1L) {
        gr_warn(paste0("The first iterative step returned no parsable structured output, so the ",
                       "retrieve-assess loop cannot run ",
                       if (cut_step)
                         "(the reply was cut off at the output cap; raise max_answer_tokens)"
                       else "(does this endpoint support JSON schema output?)",
                       ". Answering from the first retrieval only, which is in effect ",
                       "'retrieve', not 'iterative'."), class = "gr_iterative_degraded")
      }
      break
    }
    answer <- as_chr1(json_text(out$value, "answer"), "")
    # A step that reports the premise false has read enough to say so, whatever
    # it set can_answer to: the verdict is the outcome, and another round would
    # go looking for support for an assumption the excerpts contradict. The
    # verdict is read from the `false_premise` field or the sentinel in
    # `answer` (premise_field_reply()); a flag whose answer is the not-found
    # sentinel is no verdict, and the step is read as can_answer says.
    verdict <- if (isTRUE(spec$premise))
      premise_field_reply(answer, isTRUE(json_field(out$value, "false_premise")))
      else list(text = answer, premise = NULL)
    contradicted <- is_nonblank(verdict$premise)
    if (isTRUE(json_field(out$value, "can_answer")) || contradicted) {
      # Satisfied, with no answer, is a step that failed. Returned, a blank came
      # back as a blank answer and a null as a confident NOT_IN_DOCUMENT, both
      # with evidence and partial = FALSE. The answer call below reads what was
      # gathered instead, and that answer is partial. A premise verdict without
      # its sentence is still a verdict.
      if (!contradicted && !nzchar(trimws(answer))) { done_reason <- "step gave no answer"; break }
      # A premise verdict is not held to quotations here: the prompt asks for
      # them only with can_answer true, and quote-backed verdicts come later.
      quoted <- verify && !contradicted
      if (quoted) {
        quotes <- step_quotes(out$value, d, step$rows)
        if (!nrow(quotes) || !all(quotes$verified)) {
          # Not a stop: the model said it could answer and did not show it.
          # The next round is told which quotations were refused, and looks
          # further with its query, or with the same one when it gave none.
          rejected <- rejected + 1L
          last_unverified <- verdict$text
          feedback <- iterative_feedback(quotes)
          trace_note(trace, "iterative.unverified",
                     list(round = rounds, quotes = nrow(quotes),
                          failed = sum(!quotes$verified)))
          nq <- as_chr1(json_text(out$value, "next_query"))
          if (nzchar(nq) && !nq %in% queries) queries <- c(queries, nq)
          next
        }
      }
      # Why the loop stopped, in the trace and the notes: a premise verdict is
      # not the model satisfied with an answer.
      why <- if (contradicted) "premise contradicted" else "model satisfied"
      trace_note(trace, "iterative.stop", list(rounds = rounds, reason = why))
      # `step$rows`, not `seen`: a chunk that did not fit the prompt was never
      # shown to the model, and reporting it as used -- with a row in the
      # evidence table -- claims provenance the answer does not have.
      keep <- step$rows
      # The step's JSON parsed, but the provider says the reply stopped at the
      # cap, so the answer inside it may be missing its end.
      cut <- as.integer(reply_cut_off(out$result))
      notes <- list(rounds = rounds, chunks_seen = length(seen),
                    chunks_dropped = length(dropped), truncated_calls = cut,
                    queries = queries, stop_reason = why,
                    embedding_fallback = degraded_embed)
      # Under verify = TRUE the evidence is what the answer cites, checked
      # against the chunk text and not the model's copy of it; otherwise every
      # chunk the step was shown, as always.
      if (verify) notes$quotes_rejected_steps <- rejected
      ev <- if (quoted) {
        at <- match(quotes$chunk_id, d$chunk_id)
        evidence_table(quotes$chunk_id, quotes$text, d$page[at], d$section[at],
                       source_text = reader_source_text(d)[at], kind = "extracted")
      } else {
        evidence_table(d$chunk_id[keep], reader_source_text(d)[keep],
                       d$page[keep], d$section[keep], kind = "verbatim")
      }
      return(new_answer(verdict$text, "iterative", question,
                        d$chunk_id[keep], trace, premise = verdict$premise,
                        evidence = ev,
                        partial = degraded_embed || length(dropped) > 0L || cut > 0L,
                        notes = notes))
    }
    feedback <- ""
    nq <- as_chr1(json_text(out$value, "next_query"))
    if (!nzchar(nq) || nq %in% queries) { done_reason <- "query loop"; break }
    queries <- c(queries, nq)
    gr_msg(sprintf("Iterative round %d -> searching for: %s", rounds, substr(nq, 1, 90)))
  }

  # Under verify = TRUE an answer is returned only with quotations that were
  # found. Rounds or budget ran out before one was, so the outcome is not
  # found, and the last answer refused is kept in the notes for a reader to
  # weigh, not given as the answer.
  if (verify) {
    return(new_answer(.NOT_FOUND, "iterative", question, integer(0), trace, partial = TRUE,
                      notes = list(rounds = rounds, chunks_seen = length(seen),
                                   queries = queries, stop_reason = done_reason,
                                   quotes_rejected_steps = rejected,
                                   unverified_answer = last_unverified,
                                   embedding_fallback = degraded_embed)))
  }
  # Budget exhausted: answer from everything gathered rather than returning
  # nothing for work already paid for.
  if (!length(seen)) {
    return(new_answer(.NOT_FOUND, "iterative", question, integer(0), trace, partial = TRUE,
                      notes = list(rounds = rounds, stop_reason = done_reason)))
  }
  # Fitted, which it never was: every other reader sizes its final prompt to the
  # budget and this one rendered everything gathered. Several rounds of top_k
  # chunks routinely exceed the window, and the call was simply rejected by the
  # provider after the whole loop had been paid for.
  fbud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens,
                    overhead = prompt_overhead(question, answer_system(spec$cite, spec$premise),
                                               spec$restate))
  final <- iterative_fit(d, seen, seen_score, fbud$input, spec$context_order)
  sub <- d[final$rows, , drop = FALSE]
  res <- if (!nrow(sub)) {
    gr_result(FALSE, error = "no gathered chunk fits the context window")
  } else {
    gr_call(client, answer_messages(question, final$body, cite = spec$cite,
                                    restate = spec$restate, premise = spec$premise),
            model = spec$model, max_output = spec$max_answer_tokens,
            temperature = spec$temperature, trace = trace, label = "iterative.final",
            effort = spec$effort)
  }
  # Partial already, since the loop did not finish; the count says why as well.
  cut <- as.integer(res$ok && reply_cut_off(res))
  out <- premise_reply(if (res$ok) res$text else .NOT_FOUND, spec$premise)
  # No answer, no evidence; see stuff.
  new_answer(out$text, "iterative", question, sub$chunk_id, trace, premise = out$premise,
             evidence = if (res$ok) evidence_table(sub$chunk_id, reader_source_text(sub), sub$page,
                                                   sub$section, kind = "verbatim"),
             partial = TRUE,
             notes = list(rounds = rounds, chunks_seen = length(seen),
                          chunks_dropped = length(final$dropped), truncated_calls = cut,
                          queries = queries,
                          stop_reason = done_reason, embedding_fallback = degraded_embed))
}

#' What an iterative step under verify = TRUE adds to its instructions.
#' @noRd
.gr_iterative_quote_prompt <- paste0(
  " When you set can_answer true, put in quotes the passages from the excerpts that support ",
  "the answer, each copied word for word, with the number of the chunk it comes from as ",
  "chunk_id. The answer is accepted only if every quoted passage is found in its chunk.")

#' The quotations an iterative step gave, each checked against the chunk it
#' names.
#'
#' The chunk's text comes from the chunk set, never from the step's reply, and
#' a chunk the step was not shown this round cannot back anything it says. The
#' check is span_match(), the one that decides `verified` everywhere else, so
#' a quotation that stops the loop is one gr_verify_evidence() also passes.
#' @return A data frame: `chunk_id`, `text`, `verified`.
#' @noRd
step_quotes <- function(value, d, shown) {
  raw <- json_field(value, "quotes", scalar = FALSE)
  # A parsed array of objects is a data frame, and an array of one object can
  # arrive as that object alone.
  if (is.data.frame(raw)) {
    raw <- lapply(seq_len(nrow(raw)), function(i) as.list(raw[i, , drop = FALSE]))
  } else if (is.list(raw) && !is.null(names(raw))) {
    raw <- list(raw)
  }
  if (!is.list(raw)) raw <- list()
  ids <- vapply(raw, function(q) {
    v <- suppressWarnings(as.integer(as_chr1(if (is.list(q)) q[["chunk_id"]], NA_character_)))
    if (length(v) == 1L) v else NA_integer_
  }, integer(1))
  text <- vapply(raw, function(q) as_chr1(if (is.list(q)) q[["text"]], ""), character(1))
  keep <- nzchar(trimws(text))
  ids <- ids[keep]
  text <- text[keep]
  src <- reader_source_text(d)
  ok <- vapply(seq_along(text), function(i) {
    row <- match(ids[i], d$chunk_id)
    !is.na(row) && row %in% shown && isTRUE(span_match(text[i], src[row])$verified)
  }, logical(1))
  data.frame(chunk_id = ids, text = text, verified = ok, stringsAsFactors = FALSE)
}

#' The message that tells the next step why its answer was not accepted.
#' @noRd
iterative_feedback <- function(quotes) {
  if (!nrow(quotes)) {
    return(paste0("Your last answer was not accepted: it gave no quoted passage from the ",
                  "excerpts. Quote the passages that support the answer, word for word, ",
                  "with their chunk numbers."))
  }
  bad <- quotes[!quotes$verified, , drop = FALSE]
  lines <- sprintf("[chunk %s] \"%s\"", ifelse(is.na(bad$chunk_id), "?", bad$chunk_id),
                   substr(bad$text, 1L, 300L))
  paste0("Your last answer was not accepted. These quoted passages were not found in the ",
         "chunks they name:\n", paste(lines, collapse = "\n"),
         "\nQuote the excerpts word for word, with the chunk each passage is in, or keep ",
         "searching.")
}
