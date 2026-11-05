# core-transport-call.R -- the single place that talks to a model API.
#
# WHY THIS FILE EXISTS
# `process_api_call()` had five separate defects that leaked into every caller:
#
#   1. It returned a bare `NULL` on transport failure and `character(0)` when
#      the API returned `content: null`. Callers wrote `if (!nzchar(x))`, which
#      is `NA` for `character(0)` -- an "argument is not interpretable as
#      logical" crash *after* the money was spent. Other callers ran `sapply()`
#      over responses; one NULL turned the result into a list, `nzchar()` then
#      deparsed it, and the literal string "NULL" was spliced into the next
#      prompt as if it were document content.
#   2. It warned on HTTP 400 and then called `httr::stop_for_status()` anyway,
#      so the documented "returns NULL on failure" contract was false and a
#      single bad chunk aborted a whole multi-mode run.
#   3. It shipped `max_tokens` equal to the model's full output limit with no
#      regard for prompt length, guaranteeing 400s on long prompts.
#   4. It carried a branch (`if (!inherits(response, "response")) status <- 200`)
#      that existed only so the test fakes would work -- production code shaped
#      by test convenience.
#   5. `gsub("\n+", " ", result)` flattened every answer, destroying lists,
#      tables and code blocks unconditionally.
#
# The replacement returns a typed `gr_result` that is *always* safe to index,
# distinguishes retryable from terminal failures, preserves formatting, and
# never itself calls `stop()` for an API-side error -- the caller decides.

#' The result of one model call
#' @noRd
gr_result <- function(ok, text = "", error = NULL, status = NA_integer_,
                      usage = list(input = 0L, output = 0L), model = NA_character_,
                      finish_reason = NA_character_, retryable = FALSE, raw = NULL,
                      cached = FALSE) {
  structure(list(
    ok = isTRUE(ok),
    # ALWAYS character(1); never NULL/character(0). And always LABELLED: bytes
    # arrive correct but unmarked from plenty of sources, and an unmarked string
    # is at the mercy of the session locale the moment anything serialises,
    # compares or counts characters in it. mark_utf8() labels, it does not
    # convert, so this cannot corrupt a response the way enc2utf8() would.
    # Bytes that are not UTF-8 at all are replaced first; see repair_utf8().
    text = mark_utf8(repair_utf8(as_chr1(text))),
    error = error,
    status = status,
    usage = usage,
    model = model,
    # One spelling for a reply cut off at the output cap, whoever sent it; see
    # normalise_finish_reason().
    finish_reason = normalise_finish_reason(finish_reason),
    retryable = isTRUE(retryable),
    raw = raw,
    # TRUE when the response came from a cache or a recording rather than the
    # network. `usage` still reports the real token counts of the original call,
    # so the trace can say how big the prompt was; `cached` is what stops those
    # tokens from being counted as money spent this run.
    cached = isTRUE(cached)
  ), class = "gr_result")
}

#' Replace the bytes of a model's text that are not UTF-8, so no regex fails on
#' it.
#'
#' A reply is UTF-8 by contract, but jsonlite decodes a lone low-surrogate
#' escape ("\udc00", half of a split emoji) into the bytes ED B0 80, which
#' validUTF8() rejects. The first trimws() or gsub() on that text then stopped
#' with "input string 1 is invalid UTF-8" -- in parse_response(), outside every
#' handler, so a paid call vanished from the trace and one chunk's reply failed
#' the whole document. The bytes are replaced with U+FFFD, the character that
#' means "something was here that could not be read", rather than reinterpreted
#' in some other encoding as to_utf8() does for documents: a model reply that is
#' not UTF-8 is damaged, not Latin-1. Encoded surrogates are replaced by
#' pattern first, because the platform iconv() on macOS lets them through.
#' Costs one validUTF8() pass when there is nothing to repair.
#' @noRd
repair_utf8 <- function(x) {
  if (!length(x) || !is.character(x)) return(x)
  bad <- which(!is.na(x) & !validUTF8(x))
  if (!length(bad)) return(x)
  y <- gsub("\xed[\xa0-\xbf][\x80-\xbf]", "\ufffd", x[bad], useBytes = TRUE)
  y <- iconv(y, "UTF-8", "UTF-8", sub = "\ufffd")
  # iconv() gives NA only when it cannot convert at all; drop what is left
  # then, as to_utf8()'s last resort does.
  gone <- is.na(y) | !validUTF8(y)
  if (any(gone)) {
    y[gone] <- iconv(x[bad][gone], "UTF-8", "ASCII", sub = "")
    y[is.na(y)] <- ""
  }
  x[bad] <- y
  mark_utf8(x)
}

