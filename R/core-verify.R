# core-verify.R: the words a check can say about its result.
#
# A check of a quotation, a command run as a step and a judge each report a
# status from a fixed list, and a run that did less than it was asked to do
# says so with a degradation code. The lists live here, in the core, so a
# step, a scorer or a report reads them from one place.

#' What a quotation check can find about a quote. The document layer's
#' matcher (doc-verify-match.R) uses these as `.gr_quote_statuses`; the
#' meaning of each is documented there.
#' @noRd
.hr_verify_statuses <- c("verbatim", "near_verbatim", "entailed", "not_entailed",
                         "contradicted", "unverified", "not_checked")

#' What a command step can report: `passed` and `failed` as its parse rule
#' reads the result, `error` when the program could not be run or its result
#' could not be read, `timeout` when it was stopped at its time limit, and
#' `not_run` when nothing was run.
#' @noRd
.hr_command_statuses <- c("passed", "failed", "error", "timeout", "not_run")

#' The codes a result carries in `degradation` when it did less than it was
#' asked to: a command stopped at its time limit, a judge whose orders
#' disagreed.
#' @noRd
.hr_degradation_codes <- c(command_timeout = "command_timeout",
                           judge_inconsistent = "judge_inconsistent")
