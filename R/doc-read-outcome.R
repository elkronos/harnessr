# doc-read-outcome.R: what a read came to, as a value, and the structured
# answer request that can report it.
#
# Every answer carries `$outcome`, one of "answered", "not_found", "refused",
# "failed" or "partial", set by gr_read() from what the reader returned.
# is_not_found() reads it when it is given an answer, and falls back to the
# NOT_IN_DOCUMENT sentinel when it is given a string or an answer without it.
#
# How the answering requests report it is a setting (`answer_format`, owner
# decision DEC-05). "parsed", the default, sends the free-text requests the
# readers have always sent and reads the sentinel from the reply. "schema"
# sends the answering requests with a JSON schema that asks for the answer and
# an outcome field. The evidence on forcing a schema conflicts, so the default
# stays "parsed" until a live comparison says otherwise; the setting exists so
# that the comparison can be run with hr_sweep().
#
# A premise verdict can ride on the same schema (`premise_verdict =
# "structured"`, with `premise = TRUE`): a `premise_status` field and the
# `quote` from the excerpts that contradicts the question, which is checked
# with span_match(), the matcher that decides `verified` everywhere else.

#' The outcomes an answer can have.
#' @noRd
.gr_outcomes <- c("answered", "not_found", "refused", "failed", "partial")

#' The fields a structured answer request asks for under `spec`, or NULL when
#' the request is the free-text one the readers always sent.
#' @return NULL or `list(outcome = <lgl>, premise = <lgl>)`.
#' @noRd
answer_structure <- function(spec) {
  outcome <- identical(as_chr1(spec$answer_format, "parsed"), "schema")
  premise <- isTRUE(spec$premise) &&
    identical(as_chr1(spec$premise_verdict, "sentence"), "structured")
  if (!outcome && !premise) return(NULL)
  list(outcome = outcome, premise = premise)
}

#' What the system prompt gains under a structured answer request.
#' @noRd
answer_structure_prompt <- function(structure) {
  if (is.null(structure)) return("")
  paste0(
    " Reply with a JSON object. Put the answer in answer.",
    if (isTRUE(structure$outcome))
      paste0(" Set outcome to \"answered\" when the excerpts answer the question, or to ",
             "\"not_found\" when they do not, and then say in answer what is missing.")
    else " When the excerpts do not answer the question, put NOT_IN_DOCUMENT in answer.",
    if (isTRUE(structure$premise))
      paste0(" Set premise_status to \"contradicted\" when the excerpts contradict an ",
             "assumption in the question, put in answer the one sentence saying what they ",
             "state instead, and copy into quote, word for word, the passage of the excerpts ",
             "that states it. Use it only when the excerpts state the contrary; when they are ",
             "merely silent, the premise holds. Otherwise set premise_status to \"holds\" and ",
             "leave quote empty."))
}

#' The JSON schema of a structured answer request.
#' @noRd
answer_schema <- function(structure) {
  props <- list(answer = list(type = "string"))
  req <- list("answer")
  if (isTRUE(structure$outcome)) {
    props$outcome <- list(type = "string", enum = list("answered", "not_found"))
    req <- c(req, list("outcome"))
  }
  if (isTRUE(structure$premise)) {
    props$premise_status <- list(type = "string", enum = list("holds", "contradicted"))
    props$quote <- list(type = "string")
    req <- c(req, list("premise_status", "quote"))
  }
  list(type = "object", additionalProperties = FALSE, required = req, properties = props)
}

