# doc-read-run.R -- AXIS 3: the public reading entry point and the distinctness
# check.

#' Read chunks and answer a question
#'
#' The third axis. Reading is a separate decision from segmentation because the
#' call pattern (which chunks reach the model, in how many requests, and
#' whether anything flows between them) is where both cost and answer quality
#' are actually decided. The same chunk set can be read many ways;
#' [gr_readers()] lists them with what each costs.
#'
#' @param chunks A `gr_chunks` object from `gr_segment()`.
#' @param question The question.
#' @param client A `gr_client`.
#' @param spec A `gr_read_spec`, a reader name, or a named list.
#' @param trace Optional `gr_trace`; one is created when omitted.
#' @return A [gr_answer]. Check `$partial` before trusting `$answer`.
#' @seealso [gr_readers()], [gr_read_spec()], [gr_answer], [answer_document()]
#' @family reading functions
#' @export
#' @examples
#' ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 120))
#'
#' # The same chunks, two strategies, two very different call patterns. Each gets
#' # its own client and trace, so the call counts are comparable.
#' run <- function(reader, ...) {
#'   cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#'   tr <- gr_trace()
#'   a <- gr_read(ch, "What was revenue?", cl, c(list(reader = reader), list(...)), trace = tr)
#'   data.frame(reader = a$reader, signature = a$signature,
#'              calls = length(cl$calls()), chunks_used = length(a$chunks_used))
#' }
#' rbind(run("retrieve", top_k = 2), run("map_reduce"))
gr_read <- function(chunks, question, client, spec = NULL, trace = NULL) {
  if (!inherits(chunks, "gr_chunks")) gr_abort("`chunks` must come from gr_segment().")
  # UTF-8, and labelled so, before anything pastes it next to the document's
  # labelled text: a question in CP1252 stopped the token count with "invalid
  # UTF-8", and one in UTF-8 without the label had its accented letters
  # written out by paste() as "<c3><a9>" in a C locale.
  if (is.character(question)) question <- to_utf8(question)
  if (!is_nonblank(question)) gr_abort("`question` must be a non-empty string.")
  if (!inherits(client, "gr_client")) gr_abort("`client` must come from gr_client() or gr_mock_client().")
  spec <- as_read_spec(spec)
  # What the caller configured, for the trace: a model that merely follows the
  # client is not a setting, as one that followed gr_options() was not.
  settings <- read_settings(spec)
  spec <- resolve_read_model(spec, client)
  trace <- trace %||% gr_trace(meta = list(reader = spec$reader))
  rd <- registry_get("readers", spec$reader, "readers", state = gr_state)

  gr_msg(sprintf("Reading with '%s' (%s) over %d chunk(s).",
                 spec$reader, rd$signature, nrow(chunks$chunks)))
  # A limit that stopped an earlier read on the same trace did not stop this
  # one. The trace keeps that record unless this read is stopped too.
  if (inherits(trace, "gr_trace")) {
    earlier <- list(stop = isTRUE(trace$budget_stop), reason = trace$stop_reason %||% NA_character_)
    trace$budget_stop <- FALSE
    trace$stop_reason <- NA_character_
    on.exit(if (!isTRUE(trace$budget_stop)) {
      trace$budget_stop <- earlier$stop
      trace$stop_reason <- earlier$reason
    }, add = TRUE)
  }
  rec <- warning_recorder()
  # Where this read's run starts: a trace passed in may hold other runs, and
  # new_answer() cannot tell where this one began (answer_trace()).
  from <- if (inherits(trace, "gr_trace")) read_run_start(trace)
  out <- withCallingHandlers({
    preflight(chunks, spec, trace, client = client, question = question, settings = settings)
    rd$fn(chunks, question, client, spec, trace)
  }, gr_warning = rec$record)
  if (!inherits(out, "gr_answer")) {
    gr_abort(sprintf("Reader '%s' did not return a gr_answer object.", spec$reader))
  }
  # That the premise was checked, and what came of it, on the answer and in the
  # trace (read-premise.R). Before `trace_steps` is set, so the step is this
  # run's. Nothing at all when the spec did not ask.
  out <- premise_record(out, spec, trace)
  # The quotation check, when the spec asks for it (verify_record()).
  out <- verify_record(out, chunks, spec, trace)
  # Only for an answer on this trace: a custom reader that kept a trace of its
  # own has steps numbered in that one.
  if (inherits(trace, "gr_trace") && identical(out[["trace", exact = TRUE]], trace)) {
    out$trace_steps <- c(first = from, last = length(trace$steps))
  }
  if (isTRUE(trace$budget_stop)) {
    out$partial <- TRUE
    gov <- trace_governor(trace)
    why <- as_chr1(trace$stop_reason, "calls")
    if (why %in% c("cost", "unpriced")) {
      out$notes$cost_cap_reached <- gov$max_cost_usd
    } else if (identical(why, "calls")) {
      out$notes$call_cap_reached <- gov$max_calls
    } else {
      # The output ceiling or the model allow-list refused a request.
      out$notes$limit_refused <- why
    }
  }
  # Pages that never became text are missing from every chunk, so nothing this
  # reader did could have seen them. The answer rests on part of the document.
  unread <- chunks[["unread_pages", exact = TRUE]] %||% integer(0)
  if (length(unread)) {
    out$partial <- TRUE
    out$notes["unread_pages"] <- list(unread)
  }
  out$warnings <- c(chunks[["warnings", exact = TRUE]] %||% character(0), rec$get())
  out$signature <- rd$signature
  out
}

