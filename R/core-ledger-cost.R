# core-ledger-cost.R: what the calls in a trace cost, by model.

#' What a run actually cost
#'
#' Costs a trace using each step's own model and counting only the calls that
#' were issued: a call served from a [gr_cache()] or a
#' [gr_replay_client()] spent nothing, however many tokens its prompt contained.
#'
#' This is why the token totals on [gr_trace_summary()] are not a bill. They
#' report how large the prompts and replies were, which is the right measure of
#' a run's *shape*; a fully cached re-run has the same shape as the original and
#' cost nothing at all.
#'
#' @param trace A `gr_trace`.
#' @return A data frame with one row per model: `model`, `calls`, `paid_calls`,
#'   `paid_in`, `paid_out`, `usd`. `sum(x$usd)` is the run's cost. A model with
#'   no registered price contributes `NA`, so a total that silently omitted an
#'   unpriced model is impossible. The exception is a model whose every request
#'   failed without sending a token (an embeddings request to an endpoint that
#'   has none, say): that cost nothing, priced or not, so it contributes 0.
#' @seealso [gr_trace_summary()], [gr_estimate_cost()], [gr_cache()],
#'   [gr_read_many()]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ans <- answer_document(readgpt_example(), "What was revenue?", "fast", client = cl)
#' gr_trace_cost(ans$trace)
#'
#' # Priced by the model each step records: a mock's own model, at no cost.
#' # A cached re-run costs nothing for a different reason: paid_calls falls
#' # to zero while calls does not.
#' cache <- gr_cache(file.path(tempdir(), "harnessr-cost-example"))
#' again <- answer_document(readgpt_example(), "What was revenue?", "fast",
#'                          client = gr_cache_client(cl, cache))
#' twice <- answer_document(readgpt_example(), "What was revenue?", "fast",
#'                          client = gr_cache_client(cl, cache))
#' gr_trace_cost(twice$trace)[c("calls", "paid_calls", "usd")]
gr_trace_cost <- function(trace) {
  stopifnot(inherits(trace, "gr_trace"))
  steps <- Filter(function(s) !identical(s$kind, "local") && !is.null(s$tokens), trace$steps)
  if (!length(steps)) {
    return(data.frame(model = character(0), calls = integer(0), paid_calls = integer(0),
                      paid_in = integer(0), paid_out = integer(0), usd = numeric(0),
                      stringsAsFactors = FALSE))
  }
  model <- vapply(steps, function(s) as_chr1(s$model, "unknown"), character(1))
  paid <- !vapply(steps, function(s) isTRUE(s$cached), logical(1))
  # NA, not 0, for a step whose count is unknown -- a trace read back from a
  # file can carry one. Summed, it makes that model's total unknown and its cost
  # NA, which the report renders as a dash. Zero would render as free.
  tin  <- vapply(steps, function(s) as_int1(s$tokens$input, NA_integer_), integer(1))
  tout <- vapply(steps, function(s) as_int1(s$tokens$output, NA_integer_), integer(1))
  # A request that failed and sent no tokens cost nothing whatever its model, as
  # as.data.frame.gr_trace() prices it. An embeddings request to a gateway
  # without embeddings fails like that, usually for an embedding model with no
  # registered price; priced by that model, it made the cost of a run whose
  # every other request was priced unknown, and a corpus's `max_total_usd` a
  # floor. A count that is unknown (NA) is not zero, so it is still priced.
  free <- !vapply(steps, function(s) isTRUE(s$ok), logical(1)) &
    tin %in% 0L & tout %in% 0L

  do.call(rbind, lapply(sort(unique(model)), function(m) {
    i <- model == m
    pin <- sum(tin[i & paid]); pout <- sum(tout[i & paid])
    data.frame(
      model = m, calls = sum(i), paid_calls = sum(i & paid),
      paid_in = as.integer(pin), paid_out = as.integer(pout),
      # Priced over the rest, cached requests included, so a cached request of
      # a model with no price is still NA. Nothing left, nothing to price.
      usd = if (!any(i & !free)) 0
            else tryCatch(as.numeric(gr_estimate_cost(m, pin, pout)),
                          error = function(e) NA_real_,
                          warning = function(w) NA_real_),
      stringsAsFactors = FALSE)
  }))
}

#' A trace's cost in words, for the print methods.
#'
#' One wording everywhere a cost is shown: a model with no registered price
#' makes the total unknown, never zero.
#' @noRd
format_trace_cost <- function(trace) {
  cost <- gr_trace_cost(trace)
  if (!nrow(cost)) return("no cost recorded")
  total <- sum(cost$usd)
  if (is.na(total)) {
    return(sprintf("cost unknown (no registered price for %s)",
                   paste(cost$model[is.na(cost$usd)], collapse = ", ")))
  }
  sprintf("$%.4f across %s", total, paste(cost$model, collapse = ", "))
}
