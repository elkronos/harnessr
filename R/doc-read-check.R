# doc-read-check.R: the conformance checks for readers and segmenters.
#
# Each check runs one registered module on the bundled example document
# against an offline client and asks hr_check_module() which of the rules
# below it breaks. They are reports: gr_register_reader() and
# gr_register_segmenter() do not run them, and a module that fails one is
# registered and runs as before.

#' Check a reader against the reader contract
#'
#' Reads the bundled example document ([gr_example()]) with one registered
#' reader, through an offline client, and reports which rules of the reader
#' contract it breaks. Nothing is refused: a reader that fails a rule stays
#' registered and runs as before. Use it on a reader of your own after
#' [gr_register_reader()].
#'
#' The document is cut with `list(method = "paragraph", max_tokens = 150)` and
#' read on a fresh [gr_trace()]. Readers that need more than a question are
#' given what they need: `extract` one field, `screen` one inclusion
#' criterion, and `ensemble` the members `"stuff"` and `"retrieve"`.
#'
#' @section Rules:
#' \describe{
#'   \item{`is_function`, `runs`}{The reader's `fn` is a function, and
#'     [gr_read()] with it finishes without an error.}
#'   \item{`answer_class`}{It returns a [gr_answer].}
#'   \item{`answer_fields`}{The answer has every field [gr_answer] documents
#'     for [gr_read()]: `answer`, `reader`, `question`, `chunks_used`,
#'     `partial`, `notes`, `trace`, `warnings` and `signature`, with
#'     `partial` one `TRUE` or `FALSE`.}
#'   \item{`answer_text`}{`answer` is a single string, not `NA`.}
#'   \item{`evidence`}{`evidence` is `NULL`, or a data frame with a
#'     `chunk_id` column whose ids are all chunks of the input. `NA` is
#'     allowed, for a span placed in no chunk.}
#'   \item{`chunks_used`}{Every id in `chunks_used` is a chunk of the input.}
#'   \item{`calls_declared`}{The label of every model call in the trace is
#'     covered by a stem the reader declared in `calls`, by the rule an
#'     `effort` map is checked with (a stem, a part of one up to a dot, or a
#'     label under one). For `ensemble`, its members' stems count too.}
#'   \item{`calls_within_cost`}{The requests the run made, embeddings
#'     included, are no more than the worst case its `cost` function gave for
#'     this input, as the pre-flight check recorded it. `NA` for a reader
#'     registered without `cost`.}
#' }
#'
#' @param reader A registered reader's name; see [gr_readers()].
#' @param client A `gr_client` to read with. `NULL` (the default) uses a
#'   [gr_mock_client()] whose reply to a request with a JSON schema is an
#'   object of that schema's shape, and a fixed sentence otherwise.
#' @return An `hr_conformance` data frame; see [hr_check_module()].
#' @seealso [hr_check_module()], [gr_check_segmenter()], [gr_register_reader()]
#' @family reading functions
#' @export
#' @examples
#' gr_check_reader("stuff")
#'
#' # A reader whose calls carry a label it did not declare.
#' gr_register_reader("loose", signature = "one|1|none", calls = "loose.answer",
#'   fn = function(chunks, question, client, spec, trace) {
#'     res <- gr_call(client, list(list(role = "user", content = question)),
#'                    model = spec$model, trace = trace, label = "other.answer")
#'     new_answer(res$text, "loose", question, integer(0), trace)
#'   })
#' gr_check_reader("loose")
gr_check_reader <- function(reader, client = NULL) {
  reader <- as_chr1(reader, "")
  rd <- registry_get("readers", reader, "readers", state = gr_state)
  client <- check_client(client)
  question <- "What was revenue?"
  chunks <- suppressWarnings(gr_segment(gr_example(),
                                        list(method = "paragraph", max_tokens = 150L)))
  ids <- chunks$chunks$chunk_id
  spec <- c(list(reader = reader), check_read_inputs(reader))
  trace <- gr_trace(meta = list(check = reader))
  stems <- rd$calls
  if (identical(reader, "ensemble")) {
    for (m in spec$members) stems <- c(stems, gr_state$readers[[m]]$calls)
  }
  answer_fields <- c("answer", "reader", "question", "chunks_used", "partial", "notes",
                     "trace", "warnings", "signature")
  rules <- list(
    answer_class = function(a) list(ok = inherits(a, "gr_answer"),
                                    detail = if (!inherits(a, "gr_answer"))
                                      sprintf("returned class %s", paste(class(a), collapse = "/"))
                                    else ""),
    answer_fields = function(a) {
      missing <- setdiff(answer_fields, names(a))
      if (length(missing)) {
        return(list(ok = FALSE, detail = paste("missing", paste(missing, collapse = ", "))))
      }
      p <- a$partial
      list(ok = is.logical(p) && length(p) == 1L && !is.na(p),
           detail = if (is.logical(p) && length(p) == 1L && !is.na(p)) ""
                    else "`partial` is not one TRUE or FALSE")
    },
    answer_text = function(a) {
      x <- a[["answer", exact = TRUE]]
      ok <- is.character(x) && length(x) == 1L && !is.na(x)
      list(ok = ok, detail = if (ok) "" else
        sprintf("`answer` is %s of length %d", class(x)[1], length(x)))
    },
    evidence = function(a) {
      ev <- a[["evidence", exact = TRUE]]
      if (is.null(ev)) return(list(ok = TRUE, detail = "no evidence"))
      if (!is.data.frame(ev)) {
        return(list(ok = FALSE, detail = sprintf("`evidence` is %s, not a data frame",
                                                 class(ev)[1])))
      }
      if (is.null(ev$chunk_id)) {
        return(list(ok = FALSE, detail = "`evidence` has no chunk_id column"))
      }
      # NA is a span placed in no chunk, such as a screening quote found in
      # none of them on its own.
      bad <- setdiff(ev$chunk_id[!is.na(ev$chunk_id)], ids)
      list(ok = !length(bad), detail = if (length(bad))
        sprintf("chunk id(s) %s are not in the chunks", paste(bad, collapse = ", ")) else "")
    },
    chunks_used = function(a) {
      bad <- setdiff(a[["chunks_used", exact = TRUE]], ids)
      list(ok = !length(bad), detail = if (length(bad))
        sprintf("chunk id(s) %s are not in the chunks", paste(bad, collapse = ", ")) else "")
    },
    calls_declared = function(a) check_labels(trace, stems),
    calls_within_cost = function(a) {
      if (is.null(rd$cost)) return(list(ok = NA, detail = "not checked: no cost function declared"))
      pre <- Filter(function(st) identical(st$label, "preflight"), trace$steps)
      worst <- if (length(pre)) as_int1(pre[[1]]$detail$worst_calls, NA_integer_) else NA_integer_
      if (is.na(worst)) return(list(ok = NA, detail = "not checked: no preflight record"))
      made <- as.integer(trace$calls)
      list(ok = made <= worst, detail = sprintf("%d request(s) made, at most %d expected",
                                                made, worst))
    })
  hr_check_module(rd$fn, function() gr_read(chunks, question, client, spec, trace = trace),
                  rules = rules, kind = "reader", name = reader)
}