#' The first step of the run a read about to start on `trace` belongs to, for
#' its answer's `trace_steps` (answer_trace()).
#'
#' A trace is shared by reference. Where it already holds a read (that read's
#' "preflight" step), it holds another run, and this read's record starts at
#' its own first step, so no other run's prompts, calls or cost are in it.
#' Where it holds none, what is on it is the work that led to this read: the
#' document's ingestion and segmentation, on the trace gr_read_many() and
#' gr_compare() keep for each document, or on one passed to gr_segment() and
#' then to gr_read(). That stays in the record, as it always has.
#' @noRd
read_run_start <- function(trace) {
  n <- length(trace$steps)
  earlier <- vapply(trace$steps, function(st) {
    is.list(st) && identical(as_chr1(st$label, ""), "preflight")
  }, logical(1))
  if (any(earlier)) n + 1L else 1L
}

#' Pre-flight cost and call-count guard.
#'
#' The previous release had nothing like this, which is why an unrecognised
#' model name could silently turn a 10,000-word document into ~10,001 API calls.
#'
#' Only what is known refuses a run: how many requests the reader will make,
#' and, for a reader that sends every chunk, what sending them costs. What the
#' replies will cost is not known, and neither is which chunks a top-k reader
#' will pick. The old check priced every reply at its token cap and refused a
#' run at an estimate of $5.54 that cost $0.11. Now a run is refused before it
#' starts only when it cannot finish under `max_cost_usd`, and the governor
#' refuses any request whose worst case would pass the limit. The
#' worst case is still recorded in the trace, and still refuses a parallel
#' read: a batch sent to workers cannot be stopped part way through.
#'
#' What each reader can cost comes from its own `cost` function (see
#' reader_cost()), summed here; the governor decides which limit, if any, the
#' sum cannot fit (governor_run_check()), and this words the refusal.
#'
#' `client` is what the run is billed through: an ellmer chat bills every call
#' as its own model whatever the request names. `question` sizes the merge and
#' summary levels of the worst case, as the readers size them.
#' @noRd
preflight <- function(chunks, spec, trace, client = NULL, question = "",
                      settings = read_settings(spec)) {
  n <- nrow(chunks$chunks)
  stats <- read_input_stats(chunks, spec, client, question)
  total <- reader_cost(spec$reader, stats, spec)
  # Requests to the embeddings endpoint count toward max_calls too (see
  # embed_api()). Left out, a cap too small for them passed this check, and
  # the run stopped part way: its embeddings refused, a lexical fallback in
  # their place, and the answer never asked for.
  embed_calls <- as.integer(total$embed_max)
  est_calls <- as.integer(total$calls + total$embed_max)
  # Never below the expected count: a worst case under the estimate is not one.
  worst_calls <- as.integer(max(est_calls, total$calls_max + total$embed_max))
  level_in <- total$tokens_in_max
  parallel_read <- isTRUE(spec$parallel) && total$batched &&
    requireNamespace("future", quietly = TRUE) && requireNamespace("future.apply", quietly = TRUE)
  # The call cap first: a run refused on its count is not priced.
  tok <- sum(chunks$chunks$tokens)
  refuse <- function(chk) preflight_refuse(chk, spec, n, est_calls, embed_calls, worst_calls,
                                           tok, input_cost, worst)
  input_cost <- worst <- NA_real_
  refuse(governor_run_check(trace, calls = est_calls, calls_max = worst_calls,
                            parallel = parallel_read, calls_only = TRUE))

  # The reader warns about an unrecognised model itself; once is enough.
  quiet_model <- function(expr) suppressWarnings(expr, classes = "gr_unknown_model")
  # Priced below as model requests: an embedding request has no reply, and
  # what it sends goes at the embedding model's price, a small fraction of the
  # chat model's.
  model_worst <- worst_calls - embed_calls
  # What the worst case sends: every chunk, the fixed prompt of every request,
  # and what the merge and summary levels are handed, which is replies at
  # their caps. The premise rule (read-premise.R) lengthens every prompt that
  # answers the question by up to its longest form, which the 200 tokens were
  # never sized for: with it, a `stuff` or `refine` read spent more than the
  # bound recorded for it.
  per_request <- 200L + if (isTRUE(spec$premise))
    max(gr_count_tokens(unlist(.gr_premise_prompts))) else 0L
  est_in <- tok + model_worst * per_request + level_in
  # Size the completion estimate by the LARGER of the two caps: only the
  # per-chunk readers use max_chunk_tokens, and the rest size their answers with
  # max_answer_tokens, so using the per-chunk cap under-estimated output by
  # whatever ratio the user chose -- measured at 97x in one configuration.
  # This is the worst case, recorded below; it refuses only a parallel read.
  # A reasoning model is sent a larger cap than that, with room for its
  # reasoning (reasoning_output_cap()), and bills up to it: priced at the cap
  # asked for, the bound understated every such request by up to the
  # difference. Prompt tokens of 0 leave that room at its largest.
  per_out <- max(spec$max_chunk_tokens, spec$max_answer_tokens, spec$max_summary_tokens)
  est_out_for <- function(m) {
    info <- tryCatch(quiet_model(gr_model_info(m)), error = function(e) NULL)
    max(model_worst * (if (is.null(info)) per_out else reasoning_output_cap(per_out, info, 0)),
        total$tokens_out_max)
  }
  # An ellmer chat answers, and is billed, as the model it was built with,
  # whatever a request names, and the trace prices its calls by that model. So
  # that is the model to price: pricing the recipe's instead found a price,
  # raised no warning, and ran a limit that the calls, billed as a model with
  # no registered price, could never reach.
  billed <- client_billed_model(client)
  # Every request at the price of the dearest model the run uses: skim_model and
  # summary_model take most of the requests of the readers that use them, and a
  # bound priced at `model` alone understated a run whose per-chunk model was
  # the dear one.
  models <- billed %||% unique(c(spec$model, spec$skim_model, spec$summary_model))
  priced_worst <- vapply(models, function(m) as.numeric(quiet_model(
    gr_estimate_cost(m, est_in, est_out_for(m)))), numeric(1))
  # The dearest PRICED model. One model without a price made max() NA, and the
  # parallel refusal below, which needs a number, was then skipped for the whole
  # run, the priced model that receives the batch included. Only a run with no
  # priced model at all has no worst case.
  worst <- if (all(is.na(priced_worst))) NA_real_ else max(priced_worst, na.rm = TRUE)
  # What the run must send whatever it does: for each reader in it that sends
  # every chunk, the chunks once, at the price of the model that receives them
  # (each reader's cost says which; an ellmer chat bills them all as its own).
  every_chunk <- length(total$sends) > 0L
  floors <- vapply(total$sends, function(s) as.numeric(quiet_model(
    gr_estimate_cost(billed %||% s$model, s$tokens, 0))), numeric(1))
  # The same rule as `worst`: an ensemble member read by an unpriced model has
  # an unknown share, and summing it made the whole floor NA and waived the
  # refusal for the members whose share is known.
  input_cost <- if (!every_chunk) 0 else if (all(is.na(floors))) NA_real_
                else sum(floors, na.rm = TRUE)
  budget <- trace_governor(trace)$max_cost_usd
  unit <- if (!is.null(budget) && is.finite(budget)) {
    vapply(models, function(m) as.numeric(quiet_model(gr_estimate_cost(m, 1, 1))), numeric(1))
  }
  # A mock sends nothing that is paid for and a replay costs what its
  # recording says, so neither is stopped for a model with no price.
  exempt <- inherits(client, "gr_mock_client") || inherits(client, "gr_replay_client")
  refuse(governor_run_check(trace, calls = est_calls, calls_max = worst_calls,
                            parallel = parallel_read, unit_usd = unit, exempt = exempt,
                            floor_usd = if (every_chunk) input_cost, worst_usd = worst))
  trace_note(trace, "preflight", list(reader = spec$reader, chunks = n,
                                      # The model the read asked for, which is
                                      # the client's when `settings` names
                                      # none. A replay has to ask for the same
                                      # one, and the model a recording holds
                                      # most calls under is the cheaper
                                      # skim_model or summary_model when those
                                      # made most of them.
                                      model = spec$model,
                                      est_calls = est_calls,
                                      # Of those, requests to the embeddings
                                      # endpoint.
                                      embed_calls = embed_calls,
                                      # Every reply at its cap and every level
                                      # that takes: what `est_cost_usd` prices.
                                      worst_calls = worst_calls,
                                      # Every chunk once, for a reader that sends
                                      # them all: the floor that can refuse a run.
                                      est_input_usd = if (is.na(input_cost)) NULL
                                                      else round(input_cost, 4),
                                      # Every reply at its cap: an upper bound.
                                      est_cost_usd = if (is.na(worst)) NULL else round(worst, 4),
                                      # What was changed from the defaults, so
                                      # the trace records the configuration and
                                      # not just the reader's name.
                                      settings = settings))
  invisible(NULL)
}

