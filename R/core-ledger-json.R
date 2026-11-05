# core-ledger-json.R: a trace, and the values in it, written as JSON.

#' Serialise an object to JSON
#'
#' A generic so traces, answers, chunk sets and documents all serialise
#' consistently and safely (`auto_unbox` plus `null = "null"`, so a missing
#' field appears as `null` rather than vanishing). Assigning `NULL` into an R
#' list *deletes the key*, which is why the old code's `final_answer` field
#' silently disappeared from the JSON whenever a call failed.
#'
#' @param x Object to serialise. Methods exist for [gr_answer], `gr_trace`,
#'   [gr_chunks] and [gr_document]; anything else (a review stage such as a
#'   screening or an extraction, a corpus, a comparison, a list of answers)
#'   falls back to a plain `jsonlite` conversion, in which a trace, answer,
#'   chunk set or document found at any depth is written as its own method
#'   writes it, and any other environment, a function, or a client (which
#'   holds the API key), none of which is data, is written as `null`.
#' @param pretty Whether to indent.
#' @param ... Passed to `jsonlite::toJSON()`.
#' @return A `json`-classed character string. `NULL` fields are written as
#'   `null` rather than dropped, and each number is written with as many
#'   significant digits as it takes to read back as the same number: 15 for
#'   most, 16 or 17 for the few that need them (`jsonlite::toJSON()` on its own
#'   rounds to four decimal places, and its `digits = NA` keeps 15 significant
#'   digits). Pass `digits` to round them. Otherwise a vector of length one is
#'   written as a scalar, except in the fields of a trace that list things (a
#'   comparison's `recipes`, the scores a ranking kept, the cleaning steps an
#'   ingest ran), which are arrays at every length.
#' @seealso [gr_trace_summary()], [gr_answer]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "45.2 million dollars")
#' ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#'
#' # The answer plus every prompt and response from the same single run.
#' txt <- as_json(ans)
#' names(jsonlite::fromJSON(txt))
as_json <- function(x, pretty = TRUE, ...) UseMethod("as_json")

#' @export
as_json.default <- function(x, pretty = TRUE, ..., digits = NA) {
  # Every number as it is, unless the caller asks to round. jsonlite's own
  # default rounds every number to four decimal places, so a p-value of 0.00003
  # was written as 0 and an effect of 0.84321 as 0.8432 -- in an extraction's
  # answer text, in the corpus summary built from it, in the audit report and in
  # every export -- while the typed table, read from the record itself, kept the
  # real values. And jsonlite's `digits = NA` is not full precision but 15
  # significant digits, which changed a 16-digit identifier (1234567890123456
  # came out as 1.23456789012346e+15) and an amount like 12345678901234.56,
  # both of which the four-decimal default had written exactly. So `digits = NA`
  # here means exact: 15 digits, which is what jsonlite writes and is exact for
  # nearly every number, and more only for a number that needs them.
  exact <- length(digits) == 1L && is.na(digits) && !inherits(digits, "AsIs")
  x <- json_ready(x, digits = digits, ...)
  out <- jsonlite::toJSON(x, pretty = pretty, auto_unbox = TRUE, null = "null",
                          na = "null", force = TRUE, digits = if (exact) NA else digits, ...)
  if (!exact || !needs_more_digits(x)) return(out)
  shortest_numbers(jsonlite::toJSON(x, pretty = pretty, auto_unbox = TRUE, null = "null",
                                    na = "null", force = TRUE, digits = I(17), ...))
}

