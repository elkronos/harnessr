# core-transport-models.R: model registry and context-budget arithmetic.
#
# WHY THIS FILE EXISTS
# The old `get_model_limits()` was an if/else ladder with three failure modes:
#
#   1. `grepl("gpt-4", model)` swallowed every 128k-context 4-series model into
#      an 8192-token window, over-chunking documents by ~26x.
#   2. Any unrecognised id fell through to `context_window = 4096,
#      output_tokens = 4096`. Since budgets were computed as
#      `context - output - overhead`, unknown models produced a NEGATIVE budget.
#      Downstream, `split(tokens, ceiling(seq_along(tokens) / -54))` reversed the
#      document and `chunk_text_minimal(text, -2000)` emitted one chunk, and
#      therefore one API call, PER WORD.
#   3. The list was hard-coded, so it went stale the day it was written and
#      there was no way for a user to correct it.
#
# The replacement is a data-driven registry with explicit match precedence
# (exact id > alias > family regex > default), user extension via
# `hr_register_model()`, and a budget function that is mathematically incapable
# of returning a non-positive value. It errors with an actionable message
# instead.

# Built-in models: limits only, read from inst/extdata/models.csv at load
# time. harnessr ships no prices because providers change them more often
# than the package is released, and a stale price is worse than none: a
# spending limit would hold the wrong figure. Users set prices with
# hr_register_model() or hr_load_models(). `as_of` is the month the limits
# were last checked. The entries keep the shape they had when they were
# written in R, with `input_usd` and `output_usd` NA. The reading and
# checking is in core-transport-models-file.R.
.gr_seed_models <- function(file = system.file("extdata", "models.csv", package = "harnessr")) {
  models_file_seed(file)
}

# Family patterns, tried in order, only after exact and alias lookup fail.
# Each carries `certain = FALSE` so callers can tell a guess from a fact.
.gr_seed_patterns <- function() {
  list(
    list(pattern = "^gpt-5\\.6",       context_window = 1050000L, max_output = 128000L,
         reasoning = TRUE,  supports_temperature = FALSE),
    list(pattern = "^gpt-5",           context_window =  400000L, max_output = 128000L,
         reasoning = TRUE,  supports_temperature = FALSE),
    list(pattern = "^o[1-9]",          context_window =  200000L, max_output = 100000L,
         reasoning = TRUE,  supports_temperature = FALSE),
    list(pattern = "^gpt-4\\.1",       context_window = 1047576L, max_output =  32768L),
    list(pattern = "^gpt-4o",          context_window =  128000L, max_output =  16384L),
    list(pattern = "^gpt-4-turbo",     context_window =  128000L, max_output =   4096L),
    list(pattern = "^gpt-4",           context_window =    8192L, max_output =   4096L),
    list(pattern = "^gpt-3\\.5",       context_window =   16385L, max_output =   4096L),
    list(pattern = "^text-embedding",  context_window =    8191L, max_output =      0L,
         kind = "embedding", dimensions = 1536L)
  )
}

.gr_aliases <- list(
  "gpt-5.6"     = "gpt-5.6-sol",
  "gpt-4o-2024-08-06"      = "gpt-4o",
  "chatgpt-4o-latest"      = "gpt-4o",
  "gpt-4o-mini-2024-07-18" = "gpt-4o-mini",
  "gpt-3.5-turbo-1106"     = "gpt-3.5-turbo",
  "gpt-3.5-turbo-0125"     = "gpt-3.5-turbo",
  "gpt-3.5-turbo-16k"      = "gpt-3.5-turbo"
)

# Conservative last resort. Deliberately small context but a *proportionate*
# output reserve, so `hr_budget()` can never go negative on this path.
.gr_unknown_model <- list(
  context_window = 128000L, max_output = 4096L, input_usd = NA_real_,
  output_usd = NA_real_, reasoning = FALSE, supports_temperature = TRUE,
  kind = "chat", dimensions = NA_integer_, certain = FALSE, as_of = NA_character_,
  cached_input_usd = NA_real_
)