#' Word the refusal governor_run_check() returned for a read, and raise it.
#' An unpriced model that is allowed is warned about, since what its requests
#' cost is not counted. Returns nothing when the run may start.
#' @noRd
preflight_refuse <- function(chk, spec, n, est_calls, embed_calls, worst_calls, tok,
                             input_cost, worst) {
  limit <- chk$limit
  cap <- chk$cap
  already <- chk$already
  if (identical(limit, "calls")) {
    gr_abort(sprintf(paste0("Reader '%s' over %d chunks would need about %d more %s ",
                            "(%s%d already made this run), above the %s-call cap. Use a larger ",
                            "`max_tokens` when segmenting (fewer chunks), pick a top-k reader, ",
                            "or raise gr_options(max_calls = ...)."),
                     spec$reader, n, est_calls,
                     if (embed_calls > 0L) "requests" else "model calls",
                     if (embed_calls > 0L) sprintf("%d of them for embeddings; ", embed_calls)
                     else "",
                     already, format(cap, scientific = FALSE)),
             class = "gr_call_cap")
  }
  # A parallel batch is not stopped part way, so a parallel read is held to its
  # worst case against the call cap as it is against the spending limit.
  if (identical(limit, "calls_worst")) {
    gr_abort(sprintf(paste0("With parallel = TRUE, requests go out in batches that cannot be ",
                            "stopped part way, so a parallel read is held to its worst case: ",
                            "'%s' over %d chunks can need up to %d more model calls (%d already ",
                            "made this run), above the %s-call cap. Raise it with ",
                            "gr_options(max_calls = ...), or read without parallel = TRUE, where ",
                            "the cap is checked before every request."),
                     spec$reader, n, worst_calls, already, format(cap, scientific = FALSE)),
             class = "gr_call_cap")
  }
  budget <- chk$budget
  if (is.null(budget) || !is.finite(budget)) return(invisible(NULL))
  limit_txt <- format(budget, scientific = FALSE)
  unpriced <- chk$unpriced
  models_txt <- function(u) if (length(u) == 1L) sprintf("Model '%s' has", u)
                            else sprintf("Models %s have", paste0("'", u, "'", collapse = ", "))
  their <- function(u) if (length(u) == 1L) "its" else "their"
  # No pricing for a model, so the governor would refuse every request to
  # it. Stopped here, before the first, rather than read as a run of refused
  # calls.
  if (identical(limit, "unpriced")) {
    gr_abort(sprintf(paste0("%s no registered price, so what %s requests cost cannot be held to ",
                            "the $%s max_cost_usd limit, and the run was not started. Register ",
                            "prices with gr_register_model(input_usd =, output_usd =), or allow ",
                            "unpriced models with gr_options(allow_unpriced = TRUE)."),
                     models_txt(unpriced), their(unpriced), limit_txt),
             class = c("hr_unpriced_model", "hr_budget_refused"))
  }
  # Allowed unpriced, or a mock: what its requests cost is not counted. Say
  # so rather than silently running with no spending guard at all.
  if (length(unpriced)) {
    gr_warn(sprintf(paste0("%s no pricing in the registry, so what %s requests cost cannot be ",
                           "counted against the $%s max_cost_usd limit. Register prices with ",
                           "gr_register_model(input_usd =, output_usd =) to enable it."),
                    models_txt(unpriced), their(unpriced), limit_txt),
            class = "gr_cost_uncheckable")
  }
  # What this run has spent already counts, as calls already made count
  # against the call cap: several readers on one trace are one run.
  # budget_spent(): with what a replay's recorded calls cost, as the
  # governor counts it, so a replay of a run the limit stopped makes the
  # decisions here that the recording made. Spending nothing never reaches a
  # limit, so under a limit of 0 a model registered at no cost still runs.
  spent <- chk$spent
  if (identical(limit, "spent")) {
    gr_abort(sprintf(paste0("This run has already spent $%s, which reaches the $%s limit. ",
                            "Raise it with gr_options(max_cost_usd = ...)."),
                     fmt_usd(spent), limit_txt),
             class = "gr_cost_cap")
  }
  # A limit of nothing: a model that costs nothing may run, and the first
  # request to one that has a price would already pass it.
  if (identical(limit, "zero")) {
    gr_abort(sprintf(paste0("The spending limit is $0, and '%s' has a price. Raise it with ",
                            "gr_options(max_cost_usd = ...), or use a model registered at no cost."),
                     chk$zero_model),
             class = "gr_cost_cap")
  }
  already_txt <- if (spent > 0) sprintf(", and this run has already spent $%s", fmt_usd(spent))
                 else ""
  if (identical(limit, "floor")) {
    gr_abort(sprintf(paste0("Reading this document with '%s' sends every chunk at least once, ",
                            "which costs about $%s before any reply (%d chunk(s), %s input ",
                            "tokens)%s, above the $%s limit. Raise it with ",
                            "gr_options(max_cost_usd = ...), or use a reader that sends only the ",
                            "chunks it picks, such as recipe = \"needle\"."),
                     spec$reader, fmt_usd(input_cost), n,
                     format(tok, big.mark = ",", scientific = FALSE), already_txt, limit_txt),
             class = "gr_cost_cap")
  }
  if (identical(limit, "worst")) {
    gr_abort(sprintf(paste0("With parallel = TRUE, requests go out in batches that cannot be ",
                            "stopped part way, so a parallel read is held to its worst case: ",
                            "every reply at its cap, about $%s for '%s' over %d chunk(s)%s, ",
                            "above the $%s limit. Raise it with gr_options(max_cost_usd = ...), ",
                            "or read without parallel = TRUE, where spending is checked before ",
                            "every request."),
                     fmt_usd(worst), spec$reader, n, already_txt, limit_txt),
             class = "gr_cost_cap")
  }
  invisible(NULL)
}

