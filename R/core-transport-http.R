# core-transport-http.R: the request sent over HTTP and the reply read back.

#' Normalise a user-supplied header set.
#'
#' Accepts a named character vector, or a named list of length-1 values, and
#' returns a named character vector. `NA` survives and means "do not send this
#' header at all" -- which is how the automatic `Authorization` is suppressed for
#' a gateway that would reject it.
#'
#' This rejects rather than repairs, in three places. A name that is not a legal
#' HTTP field name is a typo, not a header. A value carrying a control character
#' is refused because CR/LF inside a header value is request splitting: the value
#' ends the header and starts another one the caller never wrote, and these
#' values come from environment variables and config files, which is exactly
#' where a stray line ending comes from. And duplicate names are collapsed
#' case-insensitively, because HTTP field names are case-insensitive but curl is
#' not -- given both `Authorization` and `authorization` it sends two headers,
#' and which one the gateway honours is its business rather than ours.
#' @noRd
normalise_headers <- function(headers, arg = "headers") {
  if (is.null(headers) || length(headers) == 0L) {
    return(stats::setNames(character(0), character(0)))
  }
  if (is.list(headers)) {
    bad <- which(vapply(headers, function(v) length(v) != 1L || !is.atomic(v), logical(1)))
    if (length(bad)) {
      gr_abort(sprintf("`%s[[%d]]` must be a single value.", arg, bad[1]),
               class = "gr_header_error")
    }
    nms <- names(headers)
    headers <- vapply(headers, function(v) if (is.na(v)) NA_character_ else as.character(v),
                      character(1), USE.NAMES = FALSE)
    names(headers) <- nms
  }
  if (!is.atomic(headers)) {
    gr_abort(sprintf("`%s` must be a named character vector, e.g. c(\"api-key\" = key).", arg),
             class = "gr_header_error")
  }
  nms <- names(headers)
  if (is.null(nms) || any(is.na(nms)) || !all(nzchar(nms))) {
    gr_abort(sprintf("Every element of `%s` must be named, e.g. c(\"api-key\" = key).", arg),
             class = "gr_header_error")
  }
  # Coerced rather than required, because `c(Authorization = NA)` is a LOGICAL
  # vector -- and that is the exact spelling of "suppress the bearer and send
  # nothing else", so demanding character here rejected the documented use.
  headers <- stats::setNames(as.character(headers), nms)
  ok <- grepl("^[0-9A-Za-z!#$%&'*+.^_|~`-]+$", nms)
  if (!all(ok)) {
    gr_abort(sprintf("Not a legal HTTP header name in `%s`: %s.",
                     arg, paste(sQuote(nms[!ok]), collapse = ", ")),
             class = "gr_header_error")
  }
  headers <- trimws(headers)
  # An empty value is not a header: curl drops it, so the request goes out
  # missing the credential and comes back 401. It is what
  # `c("api-key" = Sys.getenv("GATEWAY_KEY"))` produces when that variable is
  # not set, which is the single likeliest way to get here by accident.
  empty <- !is.na(headers) & !nzchar(headers)
  if (any(empty)) {
    gr_abort(sprintf(paste0("Header(s) in `%s` have an empty value: %s. ",
                            "If the value came from Sys.getenv(), that variable ",
                            "is not set. Use NA to suppress a header on purpose."),
                     arg, paste(sQuote(nms[empty]), collapse = ", ")),
             class = "gr_header_error")
  }
  bad <- !is.na(headers) & grepl("[[:cntrl:]]", headers)
  if (any(bad)) {
    # The NAME, never the value: these carry credentials, and an error message
    # is the one place a credential is guaranteed to be printed.
    gr_abort(sprintf(paste0("Header value(s) in `%s` contain a control character: %s. ",
                            "A newline in a token is usually a stray line ending from the ",
                            "file or environment variable it was read from."),
                     arg, paste(sQuote(nms[bad]), collapse = ", ")),
             class = "gr_header_error")
  }
  keep <- !duplicated(tolower(nms), fromLast = TRUE)
  stats::setNames(headers[keep], nms[keep])
}

