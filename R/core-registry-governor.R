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
#' may call. [hr_call()], and every reader, judge, adjudication, segmenter and
#' embeddings request in the package, goes through the same check, so a limit
#' holds whether or not the code that makes the call looks at it.
#'
#' A request is checked against its worst case: the most prompt tokens it can
#' be billed for at the model's input price, plus its output cap as sent (for a
#' reasoning model the raised cap; see [hr_call()]) at the output price. The
#' prompt is counted as the trace counts it, with the JSON schema and extra
#' body fields the request carries, a few tokens for each message's framing,
#' and `safety_margin` (see [hr_options()]) on top. One that would take the run
#' past `max_cost_usd` is refused, so a run ends at or under the limit rather
#' than one request over it. That bound rests on two things the governor
#' cannot see: that a provider stops a reply at its cap (a
#' [hr_mock_client()] or [hr_backend_client()] handler that returns more is
#' charged for what it returned), and that the provider counts the prompt
#' within the margin of the local tokenizer. A provider that reports more
#' prompt tokens than that, or a tokenizer far from the provider's (the
#' `"heuristic"` one, say), can leave a run a little over the limit. A run
#' whose requests leave their output cap at the model's limit is stopped while
#' it still has headroom that a smaller cap would have used.
#'
#' A refused request is not sent and is not a call: it adds nothing to the
#' trace's `calls`, steps or spend. It comes back from [hr_call()] as a
#' failed [gr_result] with `refused = TRUE` and an error that names the limit,
#' and a condition of class `hr_budget_refused` is signalled, which a caller
#' can catch with `withCallingHandlers()` or `tryCatch()` to stop instead. The
#' trace records the refusal in `refusals`, sets `budget_stop` and names the
#' limit in `stop_reason`: `"calls"`, `"cost"`, `"tokens"` (the token
#' ceiling), `"output"` (the per-call ceiling), `"model"` (not an allowed
#' model) or `"unpriced"`.
#'
#' A text-generation model with no registered price cannot be held to a
#' spending limit. harnessr ships no prices, so by default
#' (`allow_unpriced = TRUE`) a request to one is sent while `max_cost_usd` is a
#' finite number, and the trace prices it at `NA`, never 0. The first such
#' request to each model in a session warns, with class `hr_unpriced_model`,
#' that the spending limit does not cover the model until you set its prices
#' with [hr_register_model()] or [hr_load_models()]. `max_calls`,
#' `max_tokens_total` and the other limits still apply: `max_tokens_total` is
#' the limit that bounds such a run, since the spending limit cannot. With
#' `allow_unpriced = FALSE` the request is refused instead (a condition of
#' class `hr_unpriced_model` as well as `hr_budget_refused`), for a run in
#' which every request must be priced. An embedding model with no price is
#' neither refused nor warned about here; its requests count against
#' `max_calls` and add nothing to the spend, as [gr_read_many()] warns.
#' [hr_mock_client()] makes no paid requests, so it is never refused or warned
#' about as unpriced. A request an [hr_cache()] answers spends nothing
#' and is checked only against `max_calls`, `max_output_tokens` and
#' `allowed_models`.
#'
#' `max_tokens_total` holds the tokens of the run: the prompt and reply
#' tokens of every call the trace records, cache hits included, and the text
#' sent to be embedded. A request is refused when what the run has used plus
#' its own worst case (prompt as above, reply at its cap) would pass it.
#'
#' A governor is attached to a run with `hr_trace(governor = )`, and then
#' governs the requests recorded into that trace. A stage that keeps a trace
#' of its own and folds it into the one it is given ([gr_read_many()],
#' [gr_claims()], [gr_outline()] and [gr_synthesise()]) holds its requests to
#' that trace's governor, less the calls the given trace has already made and
#' what it has spent and used in tokens, so the governor's limits hold for
#' the run as a whole. Without a governor, `hr_options(max_calls =)` stays a
#' limit per document for [gr_read_many()] and per stage for the others. A
#' trace made without one, including those the package makes for itself,
#' reads the limits from [hr_options()] each time it checks, so changing an
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
#' @section A reserve for the closing call:
#' A reader that works in rounds (the `iterative` reader's steps, the
#' `map_reduce` reader's chunks) makes its answer in one last request. When
#' the rounds use up `max_calls` or `max_cost_usd`, that request is refused,
#' and the rounds already paid for end as not found. `reserve_calls` and
#' `reserve_usd` hold part of each limit back for such a request. An ordinary
#' request is refused once it would reach into the reserve: with
#' `max_calls = 10` and `reserve_calls = 1`, ordinary requests stop at 9
#' calls. A request marked as closing may spend the reserve, up to the limit
#' itself.
#'
#' A request is marked closing by the code that sends it, with
#' `hr_call(closing = TRUE)`. The readers mark their final request: the
#' `iterative` reader's final answer (`iterative.final`), the `map_reduce`
#' reader's last merge (`reduce`), the answer request of the
#' `hierarchical`, `skim`, `preview` and `rerank` readers and of the `refine`
#' reader under `refine_state = "ledger"`, and the `ensemble` reader's
#' adjudication. The `stuff` and `retrieve` readers make one model call each,
#' and the `refine` reader's last revision is its answer otherwise; they mark
#' none. In an ensemble each member's closing
#' request may spend the reserve too, so hold back one call per member and
#' one for the adjudication. You set the reserve; nothing a model returns
#' changes it or marks a request.
#'
#' Both reserves default to 0, which holds nothing back: requests, refusals
#' and cache keys are then what they were before the reserve existed. A
#' reserve larger than its limit is refused with an error of class
#' `hr_bad_reserve`. A reserve with no limit to hold back from (`max_calls`
#' or `max_cost_usd` `NULL`) has no effect. The requests of a parallel batch
#' are ordinary: each worker's share is taken from what is left outside the
#' reserve. Two governors combined (a judge's own and the run's) hold an
#' ordinary request to the lower of the two limits less their reserves, and a
#' closing request to the lower of the two limits.
#'
#' @param allow_unpriced `TRUE` to send requests to models with no registered
#'   price under a spending limit, with a warning once per model per session;
#'   `FALSE` to refuse them.
#' @param reserve_calls Calls held back from `max_calls` for closing requests,
#'   a whole number of 0 or more, at most `max_calls`. 0 holds none back.
#' @param reserve_usd Dollars held back from `max_cost_usd` for closing
#'   requests, 0 or more, at most `max_cost_usd`. 0 holds none back.
#' @return An object of class `hr_governor`: a list of the six limits, plus
#'   `reserve_calls` and `reserve_usd` when either is above 0.
#' @seealso [hr_options()] for the session defaults, [hr_trace()],
#'   [hr_register_model()] to give a model its prices
#' @export
#' @examples
#' cl <- hr_mock_client(function(m, p) "ok")
#' tr <- hr_trace(governor = hr_governor(max_calls = 2))
#' vapply(1:3, function(i) hr_call(cl, "hi", trace = tr)$ok, logical(1))
#' tr$calls
#' tr$stop_reason
#'
#' # A request whose worst case would pass the spending limit is not sent.
#' # The limit needs a price; this one is illustrative, so use your
#' # provider's current prices.
#' hr_register_model("my-priced-model", context_window = 128000, max_output = 4096,
#'                   input_usd = 2.5, output_usd = 10)
#' tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.001))
#' res <- hr_call(cl, "hi", model = "my-priced-model", trace = tr)
#' res$refused
#' res$error
#'
#' # A reserve keeps one call for the closing request.
#' tr <- hr_trace(governor = hr_governor(max_calls = 3, reserve_calls = 1))
#' vapply(1:3, function(i) hr_call(cl, "hi", trace = tr)$ok, logical(1))
#' hr_call(cl, "answer", trace = tr, closing = TRUE)$ok
#' tr$calls
hr_governor <- function(max_calls = hr_options("max_calls"),
                        max_cost_usd = hr_options("max_cost_usd"),
                        max_tokens_total = hr_options("max_tokens_total"),
                        max_output_tokens = hr_options("max_output_tokens"),
                        allowed_models = hr_options("allowed_models"),
                        allow_unpriced = hr_options("allow_unpriced"),
                        reserve_calls = hr_options("reserve_calls"),
                        reserve_usd = hr_options("reserve_usd")) {
  # The same checks as the options, so a governor cannot hold a limit the
  # options would refuse.
  gov <- structure(list(max_calls = check_option("max_calls", max_calls),
                        max_cost_usd = check_option("max_cost_usd", max_cost_usd),
                        max_tokens_total = check_option("max_tokens_total", max_tokens_total),
                        max_output_tokens = check_option("max_output_tokens", max_output_tokens),
                        allowed_models = check_option("allowed_models", allowed_models),
                        allow_unpriced = check_option("allow_unpriced", allow_unpriced)),
                   class = "hr_governor")
  rc <- check_option("reserve_calls", reserve_calls)
  ru <- check_option("reserve_usd", reserve_usd)
  over <- function(reserve, limit, what) {
    lim <- finite_limit(limit)
    if (!is.null(lim) && reserve > lim) {
      gr_abort(sprintf("%s (%s) is larger than %s (%s), so no limit would be left to hold it back from.",
                       what[1], format(reserve, scientific = FALSE), what[2],
                       format(lim, scientific = FALSE)),
               class = c("hr_bad_reserve", "gr_bad_setting"))
    }
  }
  over(rc, gov$max_calls, c("reserve_calls", "max_calls"))
  over(ru, gov$max_cost_usd, c("reserve_usd", "max_cost_usd"))
  # Only when set, so a governor without a reserve, and a trace that saves
  # one, are what they were before the reserve existed.
  if (rc > 0) gov$reserve_calls <- rc
  if (ru > 0) gov$reserve_usd <- ru
  gov
}