#' What a reader's cost function is told about the input: `n_chunks`,
#' `tokens` (all chunks), `texts`, `question`, `out_cap` (the largest reply
#' cap a request to `spec$model` is sent: the largest of the spec's caps,
#' within the model's limit and raised as reasoning_output_cap() raises it
#' at 0 prompt tokens), and three helpers that size requests the way the
#' readers do:
#'
#' - `reply_cap(model, cap)`: the largest reply a request asking for `cap`
#'   tokens can get from `model` (its own output limit, when smaller).
#' - `room(system, restate)`: the prompt tokens a request with that system
#'   prompt has for its excerpts at `max_answer_tokens`, NA when not known.
#' - `embed_requests(texts)`: the requests to the embeddings endpoint that
#'   embedding `texts` takes. It counts a text once across the readers of one
#'   run, as the session's embedding cache does, so call it once per text set.
#'   `embed_api` says whether embeddings go to the endpoint at all; when they
#'   do not, `embed_requests()` always says 0.
#' @noRd
read_input_stats <- function(chunks, spec, client, question) {
  quiet_model <- function(expr) suppressWarnings(expr, classes = "gr_unknown_model")
  counter <- embed_counter(client)
  reply_cap <- function(m, cap) {
    mo <- tryCatch(as.numeric(quiet_model(gr_model_info(m))$max_output),
                   error = function(e) NA_real_)
    as.numeric(if (length(mo) != 1L || is.na(mo)) cap else min(cap, mo))
  }
  per_out <- max(as_num1(spec$max_chunk_tokens, 0), as_num1(spec$max_answer_tokens, 0),
                 as_num1(spec$max_summary_tokens, 0))
  info <- tryCatch(quiet_model(gr_model_info(spec$model)), error = function(e) NULL)
  out_cap <- reply_cap(spec$model, per_out)
  if (!is.null(info)) out_cap <- as.numeric(reasoning_output_cap(out_cap, info, 0))
  list(
    n_chunks = nrow(chunks$chunks),
    tokens = sum(chunks$chunks$tokens),
    texts = chunks$chunks$text,
    question = question,
    out_cap = out_cap,
    reply_cap = reply_cap,
    room = function(system, restate = "never") tryCatch(as.numeric(quiet_model(gr_budget(
      spec$model, reserve_output = spec$max_answer_tokens,
      overhead = prompt_overhead(question, system, restate)))$input), error = function(e) NA_real_),
    embed_api = !is.null(counter),
    embed_requests = counter %||% function(x) 0L)
}