#' Send one answering request as `spec` says: the free-text request through
#' hr_call() at the defaults, exactly as before, or a structured one.
#'
#' A structured reply is turned back into the text the readers read: the
#' answer, NOT_IN_DOCUMENT for an outcome of "not_found", and the answer
#' after "FALSE_PREMISE: " for a premise_status of "contradicted", so every
#' reader's own handling of the reply is unchanged. What the reply said is
#' kept in `$structured`: `outcome`, `reply` (the answer field as the model
#' wrote it), `premise_status`, `quote` and `quote_verified` (the quote found
#' by span_match() in one of `sources`, the texts the request was shown, and,
#' when `document` is given, in one of those too). A reader whose request was
#' shown passages or summaries a model wrote passes them as `sources` and the
#' document's own text as `document`, so a quote counts only when the request
#' saw it and the document says it. A
#' reply that does not parse against the schema is read as free text, as the
#' parsed path reads it, and `$structured$parsed` is FALSE.
#' @noRd
answer_request <- function(client, messages, spec, trace, label, max_output,
                           model = spec$model, sources = character(0), document = NULL) {
  structure <- answer_structure(spec)
  if (is.null(structure)) {
    return(hr_call(client, messages, model = model, max_output = max_output,
                   temperature = spec$temperature, trace = trace, label = label,
                   effort = spec$effort))
  }
  out <- gr_call_json(client, messages, schema = answer_schema(structure),
                      schema_name = "answer", model = model, max_output = max_output,
                      temperature = spec$temperature, trace = trace, label = label,
                      effort = spec$effort)
  res <- out$result
  if (!isTRUE(res$ok)) return(res)
  if (!isTRUE(out$ok)) {
    res$structured <- list(parsed = FALSE)
    return(res)
  }
  reply <- as_chr1(json_text(out$value, "answer"), "")
  outcome <- if (isTRUE(structure$outcome)) as_chr1(json_text(out$value, "outcome"), NA_character_)
             else NA_character_
  status <- if (isTRUE(structure$premise))
    as_chr1(json_text(out$value, "premise_status"), NA_character_) else NA_character_
  quote <- if (isTRUE(structure$premise)) trimws(as_chr1(json_text(out$value, "quote"), ""))
           else ""
  found_in <- function(texts) {
    any(vapply(as.character(texts), function(src) isTRUE(span_match(quote, src)$verified),
               logical(1)))
  }
  verified <- nzchar(quote) && found_in(sources) && (is.null(document) || found_in(document))
  text <- if (identical(status, "contradicted")) {
    paste0(.FALSE_PREMISE, ": ", if (has_visible(reply)) reply else "")
  } else if (identical(outcome, "not_found") || !has_visible(reply)) {
    .NOT_FOUND
  } else reply
  res$text <- text
  res$structured <- list(parsed = TRUE, outcome = outcome, reply = reply,
                         premise_status = status, quote = if (nzchar(quote)) quote else NA_character_,
                         quote_verified = if (nzchar(quote)) verified else NA)
  res
}

#' Carry what a structured reply said onto the answer built from it: the
#' model's outcome and reply in `notes$structured`, and the premise verdict in
#' `$premise_verdict`. An answer from a free-text request is returned as it
#' is.
#' @noRd
with_structure <- function(ans, res) {
  st <- if (is.list(res)) res[["structured", exact = TRUE]] else NULL
  if (!is.list(st)) return(ans)
  ans$notes$structured <- st[c("parsed", "outcome", "reply")[c("parsed", "outcome", "reply") %in%
                                                              names(st)]]
  if (isTRUE(st$parsed) && !is.na(as_chr1(st$premise_status, NA_character_))) {
    ans$premise_verdict <- list(premise_status = st$premise_status, quote = st$quote,
                                quote_verified = st$quote_verified)
  }
  ans
}

#' The outcome of a read, from the answer a reader returned, the notes
#' gr_read() added and the steps the run recorded: `"refused"` when a limit
#' stopped the run and nothing was found, `"failed"` when nothing was found and
#' the reader reports an error, or every model request the run made failed,
#' `"not_found"` for any other NOT_IN_DOCUMENT, `"partial"` for an answer
#' marked partial, and `"answered"` otherwise.
#'
#' `steps` are the run's own trace steps. The readers word a run with no reply
#' in their own ways, or not at all (refine, rerank, iterative and preview set
#' no reason), so the record decides: a run that made model requests and got
#' no reply from any of them had nothing to find the answer in.
#' @noRd
answer_outcome <- function(x, steps = NULL) {
  notes <- as.list(x$notes %||% list())
  get <- function(k) notes[[k, exact = TRUE]]
  if (!is_not_found(as_chr1(x$answer, ""))) {
    return(if (isTRUE(x$partial)) "partial" else "answered")
  }
  stopped <- !is.null(get("call_cap_reached")) || !is.null(get("cost_cap_reached")) ||
    !is.null(get("limit_refused"))
  if (stopped) return("refused")
  # The readers' own words for a run with no reply to read: "every request
  # failed", "every request that was sent failed".
  reason <- as_chr1(get("reason"), "")
  if (is_nonblank(get("error")) || grepl("^every request", reason)) return("failed")
  if (every_request_failed(steps)) return("failed")
  "not_found"
}

#' TRUE when `steps` hold at least one model request and none of them got a
#' reply. Embeddings requests are left out: a failed one falls back to word
#' overlap, and the run goes on.
#' @noRd
every_request_failed <- function(steps) {
  req <- Filter(function(s) is.list(s) && !identical(s$kind, "local") &&
                  !identical(s$kind, "embedding") && is.list(s$tokens), steps %||% list())
  length(req) > 0L && !any(vapply(req, function(s) isTRUE(s$ok), logical(1)))
}
