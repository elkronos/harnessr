# core-ledger-core.R -- one run, one trace.
#
# WHY THIS FILE EXISTS
# The Shiny app called `answer_question()` twice per submission: once for the
# answer, once with `return_json = TRUE` for the "chain of thought" tab. That
# doubled every user's API bill, and at any temperature above 0 the displayed
# reasoning was not the reasoning behind the displayed answer -- two independent
# generations shown as if one explained the other.
#
# Tracing is now a side-channel on a single run. `answer_document()` always
# produces both the answer and its trace; `return_json` merely chooses which to
# hand back. There is no path that re-runs the pipeline to get a trace.

#' Create a run trace
#'
#' @param run_id Optional identifier; generated when omitted.
#' @param meta Named list of run-level metadata.
#' @param system,owner,run_by,purpose,approved_by Who the run is for and who
#'   ran it: the system it belongs to, the person or team accountable for that
#'   system, the person who ran it, what it was for, and who approved it. Each
#'   is one string. One left `NULL` is taken from `gr_options("actor")`, and is
#'   `NA` when that does not name it either.
#' @param governor An [hr_governor()] holding the limits every request recorded
#'   into this trace is checked against before it is sent, or `NULL` (the
#'   default) to read them from [gr_options()] at each check.
#' @return A `gr_trace`. It is an environment, so it accumulates by reference:
#'   pass the same trace to several calls and they all record into it. Fields:
#'   `run_id`, `started`, `meta`, `actor`, `config`, `steps`, `calls`,
#'   `cached`, `tokens_in`, `tokens_out`, `embed_tokens`, `errors`,
#'   `budget_stop`, `stop_reason`, `spent_usd`, `replayed_usd`, `refusals`,
#'   `governor`.
#'
#'   `actor` holds the five fields above. `config` is a snapshot of the
#'   options in force when the trace was made ([gr_options()], with the values
#'   of `api_headers` left out, since they can hold credentials) and the R
#'   version, so a saved trace says what it ran under. [as_json()] writes
#'   `started` in UTC, as ISO 8601 with a trailing `Z`.
#'   `cached` counts the calls answered from a [gr_cache()] or a
#'   [gr_replay_client()] rather than the network, so `calls - cached` is what
#'   the run paid for. `calls` includes requests to an embeddings endpoint,
#'   recorded as steps labelled `"embed.request"`. Their tokens are counted in
#'   `embed_tokens`, not in `tokens_in`, so `tokens_in` and `tokens_out` stay
#'   the size of the model calls' prompts and replies.
#'
#'   `errors` has one entry per request that failed: its `step`, `label` and
#'   `error`. A failure the run recovered from without losing any input also
#'   carries `recovered = TRUE`: the document was read in full, and
#'   [gr_read_many()] does not count it as failed. Only some fallbacks mark the
#'   answer partial. An embeddings request replaced by [gr_embed()]'s lexical
#'   fallback does when the vectors ranked the chunks a reader sent (the
#'   `retrieve`, `rerank` and `iterative` readers). The same fallback while
#'   [gr_segment()] made semantic cuts, and a proposition batch kept as
#'   written, leave the answer unmarked and say so in its `$warnings`. A
#'   contextual header that could not be written leaves no mark on the answer
#'   at all, and this entry is the record of it.
#'
#'   `budget_stop` is `TRUE` once a limit stopped the run, and `stop_reason`
#'   says which: `"calls"` for `max_calls`, `"cost"` for `max_cost_usd`,
#'   `"tokens"` for `max_tokens_total`, and `"output"`, `"model"` or
#'   `"unpriced"` for the other limits of [hr_governor()] (see [gr_options()]).
#'   `refusals` has one entry per request the governor did not send: its
#'   `label`, `model`, the `limit` it would have passed, its worst-case cost
#'   `worst_usd`, the run's `calls` and `spent_usd` at that moment, and the
#'   `message`. A refused request is not a call and has no step. `spent_usd`
#'   is what the calls so far cost. A call to a model with no registered price
#'   (sent under `allow_unpriced = TRUE`) adds nothing to it, so
#'   [gr_trace_cost()] is the full account. `replayed_usd` is what the calls a
#'   [gr_replay_client()] answered cost when they were recorded, counted when
#'   the spending limit stopped the recorded run: nothing was paid for them,
#'   but `max_cost_usd` is checked against `spent_usd + replayed_usd`, so the
#'   replay stops at the same call. A call answered from a [gr_cache()] adds to neither, so a
#'   re-run through a warm cache under the same limit reads further than the
#'   run that filled it.
#'   [as_json()] and [gr_trace_save()] write `budget_stop`, `stop_reason`,
#'   `spent_usd` and `replayed_usd`, so a saved run says whether it was cut
#'   short, and `refusals` and `governor` when there are any.
#'
#'   `as.data.frame()` on a trace returns one row per request; see below.
#'
#' @section Steps:
#' Each request is one entry in `steps`. Besides its label, prompt, reply and
#' the model it asked for (`model`), a step records:
#' \describe{
#'   \item{`params`}{What the call asked for: the parameters a
#'     [gr_mock_client()] or [gr_backend_client()] handler is given, which is
#'     also what a [gr_replay_client()] looks a call up by.}
#'   \item{`params_sent`}{The request as it went out, every default resolved:
#'     `model`, `api`, `base_url`, `max_output` (for a reasoning model, the
#'     larger cap its request is sent with; see [gr_call()]), `temperature`
#'     (`NA` when none was sent), `effort`, `schema_name`, and SHA-256 hashes
#'     of the JSON schema (`schema_hash`) and of the extra body fields the
#'     client and the call added (`extra_body_hash`). For a [gr_client()] it
#'     is read from the request body; for a handler, from the parameters the
#'     handler was given, which carry no extra body fields. A call answered
#'     from a [gr_cache()] records what would have been sent, and one a replay
#'     answered records what the recorded call sent.}
#'   \item{`tokens`}{`input` and `output`, plus `reasoning` and
#'     `cached_input` when the provider reported them (they are parts of
#'     `output` and `input`, not additions), and `provenance`: `"reported"`
#'     when the provider gave the counts, `"counted"` when they were counted
#'     here with the `"tiktoken"` tokenizer, `"estimated"` when they were
#'     estimated with another one, and `NA` for a reply cached or recorded
#'     before provenance was kept.}
#'   \item{`served_model`, `response_id`, `fingerprint`}{The model the
#'     provider said answered, its response id and its system fingerprint,
#'     where it returned them, else `NA`. None of them is part of a cache or
#'     replay key.}
#'   \item{`attempts`}{How many requests were sent for this one, retries
#'     included: 0 when a cache or a recording answered it.}
#'   \item{`started_utc`, `ended_utc`}{When the request started and ended,
#'     ISO 8601 in UTC with a trailing `Z`.}
#' }
#'
#' @section One row per request:
#' `as.data.frame(trace)` has one row for each request the run made, in the
#' order they were made, and none for local steps such as segmentation:
#' \describe{
#'   \item{`step`}{The step's number in `trace$steps`, where the full record is.}
#'   \item{`document`}{The document the request was about, when the run
#'     recorded one: the file name, web address or `"<inline text>"`.}
#'   \item{`recipe`}{The recipe the request belonged to, when recorded.}
#'   \item{`stage`}{What the request was for, such as `"map.answer"` or
#'     `"reduce"`.}
#'   \item{`model`, `ok`, `cached`}{The model, whether a usable reply came
#'     back, and whether it came from a [gr_cache()] or a [gr_replay_client()].}
#'   \item{`tokens_in`, `tokens_out`}{The size of the prompt and the reply.}
#'   \item{`usd`}{What the request cost, 0 when it came from a cache or failed
#'     without sending any tokens. `NA` when the model has no registered price,
#'     as in [gr_trace_cost()], whose total the column adds up to.}
#'   \item{`seconds`}{How long the request took, retries included. `NA` for a
#'     trace written by a version of readgpt that did not time requests.}
#'   \item{`error`}{The error, or `NA`.}
#'   \item{`prompt`, `reply`}{The messages sent, each as `"[role] text"`, and
#'     the text that came back.}
#'   \item{`effort`}{The reasoning effort the request was sent with, `NA` for
#'     one sent none. Present only when some request in the trace carried one
#'     (see `effort` in [gr_read_spec()]).}
#'   \item{`tokens_reasoning`, `tokens_cached_in`, `served_model`}{The
#'     reasoning and cached input tokens the provider reported and the model
#'     it said answered, `NA` where it did not. Each is present only when some
#'     request in the trace has it.}
#' }
#' A request's `usd` prices its cached input tokens at the model's cached
#' input rate when [gr_register_model()] gave it one, and at the input rate
#' otherwise.
#' @param x A `gr_trace`.
#' @param row.names Optional row names for the result.
#' @param optional,... Ignored; part of the [as.data.frame()] generic.
#' @seealso [gr_trace_summary()], [as_json()], [gr_answer], [gr_cache()]
#' @export
#' @examples
#' tr <- gr_trace(meta = list(purpose = "demo"))
#' cl <- gr_mock_client(function(m, p) "an answer")
#' ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
#' invisible(gr_read(ch, "What was revenue?", cl, "map_reduce", trace = tr))
#' print(tr)
#'
#' # One row per request, with what each cost and how long it took.
#' reqs <- as.data.frame(tr)
#' reqs[, c("step", "stage", "tokens_in", "tokens_out", "usd", "seconds")]
gr_trace <- function(run_id = NULL, meta = list(), system = NULL, owner = NULL, run_by = NULL,
                     purpose = NULL, approved_by = NULL, governor = NULL) {
  if (!is.null(governor) && !inherits(governor, "hr_governor")) {
    gr_abort("`governor` must come from hr_governor(), or be NULL.", class = "gr_bad_setting")
  }
  e <- new.env(parent = emptyenv())
  e$run_id <- as_chr1(run_id %||% gr_new_id("run"))
  e$started <- Sys.time()
  # Who the run is for and who ran it, from the arguments, else the `actor`
  # option, else NA. Kept on the run, not in `meta`, so every trace has the
  # same five fields whether or not anyone filled them in.
  given <- list(system = system, owner = owner, run_by = run_by, purpose = purpose,
                approved_by = approved_by)
  given <- given[!vapply(given, is.null, logical(1))]
  e$actor <- trace_actor(utils::modifyList(as.list(gr_options("actor") %||% list()),
                                           check_actor(given, "gr_trace()")))
  # The options in force when the run began, so a trace read back later says
  # what settings it ran under without the session that wrote it.
  e$config <- config_snapshot()
  # The version that produced the run, so a trace read back later says which
  # version wrote it. Prompts and readers change between versions. The field
  # keeps its readgpt name for now: traces written before and after the
  # rename to harnessr carry it in the same place.
  e$meta <- c(list(readgpt = tryCatch(as.character(utils::packageVersion("harnessr")),
                                      error = function(e) NA_character_)),
              meta)
  e$steps <- list()
  e$calls <- 0L
  e$cached <- 0L
  e$tokens_in <- 0L
  e$tokens_out <- 0L
  # Tokens sent to an embeddings endpoint. Kept apart from `tokens_in`, which
  # gr_trace_summary() documents as the model calls' prompts: embedding tokens
  # cost about a hundredth as much, so folded in they made
  # gr_estimate_cost(model, tokens_in, tokens_out) price a run that embeds at
  # up to 100 times what it cost. gr_trace_cost() prices each request at its
  # own model, embeddings included.
  e$embed_tokens <- 0L
  e$errors <- list()
  e$budget_stop <- FALSE
  # What the calls made so far cost, priced as they are recorded, so the
  # spending limit is enforced while a run is going and not only estimated
  # before it starts. A call to a model with no registered price adds nothing,
  # which makes this a floor on the spend: a floor that reaches the limit means
  # the spend has too. gr_trace_cost() is the full account, and says "unknown"
  # where this cannot.
  e$spent_usd <- 0
  # What the calls a replay answered from a recording cost when they were
  # recorded. Nothing was paid for them, so it is not in `spent_usd`, but it
  # counts against the spending limit with it (see budget_spent()): a replay
  # that did not count it never reached the limit that stopped the recorded
  # run, and went on to ask for calls the recording never made.
  e$replayed_usd <- 0
  # Which limit set `budget_stop`: "calls", "cost", "tokens", "output",
  # "model" or "unpriced".
  e$stop_reason <- NA_character_
  # The requests the governor did not send. None of them is a call or a step.
  e$refusals <- list()
  # NULL: the limits are read from gr_options() at each check.
  e$governor <- governor
  structure(e, class = "gr_trace")
}