#' The headers one request is actually sent with.
#'
#' Returns `NULL` when the client has neither a resolvable key nor any headers of
#' its own; the caller then stops the run with a `gr_auth_error` without spending
#' a request.
#'
#' Supplying `headers` therefore makes the key optional, and it has to: a gateway
#' that authenticates with `api-key` or a subscription key needs no bearer, and
#' nothing here can tell which of a stranger's headers is the credential. The
#' price is that a client given only non-auth headers and no key learns it is
#' unauthenticated from the server's 401 rather than from us. The 401 body is
#' carried back in the error, so that is a slower answer, not a silent one.
#' @noRd
request_headers <- function(client) {
  user <- normalise_headers(client$headers)
  # A key that cannot be sent is raised, not treated as no key: that would
  # report "No API key found" to someone whose key is set.
  key <- api_key_value(client$api_key)
  if (!nzchar(key)) key <- NULL
  if (is.null(key) && length(user) == 0L) return(NULL)
  h <- if (is.null(key)) stats::setNames(character(0), character(0))
       else c(Authorization = paste("Bearer", key))
  if (length(user)) h <- c(h[!(tolower(names(h)) %in% tolower(names(user)))], user)
  h[!is.na(h)]
}

#' @noRd
normalise_messages <- function(messages) {
  if (is.character(messages)) {
    txt <- paste(messages, collapse = "\n")
    if (!nzchar(trimws(txt))) gr_abort("`messages` is empty; there is nothing to send.")
    messages <- list(list(role = "user", content = txt))
  }
  # A single unwrapped message. Without this, each *element* became its own
  # message and the first one carried the literal content "user".
  if (is.list(messages) && !is.null(names(messages)) && "content" %in% names(messages)) {
    messages <- list(messages)
  }
  if (!is.list(messages) || !length(messages)) gr_abort("`messages` must be a non-empty list.")
  lapply(messages, function(m) {
    if (is.character(m)) m <- list(role = "user", content = m)
    role <- as_chr1(m$role, "user")
    if (!role %in% c("system", "user", "assistant", "developer")) {
      gr_abort(sprintf("Unsupported message role '%s'.", role))
    }
    # Labelled here, before anything counts, keys, records or sends it. Under a
    # non-UTF-8 locale (LC_ALL=C in cron, Docker, env -i) a question typed in a
    # script or read with readLines() is UTF-8 bytes marked "unknown", and
    # jsonlite, serialising the request body, read those bytes as the native
    # encoding and sent "Quelle <c3><a9>tait" to the model -- while the trace,
    # which labels what it records, showed the question intact. This cannot
    # help text that paste() joined to labelled document text before it got
    # here: paste() escapes the unlabelled part itself, so that has to be
    # labelled where the user's text comes in.
    list(role = role, content = mark_utf8(as_chr1(m$content)))
  })
}

