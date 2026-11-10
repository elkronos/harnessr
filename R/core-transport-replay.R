# core-transport-replay.R -- re-run a recorded run without an API key.
#
# WHY THIS FILE EXISTS
# `gr_trace` already records every prompt, every response and every token count
# for a run. That record was write-only: you could read it, print it and
# serialise it, but you could not *run* it. So a published result was something
# a reader had to take on trust and pay to reproduce, and a bug report was a
# description of a run rather than the run itself.
#
# A trace is a complete transcript of the only non-deterministic part of the
# pipeline. Everything else -- extraction, cleaning, segmentation, ranking,
# merging, budgeting -- is a pure function of its input. So a trace plus the
# source document is enough to reproduce a run exactly, with no key and no
# spend, provided the model calls are answered from the transcript instead of
# the network. That is all this file does.
#
# WHAT REPLAY IS NOT
# It is not a mock. A mock invents answers; a replay client returns the answer
# the model actually gave, matched to the prompt that actually produced it. And
# it is not a cache: a cache makes a *future* run cheaper, while a replay makes
# a *past* run checkable by someone who was not there.

#' Save a trace to a file
#'
#' Writes the trace as JSON, in the form [as_json()] produces. The file is
#' everything [gr_replay_client()] needs, so this is how a run leaves the
#' session it happened in.
#'
#' @param trace A `gr_trace`.
#' @param path Destination file.
#' @return `path`, invisibly.
#' @seealso [gr_replay_client()], [as_json()], [gr_trace()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#'
#' f <- tempfile(fileext = ".json")
#' gr_trace_save(ans$trace, f)
#' file.exists(f)
gr_trace_save <- function(trace, path) {
  stopifnot(inherits(trace, "gr_trace"))
  path <- as_chr1(path)
  if (!nzchar(path)) gr_abort("`path` must be a file name.")
  dir <- dirname(path)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(as.character(as_json(trace, pretty = TRUE)), path, useBytes = TRUE)
  invisible(path)
}