#' The five actor fields of a run, each one string or NA.
#' @noRd
trace_actor <- function(x) {
  x <- if (is.list(x)) x else list()
  stats::setNames(lapply(.gr_actor_fields, function(f) as_chr1(x[[f]], NA_character_)),
                  .gr_actor_fields)
}

#' The actor fields a run records: the system the run belongs to, its owner,
#' who ran it, what for, and who approved it. `owner` and `run_by` are kept
#' apart because the person accountable for a system is often not the person
#' who pressed run.
#' @noRd
.gr_actor_fields <- c("system", "owner", "run_by", "purpose", "approved_by")

#' Check actor fields given as an option or to gr_trace(): a named list or
#' character vector, each name one of .gr_actor_fields, each value one string
#' or NA.
#' @noRd
check_actor <- function(value, where = "gr_options(actor = )") {
  if (is.null(value) || !length(value)) return(list())
  nms <- names(value)
  if ((!is.list(value) && !is.character(value)) || is.null(nms) || any(!nzchar(nms))) {
    gr_abort(sprintf("%s takes named fields: %s.", where,
                     paste(.gr_actor_fields, collapse = ", ")), class = "gr_bad_option")
  }
  bad <- setdiff(nms, .gr_actor_fields)
  if (length(bad)) {
    gr_abort(sprintf("Unknown actor field(s) in %s: %s. Known: %s.", where,
                     paste(bad, collapse = ", "), paste(.gr_actor_fields, collapse = ", ")),
             class = "gr_bad_option")
  }
  value <- as.list(value)
  one <- vapply(value, function(v) (is.character(v) || all(is.na(v))) && length(v) == 1L,
                logical(1))
  if (!all(one)) {
    gr_abort(sprintf("Each actor field in %s must be one string or NA: %s.", where,
                     paste(names(value)[!one], collapse = ", ")), class = "gr_bad_option")
  }
  lapply(value, function(v) as_chr1(v, NA_character_))
}

