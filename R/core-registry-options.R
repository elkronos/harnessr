# core-registry-options.R: package-private mutable state and user-facing
# options.
#
# The previous codebase kept its document cache in `.GlobalEnv` under
# `.doc_cache`, which leaked between Shiny sessions and could never be cleared.
# All mutable state now lives in one package-private environment, is namespaced,
# and is individually clearable.

gr_defaults <- list(
  verbose             = TRUE,
  tokenizer           = "heuristic",
  model               = "gpt-5.6-terra",
  embedding_model     = "text-embedding-3-small",
  api_base            = "https://api.openai.com/v1",
  # Extra HTTP headers on every request. A corporate gateway in front of OpenAI
  # and Anthropic rarely takes a plain bearer: Azure OpenAI authenticates with
  # `api-key`, API Management wants a subscription key, and most want a
  # correlation or cost-centre id. Set once here and every client inherits it.
  api_headers         = character(0),
  api                 = "responses",   # "responses" | "chat"
  temperature         = NULL,          # NULL = let the model decide / omit
  max_retries         = 4L,
  retry_pause_base    = 2,
  request_timeout     = 120,
  # Fraction of the context window left unfilled, to absorb tokenizer error.
  safety_margin       = 0.10,
  # Hard floor on how much room is always left for a completion.
  min_output_tokens   = 256L,
  cache_documents     = TRUE,
  cache_embeddings    = TRUE,
  # Where hr_cache() keeps model responses. NULL means a directory under
  # tempdir(), resolved at call time. A package must not write to a user's
  # filesystem unasked, and a literal tempdir() here would be frozen at install
  # time rather than evaluated per session.
  cache_dir           = NULL,
  # Which registered embedder to use. NULL means "whatever the client brought,
  # otherwise api". The meaning is in the value, so restoring a saved option
  # list cannot change which embedder is chosen.
  embedder            = NULL,
  parallel            = FALSE,
  workers             = 4L,
  # Spending limit per run (USD), checked before the run and before every
  # request. NULL = off.
  max_cost_usd        = 5,
  # Refuse to issue more than this many model calls in one run.
  max_calls           = 400L,
  # Most tokens one run may use, prompts, replies and embedded text. NULL =
  # off. The limit that still holds a model with no price.
  max_tokens_total    = NULL,
  # The largest output cap one request may carry. NULL = off.
  max_output_tokens   = NULL,
  # The models a run may call. NULL = any.
  allowed_models      = NULL,
  # Whether a model with no registered price may be called under a spending
  # limit. On: harnessr ships no prices, so off would refuse every request to
  # a built-in model until its prices are set. Each such model is warned
  # about once per session (warn_unpriced_model()).
  allow_unpriced      = TRUE,
  # Prices older than this many days, counted from the first day of their
  # as_of month, warn once per model when a cost is computed from them. NULL =
  # never.
  price_max_age_days  = 120L,
  unknown_model_action = "warn",       # "warn" | "error"
  # Who runs are for and who runs them, recorded on every trace (see
  # hr_trace()). Empty: every field NA unless hr_trace() is given it.
  actor               = list(),
  # Settings that were constants in the code until they were options. Each
  # keeps the constant's value; see .gr_late_options.
  auto_max_tokens     = 50000L,
  auto_room_share     = 0.5,
  reasoning_floor     = 2048L,
  output_reserve_share = 0.25,
  near_verbatim_sim   = 0.90,
  near_verbatim_sim_short = 0.95,
  near_verbatim_short_chars = 40L
)

#' The options that were constants in the code until they were declared, and
#' the options added since that change no request. A trace records them only
#' when one is not its default (config_snapshot()), so a trace made at the
#' defaults reads as it did before they existed; and the ones that change a
#' reply or an answer join the cache and store keys only then
#' (nondefault_options()).
#' @noRd
.gr_late_options <- c("auto_max_tokens", "auto_room_share", "reasoning_floor",
                      "output_reserve_share", "near_verbatim_sim", "near_verbatim_sim_short",
                      "near_verbatim_short_chars", "price_max_age_days")

#' The options among `names` that are not their default, as a named list.
#' Empty at the defaults, so a key built with it is the key built without it.
#' @noRd
nondefault_options <- function(names = .gr_late_options) {
  out <- list()
  for (nm in names) {
    v <- hr_options(nm)
    if (!isTRUE(all.equal(v, gr_defaults[[nm]], check.attributes = FALSE))) out[[nm]] <- v
  }
  out
}