#' What one run of reader `r` can cost, from the cost function it registered.
#'
#' A reader registered without one is counted as one request per chunk, and,
#' when its signature says it sends every chunk, as sending all of them to
#' `spec$model`. So is a name that is not registered: the reader itself says
#' what is wrong with it once it runs.
#' @noRd
reader_cost <- function(r, stats, spec) {
  rd <- gr_state$readers[[as_chr1(r, "")]]
  fn <- rd$cost %||% default_reader_cost(rd$signature %||% "")
  out <- fn(stats, spec)
  if (!inherits(out, "hr_cost")) {
    # A plain list may state only the worst case, as calls_max: the expected
    # count is then taken as that. `[[` because `$calls` would match calls_max.
    if (is.list(out) && is.null(out[["calls"]]) && !is.null(out[["calls_max"]])) {
      out[["calls"]] <- out[["calls_max"]]
    }
    if (is.list(out) && !is.null(out[["calls"]])) out <- do.call(hr_cost, out[intersect(
      names(out), names(formals(hr_cost)))])
    else gr_abort(sprintf("The cost function of reader '%s' did not return hr_cost().", r),
                  class = "gr_bad_setting")
  }
  out
}

#' The cost of a reader that registered none: one request per chunk.
#' @noRd
default_reader_cost <- function(signature) {
  sends_all <- startsWith(as_chr1(signature, ""), "all|")
  function(stats, params) {
    hr_cost(calls = stats$n_chunks,
            sends = if (sends_all) list(list(tokens = stats$tokens, model = params$model)))
  }
}