#' The options in force, as a trace records them.
#'
#' Header values can hold credentials (an `api-key` header is one), so only
#' their names are kept.
#' @noRd
config_snapshot <- function() {
  opts <- gr_options()
  h <- opts[["api_headers", exact = TRUE]]
  if (length(h)) opts["api_headers"] <- list(stats::setNames(rep("<set>", length(h)), names(h)))
  list(options = opts, r_version = R.version$version.string)
}

#' A time as ISO 8601 in UTC, to the millisecond, with the Z that says so.
#' @noRd
utc_stamp <- function(x = Sys.time()) {
  if (is.null(x) || !inherits(x, "POSIXct")) return(NA_character_)
  format(x, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

#' A step's token record: the counts, the breakdowns the provider reported,
#' and where the counts came from.
#' @noRd
step_tokens <- function(usage) {
  u <- if (is.list(usage)) usage else list()
  out <- list(input = u$input %||% 0L, output = u$output %||% 0L)
  if (!is.null(u$reasoning)) out$reasoning <- u$reasoning
  if (!is.null(u$cached_input)) out$cached_input <- u$cached_input
  out$provenance <- as_chr1(u$provenance, NA_character_)
  out
}

#' What one request cost at `model`'s prices, from its usage record, with
#' cached input at the cached rate where the model has one.
#' @noRd
usage_cost <- function(model, usage) {
  u <- if (is.list(usage)) usage else list()
  tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(
    as_chr1(model, "unknown"), u$input %||% 0L, u$output %||% 0L,
    cached_input_tokens = u$cached_input %||% 0L))),
    error = function(e) NA_real_)
}