#' The same repair for every string in a parsed JSON value, keeping its shape.
#' @noRd
repair_utf8_deep <- function(x) {
  if (is.character(x)) {
    x[] <- repair_utf8(as.vector(x))
    return(x)
  }
  if (is.list(x) && length(x)) x[] <- lapply(x, repair_utf8_deep)
  x
}

#' The provider spellings of "the reply was cut off at the output cap".
#'
#' Chat Completions says `length`; the Responses API sets `status` to
#' `incomplete` with `incomplete_details.reason` `max_output_tokens`; Anthropic
#' says `max_tokens`, Gemini `MAX_TOKENS`, and ellmer normalises to `max_tokens`
#' or `context_window`. Callers checked for `length` alone, so on the default
#' Responses API and on every ellmer provider a cut-off reply looked complete:
#' `gr_synthesise()` kept a revision that ended mid-sentence. `incomplete` with
#' no reason given is read as cut off too -- the provider itself says the reply
#' is not whole, and treating it as complete is the direction that misleads.
#' @noRd
.gr_truncation_reasons <- c("length", "max_tokens", "max_output_tokens", "incomplete",
                            "context_window", "model_context_window_exceeded")

#' @noRd
normalise_finish_reason <- function(x) {
  x <- as_chr1(x, NA_character_)
  if (!is.na(x) && tolower(x) %in% .gr_truncation_reasons) "length" else x
}

#' @export
print.gr_result <- function(x, ...) {
  cat(sprintf("<gr_result> ok=%s model=%s in=%s out=%s%s%s%s\n",
              x$ok, as_chr1(x$model, "?"), x$usage$input %||% 0, x$usage$output %||% 0,
              if (isTRUE(x$cached)) " cached" else "",
              if (identical(x$finish_reason, "length")) " truncated" else "",
              if (!x$ok) paste0(" error=", as_chr1(x$error)) else ""))
  if (nzchar(x$text)) cat(substr(x$text, 1, 400), if (nchar(x$text) > 400) " ..." else "", "\n")
  invisible(x)
}

