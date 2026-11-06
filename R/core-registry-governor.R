# core-registry-governor.R: the spending and call limits checked before each
# request.
#
# The limits used to be the readers' to check. Each reader asked
# trace_can_call() before a call, which compared what the run had spent so far
# with the limit and knew nothing of the call about to go out, so a run passed
# the limit by one request, and a call made by code that did not ask (a judge,
# an adjudicator, a script of the user's own) was not limited at all. A model
# with no registered price added nothing to the spend, so the spending limit
# never fired for it. Now the call path asks the governor before every request
# leaves, with what that request could cost at worst, and a request that would
# pass a limit is not sent.

#' Limits on what a run may send
#'
#' A governor holds the limits that every request a run makes is checked
#' against before it is sent: how many calls the run may make, what it may
#' spend, the largest output cap one request may carry, and which models it
#' may call. [gr_call()], and every reader, judge, adjudication, segmenter and
#' embeddings request in the package, goes through the same check, so a limit
#' holds whether or not the code that makes the call looks at it.
#'
#' A request is checked against its worst case: the most prompt tokens it can
#' be billed for at the model's input price, plus its output cap as sent (for a
#' reasoning model the raised cap; see [gr_call()]) at the output price. The
#' prompt is counted as the trace counts it, with the JSON schema and extra
#' body fields the request carries, a few tokens for each message's framing,
#' and `safety_margin` (see [gr_options()]) on top. One that would take the run
#' past `max_cost_usd` is refused, so a run ends at or under the limit rather
#' than one request over it. That bound rests on two things the governor
#' cannot see: that a provider stops a reply at its cap (a
#' [gr_mock_client()] or [gr_backend_client()] handler that returns more is
#' charged for what it returned), and that the provider counts the prompt
#' within the margin of the local tokenizer. A provider that reports more
#' prompt tokens than that, or a tokenizer far from the provider's (the
#' `"heuristic"` one, say), can leave a run a little over the limit. A run
#' whose requests leave their output cap at the model's limit is stopped while
#' it still has headroom that a smaller cap would have used.
#'
#' A refused request is not sent and is not a call: it adds nothing to the
#' trace's `calls`, steps or spend. It comes back from [gr_call()] as a
#' failed [gr_result] with `refused = TRUE` and an error that names the limit,
#' and a condition of class `hr_budget_refused` is signalled, which a caller
#' can catch with `withCallingHandlers()` or `tryCatch()` to stop instead. The
#' trace records the refusal in `refusals`, sets `budget_stop` and names the
#' limit in `stop_reason`: `"calls"`, `"cost"`, `"tokens"` (the token
#' ceiling), `"output"` (the per-call ceiling), `"model"` (not an allowed
#' model) or `"unpriced"`.
#'
#' A text-generation model with no registered price cannot be held to a
#' spending limit, so while `max_cost_usd` is a finite number a request to one
#' is refused (a condition of class `hr_unpriced_model` as well as
#' `hr_budget_refused`), unless `allow_unpriced = TRUE`. With
#' `allow_unpriced = TRUE` the request is sent, the trace prices it at `NA`,
#' never 0, and `max_calls`, `max_tokens_total` and the other limits still
#' apply: `max_tokens_total` is the limit that bounds such a run, since the
#' spending limit cannot. An embedding model with no price is not refused; its
#' requests count against `max_calls` and add nothing to the spend, as
#' [gr_read_many()] warns. [gr_mock_client()] makes no paid requests and is
#' never refused as unpriced. A request a [gr_cache()] answers spends nothing
#' and is checked only against `max_calls`, `max_output_tokens` and
#' `allowed_models`.
#'
#' `max_tokens_total` holds the tokens of the run: the prompt and reply
#' tokens of every call the trace records, cache hits included, and the text
#' sent to be embedded. A request is refused when what the run has used plus
#' its own worst case (prompt as above, reply at its cap) would pass it.
#'
#' A governor is attached to a run with `gr_trace(governor = )`, and then
#' governs the requests recorded into that trace. A stage that keeps a trace
#' of its own and folds it into the one it is given ([gr_read_many()],
#' [gr_claims()], [gr_outline()] and [gr_synthesise()]) holds its requests to
#' that trace's governor, less what the given trace has already spent and
#' used in tokens; `max_calls` stays a limit per document for
#' [gr_read_many()] and per stage for the others, as with the options. A
#' trace made without one, including those the package makes for itself,
#' reads the limits from [gr_options()] each time it checks, so changing an
#' option affects runs that are already going, as it always has.
#'
#' @param max_calls Most requests the run may make, cache hits and embeddings
#'   requests included. `NULL` or `Inf` for no limit.
#' @param max_cost_usd Most the run may spend, in USD. `NULL` or `Inf` for no
#'   limit.
#' @param max_tokens_total Most tokens the run may use, prompts, replies and
#'   embedded text together. `NULL` or `Inf` for no limit.
#' @param max_output_tokens Largest output cap one request may be sent with.
#'   A request with a larger cap is refused, not cut down. `NULL` or `Inf`
#'   for no limit.
#' @param allowed_models Character vector of the model ids the run may call
#'   (chat and embedding models alike), or `NULL` for any.
#' @param allow_unpriced `TRUE` to send requests to models with no registered
#'   price under a spending limit.
#' @return An object of class `hr_governor`: a list of the six limits.
#' @seealso [gr_options()] for the session defaults, [gr_trace()],
#'   [gr_register_model()] to give a model its prices
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "ok")
#' tr <- gr_trace(governor = hr_governor(max_calls = 2))
#' vapply(1:3, function(i) gr_call(cl, "hi", trace = tr)$ok, logical(1))
#' tr$calls
#' tr$stop_reason
#'
#' # A request whose worst case would pass the spending limit is not sent.
#' tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.001))
#' res <- gr_call(cl, "hi", model = "gpt-4o", trace = tr)
#' res$refused
#' res$error
hr_governor <- function(max_calls = gr_options("max_calls"),
                        max_cost_usd = gr_options("max_cost_usd"),
                        max_tokens_total = gr_options("max_tokens_total"),
                        max_output_tokens = gr_options("max_output_tokens"),
                        allowed_models = gr_options("allowed_models"),
                        allow_unpriced = gr_options("allow_unpriced")) {
  # The same checks as the options, so a governor cannot hold a limit the
  # options would refuse.
  structure(list(max_calls = check_option("max_calls", max_calls),
                 max_cost_usd = check_option("max_cost_usd", max_cost_usd),
                 max_tokens_total = check_option("max_tokens_total", max_tokens_total),
                 max_output_tokens = check_option("max_output_tokens", max_output_tokens),
                 allowed_models = check_option("allowed_models", allowed_models),
                 allow_unpriced = check_option("allow_unpriced", allow_unpriced)),
            class = "hr_governor")
}