#' `x` with everything jsonlite cannot write replaced by what can be.
#'
#' Every review stage keeps its trace, an environment, in `$trace`, and a
#' corpus or a comparison keeps answers that each hold one, so as_json() on
#' any of them, or on a list holding an answer, failed with "cannot unclass an
#' environment". Only the four classed methods had been taught to swap the
#' trace out. So, at any depth: a trace becomes trace_as_list(); an object
#' inside `x` that has an as_json() method of its own (an answer, a chunk set,
#' a document) is written by that method, so it has the same shape wherever it
#' sits; and any other environment, a function, or a client (which holds the
#' API key) becomes `null`, since none of them is data. `x` itself is left to
#' the method that was called.
#'
#' Every string is labelled UTF-8 on the way (label_utf8()). jsonlite reads an
#' unlabelled string as the session's encoding, so under a non-UTF-8 locale
#' (LC_ALL=C in cron or a container) a question typed in a script, or read with
#' readLines(), was written as "caf<c3><a9>": in a saved trace's meta, in the
#' criteria a screening records, in a document label. Only the JSON changes;
#' the objects are left as they are, since other code compares them with
#' strings of the caller's that carry no label either.
#' @noRd
json_ready <- function(x, ...) {
  own <- new.env(parent = emptyenv())
  has_method <- function(cls) {
    if (is.null(own[[cls]])) {
      own[[cls]] <- !is.null(utils::getS3method("as_json", cls, optional = TRUE))
    }
    own[[cls]]
  }
  walk <- function(v, depth) {
    if (is.environment(v)) {
      return(if (inherits(v, "gr_trace")) walk(trace_as_list(v), depth + 1L) else NULL)
    }
    # A client is not data either, and it carries the API key: written out, a
    # list that held one put the key in the JSON.
    if (is.function(v) || inherits(v, "gr_client")) return(NULL)
    if (is.character(v)) return(label_utf8(v))
    if (is.factor(v)) {
      attr(v, "levels") <- label_utf8(attr(v, "levels", exact = TRUE))
      return(v)
    }
    if (!is.list(v) || !length(v)) return(v)
    cls <- attr(v, "class", exact = TRUE)
    if (depth > 0L && !is.null(cls) && any(vapply(cls, has_method, logical(1)))) {
      # Written by its own method and read back as plain lists, which keeps
      # every JSON type (an array stays a list, so stays an array) and lets the
      # whole document be indented as one.
      return(jsonlite::parse_json(as_json(v, pretty = FALSE, ...), simplifyVector = FALSE))
    }
    # unclass(), so no `[` or as.list() method of the object's class gets a
    # say: as.list() splits a POSIXlt into its times.
    out <- lapply(unclass(v), walk, depth = depth + 1L)
    attributes(out) <- attributes(v)
    # The names are keys in the JSON: a list of answers is keyed by document.
    nm <- attr(out, "names", exact = TRUE)
    if (!is.null(nm)) attr(out, "names") <- label_utf8(nm)
    out
  }
  walk(x, 0L)
}

#' `x`, a character vector, with each string that is valid UTF-8 but carries
#' no label labelled UTF-8, its names likewise, and nothing else changed.
#'
#' mark_utf8() keeping attributes (names, dim, I()), and leaving alone a string
#' R has labelled latin1 or bytes, which jsonlite converts itself. ASCII is
#' unaffected, as it always is.
#' @noRd
label_utf8 <- function(x) {
  lab <- function(s) {
    need <- !is.na(s) & Encoding(s) == "unknown" & validUTF8(s)
    if (any(need)) { tmp <- s[need]; Encoding(tmp) <- "UTF-8"; s[need] <- tmp }
    s
  }
  if (!length(x)) return(x)
  x <- lab(x)
  nm <- attr(x, "names", exact = TRUE)
  if (!is.null(nm)) attr(x, "names") <- lab(nm)
  x
}

#' Mark the fields of `x` named in `fields` as arrays, so as_json() writes
#' them as arrays whatever their length.
#'
#' `auto_unbox` writes every length-one vector as a scalar, so a field that
#' holds a list of things was a string with one and an array with two, and a
#' consumer that iterated over it broke on the one. [I()] keeps the brackets.
#' @noRd
json_arrays <- function(x, fields) {
  if (!is.list(x)) return(x)
  for (f in intersect(fields, names(x))) {
    v <- x[[f]]
    if (!is.null(v) && is.atomic(v) && !inherits(v, "AsIs")) x[[f]] <- I(v)
  }
  x
}

#' Does `x` hold a double that 15 significant digits do not write exactly?
#'
#' The common case is no, and then as_json() serialises once. Dates and times
#' are skipped: jsonlite writes them as strings.
#' @noRd
needs_more_digits <- function(x) {
  doubles <- function(el) {
    # Before the list test, and unclass() in it: a POSIXlt is a list, and
    # lapply() on one hands back more POSIXlt, which recursed until the C
    # stack ran out on any object holding a date-time of that kind.
    if (inherits(el, c("Date", "POSIXt"))) return(NULL)
    if (is.list(el)) return(unlist(lapply(unclass(el), doubles), use.names = FALSE))
    if (is.double(el)) return(as.vector(el[is.finite(el)]))
    NULL
  }
  v <- doubles(x)
  length(v) > 0L && any(json_reads(sprintf("%.15g", v)) != v)
}