#' Call a model
#'
#' @param client A `gr_client`.
#' @param messages A list of `list(role=, content=)` items, or a single string,
#'   which is wrapped as one user message. `role` may be `"system"`,
#'   `"developer"`, `"user"` or `"assistant"`.
#' @param model Overrides the client default.
#' @param max_output Maximum completion tokens. Clamped to the model's limit
#'   and to what the context window actually leaves after the prompt. A value
#'   that is not a single number (`NA`, text) warns and uses the model's limit,
#'   as `NULL` does. For a reasoning model (see [gr_model_info()]) the cap an
#'   API request carries also bounds the model's hidden reasoning, so a small
#'   cap is sent as at least 2048 tokens (within the model's limit and the
#'   context window); otherwise the reasoning can use all of it and the reply
#'   come back empty. The reply is then no longer held to the smaller cap by the
#'   API, and the extra tokens are billed if the model uses them.
#' @param temperature Sampling temperature; dropped automatically for reasoning
#'   models that reject it.
#' @param schema Optional JSON Schema (as a list) requesting structured output.
#' @param schema_name Name for the schema.
#' @param trace Optional `gr_trace` to record this call into.
#' @param label Short label for the trace entry.
#' @param ... Extra top-level body fields.
#' @param effort Reasoning effort for this call, or `NULL` (the default) to
#'   send none. One string, or a character vector named by label prefix,
#'   resolved against `label` as [gr_read_spec()] describes. Sent only when
#'   `model` is a reasoning model (see [gr_model_info()]), as `reasoning =
#'   {effort}` on the Responses API and `reasoning_effort` on Chat Completions;
#'   a [gr_mock_client()] or [gr_backend_client()] handler finds it in
#'   `params$effort`. Must be named in full, since it follows `...`.
#' @return A [gr_result]. **Never** `NULL`; `$text` is always a single string,
#'   `""` on failure. A successful HTTP call that returned no text (a refusal, a
#'   content filter) is reported as `ok = FALSE`, so an empty completion is never
#'   passed downstream as evidence. `$cached` is `TRUE` when the response came
#'   from a [gr_cache()] or a [gr_replay_client()] instead of the network.
#'   A reply cut off at the output cap keeps `ok = TRUE`, since its text is what
#'   the model wrote, but always carries `finish_reason = "length"`, whatever the
#'   provider called it (`"max_tokens"`, `"MAX_TOKENS"`, a Responses API status
#'   of `"incomplete"`); check for it wherever a complete reply matters. Such a
#'   reply is not written to a [gr_cache()].
#' @seealso [gr_client()], [gr_mock_client()], [gr_result], [gr_budget()],
#'   [gr_cache_client()], [gr_replay_client()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(messages, params) "The answer is 42.")
#' res <- gr_call(cl, "What is the answer?")
#' c(ok = res$ok, text = res$text)
#'
#' # A failed call still returns a usable object.
#' bad <- gr_call(gr_mock_client(function(m, p) stop("network down")), "hi")
#' c(ok = bad$ok, text = sprintf("<%s>", bad$text), error = bad$error)
#'
#' # A reasoning effort reaches a reasoning model, and the handler sees it.
#' seen <- gr_mock_client(function(m, p) {
#'   paste("effort:", if (is.null(p$effort)) "none" else p$effort)
#' })
#' gr_call(seen, "hi", model = "gpt-5.6-luna", effort = "low")$text
#' gr_call(seen, "hi", model = "gpt-4o", effort = "low")$text   # not a reasoning model
gr_call <- function(client, messages, model = NULL, max_output = NULL,
                    temperature = NULL, schema = NULL, schema_name = "result",
                    trace = NULL, label = "call", ..., effort = NULL) {
  # Checked here too, so the error names the function the user called.
  if (!inherits(client, "gr_client")) gr_abort("`client` must come from gr_client() or gr_mock_client().")
  # After `...`, so it is matched only by its full name: `...` is the request
  # body's own fields, and a field a gateway happens to call `eff` must still
  # go to the gateway.
  model_call(client, messages, model, max_output, temperature, schema, schema_name,
             trace, label, list(...), effort = check_effort(effort))
}