#' A dollar amount to 12 significant figures, as the double a JSON reader reads
#' back from them.
#'
#' What a request counts against the spending limit is rounded so before it is
#' added up. Twelve figures is far below a cent, and it lets the figure be
#' saved exactly in 15 digits: a price such as 1234 tokens at $2.50 plus 56 at
#' $10 per million needs 17, and one such figure made as_json() write the whole
#' trace twice (see needs_more_digits()). A replay adds up the saved figures,
#' so it adds the very numbers the recorded run added.
#' @noRd
usd12 <- function(x) {
  if (length(x) != 1L || !is.finite(x) || x == 0) return(x)
  json_reads(sprintf("%.12g", x))
}

#' Record one request.
#'
#' `embedding = TRUE` for a request to an embeddings endpoint: it counts as a
#' call (it answers to `max_calls` like any other request) and is priced, but
#' its tokens go to `embed_tokens` rather than `tokens_in`, and its step is
#' marked `kind = "embedding"`.
#' @noRd
trace_record <- function(trace, label, messages, result, params = list(), seconds = NA_real_,
                         embedding = FALSE, sent = NULL, started = NULL, ended = NULL,
                         replay_key = NULL, draw_scope = NULL) {
  if (is.null(trace) || !inherits(trace, "gr_trace")) return(invisible(NULL))
  trace$calls <- trace$calls + 1L
  if (isTRUE(result$cached)) trace$cached <- trace$cached + 1L
  if (isTRUE(embedding)) {
    trace$embed_tokens <- (trace$embed_tokens %||% 0L) + as.integer(result$usage$input %||% 0L)
  } else {
    trace$tokens_in <- trace$tokens_in + as.integer(result$usage$input %||% 0L)
    trace$tokens_out <- trace$tokens_out + as.integer(result$usage$output %||% 0L)
  }
  # Priced by the model the step records, as gr_trace_cost() prices it. A call
  # answered from a cache or a replay spent nothing.
  budget <- 0
  if (!isTRUE(result$cached)) {
    usd <- usage_cost(result$model %||% params$model, result$usage)
    if (length(usd) == 1L && !is.na(usd)) {
      usd <- usd12(usd)
      trace$spent_usd <- (trace$spent_usd %||% 0) + usd
      budget <- usd
    }
  } else {
    # A replayed call counts what it cost when it was recorded, so a replay
    # stops where the recorded run was stopped. A cache hit carries no such
    # figure: a cache is there to make a run cheaper, and a run through a warm
    # cache goes as far as its limit lets it pay for.
    replayed <- as_num1(result[["replay_usd", exact = TRUE]], 0)
    if (is.finite(replayed) && replayed > 0) {
      trace$replayed_usd <- as_num1(trace$replayed_usd, 0) + replayed
      budget <- replayed
    }
  }
  if (!isTRUE(result$ok)) {
    trace$errors <- c(trace$errors, list(list(step = length(trace$steps) + 1L, label = label,
                                              error = mark_utf8(as_chr1(result$error)))))
  }
  # The request's own start and end, in UTC. A caller that did not time the
  # request is taken to have just finished it.
  ended <- if (inherits(ended, "POSIXct")) ended else Sys.time()
  if (!inherits(started, "POSIXct")) {
    secs <- as_num1(seconds, NA_real_)
    started <- ended - (if (is.finite(secs)) secs else 0)
  }
  step <- list(
    step = length(trace$steps) + 1L,
    label = as_chr1(label),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3"),
    started_utc = utc_stamp(started),
    ended_utc = utc_stamp(ended),
    model = as_chr1(result$model %||% params$model, NA_character_),
    ok = isTRUE(result$ok),
    cached = isTRUE(result$cached),
    # mark_utf8(), not enc2utf8(). A trace is serialised by jsonlite, and
    # jsonlite escapes bytes it cannot interpret in the CURRENT LOCALE: an
    # unmarked string holding UTF-8 bytes came out of `as_json()` as the literal
    # text "caf<c3><a9>" on any machine whose locale is not UTF-8. The bytes
    # were always right; nothing had told R what they were. Labelling them here
    # -- converting nothing -- is what makes a saved trace portable, and is what
    # a replay from a file depends on.
    prompt = lapply(messages, function(m) list(role = m$role,
                                               content = mark_utf8(as_chr1(m$content)))),
    response = mark_utf8(as_chr1(result$text)),
    error = if (isTRUE(result$ok)) NULL else mark_utf8(as_chr1(result$error)),
    tokens = step_tokens(result$usage),
    # Wall-clock time of the request, retries and their pauses included.
    seconds = round(as_num1(seconds, NA_real_), 3),
    # Requests sent for this one, retries included; 0 when a cache or a
    # recording answered. A retried request can be billed more than once.
    attempts = as_int1(result[["attempts", exact = TRUE]], NA_integer_),
    # What the provider said answered, kept apart from `model`, the model
    # asked for, which this step is priced and replayed by.
    served_model = as_chr1(result[["served_model", exact = TRUE]], NA_character_),
    response_id = as_chr1(result[["response_id", exact = TRUE]], NA_character_),
    fingerprint = as_chr1(result[["fingerprint", exact = TRUE]], NA_character_),
    # Recorded because a replay has to be able to reach the same decisions the
    # live run reached, and this is one a caller acts on:
    # gr_synthesise(coherence = TRUE) discards a revision whose finish_reason is
    # "length" -- a review with its ending cut off. Unrecorded, the replay saw
    # NA, kept the truncated revision, published a different document, and
    # reported 0 misses: it certified itself as an exact reproduction of a run
    # it had not reproduced.
    finish_reason = as_chr1(result$finish_reason, NA_character_),
    params = params[setdiff(names(params), "schema")],
    # What the request counted against max_cost_usd: its price when it was
    # sent; for a call a replay answered, what it cost when it was recorded;
    # and 0 from a cache. A replay of this trace counts the same figures, so it
    # stops where this run stopped whatever the replaying session's prices.
    budget_usd = budget
  )
  # Only on embeddings requests, so a model call's step keeps the fields it
  # always had.
  if (isTRUE(embedding)) step$kind <- "embedding"
  # The request as it went out (see client_sent_params()); `params` above is
  # what the caller asked for.
  if (is.list(sent)) step$params_sent <- sent
  # The harnessr-replay-v2 key of the call (see replay_key()). A replay of this
  # trace looks each step up by it. A step without one was recorded before the
  # key existed and is looked up by the old key, which covers less.
  if (is.character(replay_key) && length(replay_key) == 1L && !is.na(replay_key)) {
    step$replay_key <- replay_key
  }
  # Whose draw a sampled request was (see trace_draw_scope()). Only on such
  # steps, so every other step keeps the fields it always had.
  if (is.character(draw_scope) && length(draw_scope) == 1L && !is.na(draw_scope)) {
    step$draw_scope <- draw_scope
  }
  trace$steps <- c(trace$steps, list(step))
  invisible(NULL)
}

