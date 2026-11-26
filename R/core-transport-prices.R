# core-transport-prices.R: the warnings about prices.
#
# harnessr ships no prices, so a request to a model with no price is the
# normal case for a new user, and a refusal by default would stop every first
# run under the default spending limit. Such a request is now sent, and the
# governor warns that the spending limit cannot hold it (warn_unpriced_model()).
# Prices a user sets go out of date as providers change them, so a cost
# computed from prices older than `price_max_age_days` warns too
# (warn_stale_price()). Each warning is given once per model in a session:
# a run of a thousand requests to one model needs to hear it once.

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

#' Raise a price warning. Like gr_warn(), with no call: the function that
#' raised it is internal, and the request or cost it is about is the user's.
#' @noRd
price_warn <- function(msg, class, ...) {
  warning(structure(class = c(class, "gr_warning", "warning", "condition"),
                    list(message = msg, call = NULL, ...)))
  invisible(NULL)
}

#' Today's date, for the age of a price. A function of its own so that tests
#' can move the date with testthat::local_mocked_bindings().
#' @noRd
price_today <- function() Sys.Date()

#' How many days old a price dated `as_of` ("YYYY-MM") is, counted from the
#' first day of that month. NA when `as_of` is not a month.
#' @noRd
price_age_days <- function(as_of, today = price_today()) {
  as_of <- as_chr1(as_of, NA_character_)
  if (is.na(as_of) || !grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", as_of)) return(NA_real_)
  as.numeric(as.Date(today) - as.Date(paste0(as_of, "-01")))
}

#' Warn, once per model in a session, that a request to a chat model with no
#' price was sent under a spending limit, which cannot hold it.
#' @noRd
warn_unpriced_model <- function(model, limit) {
  if (!price_warning_first("unpriced", model)) return(invisible(NULL))
  price_warn(sprintf(paste0(
    "Model '%s' has no price set, so the $%s spending limit (max_cost_usd) does not cover ",
    "its requests: they are sent, and the trace records their cost as NA. Set its prices ",
    "with hr_register_model(input_usd =, output_usd =) or hr_load_models(). Token and call ",
    "limits still apply. hr_options(allow_unpriced = FALSE) refuses such requests instead. ",
    "Shown once per model per session."),
    model, format(limit, scientific = FALSE)),
    class = "hr_unpriced_model", model = model)
}

#' Warn, once per model in a session, that a cost was computed from prices
#' older than hr_options(price_max_age_days =). `info` is the model's registry
#' entry as hr_model_info() returns it; a model with no price, or a price with
#' no month, is never stale.
#' @noRd
warn_stale_price <- function(model, info) {
  max_age <- hr_options("price_max_age_days")
  if (is.null(max_age) || is.na(as_num1(info$input_usd))) return(invisible(NULL))
  age <- price_age_days(info$as_of)
  if (is.na(age) || age <= max_age) return(invisible(NULL))
  if (!price_warning_first("stale", model)) return(invisible(NULL))
  price_warn(sprintf(paste0(
    "The prices of model '%s' are as of %s, %s days ago, more than the %s days of ",
    "hr_options(price_max_age_days =). Check your provider's current prices and set them with ",
    "hr_register_model(input_usd =, output_usd =) or hr_load_models(). ",
    "Shown once per model per session."),
    model, info$as_of, format(age, scientific = FALSE), format(max_age, scientific = FALSE)),
    class = "hr_stale_price", model = model, as_of = info$as_of)
}

# Where a cost's prices came from. Every report of a cost in dollars shows,
# for each model it prices, whether the model has a price, the month of that
# price and whether the registry entry is a fact or a guess, so a reader can
# tell a figure from current prices from one from old prices, and a cost of
# NA from a cost of nothing.

#' For each of `models`: `priced` (whether it has an input price), `as_of`
#' (the month of its prices, `NA` when it has none) and `certain` (whether
#' its registry entry is a fact rather than a family guess or the default).
#' Quiet: a model that is not in the registry is unpriced and not certain,
#' and neither warns nor stops, since the run that used it has already been
#' told.
#' @noRd
price_status <- function(models) {
  models <- as.character(models)
  # Looked up once per model: a trace has a row per request.
  ids <- unique(models)
  rows <- lapply(ids, function(m) {
    info <- tryCatch(suppressWarnings(hr_model_info(m), classes = "gr_unknown_model"),
                     error = function(e) NULL)
    if (is.null(info)) return(list(FALSE, NA_character_, FALSE))
    priced <- !is.na(as_num1(info$input_usd))
    list(priced, if (priced) as_chr1(info$as_of, NA_character_) else NA_character_,
         isTRUE(info$certain))
  })
  at <- match(models, ids)
  data.frame(model = models,
             priced = vapply(rows, function(r) r[[1]], logical(1))[at],
             as_of = vapply(rows, function(r) r[[2]], character(1))[at],
             certain = vapply(rows, function(r) r[[3]], logical(1))[at],
             stringsAsFactors = FALSE)
}

#' One row's price columns for a cost that covers several models: `priced`
#' when every one of them has a price, `as_of` the oldest month among their
#' prices (the one to check first), `certain` when every entry is a fact.
#' All `NA` when the cost covers no model.
#' @noRd
price_summary <- function(models) {
  models <- unique(as.character(models[!is.na(models)]))
  if (!length(models)) {
    return(list(priced = NA, as_of = NA_character_, certain = NA))
  }
  st <- price_status(models)
  months <- st$as_of[st$priced & !is.na(st$as_of)]
  list(priced = all(st$priced),
       as_of = if (length(months)) min(months) else NA_character_,
       certain = all(st$certain))
}

#' "prices as of 2026-11", or "prices as of 2026-08 to 2026-11" when the
#' months differ; "" with none.
#' @noRd
price_as_of_text <- function(months) {
  months <- sort(unique(months[!is.na(months)]))
  if (!length(months)) return("")
  if (length(months) == 1L) return(sprintf("prices as of %s", months))
  sprintf("prices as of %s to %s", months[1], months[length(months)])
}

#' "no price set for a, b (set one with hr_register_model() or
#' hr_load_models())", for the printed cost of a model with no price.
#' @noRd
price_missing_text <- function(models) {
  sprintf("no price set for %s (set one with hr_register_model() or hr_load_models())",
          paste(unique(models), collapse = ", "))
}
