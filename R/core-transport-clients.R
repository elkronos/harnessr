# core-transport-clients.R: the HTTP client and the API key it uses.

#' Resolve the API key
#'
#' Looks in `key`, then the `harnessr.api_key` option (or, failing that, the
#' deprecated `readgpt.api_key`), then `OPENAI_API_KEY`.
#' Never prints or logs the key.
#'
#' Spaces and line endings around the key are dropped, so a key read from a
#' file with `readLines()` or `readChar()` works as written. A key with a
#' control character inside it (a line break in the middle, say) is refused
#' with a `gr_auth_error`: sent as it is, it would end the `Authorization`
#' header and start another one, and every request would fail as a transport
#' error that never mentions the key.
#'
#' @param key Optional explicit key.
#' @return The key string. Raises a `gr_auth_error` if none is found, or if the
#'   key contains a control character.
#'
#' @section No key set:
#' A run that would have to send a request without a key stops with a
#' `gr_auth_error` that says how to set one. [answer_document()],
#' [gr_read_many()] and [gr_compare()] check before reading the document, so a
#' missing key does not first cost an OCR pass; everything else stops at the
#' first request. A client that sends its credential in `headers`, a mock, a
#' backend or replay client, and a client with a response cache attached are not
#' affected.
#' @seealso [gr_client()]
#' @export
#' @examples
#' # Resolution order: explicit argument, then the option, then the env var.
#' previous <- Sys.getenv("OPENAI_API_KEY", unset = NA)
#' Sys.setenv(OPENAI_API_KEY = "sk-example")
#' gr_api_key()
#' gr_api_key("sk-explicit-wins")
#'
#' # With no key set it says so. A run stops the same way, before its first
#' # request; see the section above.
#' Sys.unsetenv("OPENAI_API_KEY")
#' tryCatch(gr_api_key(), gr_auth_error = function(e) conditionMessage(e))
#'
#' # Restore. Sys.setenv(x = NA) would leave the variable set to "NA", not unset.
#' if (!is.na(previous)) Sys.setenv(OPENAI_API_KEY = previous)
gr_api_key <- function(key = NULL) {
  k <- api_key_value(key)
  if (!nzchar(k)) {
    gr_abort(paste0("No API key. Set OPENAI_API_KEY, or options(harnessr.api_key = '...'), ",
                    "or pass `api_key` to gr_client()."), class = "gr_auth_error")
  }
  k
}

#' The key gr_api_key() resolves, or "" when there is none.
#'
#' Separate from gr_api_key() so request_headers() can tell "no key" (fine when
#' the client sends its own headers) from "a key that cannot be sent", which is
#' raised from here and must reach the caller. It used to be pasted into the
#' Authorization header unchecked, although normalise_headers() refuses a
#' control character in any other header value: a key with "\r\n" inside
#' injected a header of its own, and the trailing newline readChar() leaves on
#' a key file corrupted the request, which then failed as a retried transport
#' error ("Server returned nothing") that never mentioned the key.
#' @noRd
api_key_value <- function(key = NULL) {
  k <- key %||% renamed_option("harnessr.api_key", "readgpt.api_key", "") %||% ""
  k <- trimws(as_chr1(k))
  if (!nzchar(k)) k <- trimws(as_chr1(Sys.getenv("OPENAI_API_KEY")))
  if (grepl("[[:cntrl:]]", k)) {
    # Never the value: an error message is the one place a credential is
    # guaranteed to be printed.
    gr_abort(paste0("The API key contains a control character. A line break inside a key is ",
                    "usually a stray line ending from the file or environment variable it was ",
                    "read from; check OPENAI_API_KEY, options(harnessr.api_key =) and the ",
                    "`api_key` passed to gr_client()."),
             class = c("gr_bad_key", "gr_auth_error"))
  }
  k
}