#' @export
print.hr_governor <- function(x, ...) {
  lim <- function(v, unit = "") if (is.null(v) || !is.finite(v)) "none" else
    paste0(unit, format(v, scientific = FALSE))
  cat("<hr_governor>\n")
  cat(sprintf("  max_calls:         %s\n", lim(x$max_calls)))
  cat(sprintf("  max_cost_usd:      %s\n", lim(x$max_cost_usd, "$")))
  cat(sprintf("  max_tokens_total:  %s\n", lim(x$max_tokens_total)))
  cat(sprintf("  max_output_tokens: %s\n", lim(x$max_output_tokens)))
  cat(sprintf("  allowed_models:    %s\n",
              if (is.null(x$allowed_models)) "any" else paste(x$allowed_models, collapse = ", ")))
  cat(sprintf("  allow_unpriced:    %s\n", isTRUE(x$allow_unpriced)))
  invisible(x)
}

#' The governor a trace's requests are checked against: the one attached to
#' it, or one read from the options now.
#' @noRd
trace_governor <- function(trace) {
  gov <- if (inherits(trace, "gr_trace")) trace[["governor"]]
  if (inherits(gov, "hr_governor")) gov else hr_governor()
}

#' A limit that is set, as a finite number, or NULL.
#' @noRd
finite_limit <- function(x) if (!is.null(x) && length(x) == 1L && is.finite(x)) x else NULL

