# core-effort-escalate.R: reasoning effort that starts low and is raised for
# the next stage when something went wrong in the last one.
#
# A static map (core-effort-static.R) fixes each stage's effort before the run.
# An escalation policy starts every stage at its base effort and watches what
# the run records: a cut, a reply that is not the JSON asked for, a reply the
# caller names as a sign of trouble, an event the caller reports. At the next
# stage boundary, if one of the triggers fired, that stage is sent at the
# raised effort, once per run unless more raises are allowed. Effort changes
# only at a stage boundary, never part way through a stage, so the requests of
# one stage share an effort (and a provider's prompt cache). Each raise is
# written to the trace, and so is whether the raised stage fired the same
# triggers again.
#
# Nothing here is used unless a policy is passed as a call's `effort`, so a
# run without one records nothing new.

.hr_escalate_triggers <- c("truncated", "parse_failure", "schema_failure", "verify_failed",
                           "not_in_document", "unclear", "disagreement")

#' Reply finish reasons that mean the reply stopped at its cap.
#' @noRd
.hr_cut_off_finish <- c("length", "max_tokens", "max_output_tokens", "incomplete")

#' Reasoning effort that is raised for the next stage when a trigger fires
#'
#' A policy for a call's `effort` ([hr_call()]) or a read's `effort_mode`
#' ([gr_read_spec()]). Every stage starts at `base` (one level, or a map named
#' by call stem, resolved as a static effort is). When a trigger in `on`
#' fired during a stage, the next stage is sent at `to`. The stage after a
#' raised one goes back to `base` unless a trigger fired in the raised stage
#' too and a raise is left: at most `max_escalations` raises happen in one
#' run (one trace), so at the default of 1 it always goes back. A stage is a call label up to its second dot, with a
#' merge level (`.level2`), a summary level (`.L2`) and a judge's order
#' (`.o2`) left off, so `map.answer` and `reduce` are stages and
#' `reduce.level1` belongs to `reduce`.
#'
#' The triggers the core sees for itself are `"truncated"` (a `"truncate"`
#' step of the trace, or a reply cut off at its output cap; a cut made while
#' a stage packs its requests belongs to that stage, including one made
#' before its first request),
#' `"parse_failure"` (a reply to one of harnessr's own structured requests,
#' such as `ctx$call_json()` in a benchmark arm, a judge or a document reader,
#' that is not JSON) and
#' `"schema_failure"` (one that does not fit the schema). [hr_call()] with a
#' `schema` does not parse its reply, so it fires neither: check the reply
#' and report it with [hr_effort_event()]. `replies` names
#' replies that are triggers: a named character vector from trigger to the
#' text a reply starts with, such as `c(not_in_document = "NOT_IN_DOCUMENT")`;
#' such a trigger fires when every request of the stage replied with it.
#' Other triggers (`"verify_failed"`, `"unclear"`, `"disagreement"`, or any
#' name of your own) fire when the caller reports them with
#' [hr_effort_event()].
#'
#' The state lives on the run's trace, so a call without a trace is sent at
#' `base`. Each raise writes an `"effort.escalate"` step naming the triggers,
#' the stage they fired in and the stage raised; when the raised stage ends,
#' an `"effort.resolve"` step says whether it fired the same triggers again.
#' [hr_effort_log()] returns both as a table.
#'
#' @param base The starting effort: one level, or a character vector named
#'   by call stem.
#' @param to The raised effort, one level.
#' @param on The triggers that raise the next stage.
#' @param max_escalations The most raises in one run.
#' @param replies `NULL`, or a named character vector from trigger name to
#'   the text a reply that signals it starts with.
#' @param x An `hr_effort_escalate`.
#' @param ... Ignored.
#' @return An object of class `hr_effort_escalate`.
#' @seealso [hr_effort_event()], [hr_effort_log()], [hr_effort_check()],
#'   [gr_read_spec()] for `effort_mode`
#' @family harness
#' @export
#' @examples
#' pol <- hr_effort_escalate(base = "low", to = "high",
#'                           replies = c(not_in_document = "NOT_IN_DOCUMENT"))
#' pol
#'
#' # A first stage that found nothing raises the second.
#' cl <- hr_mock_client(function(m, p) {
#'   if (identical(p$effort, "low") && grepl("first", m[[1]]$content)) {
#'     return("NOT_IN_DOCUMENT")
#'   }
#'   paste("done at", p$effort)
#' })
#' tr <- hr_trace()
#' hr_call(cl, "first step", model = "gpt-5.6-luna", trace = tr, label = "plan.draft",
#'         effort = pol)$text
#' hr_call(cl, "second step", model = "gpt-5.6-luna", trace = tr, label = "plan.final",
#'         effort = pol)$text
#' hr_effort_log(tr)
hr_effort_escalate <- function(base = "low", to = "high", on = .hr_escalate_triggers,
                               max_escalations = 1L, replies = NULL) {
  base <- check_effort(base, "base")
  if (is.null(base)) gr_abort("`base` must be an effort.", class = "gr_bad_setting")
  if (!is.character(to) || length(to) != 1L || is.na(to) || !nzchar(trimws(to))) {
    gr_abort("`to` must be one effort level, such as \"high\".", class = "gr_bad_setting")
  }
  check_effort(to, "to")
  if (!is.character(on) || !length(on) || anyNA(on) || !all(nzchar(trimws(on)))) {
    gr_abort("`on` must name one or more triggers.", class = "gr_bad_setting")
  }
  ok <- is.numeric(max_escalations) && length(max_escalations) == 1L &&
    !is.na(max_escalations) && max_escalations >= 0 && max_escalations == round(max_escalations)
  if (!ok) gr_abort("`max_escalations` must be one whole number, 0 or more.",
                    class = "gr_bad_setting")
  if (!is.null(replies)) {
    rn <- names(replies)
    if (!is.character(replies) || anyNA(replies) || is.null(rn) || any(!nzchar(rn)) ||
        any(!nzchar(replies))) {
      gr_abort("`replies` must be a character vector of reply texts named by trigger.",
               class = "gr_bad_setting")
    }
  }
  structure(list(base = base, to = to, on = unique(on), max_escalations = as.integer(max_escalations),
                 replies = replies), class = "hr_effort_escalate")
}

