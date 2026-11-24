# core-transport-mock.R: a client that answers offline, for tests and examples.

#' A deterministic offline client for tests, demos and dry runs
#'
#' `handler` receives `(messages, params)` and returns either a string or a
#' `gr_result`. Every call is recorded in `$calls()`, so tests can assert on the
#' exact prompts a strategy produced, which is how you prove two reading
#' strategies are actually different.
#'
#' Three things to know about the mock. It registers two model ids
#' (`"mock-model"`, `"mock-embed"`) in the session's model registry the first
#' time it is called, so they appear in [gr_models()] afterwards. Its default
#' handler returns plain text, so readers that need JSON-schema output
#' (`rerank`, `iterative`) take their documented degraded path unless your
#' handler returns valid JSON for those prompts. And [gr_embed()] uses its
#' `embed_handler` unless `gr_options(embedder =)` names a registered embedder
#' (see the `embedder` argument of [gr_embed()]), reporting
#' `embedding_source = "api"`, so an offline run gets semantic-shaped vectors
#' rather than the lexical fallback. A mock embed handler that fails or returns
#' the wrong number of rows is still caught and still degrades, like any other.
#'
#' `mode` makes the mock misbehave the way a provider can, so you can test how
#' your code copes offline. It changes chat replies only; embeddings are left
#' as they are.
#' \describe{
#'   \item{`"bad_json"`}{Every reply is a JSON object cut off part way, so a
#'     request with a JSON schema gets a reply that does not parse.}
#'   \item{`"refuse"`}{Every reply is empty, which [gr_call()] reports as a
#'     failed result with `finish_reason = "empty"`, as it does a refusal from
#'     a provider.}
#'   \item{`"at_cap"`}{Every reply is the handler's, marked as cut off at the
#'     output cap (`finish_reason = "length"`) and billed at the full cap. A
#'     failed [gr_result] from the handler comes back as it is.}
#'   \item{A vector of HTTP status codes}{Call `i` gets the `i`-th status, and
#'     every call after the last gets the last one. A status from 200 to 299
#'     gives the handler's reply; any other gives a failed result with that
#'     status, marked retryable for the statuses the HTTP transport retries
#'     (408, 409, 425, 429, 500, 502, 503 and 504). The mock does
#'     not retry, so each status is one call. `$reset()` starts the sequence
#'     again.}
#' }
#'
#' @param handler Function of `(messages, params)` returning a string or a
#'   [gr_result].
#' @param embed_handler Function of `(texts, params)` returning a numeric matrix
#'   with one row per input.
#' @param mode `NULL` (the default) for replies as the handler gives them, or
#'   one of `"bad_json"`, `"refuse"` and `"at_cap"`, or a vector of HTTP
#'   status codes such as `c(429, 500, 200)`. See Details.
#' @return An object of class `gr_client`, with `$calls()`, `$embeds()` and
#'   `$reset()`.
#' @seealso [gr_client()], [gr_call()], [gr_result], [gr_example()] for a
#'   document to run against
#' @export
#' @examples
#' cl <- gr_mock_client(function(messages, params) "mock answer")
#' gr_call(cl, list(list(role = "user", content = "hi")))$text
#'
#' # `$calls()` is how you prove two reading strategies differ: it records the
#' # exact prompts each one sent.
#' cl$reset()
#' ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 150))
#' invisible(gr_read(ch, "What was revenue?", cl, "skim"))
#' table(vapply(cl$calls(), function(x) x$label, character(1)))
#'
#' # A provider that is rate limited, then fails, then answers.
#' flaky <- gr_mock_client(mode = c(429, 500, 200))
#' vapply(1:3, function(i) gr_call(flaky, "hi")$ok, logical(1))
gr_mock_client <- function(handler = NULL, embed_handler = NULL, mode = NULL) {
  mode <- mock_mode(mode)
  # Registered so the mock does not trip the unknown-model warning on every call.
  if (is.null(hr_state$models[["mock-model"]])) {
    gr_register_model("mock-model", context_window = 128000L, max_output = 16384L,
                      input_usd = 0, output_usd = 0)
    gr_register_model("mock-embed", context_window = 8191L, max_output = 0L,
                      input_usd = 0, output_usd = 0, kind = "embedding", dimensions = 64L)
  }
  log <- new.env(parent = emptyenv())
  log$calls <- list()
  log$embeds <- list()
  handler <- handler %||% function(messages, params) "mock answer"
  if (!is.null(mode)) {
    log$mode_calls <- 0L
    handler <- mock_mode_handler(handler, mode, log)
  }
  embed_handler <- embed_handler %||% function(texts, params) {
    # Deterministic, content-derived pseudo-embeddings. Unlike the old
    # `set.seed(nchar(text)); runif(768)`, these depend on the *characters*, so
    # two different texts of equal length do not collide, and no global RNG is
    # touched.
    t(vapply(texts, function(tx) {
      b <- utf8ToInt(enc2utf8(as_chr1(tx, " ")))
      v <- numeric(64)
      for (i in seq_along(b)) v[(b[i] %% 64L) + 1L] <- v[(b[i] %% 64L) + 1L] + 1
      n <- sqrt(sum(v^2)); if (n == 0) v else v / n
    }, numeric(64), USE.NAMES = FALSE))
  }
  client <- structure(list(
    model = "mock-model", api = "mock", base_url = "mock://", embedding_model = "mock-embed",
    max_retries = 0L, retry_pause_base = 0, timeout = 1, extra_body = list(),
    # See gr_backend_client() for why a closure-backed client carries an id.
    .client_id = gr_new_id("mock"),
    handler = handler, embed_handler = embed_handler, .log = log,
    calls  = function() log$calls,
    embeds = function() log$embeds,
    reset  = function() {
      log$calls <- list()
      log$embeds <- list()
      if (!is.null(log$mode_calls)) log$mode_calls <- 0L
      invisible(NULL)
    }
  ), class = c("gr_mock_client", "gr_client"))
  # Only a client given a mode carries one, so a default mock has the fields
  # it always had.
  if (!is.null(mode)) client$mode <- mode
  client
}