#' Register a model, or set the prices of a known one
#'
#' Use this to add a model the registry does not know, to correct a built-in
#' entry, or to give a model its prices. harnessr ships each built-in model's
#' limits but no prices, because providers change prices more often than the
#' package is released: cost estimates and the `max_cost_usd` limit use the
#' prices you set here or with [hr_load_models()]. Registered entries take
#' precedence over everything built in.
#'
#' Give both `context_window` and `max_output` to register a model in full:
#' every other argument you leave out takes its default. Leave either limit
#' out to change the model's current entry, built in or registered: the new
#' entry keeps every value you leave out. That is how you price a built-in
#' model without restating its limits.
#'
#' The entry's `as_of`, shown by [hr_models()], is the current month. When you
#' change an entry that has prices without giving new ones, it keeps the
#' month of those prices. When you give only some of its prices, such as
#' `cached_input_usd` alone, the prices you leave out are as old as before, so
#' the entry keeps their month too. An alias such as `"chatgpt-4o-latest"`
#' takes its entry from its target: set the prices on the target. Once prices are older than
#' `hr_options("price_max_age_days")` (120 days by default), the first cost
#' computed from them in a session warns with class `hr_stale_price`.
#'
#' @param id Model id string, exactly as the API expects it.
#' @param context_window Total context window in tokens. Leave it out to keep
#'   the current entry's.
#' @param max_output Maximum tokens the model will emit in one response. Leave
#'   it out to keep the current entry's.
#' @param input_usd,output_usd Price per 1M tokens, in USD; used for cost
#'   estimates and the `max_cost_usd` limit. Give both or neither for a chat
#'   model: one without the other is an error, since a cost with half its
#'   price missing cannot be estimated. An embedding model needs only
#'   `input_usd`. When you change an existing entry, a price you leave out
#'   keeps its current value.
#' @param reasoning Whether this is a reasoning model (affects prompt shape).
#' @param supports_temperature Whether the API accepts `temperature`.
#' @param kind `"chat"` or `"embedding"`.
#' @param dimensions Embedding dimensionality, for `kind = "embedding"`.
#' @param cached_input_usd Price per 1M input tokens the provider served from
#'   its prompt cache, where that is billed at its own rate. `NA` (the
#'   default) prices them as other input tokens, which never undercounts.
#' @return Invisibly, `id`.
#' @seealso [hr_load_models()] to register many models from a file,
#'   [hr_models()] to see the registry, [hr_model_info()] for lookup and its
#'   `certain` flag, [hr_budget()], [hr_estimate_cost()]
#' @family cost and token functions
#' @export
#' @examples
#' hr_register_model("my-local-llama", context_window = 32768, max_output = 4096)
#' hr_model_info("my-local-llama")[c("context_window", "source", "certain")]
#'
#' # Without prices, the cost cap cannot be checked; harnessr says so rather
#' # than assuming the run is free.
#' is.na(hr_estimate_cost("my-local-llama", 1000, 500))
#'
#' # Price a built-in model and keep its limits. The figures are illustrative:
#' # use your provider's current prices.
#' hr_register_model("gpt-4o-mini", input_usd = 0.15, output_usd = 0.60)
#' hr_model_info("gpt-4o-mini")[c("context_window", "input_usd", "output_usd")]
hr_register_model <- function(id, context_window, max_output,
                              input_usd = NA_real_, output_usd = NA_real_,
                              reasoning = FALSE, supports_temperature = TRUE,
                              kind = c("chat", "embedding"), dimensions = NA_integer_,
                              cached_input_usd = NA_real_) {
  if (!missing(kind)) kind <- match.arg(kind)
  if (!is_nonblank(id)) gr_abort("`id` must be a non-empty string.")
  # Only the arguments the caller gave: what is left out is either a default
  # (a full registration) or kept from the current entry (a change to one).
  args <- c("context_window", "max_output", "input_usd", "output_usd", "reasoning",
            "supports_temperature", "kind", "dimensions", "cached_input_usd")
  supplied <- intersect(args, names(as.list(match.call())[-1]))
  env <- environment()
  given <- stats::setNames(lapply(supplied, function(nm) get(nm, envir = env, inherits = FALSE)),
                           supplied)
  # The error names this call, not the helper that found the problem.
  here <- sys.call()
  entry <- tryCatch(model_entry(id, given), gr_error = function(e) {
    e$call <- here
    stop(e)
  })
  registry_set("models", id, entry, state = hr_state)
  invisible(id)
}