#' A client that answers from a recorded run
#'
#' Replays the responses in a trace instead of calling a model. Give it the
#' trace from a run and the same document and question, and you get that run
#' back (same answers, same evidence, same merge decisions) with no API key,
#' no network and no spend.
#'
#' This is what makes a published result checkable. Ship the trace next to the
#' paper and a reader can reproduce the run rather than take it on trust. It is
#' also the cheapest possible bug report: a trace file is a re-runnable
#' recording of exactly what went wrong.
#'
#' @param source A `gr_trace`; a path to a file written by [gr_trace_save()];
#'   the JSON text [as_json()] writes for a trace or for an answer (whose trace
#'   is used); or an already-parsed list in that shape. Parse a file yourself
#'   with `jsonlite::fromJSON(path, simplifyVector = FALSE)`: the default
#'   simplification turns the steps into a data frame, which loses what a
#'   replay needs, and is refused with a message that says so.
#' @param on_exhausted What a call does when the recording holds fewer replies
#'   to its request than the replay has asked for. `"error"` (the default)
#'   raises an `hr_replay_exhausted` error: the replay is making more calls
#'   than the run it reproduces did. `"flag"` returns the last recorded reply
#'   again and counts it in `$stats()$repeats`, which is what every replay did
#'   before this argument existed.
#' @param strict If `TRUE` (default), a prompt with no recorded response raises
#'   a `gr_replay_miss` error. That is usually what you want: a miss means the
#'   replay has diverged from the recording, and continuing would produce a
#'   result that looks like the original but is not. With `FALSE` a miss returns
#'   a failed [gr_result] instead, so a partially recorded trace still runs.
#' @return An object of class `gr_replay_client`, usable anywhere a
#'   [gr_client()] is. It also carries `$stats()` and `$missed()`.
#'
#' @section Matching:
#' A response is matched on the exact prompt messages plus the model id the
#' call asked for, the reasoning effort it was sent with when it had one
#' (see `effort` in [gr_read_spec()]), the temperature it was made with once
#' the session default was filled in (none for a model that takes none), the
#' output cap it asked for, and its JSON schema. These make up the key
#' `harnessr-replay-v2`, which each step of a trace records as `replay_key`.
#' So a replay under another effort, temperature, cap or schema misses rather
#' than passing for the recording. A replay under the same effort
#' matches even where this session's registry does not list a model as a
#' reasoning model and the recording session's did (a gateway model
#' registered with [gr_register_model()] there and not here), and a call
#' through an ellmer chat, which sends no effort, is matched on the one it
#' asked for. The model id can differ from the
#' model the trace records as
#' answering: a [gr_ellmer_client()] answers with its chat's model whatever the
#' recipe asked for, and its runs replay all the same.
#'
#' A step recorded before `replay_key` existed (readgpt 0.6.0, and harnessr
#' before this key) is matched on the old key, `readgpt-replay-v1`: the
#' messages, the model and the effort only. A call that finds nothing under the
#' new key is looked up there, and a reply found that way is used, with an
#' `hr_legacy_key` warning once per recording in a session, since the replay
#' cannot then show that the temperature, cap and schema were the recorded
#' ones. `$stats()$legacy_hits` counts these replies.
#'
#' The replay client's own model, which a read that names none asks for, is
#' the model the recorded reads asked for. One trace can hold reads through
#' clients built for different models, and a recording made by readgpt 0.5.0
#' asked for `gr_options("model")` on a read and for the client's model
#' everywhere else; a call that asks for the replay client's model and finds
#' nothing under it is answered from the one other such model that holds the
#' same prompt. A model the recorded settings named (`model`, `skim_model`,
#' `summary_model`) is never used that way, so a replay that leaves one out
#' misses.
#'
#' @section Repeated calls and draws:
#' When a run issued the same request more than once (which happens at a
#' temperature above zero, and in readers that revisit a chunk), the recorded
#' responses are returned in the order they were produced. A call with a
#' `draw_index` above 0 (see [gr_call()]) is answered with the reply recorded
#' for that draw; in a recording that holds no draw indexes, draw k is the
#' k-th reply recorded for the request. In a recording of [hr_benchmark()]
#' each draw also names the arm that made it, and an arm's call is answered
#' only with that arm's replies, so replaying some of the arms, or the arms
#' in another order, gives each arm what it got. A call past the end of what
#' was recorded, or for a draw that was never recorded, raises
#' `hr_replay_exhausted` unless `on_exhausted = "flag"`.
#'
#' @section Embeddings:
#' A trace records each request to an embeddings endpoint (a step labelled
#' `"embed.request"`, counted in `calls` and priced like any other request),
#' but not the vectors that came back, so a replay has nothing to answer those
#' requests with. A run that embedded (the `semantic` segmenter, the
#' `retrieve` and `iterative` readers, `rerank` when word overlap finds
#' nothing, and so the `"needle"` recipe) therefore replays only when the
#' recording used a **deterministic** embedder and the replay uses the
#' **same** one: the vectors are then computed again, exactly. Both
#' conditions, because replaying an API-embedded run with a deterministic
#' local embedder would compute vectors the original never saw while looking
#' exact. Anything else, including a run recorded with the default `"api"`
#' embedder (or a [gr_mock_client()]'s embed handler), warns with class
#' `gr_replay_no_embeddings` and falls back to hashed lexical vectors. Those
#' place semantic cuts and rank chunks differently, so such a replay usually
#' sends prompts the recording does not hold: a strict replay stops with
#' `gr_replay_miss`, whose message names this cause, and a non-strict one gets
#' failed calls for them and does not give the recorded answer. Record a run
#' you intend to publish or replay with `gr_options(embedder = "lexical")`, or
#' with your own embedder registered as `deterministic = TRUE`.
#'
#' @section Limits:
#' A saved trace says whether a limit cut the run short (`budget_stop`,
#' `stop_reason`), and a replay of such a run stops where it stopped when it
#' runs under the limits it was recorded with. Replayed calls count against
#' `max_calls` as they did when recorded. When the spending limit stopped the
#' recorded run, each replayed call also counts what it cost when recorded
#' against `max_cost_usd` (in the trace's `replayed_usd`; nothing is spent);
#' for any other run it counts nothing, so a replay of an expensive run is not
#' stopped by the replaying session's limit. A replay under a higher limit, or
#' none, that asks for a call past the recorded stop gets a `gr_replay_miss`
#' saying so, and one under a lower limit stops sooner, marked partial as the
#' run would have been.
#'
#' @section The recipe "auto" chose:
#' A recording of [answer_document()] with `recipe = "auto"` holds the recipe
#' the choice picked for each document and question, and a replay of the same
#' document and question repeats that choice rather than making it again. What
#' the choice rests on (the token count, the registered models, the client's
#' model) can differ between the session that recorded a run and the one
#' replaying it, and a different choice would send prompts the recording does
#' not have.
#'
#' @section What does not replay:
#' Traces do not store the JSON schema a call requested, only a hash of it in
#' the step's key. In a recording made before `replay_key` existed, two calls
#' that differ only by schema, temperature or output cap share a reply.
#'
#' @seealso [gr_trace_save()], [gr_cache()] for making future runs cheap,
#'   [gr_mock_client()] for invented answers rather than recorded ones
#' @export
#' @examples
#' # A run.
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#'
#' # The same run, from the recording, with no client and no key.
#' rp <- gr_replay_client(ans$trace)
#' again <- answer_document(gr_example(), "What was revenue?", "fast", client = rp)
#' identical(again$answer, ans$answer)
#'
#' rp$stats()
#'
#' # Through a file, which is how a run reaches someone else.
#' f <- tempfile(fileext = ".json")
#' gr_trace_save(ans$trace, f)
#' answer_document(gr_example(), "What was revenue?", "fast",
#'                 client = gr_replay_client(f))$answer
gr_replay_client <- function(source, strict = TRUE, on_exhausted = c("error", "flag")) {
  on_exhausted <- match.arg(on_exhausted)
  # Read once: a file is parsed, and a trace listed, a single time for all the
  # lookups below.
  source <- replay_read(source)
  steps <- replay_steps(source)
  embed_source <- replay_embed_source(source)
  auto_choices <- replay_auto_choices(source)
  if (!length(steps)) {
    gr_abort(paste0("That trace has no recorded model calls, so there is nothing to replay. ",
                    "A run that made no calls (every reader failed, or the budget stopped it ",
                    "before the first request) produces an empty recording."),
             class = "gr_replay_empty")
  }

  idx <- new.env(parent = emptyenv())
  idx$v2 <- list()        # harnessr-replay-v2 key -> recorded responses, in order
  idx$full <- list()      # readgpt-replay-v1 key  -> the same, for steps without a v2 key
  idx$prompt <- list()    # prompt only     -> models seen, for diagnostics
  idx$cursor <- list()
  idx$hits <- 0L
  idx$repeats <- 0L
  idx$legacy_hits <- 0L
  idx$misses <- list()
  idx$auto_used <- rep(FALSE, nrow(auto_choices))

  idx$effort <- list()    # prompt + model  -> efforts seen, for diagnostics

  for (st in steps) {
    # The diagnostic tables are keyed with the v1 function because it can
    # leave out the model or the effort; they are never matched to a step.
    kp <- legacy_replay_key_v1(st$prompt, NULL)
    km <- legacy_replay_key_v1(st$prompt, st$model)
    if (!is.na(st$key)) {
      idx$v2[[st$key]] <- c(idx$v2[[st$key]], list(st))
    } else {
      kf <- legacy_replay_key_v1(st$prompt, st$model, st$effort)
      idx$full[[kf]] <- c(idx$full[[kf]], list(st))
    }
    idx$prompt[[kp]] <- unique(c(idx$prompt[[kp]], as_chr1(st$model, "?")))
    idx$effort[[km]] <- unique(c(idx$effort[[km]], as_chr1(st$effort, "<none>")))
  }

  # The model a replayed read asks for when it names none is this client's, so
  # it has to be the one the recorded reads asked for. Their pre-flight notes
  # say which that was. The model most calls asked for is only a guess at it,
  # and a wrong one when a cheaper skim_model or summary_model made most of
  # them: the replay then asked for that model on the answer call, found
  # nothing recorded under it and stopped with gr_replay_miss. A recording
  # without the notes falls back to the guess.
  #
  # One client's model cannot be every model a recording needs when its reads
  # followed clients built for different models, or when it was made by 0.5.0,
  # whose reads asked for gr_options("model") and whose segmenters, extraction
  # and claims asked for the client's model. The others are kept apart, and
  # answer only a call that asked for this client's model and found nothing
  # under it. See replay_default_models().
  models <- vapply(steps, function(s) as_chr1(s$model, NA_character_), character(1))
  models <- models[!is.na(models)]
  defaults <- replay_default_models(source, models)
  default_model <- if (!is.na(defaults$read)) defaults$read
                   else if (length(models)) replay_most_frequent(models) else "replay"

  structure(list(
    model = default_model, api = "replay", base_url = "replay://",
    embedding_model = "replay-embed", max_retries = 0L, retry_pause_base = 0,
    timeout = 1, extra_body = list(),
    strict = isTRUE(strict), on_exhausted = on_exhausted, .idx = idx,
    .alt_models = defaults$alts,
    # Derived from the recording, not from this object: two replays of the same
    # trace are the same thing and should share a store, while replays of
    # DIFFERENT recordings must not -- without this a corpus store served one
    # recording's answers while replaying another, which is exactly the failure
    # the client identity was introduced to prevent.
    .client_id = paste0("replay-", gr_hash(lapply(steps, function(s)
      c(s$answered_model, s$response, unlist(lapply(s$prompt, function(m) m$content)))))),
    # Which embedder the RECORDING used, so a replay can tell an embedding it
    # can reproduce from one it cannot. See gr_embed().
    embed_source = embed_source,
    # Which limit cut the recorded run short, or NA, so a miss past the stop
    # can say why it missed. A trace saved before this was recorded says
    # nothing, and its misses keep the general message.
    .recorded_stop = if (isTRUE(source$budget_stop)) as_chr1(source$stop_reason, "limit")
                     else NA_character_,
    # Whether a replayed call counts what it cost when recorded against
    # max_cost_usd: only when the spending limit stopped the recorded run, so
    # the replay stops at the same call. A run the limit never stopped replays
    # whatever limit the replaying session has, as it always did; counted
    # there, a $12 recording made under a raised limit stopped at the default
    # $5 when someone else replayed it.
    .replay_costs = isTRUE(source$budget_stop) &&
      identical(as_chr1(source$stop_reason, ""), "cost"),
    # The recipe answer_document()'s "auto" chose in the recording for a
    # document and question, found by their key. Replayed rather than chosen
    # again: what the choice rests on (the token count, the registered models,
    # the client) can differ between the session that recorded a run and the
    # one replaying it. Several recorded choices for one key are handed out in
    # the order they were made.
    auto_choice = function(key = NULL) {
      hit <- which(auto_choices$key == as_chr1(key, "") & !idx$auto_used)
      if (!length(hit)) return(NULL)
      idx$auto_used[hit[1]] <- TRUE
      auto_choices$chose[hit[1]]
    },
    n_recorded = length(steps),
    stats = function() data.frame(
      recorded = length(steps), distinct = length(idx$v2) + length(idx$full),
      hits = idx$hits, repeats = idx$repeats, misses = length(idx$misses),
      legacy_hits = idx$legacy_hits,
      stringsAsFactors = FALSE
    ),
    missed = function() idx$misses
  ), class = c("gr_replay_client", "gr_client"))
}