#' @rdname hr_effort_escalate
#' @export
print.hr_effort_escalate <- function(x, ...) {
  kn <- names(x$base) %||% rep("", length(x$base))
  base <- ifelse(nzchar(kn), paste0(kn, " = ", x$base), unname(x$base))
  cat("<hr_effort_escalate>\n")
  cat(sprintf("  base: %s; raised to %s for the next stage, at most %d time(s) a run\n",
              paste(base, collapse = ", "), x$to, x$max_escalations))
  cat(sprintf("  on:   %s\n", paste(x$on, collapse = ", ")))
  invisible(x)
}

#' The stage a call label belongs to: up to its second dot, with a merge
#' level, a summary level or a judge's order left off.
#' @noRd
effort_stage <- function(label) {
  label <- sub("\\.(level[0-9]+|L[0-9]+|o[0-9]+)$", "", as_chr1(label, "call"))
  parts <- strsplit(label, ".", fixed = TRUE)[[1]]
  paste(utils::head(parts, 2L), collapse = ".")
}

#' The escalation state of a trace, made on first use.
#' @noRd
effort_state <- function(trace) {
  st <- get0("effort_state", envir = trace, inherits = FALSE)
  if (is.environment(st)) return(st)
  st <- new.env(parent = emptyenv())
  st$stage <- NULL
  st$from <- length(trace$steps) + 1L
  # Cuts are counted from the trace's start: a cut made while the first stage
  # packed its first request belongs to that stage.
  st$cut_from <- 1L
  # Requests already on the trace were sent before the policy saw one: by a
  # batch whose items each had a trace of their own (gr_lapply()), folded in
  # since. They are the stage before this one, from the trace's start.
  reqs <- Filter(function(s) !identical(s$kind, "local") && !identical(s$kind, "embedding"),
                 trace$steps)
  if (length(reqs)) {
    st$stage <- effort_stage(reqs[[length(reqs)]]$label)
    st$from <- 1L
  }
  # A parallel worker's trace carries the run's raised level in its meta, so
  # the requests of a raised stage go out raised whichever process sends them.
  st$raised <- !is.null(trace$meta[["effort_raised", exact = TRUE]])
  st$raised_for <- character(0)
  st$escalations <- 0L
  st$calls <- 0L
  st$log <- list()
  assign("effort_state", st, envir = trace)
  st
}