#' Look up a model's capabilities
#'
#' Resolution order: user-registered exact id, built-in exact id, alias, family
#' regex, then a conservative default. The returned list always carries
#' `certain`, which is `FALSE` when the answer came from a regex or the default.
#' Treat that as "verify before trusting for cost control".
#'
#' An alias (`"chatgpt-4o-latest"`, say) takes the entry of the model it names,
#' a registered override of that model included, and reports the alias as its
#' `id`. A family-regex match and the default both warn with class
#' `gr_unknown_model`; under `hr_options(unknown_model_action = "error")` both
#' stop instead, because neither id is in the registry.
#'
#' @param model Model id.
#' @return A named list: `id`, `context_window`, `max_output`, `input_usd`,
#'   `output_usd` and `cached_input_usd` (per 1M tokens, used by
#'   [hr_estimate_cost()]), `reasoning`, `supports_temperature`, `kind`,
#'   `dimensions`, `as_of`, `certain`, and
#'   `source` (`"registered"`, `"builtin"`, `"alias"`, `"pattern:..."` or
#'   `"default"`). `certain` is `FALSE` when the answer came from a family regex
#'   or the fallback; verify before relying on it for cost control.
#' @seealso [hr_register_model()], [hr_models()], [hr_budget()]
#' @family cost and token functions
#' @export
#' @examples
#' hr_model_info("gpt-4o")[c("context_window", "max_output", "certain")]
#'
#' # An unrecognised id warns and falls back to conservative limits.
#' suppressWarnings(hr_model_info("some-model-from-next-year")$certain)
hr_model_info <- function(model = NULL) {
  model <- as_chr1(model %||% hr_options("model"))
  if (!nzchar(model)) gr_abort("`model` must be a non-empty string.")

  if (!is.null(hr_state$models[[model]])) {
    return(utils::modifyList(.gr_unknown_model,
                             c(hr_state$models[[model]], list(certain = TRUE, source = "registered"))))
  }
  seeded <- hr_state$seed_models %||% list()
  if (!is.null(seeded[[model]])) {
    return(utils::modifyList(.gr_unknown_model,
                             c(seeded[[model]], list(certain = TRUE, source = "builtin"))))
  }
  # An alias resolves to its target as the target itself would: a registered
  # override first. Looking in the built-ins alone kept charging the stale
  # built-in price for "chatgpt-4o-latest" after hr_register_model("gpt-4o")
  # corrected it, so a spending limit allowed twice the intended spend. The id
  # is set after the merge: c(target, list(id = alias)) held two `id`
  # elements, and the target's won.
  alias <- .gr_aliases[[model]]
  target <- if (!is.null(alias)) hr_state$models[[alias]] %||% seeded[[alias]]
  if (!is.null(target)) {
    out <- utils::modifyList(.gr_unknown_model, target)
    out$id <- model; out$certain <- TRUE; out$source <- "alias"
    return(out)
  }
  action <- hr_options("unknown_model_action")
  for (p in hr_state$model_patterns) {
    if (grepl(p$pattern, model, perl = TRUE)) {
      out <- utils::modifyList(.gr_unknown_model, p[setdiff(names(p), "pattern")])
      out$id <- model; out$certain <- FALSE; out$source <- paste0("pattern:", p$pattern)
      # A family match is a GUESS. Say so: the gpt-4 catch-all assigns an
      # 8192-token window, and silently applying that to a 128k model
      # over-chunks the document by ~20x and multiplies the API calls to match.
      msg <- sprintf(paste0("Model '%s' is not in the registry; matched family pattern '%s' ",
                            "-> %d-token context, %d-token output. Verify with ",
                            "hr_model_info('%s'), and correct it with hr_register_model() ",
                            "if that is wrong."),
                     model, p$pattern, out$context_window, out$max_output, model)
      # The option is "what to do when an id is not in the registry", and a
      # family match is not in the registry either. It used to be read only
      # after the patterns, so a typo such as "gpt-5.6-tera" matched ^gpt-5 and
      # ran under the setting chosen to stop exactly that, with a guessed
      # window and no price, so no enforceable spending limit.
      if (identical(action, "error")) gr_abort(msg, class = "gr_unknown_model")
      gr_warn(msg, class = "gr_unknown_model")
      return(out)
    }
  }
  msg <- sprintf(paste0("Model '%s' is not in the registry. Falling back to a conservative ",
                        "%d-token context with a %d-token output reserve. Register the real ",
                        "limits with hr_register_model('%s', context_window = ..., max_output = ...) ",
                        "so budgets and cost estimates are correct."),
                 model, .gr_unknown_model$context_window, .gr_unknown_model$max_output, model)
  if (identical(action, "error")) gr_abort(msg, class = "gr_unknown_model")
  gr_warn(msg, class = "gr_unknown_model")
  out <- .gr_unknown_model
  out$id <- model; out$source <- "default"
  out
}