#' A counter of requests to the embeddings endpoint, for read_input_stats().
#'
#' Only the built-in "api" embedder sends requests: a client's own embed
#' function, a registered one such as "lexical", and a backend or replay
#' client (which gr_embed() moves to lexical vectors) send none, and there is
#' then no counter (NULL). A text in the session's embedding cache is not
#' sent again, and with the cache on a reader finds what an earlier ensemble
#' member embedded there. 64 texts to a request, gr_embed()'s default.
#' @noRd
embed_counter <- function(client) {
  if (!inherits(client, "gr_client")) return(NULL)
  emb <- tryCatch(resolve_embedder(client), error = function(e) NULL)
  if (is.null(emb) || !identical(emb$fn, embed_api) || inherits(client, "gr_replay_client") ||
      as_chr1(client[["api", exact = TRUE]], "") %in% c("backend", "replay")) {
    return(NULL)
  }
  cache <- isTRUE(gr_options("cache_embeddings"))
  model <- as_chr1(client[["embedding_model", exact = TRUE]], "")
  # The key embed_api() files a vector under. Should the two drift apart, a
  # cached text is counted as sent, which can refuse a run near the cap but
  # never lets one start that the cap stops part way.
  endpoint <- paste0(as_chr1(client[["base_url", exact = TRUE]], "?"), "|",
                     as_chr1(client[[".client_id", exact = TRUE]], "<url-addressed>"))
  earlier <- character(0)
  function(x) {
    if (cache && length(x)) {
      keys <- vapply(x, function(t) embed_cache_key("api", model, t, endpoint), character(1),
                     USE.NAMES = FALSE)
      held <- vapply(keys, function(k) !is.null(hr_state$embed_cache[[k]]), logical(1),
                     USE.NAMES = FALSE)
      x <- x[!held & !keys %in% earlier]
      earlier <<- c(earlier, keys)
    }
    as.integer(ceiling(length(x) / 64))
  }
}

