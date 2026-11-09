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
                      cached = FALSE, served_model = NA_character_,
                      response_id = NA_character_, fingerprint = NA_character_,
                      attempts = NA_integer_) {
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
    cached = isTRUE(cached),
    # What the provider says about the reply it sent: the model that actually
    # answered (an alias such as "gpt-4o" is served by a dated snapshot), the
    # response id and the system fingerprint. `model` stays the model asked
    # for, since that is what pricing, the cache key and a replay look up.
    served_model = as_chr1(served_model, NA_character_),
    response_id = as_chr1(response_id, NA_character_),
    fingerprint = as_chr1(fingerprint, NA_character_),
    # Requests sent for this reply, retries included: 0 for a reply served
    # from a cache or a recording, NA when the transport does not say.
    attempts = as_int1(attempts, NA_integer_)
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
#' @param draw_index Which draw of a sampled request this is: 0 (the default)
#'   for an ordinary call, or 1, 2, ... for repeated draws of the same request.
#'   Above 0 it is part of the [gr_cache()] key, so N identical calls with
#'   draw indexes 1 to N are N cached replies rather than one reply N times,
#'   and a [gr_replay_client()] answers draw k with the k-th recorded reply to
#'   the request. A [gr_mock_client()] or [gr_backend_client()] handler finds
#'   it in `params$draw_index`, and the trace records it in the step's
#'   `params`; at 0 neither carries it, so an unsampled call is unchanged.
#'   Must be named in full, since it follows `...`.
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
#'   `$served_model`, `$response_id` and `$fingerprint` are what the provider
#'   said about its reply (`NA` where it said nothing; `$model` stays the model
#'   asked for), and `$attempts` is how many requests were sent for it,
#'   retries included, 0 for a reply from a cache or a recording.
#'   A request that would pass one of the run's limits (see [hr_governor()])
#'   is not sent: it comes back with `ok = FALSE`, `$refused = TRUE`, an
#'   `$error` naming the limit and the condition in `$refusal`, after a
#'   condition of class `hr_budget_refused` is signalled. It is not recorded
#'   as a step of the trace.
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
#'
#' # Draws of one request, each cached under its own key.
#' n <- 0
#' sampler <- gr_mock_client(function(m, p) { n <<- n + 1; paste("draw", n) })
#' sampler <- gr_cache_client(sampler, gr_cache(file.path(tempdir(), "harnessr-draws")))
#' vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")
#' vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")  # cached
gr_call <- function(client, messages, model = NULL, max_output = NULL,
                    temperature = NULL, schema = NULL, schema_name = "result",
                    trace = NULL, label = "call", ..., effort = NULL, draw_index = 0L) {
  # Checked here too, so the error names the function the user called.
  if (!inherits(client, "gr_client")) gr_abort("`client` must come from gr_client() or gr_mock_client().")
  # After `...`, so it is matched only by its full name: `...` is the request
  # body's own fields, and a field a gateway happens to call `eff` must still
  # go to the gateway.
  model_call(client, messages, model = model, max_output = max_output,
             temperature = temperature, schema = schema, schema_name = schema_name,
             trace = trace, label = label, extra = list(...), effort = check_effort(effort),
             draw_index = check_draw_index(draw_index))
}

#' A draw index as one non-negative integer, or a classed error.
#' @noRd
check_draw_index <- function(draw_index) {
  ok <- is.numeric(draw_index) && length(draw_index) == 1L && !is.na(draw_index) &&
    is.finite(draw_index) && draw_index >= 0 && draw_index == round(draw_index) &&
    draw_index <= .Machine$integer.max
  if (!ok) {
    gr_abort(paste0("`draw_index` must be one whole number, 0 for an ordinary call or 1, 2, ... ",
                    "for the draws of a sampled request."),
             class = "gr_bad_setting")
  }
  as.integer(draw_index)
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
                       effort = NULL, draw_index = 0L) {
  if (!inherits(client, "gr_client")) gr_abort("`client` must come from gr_client() or gr_mock_client().")
  messages <- normalise_messages(messages)
  model <- as_chr1(model %||% client$model)
  info <- gr_model_info(model)

  # Counted in the model's own encoding where the tokenizer has one (tiktoken).
  prompt_tokens <- sum(gr_count_tokens(vapply(messages, function(m) as_chr1(m$content), character(1)),
                                       model = model))
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
  # The cap as asked, for a replay key worked out for another model.
  asked_cap <- max_output
  max_output <- call_cap(max_output, info, prompt_tokens)

  if (max_output <= 0L) {
    res <- gr_result(FALSE, error = sprintf(
      paste0("Prompt is %d tokens but '%s' has a %d-token context window, leaving no room for a ",
             "reply. Segment more aggressively (lower `max_tokens` on the segmenter) or use a ",
             "larger-context model."),
      prompt_tokens, model, info$context_window), status = 0L, model = model,
      usage = usage_record(0L, 0L, "counted"), attempts = 0L)
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
  # Added only above 0, as the effort is only when there is one: an unsampled
  # call gives a handler and the trace exactly the params it always did.
  draw_index <- as_int1(draw_index, 0L)
  # A run whose requests are made deep inside a reader cannot pass the index
  # to each of them, so the run's trace can carry it instead (gr_arm() sets it
  # on the trace of each benchmark run). An index given to the call wins.
  if (draw_index == 0L) draw_index <- trace_draw_index(trace)
  if (draw_index > 0L) params$draw_index <- draw_index
  # Whose draw it is, when the trace says (hr_benchmark() names the arm), so
  # a replay hands each arm its own recorded replies. Kept out of `params`,
  # and out of the cache and replay keys.
  draw_scope <- if (draw_index > 0L) trace_draw_scope(trace)

  # One dispatch, one exit, one trace entry. The mock and HTTP paths each used
  # to `return()` after recording their own trace entry, so every feature that
  # had to sit between the request and the response -- caching, replay -- would
  # have had to be written twice and kept in step by hand.
  req <- list(messages = messages, model = model, max_output = max_output,
              temperature = temperature, schema = schema, schema_name = schema_name,
              info = info, params = params, label = label, extra = extra,
              accept = accept, effort_map = effort_map, draw_index = draw_index,
              draw_scope = draw_scope, asked_cap = asked_cap)
  # The replay key of this call, recorded on its step so a replay of the trace
  # looks it up by the same key (see replay_lookup()).
  rkey <- request_replay_key(req, model, params$effort)
  # What the request carries once every default is resolved, worked out from
  # the same function that builds it. `params` stays what the caller asked for
  # and a handler is given, which a replay reads; this is the record of what
  # went out, and is kept out of every key.
  sent <- client_sent_params(client, req)
  # The governor sees the request before the client does. What holds whoever
  # answers (the call count, the output ceiling, the allowed models) is
  # checked here; what only a paid request can pass (the spending limit, a
  # model with no price) is checked by the client's dispatch once a cache has
  # missed, through `admit`. A refused request is not sent and is no step.
  gate <- governor_request(client, req, sent)
  refusal <- governor_check(trace, gate, "call")
  if (is.null(refusal)) {
    req$admit <- function() governor_check(trace, gate, "send")
    started <- Sys.time()
    res <- client_dispatch(client, req)
    ended <- Sys.time()
  } else {
    res <- refused_result(refusal, model)
  }
  if (is_refused(res)) {
    governor_refuse(trace, res$refusal)
    return(res)
  }
  # A reply a replay found by the old key, or repeated, is recorded without
  # a replay key, so a replay of this trace is not exact where this one was
  # not (see replay_lookup()).
  if (isTRUE(res[["unkeyed", exact = TRUE]])) {
    rkey <- NA_character_
    res$unkeyed <- NULL
  }
  # A replay hands back the record of what the recorded call sent.
  if (!is.null(res[["params_sent", exact = TRUE]])) {
    sent <- res$params_sent
    res$params_sent <- NULL
  }
  # An ellmer chat is handed the effort only so that it can say it does not
  # send it (gr_ellmer_client()). Recorded as `effort`, the trace, its
  # `effort` column and the audit report said every request ran at an effort
  # none of them carried. So the step keeps it as the effort the call asked
  # for, under its own name, as does a replay of such a step. The handler's
  # params, the cache key and the replay key are left as they were.
  if (!is.null(params$effort) &&
      (!client_sends_effort(client) || isTRUE(res[["unsent_effort", exact = TRUE]]))) {
    params$unsent_effort <- params$effort
    params$effort <- NULL
    if (is.list(sent)) sent$effort <- NA_character_
  }
  trace_record(trace, label, messages, res, params,
               seconds = as.numeric(difftime(ended, started, units = "secs")),
               sent = sent, started = started, ended = ended, replay_key = rkey,
               draw_scope = draw_scope)
  res
}

#' What the governor is told about a prepared request: its model and label, the
#' most prompt tokens it can be billed for (see governor_input_tokens()), and
#' the output cap it goes out with. That is the cap the
#' request carries (for a reasoning model over HTTP the raised one), or for a
#' replay the cap an HTTP request would have carried. A mock makes no paid
#' request, so its model needs no price. A replay costs nothing unless its
#' recording was stopped by the spending limit, in which case each request
#' counts what it would cost here, so the replay is refused where the
#' recording was. An ellmer chat answers, and is billed, as the model it was
#' built with whatever the request names, so that is the model checked.
#' @noRd
governor_request <- function(client, req, sent) {
  cap <- if (is.list(sent)) as_num1(sent$max_output, NA_real_) else NA_real_
  if (is.na(cap)) {
    cap <- reasoning_output_cap(req$max_output, req$info, as_num1(req$params$prompt_tokens, 0))
  }
  prompt <- governor_input_tokens(client, req)
  model <- req$model
  if (inherits(client, "gr_ellmer_client")) {
    built <- as_chr1(client[["model", exact = TRUE]], "")
    if (nzchar(built)) model <- built
  }
  out <- list(model = model, label = req$label, input_tokens = prompt, output_tokens = cap,
              unpriced_ok = inherits(client, "gr_mock_client"))
  if (inherits(client, "gr_replay_client")) {
    worst <- if (isTRUE(client[[".replay_costs", exact = TRUE]])) {
      worst_case_usd(model, prompt, cap)
    } else 0
    out$worst_usd <- if (is.na(worst)) 0 else worst
  }
  out
}

#' The most prompt tokens a request can be billed for.
#'
#' The trace counts the text of the messages, but a provider bills for more:
#' a few tokens of framing per message and for the reply, the JSON schema a
#' structured call sends, and any extra body fields. The governor checked the
#' message count alone while the spend was charged on the provider's figure,
#' so a run whose replies reached their cap ended above its limit. So the
#' schema and the extra fields are counted as JSON, each message is given
#' `.gr_message_overhead` tokens and the reply `.gr_reply_overhead`, and the
#' sum is raised by `safety_margin`, the slack the context budget already
#' leaves for tokenizer error. It is a bound on what a tokenizer can count,
#' not a promise about what a provider reports.
#' @noRd
governor_input_tokens <- function(client, req) {
  counted <- as_num1(req$params$prompt_tokens, 0)
  json_tokens <- function(x) {
    if (is.null(x) || (is.list(x) && !length(x))) return(0)
    json <- jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
    sum(gr_count_tokens(as.character(json), model = req$model))
  }
  schema <- if (!is.null(req$schema)) list(name = req$schema_name, schema = req$schema)
  # Only an HTTP client puts the extra body fields on the request; a handler
  # is never given them.
  extra <- if (!inherits(client, c("gr_backend_client", "gr_mock_client", "gr_replay_client"))) {
    utils::modifyList(client$extra_body %||% list(), req$extra %||% list())
  }
  framing <- .gr_message_overhead * length(req$messages) + .gr_reply_overhead
  margin <- as_num1(gr_options("safety_margin"), 0.1)
  ceiling((counted + framing + json_tokens(schema) + json_tokens(extra)) * (1 + max(margin, 0)))
}

# Tokens a chat provider adds to each message for its role and delimiters, and
# to prime the reply. OpenAI documents 3 and 3 for its chat models; one more
# per message covers a `name` field.
.gr_message_overhead <- 4
.gr_reply_overhead <- 3

#' The output cap a call is made with: the one asked for, or the model's, held
#' to the model's limit and to what the context window leaves after the prompt.
#' Zero or less when the prompt leaves no room.
#' @noRd
call_cap <- function(max_output, info, prompt_tokens) {
  cap <- as.integer(clamp(max_output %||% info$max_output, 1, info$max_output))
  headroom <- info$context_window - prompt_tokens - 32L
  if (headroom < cap) cap <- as.integer(max(headroom, 0L))
  cap
}

#' The temperature a request carries: the one asked for or the session
#' default, and none for a model that does not take one.
#' @noRd
call_temperature <- function(temperature, info) {
  temperature <- temperature %||% gr_options("temperature")
  if (isTRUE(info$reasoning) || !isTRUE(info$supports_temperature)) NULL else temperature
}

#' The harnessr-replay-v2 key of a prepared request, for `model` at `effort`.
#'
#' The temperature is resolved under `model`'s profile, as a call that asked
#' for it would have been (replay_lookup() also tries the recording's other
#' models). `sent_effort = TRUE` is for an effort this session's registry would
#' not send but the recording may have: a model that was sent an effort was a
#' reasoning model there, and so was sent no temperature.
#'
#' The cap is the one the call asked for, before it is held to the model's
#' limit and context window. Those come from the model's profile, which can
#' differ between the session that recorded a run and the one replaying it
#' (a gateway model registered in one and not the other), and the model id is
#' already in the key.
#' @noRd
request_replay_key <- function(req, model, effort, sent_effort = FALSE) {
  info <- if (identical(model, req$model)) req$info
          else tryCatch(suppressWarnings(gr_model_info(model)), error = function(e) NULL)
  if (is.null(info)) return(NA_character_)
  temperature <- if (isTRUE(sent_effort)) NULL else call_temperature(req$temperature, info)
  replay_key(req$messages, model, effort, temperature = temperature, max_output = req$asked_cap,
             schema = req$schema, schema_name = req$schema_name)
}

#' Where a prepared request actually goes.
#'
#' An internal S3 generic over the client's class. `req` is the request
#' model_call() prepared: `messages`, `model`, `max_output`, `temperature`,
#' `schema`, `schema_name`, `info` (the model profile), `params` (what a
#' handler is given and the trace keeps), `label`, `extra` (top level body
#' fields), `accept` and `effort_map` (the effort setting before it was
#' resolved for this label).
#'
#' The methods are registered in NAMESPACE, as S3 methods should be, so the
#' generics dispatch the same way wherever they are called from. None of them
#' is exported.
#'
#' Order matters. A replay client never reaches the network at all, so it has
#' its own method. Every other client goes through the `gr_client` method,
#' which consults an attached cache before the request is issued and writes it
#' only after the request succeeds; client_send() then issues the request for
#' that client's class. A failure is a property of the moment, not of the
#' request, and caching one would make a transient blip permanent. `accept`,
#' when given, is the caller's test of a usable reply (see model_call()).
#' @rawNamespace S3method(client_dispatch, gr_replay_client)
#' @rawNamespace S3method(client_dispatch, gr_client)
#' @rawNamespace S3method(client_send, gr_client)
#' @rawNamespace S3method(client_send, gr_backend_client)
#' @rawNamespace S3method(client_send, gr_mock_client)
#' @rawNamespace S3method(client_sends_effort, gr_client)
#' @rawNamespace S3method(client_sends_effort, gr_ellmer_client)
#' @rawNamespace S3method(client_sent_params, gr_client)
#' @rawNamespace S3method(client_sent_params, gr_backend_client)
#' @rawNamespace S3method(client_sent_params, gr_mock_client)
#' @rawNamespace S3method(client_sent_params, gr_replay_client)
#' @noRd
client_dispatch <- function(client, req) UseMethod("client_dispatch")

#' @noRd
client_dispatch.gr_replay_client <- function(client, req) {
  refusal <- if (is.function(req$admit)) req$admit()
  if (!is.null(refusal)) return(refused_result(refusal, req$model))
  replay_lookup(client, req)
}

#' @noRd
client_dispatch.gr_client <- function(client, req) {
  # Resolved BEFORE the key, not after. `temperature` arrives NULL whenever the
  # caller did not name one, and build_request_body() then filled it from
  # gr_options("temperature") -- after cache_key() had already hashed the NULL.
  # So two runs that sent different temperatures to the API computed the same
  # key: a temperature sweep through one cache directory explored nothing and
  # reported the first sample's answer for every setting. The reasoning-model
  # drop moves here for the mirror-image reason -- the body does not carry a
  # temperature for those models, so the key must not vary with one.
  temperature <- call_temperature(req$temperature, req$info)
  req["temperature"] <- list(temperature)

  accept <- req$accept
  cache <- client$.cache
  key <- NULL
  usable <- function(r) is.null(accept) || isTRUE(tryCatch(accept(r$text), error = function(e) FALSE))
  if (inherits(cache, "gr_cache")) {
    draw <- as_int1(req$draw_index, 0L)
    key <- cache_key(client, req$messages, req$model, req$max_output, temperature,
                     req$schema, req$schema_name, req$extra, effort = req$params$effort,
                     draw_index = draw)
    # The key this request had before harnessr-cache-v3, for an entry written
    # then. Only for draw 0: there were no draws, so every old entry is one.
    # A function, so the second hash is paid only when the new key misses.
    legacy <- if (draw == 0L) function() {
      legacy_cache_key_v2(client, req$messages, req$model, req$max_output, temperature,
                          req$schema, req$schema_name, req$extra, effort = req$params$effort)
    }
    hit <- cache_get(cache, key, legacy)
    if (!is.null(hit) && !usable(hit)) {
      # Stored before the caller's test existed. Asked again, and written
      # below under the new key if the new reply passes.
      cache_unhit(cache, hit)
      hit <- NULL
    }
    if (!is.null(hit)) {
      attr(hit, "legacy_key") <- NULL
      # Entries are stored as built. One written before the truncation
      # spellings were unified can still say "incomplete" or "max_tokens".
      hit$finish_reason <- normalise_finish_reason(hit$finish_reason)
      # Nothing was sent for it this time.
      hit$attempts <- 0L
      return(hit)
    }
  }

  # Past the cache, so about to be sent: the spending limit and the unpriced
  # rule are checked now, and a request either refuses is not sent.
  refusal <- if (is.function(req$admit)) req$admit()
  if (!is.null(refusal)) return(refused_result(refusal, req$model))
  res <- client_send(client, req)

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

#' Issue one request that the cache did not answer.
#'
#' An internal S3 generic. `req` is the request client_dispatch() was given,
#' with `temperature` already resolved. The `gr_client` method is the HTTP
#' transport; the `gr_backend_client` method serves every client whose answer
#' comes from an R function (gr_mock_client(), gr_backend_client() and so
#' gr_ellmer_client()).
#' @noRd
client_send <- function(client, req) UseMethod("client_send")

#' @noRd
client_send.gr_client <- function(client, req) {
  out <- http_call(client, request_url(client), request_body(client, req))
  # The model asked for, which pricing and the trace key on. The one the
  # provider says answered is kept apart, in `served_model`.
  out$model <- req$model
  out$usage <- settle_usage(out$usage, req$params$prompt_tokens, out$text)
  out
}

#' The body an HTTP client sends for a prepared request.
#'
#' One function for the request and for the record of it (client_sent_params()),
#' so the two cannot drift apart.
#' @noRd
request_body <- function(client, req) {
  info <- req$info
  build_request_body(client, req$messages, req$model,
                     reasoning_output_cap(req$max_output, info, req$params$prompt_tokens),
                     req$temperature, req$schema, req$schema_name, info, req$extra,
                     effort = req$params$effort)
}

#' @noRd
request_url <- function(client) {
  paste0(client$base_url,
         if (identical(client$api, "responses")) "/responses" else "/chat/completions")
}

#' What a request carries once every default is resolved.
#'
#' An internal S3 generic. The trace used to record the caller's values: a
#' temperature left NULL that the request filled from gr_options(), and the cap
#' the caller asked for where a reasoning model was sent a larger one. This is
#' read from the request itself: for the HTTP client from the body
#' request_body() builds, for a closure client from the params its handler is
#' given. A schema and the extra body fields are kept as hashes of their JSON,
#' since the trace already holds enough to rebuild neither and both can be
#' large. `NA` marks a field the request does not carry.
#' @noRd
client_sent_params <- function(client, req) UseMethod("client_sent_params")

#' @noRd
client_sent_params.gr_client <- function(client, req) {
  body <- request_body(client, req)
  responses <- identical(client$api, "responses")
  schema <- if (responses) body[["text", exact = TRUE]][["format", exact = TRUE]]
            else body[["response_format", exact = TRUE]][["json_schema", exact = TRUE]]
  effort <- if (responses) body[["reasoning", exact = TRUE]][["effort", exact = TRUE]]
            else body[["reasoning_effort", exact = TRUE]]
  cap <- body[["max_output_tokens", exact = TRUE]] %||%
    body[["max_completion_tokens", exact = TRUE]] %||% body[["max_tokens", exact = TRUE]]
  extra <- utils::modifyList(client$extra_body %||% list(), req$extra %||% list())
  sent_params(model = body[["model", exact = TRUE]], api = client$api,
              base_url = client$base_url, max_output = cap,
              temperature = body[["temperature", exact = TRUE]], effort = effort,
              schema_name = if (is.list(schema)) schema[["name", exact = TRUE]],
              schema = if (is.list(schema)) schema[["schema", exact = TRUE]], extra = extra)
}

#' @noRd
client_sent_params.gr_backend_client <- function(client, req) {
  # The handler is given `params` and the messages, nothing else: no extra
  # body fields reach it, and a temperature left NULL reaches it as NULL.
  p <- req$params
  sent_params(model = p$model, api = client$api, base_url = client$base_url,
              max_output = p$max_output, temperature = p$temperature, effort = p$effort,
              schema_name = if (!is.null(p$schema)) p$schema_name, schema = p$schema,
              extra = NULL)
}

#' @noRd
client_sent_params.gr_mock_client <- client_sent_params.gr_backend_client

#' @noRd
client_sent_params.gr_replay_client <- function(client, req) NULL

#' The record client_sent_params() returns, with a fixed set of fields.
#' @noRd
sent_params <- function(model, api, base_url, max_output, temperature, effort, schema_name,
                        schema, extra) {
  list(model = as_chr1(model, NA_character_),
       api = as_chr1(api, NA_character_),
       base_url = as_chr1(base_url, NA_character_),
       max_output = as_int1(max_output, NA_integer_),
       temperature = as_num1(temperature, NA_real_),
       effort = as_chr1(effort, NA_character_),
       schema_name = as_chr1(schema_name, NA_character_),
       schema_hash = json_sha256(schema),
       extra_body_hash = json_sha256(extra))
}

#' SHA-256 of a value's JSON, or NA for nothing.
#'
#' The JSON is written as the request body is (auto_unbox, every digit), so
#' the hash of a schema recorded here is the hash of the schema the body held.
#' @noRd
json_sha256 <- function(x) {
  if (is.null(x) || (is.list(x) && !length(x))) return(NA_character_)
  json <- jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  digest::digest(charToRaw(enc2utf8(as.character(json))), algo = "sha256", serialize = FALSE)
}

#' Run a closure client's handler and normalise whatever it returned.
#'
#' One method for the mock and the backend, deliberately: a backend is a
#' stranger's function, and every caller downstream relies on invariants it has
#' never heard of. Sharing `handler_result()` is what stops the two paths from
#' drifting. The mock's method is this same function, and an ellmer client is a
#' backend client, so it gets it by inheritance.
#' @noRd
client_send.gr_backend_client <- function(client, req) {
  params <- req$params
  out <- tryCatch(client$handler(req$messages, params), error = function(e) e)
  res <- handler_result(out, req$model, as_int1(params$prompt_tokens, 0L))
  if (is.na(res$attempts)) res$attempts <- 1L
  client$.log$calls <- c(client$.log$calls, list(list(messages = req$messages, params = params,
                                                      result = res, label = req$label)))
  res
}

#' @noRd
client_send.gr_mock_client <- client_send.gr_backend_client

#' Whether a client puts the call's reasoning effort on the request it sends.
#'
#' An internal S3 generic. An ellmer chat is handed the effort only so that it
#' can say it does not send it; model_call() then traces it as `unsent_effort`.
#' @noRd
client_sends_effort <- function(client) UseMethod("client_sends_effort")

#' @noRd
client_sends_effort.gr_client <- function(client) TRUE

#' @noRd
client_sends_effort.gr_ellmer_client <- function(client) FALSE

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

#' Token usage the trace can trust.
#'
#' Unknown is not zero. When the provider's figure for a call is missing or not
#' a number, count locally instead: the prompt was measured before it was sent
#' and the reply is in hand. This package's tokenizer is deliberately biased to
#' over-count, so the substitute errs towards charging too much rather than too
#' little -- the same rule `ellmer_usage()` applies, now applied to the HTTP
#' path and to a handler-built result that left `usage` out. A figure the
#' provider did report is kept as reported, including a genuine zero.
#'
#' The record says which it is (see usage_record()), and keeps the reasoning
#' and cached-input counts the provider reported. Both are parts of `output`
#' and `input`, not additions to them.
#' @noRd
settle_usage <- function(usage, prompt_tokens, text) {
  num <- function(v) {
    v <- suppressWarnings(as.numeric(v))
    if (length(v) != 1L || is.na(v) || !is.finite(v) || v < 0) NA_integer_ else as.integer(v)
  }
  get <- function(nm) if (is.list(usage)) usage[[nm, exact = TRUE]] else NULL
  inp <- num(get("input"))
  out <- num(get("output"))
  given <- as_chr1(get("provenance"), NA_character_)
  if (!given %in% .gr_usage_provenance) given <- "reported"
  prov <- if (is.na(inp) || is.na(out)) weaker_provenance(given, local_provenance()) else given
  usage_record(input  = if (is.na(inp)) as_int1(prompt_tokens, 0L) else inp,
               output = if (is.na(out)) sum(gr_count_tokens(as_chr1(text))) else out,
               provenance = prov,
               reasoning = num(get("reasoning")), cached_input = num(get("cached_input")))
}

#' Where a usage figure came from, from most to least exact: the provider
#' reported it, it was counted locally with the model's own tokenizer, or it
#' was estimated by a heuristic one.
#' @noRd
.gr_usage_provenance <- c("reported", "counted", "estimated")

#' @noRd
weaker_provenance <- function(a, b) {
  .gr_usage_provenance[max(match(c(a, b), .gr_usage_provenance), na.rm = TRUE)]
}

#' What a count made here is: "counted" with tiktoken, which encodes as the
#' OpenAI models do, and "estimated" with any other tokenizer.
#' @noRd
local_provenance <- function() {
  if (identical(gr_options("tokenizer"), "tiktoken")) "counted" else "estimated"
}

#' One usage record, its fields always in this order.
#'
#' `reasoning` and `cached_input` are present only when the provider reported
#' them, so a reply without them keeps the shape it always had. `provenance`
#' is one of .gr_usage_provenance, or NA for a record written before it was
#' kept (an old cache entry or recording).
#' @noRd
usage_record <- function(input, output, provenance = NA_character_,
                         reasoning = NA_integer_, cached_input = NA_integer_) {
  u <- list(input = input, output = output)
  if (!is.na(as_int1(reasoning, NA_integer_))) u$reasoning <- as_int1(reasoning)
  if (!is.na(as_int1(cached_input, NA_integer_))) u$cached_input <- as_int1(cached_input)
  u$provenance <- as_chr1(provenance, NA_character_)
  u
}

#' Turn whatever a handler returned into a lawful `gr_result`.
#' @noRd
handler_result <- function(out, model, prompt_tokens) {
  if (inherits(out, "gr_result")) {
    # Re-normalise: a hand-built gr_result from a user handler can violate the
    # character(1) contract that every caller downstream relies on.
    txt <- repair_utf8(as_chr1(out$text))
    # gr_result()'s default usage is 0 in and 0 out with no provenance. On a
    # reply that has text, that is a handler that said nothing about tokens,
    # not a provider that reported none, so it is counted here instead.
    usage <- out$usage
    if (is.list(usage) && is.null(usage$provenance) && nzchar(txt) &&
        identical(as_int1(usage$input, NA_integer_), 0L) &&
        identical(as_int1(usage$output, NA_integer_), 0L)) {
      usage <- NULL
    }
    return(gr_result(out$ok, text = txt, error = out$error,
                     status = out$status %||% NA_integer_,
                     usage = settle_usage(usage, prompt_tokens, txt),
                     # A result built with gr_result() and no `model` carries
                     # NA, not NULL, so `%||%` kept it: the trace then priced
                     # the call as model "unknown" and added nothing to
                     # spent_usd, however many tokens it reported.
                     model = if (nzchar(as_chr1(out$model, ""))) as_chr1(out$model) else model,
                     finish_reason = out$finish_reason %||% NA_character_,
                     retryable = isTRUE(out$retryable), raw = out$raw,
                     cached = isTRUE(out$cached),
                     served_model = out[["served_model", exact = TRUE]] %||% NA_character_,
                     response_id = out[["response_id", exact = TRUE]] %||% NA_character_,
                     fingerprint = out[["fingerprint", exact = TRUE]] %||% NA_character_,
                     attempts = out[["attempts", exact = TRUE]] %||% NA_integer_))
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
                     usage = usage_record(as_int1(prompt_tokens, 0L), 0L, local_provenance())))
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
                usage = usage_record(prompt_tokens, 0L, local_provenance()))
    } else {
      gr_result(TRUE, text = txt, model = model,
                usage = usage_record(prompt_tokens, sum(gr_count_tokens(txt)),
                                     local_provenance()))
    }
  }
}

