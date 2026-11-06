# core-context-budget.R: how many tokens a call can spend on a document.

#' Compute a usable input-token budget for one model call
#'
#' This is the single arithmetic chokepoint that every prompt-building path in
#' the package must go through. It has three guarantees:
#'
#' * the returned `input` budget is always **strictly positive**;
#' * `input + output <= context_window * (1 - safety_margin)`;
#' * if no positive budget exists, it raises a `gr_budget_error` naming the
#'   parameter to change, rather than returning a negative number that silently
#'   corrupts every downstream `split()` and `while` loop.
#'
#' @param model Model id.
#' @param reserve_output Tokens to reserve for the completion. An explicit value
#'   is clamped to the model's `max_output`. `NULL` reserves
#'   `min(max_output, max(min_output_tokens, usable / 4))`, where `usable` is the
#'   context window after `safety_margin` and `min_output_tokens` is a
#'   [gr_options()] setting (default 256).
#' @param overhead Tokens consumed by system prompts, question text and message
#'   framing that are not part of the document payload.
#' @param safety_margin Fraction of the context window left unused to absorb
#'   tokenizer error. Defaults to the `safety_margin` option; clamped to
#'   \[0, 0.5\].
#' @return A list with `input`, `output`, `context_window`, `overhead`, `margin`
#'   and `certain` (`FALSE` when the model's limits were guessed rather than
#'   known; see [gr_model_info()]).
#' @seealso [gr_model_info()], [gr_estimate_cost()], [gr_count_tokens()]
#' @export
#' @family cost and token functions
#' @examples
#' unlist(gr_budget("gpt-4o", reserve_output = 1024, overhead = 200))
#'
#' # The same question leaves very different room on different models.
#' vapply(c("gpt-4", "gpt-4o", "gpt-5.6-terra"),
#'        function(m) gr_budget(m)$input, numeric(1))
#'
#' # No positive budget is an error naming what to change, never a negative
#' # number that silently reverses the document downstream.
#' tryCatch(gr_budget("gpt-4", overhead = 9000),
#'          gr_budget_error = function(e) conditionMessage(e))
gr_budget <- function(model = NULL, reserve_output = NULL, overhead = 0,
                      safety_margin = NULL) {
  info <- gr_model_info(model)
  ctx <- info$context_window
  # na_default(), not bare clamp(): clamp() maps NA to `lo`, and `lo` here is
  # ZERO margin -- no headroom at all, which is the exact condition the margin
  # exists to prevent. Same defect the `mmr` setting was fixed for, in the one
  # place where it decides whether a prompt fits.
  # The fallback is the SESSION's margin, not a hard-coded 0.10: with
  # gr_options(safety_margin = 0.3) set, an NA argument used to budget at 0.10
  # while omitting the argument budgeted at 0.3, so NA and omission differed
  # and NA pushed the input budget up. The option is validated when set, so it
  # is always a usable number.
  session_margin <- gr_options("safety_margin")
  safety_margin <- clamp_warn(na_default(safety_margin %||% session_margin, session_margin,
                                         "safety_margin"),
                              0, 0.5, "safety_margin", integer = FALSE)
  usable <- floor(ctx * (1 - safety_margin))

  min_out <- as_int1(gr_options("min_output_tokens"), 256L)
  # One number, or text that is one: as_num1() would take the first element of
  # c(100, 9000) and budget the rest as if it were not there.
  one_num <- function(x) if (length(x) == 1L && (is.numeric(x) || is.character(x)))
    suppressWarnings(as.numeric(x)) else NA_real_
  # A reserve that cannot be read takes the default reserve, as NULL does.
  # clamp() mapped NA to its floor -- ONE token -- leaving the answer no room.
  if (!is.null(reserve_output) && is.na(one_num(reserve_output))) {
    gr_warn("`reserve_output` must be a single number of tokens; using the default reserve.",
            class = "gr_bad_setting")
    reserve_output <- NULL
  }
  reserve_output <- if (is.null(reserve_output)) {
    min(info$max_output, max(min_out, floor(usable / 4)))
  } else {
    as.integer(clamp(one_num(reserve_output), 1, info$max_output))
  }
  # `overhead` is the caller's count of the prompt around the excerpts. NULL is
  # none, and a number written as text is that number. A value that cannot be
  # counted -- NA, "abc", a vector -- is refused: budgeting it as zero is the
  # one direction that overruns the window. as_int1() below rather than
  # as.integer(), which turns 3e9 into NA.
  oh <- if (is.null(overhead)) 0 else one_num(overhead)
  if (is.na(oh)) {
    gr_abort(paste0("`overhead` could not be read as a number of tokens. An overhead that cannot ",
                    "be counted would be budgeted as zero, which is the one direction that ",
                    "overruns the context window."), class = "gr_budget_error")
  }
  overhead <- as_int1(clamp(oh, 0, .Machine$integer.max), 0L)

  input <- usable - reserve_output - overhead
  if (input <= 0) {
    # Try shrinking the reserve to the floor before giving up.
    reserve_output <- min(reserve_output, max(min_out, 1L))
    input <- usable - reserve_output - overhead
  }
  if (input <= 0) {
    gr_abort(sprintf(paste0("No positive input budget for model '%s': context %d, usable after a ",
                            "%.0f%% safety margin %d, output reserve %d, fixed overhead %d. ",
                            "Reduce `reserve_output`, shorten the question/system prompt, or use a ",
                            "model with a larger context window."),
                     info$id, ctx, safety_margin * 100, usable, reserve_output, overhead),
             class = "gr_budget_error")
  }
  list(input = as.integer(input), output = as.integer(reserve_output),
       context_window = as.integer(ctx), overhead = overhead, margin = safety_margin,
       certain = isTRUE(info$certain))
}