#' @noRd
build_request_body <- function(client, messages, model, max_output, temperature,
                               schema, schema_name, info, extra, effort = NULL) {
  temperature <- temperature %||% gr_options("temperature")
  # Reasoning models reject `temperature`; sending it is a hard 400.
  if (isTRUE(info$reasoning) || !isTRUE(info$supports_temperature)) temperature <- NULL

  if (identical(client$api, "responses")) {
    sys <- vapply(Filter(function(m) m$role %in% c("system", "developer"), messages),
                  function(m) m$content, character(1))
    rest <- Filter(function(m) !m$role %in% c("system", "developer"), messages)
    body <- list(
      model = model,
      input = lapply(rest, function(m) list(role = m$role, content = m$content)),
      max_output_tokens = max_output
    )
    if (length(sys)) body$instructions <- paste(sys, collapse = "\n\n")
    if (!is.null(temperature)) body$temperature <- temperature
    if (!is.null(schema)) {
      body$text <- list(format = list(type = "json_schema", name = schema_name,
                                      strict = TRUE, schema = schema))
    }
  } else {
    body <- list(model = model, messages = lapply(messages, function(m)
      list(role = m$role, content = m$content)))
    # Reasoning models reject `max_tokens` on Chat Completions with a 400 and
    # take `max_completion_tokens` instead -- the same kind of rule as the
    # temperature one above. Other models keep `max_tokens`, which every
    # OpenAI-compatible server understands. A limit field the caller names in
    # `extra_body` replaces this one rather than joining it, so a gateway that
    # wants the other spelling is not sent both.
    limit_field <- if (isTRUE(info$reasoning)) "max_completion_tokens" else "max_tokens"
    named <- c(names(client$extra_body %||% list()), names(extra %||% list()))
    if (!any(c("max_tokens", "max_completion_tokens") %in% named)) {
      body[[limit_field]] <- max_output
    }
    if (!is.null(temperature)) body$temperature <- temperature
    if (!is.null(schema)) {
      body$response_format <- list(type = "json_schema",
                                   json_schema = list(name = schema_name, strict = TRUE,
                                                      schema = schema))
    }
  }
  # The effort between the two: over the client's default, under a field the
  # call names itself (see effort_body()). NULL leaves the body as it was.
  body <- effort_body(utils::modifyList(body, client$extra_body %||% list()), effort, client$api)
  utils::modifyList(body, extra %||% list())
}

# Status codes worth retrying. 400 is NOT here: a malformed request will be
# malformed on every attempt, and retrying it four times was pure waste.
.retryable_status <- c(408L, 409L, 425L, 429L, 500L, 502L, 503L, 504L)

#' @noRd
http_call <- function(client, url, body) {
  headers <- request_headers(client)
  if (is.null(headers)) no_credentials_error()
  # `.headers =`, not `...`: add_headers() has its own `.headers` argument, so a
  # header literally named `.headers` -- a legal HTTP field name -- would be
  # swallowed as that argument by do.call() instead of being sent. Placed after
  # content_type_json() so a caller who names Content-Type wins.
  hdr <- httr::add_headers(.headers = headers)
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    resp <- tryCatch(
      httr::POST(url,
                 httr::content_type_json(),
                 hdr,
                 httr::timeout(client$timeout),
                 body = body, encode = "json"),
      error = function(e) e
    )
    if (inherits(resp, "condition")) {
      if (attempt > client$max_retries) {
        return(gr_result(FALSE, error = paste0("Transport error: ", conditionMessage(resp)),
                         status = 0L, retryable = TRUE))
      }
      Sys.sleep(backoff_delay(client$retry_pause_base, attempt))
      next
    }
    status <- httr::status_code(resp)
    if (status >= 200 && status < 300) {
      # A 200 is a request that was sent and billed, so it is traced whatever
      # its body turns out to hold. An error here used to leave gr_call()
      # before trace_record(), and in a parallel map took the document with it.
      # Usage unknown, not zero, so gr_call() settles it against the prompt.
      return(tryCatch(parse_response(resp, client$api), error = function(e) {
        gr_result(FALSE, status = status,
                  usage = list(input = NA_integer_, output = NA_integer_),
                  error = paste0("Could not read the API response: ",
                                 repair_utf8(conditionMessage(e))))
      }))
    }
    body_text <- repair_utf8(as_chr1(tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                                              error = function(e) "<unreadable body>")))
    detail <- substr(body_text, 1, 800)
    if (out_of_quota(status, body_text)) {
      # Terminal, whatever the status says: see out_of_quota().
      return(gr_result(FALSE, status = status, retryable = FALSE,
                       error = sprintf("HTTP %d (the account is out of quota; not retried): %s",
                                       status, detail)))
    }
    if (status %in% .retryable_status && attempt <= client$max_retries) {
      wait <- retry_after(resp) %||% backoff_delay(client$retry_pause_base, attempt)
      gr_msg(sprintf("HTTP %d; retrying in %.1fs (attempt %d/%d).",
                     status, wait, attempt, client$max_retries + 1L))
      Sys.sleep(wait)
      next
    }
    return(gr_result(FALSE, error = sprintf("HTTP %d: %s", status, detail),
                     status = status, retryable = status %in% .retryable_status))
  }
}

