# doc-steps.R: the built-in steps of the composition layer, first part.
#
# A step is a function of (input, ctx) that does one stage of a run: ingest a
# document, cut it into chunks, rank the chunks, or read them. `ctx` is the
# context hr_benchmark() hands an arm's run function (hr_arm()), so a step
# sends its requests through `ctx$client` and records them on `ctx$trace`,
# and the benchmark counts, limits and keys them by draw. hr_step() and
# hr_chain() come later; until then, steps are composed by hand inside an
# arm's run function. Each step records its kind, name and validated spec as
# attributes, so a chain can read them when it exists.
#
# What flows between steps is a list: the item the benchmark gives the arm
# (`question` and `document`, as gr_qa_reference() builds it) with a field
# added by each step: `doc` by ingest, `chunks` by segment and retrieve. A
# read step returns the gr_answer, so it is the last step of a run.

#' Built-in steps for composing a run by hand
#'
#' `gr_step()` builds one stage of a run as a step: a function of
#' `(input, ctx)` that ingests, segments or reads. `gr_step_retrieve()`
#' builds a step that ranks the chunks against the question and keeps the
#' best, as the `retrieve` reader does, without the answer request. The
#' settings are checked when the step is built, by the spec constructors
#' ([gr_ingest_spec()], [gr_segment_spec()], [gr_read_spec()]), so a
#' misspelt or out-of-range setting fails there and not on the hundredth run
#' of a benchmark.
#'
#' A step uses `ctx$client` for its requests and records them on `ctx$trace`,
#' which is what [hr_benchmark()] gives an arm's run function: inside an
#' [hr_arm()] every request a step makes is counted, held to the benchmark's
#' limits and sent at the run's draw. Outside a benchmark, pass a list such
#' as `list(client = cl, trace = gr_trace())`.
#'
#' Steps pass a list along. The first step takes the item ([gr_qa_reference()]
#' items are lists with `question` and `document`); `"ingest"` adds `doc`,
#' `"segment"` adds `chunks` (ingesting `document` first when there is no
#' `doc`), and `gr_step_retrieve()` replaces `chunks` with the chunks it
#' kept, best first, with their scores in a `score` column. `"read"` reads
#' `chunks` (segmenting first when there are none) and returns the
#' [gr_answer], so it is the last step. Chaining them is a fold:
#' `Reduce(function(x, step) step(x, ctx), steps, item)`.
#'
#' Each step is a function with class `gr_step` and attributes `kind`,
#' `name` and `spec`, which `print()` shows. A later `hr_chain()` reads the
#' same attributes, so the steps built now are the ones it will take.
#'
#' @param kind `"ingest"`, `"segment"` or `"read"`.
#' @param ... Settings for the stage's spec constructor: [gr_ingest_spec()]
#'   for `"ingest"`, [gr_segment_spec()] for `"segment"`, [gr_read_spec()]
#'   for `"read"` (`reader = "stuff"`, say). For `gr_step_retrieve()`, the
#'   other ranking settings of [gr_read_spec()]: `min_score`, `mmr`,
#'   `fusion`, `rrf_k`, `lexical_blend`, `bm25_k1`, `bm25_b`.
#' @param name The step's name; defaults to `kind`, or `"retrieve"`.
#' @param top_k How many chunks to keep, as in [gr_read_spec()].
#' @return A function of `(input, ctx)` with class `gr_step`.
#' @seealso [hr_arm()] and [hr_benchmark()], which run steps inside an arm;
#'   [gr_arm()] for a whole recipe as one arm.
#' @family reading functions
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ctx <- list(client = cl, trace = gr_trace())
#' steps <- list(gr_step("segment", method = "paragraph", max_tokens = 120),
#'               gr_step_retrieve(top_k = 2),
#'               gr_step("read", reader = "stuff"))
#' item <- list(question = "What was revenue?", document = gr_example())
#' ans <- Reduce(function(x, step) step(x, ctx), steps, item)
#' ans$chunks_used
#'
#' # The same steps as an arm a benchmark can run.
#' arm <- hr_arm("segment-rank-read",
#'               function(item, ctx) Reduce(function(x, step) step(x, ctx), steps, item))
#' steps[[2]]
gr_step <- function(kind = c("ingest", "segment", "read"), ..., name = NULL) {
  kind <- match.arg(kind)
  spec <- switch(kind,
                 ingest = gr_ingest_spec(...),
                 segment = gr_segment_spec(...),
                 read = gr_read_spec(...))
  # gr_segment_spec() takes any method name, and gr_segment() looks it up when
  # it runs; a step looks it up now, so a typo fails where the step is built.
  if (identical(kind, "segment")) {
    registry_get("segmenters", spec$method, "segmenters", state = gr_state)
  }
  fn <- switch(kind,
    ingest = function(input, ctx = NULL) {
      state <- step_state(input)
      state$doc <- gr_ingest(step_document(state, "ingest"), spec, trace = step_trace(ctx))
      state
    },
    segment = function(input, ctx = NULL) {
      state <- step_state(input)
      doc <- state[["doc", exact = TRUE]] %||% step_document(state, "segment")
      state$chunks <- gr_segment(doc, spec, client = step_client(ctx, required = FALSE),
                                 trace = step_trace(ctx))
      state
    },
    read = function(input, ctx = NULL) {
      state <- step_state(input)
      chunks <- step_chunks(state, ctx)
      gr_read(chunks, step_question(state, "read"), step_client(ctx), spec,
              trace = step_trace(ctx))
    })
  new_step(fn, kind, name %||% kind, spec)
}