#' Mark the failures recorded from error `from` on as recovered.
#'
#' For a caller that has just recovered from them without losing any input, as
#' gr_embed() does when its lexical fallback replaces a failed embeddings
#' request. A document-level check (failed_note() in corpus.R) passes over a
#' recovered failure: the document was read in full, on the fallback, and the
#' answer already says what the fallback cost it.
#' @noRd
trace_mark_recovered <- function(trace, from) {
  if (!inherits(trace, "gr_trace")) return(invisible(NULL))
  n <- length(trace$errors)
  if (from > n) return(invisible(NULL))
  for (i in seq.int(from, n)) {
    trace$errors[[i]]$recovered <- TRUE
    s <- as_int1(trace$errors[[i]]$step, NA_integer_)
    if (!is.na(s) && s >= 1L && s <= length(trace$steps)) trace$steps[[s]]$recovered <- TRUE
  }
  invisible(NULL)
}

#' Record a non-model step (segmentation, ranking, a local computation).
#' @noRd
trace_note <- function(trace, label, detail = list()) {
  if (is.null(trace) || !inherits(trace, "gr_trace")) return(invisible(NULL))
  trace$steps <- c(trace$steps, list(list(
    step = length(trace$steps) + 1L, label = as_chr1(label),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3"),
    ok = TRUE, kind = "local", detail = detail
  )))
  invisible(NULL)
}

#' The draw index a trace hands to the requests recorded into it, or 0.
#'
#' Set on the trace of one benchmark run, so every request a reader makes in
#' that run is its own draw (see model_call()). Read without inheritance: a
#' trace is an environment with an empty parent.
#' @noRd
trace_draw_index <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(0L)
  d <- get0("draw_index", envir = trace, inherits = FALSE)
  ok <- is.numeric(d) && length(d) == 1L && !is.na(d) && is.finite(d) && d >= 1 &&
    d == round(d) && d <= .Machine$integer.max
  if (ok) as.integer(d) else 0L
}

#' The draw scope a trace hands to the sampled requests recorded into it, or
#' NULL.
#'
#' hr_benchmark() sets it to the arm's name on the trace of each run. Two arms
#' can send the same request at the same draw index; the scope keeps their
#' recorded replies apart, so a replay answers each arm with its own replies
#' whichever arms are replayed and in whatever order (see replay_lookup()).
#' @noRd
trace_draw_scope <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(NULL)
  s <- get0("draw_scope", envir = trace, inherits = FALSE)
  if (is.character(s) && length(s) == 1L && !is.na(s) && nzchar(s)) s else NULL
}