#' Is this a refusal because the account has no quota left?
#'
#' OpenAI sends it as a 429 with code `insufficient_quota`, the status it uses
#' for a rate limit, and every 429 was retried: with the default policy each
#' call slept through about 22 seconds of backoff before failing, and a
#' 40-chunk read spent some 15 minutes waiting on an account that no retry
#' could fix. Only the provider's own code is trusted here; a 429 without it is
#' a rate limit and is retried as before.
#' @noRd
out_of_quota <- function(status, body_text) {
  if (!identical(as.integer(status), 429L) || !grepl("insufficient_quota", body_text, fixed = TRUE)) {
    return(FALSE)
  }
  parsed <- tryCatch(jsonlite::parse_json(body_text), error = function(e) NULL)
  err <- if (is.list(parsed)) parsed[["error", exact = TRUE]] else NULL
  if (!is.list(err)) return(FALSE)
  any(vapply(c("code", "type"), function(f) identical(as_chr1(err[[f, exact = TRUE]]),
                                                     "insufficient_quota"), logical(1)))
}

#' Exponential backoff with real jitter.
#'
#' The seed used to be a pure function of `attempt`, so every client and every
#' parallel worker retrying attempt N slept for the identical duration -- the
#' delay was labelled "jitter" but had none, and a rate-limited fleet re-collided
#' on every round. Mixing in the process id and the clock decorrelates them. The
#' draw still goes through a private RNG, so the caller's `set.seed()` stream is
#' untouched and any simulation running alongside is unaffected.
#' @noRd
backoff_delay <- function(base, attempt) {
  cap <- min(base * 2^(attempt - 1L), 60)
  if (cap <= 0) return(0)
  seed <- as.integer((as.numeric(Sys.getpid()) * 7919 +
                      as.numeric(Sys.time()) * 1000 + attempt * 104729) %% 2147483647)
  with_private_rng(seed, stats::runif(1, cap * 0.5, cap))
}

#' @noRd
retry_after <- function(resp) {
  h <- httr::headers(resp)
  v <- suppressWarnings(as.numeric(h[["retry-after"]] %||% NA))
  if (is.finite(v) && v >= 0) min(v, 60) else NULL
}