#' @rdname gr_step
#' @export
gr_step_retrieve <- function(top_k = 6L, ..., name = NULL) {
  spec <- gr_read_spec("retrieve", top_k = top_k, ...)
  fn <- function(input, ctx = NULL) {
    state <- step_state(input)
    chunks <- step_chunks(state, ctx)
    d <- chunks$chunks
    trace <- step_trace(ctx)
    if (!nrow(d)) return(state)
    # The retrieve reader's own selection (retrieve_select()), with no
    # answer request after it.
    sel <- retrieve_select(d, step_question(state, "retrieve"), step_client(ctx), spec, trace)
    kept <- d[sel$keep, , drop = FALSE]
    kept$score <- sel$scores[sel$keep]
    rownames(kept) <- NULL
    trace_note(trace, "step.retrieve", list(k = sel$k, kept = nrow(kept),
                                            chunk_ids = kept$chunk_id,
                                            embedding_source = sel$source,
                                            scores = round(kept$score, 4)))
    chunks$chunks <- kept
    chunks$retrieved <- list(from = nrow(d), embedding_source = sel$source,
                             embedding_fallback = sel$degraded)
    state$chunks <- chunks
    state
  }
  new_step(fn, "retrieve", name %||% "retrieve", spec)
}

#' @export
print.gr_step <- function(x, ...) {
  spec <- attr(x, "spec", exact = TRUE)
  set <- if (inherits(spec, "gr_read_spec")) read_settings(spec) else list()
  cat(sprintf("<gr_step> %s (%s)%s\n", attr(x, "name", exact = TRUE),
              attr(x, "kind", exact = TRUE),
              if (length(set)) paste0(": ", format_settings(set)) else ""))
  invisible(x)
}

#' A step: the function with the attributes a chain will read.
#' @noRd
new_step <- function(fn, kind, name, spec) {
  if (!is_nonblank(name)) gr_abort("`name` must be one non-blank string.", class = "gr_bad_setting")
  structure(fn, class = c("gr_step", "function"), kind = kind, name = as_chr1(name),
            spec = spec)
}

#' What a step was given, as the list steps pass along. A bare source (a
#' path, a URL, a gr_document) is a document with no question.
#' @noRd
step_state <- function(input) {
  if (is.list(input) && !inherits(input, c("gr_document", "gr_chunks"))) return(input)
  if (inherits(input, "gr_chunks")) return(list(chunks = input))
  list(document = input)
}

#' @noRd
step_document <- function(state, what) {
  doc <- state[["document", exact = TRUE]]
  if (is.null(doc)) {
    gr_abort(sprintf("The %s step needs a `document` in its input.", what),
             class = "gr_bad_setting")
  }
  doc
}

#' @noRd
step_question <- function(state, what) {
  q <- state[["question", exact = TRUE]]
  if (!is_nonblank(q)) {
    gr_abort(sprintf("The %s step needs a `question` in its input.", what),
             class = "gr_bad_setting")
  }
  q
}

#' The input's chunks, or the document segmented at the defaults.
#' @noRd
step_chunks <- function(state, ctx) {
  ch <- state[["chunks", exact = TRUE]]
  if (inherits(ch, "gr_chunks")) return(ch)
  doc <- state[["doc", exact = TRUE]] %||% step_document(state, "read")
  gr_segment(doc, client = step_client(ctx, required = FALSE), trace = step_trace(ctx))
}

#' @noRd
step_client <- function(ctx, required = TRUE) {
  cl <- if (is.list(ctx)) ctx[["client", exact = TRUE]] else NULL
  if (is.null(cl) && required) {
    gr_abort("A step that sends requests needs `ctx$client`, as hr_benchmark() gives it.",
             class = "gr_bad_setting")
  }
  cl
}

#' @noRd
step_trace <- function(ctx) {
  tr <- if (is.list(ctx)) ctx[["trace", exact = TRUE]] else NULL
  if (inherits(tr, "gr_trace")) tr else NULL
}