#' gr_call(), with a test a reply must pass before it is cached.
#'
#' `accept` is a function of the reply text. The cache wrote every reply with
#' ok = TRUE, but for a schema call gr_call_json() parses afterwards, and a
#' reply cut off mid-JSON is a failure to every reader of it. Caching it turned
#' a one-off glitch into a permanent failure that re-running could not clear --
#' the one thing the cache promises never to do. So the caller that knows what
#' a usable reply is says so, and a stored reply that fails the same test (one
#' written before this existed) is asked again rather than replayed.
#' @noRd
model_call <- function(client, messages, model = NULL, max_output = NULL,
                       temperature = NULL, schema = NULL, schema_name = "result",
                       trace = NULL, label = "call", extra = list(), accept = NULL,
                       effort = NULL) {
  if (!inherits(client, "gr_client")) gr_abort("`client` must come from gr_client() or gr_mock_client().")
  messages <- normalise_messages(messages)
  model <- as_chr1(model %||% client$model)
  info <- gr_model_info(model)

  # Counted in the model's own encoding where the tokenizer has one (tiktoken).
  prompt_tokens <- sum(gr_count_tokens(vapply(messages, function(m) as_chr1(m$content), character(1)),
                                       model = model))
  headroom <- info$context_window - prompt_tokens - 32L
  # A cap that cannot be read is the model's cap, as NULL is. clamp() maps NA
  # to its floor, so max_output = NA -- a spec field left unset, text that is
  # not a number -- sent every request capped at ONE token (below the
  # Responses API's minimum of 16, so a 400), with no word about the setting.
  # gr_budget() was fixed for the same thing in `reserve_output`.
  if (!is.null(max_output) &&
      !(length(max_output) == 1L && (is.numeric(max_output) || is.character(max_output)) &&
        !is.na(suppressWarnings(as.numeric(max_output))))) {
    gr_warn("`max_output` must be a single number of tokens; using the model's limit.",
            class = "gr_bad_setting")
    max_output <- NULL
  }
  max_output <- as.integer(clamp(max_output %||% info$max_output, 1, info$max_output))
  if (headroom < max_output) max_output <- as.integer(max(headroom, 0L))

  if (max_output <= 0L) {
    res <- gr_result(FALSE, error = sprintf(
      paste0("Prompt is %d tokens but '%s' has a %d-token context window, leaving no room for a ",
             "reply. Segment more aggressively (lower `max_tokens` on the segmenter) or use a ",
             "larger-context model."),
      prompt_tokens, model, info$context_window), status = 0L, model = model)
    trace_record(trace, label, messages, res, params = list(model = model), seconds = 0)
    return(res)
  }

  params <- list(model = model, max_output = max_output, temperature = temperature,
                 schema = schema, schema_name = schema_name, prompt_tokens = prompt_tokens)
  # Resolved for this call's label here, where the label is the one the trace
  # records, and added only when there is one to send: params is what a
  # handler is given and what the trace keeps, and a NULL entry would change
  # both for every run that never asked for an effort.
  # The setting itself goes on to a replay, which must not let this session's
  # registry decide what the recording session sent (replay_lookup()).
  effort_map <- effort
  effort <- effort_to_send(effort, label, info)
  if (!is.null(effort)) params$effort <- effort

  # One dispatch, one exit, one trace entry. The mock and HTTP paths each used
  # to `return()` after recording their own trace entry, so every feature that
  # had to sit between the request and the response -- caching, replay -- would
  # have had to be written twice and kept in step by hand.
  started <- Sys.time()
  res <- client_dispatch(client, messages, model, max_output, temperature,
                         schema, schema_name, info, params, label, extra, accept,
                         effort_map = effort_map)
  # An ellmer chat is handed the effort only so that it can say it does not
  # send it (gr_ellmer_client()). Recorded as `effort`, the trace, its
  # `effort` column and the audit report said every request ran at an effort
  # none of them carried. So the step keeps it as the effort the call asked
  # for, under its own name, as does a replay of such a step. The handler's
  # params, the cache key and the replay key are left as they were.
  if (!is.null(params$effort) &&
      (inherits(client, "gr_ellmer_client") || isTRUE(res[["unsent_effort", exact = TRUE]]))) {
    params$unsent_effort <- params$effort
    params$effort <- NULL
  }
  trace_record(trace, label, messages, res, params,
               seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))
  res
}

#' Where a prepared request actually goes.
#'
#' Order matters. A replay client never reaches the network at all. A cache is
#' consulted before the request is issued and written only after it succeeds --
#' a failure is a property of the moment, not of the request, and caching one
#' would make a transient blip permanent. `accept`, when given, is the caller's
#' test of a usable reply (see model_call()).
#' @noRd
client_dispatch <- function(client, messages, model, max_output, temperature,
                            schema, schema_name, info, params, label, extra,
                            accept = NULL, effort_map = NULL) {
  if (inherits(client, "gr_replay_client")) {
    return(replay_lookup(client, messages, model, params, label, effort_map))
  }

  # Resolved BEFORE the key, not after. `temperature` arrives NULL whenever the
  # caller did not name one, and build_request_body() then filled it from
  # gr_options("temperature") -- after cache_key() had already hashed the NULL.
  # So two runs that sent different temperatures to the API computed the same
  # key: a temperature sweep through one cache directory explored nothing and
  # reported the first sample's answer for every setting. The reasoning-model
  # drop moves here for the mirror-image reason -- the body does not carry a
  # temperature for those models, so the key must not vary with one.
  temperature <- temperature %||% gr_options("temperature")
  if (isTRUE(info$reasoning) || !isTRUE(info$supports_temperature)) temperature <- NULL

  cache <- client$.cache
  key <- NULL
  usable <- function(r) is.null(accept) || isTRUE(tryCatch(accept(r$text), error = function(e) FALSE))
  if (inherits(cache, "gr_cache")) {
    key <- cache_key(client, messages, model, max_output, temperature,
                     schema, schema_name, extra, effort = params$effort)
    hit <- cache_get(cache, key)
    if (!is.null(hit) && !usable(hit)) {
      # Stored before the caller's test existed. Asked again, and overwritten
      # below if the new reply passes.
      cache_unhit(cache)
      hit <- NULL
    }
    if (!is.null(hit)) {
      # Entries are stored as built. One written before the truncation
      # spellings were unified can still say "incomplete" or "max_tokens".
      hit$finish_reason <- normalise_finish_reason(hit$finish_reason)
      return(hit)
    }
  }

  res <- if (inherits(client, "gr_mock_client")) {
    mock_dispatch(client, messages, model, params, label)
  } else if (inherits(client, "gr_backend_client")) {
    backend_dispatch(client, messages, model, params, label)
  } else {
    body <- build_request_body(client, messages, model,
                               reasoning_output_cap(max_output, info, params$prompt_tokens),
                               temperature, schema, schema_name, info, extra,
                               effort = params$effort)
    url <- paste0(client$base_url,
                  if (identical(client$api, "responses")) "/responses" else "/chat/completions")
    out <- http_call(client, url, body)
    out$model <- model
    out$usage <- settle_usage(out$usage, params$prompt_tokens, out$text)
    out
  }

  # A reply cut off at the cap is not stored either. It is an incomplete answer,
  # and caching it made the cut permanent: every later run replayed the same
  # half sentence instead of asking again.
  # Nor is a reply the caller has said it cannot use: a schema reply that does
  # not parse is as much a failure as a timeout.
  if (inherits(cache, "gr_cache") && isTRUE(res$ok) &&
      !identical(res$finish_reason, "length") && usable(res)) {
    cache_put(cache, key, res)
  }
  res
}

