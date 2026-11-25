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
#' read on a fresh [hr_trace()]. Readers that need more than a question are
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
#'   [hr_mock_client()] whose reply to a request with a JSON schema is an
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
#'     res <- hr_call(client, list(list(role = "user", content = question)),
#'                    model = spec$model, trace = trace, label = "other.answer")
#'     new_answer(res$text, "loose", question, integer(0), trace)
#'   })
#' gr_check_reader("loose")
gr_check_reader <- function(reader, client = NULL) {
  reader <- as_chr1(reader, "")
  rd <- registry_get("reader", reader)
  client <- check_client(client)
  question <- "What was revenue?"
  chunks <- suppressWarnings(gr_segment(gr_example(),
                                        list(method = "paragraph", max_tokens = 150L)))
  ids <- chunks$chunks$chunk_id
  spec <- c(list(reader = reader), check_read_inputs(reader))
  trace <- hr_trace(meta = list(check = reader))
  stems <- rd$calls
  if (identical(reader, "ensemble")) {
    for (m in spec$members) stems <- c(stems, registry_get("reader")[[m]]$calls)
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
  sg <- registry_get("segmenter", segmenter)
  uses_client <- isTRUE(sg$needs_client) || length(sg$calls) > 0L
  client <- if (!is.null(client) || uses_client) check_client(client)
  spec <- gr_segment_spec(method = segmenter, max_tokens = 150L, context_source = "llm")
  trace <- hr_trace(meta = list(check = segmenter))
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
  if (is.null(client)) return(hr_mock_client(check_reply))
  if (!inherits(client, "gr_client")) {
    gr_abort("`client` must come from hr_client() or hr_mock_client(), or be NULL.",
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

# ---------------------------------------------------------------------------
# Rules for the other kinds: extractors, cleaners, embedders and protocols.
# Each gr_rules_*() returns the named list of rules hr_check_module() asks,
# and each check_*() runs one registered module once and asks them. Like the
# reader and segmenter checks, they report and refuse nothing.
# ---------------------------------------------------------------------------

#' The rules for what an extractor returns: a character vector or a data
#' frame with a `text` column, at least one block with text, `page`, `section`
#' and `kind` of the right type where given, and unread pages given as page
#' numbers.
#' @noRd
gr_rules_extractor <- function() {
  list(
    blocks_shape = function(x) {
      ok <- is.character(x) || (is.data.frame(x) && "text" %in% names(x))
      list(ok = ok, detail = if (ok) "" else
        sprintf("returned class %s, not text or a data frame with a `text` column",
                paste(class(x), collapse = "/")))
    },
    block_text = function(x) {
      text <- if (is.data.frame(x)) x$text else x
      n <- sum(has_visible(vapply(text, as_chr1, character(1), USE.NAMES = FALSE)))
      list(ok = n > 0L, detail = sprintf("%d block(s) with text", n))
    },
    block_columns = function(x) {
      if (!is.data.frame(x)) return(list(ok = TRUE, detail = "text only: no page, section or kind"))
      untyped <- function(v, test) !is.null(v) && !all(is.na(v)) && !test(v)
      bad <- c(page = untyped(x[["page"]], is.numeric),
               section = untyped(x[["section"]], is.character),
               kind = untyped(x[["kind"]], is.character))
      list(ok = !any(bad), detail = if (any(bad))
        sprintf("wrong type: %s", paste(names(bad)[bad], collapse = ", ")) else "")
    },
    unread_pages = function(x) {
      u <- attr(x, "gr_unread_pages", exact = TRUE)
      ok <- is.null(u) || (is.numeric(u) && !anyNA(u) && all(u >= 1 & u == round(u)))
      list(ok = ok, detail = if (ok) "" else "`gr_unread_pages` is not a set of page numbers")
    })
}

#' The rules for a cleaner, run by gr_clean() on `text`: one string per input
#' block and none NA, some text left, a line in the clean log, and the same
#' result from a second run (`again()`).
#' @noRd
gr_rules_cleaner <- function(text, cleaner, again) {
  list(
    text_class = function(x) {
      ok <- is.character(x) && length(x) == length(text) && !anyNA(x)
      list(ok = ok, detail = if (ok) "" else
        sprintf("returned %s of length %d for %d block(s)", class(x)[1], length(x),
                length(text)))
    },
    keeps_text = function(x) {
      ok <- any(has_visible(as.character(x)))
      list(ok = ok, detail = if (ok) "" else "no text was left")
    },
    logged = function(x) {
      ok <- cleaner %in% names(attr(x, "gr_clean_log", exact = TRUE))
      list(ok = ok, detail = if (ok) "" else "the step is not in the clean log")
    },
    deterministic = function(x) {
      ok <- identical(as.character(again()), as.character(x))
      list(ok = ok, detail = if (ok) "" else "a second run cleaned the text differently")
    })
}

#' The rules for an embedder's vectors for `texts`: a numeric matrix with one
#' row per text, finite values, rows of length 1 (or 0), reported under the
#' embedder's own name with no fallback, and for an embedder registered as
#' deterministic, the same vectors from a second run (`again()`).
#' @noRd
gr_rules_embedder <- function(texts, embedder, deterministic, again) {
  list(
    matrix_shape = function(m) {
      ok <- is.matrix(m) && is.numeric(m) && nrow(m) == length(texts) && ncol(m) > 0L
      list(ok = ok, detail = if (ok) sprintf("%d x %d", nrow(m), ncol(m)) else
        sprintf("returned %s, not a numeric matrix with %d row(s)", class(m)[1], length(texts)))
    },
    finite = function(m) {
      ok <- is.numeric(m) && length(m) > 0L && all(is.finite(m))
      list(ok = ok, detail = if (ok) "" else "missing or non-finite values")
    },
    unit_rows = function(m) {
      norms <- sqrt(rowSums(m^2))
      ok <- all(abs(norms - 1) < 1e-6 | norms == 0)
      list(ok = ok, detail = if (ok) "" else
        sprintf("row lengths from %.3g to %.3g, not 1", min(norms), max(norms)))
    },
    source = function(m) {
      src <- as_chr1(attr(m, "embedding_source", exact = TRUE), "")
      ok <- identical(src, embedder) && !isTRUE(attr(m, "embedding_fallback", exact = TRUE))
      list(ok = ok, detail = if (ok) "" else sprintf("vectors came from '%s'", src))
    },
    deterministic = function(m) {
      if (!isTRUE(deterministic)) {
        return(list(ok = NA, detail = "not checked: not registered as deterministic"))
      }
      ok <- identical(unclass(again())[, ], unclass(m)[, ])
      list(ok = ok, detail = if (ok) "" else "a second run gave different vectors")
    })
}

#' The rules for a registered protocol: a gr_protocol under its own name,
#' with a question, criteria with no blank entries, a gr_fields schema or
#' none, an outline with headings, and a save and read that gives the same
#' protocol back.
#' @noRd
gr_rules_protocol <- function(name) {
  criteria_ok <- function(v) is.null(v) || (is.character(v) && all(has_visible(v)))
  list(
    protocol_class = function(p) list(ok = inherits(p, "gr_protocol"),
                                      detail = if (inherits(p, "gr_protocol")) "" else
                                        sprintf("returned class %s",
                                                paste(class(p), collapse = "/"))),
    name_matches = function(p) {
      ok <- identical(as_chr1(p$name, ""), name)
      list(ok = ok, detail = if (ok) "" else sprintf("named '%s'", as_chr1(p$name, "")))
    },
    question = function(p) {
      ok <- is.character(p$question) && length(p$question) == 1L && has_visible(p$question)
      list(ok = ok, detail = if (ok) "" else "no question")
    },
    criteria = function(p) {
      ok <- criteria_ok(p$include) && criteria_ok(p$exclude)
      list(ok = ok, detail = if (ok) "" else "a criterion is blank or not text")
    },
    fields = function(p) {
      ok <- is.null(p$fields) || inherits(p$fields, "gr_fields")
      list(ok = ok, detail = if (ok) "" else "`fields` does not come from gr_fields()")
    },
    outline = function(p) {
      o <- p$outline
      ok <- !length(o) || (is.character(o) && !is.null(names(o)) && all(has_visible(names(o))))
      list(ok = ok, detail = if (ok) "" else "the outline is not text under headings")
    },
    round_trip = function(p) {
      f <- tempfile(fileext = ".json")
      on.exit(unlink(f), add = TRUE)
      back <- suppressWarnings({
        gr_protocol_save(p, f)
        gr_protocol_read(f)
      })
      same <- vapply(c("question", "include", "exclude", "outline"), function(k) {
        identical(unname(as.character(back[[k]])), unname(as.character(p[[k]])))
      }, logical(1))
      same["fields"] <- identical(names(back$fields), names(p$fields))
      list(ok = all(same), detail = if (all(same)) "" else
        sprintf("changed on a save and read: %s", paste(names(same)[!same], collapse = ", ")))
    })
}

#' Run one registered extractor on `path` and check what it returns. Without
#' a path, the example document ([gr_example()]) is written in a format the
#' extractor claims: text, Markdown or HTML. For any other format, pass a
#' file.
#' @noRd
check_extractor <- function(extractor, path = NULL) {
  extractor <- as_chr1(extractor, "")
  ex <- registry_get("extractor", extractor)
  path <- if (is.null(path)) extractor_sample(ex) else normalizePath(as_chr1(path),
                                                                     mustWork = TRUE)
  spec <- gr_ingest_spec()
  hr_check_module(ex$fn, function() ex$fn(path, spec), rules = gr_rules_extractor(),
                  kind = "extractor", name = extractor)
}

#' A file of the example document in a format `ex` claims, written under
#' tempdir(). The example is Markdown, so a text extractor reads it as it is
#' and an HTML one is given its paragraphs as `<p>` elements.
#' @noRd
extractor_sample <- function(ex) {
  lines <- readLines(gr_example(), encoding = "UTF-8", warn = FALSE)
  exts <- ex$extensions
  html <- intersect(exts, c("html", "htm", "xhtml"))
  plain <- intersect(exts, c("md", "markdown", "txt", "text"))
  if (length(plain)) {
    f <- tempfile("hr-check-", fileext = paste0(".", plain[1]))
    writeLines(lines, f, useBytes = TRUE)
    return(f)
  }
  if (length(html)) {
    paras <- lines[has_visible(lines)]
    esc <- function(s) gsub(">", "&gt;", gsub("<", "&lt;", gsub("&", "&amp;", s, fixed = TRUE),
                                              fixed = TRUE), fixed = TRUE)
    f <- tempfile("hr-check-", fileext = paste0(".", html[1]))
    writeLines(c("<html><body>", paste0("<p>", esc(sub("^#+\\s*", "", paras)), "</p>"),
                 "</body></html>"), f, useBytes = TRUE)
    return(f)
  }
  gr_abort(sprintf(paste0("The check cannot write a sample file for extractor '%s' (%s). ",
                          "Give `path`, a file of that format."),
                   ex$name, paste(exts, collapse = ", ")), class = "gr_bad_setting")
}

#' Run one registered cleaner over the example document's blocks with
#' gr_clean() and check the result.
#' @noRd
check_cleaner <- function(cleaner) {
  cleaner <- as_chr1(cleaner, "")
  cl <- registry_get("cleaner", cleaner)
  text <- suppressWarnings(gr_ingest(gr_example(), gr_ingest_spec(clean = "none"),
                                     cache = FALSE))$blocks$text
  again <- function() gr_clean(text, steps = cleaner)
  hr_check_module(cl$fn, again, rules = gr_rules_cleaner(text, cleaner, again),
                  kind = "cleaner", name = cleaner)
}

#' Embed three short texts with one registered embedder through hr_embed()
#' and check the vectors. `client` is the offline one unless given. For
#' "api", a client with an embed function (the offline one has one) stands
#' in for the endpoint, as hr_embed() uses it for such a client.
#' @noRd
check_embedder <- function(embedder, client = NULL) {
  embedder <- as_chr1(embedder, "")
  emb <- registry_get("embedder", embedder)
  client <- check_client(client)
  texts <- c("Revenue was 45.2 million dollars.", "Costs rose in the north.",
             "Revenue was 45.2 million dollars.")
  via_client <- identical(embedder, "api") && is.function(client$embed_handler)
  again <- function() {
    if (!via_client) {
      return(hr_embed(client, texts, cache = FALSE, fallback = "error", embedder = embedder))
    }
    old <- hr_options(embedder = NULL)
    on.exit(hr_options(old), add = TRUE)
    hr_embed(client, texts, cache = FALSE, fallback = "error")
  }
  hr_check_module(emb$fn, again,
                  rules = gr_rules_embedder(texts, embedder, emb$deterministic, again),
                  kind = "embedder", name = embedder)
}

#' Check a registered protocol against the protocol rules.
#' @noRd
check_protocol <- function(protocol) {
  protocol <- as_chr1(protocol, "")
  p <- gr_protocols(protocol)
  hr_check_module(function() p, function() gr_protocols(protocol),
                  rules = gr_rules_protocol(protocol), kind = "protocol", name = protocol)
}

#' The rules for a read under a call cap of `max_calls`, on `trace`: no more
#' requests than the cap; an answer, or the refusal of class `gr_call_cap`
#' that a read raises before it starts when it would need more; and an answer
#' cut short by a refused request is marked partial.
#' @noRd
gr_rules_governor <- function(trace, max_calls) {
  list(
    within_max_calls = function(v) {
      made <- as.integer(trace$calls)
      list(ok = made <= max_calls, detail = sprintf("%d request(s) made under a cap of %d",
                                                    made, as.integer(max_calls)))
    },
    stops_cleanly = function(v) {
      ok <- inherits(v, "gr_answer") || inherits(v, "gr_call_cap")
      list(ok = ok, detail = if (inherits(v, "gr_call_cap")) "refused before the first request"
                             else if (ok) "answered" else
                               sprintf("returned class %s", paste(class(v), collapse = "/")))
    },
    partial_when_capped = function(v) {
      if (!isTRUE(trace$budget_stop) || !inherits(v, "gr_answer")) {
        return(list(ok = NA, detail = "not checked: no request was refused"))
      }
      list(ok = isTRUE(v$partial), detail = if (isTRUE(v$partial)) "" else
        "a request was refused and the answer is not marked partial")
    })
}

#' Read the example document with one registered reader under
#' `hr_governor(max_calls = max_calls)` and check that it keeps to the cap.
#' The inputs are those gr_check_reader() reads with.
#' @noRd
check_reader_governor <- function(reader, max_calls, client = NULL) {
  reader <- as_chr1(reader, "")
  rd <- registry_get("reader", reader)
  client <- check_client(client)
  chunks <- suppressWarnings(gr_segment(gr_example(),
                                        list(method = "paragraph", max_tokens = 150L)))
  spec <- c(list(reader = reader), check_read_inputs(reader))
  trace <- hr_trace(governor = hr_governor(max_calls = max_calls),
                    meta = list(check = reader))
  # Only the refusal is kept: a warning of the same class, which a read
  # gives when a batch will not fit, must not end the read.
  run <- function() {
    tryCatch(gr_read(chunks, "What was revenue?", client, spec, trace = trace),
             error = function(e) if (inherits(e, "gr_call_cap")) e else stop(e))
  }
  hr_check_module(rd$fn, run, rules = gr_rules_governor(trace, max_calls),
                  kind = "reader", name = reader)
}