#' What each numeric option is allowed to be, checked where it is SET.
#'
#' Every consumer used to invent its own opinion of a bad value, and the
#' opinions pointed the wrong way. `is.finite(max_cost_usd)` as a guard meant NA
#' or a value read from a config file as text silently removed the cost cap:
#' $710 spent against a $5 ceiling, no warning. The old call-cap check did the same
#' for `max_calls`, and disagreed with `preflight()`, which parsed a character
#' cap and enforced it: one option, two answers. `as.integer(min_output_tokens)`
#' turned 1e10 into NA and `hr_budget()` then raised a bare simpleError.
#'
#' Two kinds, treated differently on purpose. A CEILING (`max_cost_usd`,
#' `max_calls`) is refused when it cannot be compared: falling back to anything
#' would be choosing a limit the user did not set, and every fallback here had
#' meant "no limit". NULL and Inf are the two explicit ways to say "no limit".
#' A TUNING knob keeps its current value, with a warning, when the new one
#' cannot be read, and is clamped into range, as `gr_read_spec()` and
#' `gr_segment_spec()` clamp theirs. `hr_options(workers =
#' parallel::detectCores())` is a normal thing to write, and detectCores() can
#' return NA.
#' @noRd
.gr_option_rules <- list(
  # The ranges are the ones the code that reads each option clamps to:
  # hr_client() for the three request settings, gr_lapply() for `workers`. So
  # a value accepted here is the value used, and a warning's "using N" is true.
  # Each tuning rule says where its default comes from (`evidence`, as an
  # hr_param() does); see the "Where the defaults come from" section of
  # hr_options().
  safety_margin     = list(kind = "tune", lo = 0, hi = 0.5,  whole = FALSE,
                           evidence = list(status = "untested",
                                           source = "Set to absorb local token-count error.")),
  min_output_tokens = list(kind = "tune", lo = 0, hi = 1e6,  whole = TRUE,
                           evidence = list(status = "untested",
                                           source = "Set as a floor for a short reply.")),
  max_retries       = list(kind = "tune", lo = 0, hi = 10,   whole = TRUE,
                           evidence = list(status = "untested",
                                           source = "Set when retries were written.")),
  retry_pause_base  = list(kind = "tune", lo = 0, hi = 60,   whole = FALSE,
                           evidence = list(status = "untested",
                                           source = "Set when retries were written.")),
  request_timeout   = list(kind = "tune", lo = 1, hi = 3600, whole = FALSE,
                           evidence = list(status = "untested",
                                           source = "Set when the HTTP client was written.")),
  workers           = list(kind = "tune", lo = 1, hi = 32,   whole = TRUE,
                           evidence = list(status = "untested",
                                           source = "Set when parallel runs were added.")),
  # NULL is temperature's default ("let the model decide"), so it falls back
  # to NULL; and Inf is out of range for it rather than meaning "no limit",
  # which is the ceilings' meaning and went on the wire as "temperature":"Inf".
  temperature       = list(kind = "tune", lo = 0, hi = 2, whole = FALSE, null_ok = TRUE,
                           evidence = list(status = "untested",
                                           source = "NULL sends none; the model decides.")),
  auto_max_tokens   = list(kind = "tune", lo = 0, hi = 1e7, whole = TRUE,
                           evidence = list(status = "untested", source = paste0(
                             "The constant the code had: about 70 pages of prose, under a ",
                             "twentieth of the default model's window. Not measured."))),
  auto_room_share   = list(kind = "tune", lo = 0, hi = 1, whole = FALSE,
                           evidence = list(status = "untested", source = paste0(
                             "The constant the code had: half the room, the other half for ",
                             "local token-count error. Not measured."))),
  reasoning_floor   = list(kind = "tune", lo = 0, hi = 1e6, whole = TRUE,
                           evidence = list(status = "untested", source = paste0(
                             "The constant the code had, from the observation that a reasoning ",
                             "model can spend a few hundred to a couple of thousand tokens ",
                             "before it replies. Not measured."))),
  output_reserve_share = list(kind = "tune", lo = 0, hi = 0.9, whole = FALSE,
                              evidence = list(status = "untested",
                                              source = "The quarter the code had; not measured.")),
  near_verbatim_sim = list(kind = "tune", lo = 0, hi = 1, whole = FALSE,
                           evidence = list(status = "measured", source = paste0(
                             "From practitioner sources, not tuned. The matcher's error rates at ",
                             "this value were measured on 343 true and 162 false quotations ",
                             "(dev/quote-matcher-rates.R; NEWS, 0.6.0.9000)."))),
  near_verbatim_sim_short = list(kind = "tune", lo = 0, hi = 1, whole = FALSE,
                                 evidence = list(status = "measured", source = paste0(
                                   "From practitioner sources, not tuned; measured with ",
                                   "near_verbatim_sim on the same labelled set."))),
  near_verbatim_short_chars = list(kind = "tune", lo = 0, hi = 1e4, whole = TRUE,
                                   evidence = list(status = "measured", source = paste0(
                                     "From practitioner sources, not tuned; measured with ",
                                     "near_verbatim_sim on the same labelled set."))),
  max_cost_usd      = list(kind = "ceiling", lo = 0, whole = FALSE),
  # lo = 0: "make no calls at all" is a meaningful instruction, and the tests
  # that assert a reader degrades rather than spending use it.
  max_calls         = list(kind = "ceiling", lo = 0, whole = TRUE),
  # lo = 1: a ceiling of 0 tokens would refuse every request, which
  # max_calls = 0 says more plainly.
  max_output_tokens = list(kind = "ceiling", lo = 1, whole = TRUE),
  # lo = 0, as for max_calls: a run that may use no tokens sends nothing.
  max_tokens_total  = list(kind = "ceiling", lo = 0, whole = TRUE),
  # NULL turns the warning off; 3650 days is ten years.
  price_max_age_days = list(kind = "tune", lo = 0, hi = 3650, whole = TRUE, null_ok = TRUE,
                            evidence = list(status = "untested", source = paste0(
                              "A choice, not a measured value: about four months, so prices ",
                              "set once are checked again a few times a year."))),
  # A switch, checked by check_option() itself; listed for its evidence.
  allow_unpriced    = list(kind = "switch",
                           evidence = list(status = "untested", source = paste0(
                             "A choice, not a tuned value: harnessr ships no prices, so FALSE ",
                             "would refuse every request to a built-in model until you set ",
                             "its prices.")))
)