#' The triggers that fired in a stage. Requests and reported events count
#' from step `from` on. A cut belongs to the stage whose request it was made
#' for: it counts from `cut_from` up to the stage's last request, and a cut
#' after that request was made while the next stage packed its first one.
#' Returns the triggers with attribute `"cut_to"`, the last step counted for
#' cuts.
#' @noRd
effort_fired <- function(trace, from, policy, cut_from = from) {
  steps <- trace$steps
  n <- length(steps)
  is_req <- vapply(steps, function(s) !identical(s$kind, "local") &&
                     !identical(s$kind, "embedding"), logical(1))
  last_req <- if (from <= n) which(is_req & seq_len(n) >= from) else integer(0)
  cut_to <- if (length(last_req)) max(last_req) else from - 1L
  fired <- character(0)
  reqs <- list()
  lo <- min(from, cut_from)
  for (i in seq_len(max(n - lo + 1L, 0L)) + lo - 1L) {
    s <- steps[[i]]
    lab <- as_chr1(s$label, "")
    if (identical(s$kind, "local")) {
      if (identical(lab, "truncate") && i >= cut_from && i <= cut_to) {
        fired <- c(fired, "truncated")
      }
      if (identical(lab, "effort.event") && i >= from) {
        fired <- c(fired, as_chr1(s$detail$event, ""))
      }
      next
    }
    if (i < from) next
    if (identical(s$kind, "embedding")) next
    reqs[[length(reqs) + 1L]] <- s
    if (tolower(as_chr1(s$finish_reason, "")) %in% .hr_cut_off_finish) {
      fired <- c(fired, "truncated")
    }
  }
  rep <- policy$replies
  if (length(rep) && length(reqs)) {
    texts <- trimws(vapply(reqs, function(s) as_chr1(s$response, ""), character(1)))
    for (k in seq_along(rep)) {
      if (all(startsWith(texts, rep[[k]]))) fired <- c(fired, names(rep)[k])
    }
  }
  structure(intersect(unique(fired[nzchar(fired)]), policy$on), cut_to = cut_to)
}

#' The effort one call goes out with under an escalation policy, moving the
#' trace's state across a stage boundary first when the call starts a new
#' stage.
#' @noRd
escalate_effort <- function(policy, label, trace) {
  if (!inherits(trace, "gr_trace")) return(effort_for(policy$base, label))
  st <- effort_state(trace)
  st$replies <- policy$replies
  stage <- effort_stage(label)
  if (is.null(st$stage)) {
    st$stage <- stage
  } else if (!identical(stage, st$stage)) {
    effort_boundary(st, policy, stage, trace)
  }
  st$calls <- st$calls + 1L
  if (isTRUE(st$raised)) policy$to else effort_for(policy$base, label)
}

#' A stage boundary: settle the raise that ended, then raise the next stage
#' when a trigger fired in the one that ended.
#' @noRd
effort_boundary <- function(st, policy, stage, trace) {
  fired <- effort_fired(trace, st$from, policy, st$cut_from %||% st$from)
  cut_to <- attr(fired, "cut_to")
  fired <- as.character(fired)
  if (isTRUE(st$raised) && length(st$log)) {
    k <- length(st$log)
    again <- intersect(st$raised_for, fired)
    st$log[[k]]$resolved <- !length(again)
    st$log[[k]]$calls <- st$calls
    trace_note(trace, "effort.resolve", list(stage = st$stage, triggers = st$raised_for,
                                             resolved = !length(again), calls = st$calls))
  }
  raise <- length(fired) > 0L && st$escalations < policy$max_escalations
  if (raise) {
    st$escalations <- st$escalations + 1L
    st$raised <- TRUE
    st$raised_for <- fired
    st$log[[length(st$log) + 1L]] <- list(after = st$stage, stage = stage,
                                          triggers = paste(fired, collapse = ", "),
                                          to = policy$to, resolved = NA, calls = NA_integer_)
    trace_note(trace, "effort.escalate", list(after = st$stage, stage = stage, triggers = fired,
                                              to = policy$to))
    trace$meta$effort_raised <- policy$to
  } else {
    st$raised <- FALSE
    st$raised_for <- character(0)
    if (!is.null(trace$meta[["effort_raised", exact = TRUE]])) trace$meta$effort_raised <- NULL
  }
  st$stage <- stage
  st$calls <- 0L
  # The cuts after the ended stage's last request were made for this one.
  st$cut_from <- cut_to + 1L
  st$from <- length(trace$steps) + 1L
  invisible(NULL)
}