#' Stop a run that has no credential to send.
#'
#' A missing key is not a failed request: every request would fail the same way.
#' Recording it as one per call turned a first run without a key into an answer
#' of "NOT_IN_DOCUMENT" marked partial, which reads as "the document does not
#' say", with the reason only inside the trace.
#' @noRd
no_credentials_error <- function() {
  gr_abort(paste0(
    "No API key found, so no request can be sent. harnessr reads the key from the ",
    "OPENAI_API_KEY environment variable: add the line OPENAI_API_KEY=<your key> to your ",
    ".Renviron file (file.edit(\"~/.Renviron\") opens it), restart R, and check with ",
    "gr_api_key(). To practise without a key, pass `client = gr_mock_client(...)`. A ",
    "gateway that authenticates another way needs `headers` in gr_client()."),
    class = "gr_auth_error")
}

#' Stop before any work when a run could not send a single request.
#'
#' Only for a client that sends HTTP requests itself: mock, backend and replay
#' clients authenticate some other way or not at all. A client with a response
#' cache attached is let through, because the requests it makes may all be
#' answered from the cache; the first one that is not stops the run there, in
#' http_call(). Called by the entry points before ingestion, so a missing key
#' does not first cost an OCR pass over a long scan.
#' @noRd
stop_if_no_credentials <- function(client) {
  if (!inherits(client, "gr_client") ||
      inherits(client, c("gr_mock_client", "gr_backend_client", "gr_replay_client")) ||
      inherits(client[[".cache", exact = TRUE]], "gr_cache")) {
    return(invisible(TRUE))
  }
  if (is.null(request_headers(client))) no_credentials_error()
  invisible(TRUE)
}