#' Numbers written as JSON text, read back as a JSON reader reads them.
#'
#' Not as.numeric(): R's own reader is not correctly rounded on every platform
#' (on arm64, where a long double is a double, "1e-300" reads as the double
#' below the nearest one), so it cannot say whether a number survives the trip
#' through a file. jsonlite's reader is, and it is what reads the text back.
#' @noRd
json_reads <- function(s) {
  if (!length(s)) return(numeric(0))
  as.numeric(jsonlite::parse_json(paste0("[", paste(s, collapse = ","), "]"),
                                  simplifyVector = TRUE))
}

#' Rewrite every number in JSON text with the fewest significant digits (15,
#' 16 or 17) that read back as the same double.
#'
#' `json` was written with 17 significant digits, which is exact for every
#' double but turns 0.1 into 0.10000000000000001; this shortens each number
#' again, to exactly what 15 digits write whenever that is exact. Strings are
#' matched as a whole and left alone, so digits inside one are never touched.
#' @noRd
shortest_numbers <- function(json) {
  txt <- as.character(json)
  # Bytes, so any text inside a string passes through untouched whatever its
  # encoding.
  m <- gregexpr('"(?:[^"\\\\]|\\\\.)*"|-?[0-9][0-9.eE+-]*', txt, perl = TRUE, useBytes = TRUE)
  tok <- regmatches(txt, m)[[1]]
  num <- !startsWith(tok, '"')
  if (any(num)) {
    best <- tok[num]
    v <- json_reads(best)
    # 16 first and 15 last, so the shorter form wins where both are exact.
    for (p in c(16L, 15L)) {
      s <- sprintf("%.*g", p, v)
      ok <- json_reads(s) == v
      best[ok] <- s[ok]
    }
    tok[num] <- best
    regmatches(txt, m) <- list(tok)
  }
  # Labelled again: jsonlite writes UTF-8, and a byte-wise replacement can
  # hand the text back without its label.
  structure(mark_utf8(txt), class = class(json))
}

#' The trace fields that list things: a comparison's `recipes`, the models
#' "auto" weighed, the cleaning steps an ingest ran, and the scores a ranking
#' kept. A new field that lists things belongs here too.
#' @noRd
.gr_trace_arrays <- c("recipes", "models", "clean_steps", "top_scores", "scores")

#' A trace as a plain, serialisable list.
#'
#' A `gr_trace` is an environment so that nested readers can write to one shared
#' record. Environments cannot be serialised: handing one to `jsonlite::toJSON()`
#' fails with "cannot unclass an environment", which is what happened to every
#' caller that put a trace inside a larger list before encoding it. Anything that
#' embeds a trace in JSON goes through this.
#' @noRd
trace_as_list <- function(x) {
  if (is.null(x) || !inherits(x, "gr_trace")) return(NULL)
  # The fields of the meta and of a local step's detail that list things, as
  # arrays at every length (see json_arrays()): a one-recipe comparison's
  # `recipes` was a string, and a two-recipe one's an array.
  steps <- lapply(x$steps, function(st) {
    if (is.list(st) && is.list(st$detail)) st$detail <- json_arrays(st$detail, .gr_trace_arrays)
    st
  })
  list(
    run_id = x$run_id,
    started = format(x$started, "%Y-%m-%dT%H:%M:%OS3"),
    meta = json_arrays(x$meta, .gr_trace_arrays),
    summary = as.list(gr_trace_summary(x)),
    steps = steps,
    errors = x$errors,
    # Whether a limit cut the run short, and which. Left out, a saved run that
    # was stopped read as one that finished, and a replay of it that went past
    # the stop was told only that it had "diverged".
    budget_stop = isTRUE(x$budget_stop),
    stop_reason = as_chr1(x$stop_reason, NA_character_),
    spent_usd = usd12(as_num1(x$spent_usd, 0)),
    replayed_usd = usd12(as_num1(x$replayed_usd, 0))
  )
}

#' @export
as_json.gr_trace <- function(x, pretty = TRUE, ...) {
  as_json.default(trace_as_list(x), pretty = pretty, ...)
}