#' Call a model and parse a JSON-schema response into a list
#'
#' A reply is usable only if it parses to an object that meets `schema` (see
#' json_reply()); one that does not comes back with `ok = FALSE` and the
#' reason in `problem`, and is not cached. `own_scalars` is for a caller that
#' reads each scalar value itself (see schema_problem()).
#' @noRd
gr_call_json <- function(client, messages, schema, schema_name = "result",
                         allow_empty = FALSE, own_scalars = FALSE, ...) {
  # The same test decides what is cached, so a reply this function would call
  # a failure is never stored as a success (see model_call()).
  accept <- function(txt) json_reply(txt, schema, allow_empty, own_scalars)$ok
  # gr_call()'s own arguments, so `...` is matched exactly as it was.
  send <- function(client, messages, model = NULL, max_output = NULL, temperature = NULL,
                   schema = NULL, schema_name = "result", trace = NULL, label = "call", ...,
                   effort = NULL, draw_index = 0L) {
    model_call(client, messages, model = model, max_output = max_output,
               temperature = temperature, schema = schema, schema_name = schema_name,
               trace = trace, label = label, extra = list(...), accept = accept,
               effort = effort, draw_index = check_draw_index(draw_index))
  }
  res <- send(client, messages, schema = schema, schema_name = schema_name, ...)
  if (!res$ok) return(list(ok = FALSE, value = NULL, result = res, problem = NULL))
  out <- json_reply(res$text, schema, allow_empty, own_scalars)
  list(ok = out$ok, value = out$value, result = res, problem = out$problem)
}
