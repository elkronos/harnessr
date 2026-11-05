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
#' @return A `gr_trace`. It is an environment, so it accumulates by reference:
#'   pass the same trace to several calls and they all record into it. Fields:
#'   `run_id`, `started`, `meta`, `steps`, `calls`, `cached`, `tokens_in`,
#'   `tokens_out`, `embed_tokens`, `errors`, `budget_stop`, `stop_reason`,
#'   `spent_usd`, `replayed_usd`.
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
#'   says which: `"calls"` for `max_calls`, `"cost"` for `max_cost_usd` (see
#'   [gr_options()]). `spent_usd` is what the calls so far cost. A call to a
#'   model with no registered price adds nothing to it, so [gr_trace_cost()] is
#'   the full account. `replayed_usd` is what the calls a [gr_replay_client()]
#'   answered cost when they were recorded, counted when the spending limit
#'   stopped the recorded run: nothing was paid for them, but `max_cost_usd`
#'   is checked against `spent_usd + replayed_usd`, so the replay stops at the
#'   same call. A call answered from a [gr_cache()] adds to neither, so a
#'   re-run through a warm cache under the same limit reads further than the
#'   run that filled it.
#'   [as_json()] and [gr_trace_save()] write `budget_stop`, `stop_reason`,
#'   `spent_usd` and `replayed_usd`, so a saved run says whether it was cut
#'   short.
#'
#'   `as.data.frame()` on a trace returns one row per request; see below.
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
#' }
#' @param x A `gr_trace`.
#' @param row.names Optional row names for the result.
#' @param optional,... Ignored; part of the [as.data.frame()] generic.
#' @seealso [gr_trace_summary()], [as_json()], [gr_answer], [gr_cache()]
#' @export
#' @examples
#' tr <- gr_trace(meta = list(purpose = "demo"))
#' cl <- gr_mock_client(function(m, p) "an answer")
#' ch <- gr_segment(readgpt_example(), list(method = "sentence", max_tokens = 150))
#' invisible(gr_read(ch, "What was revenue?", cl, "map_reduce", trace = tr))
#' print(tr)
#'
#' # One row per request, with what each cost and how long it took.
#' reqs <- as.data.frame(tr)
#' reqs[, c("step", "stage", "tokens_in", "tokens_out", "usd", "seconds")]
gr_trace <- function(run_id = NULL, meta = list()) {
  e <- new.env(parent = emptyenv())
  e$run_id <- as_chr1(run_id %||% gr_new_id("run"))
  e$started <- Sys.time()
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
  # "calls" or "cost": which limit set `budget_stop`.
  e$stop_reason <- NA_character_
  structure(e, class = "gr_trace")
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
                         embedding = FALSE) {
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
    usd <- tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(
      as_chr1(result$model %||% params$model, "unknown"),
      result$usage$input %||% 0L, result$usage$output %||% 0L))),
      error = function(e) NA_real_)
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
  step <- list(
    step = length(trace$steps) + 1L,
    label = as_chr1(label),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3"),
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
    tokens = list(input = result$usage$input %||% 0L, output = result$usage$output %||% 0L),
    # Wall-clock time of the request, retries and their pauses included.
    seconds = round(as_num1(seconds, NA_real_), 3),
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
#' the counter `trace_can_call()` measures `max_calls` against. Those want
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
#'   `embed_tokens`.
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
#' @seealso [gr_trace()], [as_json()], [gr_trace_cost()], [gr_estimate_cost()],
#'   [gr_cache()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "45.2 million dollars")
#' ans <- answer_document(readgpt_example(), "What was revenue?", "thorough", client = cl)
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
    stringsAsFactors = FALSE
  )
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
    tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(
      as_chr1(model[i], "unknown"), if (cached[i]) 0L else tin[i],
      if (cached[i]) 0L else tout[i]))), error = function(e) NA_real_)
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
  if (length(x$errors)) {
    cat("  first error:", substr(as_chr1(x$errors[[1]]$error), 1, 160), "\n")
  }
  invisible(x)
}