#' Check a segmenter against the segmenter contract
#'
#' Cuts the bundled example document ([gr_example()]) with one registered
#' segmenter and reports which rules of the segmenter contract it breaks.
#' Nothing is refused: a segmenter that fails a rule stays registered and runs
#' as before. Use it on a segmenter of your own after
#' [gr_register_segmenter()].
#'
#' The spec is `gr_segment_spec(method = segmenter, max_tokens = 150,
#' context_source = "llm")`, so `contextual` writes its context lines with
#' the model. A client you pass is used whatever the segmenter declares, so
#' `calls_declared` sees every call it makes with one. With none, a
#' segmenter that needs a client, or declares calls, is given the offline one.
#'
#' @section Rules:
#' \describe{
#'   \item{`is_function`, `runs`}{The segmenter's `fn` is a function, and
#'     [gr_segment()] with it finishes without an error.}
#'   \item{`chunks_class`}{It returns a [gr_chunks] whose `chunks` is a data
#'     frame.}
#'   \item{`chunk_columns`}{`chunks` has the columns [gr_chunks] documents:
#'     `chunk_id`, `text`, `tokens`, `chars`, `page`, `section` and
#'     `block_id`.}
#'   \item{`chunk_text`}{Every chunk has text that is not blank.}
#'   \item{`chunk_ids`}{Chunk ids are unique and not `NA`.}
#'   \item{`within_cap`}{No chunk the segmenter returned was over
#'     `max_tokens`. [gr_segment()] splits an oversized chunk and records it
#'     in `extra$cap_enforced`, and the segmenter is reported for each one
#'     it had to split.}
#'   \item{`calls_declared`}{The label of every model call in the trace is
#'     covered by a stem the segmenter declared in `calls`, by the rule an
#'     `effort` map is checked with.}
#' }
#'
#' @param segmenter A registered segmenter's name; see [gr_segmenters()].
#' @inheritParams gr_check_reader
#' @return An `hr_conformance` data frame; see [hr_check_module()].
#' @seealso [hr_check_module()], [gr_check_reader()], [gr_register_segmenter()]
#' @family segmentation functions
#' @export
#' @examples
#' gr_check_segmenter("paragraph")
gr_check_segmenter <- function(segmenter, client = NULL) {
  segmenter <- as_chr1(segmenter, "")
  sg <- registry_get("segmenters", segmenter, "segmenters", state = gr_state)
  uses_client <- isTRUE(sg$needs_client) || length(sg$calls) > 0L
  client <- if (!is.null(client) || uses_client) check_client(client)
  spec <- gr_segment_spec(method = segmenter, max_tokens = 150L, context_source = "llm")
  trace <- gr_trace(meta = list(check = segmenter))
  columns <- c("chunk_id", "text", "tokens", "chars", "page", "section", "block_id")
  rules <- list(
    chunks_class = function(ch) list(ok = inherits(ch, "gr_chunks") && is.data.frame(ch$chunks),
                                     detail = if (!inherits(ch, "gr_chunks"))
                                       sprintf("returned class %s",
                                               paste(class(ch), collapse = "/"))
                                     else if (!is.data.frame(ch$chunks))
                                       "`chunks` is not a data frame" else ""),
    chunk_columns = function(ch) {
      missing <- setdiff(columns, names(ch$chunks))
      list(ok = !length(missing), detail = if (length(missing))
        paste("missing", paste(missing, collapse = ", ")) else "")
    },
    chunk_text = function(ch) {
      blank <- which(!has_visible(as.character(ch$chunks$text)))
      list(ok = !length(blank), detail = if (length(blank))
        sprintf("%d chunk(s) have blank text", length(blank)) else "")
    },
    chunk_ids = function(ch) {
      id <- ch$chunks$chunk_id
      ok <- !anyNA(id) && !anyDuplicated(id)
      list(ok = ok, detail = if (ok) "" else "chunk ids are missing or repeated")
    },
    within_cap = function(ch) {
      split <- as_int1(ch$extra[["cap_enforced", exact = TRUE]], 0L)
      over <- sum(ch$chunks$tokens > spec$max_tokens)
      ok <- split == 0L && over == 0L
      list(ok = ok, detail = if (ok) "" else
        sprintf("%d chunk(s) over the %d-token cap", split + over, spec$max_tokens))
    },
    calls_declared = function(ch) check_labels(trace, sg$calls))
  hr_check_module(sg$fn, function() gr_segment(gr_example(), spec, client = client, trace = trace),
                  rules = rules, kind = "segmenter", name = segmenter)
}