#' Fold a child trace's steps and counters into a parent.
#'
#' Used by `gr_compare()` so each recipe is budgeted independently while the
#' comparison still reports one combined trace.
#' @noRd
trace_absorb <- function(parent, child) {
  if (!inherits(parent, "gr_trace") || !inherits(child, "gr_trace")) return(invisible(NULL))
  off <- length(parent$steps)
  # Exact names: `$recipe` would match the `recipes` a comparison's trace keeps.
  src <- child$meta[["source", exact = TRUE]]
  rec <- as_chr1(child$meta[["recipe", exact = TRUE]], NA_character_)
  parent$steps <- c(parent$steps, lapply(child$steps, function(st) {
    st$step <- st$step + off
    # Which document and recipe a folded-in step was about, so a corpus trace
    # can still be read request by request. A step folded in twice keeps its
    # first document and its first recipe: a stage whose own meta names no
    # recipe used to write NA over the one the step already had.
    if (is.null(st$source) && !is.null(src)) st$source <- as_chr1(src, NA_character_)
    if (!is_nonblank(as_chr1(st$recipe, NA_character_)) && is_nonblank(rec)) st$recipe <- rec
    st
  }))
  parent$calls <- parent$calls + child$calls
  parent$cached <- (parent$cached %||% 0L) + (child$cached %||% 0L)
  parent$tokens_in <- parent$tokens_in + child$tokens_in
  parent$tokens_out <- parent$tokens_out + child$tokens_out
  parent$embed_tokens <- (parent$embed_tokens %||% 0L) + (child$embed_tokens %||% 0L)
  # An error names its step by number, so it moves with the steps: left as it
  # was, it pointed at one of the parent's own steps, and trace_mark_recovered()
  # marked that step instead of the one that failed.
  parent$errors <- c(parent$errors, lapply(child$errors, function(e) {
    if (is.list(e) && is.numeric(e$step) && length(e$step) == 1L && !is.na(e$step)) {
      e$step <- e$step + off
    }
    e
  }))
  parent$spent_usd <- (parent$spent_usd %||% 0) + (child$spent_usd %||% 0)
  parent$replayed_usd <- as_num1(parent$replayed_usd, 0) + as_num1(child$replayed_usd, 0)
  parent$refusals <- c(parent$refusals, child$refusals)
  if (isTRUE(child$budget_stop)) {
    parent$budget_stop <- TRUE
    parent$stop_reason <- child$stop_reason %||% NA_character_
  }
  invisible(NULL)
}

#' Label the steps from `from` on with the document and recipe they were for,
#' where a step does not say already. For a trace the caller passed in, which
#' may hold other runs, the trace's own meta cannot say which run a step was.
#' @noRd
trace_stamp <- function(trace, from, source = NULL, recipe = NULL) {
  if (!inherits(trace, "gr_trace")) return(invisible(NULL))
  n <- length(trace$steps)
  if (from > n) return(invisible(NULL))
  idx <- seq.int(from, n)
  trace$steps[idx] <- lapply(trace$steps[idx], function(st) {
    if (is.null(st$source) && !is.null(source)) st$source <- as_chr1(source, NA_character_)
    if (is.null(st$recipe) && !is.null(recipe)) st$recipe <- as_chr1(recipe, NA_character_)
    st
  })
  invisible(NULL)
}

#' A parent trace to fold a stage into, validated.
#'
#' `trace` does two jobs at once: it is the ledger of what a run did, and it is
#' the counter the governor measures `max_calls` against. Those want
#' opposite things when several stages of one review share it -- the ledger
#' should accumulate, the counter must not, or screening's calls are charged
#' against the write-up's per-stage ceiling and every section comes back blank.
#'
#' So a `trace` argument on a STAGE means "the parent to fold this stage's
#' accounting into". The stage still runs on its own, exactly as each document
#' inside gr_read_many() does, and `$trace` on the result is the stage's own.
#' @noRd
as_parent_trace <- function(trace, arg = "trace") {
  if (is.null(trace)) return(NULL)
  if (!inherits(trace, "gr_trace")) {
    gr_abort(sprintf("`%s` must come from gr_trace(), or be NULL.", arg),
             class = "gr_bad_trace")
  }
  trace
}