#' @export
print.gr_replay_client <- function(x, ...) {
  s <- x$stats()
  cat(sprintf("<gr_replay_client> %d recorded call(s), %d distinct prompt(s), model=%s%s\n",
              s$recorded, s$distinct, x$model, if (x$strict) "" else " [non-strict]"))
  cat(sprintf("  %d hit(s), %d repeat(s), %d miss(es)%s\n", s$hits, s$repeats, s$misses,
              if (s$legacy_hits > 0L) sprintf(", %d under the old key", s$legacy_hits) else ""))
  invisible(x)
}

# --- internals -------------------------------------------------------------

#' A recording as a plain list, in the shape trace_as_list() gives, from any
#' source gr_replay_client() takes. Raises when it cannot be one, saying why.
#'
#' Each misread used to end in a message about something else. A trace parsed
#' with jsonlite's default simplification has its steps as a data frame, and
#' walking that walked its columns: the replay found no calls and said the run
#' had made none. The JSON text of a trace or an answer was taken for a file
#' name, and reported as "No such trace file" followed by the whole JSON.
#' @noRd
replay_read <- function(source) {
  obj <- source
  if (inherits(source, "gr_trace")) {
    obj <- trace_as_list(source)
  } else if (is.character(source) && length(source) == 1L && !is.na(source)) {
    text <- inherits(source, "json") ||
      (!file.exists(source) && grepl("^\\s*\\{", source, useBytes = TRUE))
    if (!text && !file.exists(source)) {
      gr_abort(sprintf("No such trace file: %s", source), class = "gr_file_not_found")
    }
    obj <- tryCatch(if (text) jsonlite::parse_json(as.character(source), simplifyVector = FALSE)
                    else jsonlite::fromJSON(source, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (is.null(obj)) {
      gr_abort(if (text) "Could not parse that JSON text as a trace. Write it with as_json() or gr_trace_save()."
               else sprintf("Could not parse '%s' as a trace. Write it with gr_trace_save().", source),
               class = "gr_replay_unreadable")
    }
  }
  if (!is.list(obj)) {
    gr_abort(paste0("`source` must be a gr_trace, a path written by gr_trace_save(), the JSON ",
                    "text of a trace, or a parsed trace."),
             class = "gr_replay_unreadable")
  }
  # An answer, or its JSON: its trace is the recording.
  if (is.null(obj[["steps", exact = TRUE]]) && !is.null(obj[["trace", exact = TRUE]])) {
    inner <- obj[["trace", exact = TRUE]]
    if (inherits(inner, "gr_trace")) inner <- trace_as_list(inner)
    if (is.list(inner) && !is.null(inner[["steps", exact = TRUE]])) obj <- inner
  }
  steps <- obj[["steps", exact = TRUE]]
  if (is.data.frame(steps)) {
    gr_abort(paste0("This trace's steps were read as a data frame, which is what ",
                    "jsonlite::fromJSON() makes of them with its default simplifyVector = TRUE, ",
                    "and that loses the shape a replay needs. Pass the file's path to ",
                    "gr_replay_client(), or read it with ",
                    "jsonlite::fromJSON(path, simplifyVector = FALSE)."),
             class = "gr_replay_unreadable")
  }
  if (is.null(steps) || !is.list(steps)) {
    gr_abort(paste0("`source` holds no list of `steps`, so it is not a trace. Pass a gr_trace, ",
                    "a file written by gr_trace_save(), or the JSON text as_json() writes."),
             class = "gr_replay_unreadable")
  }
  obj
}

#' Model steps from a trace, a parsed trace, or a file.
#' @noRd
replay_steps <- function(source) {
  obj <- replay_read(source)
  steps <- obj$steps
  out <- list()
  for (st in steps) {
    if (!is.list(st)) next
    if (identical(as_chr1(st$kind, ""), "local")) next   # segmentation, ranking, merges
    prompt <- replay_prompt(st$prompt)
    if (!length(prompt)) next
    tok <- st$tokens %||% list()
    params <- if (is.list(st$params)) st$params else list()
    requested <- as_chr1(params[["model", exact = TRUE]], NA_character_)
    answered <- as_chr1(st$model, NA_character_)
    out[[length(out) + 1L]] <- list(
      prompt = prompt,
      # The model the call ASKED for, which is what a replayed gr_call() looks
      # up. The step's own `model` is the one that answered, and a client that
      # reports the provider's model (gr_ellmer_client() always does; so can a
      # backend handler) records a different name there: keyed on that, no
      # prompt of such a run was ever found, and every replay stopped with
      # gr_replay_miss on its first call. A trace without `params` (an older
      # or hand-built one) falls back to the answering model.
      model = if (!is.na(requested)) requested else answered,
      # Kept for what the replayed result reports, so pricing and display name
      # the model the recording says answered.
      answered_model = if (!is.na(answered)) answered else requested,
      ok = isTRUE(st$ok),
      response = as_chr1(st$response, ""),
      error = if (isTRUE(st$ok)) NULL else as_chr1(st$error, "recorded failure"),
      tokens = list(input = as_int1(tok$input, 0L), output = as_int1(tok$output, 0L)),
      # The rest of the usage record and what the provider said about the
      # reply, so a replayed step reports what the recorded one did. None of
      # it is part of the key a call is looked up by.
      usage = usage_record(as_int1(tok$input, 0L), as_int1(tok$output, 0L),
                           if (as_chr1(tok$provenance, "") %in% .gr_usage_provenance)
                             tok$provenance else NA_character_,
                           reasoning = as_int1(tok$reasoning, NA_integer_),
                           cached_input = as_int1(tok$cached_input, NA_integer_)),
      served_model = as_chr1(st$served_model, NA_character_),
      response_id = as_chr1(st$response_id, NA_character_),
      fingerprint = as_chr1(st$fingerprint, NA_character_),
      params_sent = replay_sent_params(st$params_sent),
      # Carried through, because a caller acts on it: gr_synthesise(coherence =
      # TRUE) rejects a revision that stopped for "length". Dropping it here
      # made every replayed call look like a clean stop, so the replay kept a
      # truncated revision the live run had thrown away, published a different
      # document, and reported 0 misses -- certifying itself as an exact
      # reproduction of a run it had not reproduced.
      finish_reason = as_chr1(st$finish_reason, NA_character_),
      label = as_chr1(st$label, "call"),
      # The harnessr-replay-v2 key the call recorded, or NA for a step made
      # before it existed, which is looked up by readgpt-replay-v1 instead.
      key = replay_step_key(st$replay_key),
      # Which draw of a sampled request the call was; 0 for an ordinary call.
      draw = max(as_int1(params[["draw_index", exact = TRUE]], 0L), 0L),
      # Whose draw it was (an hr_benchmark() arm), or NA. See replay_lookup().
      scope = as_chr1(st$draw_scope, NA_character_),
      # The reasoning effort the request was sent with, or NULL for none, which
      # is every step recorded without the setting. Part of the old key a
      # replayed call is looked up by: see legacy_replay_key_v1(). And whether
      # it was only asked for, by a call through an ellmer chat, which its
      # replay records again.
      effort = replay_step_effort(params),
      unsent_effort = replay_step_effort(params, unsent = TRUE),
      # What the call counted against max_cost_usd when it was recorded, which
      # the replayed call counts again (see trace_record()).
      budget_usd = replay_step_budget(st, if (!is.na(answered)) answered else requested)
    )
  }
  out
}

#' A recorded step's params_sent as client_sent_params() made it, or NULL.
#'
#' A trace read back from JSON has lost its NA fields, which were written as
#' null; they are put back so a replayed step records the same fields.
#' @noRd
replay_sent_params <- function(x) {
  if (!is.list(x)) return(NULL)
  out <- sent_params(model = x$model, api = x$api, base_url = x$base_url,
                     max_output = x$max_output, temperature = x$temperature,
                     effort = x$effort, schema_name = x$schema_name, schema = NULL,
                     extra = NULL)
  out$schema_hash <- as_chr1(x$schema_hash, NA_character_)
  out$extra_body_hash <- as_chr1(x$extra_body_hash, NA_character_)
  out
}

#' What a recorded call counted against the spending limit.
#'
#' The step says, in a trace written since it began to. An older one is priced
#' from its tokens at the model that answered, as the recording session priced
#' it, and a call it answered from a cache or a replay counted nothing.
#' @noRd
replay_step_budget <- function(st, model) {
  if (!is.null(st$budget_usd)) return(max(as_num1(st$budget_usd, 0), 0))
  if (isTRUE(st$cached)) return(0)
  tok <- if (is.list(st$tokens)) st$tokens else list()
  usd <- tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(
    as_chr1(model, "unknown"), as_int1(tok$input, 0L), as_int1(tok$output, 0L)))),
    error = function(e) NA_real_)
  if (length(usd) == 1L && is.finite(usd) && usd > 0) usd else 0
}