#' @noRd
check_option <- function(name, value) {
  if (identical(name, "actor")) return(check_actor(value))
  if (identical(name, "allowed_models")) {
    if (is.null(value)) return(NULL)
    if (!is.character(value) || !length(value) || anyNA(value) || any(!nzchar(value))) {
      gr_abort(paste0("hr_options(allowed_models = ) must be a character vector of model ids, ",
                      "or NULL for any model."), class = "gr_bad_option")
    }
    return(unique(unname(value)))
  }
  if (identical(name, "allow_unpriced")) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      gr_abort("hr_options(allow_unpriced = ) must be TRUE or FALSE.", class = "gr_bad_option")
    }
    return(value)
  }
  rule <- .gr_option_rules[[name]]
  if (is.null(rule)) return(value)
  what <- function(v) if (is.null(v)) "NULL" else if (length(v) != 1L)
    sprintf("a length-%d value", length(v)) else if (is.na(v)) "NA" else
    sprintf("a %s", class(v)[1])
  usable <- !is.null(value) && length(value) == 1L && is.numeric(value) && !is.na(value)

  if (identical(rule$kind, "ceiling")) {
    if (is.null(value)) return(NULL)
    if (!usable) {
      gr_abort(sprintf(paste0("hr_options(%s = ) must be a single number or NULL, not %s. A limit ",
                              "that cannot be compared is not a limit, so this is refused here ",
                              "rather than ignored later."), name, what(value)),
               class = "gr_bad_option")
    }
    if (value < rule$lo) {
      gr_abort(if (rule$lo == 0) {
        sprintf("hr_options(%s = ) cannot be negative; got %s.", name, format(value))
      } else {
        sprintf("hr_options(%s = ) must be at least %s; got %s.", name, format(rule$lo),
                format(value))
      }, class = "gr_bad_option")
    }
    if (!is.finite(value)) return(Inf)
    # A whole number kept as a DOUBLE. as.integer() is what turned 1e10 into NA.
    return(if (isTRUE(rule$whole)) floor(value) else value)
  }

  # A tuning knob. A number written as text is still a number, as it is for the
  # same settings passed to hr_budget() or a spec constructor.
  if (is.null(value) && isTRUE(rule$null_ok)) return(NULL)
  if (!usable && is.character(value) && length(value) == 1L) {
    parsed <- suppressWarnings(as.numeric(value))
    if (!is.na(parsed)) { value <- parsed; usable <- TRUE }
  }
  if (!usable) {
    # Keep the CURRENT value, not the package default: with safety_margin set
    # to 0.3, a stray NA dropping it to the default 0.1 is the "a missing value
    # pushes the input budget up" defect, moved into the setter.
    cur <- hr_options(name)
    gr_warn(sprintf("hr_options(%s = ) cannot be %s; keeping the current value (%s).",
                    name, what(value), if (is.null(cur)) "NULL" else format(cur)),
            class = "gr_bad_option")
    return(cur)
  }
  out <- min(max(value, rule$lo), rule$hi)
  # `!=`, not identical(): max(4L, 1) is the double 4, and identical(4, 4L) is
  # FALSE, so every integer setting (`workers = 4L`) was reported as out
  # of range.
  if (out != value) {
    gr_warn(sprintf("hr_options(%s = %s) is outside [%s, %s]; using %s.", name, format(value),
                    format(rule$lo), format(rule$hi), format(out)),
            class = "gr_bad_option")
  }
  if (isTRUE(rule$whole)) floor(out) else out
}