#' @noRd
parse_response <- function(resp, api) {
  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json",
                                   encoding = "UTF-8"),
                     error = function(e) NULL)
  if (is.null(parsed)) {
    return(gr_result(FALSE, error = "Could not parse API response as JSON.",
                     status = httr::status_code(resp)))
  }
  fld <- function(x, nm) if (is.list(x)) x[[nm, exact = TRUE]] else NULL
  err <- fld(parsed, "error")
  if (!is.null(err)) {
    # `error` may be an object or a bare string, depending on the endpoint.
    msg <- repair_utf8(if (is.list(err)) as_chr1(fld(err, "message"), "API returned an error object.")
                       else as_chr1(err, "API returned an error object."))
    return(gr_result(FALSE, error = msg, status = httr::status_code(resp), raw = parsed))
  }
  text <- extract_text(parsed, api)
  ug <- fld(parsed, "usage")
  # NA, not 0, when the block is missing or holds nothing numeric. A provider
  # that omits `usage` -- several OpenAI-compatible local servers do, and so
  # does a gateway that strips it -- had every call recorded as 0 tokens in and
  # 0 out: a real call costed at nothing. That is the fault `ellmer_usage()` and
  # `gr_estimate_cost()` were fixed for, still alive on the path every HTTP user
  # takes. The caller settles NA against a local count; see settle_usage().
  int1 <- function(v) {
    v <- suppressWarnings(as.integer(v)[1])
    if (is.na(v) || v < 0L) NA_integer_ else v
  }
  usage <- list(
    input  = int1(fld(ug, "input_tokens")  %||% fld(ug, "prompt_tokens")     %||% NA_integer_),
    output = int1(fld(ug, "output_tokens") %||% fld(ug, "completion_tokens") %||% NA_integer_)
  )
  ch <- fld(parsed, "choices")
  status <- fld(parsed, "status")
  # A Responses API reply cut off at `max_output_tokens` has status
  # "incomplete" and says why in `incomplete_details`. The reason is what
  # tells a truncated reply from a filtered one, so it is what is kept;
  # gr_result() then maps the truncation spellings to "length".
  if (identical(as_chr1(status), "incomplete")) {
    status <- fld(fld(parsed, "incomplete_details"), "reason") %||% status
  }
  finish <- as_chr1(status %||%
                    (if (is.list(ch) && length(ch) && is.list(ch[[1]])) fld(ch[[1]], "finish_reason")) %||%
                    NA_character_, NA_character_)

  # A refusal is not an answer. Returning ok = TRUE here let the refusal text be
  # spliced into the next prompt as if it were document evidence.
  if (is_refusal(parsed)) {
    return(gr_result(FALSE, text = "", status = httr::status_code(resp), usage = usage,
                     finish_reason = "refusal", raw = parsed,
                     error = paste0("Model refused the request: ", substr(text, 1, 200))))
  }
  # An empty completion is a *successful* call with no content -- report it as
  # a failure so callers do not splice "" into a downstream prompt as evidence.
  if (!nzchar(trimws(text))) {
    return(gr_result(FALSE, text = "", status = httr::status_code(resp), usage = usage,
                     finish_reason = finish, raw = parsed,
                     error = sprintf("Model returned no text content (finish reason: %s).",
                                     as_chr1(finish, "unknown"))))
  }
  gr_result(TRUE, text = text, status = httr::status_code(resp), usage = usage,
            finish_reason = finish, raw = parsed)
}

#' One field of a parsed model reply, read EXACTLY and shaped.
#'
#' Two traps in one place, both with a history here.
#'
#' `$` partial-matches, so a reply using `decisions` satisfied a read of
#' `decision` and the screener recorded a real "include" from a key that does
#' not exist; `can_answer_now` ended the iterative loop and its answer was
#' returned as final. `extract_text()` below has used `[[exact = TRUE]]` since
#' the same bug bit the HTTP layer -- the readers were never given the same
#' treatment.
#'
#' And `simplifyVector = TRUE` is not type-stable: one element unboxes to a
#' scalar, several become a vector, an array of arrays becomes a matrix, and an
#' array of objects becomes a data frame. Asking for a scalar and getting a
#' length-2 vector crashed `vapply()`; getting a list crashed `as.integer()`;
#' getting a matrix silently transposed a list of propositions. A wrong shape is
#' a field the reply did not supply, which is what `default` is for.
#' @noRd
json_field <- function(value, name, default = NULL, scalar = TRUE) {
  if (!is.list(value)) return(default)
  v <- value[[name, exact = TRUE]]
  if (is.null(v)) return(default)
  # A one-element list around a scalar is jsonlite being jsonlite, not a shape
  # the caller has to know about.
  if (is.list(v) && length(v) == 1L && is.null(names(v))) v <- v[[1]]
  if (!scalar) return(v)
  if (is.list(v) || length(v) != 1L || is.na(v)) return(default)
  v
}

#' A numeric field, or `default` when the reply's value is not one number.
#' @noRd
json_num <- function(value, name, default = NA_real_) {
  v <- json_field(value, name)
  if (is.null(v)) return(default)
  n <- suppressWarnings(as.numeric(v))
  if (length(n) != 1L || is.na(n) || !is.finite(n)) default else n
}