#' A recording as a plain list, or NULL when it cannot be read. For the
#' lookups beside replay_steps() that find a note in the recording: those make
#' do without it, and replay_read() is what reports a source it cannot use.
#' @noRd
replay_source_list <- function(source) {
  tryCatch(replay_read(source), error = function(e) NULL)
}

#' The model a replay client stands for, and the others a recording needs.
#'
#' gr_read() notes on every pre-flight the model the read asked for
#' (`detail$model`). A read whose settings name a model asks for that model
#' again when it is replayed, so only the reads that followed their client say
#' what the replay client's own model has to be: `read` is that model, and NA
#' when no note says (a recording with no read), so the caller falls back to
#' the model most calls asked for.
#'
#' `alts` are the other models calls that followed a client asked for, which
#' replay_lookup() tries, one prompt at a time, for a call that asked for the
#' replay client's model and found nothing under it:
#'
#' - Reads through clients built for different models (one trace passed to
#'   both): `read` is the noted model most calls asked for, and the other
#'   noted models are `alts`.
#' - A recording made by 0.5.0, whose notes do not name the model. Its reads
#'   asked for gr_options("model") whatever the client, and its segmenters,
#'   extraction and claims asked for the client's own model; its replay asked
#'   for gr_options("model") on every read and for the model most calls asked
#'   for everywhere else, so its recordings of a read with a cheaper
#'   skim_model or summary_model replayed. `read` is gr_options("model") when
#'   the recording holds calls under it, as that version assumed, or else the
#'   only model left, or the one most of them asked for; `alts` is the model
#'   most of the rest asked for.
#'
#' A model any note names as a setting (`model`, `skim_model`,
#' `summary_model`) is never in `alts`, nor a 0.5.0 recording's `read`: the
#' calls that followed a client did not ask for it, and a replay that leaves
#' out a recorded skim_model has to miss, as it did in 0.5.0, rather than be
#' answered from the calls that setting made.
#' @noRd
replay_default_models <- function(source, models) {
  none <- list(read = NA_character_, alts = character(0))
  obj <- replay_source_list(source)
  if (is.null(obj) || !length(models)) return(none)
  notes <- Filter(function(st) is.list(st) && identical(as_chr1(st$label, ""), "preflight"),
                  obj$steps %||% list())
  if (!length(notes)) return(none)
  details <- lapply(notes, function(st) if (is.list(st$detail)) st$detail else list())
  settings <- lapply(details, function(d) if (is.list(d$settings)) d$settings else list())
  followed <- vapply(settings, function(s) is.null(s[["model", exact = TRUE]]), logical(1))
  if (!any(followed)) return(none)
  named <- unlist(lapply(settings, function(s) vapply(
    c("model", "skim_model", "summary_model"),
    function(k) as_chr1(s[[k, exact = TRUE]], NA_character_), character(1))), use.names = FALSE)
  named <- unique(named[!is.na(named) & nzchar(named)])
  noted <- vapply(details[followed], function(d) as_chr1(d[["model", exact = TRUE]], NA_character_),
                  character(1))
  noted <- unique(noted[!is.na(noted) & nzchar(noted)])

  if (length(noted)) {
    if (length(noted) == 1L) return(list(read = noted, alts = character(0)))
    under <- models[models %in% noted]
    read <- if (length(under)) replay_most_frequent(under) else noted[1]
    return(list(read = read, alts = setdiff(noted, c(read, named))))
  }
  # Every note that followed a client is silent about its model: 0.5.0.
  if (any(vapply(details, function(d) !is.null(d[["model", exact = TRUE]]), logical(1)))) {
    return(none)
  }
  pool <- models[!models %in% named]
  if (!length(pool)) return(none)
  opt <- as_chr1(gr_options("model"), "")
  cand <- unique(pool)
  read <- if (opt %in% cand) opt else if (length(cand) == 1L) cand else replay_most_frequent(pool)
  rest <- pool[pool != read]
  list(read = read, alts = if (length(rest)) replay_most_frequent(rest) else character(0))
}

