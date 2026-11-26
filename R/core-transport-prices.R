# core-transport-prices.R: the warnings about prices.
#
# harnessr ships no prices, so a request to a model with no price is the
# normal case for a new user, and a refusal by default would stop every first
# run under the default spending limit. Such a request is now sent, and the
# governor warns that the spending limit cannot hold it (warn_unpriced_model()).
# The warning is given once per model in a session: a run of a thousand
# requests to one model needs to hear it once.

#' Whether this is the first time in the session that `kind` ("unpriced" or
#' "stale") is warned about for `model`. Records it, so the next call for the
#' same pair returns FALSE.
#' @noRd
price_warning_first <- function(kind, model) {
  seen <- hr_state$price_warned[[kind]] %||% character(0)
  if (model %in% seen) return(FALSE)
  warned <- hr_state$price_warned %||% list()
  warned[[kind]] <- c(seen, model)
  hr_state$price_warned <- warned
  TRUE
}

#' Warn, once per model in a session, that a request to a chat model with no
#' price was sent under a spending limit, which cannot hold it.
#' @noRd
warn_unpriced_model <- function(model, limit) {
  if (!price_warning_first("unpriced", model)) return(invisible(NULL))
  gr_warn(sprintf(paste0(
    "Model '%s' has no price set, so the $%s spending limit (max_cost_usd) does not cover ",
    "its requests: they are sent, and the trace records their cost as NA. Set its prices ",
    "with hr_register_model(input_usd =, output_usd =) or hr_load_models(). Token and call ",
    "limits still apply. hr_options(allow_unpriced = FALSE) refuses such requests instead. ",
    "Shown once per model per session."),
    model, format(limit, scientific = FALSE)),
    class = "hr_unpriced_model", model = model)
}