#' The output cap a request to a reasoning model is sent with.
#'
#' On the Responses API `max_output_tokens`, and on Chat Completions
#' `max_completion_tokens`, bound the reasoning tokens as well as the reply, and
#' a reasoning model at its default effort can spend a few hundred to a couple
#' of thousand of them before it writes a word. The package's short structured
#' calls ask for 90 to 200 tokens (a chunk's context line, a relevance score, a
#' conflict resolution), so on the default model all of the cap could go on
#' reasoning: the reply came back "incomplete" with no text, context headers
#' were silently dropped and rerank reported that the endpoint might not
#' support JSON schema -- while every call was billed. Such a request is sent
#' with room for the reasoning (at least `.gr_reasoning_floor` tokens, within
#' the model's limit and what the context window leaves after the prompt). A cap
#' at or above that is sent as it is. Only the HTTP request changes: the cache
#' key, the trace and a mock or backend handler see the cap the caller asked
#' for.
#' @noRd
reasoning_output_cap <- function(max_output, info, prompt_tokens) {
  max_output <- as.integer(max_output)
  if (!isTRUE(info$reasoning) || max_output >= .gr_reasoning_floor) return(max_output)
  room <- min(as_num1(info$max_output, .gr_reasoning_floor),
              as_num1(info$context_window, 0) - as_num1(prompt_tokens, 0) - 32)
  as.integer(max(max_output, min(.gr_reasoning_floor, room)))
}

#' The least output cap a reasoning model is sent; see reasoning_output_cap().
#' @noRd
.gr_reasoning_floor <- 2048L

#' Run a mock client's handler and normalise whatever it returned.
#' @noRd
mock_dispatch <- function(client, messages, model, params, label) {
  out <- tryCatch(client$handler(messages, params), error = function(e) e)
  res <- handler_result(out, model, as_int1(params$prompt_tokens, 0L))
  client$.log$calls <- c(client$.log$calls, list(list(messages = messages, params = params,
                                                      result = res, label = label)))
  res
}

#' Run a user-supplied backend handler.
#'
#' Same normalisation as the mock, deliberately: a backend is a stranger's
#' function, and every caller downstream relies on invariants it has never heard
#' of. Sharing `handler_result()` is what stops the two paths from drifting.
#' @noRd
backend_dispatch <- function(client, messages, model, params, label) {
  out <- tryCatch(client$handler(messages, params), error = function(e) e)
  res <- handler_result(out, model, as_int1(params$prompt_tokens, 0L))
  client$.log$calls <- c(client$.log$calls, list(list(messages = messages, params = params,
                                                      result = res, label = label)))
  res
}

