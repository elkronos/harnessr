# doc-read-cost.R: what each built-in reader can cost, as the `cost` function
# it registers (doc-modules.R).
#
# preflight() sums these to decide whether a read can start under the run's
# limits and records the result in the trace. Each function counts the
# requests its reader makes the way the reader makes them, so a change to a
# reader's call pattern is made here, next to the others, and not in the
# pre-flight check. `stats` is read_input_stats(); `params` is the read spec.
#
# `calls` is the expected count and `calls_max` the worst case: every reply at
# its cap and as many merge or summary levels as replies that size need. A
# worst case that cannot be sized (no known context window) falls back to the
# expected count. `sends` is what a reader that sends every chunk must send
# at least, and to which model; `batched` is FALSE for the readers that make
# one request, or theirs one at a time, each checked as it goes.

#' @noRd
cost_stuff <- function(stats, params) {
  # What fits in one request, not the whole document: the rest is cut.
  room <- tryCatch(suppressWarnings(gr_budget(params$model,
                                              reserve_output = params$max_answer_tokens)$input,
                                    classes = "gr_unknown_model"),
                   error = function(e) stats$tokens)
  hr_cost(calls = 1L, batched = FALSE,
          sends = list(list(tokens = min(stats$tokens, room), model = params$model)))
}

#' @noRd
cost_map_reduce <- function(stats, params) {
  n <- stats$n_chunks
  m <- merge_tree_worst(n, stats$reply_cap(params$model, params$max_chunk_tokens),
                        stats$reply_cap(params$model, params$max_answer_tokens),
                        # The prompt the merge sends, the premise rule included
                        # when the spec checks it: a longer system prompt leaves
                        # each merge less room.
                        stats$room(merge_system_prompt(params$premise)))
  calls <- n + ceiling(n / 5)
  hr_cost(calls = calls, calls_max = if (is.null(m)) calls else n + m$calls,
          tokens_in_max = if (is.null(m)) 0 else m$input,
          sends = list(list(tokens = stats$tokens, model = params$model)))
}

#' @noRd
cost_refine <- function(stats, params) {
  hr_cost(calls = stats$n_chunks, batched = FALSE,
          sends = list(list(tokens = stats$tokens, model = params$model)))
}

#' @noRd
cost_skim <- function(stats, params) {
  n <- stats$n_chunks
  model <- params$skim_model %||% params$model
  piece <- stats$reply_cap(model, params$max_chunk_tokens)
  fit <- stats$room(answer_system(params$cite, params$premise), params$restate)
  body <- n * piece
  # The evidence is consolidated in a merge tree only when it does not fit the
  # answer's prompt as it is.
  m <- if (is.na(fit)) NULL
       else if (body <= fit) list(calls = 0, input = 0)
       else merge_tree_worst(n, piece, stats$reply_cap(params$model, params$max_answer_tokens),
                             stats$room(.gr_prompts$summarise_system))
  calls <- n + 1L
  hr_cost(calls = calls, calls_max = if (is.null(m)) calls else n + m$calls + 1,
          tokens_in_max = if (is.null(m)) 0 else m$input + min(body, fit),
          sends = list(list(tokens = stats$tokens, model = model)))
}

#' @noRd
cost_retrieve <- function(stats, params) {
  hr_cost(calls = 1L, batched = FALSE,
          embed_max = stats$embed_requests(c(stats$question, stats$texts)))
}

#' @noRd
cost_rerank <- function(stats, params) {
  n <- stats$n_chunks
  m <- min(params$rerank_candidates, n)
  # Embeddings rank the candidates only when no chunk shares a word with the
  # question and there are more chunks than candidates (rerank_prefilter()).
  embeds <- if (m < n && shares_no_word(stats$texts, stats$question))
              stats$embed_requests(c(stats$question, stats$texts)) else 0L
  hr_cost(calls = m + 1L, embed_max = embeds)
}

#' @noRd
cost_hierarchical <- function(stats, params) {
  n <- stats$n_chunks
  model <- params$summary_model %||% params$model
  w <- summary_levels_worst(n, stats$reply_cap(model, params$max_summary_tokens),
                            stats$room(answer_system(FALSE, params$premise), params$restate),
                            params$fan_in, params$max_levels)
  calls <- n + ceiling(n / params$fan_in) + 1L
  hr_cost(calls = calls, calls_max = if (is.null(w)) calls else w$calls,
          tokens_in_max = if (is.null(w)) 0 else w$input,
          sends = list(list(tokens = stats$tokens, model = model)))
}

#' @noRd
cost_iterative <- function(stats, params) {
  # A step a round and the answer after them. Embeddings: every chunk, then
  # one query a round, the first being the question; a later round's query is
  # not known yet and counts as a request of its own. None of it when the
  # embeddings are not sent to the endpoint.
  embeds <- if (!isTRUE(stats$embed_api)) 0L
            else stats$embed_requests(stats$texts) + stats$embed_requests(stats$question) +
              as.integer(params$max_rounds) - 1L
  hr_cost(calls = params$max_rounds + 1L, batched = FALSE, embed_max = embeds)
}

#' @noRd
cost_extract <- function(stats, params) {
  # A call per chunk; with resolve = "model" a field that disagrees across
  # chunks takes one more, which the governor holds to the limits as it goes.
  hr_cost(calls = stats$n_chunks,
          sends = list(list(tokens = stats$tokens,
                            model = params$skim_model %||% params$model)))
}

#' @noRd
cost_screen <- function(stats, params) {
  # The opening of the document in one call, whatever its size.
  hr_cost(calls = 1L, batched = FALSE)
}

#' @noRd
cost_preview <- function(stats, params) {
  # A plan, the sections it picks and an answer. Which sections are picked is
  # not known before the plan, so every chunk is counted.
  hr_cost(calls = stats$n_chunks)
}

#' @noRd
cost_ensemble <- function(stats, params) {
  members <- params$members %||% c("retrieve", "map_reduce")
  # An ensemble inside an ensemble is refused when the reader runs; counted
  # here as one request per chunk rather than as itself, which never ends.
  parts <- lapply(members, function(m) {
    if (identical(m, "ensemble")) default_reader_cost("")(stats, params)
    else reader_cost(m, stats, params)
  })
  cost_sum(parts, extra_calls = 1L)
}