#' A TEXT field: everything the reply put there, joined, or `default`.
#'
#' Prose is the one kind of field where an array is not a wrong shape. A model
#' that answers in two sentences may send `["First.", "Second."]`, and reading
#' only a scalar turned that into "no answer": the iterative reader returned
#' NOT_IN_DOCUMENT for a question it had answered. Every value is kept, numbers
#' included, in the order it was written: an answer sent as
#' `{"participants": 482}` is 482, and losing it is worse than keeping a stray
#' chunk number beside it.
#' @noRd
json_text <- function(value, name, default = NULL) {
  v <- text_leaves(json_field(value, name, scalar = FALSE))
  if (!length(v)) default else paste(v, collapse = "\n")
}

#' The values in a parsed JSON value, as text, in the order they were written.
#'
#' `simplifyVector = TRUE` gives one JSON value several R shapes, and each needs
#' reading in document order: an array of arrays becomes a matrix or array,
#' which `as.character()` reads column by column, transposing it; an array of
#' objects becomes a data frame, read here row by row with its list and nested
#' data-frame columns followed into; a list is read element by element.
#'
#' `prefer` names the keys that hold an object's text. An object carrying any of
#' them is read through those keys only; one carrying none is read through all
#' of them, so text under an unexpected key is kept rather than lost. With
#' `object_numbers = FALSE`, a number inside an object is a label -- an `id`, a
#' page -- and not text. A bare value or array is text whatever its type.
#' @noRd
text_leaves <- function(x, prefer = character(0), object_numbers = TRUE,
                        in_object = FALSE) {
  if (is.null(x)) return(character(0))
  again <- function(v, obj) text_leaves(v, prefer, object_numbers, obj)
  # Decided per OBJECT: a row of a data frame whose text key is empty -- the
  # reply used a different key for that one -- is read through all its keys.
  choose <- function(got, nms) {
    pref <- !is.na(nms) & tolower(nms) %in% prefer
    if (any(pref & lengths(got) > 0L)) got[pref] else got
  }
  if (is.data.frame(x)) {
    if (!nrow(x) || !ncol(x)) return(character(0))
    out <- lapply(seq_len(nrow(x)), function(i) {
      got <- lapply(x, function(col) {
        # `col[i]` on a nested data-frame column selects its i-th COLUMN.
        cell <- if (is.data.frame(col)) col[i, , drop = FALSE] else
          if (is.list(col)) col[[i]] else col[i]
        again(cell, TRUE)
      })
      unlist(choose(got, names(x)), use.names = FALSE)
    })
    return(unlist(out, use.names = FALSE) %||% character(0))
  }
  # Last index fastest, which is the order the JSON was written in.
  if (length(dim(x)) > 1L) x <- as.vector(aperm(x))
  if (is.list(x)) {
    named <- !is.null(names(x)) && any(nzchar(names(x)))
    got <- lapply(x, again, obj = in_object || named)
    if (named) got <- choose(got, names(x))
    return(unlist(got, use.names = FALSE) %||% character(0))
  }
  if (!is.atomic(x)) return(character(0))
  if (in_object && !object_numbers && !is.character(x)) return(character(0))
  x <- as.character(x)
  x[!is.na(x)]
}

