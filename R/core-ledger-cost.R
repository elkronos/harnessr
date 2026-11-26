# core-ledger-cost.R: what the calls in a trace cost, by model.

#' What a run actually cost
#'
#' Costs a trace using each step's own model and counting only the calls that
#' were issued: a call served from an [hr_cache()] or a
#' [hr_replay_client()] spent nothing, however many tokens its prompt contained.
#'
#' This is why the token totals on [hr_trace_summary()] are not a bill. They
#' report how large the prompts and replies were, which is the right measure of
#' a run's *shape*; a fully cached re-run has the same shape as the original and
#' cost nothing at all.
#'
#' @param trace A `gr_trace`.
#' @return A data frame with one row per model: `model`, `calls`, `paid_calls`,
#'   `paid_in`, `paid_out`, `usd`, `paid_reasoning`, `paid_cached_in`.
#'   `sum(x$usd)` is the run's cost. `paid_reasoning` and `paid_cached_in` are
#'   the reasoning and cached input tokens the provider reported among
#'   `paid_out` and `paid_in`; cached input is priced at the model's cached
#'   input rate where [hr_register_model()] gave it one. A model with
#'   no registered price contributes `NA`, so a total that silently omitted an
#'   unpriced model is impossible. The exception is a model whose every request
#'   failed without sending a token (an embeddings request to an endpoint that
#'   has none, say): that cost nothing, priced or not, so it contributes 0.
#'
#'   Three more columns say where each row's prices came from: `priced`
#'   (whether the model has a price), `as_of` (the month of its prices, `NA`
#'   without one) and `certain` (`FALSE` when the model's registry entry is a
#'   family guess or the default; see [hr_model_info()]). They describe the
#'   registry when you call this, which is also what `usd` is priced at.
#'   Printed, a trace shows the cost with the month of its prices, and names
#'   each model with no price; a total over models of which some have no
#'   price says it covers only the priced ones.
#' @seealso [hr_trace_summary()], [hr_estimate_cost()], [hr_cache()],
#'   [gr_read_many()]
#' @export
#' @examples
#' cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#' hr_trace_cost(ans$trace)
#'
#' # Priced by the model each step records: a mock's own model, at no cost.
#' # A cached re-run costs nothing for a different reason: paid_calls falls
#' # to zero while calls does not.
#' cache <- hr_cache(file.path(tempdir(), "harnessr-cost-example"))
#' again <- answer_document(gr_example(), "What was revenue?", "fast",
#'                          client = hr_cache_client(cl, cache))
#' twice <- answer_document(gr_example(), "What was revenue?", "fast",
#'                          client = hr_cache_client(cl, cache))
#' hr_trace_cost(twice$trace)[c("calls", "paid_calls", "usd")]
hr_trace_cost <- function(trace) {
  stopifnot(inherits(trace, "gr_trace"))
  steps <- Filter(function(s) !identical(s$kind, "local") && !is.null(s$tokens), trace$steps)
  if (!length(steps)) {
    return(data.frame(model = character(0), calls = integer(0), paid_calls = integer(0),
                      paid_in = integer(0), paid_out = integer(0), usd = numeric(0),
                      paid_reasoning = integer(0), paid_cached_in = integer(0),
                      priced = logical(0), as_of = character(0), certain = logical(0),
                      stringsAsFactors = FALSE))
  }
  model <- vapply(steps, function(s) as_chr1(s$model, "unknown"), character(1))
  paid <- !vapply(steps, function(s) isTRUE(s$cached), logical(1))
  # NA, not 0, for a step whose count is unknown. A trace read back from a
  # file can carry one. Summed, it makes that model's total unknown and its cost
  # NA, which the report renders as a dash. Zero would render as free.
  tin  <- vapply(steps, function(s) as_int1(s$tokens$input, NA_integer_), integer(1))
  tout <- vapply(steps, function(s) as_int1(s$tokens$output, NA_integer_), integer(1))
  # Breakdowns the provider did not report are none, not unknown: they only
  # move part of a known count to another rate.
  treas <- vapply(steps, function(s) as_int1(s$tokens$reasoning, 0L), integer(1))
  tcach <- vapply(steps, function(s) as_int1(s$tokens$cached_input, 0L), integer(1))
  # A request that failed and sent no tokens cost nothing whatever its model, as
  # as.data.frame.gr_trace() prices it. An embeddings request to a gateway
  # without embeddings fails like that, usually for an embedding model with no
  # registered price; priced by that model, it made the cost of a run whose
  # every other request was priced unknown, and a corpus's `max_total_usd` a
  # floor. A count that is unknown (NA) is not zero, so it is still priced.
  free <- !vapply(steps, function(s) isTRUE(s$ok), logical(1)) &
    tin %in% 0L & tout %in% 0L

  models <- sort(unique(model))
  prices <- price_status(models)
  do.call(rbind, lapply(seq_along(models), function(k) {
    m <- models[k]
    i <- model == m
    pin <- sum(tin[i & paid]); pout <- sum(tout[i & paid]); pcach <- sum(tcach[i & paid])
    data.frame(
      model = m, calls = sum(i), paid_calls = sum(i & paid),
      paid_in = as.integer(pin), paid_out = as.integer(pout),
      # Priced over the rest, cached requests included, so a cached request of
      # a model with no price is still NA. Nothing left, nothing to price.
      usd = if (!any(i & !free)) 0
            else tryCatch(as.numeric(hr_estimate_cost(m, pin, pout,
                                                      cached_input_tokens = pcach)),
                          error = function(e) NA_real_,
                          # An unknown model is unpriced. A stale price still
                          # prices the calls, and warns.
                          gr_unknown_model = function(w) NA_real_),
      paid_reasoning = as.integer(sum(treas[i & paid])),
      paid_cached_in = as.integer(pcach),
      # Where the prices came from: added last, so the columns above keep
      # their places.
      priced = prices$priced[k], as_of = prices$as_of[k], certain = prices$certain[k],
      stringsAsFactors = FALSE)
  }))
}