#' Summarise a trace
#' @param trace A `gr_trace`.
#' @return A one-row data frame: `run_id`, `calls`, `cached`, `steps`,
#'   `tokens_in`, `tokens_out`, `errors`, `elapsed_s`, `embed_calls`,
#'   `embed_tokens`, `tokens_reasoning`, `tokens_cached_in`,
#'   `usage_estimated`.
#'
#'   `calls` counts every request, including the `embed_calls` of them made to
#'   an embeddings endpoint. `tokens_in` and `tokens_out` are the size of the
#'   model calls' prompts and replies; the text sent to be embedded is counted
#'   in `embed_tokens` instead, because an embedding model is priced at a small
#'   fraction of a chat model's rate. There is no cost column: [gr_trace_cost()]
#'   prices every request at its own model, embeddings included, and is what the
#'   run cost. Combining `tokens_in`/`tokens_out` with [gr_estimate_cost()]
#'   estimates the model calls alone at one model's prices.
#'
#'   `cached` is how many of those calls were answered from a [gr_cache()] or a
#'   [gr_replay_client()]. Their tokens are still counted in `tokens_in` and
#'   `tokens_out`, because that is how large the prompts and replies were; they
#'   were simply not paid for again. A run with `cached == calls` cost nothing,
#'   so feeding its token counts to [gr_estimate_cost()] gives you what the run
#'   *would* have cost, not what it did.
#'
#'   `errors` counts every failed request, including any the run recovered
#'   from (see `errors` in [gr_trace()]).
#'
#'   `tokens_reasoning` and `tokens_cached_in` are the reasoning tokens and
#'   cached input tokens the provider reported for the model calls, 0 where it
#'   reported none. They are parts of `tokens_out` and `tokens_in`, not
#'   additions to them. `usage_estimated` is the share of requests whose token
#'   counts were estimated locally because the provider reported none (see
#'   `tokens` under "Steps" in [gr_trace()]), from 0 to 1, or `NA` when no
#'   request says.
#' @seealso [gr_trace()], [as_json()], [gr_trace_cost()], [gr_estimate_cost()],
#'   [gr_cache()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "45.2 million dollars")
#' ans <- answer_document(gr_example(), "What was revenue?", "thorough", client = cl)
#' gr_trace_summary(ans$trace)
#'
#' # What the run cost, each request priced at its own model (nothing, for a
#' # mock), and what its model calls would cost at another model's prices.
#' gr_trace_cost(ans$trace)
#' gr_estimate_cost("gpt-4o", ans$trace$tokens_in, ans$trace$tokens_out)
gr_trace_summary <- function(trace) {
  stopifnot(inherits(trace, "gr_trace"))
  data.frame(
    run_id = trace$run_id,
    calls = trace$calls,
    cached = as.integer(trace$cached %||% 0L),
    steps = length(trace$steps),
    tokens_in = trace$tokens_in,
    tokens_out = trace$tokens_out,
    errors = length(trace$errors),
    elapsed_s = round(as.numeric(difftime(Sys.time(), trace$started, units = "secs")), 2),
    # Last, so code that reads the columns by position finds the others where
    # they were.
    embed_calls = sum(vapply(trace$steps, function(st) identical(st$kind, "embedding"),
                             logical(1))),
    embed_tokens = as.integer(trace$embed_tokens %||% 0L),
    # The breakdowns the provider reported: parts of tokens_out and
    # tokens_in, not additions to them.
    tokens_reasoning = sum_step_tokens(trace$steps, "reasoning"),
    tokens_cached_in = sum_step_tokens(trace$steps, "cached_input"),
    usage_estimated = usage_estimated_share(trace$steps),
    stringsAsFactors = FALSE
  )
}

#' The requests of a trace whose usage is recorded: not local steps.
#' @noRd
request_steps <- function(steps) {
  Filter(function(s) is.list(s) && !identical(s$kind, "local") && is.list(s$tokens), steps)
}

#' One token breakdown summed over a trace's model calls.
#' @noRd
sum_step_tokens <- function(steps, field) {
  req <- Filter(function(s) !identical(s$kind, "embedding"), request_steps(steps))
  as.integer(sum(vapply(req, function(s) as_int1(s$tokens[[field]], 0L), integer(1))))
}

#' The share of requests whose token counts were estimated here rather than
#' reported by the provider or counted with the model's own tokenizer. NA
#' when no request says where its counts came from (an empty trace, or one
#' written before the record was kept).
#' @noRd
usage_estimated_share <- function(steps) {
  prov <- vapply(request_steps(steps), function(s) as_chr1(s$tokens$provenance, NA_character_),
                 character(1))
  prov <- prov[!is.na(prov)]
  if (!length(prov)) return(NA_real_)
  round(mean(prov == "estimated"), 4)
}