#' Construct a model client
#'
#' The client is an object, not a global. Passing it explicitly is what lets a
#' Shiny app serve two users with two different keys in one R process. The old
#' code called `Sys.setenv(OPENAI_API_KEY = ...)`, which is process-wide, so the
#' second user's key silently billed the first user's requests.
#'
#' @param model Default chat model id.
#' @param api `"responses"` (default) or `"chat"`.
#' @param api_key Optional key; resolved lazily at call time if omitted.
#' @param base_url API base, for proxies and compatible endpoints.
#' @param embedding_model Default embedding model id.
#' @param max_retries,retry_pause_base Retry policy for transient failures.
#' @param timeout Per-request timeout in seconds.
#' @param extra_body Named list merged into every request body. A reasoning
#'   effort set here (`list(reasoning = list(effort = "low"))`) is the client's
#'   default; the `effort` setting of [gr_read_spec()] replaces it for the
#'   calls it covers.
#' @param headers Named character vector of extra HTTP headers, for endpoints
#'   that do not authenticate with a bearer token. Defaults to the `api_headers`
#'   option. `NA` as a value suppresses a header rather than sending it, which
#'   is how the automatic `Authorization` is dropped.
#' @section Endpoints behind a company gateway:
#' `base_url` alone is enough when the gateway speaks the OpenAI shape and takes
#' `Authorization: Bearer`. It is not enough anywhere else, and most corporate
#' gateways are somewhere else: Azure OpenAI authenticates with `api-key`, API
#' Management adds a subscription key, and many require a cost-centre or
#' correlation id. `headers` covers those.
#'
#' Two rules make it predictable. A header you name replaces the automatic
#' `Authorization` rather than joining it, matched without regard to case; and
#' naming any header at all makes the API key optional, because nothing here can
#' tell which of your headers is the credential. So a gateway with its own
#' scheme needs no `OPENAI_API_KEY` set at all:
#'
#' ```r
#' gr_client(
#'   base_url = "https://gateway.example.com/openai/v1", api = "chat",
#'   headers  = c("api-key" = Sys.getenv("GATEWAY_KEY"), Authorization = NA))
#' ```
#'
#' Headers are credentials and routing metadata, not part of what answers, so
#' they are excluded from the [gr_cache()] key for the same reason `api_key` is.
#' A rotating bearer or a per-request correlation id would otherwise make
#' every cache lookup miss. If a header changes *which* model answers, give that
#' client its own `base_url` or `model` so the cache can tell them apart.
#' @return An object of class `gr_client`: a list of the settings above.
#'   Constructing one makes no request and does not require a key; the key is
#'   resolved at call time by [gr_api_key()].
#' @seealso [gr_call()] to use it, [gr_mock_client()] to work offline,
#'   [gr_cache_client()] to make repeat calls free, [gr_replay_client()] to
#'   re-run a recorded run, [gr_api_key()] for key resolution, [gr_options()]
#'   for the defaults, [gr_result] for what a call returns
#' @export
#' @examples
#' # A client is a value, not a global. Two of them, two keys, one R process.
#' # That is what makes a Shiny app serving two users safe.
#' a <- gr_client(model = "gpt-4o",  api_key = "sk-user-a")
#' b <- gr_client(model = "gpt-4.1", api_key = "sk-user-b", timeout = 30)
#' vapply(list(a = a, b = b), function(cl) cl$model, character(1))
#'
#' # What that model can actually take.
#' unlist(gr_model_info(a$model)[c("context_window", "max_output")])
#'
#' # No key needed to develop against the pipeline.
#' gr_call(gr_mock_client(function(m, p) "hi there"), "hello")$text
#'
#' \dontrun{
#' cl <- gr_client(model = "gpt-5.6-terra")
#' gr_call(cl, list(list(role = "user", content = "Say hi.")), max_output = 20)
#' }
gr_client <- function(model = NULL, api = NULL, api_key = NULL, base_url = NULL,
                      embedding_model = NULL, max_retries = NULL,
                      retry_pause_base = NULL, timeout = NULL, extra_body = list(),
                      headers = NULL) {
  structure(list(
    model            = as_chr1(model %||% gr_options("model")),
    api              = match.arg(as_chr1(api %||% gr_options("api")), c("responses", "chat")),
    api_key          = api_key,          # may be NULL -> resolved at call time
    base_url         = sub("/+$", "", as_chr1(base_url %||% gr_options("api_base"))),
    embedding_model  = as_chr1(embedding_model %||% gr_options("embedding_model")),
    max_retries      = as.integer(clamp(max_retries %||% gr_options("max_retries"), 0, 10)),
    retry_pause_base = clamp(retry_pause_base %||% gr_options("retry_pause_base"), 0, 60),
    timeout          = clamp(timeout %||% gr_options("request_timeout"), 1, 3600),
    extra_body       = extra_body,
    # Normalised here rather than at call time so a malformed header set is a
    # construction error, next to the typo, instead of a transport error four
    # function calls away from it.
    headers          = if (is.null(headers)) {
      # Named for what the user would have to edit: a malformed set inherited
      # from the option is not a problem with the `headers` argument, and being
      # told it is sends them to the wrong line.
      normalise_headers(gr_options("api_headers"), arg = "api_headers option")
    } else normalise_headers(headers)
  ), class = "gr_client")
}

# Without a method, a client printed at the console as a plain list -- which
# meant `cl` echoed `api_key` in full, and would now echo every header value
# too. Both are credentials. Names are shown because they are what you need to
# see to debug a gateway; values never are.
#' @export
print.gr_client <- function(x, ...) {
  cat(sprintf("<gr_client> model=%s api=%s base_url=%s\n",
              as_chr1(x$model, "?"), as_chr1(x$api, "?"), as_chr1(x$base_url, "?")))
  key <- tryCatch(gr_api_key(x$api_key), gr_bad_key = function(e) NA,
                  error = function(e) NULL)
  hdr <- normalise_headers(x$headers)
  cat(sprintf("  auth: %s%s\n",
              if (is.null(key)) "no key resolved"
              else if (identical(key, NA)) "key refused (it contains a control character)"
              else "bearer key (hidden)",
              if (length(hdr)) {
                sprintf(", %d extra header(s), values hidden: %s",
                        length(hdr), paste(names(hdr), collapse = ", "))
              } else ""))
  cat(sprintf("  embeddings=%s timeout=%gs retries=%d cache=%s\n",
              as_chr1(x$embedding_model, "?"), x$timeout, x$max_retries,
              if (inherits(x$.cache, "gr_cache")) "attached" else "none"))
  invisible(x)
}