#' A trace's cost in words, for the print methods.
#'
#' One wording everywhere a cost is shown. `trace` is a `gr_trace`, or a data
#' frame with `model` and `usd` columns, as hr_trace_cost() and
#' hr_estimate_cost(detail = TRUE) return. A known total says the month of its
#' prices. A model with no price makes its share unknown, never zero: the line
#' names it and the function that sets a price, and a total over the other
#' models says it covers only them. A priced model whose cost is still unknown
#' has a step with no token count, read back from a file.
#' @noRd
format_trace_cost <- function(trace) {
  cost <- if (inherits(trace, "gr_trace")) hr_trace_cost(trace) else trace
  if (!nrow(cost)) return("no cost recorded")
  if (is.null(cost$priced)) {
    cost <- cbind(cost[setdiff(names(cost), c("as_of", "certain"))],
                  price_status(cost$model)[c("priced", "as_of", "certain")])
  }
  known <- !is.na(cost$usd)
  dated <- price_as_of_text(cost$as_of[known & cost$priced %in% TRUE])
  with_date <- function(txt) if (nzchar(dated)) paste0(txt, ", ", dated) else txt
  if (all(known)) {
    return(with_date(sprintf("$%.4f across %s", sum(cost$usd),
                             paste(cost$model, collapse = ", "))))
  }
  missing <- cost$model[!known & !(cost$priced %in% TRUE)]
  untold <- cost$model[!known & cost$priced %in% TRUE]
  why <- paste(c(if (length(missing)) price_missing_text(missing),
                 if (length(untold)) sprintf("token counts unknown for %s",
                                             paste(untold, collapse = ", "))),
               collapse = "; ")
  if (!any(known)) return(sprintf("cost unknown: %s", why))
  sprintf("$%.4f covers the priced models only (%s); %s", sum(cost$usd[known]),
          with_date(paste(cost$model[known], collapse = ", ")), why)
}
