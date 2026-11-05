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
#' @param handler Function of `(messages, params)` returning a string or a
#'   [gr_result].
#' @param embed_handler Function of `(texts, params)` returning a numeric matrix
#'   with one row per input.
#' @return An object of class `gr_client`, with `$calls()`, `$embeds()` and
#'   `$reset()`.
#' @seealso [gr_client()], [gr_call()], [gr_result], [readgpt_example()] for a
#'   document to run against
#' @export
#' @examples
#' cl <- gr_mock_client(function(messages, params) "mock answer")
#' gr_call(cl, list(list(role = "user", content = "hi")))$text
#'
#' # `$calls()` is how you prove two reading strategies differ: it records the
#' # exact prompts each one sent.
#' cl$reset()
#' ch <- gr_segment(readgpt_example(), list(method = "paragraph", max_tokens = 150))
#' invisible(gr_read(ch, "What was revenue?", cl, "skim"))
#' table(vapply(cl$calls(), function(x) x$label, character(1)))
gr_mock_client <- function(handler = NULL, embed_handler = NULL) {
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
  structure(list(
    model = "mock-model", api = "mock", base_url = "mock://", embedding_model = "mock-embed",
    max_retries = 0L, retry_pause_base = 0, timeout = 1, extra_body = list(),
    # See gr_backend_client() for why a closure-backed client carries an id.
    .client_id = gr_new_id("mock"),
    handler = handler, embed_handler = embed_handler, .log = log,
    calls  = function() log$calls,
    embeds = function() log$embeds,
    reset  = function() { log$calls <- list(); log$embeds <- list(); invisible(NULL) }
  ), class = c("gr_mock_client", "gr_client"))
}