#' What a run has counted against `max_cost_usd`: what it spent, plus what the
#' calls a replay answered from a recording cost when they were recorded.
#' @noRd
budget_spent <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(0)
  as_num1(trace$spent_usd, 0) + as_num1(trace$replayed_usd, 0)
}

#' What a run has counted against `max_tokens_total`: the prompt and reply
#' tokens of its calls and the text it sent to be embedded.
#' @noRd
tokens_used <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(0)
  as_num1(trace$tokens_in, 0) + as_num1(trace$tokens_out, 0) + as_num1(trace$embed_tokens, 0)
}

#' The governor a stage's own trace is held to when it folds into `parent`:
#' the parent's, with what the parent has already spent and used in tokens
#' taken off the run's limits. `max_calls` is left whole, since such a stage
#' counts its calls apart (see as_parent_trace()). NULL when the parent has no
#' governor, so the stage reads the options as it always has.
#' @noRd
fork_governor <- function(parent) {
  gov <- if (inherits(parent, "gr_trace")) parent[["governor"]]
  if (!inherits(gov, "hr_governor")) return(NULL)
  limit <- finite_limit(gov$max_cost_usd)
  if (!is.null(limit)) gov$max_cost_usd <- max(limit - budget_spent(parent), 0)
  tokens <- finite_limit(gov$max_tokens_total)
  if (!is.null(tokens)) gov$max_tokens_total <- max(tokens - tokens_used(parent), 0)
  gov
}

#' What one request could cost at worst: its prompt at the input price and its
#' output cap at the output price. NA when the model has no price.
#' @noRd
worst_case_usd <- function(model, input_tokens, output_tokens) {
  tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(as_chr1(model, "unknown"),
                                                        max(as_num1(input_tokens, 0), 0),
                                                        max(as_num1(output_tokens, 0), 0)))),
           error = function(e) NA_real_)
}