#' What a governor holds back for closing requests from one limit: its
#' reserve, at most the limit itself; 0 without one.
#' @noRd
governor_hold <- function(gov, field, limit) {
  r <- as_num1(gov[[field]], 0)
  if (!is.finite(r) || r <= 0 || is.null(limit)) return(0)
  min(r, limit)
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
  if (!is.null(x$reserve_calls)) cat(sprintf("  reserve_calls:     %s\n", lim(x$reserve_calls)))
  if (!is.null(x$reserve_usd)) cat(sprintf("  reserve_usd:       %s\n", lim(x$reserve_usd, "$")))
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
#' the parent's, with the calls the parent has made, what it has spent and
#' what it has used in tokens taken off the run's limits. NULL when the parent
#' has no governor, so the stage reads the options as it always has.
#'
#' The calls taken off are the parent's `calls`, the count the governor checks
#' `max_calls` against (see governor_check()): every request recorded, cache
#' hits, replayed calls and embeddings requests included. `max_calls` used to
#' be left whole, so a stage under `hr_governor(max_calls = 2)` given a trace
#' that had already made 2 calls made a third.
#' @noRd
fork_governor <- function(parent) {
  gov <- if (inherits(parent, "gr_trace")) parent[["governor"]]
  if (!inherits(gov, "hr_governor")) return(NULL)
  cap <- finite_limit(gov$max_calls)
  if (!is.null(cap)) gov$max_calls <- max(cap - as_num1(parent$calls, 0), 0)
  limit <- finite_limit(gov$max_cost_usd)
  if (!is.null(limit)) gov$max_cost_usd <- max(limit - budget_spent(parent), 0)
  tokens <- finite_limit(gov$max_tokens_total)
  if (!is.null(tokens)) gov$max_tokens_total <- max(tokens - tokens_used(parent), 0)
  gov
}

#' A governor that holds a request to both `a` and `b`: the lower of each
#' limit, only the models both allow, and unpriced models only when both
#' allow them. Either may be NULL, and then the other is returned as it is.
#'
#' A reserve is combined so that an ordinary request is held to the lower of
#' the two limits less their reserves, and a closing request to the lower of
#' the two limits: the combined reserve is the difference.
#' @noRd
governor_tighter <- function(a, b) {
  if (!inherits(a, "hr_governor")) return(if (inherits(b, "hr_governor")) b)
  if (!inherits(b, "hr_governor")) return(a)
  out <- a
  for (f in c("max_calls", "max_cost_usd", "max_tokens_total", "max_output_tokens")) {
    lim <- c(finite_limit(a[[f]]), finite_limit(b[[f]]))
    if (length(lim)) out[f] <- list(min(lim))
  }
  for (f in c("calls", "usd")) {
    lf <- if (f == "calls") "max_calls" else "max_cost_usd"
    rf <- paste0("reserve_", f)
    out[rf] <- list(NULL)
    full <- c(finite_limit(a[[lf]]), finite_limit(b[[lf]]))
    if (!length(full)) next
    ordinary <- c(if (!is.null(finite_limit(a[[lf]])))
                    finite_limit(a[[lf]]) - governor_hold(a, rf, finite_limit(a[[lf]])),
                  if (!is.null(finite_limit(b[[lf]])))
                    finite_limit(b[[lf]]) - governor_hold(b, rf, finite_limit(b[[lf]])))
    hold <- min(full) - min(ordinary)
    if (hold > 0) out[rf] <- list(hold)
  }
  models <- list(a$allowed_models, b$allowed_models)
  models <- models[!vapply(models, is.null, logical(1))]
  if (length(models)) out["allowed_models"] <- list(Reduce(intersect, models))
  out$allow_unpriced <- isTRUE(a$allow_unpriced) && isTRUE(b$allow_unpriced)
  out
}

#' What one request could cost at worst: its prompt at the input price and its
#' output cap at the output price. NA when the model has no price.
#' @noRd
worst_case_usd <- function(model, input_tokens, output_tokens) {
  # Only the unknown-model warning is muffled: a stale price is worth hearing
  # the first time a request is priced from it.
  tryCatch(suppressWarnings(as.numeric(hr_estimate_cost(as_chr1(model, "unknown"),
                                                        max(as_num1(input_tokens, 0), 0),
                                                        max(as_num1(output_tokens, 0), 0))),
                            classes = "gr_unknown_model"),
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
  # A closing request may spend the reserve; any other stops short of it.
  closing <- isTRUE(request$closing)
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
        "request was not sent; see hr_options(allowed_models =)"),
        model, paste(allowed, collapse = ", "), label)))
    }
    ceiling <- finite_limit(gov$max_output_tokens)
    if (!is.null(ceiling) && out_tokens > ceiling) {
      return(refuse("output", sprintf(paste0(
        "output ceiling reached: the '%s' request would be sent with an output cap of %s ",
        "tokens, above the %s-token ceiling of hr_options(max_output_tokens =), so it was not ",
        "sent; ask for a smaller max_output"),
        label, format(out_tokens, scientific = FALSE), format(ceiling, scientific = FALSE))))
    }
    cap <- finite_limit(gov$max_calls)
    calls <- if (inherits(trace, "gr_trace")) as_num1(trace$calls, 0) else 0
    hold <- if (closing) 0 else governor_hold(gov, "reserve_calls", cap)
    if (!is.null(cap) && hold > 0 && calls + 1 > cap - hold) {
      return(refuse("calls", sprintf(paste0(
        "call cap reached: the run has made %s of the %s calls it may make, with %s kept ",
        "for closing requests, so the '%s' request was not sent; raise ",
        "hr_options(max_calls =) or lower reserve_calls"),
        format(calls, scientific = FALSE), format(cap, scientific = FALSE),
        format(hold, scientific = FALSE), label)))
    }
    if (!is.null(cap) && calls + 1 > cap) {
      # %s, not %d: max_calls is a whole DOUBLE, and %d refuses one beyond the
      # integer range.
      return(refuse("calls", sprintf(paste0(
        "call cap reached: the run has made %s of the %s calls it may make, so the '%s' ",
        "request was not sent; raise hr_options(max_calls =)"),
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
        "hr_options(max_tokens_total =) or ask for a smaller max_output"),
        label, format(in_tokens + out_tokens, scientific = FALSE),
        format(tokens_used(trace), scientific = FALSE), format(tokens, scientific = FALSE))))
    }
    limit <- finite_limit(gov$max_cost_usd)
    if (is.null(limit)) return(NULL)
    worst <- request$worst_usd %||% worst_case_usd(model, request$input_tokens, out_tokens)
    if (is.na(worst)) {
      if (isTRUE(request$unpriced_ok)) return(NULL)
      if (isTRUE(gov$allow_unpriced)) {
        warn_unpriced_model(model, limit)
        return(NULL)
      }
      return(refuse("unpriced", sprintf(paste0(
        "unpriced model: '%s' has no registered price, so what the '%s' request costs cannot ",
        "be held to the $%s spending limit, and it was not sent. Register its prices with ",
        "hr_register_model(input_usd =, output_usd =) or hr_load_models(), or send it ",
        "unpriced with hr_options(allow_unpriced = TRUE) or hr_governor(allow_unpriced = TRUE)"),
        model, label, format(limit, scientific = FALSE))))
    }
    spent <- budget_spent(trace)
    hold <- if (closing) 0 else governor_hold(gov, "reserve_usd", limit)
    if (hold > 0 && spent + worst > limit - hold + 1e-9) {
      return(refuse("cost", sprintf(paste0(
        "spending limit reached: the '%s' request could cost up to $%s, and the run has spent ",
        "$%s of its $%s limit, with $%s kept for closing requests, so it was not ",
        "sent; raise hr_options(max_cost_usd =) or lower reserve_usd"),
        label, fmt_usd(worst), fmt_usd(spent), format(limit, scientific = FALSE),
        format(hold, scientific = FALSE)), worst = worst))
    }
    # A billionth of a dollar of slack: what a run has spent is a sum of
    # figures rounded to 12 significant digits (usd12()), so a request that
    # fits the limit exactly could otherwise be refused for the rounding.
    if (spent + worst > limit + 1e-9) {
      return(refuse("cost", sprintf(paste0(
        "spending limit reached: the '%s' request could cost up to $%s (up to %s prompt tokens, ",
        "and %s reply tokens at its cap), and the run has spent $%s of its $%s limit, so it ",
        "was not sent; raise hr_options(max_cost_usd =) or ask for a smaller max_output"),
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
#' there is no limit. What is left for ordinary requests, outside the reserve,
#' unless `closing` is TRUE.
#' @noRd
governor_headroom <- function(trace, closing = FALSE) {
  gov <- trace_governor(trace)
  cap <- finite_limit(gov$max_calls)
  limit <- finite_limit(gov$max_cost_usd)
  tokens <- finite_limit(gov$max_tokens_total)
  calls <- if (inherits(trace, "gr_trace")) as_num1(trace$calls, 0) else 0
  hold_calls <- if (closing) 0 else governor_hold(gov, "reserve_calls", cap)
  hold_usd <- if (closing) 0 else governor_hold(gov, "reserve_usd", limit)
  list(calls = if (is.null(cap)) Inf else max(cap - hold_calls - calls, 0),
       usd = if (is.null(limit)) Inf else max(limit - hold_usd - budget_spent(trace), 0),
       tokens = if (is.null(tokens)) Inf else max(tokens - tokens_used(trace), 0))
}

#' May the run make another call?
#'
#' Kept for readers registered with gr_register_reader() that check it before
#' each call, as the 0.6.0 help page told them to. The package's own code no
#' longer calls it: hr_call() refuses a request that would pass a limit, so a
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
    gr_warn(sprintf("%s needs %d calls but the run cap is %s; %s or raise hr_options(max_calls =).",
                    who, n, format(gov$max_calls, scientific = FALSE), advice),
            class = "gr_call_cap")
  } else if (is.finite(room$usd) && room$usd <= 0 && budget_spent(trace) > 0) {
    gr_warn(sprintf(paste0("%s needs %d calls but the run has spent $%s, which reaches the $%s ",
                           "spending limit; raise hr_options(max_cost_usd =)."),
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
#' unpriced models whatever the outcome. When they are allowed, each one not
#' `exempt` is warned about here (warn_unpriced_model()), once per session.
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
  # Allowed: said here, before the first request, with the run's own limit,
  # and once per model per session, as each request's check says it. A mock
  # or a replay is not warned about, since what it answers is not billed.
  if (!isTRUE(exempt)) for (m in out$unpriced) warn_unpriced_model(m, budget)
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
