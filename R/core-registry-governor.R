# core-registry-governor.R: the spending and call limits checked before each
# request.

#' What a run has counted against `max_cost_usd`: what it spent, plus what the
#' calls a replay answered from a recording cost when they were recorded.
#' @noRd
budget_spent <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(0)
  as_num1(trace$spent_usd, 0) + as_num1(trace$replayed_usd, 0)
}

#' May the run make another call?
#'
#' Strategies consult this before every call. It says no when the call cap would
#' be passed, or when what the run has spent has reached the spending limit, and
#' it records which of the two stopped the run. The old code had no equivalent,
#' which is why a negative token budget could turn into one API call per word
#' with nothing to stop it. The spending limit used to be checked only once,
#' against an estimate that priced every reply at its cap, so a run was refused
#' at an estimate fifty times what it would have cost, and nothing checked what
#' a run that did start went on to spend.
#'
#' The cost of a request is known only once it is made, so a run can pass the
#' limit by what one request costs. A parallel batch is checked before it is
#' sent and not inside it; see gr_lapply() and preflight().
#' @noRd
trace_can_call <- function(trace, n = 1L) {
  if (is.null(trace) || !inherits(trace, "gr_trace")) return(TRUE)
  cap <- gr_options("max_calls")
  if (!is.null(cap) && is.finite(cap) && (trace$calls + n) > cap) {
    trace$budget_stop <- TRUE
    trace$stop_reason <- "calls"
    return(FALSE)
  }
  if (limit_reached(budget_spent(trace), gr_options("max_cost_usd"))) {
    trace$budget_stop <- TRUE
    trace$stop_reason <- "cost"
    return(FALSE)
  }
  TRUE
}

#' Has a run that spent `spent` reached the spending limit `limit`?
#'
#' At or past it, except that spending nothing never reaches a limit: under
#' `max_cost_usd = 0` a model registered at no cost still runs, as it did when
#' the limit was only an estimate, and a priced one is stopped.
#' @noRd
limit_reached <- function(spent, limit) {
  if (is.null(limit) || !is.finite(limit)) return(FALSE)
  spent > limit || (spent == limit && spent > 0)
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
  if (inherits(trace, "gr_trace") && identical(trace$stop_reason, "cost")) "spending limit"
  else "call cap"
}

#' Warn that a batch of `n` requests cannot all be made, naming the limit and
#' the setting that raises it.
#' @noRd
warn_capped_batch <- function(trace, who, n, advice) {
  if (identical(cap_name(trace), "spending limit")) {
    gr_warn(sprintf(paste0("%s needs %d calls but the run has spent $%s, which reaches the $%s ",
                           "spending limit; raise gr_options(max_cost_usd =)."),
                    who, n, fmt_usd(budget_spent(trace)),
                    format(gr_options("max_cost_usd"), scientific = FALSE)),
            class = "gr_cost_cap")
  } else {
    # %s, not %d: max_calls is a whole DOUBLE, and %d refuses one beyond the
    # integer range.
    gr_warn(sprintf("%s needs %d calls but the run cap is %s; %s or raise gr_options(max_calls =).",
                    who, n, format(gr_options("max_calls"), scientific = FALSE), advice),
            class = "gr_call_cap")
  }
}