#' Get or set package options
#'
#' `hr_options()` with no arguments returns the full option list. Called with
#' a single string it returns that option. Called with `name = value` pairs it
#' sets them and invisibly returns the previous values, so it composes with
#' `on.exit()`.
#'
#' Options are read at *call* time, never captured at load time, so changing an
#' option mid-session affects subsequent runs.
#'
#' @param ... Nothing, a single option name, `name = value` pairs, or a named
#'   list (the form `hr_options()` itself returns, so a saved value can be
#'   restored directly).
#' @return The option list, a single option value, or (when setting) the old
#'   values invisibly.
#'
#' @section Options:
#' \describe{
#'   \item{`verbose` (TRUE)}{Print a line for each ingest, segment and read
#'     stage. In an interactive session, also keep one line up to date with how
#'     many chunks a long read has done and what the run has spent.}
#'   \item{`model` ("gpt-5.6-terra")}{Default chat model. Note the default is a
#'     reasoning model, which does not accept `temperature`.}
#'   \item{`embedding_model` ("text-embedding-3-small")}{Default embedding model.}
#'   \item{`tokenizer` ("heuristic")}{Token counter: `"heuristic"` (conservative,
#'     no dependencies), `"words"`, `"chars"`, `"tiktoken"` (needs reticulate),
#'     or a name registered via [hr_set_tokenizer()].}
#'   \item{`api` ("responses")}{`"responses"` or `"chat"` request shape.}
#'   \item{`api_base` ("https://api.openai.com/v1")}{API root; point this at a
#'     proxy or a compatible endpoint.}
#'   \item{`api_headers` (none)}{Named character vector of extra HTTP headers
#'     sent with every request, for gateways that do not authenticate with a
#'     bearer token. Inherited by every [hr_client()] that does not name its
#'     own; see that function's `headers` argument for the rules.}
#'   \item{`temperature` (NULL)}{Default sampling temperature. `NULL` omits the
#'     field. Dropped automatically for models that reject it. Untested:
#'     `NULL` sends no temperature, so the model decides.}
#'   \item{`max_retries` (4)}{Retries for transient failures. HTTP 400 is never
#'     retried: a malformed request stays malformed. Untested: set when
#'     retries were written, with no measurement behind the number.}
#'   \item{`retry_pause_base` (2)}{Seconds; exponential backoff base.
#'     Untested: set when retries were written.}
#'   \item{`request_timeout` (120)}{Per-request timeout, seconds. Untested:
#'     set when the HTTP client was written.}
#'   \item{`safety_margin` (0.10)}{Fraction of the context window left unused to
#'     absorb tokenizer error. Not a spending cap (see `max_cost_usd`).
#'     Untested: set to absorb the error of counting tokens locally, and not
#'     measured against it.}
#'   \item{`min_output_tokens` (256)}{Floor on the completion room [hr_budget()]
#'     reserves *when `reserve_output` is not given explicitly*. An explicit
#'     `reserve_output` is honoured down to 1, unless it leaves no input room;
#'     then it drops to this floor, as the default reserve does. Untested: set
#'     as a floor for a short reply.}
#'   \item{`cache_documents` (TRUE)}{Cache ingestion per file + settings. The key
#'     covers file size, mtime and every option that changes the output.}
#'   \item{`cache_embeddings` (TRUE)}{Cache embeddings per text + model.}
#'   \item{`embedder` (NULL)}{Which registered embedder to use. `NULL` means the
#'     one the client carries, if any, and otherwise `"api"`. Naming one here
#'     overrides both. See [gr_embedders()]; recording a run with a
#'     *deterministic* embedder is what lets an [hr_replay_client()] reproduce its
#'     chunk ranking.}
#'   \item{`cache_dir` (NULL)}{Directory [hr_cache()] stores model responses in.
#'     `NULL` means a per-session directory under `tempdir()`, which costs
#'     nothing and disappears with the session. Set it to a real path, such as
#'     `tools::R_user_dir("harnessr", "cache")`, to keep responses across
#'     sessions and make a long run resumable.}
#'   \item{`parallel` (FALSE)}{Run per-chunk calls concurrently. Needs the
#'     future and future.apply packages; without them it warns and runs
#'     sequentially.}
#'   \item{`workers` (4)}{Worker processes when `parallel` is TRUE.
#'     Untested: set when parallel runs were added. It does not change
#'     output.}
#'   \item{`max_cost_usd` (5)}{Spending limit per run, in USD. A run whose
#'     reader sends every chunk is refused before it starts when sending them
#'     would cost more than this. Every request is then checked before it is
#'     sent, against what the run has spent plus the most the request could
#'     cost (its prompt, and its reply at the output cap), and one that could
#'     pass the limit is not sent (see [hr_governor()]), so a run ends at or
#'     under the limit with a `partial` answer. With `parallel = TRUE` a reader
#'     that sends batches is also refused before it starts when its worst case,
#'     every reply at its token cap and the price of the dearest model it uses,
#'     would pass the limit, and each worker is held to its share of what is
#'     left. A chat model with no registered price (see [hr_models()]) is
#'     not held by the limit: its requests are sent with a warning, unless
#'     `allow_unpriced` is `FALSE`. Under a limit of 0 a model registered at no
#'     cost runs and one with a price is refused. `NULL` removes the limit.}
#'   \item{`max_calls` (400)}{Hard cap on model calls per run, checked before
#'     every request. A request to an embeddings endpoint (the built-in `"api"`
#'     embedder) counts as one, and is checked and priced against
#'     `max_cost_usd` the same way; an embedding served from the session cache
#'     is free. A request an [hr_cache()] answers counts. `NULL` removes the
#'     cap.}
#'   \item{`max_tokens_total` (NULL)}{Most tokens one run may use: the
#'     prompt and reply tokens of every call, cache hits included, and the
#'     text sent to be embedded. A request is refused when what the run has
#'     used plus its prompt and its reply at the cap would pass it. The limit
#'     that still bounds a run on a model with no price. `NULL` for no
#'     limit.}
#'   \item{`max_output_tokens` (NULL)}{The largest output cap one request may
#'     be sent with. A request with a larger cap (for a reasoning model, the
#'     raised cap [hr_call()] sends) is refused rather than cut down. `NULL`
#'     for no ceiling.}
#'   \item{`allowed_models` (NULL)}{Character vector of the model ids a run
#'     may call, chat and embedding models alike. A request to any other is
#'     refused. `NULL` for any model.}
#'   \item{`allow_unpriced` (TRUE)}{Whether a chat model with no registered price
#'     may be called while `max_cost_usd` is set. On, such a request is sent,
#'     its cost is recorded as unknown (`NA`), and the first request to each
#'     such model in a session warns with class `hr_unpriced_model`. Off, it is
#'     refused with a condition of that class. Untested: harnessr ships no
#'     prices, so off would refuse every built-in model until you set its
#'     prices with [hr_register_model()] or [hr_load_models()].}
#'   \item{`price_max_age_days` (120)}{How old a price may be, in days, before
#'     a cost computed from it warns with class `hr_stale_price`. A price's age
#'     is counted from the first day of its `as_of` month (see [hr_models()]),
#'     and the warning is given once per model per session. Built-in models
#'     have no prices, so it applies to prices you set. `NULL` turns the
#'     warning off. Untested: about four months, so prices set once are
#'     checked again a few times a year.}
#'   \item{`unknown_model_action` ("warn")}{`"warn"` or `"error"` when a model id
#'     is not in the registry.}
#'   \item{`actor` (none)}{A named list (or character vector) of the actor
#'     fields every [hr_trace()] records: `system`, `owner`, `run_by`,
#'     `purpose` and `approved_by`, each one string. A field named here is
#'     recorded on each new trace unless [hr_trace()] is given its own; one
#'     named nowhere is `NA`. Other names are refused with an error of class
#'     `gr_bad_option`.}
#'   \item{`auto_max_tokens` (50000)}{The largest document, in tokens, that
#'     [answer_document()] with `recipe = "auto"` reads with `"fast"` (one
#'     request); a larger one is read with `"thorough"`. Untested: the value
#'     is about 70 pages of prose and under a twentieth of the default model's
#'     window, and nothing has measured where the two recipes' answers
#'     diverge.}
#'   \item{`auto_room_share` (0.5)}{The second condition of that choice: the
#'     document must fill at most this share of the input room [hr_budget()]
#'     leaves on every model of the run. Untested: the other half was left
#'     for the error of counting tokens locally.}
#'   \item{`reasoning_floor` (2048)}{The smallest output cap a request to a
#'     reasoning model is sent with. A smaller cap is raised to it, within the
#'     model's limit and the room the context window leaves, so a short
#'     structured call is not used up by reasoning; `0` turns the raise off.
#'     The trace's `params_sent` records the cap sent. Untested: a reasoning
#'     model can spend a few hundred to a couple of thousand tokens before it
#'     replies, and the value was not measured. A value other than the
#'     default joins the response-cache key and the store key of
#'     [gr_read_many()].}
#'   \item{`output_reserve_share` (0.25)}{The share of the usable window
#'     [hr_budget()] reserves for the reply when no `reserve_output` is given,
#'     between `min_output_tokens` and the model's output limit. It sets the
#'     input room of such a budget. The readers give `max_answer_tokens` as
#'     the reserve, so it does not change how much of a document they fit
#'     in one request. Untested.}
#'   \item{`near_verbatim_sim` (0.90), `near_verbatim_sim_short` (0.95),
#'     `near_verbatim_short_chars` (40)}{The least similarity a quotation of at
#'     least `near_verbatim_short_chars` characters (after normalising), and
#'     one shorter than that, needs for the edit-distance matcher to score it
#'     `near_verbatim` (see [gr_verify_evidence()]). The values come from
#'     practitioner sources and were not tuned; the matcher's error rates at
#'     them were measured on a labelled set of 343 true and 162 false
#'     quotations (see NEWS). The status is recorded only, unless
#'     `accept_near_verbatim = TRUE` (see [gr_read_spec()]). A value other
#'     than the default joins the store key of [gr_read_many()].}
#' }
#'
#' @section Where the defaults come from:
#' The settings listed last above were constants in the code until they were
#' options; each keeps the constant's value. A trace records them, and
#' `price_max_age_days`, (in its options snapshot) only when one is not its
#' default, so a trace made at the defaults reads as it did before they
#' existed. Each tuning setting's entry above (`temperature`, `max_retries`,
#' `retry_pause_base`, `request_timeout`, `safety_margin`,
#' `min_output_tokens`, `workers`, `price_max_age_days` and the settings
#' listed last) says where its default came from, as does `allow_unpriced`'s;
#' "untested" means no measurement backs the value. The other entries are
#' switches, limits and names, which are choices rather than tuned values.
#'
#' @section Checked values:
#' Numeric options are checked when they are set, and the two kinds are treated
#' differently because a wrong value costs different things.
#'
#' The ceilings, `max_cost_usd`, `max_calls`, `max_tokens_total` and
#' `max_output_tokens`, refuse anything that is not a single number of zero or
#' more (one or more for `max_output_tokens`), with an error of class
#' `gr_bad_option`: a limit that cannot be compared is not a limit, and
#' ignoring it spends money. `NULL` and `Inf` both mean "no limit".
#' `allowed_models` must be `NULL` or a character
#' vector of ids, and `allow_unpriced` `TRUE` or `FALSE`.
#'
#' The tuning settings (`safety_margin` \[0, 0.5\], `min_output_tokens`
#' \[0, 1e6\], `max_retries` \[0, 10\], `retry_pause_base` \[0, 60\],
#' `request_timeout` \[1, 3600\], `workers` \[1, 32\], `temperature`
#' \[0, 2\], `auto_max_tokens` \[0, 1e7\], `auto_room_share` \[0, 1\],
#' `reasoning_floor` \[0, 1e6\], `output_reserve_share` \[0, 0.9\],
#' `near_verbatim_sim` and `near_verbatim_sim_short` \[0, 1\],
#' `near_verbatim_short_chars` \[0, 1e4\] and `price_max_age_days`
#' \[0, 3650\]) read a number written as text as that number. A value they cannot
#' read, such as `NA` or `"x"`, warns (`gr_bad_option`) and leaves the current
#' setting unchanged; a value outside the range is clamped into it, with the
#' same warning. Whole-number settings are rounded down. `temperature` also
#' takes `NULL`, its default, and `price_max_age_days` takes `NULL` to turn
#' its warning off.
#'
#' @seealso [hr_register_model()] to correct a model's limits,
#'   [hr_set_tokenizer()], [hr_budget()], [hr_cache()]
#' @export
#' @examples
#' old <- hr_options(verbose = FALSE)
#' hr_options("verbose")
#' hr_options(old)
hr_options <- function(...) {
  args <- list(...)
  merged <- function() {
    out <- gr_defaults
    cur <- as.list(hr_state$options %||% list())
    for (nm in names(cur)) out[nm] <- list(cur[[nm]])
    out
  }
  if (length(args) == 0L) return(merged())
  # Unnamed only: `hr_options(actor = list(owner = "x"))` sets one option
  # whose value is a list, and is not a list of options to restore.
  if (length(args) == 1L && is.null(names(args)) && is.list(args[[1]]) &&
      !is.null(names(args[[1]]))) {
    args <- args[[1]]
  } else if (length(args) == 1L && is.character(args[[1]]) && is.null(names(args))) {
    nm <- args[[1]]
    cur <- merged()
    if (!nm %in% names(cur)) {
      gr_abort(sprintf("Unknown option '%s'. Known options: %s.",
                       nm, paste(names(gr_defaults), collapse = ", ")))
    }
    return(cur[[nm]])
  }
  if (is.null(names(args)) || any(!nzchar(names(args)))) {
    gr_abort("hr_options() setters must be named, e.g. hr_options(model = 'gpt-5.6-terra').")
  }
  unknown <- setdiff(names(args), names(gr_defaults))
  if (length(unknown)) {
    gr_abort(sprintf("Unknown option(s): %s. Known options: %s.",
                     paste(unknown, collapse = ", "), paste(names(gr_defaults), collapse = ", ")))
  }
  for (nm in names(args)) args[nm] <- list(check_option(nm, args[[nm]]))
  cur <- as.list(hr_state$options %||% list())
  # merged(), not modifyList(). modifyList() DELETES a key whose value is NULL.
  # Restoring a saved list stores NULL for `temperature`, `max_cost_usd`,
  # `cache_dir` or `embedder` when they were unset. Once an option had been
  # *stored* as NULL, the returned "old" value came back with the name NA and
  # the next hr_options(old) failed with "Unknown option(s): NA". That is the
  # documented on.exit() pattern breaking on the second use, and it is the same
  # NULL trap the setter below was already fixed for.
  old <- merged()[names(args)]
  # modifyList() DELETES a key whose value is NULL, which silently reverted the
  # option to its default. So `hr_options(max_cost_usd = NULL)`, documented as
  # disabling the cost cap, quietly restored the $5 cap instead. Assign directly
  # so NULL is stored as a value.
  for (nm in names(args)) cur[nm] <- list(args[[nm]])
  hr_state$options <- cur
  invisible(old)
}