#' Check a request against the governor before it goes out.
#'
#' model_call() calls it twice: with `stage = "call"` before the request is
#' handed to the client, for the limits that hold whoever answers (the call
#' count, the output ceiling, the allowed models), and with `stage = "send"`
#' once a cache has missed and the request is about to leave, for the
#' spending limit and the unpriced rule, which only a paid request can pass.
#' An embeddings request is checked once, with `stage = "both"`.
#'
#' `request` names `model`, `label`, `input_tokens` and `output_tokens` (the
#' cap as sent), and `unpriced_ok` when the client makes no paid requests (a
#' mock) or `worst_usd` when the client prices the request itself (a replay).
#' Returns NULL when the request may go, or the refusal condition, which the
#' caller records with governor_refuse() and returns with refused_result().
#' @noRd
governor_check <- function(trace, request, stage = c("both", "call", "send")) {
  stage <- match.arg(stage)
  gov <- trace_governor(trace)
  model <- as_chr1(request$model, "unknown")
  label <- as_chr1(request$label, "call")
  out_tokens <- as_num1(request$output_tokens, 0)
  refuse <- function(limit, msg, worst = NA_real_) {
    cls <- c(if (identical(limit, "unpriced")) "hr_unpriced_model",
             if (identical(limit, "model")) "hr_model_not_allowed",
             "hr_budget_refused", "condition")
    structure(class = cls, list(message = msg, call = NULL, limit = limit, label = label,
                                model = model, worst_usd = worst))
  }
  if (stage %in% c("both", "call")) {
    allowed <- gov$allowed_models
    if (!is.null(allowed) && !model %in% allowed) {
      return(refuse("model", sprintf(paste0(
        "model not allowed: '%s' is not among the run's allowed models (%s), so the '%s' ",
        "request was not sent; see gr_options(allowed_models =)"),
        model, paste(allowed, collapse = ", "), label)))
    }
    ceiling <- finite_limit(gov$max_output_tokens)
    if (!is.null(ceiling) && out_tokens > ceiling) {
      return(refuse("output", sprintf(paste0(
        "output ceiling reached: the '%s' request would be sent with an output cap of %s ",
        "tokens, above the %s-token ceiling of gr_options(max_output_tokens =), so it was not ",
        "sent; ask for a smaller max_output"),
        label, format(out_tokens, scientific = FALSE), format(ceiling, scientific = FALSE))))
    }
    cap <- finite_limit(gov$max_calls)
    calls <- if (inherits(trace, "gr_trace")) as_num1(trace$calls, 0) else 0
    if (!is.null(cap) && calls + 1 > cap) {
      # %s, not %d: max_calls is a whole DOUBLE, and %d refuses one beyond the
      # integer range.
      return(refuse("calls", sprintf(paste0(
        "call cap reached: the run has made %s of the %s calls it may make, so the '%s' ",
        "request was not sent; raise gr_options(max_calls =)"),
        format(calls, scientific = FALSE), format(cap, scientific = FALSE), label)))
    }
  }
  if (stage %in% c("both", "send")) {
    tokens <- finite_limit(gov$max_tokens_total)
    in_tokens <- as_num1(request$input_tokens, 0)
    if (!is.null(tokens) && tokens_used(trace) + in_tokens + out_tokens > tokens) {
      return(refuse("tokens", sprintf(paste0(
        "token ceiling reached: the '%s' request could use up to %s tokens (prompt, and reply ",
        "at its cap), and the run has used %s of its %s, so it was not sent; raise ",
        "gr_options(max_tokens_total =) or ask for a smaller max_output"),
        label, format(in_tokens + out_tokens, scientific = FALSE),
        format(tokens_used(trace), scientific = FALSE), format(tokens, scientific = FALSE))))
    }
    limit <- finite_limit(gov$max_cost_usd)
    if (is.null(limit)) return(NULL)
    worst <- request$worst_usd %||% worst_case_usd(model, request$input_tokens, out_tokens)
    if (is.na(worst)) {
      if (isTRUE(request$unpriced_ok) || isTRUE(gov$allow_unpriced)) return(NULL)
      return(refuse("unpriced", sprintf(paste0(
        "unpriced model: '%s' has no registered price, so what the '%s' request costs cannot ",
        "be held to the $%s spending limit, and it was not sent. Register its prices with ",
        "gr_register_model(input_usd =, output_usd =), or send it unpriced with ",
        "gr_options(allow_unpriced = TRUE) or hr_governor(allow_unpriced = TRUE)"),
        model, label, format(limit, scientific = FALSE))))
    }
    spent <- budget_spent(trace)
    # A billionth of a dollar of slack: what a run has spent is a sum of
    # figures rounded to 12 significant digits (usd12()), so a request that
    # fits the limit exactly could otherwise be refused for the rounding.
    if (spent + worst > limit + 1e-9) {
      return(refuse("cost", sprintf(paste0(
        "spending limit reached: the '%s' request could cost up to $%s (up to %s prompt tokens, ",
        "and %s reply tokens at its cap), and the run has spent $%s of its $%s limit, so it ",
        "was not sent; raise gr_options(max_cost_usd =) or ask for a smaller max_output"),
        label, fmt_usd(worst), format(as_num1(request$input_tokens, 0), scientific = FALSE),
        format(out_tokens, scientific = FALSE), fmt_usd(spent),
        format(limit, scientific = FALSE)), worst = worst))
    }
  }
  NULL
}

#' Record a refusal on the trace and signal it.
#'
#' The trace keeps every refusal in `refusals` and marks the run stopped by
#' the limit, so a reader's answer is marked partial as it was when the reader
#' checked the limit itself. The condition is signalled, not raised: with no
#' handler for it, the caller carries on with the refused result.
#' @noRd
governor_refuse <- function(trace, cnd) {
  if (inherits(trace, "gr_trace")) {
    trace$budget_stop <- TRUE
    trace$stop_reason <- cnd$limit
    trace$refusals <- c(trace$refusals, list(list(
      label = cnd$label, model = cnd$model, limit = cnd$limit,
      worst_usd = as_num1(cnd$worst_usd, NA_real_),
      calls = as_int1(trace$calls, 0L), spent_usd = usd12(budget_spent(trace)),
      message = cnd$message)))
  }
  signalCondition(cnd)
  invisible(cnd)
}