#' The client a check runs with: the one given, or the offline one below.
#' @noRd
check_client <- function(client) {
  if (is.null(client)) return(gr_mock_client(check_reply))
  if (!inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client() or gr_mock_client(), or be NULL.",
             class = "gr_bad_setting")
  }
  client
}

#' The offline client's reply: an object of the schema's shape to a request
#' that sends one, and a fixed sentence to any other.
#' @noRd
check_reply <- function(messages, params) {
  if (is.null(params$schema)) return(.gr_check_answer)
  as.character(jsonlite::toJSON(schema_sample(params$schema), auto_unbox = TRUE, null = "null"))
}

.gr_check_answer <- "Revenue was 45.2 million dollars."

#' A value of a JSON schema's shape: every property of an object, one item of
#' an array, the first value of an enum as it is (not coerced to the type of
#' the others), the first branch of `anyOf` or `oneOf` that is not only
#' null, the largest number allowed (or the smallest, or 1), TRUE, and a
#' fixed sentence for a string.
#' @noRd
schema_sample <- function(s) {
  if (!is.list(s)) return(.gr_check_answer)
  if (length(s$enum)) {
    vals <- Filter(function(e) !is.null(e) && length(e) == 1L && !is.na(e), as.list(s$enum))
    if (length(vals)) return(vals[[1]])
  }
  alt <- s$anyOf %||% s$oneOf
  if (is.list(alt) && length(alt)) {
    keep <- Filter(function(b) {
      is.list(b) && (length(setdiff(unlist(b$type), "null")) > 0L || !is.null(b$properties))
    }, alt)
    return(schema_sample(if (length(keep)) keep[[1]] else alt[[1]]))
  }
  type <- setdiff(unlist(s$type), "null")
  type <- if (length(type)) type[[1]] else if (!is.null(s$properties)) "object" else "string"
  switch(type,
    object = {
      props <- s$properties %||% list()
      if (!length(props)) structure(list(), names = character(0))
      else lapply(props, schema_sample)
    },
    array = list(schema_sample(s$items)),
    integer = ,
    number = s$maximum %||% s$minimum %||% 1L,
    boolean = TRUE,
    .gr_check_answer)
}

#' What a reader needs besides a question to read the example document.
#' @noRd
check_read_inputs <- function(reader) {
  switch(reader,
    extract = list(fields = gr_fields(revenue = "Total revenue for the year")),
    screen = list(include = "Reports the company's annual revenue"),
    ensemble = list(members = c("stuff", "retrieve")),
    list())
}

#' The rule that every model call in a trace carries a label covered by one of
#' `stems` (stem_known()). Embedding requests and local steps are not model
#' calls.
#' @noRd
check_labels <- function(trace, stems) {
  labels <- unlist(lapply(trace$steps, function(st) {
    if (is.null(st$kind)) as_chr1(st$label, NA_character_)
  }), use.names = FALSE)
  if (!length(labels)) return(list(ok = TRUE, detail = "no model calls"))
  bad <- unique(labels[!stem_known(labels, stems)])
  list(ok = !length(bad),
       detail = if (length(bad)) sprintf("label(s) %s not under the declared stems %s",
                                         paste0("'", bad, "'", collapse = ", "),
                                         if (length(stems)) paste(stems, collapse = ", ")
                                         else "(none)")
                else sprintf("%d call(s), all under declared stems", length(labels)))
}