#' Report a trigger for an effort escalation
#'
#' Records an event a caller detects, such as a quotation that failed
#' verification (`"verify_failed"`), a decision left `"unclear"` or members
#' that disagree (`"disagreement"`), as an `"effort.event"` step of the
#' trace. An [hr_effort_escalate()] policy reads it at the next stage
#' boundary. Nothing is written unless an escalation policy has already sent
#' a request on this trace, so a run without one records nothing new.
#'
#' @param trace A `gr_trace`, or `NULL`.
#' @param event The trigger's name, one string.
#' @param ... Further detail for the step.
#' @return `TRUE` when the event was recorded, invisibly.
#' @seealso [hr_effort_escalate()], [hr_effort_log()]
#' @family harness
#' @export
#' @examples
#' tr <- hr_trace()
#' hr_effort_event(tr, "disagreement")   # no policy has run: nothing recorded
hr_effort_event <- function(trace, event, ...) {
  if (!is.character(event) || length(event) != 1L || is.na(event) || !nzchar(event)) {
    gr_abort("`event` must be one trigger name.", class = "gr_bad_setting")
  }
  if (!inherits(trace, "gr_trace") ||
      !is.environment(get0("effort_state", envir = trace, inherits = FALSE))) {
    return(invisible(FALSE))
  }
  trace_note(trace, "effort.event", c(list(event = event), list(...)))
  invisible(TRUE)
}

#' The effort raises of a run
#'
#' One row per raise an [hr_effort_escalate()] policy made on a trace: `after`
#' (the stage the triggers fired in), `stage` (the stage sent raised),
#' `triggers`, `to` (the raised effort), `calls` (the requests the raised
#' stage sent) and `resolved` (whether the raised stage fired none of the same
#' triggers). A raise whose stage is the last of the run is settled from the
#' trace as it is now.
#'
#' @param trace A `gr_trace`.
#' @return A data frame, with no rows when nothing was raised.
#' @seealso [hr_effort_escalate()], [hr_effort_check()]
#' @family harness
#' @export
#' @examples
#' hr_effort_log(hr_trace())
hr_effort_log <- function(trace) {
  empty <- data.frame(after = character(0), stage = character(0), triggers = character(0),
                      to = character(0), calls = integer(0), resolved = logical(0),
                      stringsAsFactors = FALSE)
  if (!inherits(trace, "gr_trace")) return(empty)
  st <- get0("effort_state", envir = trace, inherits = FALSE)
  if (!is.environment(st) || !length(st$log)) return(empty)
  log <- st$log
  k <- length(log)
  if (is.na(log[[k]]$resolved) && isTRUE(st$raised)) {
    # The run ended in the raised stage: settle it from what it recorded.
    on <- strsplit(log[[k]]$triggers, ", ", fixed = TRUE)[[1]]
    pol <- list(on = on, replies = st$replies)
    again <- intersect(on, as.character(effort_fired(trace, st$from, pol,
                                                     st$cut_from %||% st$from)))
    log[[k]]$resolved <- !length(again)
    log[[k]]$calls <- st$calls
  }
  data.frame(after = vapply(log, function(r) r$after, ""),
             stage = vapply(log, function(r) r$stage, ""),
             triggers = vapply(log, function(r) r$triggers, ""),
             to = vapply(log, function(r) r$to, ""),
             calls = vapply(log, function(r) as_int1(r$calls, NA_integer_), integer(1)),
             resolved = vapply(log, function(r) as.logical(r$resolved), logical(1)),
             stringsAsFactors = FALSE)
}