#' The failed result a refused request comes back as.
#' @noRd
refused_result <- function(cnd, model) {
  res <- gr_result(FALSE, error = cnd$message, status = 0L, model = model,
                   usage = usage_record(0L, 0L, "counted"), attempts = 0L)
  res$refused <- TRUE
  res$refusal <- cnd
  res
}

#' Whether a result is a request the governor refused.
#' @noRd
is_refused <- function(res) is.list(res) && isTRUE(res[["refused", exact = TRUE]])

#' How much of the run's limits is left: calls, dollars and tokens, Inf where
#' there is no limit.
#' @noRd
governor_headroom <- function(trace) {
  gov <- trace_governor(trace)
  cap <- finite_limit(gov$max_calls)
  limit <- finite_limit(gov$max_cost_usd)
  tokens <- finite_limit(gov$max_tokens_total)
  calls <- if (inherits(trace, "gr_trace")) as_num1(trace$calls, 0) else 0
  list(calls = if (is.null(cap)) Inf else max(cap - calls, 0),
       usd = if (is.null(limit)) Inf else max(limit - budget_spent(trace), 0),
       tokens = if (is.null(tokens)) Inf else max(tokens - tokens_used(trace), 0))
}

#' May the run make another call?
#'
#' Kept for readers registered with gr_register_reader() that check it before
#' each call, as the 0.6.0 help page told them to. The package's own code no
#' longer calls it: gr_call() refuses a request that would pass a limit, so a
#' reader that never asks cannot overspend. It says no when `n` more calls
#' would pass `max_calls` or the run has already spent its limit, and records
#' the stop as it always did.
#' @noRd
trace_can_call <- function(trace, n = 1L) {
  if (is.null(trace) || !inherits(trace, "gr_trace")) return(TRUE)
  if (n > governor_headroom(trace)$calls) {
    trace$budget_stop <- TRUE
    trace$stop_reason <- "calls"
    return(FALSE)
  }
  limit <- finite_limit(trace_governor(trace)$max_cost_usd)
  spent <- budget_spent(trace)
  if (!is.null(limit) && (spent > limit || (spent == limit && spent > 0))) {
    trace$budget_stop <- TRUE
    trace$stop_reason <- "cost"
    return(FALSE)
  }
  TRUE
}

#' A dollar amount for a message: cents when it is at least a cent, and two
#' significant figures below that, so a limit of $0.003 is not reported as
#' being passed by "$0.00".
#' @noRd
fmt_usd <- function(x) {
  x <- as_num1(x, NA_real_)
  if (is.na(x) || !is.finite(x)) return(format(x))
  if (abs(x) >= 0.01) sprintf("%.2f", x) else format(signif(x, 2), scientific = FALSE)
}

#' The limit that stopped a run, by name, for the messages readers leave.
#' @noRd
cap_name <- function(trace) {
  why <- if (inherits(trace, "gr_trace")) as_chr1(trace$stop_reason, "") else ""
  switch(why, cost = "spending limit", unpriced = "spending limit", tokens = "token ceiling",
         output = "output ceiling", model = "model allow-list", "call cap")
}

#' Warn that a batch of `n` requests cannot all be made under the call cap, or
#' that the run has spent its limit, naming the setting that raises it. Only a
#' warning: each request is still checked as it goes out.
#' @noRd
warn_capped_batch <- function(trace, who, n, advice) {
  gov <- trace_governor(trace)
  room <- governor_headroom(trace)
  if (n > room$calls) {
    gr_warn(sprintf("%s needs %d calls but the run cap is %s; %s or raise gr_options(max_calls =).",
                    who, n, format(gov$max_calls, scientific = FALSE), advice),
            class = "gr_call_cap")
  } else if (is.finite(room$usd) && room$usd <= 0 && budget_spent(trace) > 0) {
    gr_warn(sprintf(paste0("%s needs %d calls but the run has spent $%s, which reaches the $%s ",
                           "spending limit; raise gr_options(max_cost_usd =)."),
                    who, n, fmt_usd(budget_spent(trace)),
                    format(gov$max_cost_usd, scientific = FALSE)),
            class = "gr_cost_cap")
  }
  invisible(NULL)
}