#' Context and output limits for a model
#'
#' A two-field convenience wrapper over [hr_model_info()].
#'
#' @param model Model id.
#' @return A list with exactly two elements: `context_window` and
#'   `output_tokens`. (Note the second name differs from [hr_model_info()]'s
#'   `max_output`.)
#' @seealso [hr_model_info()], [hr_budget()]
#' @family cost and token functions
#' @export
#' @examples
#' hr_model_limits("gpt-4o")
hr_model_limits <- function(model = NULL) {
  info <- hr_model_info(model)
  list(context_window = info$context_window, output_tokens = info$max_output)
}

#' List every known model
#' @return A data frame with `id`, `kind`, `context_window`, `max_output`,
#'   `reasoning`, `input_usd_per_1m`, `output_usd_per_1m`, `as_of` and
#'   `cached_input_usd_per_1m`. Built-in models have no prices, so their
#'   price columns are `NA` until you set them. `as_of` is the month a
#'   built-in model's limits were last checked, or the month a registered
#'   entry was recorded; a stale date is a prompt to verify.
#' @seealso [hr_model_info()], [hr_register_model()], [hr_load_models()]
#' @family cost and token functions
#' @export
#' @examples
#' subset(hr_models(), kind == "chat")[, c("id", "context_window", "as_of")]
hr_models <- function() {
  all <- utils::modifyList(hr_state$seed_models %||% list(), hr_state$models %||% list())
  if (!length(all)) return(data.frame())
  df <- do.call(rbind, lapply(names(all), function(nm) {
    e <- utils::modifyList(.gr_unknown_model, all[[nm]])
    data.frame(id = nm, kind = as_chr1(e$kind, NA_character_),
               context_window = as_int1(e$context_window),
               max_output = as_int1(e$max_output), reasoning = isTRUE(e$reasoning),
               input_usd_per_1m = as_num1(e$input_usd),
               output_usd_per_1m = as_num1(e$output_usd),
               as_of = as_chr1(e$as_of, NA_character_),
               cached_input_usd_per_1m = as_num1(e$cached_input_usd),
               stringsAsFactors = FALSE)
  }))
  df <- df[order(df$kind, df$id), , drop = FALSE]
  rownames(df) <- NULL
  df
}