#' The model most of `models` name. Ties go to the first in sorted order.
#' @noRd
replay_most_frequent <- function(models) {
  names(sort(table(models), decreasing = TRUE))[1]
}

#' Which embedder produced the vectors in the recorded run, if any.
#'
#' The transcript holds each embeddings request but not the vectors it
#' returned -- but `gr_embed()` writes a local note saying which embedder it
#' used, and that is enough. A replay can reproduce a run's ranking only when
#' it uses the SAME embedder and that embedder is deterministic. Without this the check was
#' "is the current embedder deterministic", which is not the same question: a
#' run recorded through an API and replayed with a deterministic local embedder
#' would have claimed to be exact while ranking chunks by different vectors.
#'
#' `NA` when the run embedded nothing (no ranking to reproduce) or when the
#' recording used more than one embedder.
#' @noRd
replay_embed_source <- function(source) {
  obj <- replay_source_list(source)
  if (is.null(obj)) return(NA_character_)
  srcs <- unlist(lapply(obj$steps %||% list(), function(st) {
    if (!is.list(st) || !identical(as_chr1(st$label, ""), "embed")) return(NULL)
    as_chr1((st$detail %||% list())$source, NA_character_)
  }), use.names = FALSE)
  srcs <- unique(srcs[!is.na(srcs)])
  if (length(srcs) == 1L) srcs else NA_character_
}