#' @rdname gr_trace
#' @export
as.data.frame.gr_trace <- function(x, row.names = NULL, optional = FALSE, ...) {
  # The requests gr_trace_cost() prices, so the two agree on what a run cost.
  steps <- Filter(function(s) !identical(s$kind, "local") && !is.null(s$tokens), x$steps)
  chr <- function(f) vapply(steps, function(s) as_chr1(f(s), NA_character_), character(1))
  tin <- vapply(steps, function(s) as_int1(s$tokens$input, NA_integer_), integer(1))
  tout <- vapply(steps, function(s) as_int1(s$tokens$output, NA_integer_), integer(1))
  cached <- vapply(steps, function(s) isTRUE(s$cached), logical(1))
  model <- chr(function(s) s$model)
  ok <- vapply(steps, function(s) isTRUE(s$ok), logical(1))
  # A cached request is priced at no tokens, as gr_trace_cost() prices it: 0
  # for a model with a price, NA for one without.
  usd <- vapply(seq_along(steps), function(i) {
    # A request that failed and sent no tokens cost nothing whatever its model.
    # An embeddings request to a gateway without embeddings fails like that,
    # usually for an embedding model with no registered price, and priced NA
    # it made the cost of a run whose every other request was priced unknown.
    if (!ok[i] && identical(tin[i], 0L) && identical(tout[i], 0L)) return(0)
    usage_cost(model[i], if (cached[i]) list(input = 0L, output = 0L)
                         else list(input = tin[i], output = tout[i],
                                   cached_input = steps[[i]]$tokens$cached_input))
  }, numeric(1))
  prompt <- vapply(steps, function(s) {
    parts <- vapply(s$prompt %||% list(), function(m) sprintf("[%s] %s", as_chr1(m$role, "?"),
                                                              as_chr1(m$content, "")),
                    character(1))
    paste(parts, collapse = "\n\n")
  }, character(1))
  out <- data.frame(
    step = vapply(steps, function(s) as_int1(s$step, NA_integer_), integer(1)),
    document = chr(function(s) s$source %||% x$meta[["source", exact = TRUE]]),
    recipe = chr(function(s) s$recipe %||% x$meta[["recipe", exact = TRUE]]),
    stage = chr(function(s) s$label),
    model = model,
    ok = ok,
    cached = cached,
    tokens_in = tin,
    tokens_out = tout,
    usd = usd,
    seconds = vapply(steps, function(s) as_num1(s$seconds, NA_real_), numeric(1)),
    error = chr(function(s) s$error),
    prompt = prompt,
    reply = chr(function(s) s$response),
    stringsAsFactors = FALSE)
  # The reasoning effort each request was sent with, last and only when some
  # request carried one: a run without the setting keeps the columns, in the
  # places, it always had.
  effort <- chr(function(s) if (is.list(s$params)) s$params[["effort", exact = TRUE]])
  if (any(!is.na(effort))) out$effort <- effort
  # The same rule for the token breakdowns and the model the provider said
  # answered: columns only when some request has them.
  brk <- function(f) vapply(steps, function(s) as_int1(s$tokens[[f]], NA_integer_), integer(1))
  reasoning <- brk("reasoning")
  if (any(!is.na(reasoning))) out$tokens_reasoning <- reasoning
  cached_in <- brk("cached_input")
  if (any(!is.na(cached_in))) out$tokens_cached_in <- cached_in
  served <- chr(function(s) s$served_model)
  if (any(!is.na(served))) out$served_model <- served
  if (!is.null(row.names)) rownames(out) <- row.names
  out
}

#' A run's requests as a one-line print shows them: "3 model call(s)", then
#' ", 4 embeddings request(s)" when it made any.
#'
#' `calls` counts both, since the limits count both, but only the first are
#' model calls. print.gr_trace() and print.gr_answer() count them apart, and a
#' print that showed `calls` as model calls (a corpus's "this run: 6 model
#' call(s)" for 2 model calls and 4 embeddings requests) disagreed with the
#' trace printed after it.
#' @noRd
format_call_counts <- function(trace) {
  if (!inherits(trace, "gr_trace")) return("0 model call(s)")
  s <- gr_trace_summary(trace)
  embed <- as.integer(s$embed_calls)
  paste0(sprintf("%d model call(s)", as.integer(s$calls) - embed),
         if (embed > 0L) sprintf(", %d embeddings request(s)", embed) else "")
}

#' @export
print.gr_trace <- function(x, ...) {
  s <- gr_trace_summary(x)
  recovered <- sum(vapply(x$errors, function(e) isTRUE(e$recovered), logical(1)))
  # Model calls and embeddings requests apart: both are requests the limits
  # count, but only the first are model calls, and the two are priced and
  # tokenised differently.
  cat(sprintf("<gr_trace %s>  %d steps, %d model calls%s%s, %d in / %d out tokens, %d error(s)%s\n",
              s$run_id, s$steps, s$calls - s$embed_calls,
              if (s$cached > 0L) sprintf(" (%d cached)", s$cached) else "",
              if (s$embed_calls > 0L)
                sprintf(", %d embeddings request(s) (%d tokens)", s$embed_calls, s$embed_tokens)
              else "",
              s$tokens_in, s$tokens_out, s$errors,
              if (recovered > 0L) sprintf(" (%d recovered by a fallback)", recovered) else ""))
  labs <- vapply(x$steps, function(st) as_chr1(st$label), character(1))
  if (length(labs)) {
    tab <- table(labs)
    cat("  steps:", paste(sprintf("%s x%d", names(tab), as.integer(tab)), collapse = ", "), "\n")
  }
  cat(sprintf("  cost: %s\n", format_trace_cost(x)))
  # The usage, served-by and actor lines print only when there is something
  # to say, so a mock run prints what it did, plus where its token counts came
  # from. The start time and the first error follow them.
  if (!is.na(s$usage_estimated) && s$usage_estimated > 0) {
    cat(sprintf("  usage: estimated locally for %s of requests (the provider reported none)\n",
                sprintf("%.0f%%", 100 * s$usage_estimated)))
  }
  served <- unique(stats::na.omit(vapply(x$steps, function(st)
    as_chr1(st$served_model, NA_character_), character(1))))
  if (length(served)) cat("  served by:", paste(served, collapse = ", "), "\n")
  actor <- trace_actor(x$actor)
  set <- !vapply(actor, is.na, logical(1))
  if (any(set)) {
    cat("  actor:", paste(sprintf("%s = %s", names(actor)[set], unlist(actor[set])),
                          collapse = ", "), "\n")
  }
  if (inherits(x$started, "POSIXct")) cat("  started:", utc_stamp(x$started), "\n")
  if (length(x$errors)) {
    cat("  first error:", substr(as_chr1(x$errors[[1]]$error), 1, 160), "\n")
  }
  invisible(x)
}
