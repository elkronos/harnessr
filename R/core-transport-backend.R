# core-transport-backend.R: a client that sends calls to a function you supply.

#' Use any function as the model transport
#'
#' Wraps an arbitrary R function as a client. `handler` receives
#' `(messages, params)` and returns a string or a [gr_result]; everything else
#' the package does (context budgeting, cost and call caps, provenance, the
#' run trace, [gr_cache()], [gr_replay_client()], [gr_compare()]) works
#' exactly as it does for the built-in HTTP client.
#'
#' Use it to reach a provider this package does not speak to, a company proxy, a
#' local model, or another R package's client. [gr_ellmer_client()] is this
#' function with an `ellmer` chat object plugged in.
#'
#' @param handler Function of `(messages, params)`. `messages` is a list of
#'   `list(role=, content=)` with roles `"system"`, `"developer"`, `"user"` or
#'   `"assistant"`. `params` carries `model`, `max_output`, `temperature`,
#'   `schema`, `schema_name` and `prompt_tokens`, and `effort` when the call has
#'   a reasoning effort to send (see `effort` in [gr_read_spec()]); passing it
#'   on is the handler's business. Return a single string, or a
#'   [gr_result] for full control over token usage and failure reporting.
#' @param embed Optional function of `(texts, params)` returning a numeric
#'   matrix with one row per input. Without it, readers that embed
#'   (`retrieve`, and the `semantic` segmenter) fall back to hashed lexical
#'   vectors and warn.
#' @param id Stable identity for this backend, used by [gr_cache()] and by
#'   [gr_read_many()]'s `store`. **Read this before setting up a durable cache.**
#'
#'   For [gr_client()] a cache key can be built from the API shape, base URL and
#'   model, because those completely describe what will answer: two clients with
#'   the same three give the same answers today and next month, which is what
#'   makes a cache safe to keep on disk. A backend has none of that (every one
#'   of them is `api = "backend"`, `base_url = "backend://"`), and the thing
#'   that actually answers is an R closure, whose behaviour this package cannot
#'   inspect.
#'
#'   So the default is a fresh id per client object, which is *safe*: two
#'   different handlers can never trade answers. It is also *session-scoped*, so
#'   a cache or store will not be reused by a later session. Pass a stable `id`
#'   to get cross-session reuse. Pass one **only** when the handler does
#'   answer the same way every time, because that is the assertion you are
#'   making. Hashing the closure would not do: two handlers can share a body and
#'   differ in what they captured.
#' @param model,embedding_model Model ids reported to the rest of the package.
#'   If `model` is not in the model registry you will get the usual unknown-model
#'   warning and a conservative context window; [gr_register_model()] fixes that,
#'   and getting it right matters because it is what sizes your chunks.
#' @param max_retries,timeout Recorded on the client for completeness. Retrying
#'   is the backend's business: this package does not retry a handler, because
#'   it cannot know whether the failure was transient.
#' @return An object of class `gr_backend_client`, usable anywhere a
#'   [gr_client()] is, with `$calls()` recording every request made through it.
#'
#' @section Failure is data, not an exception:
#' A handler that raises is caught and reported as a failed [gr_result], the
#' same as an HTTP error, so one bad chunk does not abort a run. A handler that
#' returns `""` is treated as an empty completion, which this package reports as
#' `ok = FALSE` rather than passing `""` downstream as evidence.
#'
#' @seealso [gr_ellmer_client()], [gr_client()], [gr_mock_client()],
#'   [gr_register_model()], [gr_cache_client()]
#' @export
#' @examples
#' # Any function will do. This one is deterministic so the example is too.
#' cl <- gr_backend_client(function(messages, params) {
#'   user <- Filter(function(m) m$role == "user", messages)
#'   sprintf("I was asked %d thing(s) with a %d-token cap.",
#'           length(user), params$max_output)
#' }, model = "my-backend")
#'
#' gr_call(cl, "What was revenue?", max_output = 128L)$text
#'
#' # It composes with everything else: caching, tracing, cost accounting.
#' tr <- gr_trace()
#' invisible(gr_call(cl, "again", trace = tr))
#' gr_trace_summary(tr)[c("calls", "tokens_in", "tokens_out")]
gr_backend_client <- function(handler, embed = NULL, model = "backend-model",
                              embedding_model = "backend-embed", id = NULL,
                              max_retries = 0L, timeout = NULL) {
  if (!is.function(handler)) {
    gr_abort("`handler` must be a function of (messages, params).")
  }
  if (!is.null(embed) && !is.function(embed)) {
    gr_abort("`embed` must be a function of (texts, params), or NULL.")
  }
  log <- new.env(parent = emptyenv())
  log$calls <- list()
  log$embeds <- list()
  structure(list(
    model = as_chr1(model, "backend-model"),
    api = "backend", base_url = "backend://",
    embedding_model = as_chr1(embedding_model, "backend-embed"),
    max_retries = as.integer(clamp(max_retries, 0, 10)),
    retry_pause_base = 0,
    timeout = clamp(timeout %||% gr_options("request_timeout"), 1, 3600),
    extra_body = list(),
    # The identity the cache and corpus-store keys depend on. See `id` above.
    #
    # Named `.client_id` and NOT `.cache_id`: `$` on a list partial-matches, so
    # with a field called `.cache_id` the expression `client$.cache` -- which is
    # how every caller asks whether a cache is attached -- would silently return
    # this id string for any client that has no cache. That is the same
    # partial-matching trap that made `parsed$output` return `output_text` in the
    # previous release, and the only reliable defence is not to create a name
    # that is a prefix of another.
    .client_id = as_chr1(id %||% gr_new_id("backend")),
    handler = handler, embed_handler = embed, .log = log,
    calls  = function() log$calls,
    embeds = function() log$embeds,
    reset  = function() { log$calls <- list(); log$embeds <- list(); invisible(NULL) }
  ), class = c("gr_backend_client", "gr_client"))
}

#' @export
print.gr_backend_client <- function(x, ...) {
  cat(sprintf("<gr_backend_client> model=%s embeddings=%s, %d call(s) made\n",
              x$model, if (is.function(x$embed_handler)) "supplied" else "none (lexical fallback)",
              length(x$.log$calls)))
  invisible(x)
}