#' Estimate the USD cost of a set of calls
#'
#' @param model Model id.
#' @param input_tokens,output_tokens Token counts (scalars or vectors; vectors
#'   are summed).
#' @param cached_input_tokens How many of `input_tokens` the provider served
#'   from its prompt cache. They are priced at the model's `cached_input_usd`
#'   when it has one, and as other input tokens when it does not.
#' @return A single numeric USD figure, or `NA_real_` when the model has no
#'   pricing in the registry, or no output price and `output_tokens` above zero
#'   (an embedding model's missing output price counts as zero, since it
#'   produces no output tokens). harnessr ships no prices: set them with
#'   [hr_register_model()] or [hr_load_models()]. Treat the figure as an
#'   estimate. When the model's prices are older than
#'   `hr_options("price_max_age_days")` (120 days by default, counted from the
#'   first day of their `as_of` month), the first figure computed from them in
#'   a session warns with class `hr_stale_price`.
#'
#'   With `detail = TRUE`, a one-row data frame instead: `model`, `usd` (the
#'   same figure), `priced` (whether the model has a price), `as_of` (the
#'   month of its prices, `NA` without one) and `certain` (`FALSE` when the
#'   model's registry entry is a family guess or the default; see
#'   [hr_model_info()]).
#' @param detail `FALSE` (the default) for the figure alone; `TRUE` for a
#'   data frame that also says where the prices came from.
#' @seealso [hr_model_info()], [hr_register_model()], [hr_trace_summary()]
#' @family cost and token functions
#' @export
#' @examples
#' # harnessr ships no prices, so a built-in model's cost is NA until you set
#' # them. Not 0: nothing says the run is free.
#' hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#'
#' # Set the prices you pay. These figures are illustrative: use your
#' # provider's current prices, in USD per million tokens.
#' hr_register_model("gpt-4o", input_usd = 2.50, output_usd = 10)
#' hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#'
#' # Where the figure's prices came from.
#' hr_estimate_cost("gpt-4o", 120000, 4000, detail = TRUE)
hr_estimate_cost <- function(model, input_tokens, output_tokens = 0, cached_input_tokens = 0,
                             detail = FALSE) {
  if (!is.logical(detail) || length(detail) != 1L || is.na(detail)) {
    gr_abort("`detail` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  if (detail) {
    usd <- hr_estimate_cost(model, input_tokens, output_tokens, cached_input_tokens)
    return(data.frame(model = as_chr1(model), usd = usd,
                      price_status(as_chr1(model))[c("priced", "as_of", "certain")],
                      stringsAsFactors = FALSE))
  }
  info <- hr_model_info(model)
  if (is.na(info$input_usd)) return(NA_real_)
  # An UNKNOWN token count is not a zero one. `sum(na.rm = TRUE)` made
  # hr_estimate_cost(m, NA, NA) return 0: a run reported as free because
  # nobody knew what it was. That is the same defect gr_read_many() had, and the
  # rule it settled on: a cost that cannot be computed comes back NA so a total
  # cannot quietly omit it. NULL still means none, because a length-zero sum
  # really is zero; it is NA that means "we do not know".
  usable <- function(x) {
    if (!length(x)) return(0)
    v <- suppressWarnings(as.numeric(x))
    if (anyNA(v) || !all(is.finite(v))) NA_real_ else sum(v)
  }
  tin <- usable(input_tokens); tout <- usable(output_tokens)
  if (is.na(tin) || is.na(tout)) return(NA_real_)
  # A missing output price is unknown, not free. `%|z|% 0` priced every reply
  # at $0, so the preflight saw a number and did not warn that the limit was
  # uncheckable, and the trace counted the input alone. Only an embedding
  # model, which has no output tokens to price, gets zero.
  out_usd <- as_num1(info$output_usd)
  if (is.na(out_usd)) {
    if (tout > 0 && !identical(info$kind, "embedding")) return(NA_real_)
    out_usd <- 0
  }
  # Cached input at its own rate only where the model has one; otherwise it
  # stays in the input count, at the full rate. A count above the input is
  # read as all of the input, and an unknown one as none of it.
  cached <- suppressWarnings(usable(cached_input_tokens))
  cached_usd <- as_num1(info$cached_input_usd)
  usd <- if (is.na(cached_usd) || is.na(cached) || cached <= 0) {
    tin / 1e6 * info$input_usd + tout / 1e6 * out_usd
  } else {
    cached <- min(cached, tin)
    (tin - cached) / 1e6 * info$input_usd + cached / 1e6 * cached_usd + tout / 1e6 * out_usd
  }
  # A figure computed from old prices is the one to warn about; NA is not.
  warn_stale_price(model, info)
  usd
}