#' Pull assistant text out of either API shape.
#'
#' Note what this deliberately does NOT do: collapse newlines. The old code ran
#' `gsub("\n+", " ", result)` on every response, flattening lists, tables and
#' code blocks into one line.
#' @noRd
extract_text <- function(parsed, api) {
  # `[[` with exact = TRUE throughout. `$` on a list partial-matches, so
  # `parsed$output` silently returned `output_text` and then failed on it.
  # Every branch is also defensive about shape: a 200 response whose fields are
  # a different type than expected must produce "", not an uncaught error.
  if (!is.list(parsed)) return("")
  fld <- function(x, nm) if (is.list(x)) x[[nm, exact = TRUE]] else NULL
  # Repaired before trimws(), whose regex stops on bytes that are not UTF-8;
  # see repair_utf8().
  clean <- function(x) trimws(repair_utf8(x))

  ot <- fld(parsed, "output_text")
  if (is.list(ot)) ot <- unlist(ot, use.names = FALSE)
  if (is.character(ot) && length(ot)) return(clean(paste(ot, collapse = "")))

  out <- fld(parsed, "output")
  if (is.list(out) && length(out)) {
    parts <- unlist(lapply(out, function(item) {
      if (!is.list(item)) return(NULL)
      if (!identical(as_chr1(fld(item, "type"), "message"), "message")) return(NULL)
      cont <- fld(item, "content")
      if (is.character(cont)) return(cont)
      if (!is.list(cont)) return(NULL)
      vapply(cont, function(cc) {
        if (is.character(cc)) return(as_chr1(cc))
        if (!is.list(cc)) return("")
        if (identical(as_chr1(fld(cc, "type")), "refusal")) return(as_chr1(fld(cc, "refusal")))
        as_chr1(fld(cc, "text"))
      }, character(1))
    }), use.names = FALSE)
    parts <- parts[!is.na(parts) & nzchar(parts)]
    if (length(parts)) return(clean(paste(parts, collapse = "")))
  }

  ch <- fld(parsed, "choices")
  if (is.list(ch) && length(ch) && is.list(ch[[1]])) {
    msg <- fld(ch[[1]], "message")
    if (is.character(msg)) return(clean(as_chr1(msg)))
    if (is.list(msg)) {
      ref <- fld(msg, "refusal")
      if (!is.null(ref)) return(repair_utf8(as_chr1(ref)))
      cont <- fld(msg, "content")
      # Content as an array of typed parts, which several OpenAI-compatible
      # servers send (reasoning models: a "thinking" part, then "text").
      # as_chr1() deparsed each part, so the answer read
      # 'list(type = "text", text = "...")', the model's reasoning included,
      # with ok = TRUE. Only the text parts are the reply, as in the
      # Responses branch above; a refusal part is reported as one.
      if (is.list(cont)) {
        parts <- vapply(cont, function(cc) {
          if (is.character(cc)) return(as_chr1(cc))
          if (!is.list(cc)) return("")
          type <- as_chr1(fld(cc, "type"), "text")
          if (identical(type, "refusal")) return(as_chr1(fld(cc, "refusal")))
          if (type %in% c("text", "output_text")) as_chr1(fld(cc, "text")) else ""
        }, character(1))
        return(clean(paste(parts[nzchar(parts)], collapse = "")))
      }
      return(clean(as_chr1(cont)))
    }
  }
  ""
}

#' Was the response a model refusal rather than an answer?
#' @noRd
is_refusal <- function(parsed) {
  if (!is.list(parsed)) return(FALSE)
  fld <- function(x, nm) if (is.list(x)) x[[nm, exact = TRUE]] else NULL
  out <- fld(parsed, "output")
  if (is.list(out)) {
    for (item in out) {
      cont <- if (is.list(item)) fld(item, "content") else NULL
      if (is.list(cont)) for (cc in cont) {
        if (is.list(cc) && identical(as_chr1(fld(cc, "type")), "refusal")) return(TRUE)
      }
    }
  }
  ch <- fld(parsed, "choices")
  if (is.list(ch) && length(ch) && is.list(ch[[1]])) {
    msg <- fld(ch[[1]], "message")
    if (is.list(msg) && !is.null(fld(msg, "refusal"))) return(TRUE)
    cont <- if (is.list(msg)) fld(msg, "content") else NULL
    if (is.list(cont)) for (cc in cont) {
      if (is.list(cc) && identical(as_chr1(fld(cc, "type")), "refusal")) return(TRUE)
    }
  }
  FALSE
}