#' The requests tree_merge() makes at worst, and the tokens they are handed.
#'
#' `k` findings of up to `piece` tokens are grouped greedily into merges that
#' fit `room`, each merge replying with up to `answer` tokens, level after
#' level, until one merge takes everything that is left. A group of one is
#' passed on without a request, and tree_merge() gives up after seven levels or
#' a level that does not shrink the pile. NULL when the room is not known.
#'
#' Each finding is counted in the numbered tags tree_merge() sizes it in, with
#' the blank line after it, so the bound holds for findings of any size.
#' @noRd
merge_tree_worst <- function(k, piece, answer, room) {
  if (length(room) != 1L || is.na(room) || room <= 0) return(NULL)
  if (k <= 1) return(list(calls = 0, input = 0))
  tag <- gr_count_tokens("<findings 999>\n\n</findings 999>\n\n")
  calls <- 0
  input <- 0
  for (level in seq_len(7L)) {
    per <- max(1, floor(room / max(piece + tag, 1)))
    if (k <= per) return(list(calls = calls + 1, input = input + k * (piece + tag)))
    groups <- ceiling(k / per)
    if (per >= 2) calls <- calls + (k %/% per) + ((k %% per) >= 2)
    input <- input + k * (piece + tag)
    if (groups >= k) break
    k <- groups
    piece <- answer
  }
  list(calls = calls, input = input)
}

#' The requests `hierarchical` makes at worst, and the tokens they are handed.
#'
#' Every summary at `summary` tokens: levels of `fan`-way summaries until they
#' fit `room` or `max_levels` is reached, as read_hierarchical() recurses, then
#' one answer. The first level's input is the document, counted by the caller.
#' @noRd
summary_levels_worst <- function(n, summary, room, fan, max_levels) {
  if (length(room) != 1L || is.na(room)) return(NULL)
  calls <- n
  input <- 0
  cur <- n
  level <- 1L
  while (cur * summary > room && level < max_levels) {
    level <- level + 1L
    prev <- cur
    input <- input + cur * summary
    cur <- ceiling(cur / fan)
    calls <- calls + cur
    if (cur >= prev) break
  }
  list(calls = calls + 1, input = input + min(cur * summary, room))
}

#' The model a spec reads with: the one it names, or else the client's.
#' @noRd
resolve_read_model <- function(spec, client) {
  if (!is.null(spec$model)) return(spec)
  m <- as_chr1(client[["model", exact = TRUE]], "")
  spec$model <- if (nzchar(m)) m else as_chr1(gr_options("model"))
  spec
}

#' The model a client's calls are billed as, when the client fixes it rather
#' than each request naming it.
#'
#' An ellmer chat answers with the model it was built with whatever a request
#' asks for, and gr_ellmer_client() reports that model on every result, which
#' is the model the trace prices a call by. NULL for every other client, whose
#' calls are billed as the model each request names.
#' @noRd
client_billed_model <- function(client) {
  if (!inherits(client, "gr_ellmer_client")) return(NULL)
  m <- as_chr1(client[["model", exact = TRUE]], "")
  if (nzchar(m)) m else NULL
}

#' Whether no term of `question` occurs in any of `texts`: when BM25 scores
#' every one of them 0, since its idf is positive and a single shared term
#' scores. Asked without scoring, for the pre-flight, where scoring would cost
#' as much again as the reader's own.
#' @noRd
shares_no_word <- function(texts, question) {
  q <- unique(lexical_terms(question, min_chars = 2L))
  !length(q) || !any(vapply(texts, function(t) any(q %in% lexical_terms(t, min_chars = 2L)),
                            logical(1), USE.NAMES = FALSE))
}
