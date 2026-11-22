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
  # refine_state = "ledger": the state is a list of findings, not a draft.
  is_ledger <- identical(spec$refine_state, "ledger")
  ledger <- character(0)
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
                  prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate),
                  if (is_ledger) prompt_overhead(question, ledger_system_prompt(spec$premise),
                                                 "never"))
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  p <- progress_start(nrow(d), "chunk", trace)
  with_progress(p, for (i in seq_len(nrow(d))) {
    if (i > 1L) progress_tick(p, i - 1L)
    excerpt <- render_chunks(d[i, , drop = FALSE])
    # Halve the budget between the running draft and the incoming excerpt.
    # The cuts are counted once the request is known to have gone out.
    half <- max(as.integer(bud$input / 2), 64L)
    # Each cut goes into the trace with the tokens it dropped: the draft's cut
    # loses its end, which no later revision can see again. The counts on the
    # answer are added only once the request is known to have gone out.
    cuts <- 0L
    cut_tokens <- 0L
    kept_draft <- draft
    kept_ledger <- ledger
    if (!is.null(spec$context_policy)) {
      # Under a context policy the draft (or ledger) and the excerpt share the
      # input budget, and the policy decides which is cut and which part of
      # it is kept, in place of an even split.
      state_name <- if (is_ledger) "ledger" else "draft"
      have <- if (is_ledger) ledger_text(ledger) else draft
      pieces <- stats::setNames(c(as_chr1(have, ""), excerpt), c(state_name, "excerpt"))
      fit <- hr_context_fit(pieces, bud$input, spec$context_policy, trace = trace,
                            where = "refine")
      cuts <- length(fit$cut); cut_tokens <- as.integer(fit$tokens_dropped)
      excerpt <- fit$pieces[["excerpt"]]
      if (state_name %in% fit$cut) {
        if (is_ledger) {
          # A finding the cut went through is dropped whole.
          ledger <- ledger_whole(ledger, fit$pieces[["ledger"]])
          cut_tokens <- cut_tokens + as.integer(max(gr_count_tokens(fit$pieces[["ledger"]]) -
                                                      gr_count_tokens(ledger_text(ledger)), 0))
        } else {
          draft <- fit$pieces[["draft"]]
        }
      }
    } else {
      if (gr_count_tokens(excerpt) > half) {
        t <- truncate_logged(excerpt, half, "refine.excerpt", trace, chunk_id = d$chunk_id[i])
        excerpt <- t$text; cuts <- cuts + 1L; cut_tokens <- cut_tokens + t$dropped
      }
      if (!is.null(draft) && gr_count_tokens(draft) > half) {
        t <- truncate_logged(draft, half, "refine.draft", trace, chunk_id = d$chunk_id[i])
        draft <- t$text; cuts <- cuts + 1L; cut_tokens <- cut_tokens + t$dropped
      }
      if (is_ledger && length(ledger) && gr_count_tokens(ledger_text(ledger)) > half) {
        t <- truncate_logged(ledger_text(ledger), half, "refine.ledger", trace,
                             chunk_id = d$chunk_id[i], marker = "")
        all_tokens <- gr_count_tokens(ledger_text(ledger))
        ledger <- ledger_whole(ledger, t$text); cuts <- cuts + 1L
        cut_tokens <- cut_tokens + as.integer(max(all_tokens -
                                                    gr_count_tokens(ledger_text(ledger)), 0))
      }
    }
    # The draft as this request carries it, for the state length below.
    state_in <- if (is_ledger) gr_count_tokens(ledger_text(ledger))
                else if (is.null(draft)) 0L else gr_count_tokens(draft)
    from <- length(trace$steps)
    msgs <- if (is_ledger) {
      ledger_messages(question, ledger, excerpt, spec$premise)
    } else if (is.null(draft)) {
      answer_messages(question, excerpt, cite = spec$cite, restate = restate_how(spec),
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
    step_label <- if (if (is_ledger) i == 1L else is.null(draft)) "refine.draft" else "refine.revise"
    res <- gr_call(client, msgs, model = spec$model, max_output = spec$max_answer_tokens,
                   temperature = spec$temperature, trace = trace,
                   label = step_label, effort = spec$effort)
    # A limit ends the pass, with the draft as it was before this chunk.
    if (is_refused(res)) { draft <- kept_draft; ledger <- kept_ledger; break }
    truncated <- truncated + cuts
    dropped <- dropped + cut_tokens
    # The state length at every step: the draft sent and the draft carried on,
    # which is the old one when the reply was unusable. A draft that shrinks
    # sharply in one revision is the collapse a whole rewrite can cause.
    if (is_ledger) {
      # The reply is a list of edits to the ledger; the code applies them, so
      # an item no edit names is carried forward word for word.
      if (!usable_text(res)) {
        trace_state(trace, from, step_label, tokens_in = state_in, tokens_out = state_in)
        failures <- failures + 1L; next
      }
      before <- ledger
      ledger <- ledger_apply(ledger, res$text)
      trace_state(trace, from, step_label, tokens_in = state_in,
                  tokens_out = gr_count_tokens(ledger_text(ledger)))
      if (reply_cut_off(res)) cut <- cut + 1L
      used <- c(used, d$chunk_id[i])
      if (i > 1L && !identical(before, ledger)) revisions <- revisions + 1L
      if (spec$delay_between_calls > 0) Sys.sleep(spec$delay_between_calls)
      next
    }
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
  if (is_ledger) {
    fin <- ledger_answer(ledger, question, client, spec, trace)
    if (isTRUE(fin$failed)) failures <- failures + 1L
    if (isTRUE(fin$cut)) cut <- cut + 1L
    draft <- fin$text
  }
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
                          tokens_truncated = dropped,
                          ledger_items = if (is_ledger) length(ledger)),
             premise = out$premise)
}

# ---------------------------------------------------------------------------
# refine_state = "ledger"
# The state carried down the document is a numbered list of findings. Each
# request is shown the list and one excerpt and replies with edits: ADD a
# finding, REPLACE finding n when the excerpt corrects it, DROP finding n when
# the excerpt shows it wrong. The code applies the edits, so a finding no
# edit names is carried forward word for word, and a corrected one is
# replaced rather than annotated. One last request answers from the list.
# ---------------------------------------------------------------------------

#' The system prompt of a ledger edit, with the premise rule when asked.
#' @noRd
ledger_system_prompt <- function(premise = FALSE) {
  base <- .gr_prompts$refine_ledger_system
  if (isTRUE(premise)) paste0(base, .gr_premise_prompts$refine) else base
}

#' A ledger as the numbered list a request carries.
#' @noRd
ledger_text <- function(ledger) {
  if (!length(ledger)) return("")
  paste(sprintf("%d. %s", seq_along(ledger), ledger), collapse = "\n")
}

#' A numbered list read back into a ledger, as after a cut.
#' @noRd
ledger_from_text <- function(text) {
  lines <- trimws(strsplit(as_chr1(text, ""), "\n", fixed = TRUE)[[1]])
  lines <- lines[grepl("^[0-9]+\\.\\s+\\S", lines)]
  sub("^[0-9]+\\.\\s+", "", lines)
}

#' The findings of a ledger that a cut of its text kept whole. A numbered
#' line the cut went through is a finding cut short, and is dropped, so every
#' finding carried forward is one the ledger holds word for word.
#' @noRd
ledger_whole <- function(ledger, text) {
  kept <- ledger_from_text(text)
  kept[kept %in% ledger]
}

#' The messages of one ledger edit.
#' @noRd
ledger_messages <- function(question, ledger, excerpt, premise = FALSE) {
  list(
    list(role = "system", content = ledger_system_prompt(premise)),
    list(role = "user", content = paste0("Question: ", question)),
    list(role = "user", content = paste0("<ledger>\n",
                                         if (length(ledger)) ledger_text(ledger) else "(empty)",
                                         "\n</ledger>")),
    list(role = "user", content = paste0("<new_excerpt>\n", excerpt, "\n</new_excerpt>")),
    list(role = "user", content = paste0(
      "Reply with the edits, one per line: ADD: <finding>, REPLACE <n>: <finding>, or ",
      "DROP <n>. Reply NONE if the excerpt changes nothing.")))
}

#' Apply a reply's edits to a ledger. Lines that are not edits are ignored;
#' an edit that names a finding the ledger does not have is ignored too.
#' @noRd
ledger_apply <- function(ledger, reply) {
  lines <- trimws(strsplit(as_chr1(reply, ""), "\n", fixed = TRUE)[[1]])
  lines <- sub("^[-*]\\s*", "", lines)
  n <- length(ledger)
  keep <- rep(TRUE, n)
  out <- ledger
  added <- character(0)
  for (ln in lines) {
    if (grepl("^ADD\\s*:", ln, ignore.case = TRUE)) {
      f <- trimws(sub("^ADD\\s*:", "", ln, ignore.case = TRUE))
      if (nzchar(f)) added <- c(added, f)
    } else if (grepl("^REPLACE\\s+[0-9]+\\s*:", ln, ignore.case = TRUE)) {
      k <- as.integer(sub("^REPLACE\\s+([0-9]+).*$", "\\1", ln, ignore.case = TRUE))
      f <- trimws(sub("^REPLACE\\s+[0-9]+\\s*:", "", ln, ignore.case = TRUE))
      if (!is.na(k) && k >= 1L && k <= n && nzchar(f)) out[k] <- f
    } else if (grepl("^DROP\\s+[0-9]+", ln, ignore.case = TRUE)) {
      k <- as.integer(sub("^DROP\\s+([0-9]+).*$", "\\1", ln, ignore.case = TRUE))
      if (!is.na(k) && k >= 1L && k <= n) keep[k] <- FALSE
    }
  }
  c(out[keep], added)
}

#' The answer from a finished ledger: one request, or NOT_IN_DOCUMENT with
#' none when the ledger is empty.
#' @noRd
ledger_answer <- function(ledger, question, client, spec, trace) {
  if (!length(ledger)) return(list(text = .NOT_FOUND))
  res <- gr_call(client, answer_messages(question, ledger_text(ledger), label = "Findings",
                                         restate = restate_how(spec), premise = spec$premise),
                 model = spec$model, max_output = spec$max_answer_tokens,
                 temperature = spec$temperature, trace = trace, label = "refine.answer",
                 effort = spec$effort)
  if (is_refused(res) || !usable_text(res)) {
    return(list(text = paste(ledger, collapse = "\n"), failed = !is_refused(res)))
  }
  list(text = res$text, cut = reply_cut_off(res))
}