#' Check a mock's `mode`: NULL, one of the named modes, or HTTP status codes
#' as whole numbers from 100 to 599.
#' @noRd
mock_mode <- function(mode) {
  if (is.null(mode)) return(NULL)
  named <- c("bad_json", "refuse", "at_cap")
  if (is.character(mode) && length(mode) == 1L && !is.na(mode) && mode %in% named) return(mode)
  if (is.numeric(mode) && length(mode) && !anyNA(mode) && all(mode == round(mode)) &&
      all(mode >= 100 & mode <= 599)) {
    return(as.integer(mode))
  }
  gr_abort(sprintf(paste0("`mode` must be NULL, one of %s, or a vector of HTTP status codes ",
                          "from 100 to 599, such as c(429, 500, 200)."),
                   paste0("\"", named, "\"", collapse = ", ")),
           class = "gr_bad_setting")
}

#' The handler a mock with a mode calls: `handler` wrapped so that its reply
#' is broken the way `mode` says. `log$mode_calls` counts the calls, for a
#' status sequence.
#' @noRd
mock_mode_handler <- function(handler, mode, log) {
  force(handler)
  force(mode)
  function(messages, params) {
    log$mode_calls <- log$mode_calls + 1L
    if (is.numeric(mode)) {
      status <- mode[min(log$mode_calls, length(mode))]
      if (status < 200L || status > 299L) {
        return(gr_result(FALSE, error = sprintf("HTTP %d from the mock client", status),
                         status = status, retryable = status %in% .retryable_status))
      }
      return(handler(messages, params))
    }
    switch(mode,
      bad_json = "{\"answer\": \"Revenue was 45.2 million",
      refuse = "",
      at_cap = {
        out <- handler(messages, params)
        # A failed reply stays failed: only a reply can be cut off at the cap.
        if (inherits(out, "gr_result") && !isTRUE(out$ok)) return(out)
        text <- if (inherits(out, "gr_result")) out$text else as_chr1(out, "")
        cap <- as_int1(params$max_output, NA_integer_)
        output <- if (is.na(cap)) sum(gr_count_tokens(text)) else cap
        gr_result(TRUE, text = text, finish_reason = "length",
                  usage = usage_record(as_int1(params$prompt_tokens, 0L), output,
                                       local_provenance()))
      })
  }
}