#' The choices "auto" made in a recording: the key of the document and question
#' each was made for, and the recipe it picked, in the order they were made.
#' @noRd
replay_auto_choices <- function(source) {
  none <- data.frame(key = character(0), chose = character(0), stringsAsFactors = FALSE)
  obj <- replay_source_list(source)
  if (is.null(obj)) return(none)
  rows <- lapply(obj$steps %||% list(), function(st) {
    if (!is.list(st) || !identical(as_chr1(st$label, ""), "auto_recipe")) return(NULL)
    d <- st$detail %||% list()
    data.frame(key = as_chr1(d$key, ""), chose = as_chr1(d$chose, NA_character_),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, c(list(none), rows))
  out[!is.na(out$chose) & out$chose %in% c("fast", "thorough") & nzchar(out$key), , drop = FALSE]
}

#' Normalise a recorded prompt to a plain list of role/content pairs.
#' @noRd
replay_prompt <- function(p) {
  if (is.null(p) || !is.list(p) || !length(p)) return(list())
  # A single unwrapped message, as `$` on a one-element list can produce.
  if (!is.null(names(p)) && "content" %in% names(p)) p <- list(p)
  out <- lapply(p, function(m) {
    if (is.character(m)) return(list(role = "user", content = as_chr1(m)))
    if (!is.list(m)) return(NULL)
    list(role = as_chr1(m$role, "user"), content = as_chr1(m$content, ""))
  })
  Filter(Negate(is.null), out)
}

#' The harnessr-replay-v2 key of a call.
#'
#' Everything about the call that changes the reply and that a recording can
#' be checked against: the messages, the model asked for, the reasoning effort
#' sent, the temperature once the default is filled in (call_temperature()),
#' the output cap asked for (NULL for the model's own; see
#' request_replay_key() for why not the clamped one), and the JSON schema with
#' its name. The readgpt-replay-v1 key (legacy_replay_key_v1()) had the first three only, so
#' a replay at another temperature, cap or schema was answered with the
#' recorded replies and reported 0 misses. The draw index is not in it: the
#' draws of one request share a key and are told apart by the index each step
#' records (see replay_lookup()).
#'
#' key_text() is what makes a trace replayable from a FILE: jsonlite does not
#' necessarily hand back a string labelled the way the original was. See the
#' note on key_text() in core-transport-cache.R.
#' @noRd
replay_key <- function(messages, model, effort = NULL, temperature = NULL, max_output = NULL,
                       schema = NULL, schema_name = "result") {
  hr_hash(c("harnessr-replay-v2",
            as_chr1(model, "?"),
            if (!is.null(effort)) paste0("effort:", as_chr1(effort)),
            paste0("temperature:",
                   if (is.null(temperature)) "<null>" else format(temperature, digits = 15L)),
            paste0("max_output:",
                   if (is.null(max_output)) "<model>"
                   else format(as.numeric(max_output), digits = 15L)),
            if (is.null(schema)) "schema:<none>"
            else paste0("schema:", as_chr1(schema_name, "result"), ":", hr_hash(schema)),
            key_text(unlist(lapply(messages, function(m) c(as_chr1(m$role), as_chr1(m$content))),
                            use.names = FALSE))))
}

#' A step's recorded replay_key, when it is one; NA otherwise.
#'
#' Anything else in the field (a hand-edited trace, a damaged file) is treated
#' as a step with no key, which the old key still finds.
#' @noRd
replay_step_key <- function(x) {
  k <- as_chr1(x, NA_character_)
  if (!is.na(k) && grepl("^[0-9a-f]{64}$", k)) k else NA_character_
}

#' The effort a recorded step's request carried, or NULL.
#'
#' NULL for a step with none, and for anything a hand-edited or damaged trace
#' holds there that is not one string: a recording that cannot say what effort
#' it used is a recording made without one. A step through an ellmer chat
#' keeps the effort its call asked for as `unsent_effort` (see model_call()),
#' and is looked up by it all the same, since a replay of the run asks for it
#' again; `unsent = TRUE` says whether that is where it came from.
#' @noRd
replay_step_effort <- function(params, unsent = FALSE) {
  one <- function(nm) {
    e <- as_chr1(if (is.list(params)) params[[nm, exact = TRUE]], NA_character_)
    if (is.na(e) || !has_visible(e)) NULL else e
  }
  sent <- one("effort")
  if (unsent) return(is.null(sent) && !is.null(one("unsent_effort")))
  sent %||% one("unsent_effort")
}

#' Answer one call from the recording.
#'
#' `req` is the request model_call() prepared (see client_dispatch()). Its
#' `label` and `effort_map` are the call's own label and `effort` setting.
#' `params$effort` is that setting resolved for this call and sent only to a
#' model this session's registry says reasons, and the recording was made
#' under the registry of the session that made it. A gateway model registered
#' there as a reasoning model, and not here, was recorded at the effort and is
#' asked for without it, so every call missed, with a message saying the call
#' had asked for no effort. So when the effort this session would send finds
#' nothing, the effort the call asked for is tried, and each of the
#' recording's other models is looked up at the effort it would be sent, not
#' the one resolved for this client's model.
#'
#' Every one of those lookups is made under the harnessr-replay-v2 key first,
#' and only when none finds anything, under the readgpt-replay-v1 key of steps
#' recorded before the new key existed.
#' @noRd
replay_lookup <- function(client, req) {
  idx <- client$.idx
  messages <- req$messages
  model <- req$model
  params <- req$params
  label <- req$label %||% "call"
  draw <- as_int1(req$draw_index, 0L)
  effort <- params[["effort", exact = TRUE]]
  effort_map <- req$effort_map %||% effort
  asked <- effort_for(effort_map, label)
  # The key a lookup of model `m` at effort `e` uses under one scheme, and the
  # table it is looked up in.
  find <- function(v2) {
    tab <- if (v2) idx$v2 else idx$full
    if (!length(tab)) return(NULL)
    held <- function(m, e, sent_effort = FALSE) {
      k <- if (v2) request_replay_key(req, m, e, sent_effort)
           else legacy_replay_key_v1(messages, m, e)
      if (!is.na(k) && !is.null(tab[[k]])) k
    }
    kf <- held(model, effort)
    if (is.null(kf) && is.null(effort) && !is.null(asked)) kf <- held(model, asked, TRUE)
    # The recording's other models that calls following a client asked for
    # (see replay_default_models()), for a call that asked for this client's
    # model. Only when exactly one holds the prompt: two would be a guess
    # between two recorded answers, and that is reported as the miss it is.
    alts <- as.character(client[[".alt_models", exact = TRUE]] %||% character(0))
    if (is.null(kf) && length(alts) &&
        identical(as_chr1(model, ""), as_chr1(client$model, ""))) {
      ka <- unlist(lapply(alts, function(a) {
        # Only looked up, never called, so a model this session does not know
        # is not warned about, nor refused under unknown_model_action = "error".
        info <- tryCatch(suppressWarnings(gr_model_info(a)), error = function(e) NULL)
        ea <- effort_to_send(effort_map, label, info)
        held(a, ea) %||% (if (is.null(ea) && !is.null(asked)) held(a, asked, TRUE))
      }))
      if (length(ka) == 1L) kf <- ka[[1]]
    }
    kf
  }
  kf <- find(TRUE)
  legacy <- is.null(kf)
  if (legacy) kf <- find(FALSE)
  recorded <- if (!is.null(kf)) (if (legacy) idx$full else idx$v2)[[kf]]

  if (is.null(recorded)) {
    other <- idx$prompt[[legacy_replay_key_v1(messages, NULL)]]
    # The same prompt for the same model at another effort: said first, since
    # "replay the run with that model" would name the model it already asked.
    efforts <- if (is.list(idx$effort)) idx$effort[[legacy_replay_key_v1(messages, model)]] else NULL
    ask <- as_chr1(effort %||% asked, "<none>")
    detail <- if (!is.null(efforts) && ask %in% efforts) {
      # Recorded for this model at this effort, so the v2 key missed on the
      # temperature, the output cap or the schema.
      replay_settings_miss(idx, req, ask)
    } else if (!is.null(efforts)) {
      say <- function(e) if (identical(e, "<none>")) "no effort" else sprintf("effort '%s'", e)
      # What the call asked for, which this session's registry may not send.
      sprintf(paste0(" The same prompt IS recorded for this model at reasoning %s, and this call ",
                     "asked for %s; replay the run with the `effort` it was recorded with."),
              paste(vapply(efforts, say, character(1)), collapse = " or "),
              say(ask))
    } else if (!is.null(other)) {
      sprintf(" The same prompt IS recorded under model %s; replay the run with that model.",
              paste(sprintf("'%s'", other), collapse = " or "))
    } else {
      paste0(sprintf(paste0(" The recording holds %d distinct prompt(s); this is not one of them, ",
                            "so the replay has diverged from the run that produced it"),
                     length(idx$v2) + length(idx$full)),
             replay_miss_causes(client))
    }
    idx$misses <- c(idx$misses, list(list(model = as_chr1(model, "?"), messages = messages)))
    msg <- paste0("No recorded response for this prompt.", detail)
    if (isTRUE(client$strict)) gr_abort(msg, class = "gr_replay_miss")
    return(gr_result(FALSE, error = msg, status = 0L, model = model, cached = TRUE))
  }

  # The replies recorded for this draw. A step recorded with the new key
  # carries its own draw index. One recorded before had none, and its draws
  # are numbered in the order they were recorded, which is what a replay of
  # repeated calls has always handed back.
  cand <- if (!legacy) Filter(function(s) identical(s$draw, draw), recorded)
          else if (draw == 0L) recorded
          else if (draw <= length(recorded)) recorded[draw]
          else list()
  # Two benchmark arms that send the same request at the same draw each have
  # a reply recorded under it. Handed out in call order, a replay of one arm
  # alone, or of the arms in another order, gave an arm the other's replies.
  # So a request that names its scope (the arm) takes only the replies
  # recorded for that scope, and keeps its own cursor. A recording made
  # without scopes is read as before.
  scope <- as_chr1(req[["draw_scope", exact = TRUE]], NA_character_)
  scoped <- !legacy && draw > 0L && !is.na(scope) &&
    any(vapply(cand, function(s) !is.na(as_chr1(s$scope, NA_character_)), logical(1)))
  if (scoped) {
    cand <- Filter(function(s) identical(as_chr1(s$scope, NA_character_), scope), cand)
  }
  ck <- paste(if (legacy) "v1" else "v2", kf, draw, if (scoped) scope)
  pos <- (idx$cursor[[ck]] %||% 0L) + 1L
  if (pos > length(cand)) {
    if (!identical(client$on_exhausted, "flag")) {
      have <- if (legacy) length(recorded) else length(unique(vapply(recorded, function(s) s$draw, 1L)))
      gr_abort(paste0(
        if (!length(cand)) {
          sprintf(paste0("The recording holds no reply for draw %d of this request%s; it holds %d ",
                         "draw(s) of it."), draw,
                  if (scoped) sprintf(" made by '%s'", scope) else "", have)
        } else {
          sprintf("The recording holds %d repl%s to %s, and this is call %d for it.",
                  length(cand), if (length(cand) == 1L) "y" else "ies",
                  if (draw > 0L) sprintf("draw %d of this request", draw) else "this request", pos)
        },
        " The replay is making more calls than the recorded run did, so it is not reproducing ",
        "that run. Pass on_exhausted = \"flag\" to gr_replay_client() to repeat the last ",
        "recorded reply instead, counted in $stats()$repeats."),
        class = "hr_replay_exhausted")
    }
    # Flagged: the last reply repeats, and `$stats()` says the replay was not
    # exact.
    st <- if (length(cand)) cand[[length(cand)]] else recorded[[length(recorded)]]
    idx$repeats <- idx$repeats + 1L
    repeated <- TRUE
  } else {
    idx$cursor[[ck]] <- pos
    st <- cand[[pos]]
    repeated <- FALSE
  }
  idx$hits <- idx$hits + 1L
  if (legacy) {
    idx$legacy_hits <- idx$legacy_hits + 1L
    legacy_key_warn("replay", as_chr1(client$.client_id, "replay"))
  }

  res <- gr_result(
    ok = st$ok, text = st$response, error = st$error, status = NA_integer_,
    usage = st$usage %||% list(input = st$tokens$input, output = st$tokens$output),
    model = as_chr1(st$answered_model, model),
    # From the recording. Hard-coded NA here made every replayed call look like
    # a clean stop, including the ones the live run rejected for being cut off.
    finish_reason = as_chr1(st$finish_reason, NA_character_),
    cached = TRUE,
    served_model = st$served_model %||% NA_character_,
    response_id = st$response_id %||% NA_character_,
    fingerprint = st$fingerprint %||% NA_character_,
    attempts = 0L
  )
  # What the recorded call sent; model_call() records it in place of a record
  # of its own, since a replay sends nothing.
  if (is.list(st$params_sent)) res$params_sent <- st$params_sent
  # What the call cost when it was recorded, for a recording the spending
  # limit stopped. Nothing is spent, but the trace counts it against
  # max_cost_usd, so a replay stops where the recorded run did. Counted as
  # nothing, it never reached the limit that stopped the run, asked for the
  # call after the stop, and missed.
  if (isTRUE(client[[".replay_costs", exact = TRUE]])) res$replay_usd <- as_num1(st$budget_usd, 0)
  # A recorded call that asked for an effort it did not send (an ellmer chat's)
  # is traced the same way when replayed (see model_call()).
  if (isTRUE(st$unsent_effort)) res$unsent_effort <- TRUE
  # A reply found by the old key was matched on the messages, model and effort
  # only, and a repeated one is not the reply recorded for this call. Neither
  # is given a harnessr-replay-v2 key in the replay's own trace (see
  # model_call()), so a replay of that trace still goes through the old key,
  # or still runs out of replies, instead of counting as exact.
  if (legacy || repeated) res$unkeyed <- TRUE
  res
}

#' The detail of a gr_replay_miss for a prompt recorded for this model at the
#' effort the call asked for: the temperature, output cap or schema differ.
#'
#' Names what the first such recorded step asked for next to what this call
#' asks for, and which of the three differ. The step's params_sent holds the
#' cap after it was held to the model's limit, while the key holds the cap
#' the call asked for, so that one is found by trying the likely values
#' against the step's key. A schema is compared by the hash of its body as
#' well as its name. A step with neither a key nor a params_sent is only said
#' to differ.
#' @noRd
replay_settings_miss <- function(idx, req, ask) {
  km <- legacy_replay_key_v1(req$messages, req$model)
  steps <- Filter(function(st) {
    identical(legacy_replay_key_v1(st$prompt, st$model), km) &&
      identical(as_chr1(st$effort, "<none>"), ask)
  }, c(unlist(unname(idx$v2), recursive = FALSE), unlist(unname(idx$full), recursive = FALSE)))
  intro <- paste0(" The same prompt IS recorded for this model at the effort this call asked ",
                 "for, but with another temperature, output cap or JSON schema.")
  advice <- " Replay the run with the settings it was recorded with."
  if (!length(steps)) return(paste0(intro, advice))
  st <- steps[[1]]
  sent <- st[["params_sent", exact = TRUE]]
  num <- function(x) if (is.null(x) || !length(x) || is.na(x)) NULL else as.numeric(x)

  # This call, as its key was made.
  temp_now <- num(call_temperature(req$temperature, req$info))
  cap_now <- num(req$asked_cap)
  name_now <- if (!is.null(req$schema)) as_chr1(req$schema_name, "result") else NA_character_
  hash_now <- json_sha256(req$schema)

  # The recorded call, from params_sent and, where it says more, its key.
  temp_rec <- if (is.list(sent)) num(sent$temperature)
  cap_sent <- if (is.list(sent)) num(sent$max_output)
  name_rec <- if (is.list(sent)) as_chr1(sent$schema_name, NA_character_) else NA_character_
  hash_rec <- if (is.list(sent)) as_chr1(sent$schema_hash, NA_character_) else NA_character_
  schema_same <- if (is.list(sent)) identical(name_rec, name_now) && identical(hash_rec, hash_now)
  cap_rec <- NULL
  cap_known <- FALSE
  if (!is.na(st$key) && (isTRUE(schema_same) || (is.list(sent) && is.na(hash_rec)))) {
    sc <- if (isTRUE(schema_same)) req$schema
    for (e in unique(list(st$effort, NULL))) for (t in unique(list(temp_now, temp_rec, NULL)))
      for (cap in unique(list(cap_now, cap_sent, NULL))) {
        if (cap_known) next
        k <- replay_key(st$prompt, st$model, e, temperature = t, max_output = cap,
                        schema = sc, schema_name = if (!is.null(sc)) name_now else "result")
        if (identical(k, st$key)) {
          temp_rec <- t
          cap_rec <- cap
          cap_known <- TRUE
        }
      }
  }
  if (!is.list(sent) && !cap_known) return(paste0(intro, advice))

  fmt_temp <- function(t) sprintf("temperature %s", if (is.null(t)) "none" else format(t))
  fmt_cap <- function(cap) if (is.null(cap)) "no output cap" else sprintf("output cap %s", format(cap))
  fmt_schema <- function(name, other_body = FALSE) {
    if (is.na(name)) "no schema"
    else sprintf("schema '%s'%s", name, if (other_body) " with another body" else "")
  }
  rec_cap <- if (cap_known) fmt_cap(cap_rec)
             else if (is.null(cap_sent)) "an output cap it did not record"
             else sprintf("an output cap it sent as %s once held to the model's limit", format(cap_sent))
  rec <- sprintf("%s, %s and %s", fmt_temp(temp_rec), rec_cap,
                 if (is.list(sent)) fmt_schema(name_rec) else "the schema this call has")
  now <- sprintf("%s, %s and %s", fmt_temp(temp_now), fmt_cap(cap_now),
                 fmt_schema(name_now, identical(name_rec, name_now) && !identical(hash_rec, hash_now)))

  temp_diff <- !identical(temp_rec, temp_now)
  schema_diff <- is.list(sent) && !isTRUE(schema_same)
  cap_diff <- if (cap_known) !identical(cap_rec, cap_now) else !temp_diff && !schema_diff
  causes <- c(if (temp_diff) "the temperature", if (cap_diff) "the output cap asked for",
              if (schema_diff) "the JSON schema")
  paste0(intro, sprintf(" The recorded call asked for %s; this call asks for %s.", rec, now),
         if (length(causes)) sprintf(" They differ in %s.", paste(causes, collapse = " and ")),
         advice)
}

#' Why a prompt the replay asked for may be missing from the recording, for the
#' gr_replay_miss message: the two causes a replay can see for itself, or the
#' usual suspects when neither applies.
#' @noRd
replay_miss_causes <- function(client) {
  idx <- client$.idx
  why <- character(0)
  if (is.environment(idx) && isTRUE(idx$embed_degraded)) {
    why <- c(why, paste0(
      "this replay could not reproduce the recording's embeddings (see the ",
      "gr_replay_no_embeddings warning), so its semantic cuts or chunk ranking can differ from ",
      "the recording's and send prompts the recording does not hold. A run that embeds replays ",
      "exactly only when it was recorded, and is replayed, with the same deterministic embedder, ",
      "such as gr_options(embedder = 'lexical')"))
  }
  stop <- as_chr1(client[[".recorded_stop", exact = TRUE]], NA_character_)
  if (!is.na(stop)) {
    what <- switch(stop, calls = "call cap (max_calls)", cost = "spending limit (max_cost_usd)",
                   "limits")
    why <- c(why, sprintf(paste0(
      "the recorded run was cut short by its %s after %d recorded call(s), so a replay under a ",
      "higher limit, or none, asks for calls the recording never made. Replay it under the ",
      "limits it was recorded with"), what, as_int1(client$n_recorded, 0L)))
  }
  if (!length(why)) return(" (a different document, question, recipe or segmenter).")
  paste0(": ", paste(why, collapse = "; and "), ".")
}