#' Whether no request could pass the run's limits now: the call cap is
#' reached, or the spending limit is spent. Records nothing; for a message that
#' says why a step was not taken, not for deciding whether to send one.
#' @noRd
governor_exhausted <- function(trace) {
  room <- governor_headroom(trace)
  room$calls < 1 || (is.finite(room$usd) && room$usd <= 0 && budget_spent(trace) > 0) ||
    room$tokens <= 0
}

#' Check the estimate for a whole run against the governor before it starts.
#'
#' The request check above holds each request to the limits as it goes out.
#' This one runs once, before the first, on the summed cost of the modules a
#' run uses (cost_sum() of their hr_cost()), and says which limit the run as
#' a whole cannot fit, so it is refused before anything is spent rather than
#' stopped part way:
#'
#' - "calls": the expected requests pass `max_calls`.
#' - "calls_worst": a run sent in parallel batches, which cannot be stopped
#'   part way, could pass `max_calls` at worst.
#' - "unpriced": a model has no price and unpriced models are not allowed.
#'   `exempt` is TRUE for a client that sends nothing paid for (a mock) or
#'   prices what it answers itself (a replay).
#' - "spent": the run has already spent its limit.
#' - "zero": the limit is $0 and a model has a price.
#' - "floor": what the run must send at least (`floor_usd`; NULL or NA for
#'   none) passes the limit.
#' - "worst": a parallel run's worst case (`worst_usd`) passes the limit.
#'
#' With `calls_only = TRUE` only the first two are checked, so a caller can
#' refuse a run on its call count before pricing it. `unit_usd` is the price
#' of one input and one output token for each model the run may use, named by
#' model, NA for a model with no price. The caller
#' words the refusal, since it knows what the run is. `unpriced` lists the
#' unpriced models whatever the outcome, for a warning that their cost is not
#' counted.
#' @noRd
governor_run_check <- function(trace, calls, calls_max, parallel = FALSE, calls_only = FALSE,
                               unit_usd = NULL, exempt = FALSE, floor_usd = NULL,
                               worst_usd = NA_real_) {
  gov <- trace_governor(trace)
  cap <- as_num1(gov$max_calls, Inf)
  already <- if (inherits(trace, "gr_trace")) trace$calls else 0L
  out <- list(limit = NA_character_, cap = cap, already = already, budget = gov$max_cost_usd,
              spent = 0, unpriced = character(0), zero_model = NA_character_)
  done <- function(limit) {
    out$limit <- limit
    out
  }
  if (is.finite(cap) && (already + calls) > cap) return(done("calls"))
  if (is.finite(cap) && isTRUE(parallel) && (already + calls_max) > cap) {
    return(done("calls_worst"))
  }
  budget <- gov$max_cost_usd
  if (isTRUE(calls_only) || is.null(budget) || !is.finite(budget)) return(out)
  out$unpriced <- names(unit_usd)[is.na(unit_usd)]
  if (length(out$unpriced) && !isTRUE(gov$allow_unpriced) && !isTRUE(exempt)) {
    return(done("unpriced"))
  }
  spent <- budget_spent(trace)
  out$spent <- spent
  if (spent > 0 && spent >= budget) return(done("spent"))
  priced <- !is.na(unit_usd) & unit_usd > 0
  if (budget <= 0 && any(priced)) {
    out$zero_model <- names(unit_usd)[priced][1]
    return(done("zero"))
  }
  if (!is.null(floor_usd) && !is.na(floor_usd) && spent + floor_usd > budget) {
    return(done("floor"))
  }
  if (isTRUE(parallel) && !is.na(worst_usd) && spent + worst_usd > budget) return(done("worst"))
  out
}