#' Turn whatever a handler returned into a lawful `gr_result`.
#' Token usage the trace can trust.
#'
#' Unknown is not zero. When the provider's figure for a call is missing or not
#' a number, count locally instead: the prompt was measured before it was sent
#' and the reply is in hand. This package's tokenizer is deliberately biased to
#' over-count, so the substitute errs towards charging too much rather than too
#' little -- the same rule `ellmer_usage()` applies, now applied to the HTTP
#' path and to a handler-built result that left `usage` out. A figure the
#' provider did report is kept as reported, including a genuine zero.
#' @noRd
settle_usage <- function(usage, prompt_tokens, text) {
  num <- function(v) {
    v <- suppressWarnings(as.numeric(v))
    if (length(v) != 1L || is.na(v) || !is.finite(v) || v < 0) NA_integer_ else as.integer(v)
  }
  inp <- num(if (is.list(usage)) usage$input else NULL)
  out <- num(if (is.list(usage)) usage$output else NULL)
  list(input  = if (is.na(inp)) as_int1(prompt_tokens, 0L) else inp,
       output = if (is.na(out)) sum(gr_count_tokens(as_chr1(text))) else out)
}

#' @noRd
handler_result <- function(out, model, prompt_tokens) {
  if (inherits(out, "gr_result")) {
    # Re-normalise: a hand-built gr_result from a user handler can violate the
    # character(1) contract that every caller downstream relies on.
    txt <- repair_utf8(as_chr1(out$text))
    return(gr_result(out$ok, text = txt, error = out$error,
                     status = out$status %||% NA_integer_,
                     usage = settle_usage(out$usage, prompt_tokens, txt),
                     # A result built with gr_result() and no `model` carries
                     # NA, not NULL, so `%||%` kept it: the trace then priced
                     # the call as model "unknown" and added nothing to
                     # spent_usd, however many tokens it reported.
                     model = if (nzchar(as_chr1(out$model, ""))) as_chr1(out$model) else model,
                     finish_reason = out$finish_reason %||% NA_character_,
                     retryable = isTRUE(out$retryable), raw = out$raw,
                     cached = isTRUE(out$cached)))
  }
  if (inherits(out, "condition")) {
    # The handler was handed the prompt and then raised. Whether a provider
    # billed it first is not knowable from here, and for ellmer it usually did:
    # chat_structured() raises when it cannot parse the JSON the model sent
    # back, after the paid round trip. Recording 0 tokens made that spend
    # invisible to max_cost_usd, so the prompt is charged -- the direction that
    # keeps a spending limit honest, as settle_usage() does. The reply's
    # tokens are unknown and not charged. (The ellmer adapter no longer raises
    # for a reply it could not read: it returns the failure with the tokens
    # ellmer recorded for the turn, and raises only when there was no turn.)
    return(gr_result(FALSE, error = repair_utf8(conditionMessage(out)), model = model,
                     usage = list(input = as_int1(prompt_tokens, 0L), output = 0L)))
  }
  {
    # A handler that returns "" is the mock's version of the API returning
    # `content: null` -- a refusal, a content filter, a tool-call response. The
    # real client reports that as ok = FALSE, and `gr_result`'s documented
    # invariant says so. Reporting it as a successful empty answer here made
    # the mock disagree with production on the one case readers most need to
    # handle, and made the invariant untestable offline.
    txt <- repair_utf8(as_chr1(out))
    if (!nzchar(trimws(txt))) {
      gr_result(FALSE, text = "", error = "empty completion", model = model,
                finish_reason = "empty",
                usage = list(input = prompt_tokens, output = 0L))
    } else {
      gr_result(TRUE, text = txt, model = model,
                usage = list(input = prompt_tokens, output = sum(gr_count_tokens(txt))))
    }
  }
}

#' Call a model and parse a JSON-schema response into a list
#' @noRd
gr_call_json <- function(client, messages, schema, schema_name = "result",
                         allow_empty = FALSE, ...) {
  # The same test decides what is cached, so a reply this function would call
  # a failure is never stored as a success (see model_call()).
  accept <- function(txt) json_reply(txt, schema, allow_empty)$ok
  # gr_call()'s own arguments, so `...` is matched exactly as it was.
  send <- function(client, messages, model = NULL, max_output = NULL, temperature = NULL,
                   schema = NULL, schema_name = "result", trace = NULL, label = "call", ...,
                   effort = NULL) {
    model_call(client, messages, model, max_output, temperature, schema, schema_name,
               trace, label, list(...), accept = accept, effort = effort)
  }
  res <- send(client, messages, schema = schema, schema_name = schema_name, ...)
  if (!res$ok) return(list(ok = FALSE, value = NULL, result = res))
  out <- json_reply(res$text, schema, allow_empty)
  list(ok = out$ok, value = out$value, result = res)
}
