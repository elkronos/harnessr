# doc-steps.R: the built-in steps of the composition layer.
#
# A step is a function of (input, ctx) that does one stage of a run: ingest a
# document, cut it into chunks, rank the chunks, or read them. `ctx` is the
# context hr_benchmark() hands an arm's run function (hr_arm()), so a step
# sends its requests through `ctx$client` and records them on `ctx$trace`,
# and the benchmark counts, limits and keys them by draw. Each step is built
# by hr_step() with a `build` function, so its settings are checked against
# the stage's schema and its spec constructor when it is built, and
# hr_chain() runs steps in order as one arm.
#
# What flows between steps is a list: the item the benchmark gives the arm
# (`question` and `document`, as gr_qa_reference() builds it) with a field
# added by each step: `doc` by ingest, `chunks` by segment and retrieve. A
# read step returns the gr_answer.

#' Built-in steps for composing a run
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
#' as `list(client = cl, trace = hr_trace())`.
#'
#' Steps pass a list along. The first step takes the item ([gr_qa_reference()]
#' items are lists with `question` and `document`); `"ingest"` adds `doc`,
#' `"segment"` adds `chunks` (ingesting `document` first when there is no
#' `doc`), and `gr_step_retrieve()` replaces `chunks` with the chunks it
#' kept, best first, with their scores in a `score` column. `"read"` reads
#' `chunks` (segmenting first when there are none) and returns the
#' [gr_answer]. [hr_chain()] runs steps in order as one arm; by hand, the
#' same is a fold: `Reduce(function(x, step) step(x, ctx), steps, item)`.
#'
#' Each step is an [hr_step()] with class `gr_step` added and the
#' attributes `kind` and `spec`, which `print()` shows. Its settings are
#' checked against the stage's schema: [gr_ingest_spec()]'s, [gr_segment_spec()]'s
#' or [gr_read_spec()]'s for `gr_step()`, and for `gr_step_retrieve()` the
#' ranking settings `top_k`, `min_score`, `mmr`, `fusion`, `rrf_k`,
#' `lexical_blend`, `bm25_k1` and `bm25_b`. Any other setting passed to
#' `gr_step_retrieve()` reaches [gr_read_spec()] as it is. A step declares
#' what it takes and returns, which [hr_chain()] checks: ingest takes a
#' document and returns a doc, segment takes a doc and returns chunks,
#' retrieve takes and returns chunks, and read takes chunks and returns the
#' answer.
#'
#' These steps take no skill ([hr_skill()]): their requests are built by the
#' stage, not sent through `ctx$call()`, so a skill would not reach them.
#' Passing `skill` is an error of class `hr_bad_skill`.
#'
#' @param kind `"ingest"`, `"segment"` or `"read"`.
#' @param ... Settings for the stage's spec constructor: [gr_ingest_spec()]
#'   for `"ingest"`, [gr_segment_spec()] for `"segment"`, [gr_read_spec()]
#'   for `"read"` (`reader = "stuff"`, say). For `gr_step_retrieve()`, the
#'   other ranking settings of [gr_read_spec()]: `min_score`, `mmr`,
#'   `fusion`, `rrf_k`, `lexical_blend`, `bm25_k1`, `bm25_b`.
#' @param name The step's name; defaults to `kind`, or `"retrieve"`.
#' @param top_k How many chunks to keep, as in [gr_read_spec()].
#' @return A function of `(input, ctx)` with class
#'   `c("gr_step", "hr_step", "function")`.
#' @seealso [hr_chain()], which runs steps as one arm; [hr_step()] for a
#'   step of your own; [gr_arm()] for a whole recipe as one arm.
#' @family reading functions
#' @export
#' @examples
#' cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ctx <- list(client = cl, trace = hr_trace())
#' steps <- list(gr_step("segment", method = "paragraph", max_tokens = 120),
#'               gr_step_retrieve(top_k = 2),
#'               gr_step("read", reader = "stuff"))
#' item <- list(question = "What was revenue?", document = gr_example())
#' ans <- Reduce(function(x, step) step(x, ctx), steps, item)
#' ans$chunks_used
#'
#' # The same steps as an arm a benchmark can run.
#' arm <- hr_chain(segment = steps[[1]], retrieve = steps[[2]], read = steps[[3]],
#'                 name = "segment-rank-read")
#' steps[[2]]
gr_step <- function(kind = c("ingest", "segment", "read"), ..., name = NULL) {
  kind <- match.arg(kind)
  step_refuse_skill(names(list(...)), "gr_step()")
  ctor <- switch(kind, ingest = gr_ingest_spec, segment = gr_segment_spec, read = gr_read_spec)
  schema <- switch(kind, ingest = .gr_ingest_schema, segment = .gr_segment_schema,
                   read = .gr_read_schema)
  build <- function(params) {
    spec <- step_spec(ctor, params)
    # gr_segment_spec() takes any method name, and gr_segment() looks it up
    # when it runs; a step looks it up now, so a typo fails where the step is
    # built.
    if (identical(kind, "segment")) {
      registry_get("segmenter", spec$method)
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
    structure(fn, class = c("gr_step", "function"), kind = kind, spec = spec)
  }
  io <- switch(kind, ingest = c("document", "doc"), segment = c("doc", "chunks"),
               read = c("chunks", "answer"))
  hr_step(name %||% kind, params = step_args(ctor, list(...)), schema = schema,
          input = io[1], output = io[2], version = step_version(), build = build)
}

#' @rdname gr_step
#' @export
gr_step_retrieve <- function(top_k = 6L, ..., name = NULL) {
  step_refuse_skill(names(list(...)), "gr_step_retrieve()")
  given <- c(if (!missing(top_k)) list(top_k = top_k), list(...))
  params <- step_args(gr_read_spec, c(list(reader = "retrieve"), given))
  params$reader <- NULL
  build <- function(params) {
    spec <- step_spec(gr_read_spec, c(list(reader = "retrieve"), params))
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
      chunks$retrieved <- c(list(from = nrow(d), embedding_source = sel$source,
                                 embedding_fallback = sel$degraded),
                            if (isTRUE(sel$below_min_score)) list(below_min_score = TRUE))
      state$chunks <- chunks
      state
    }
    structure(fn, class = c("gr_step", "function"), kind = "retrieve", spec = spec)
  }
  hr_step(name %||% "retrieve", params = params, schema = .gr_retrieve_step_schema,
          input = "chunks", output = "chunks", version = step_version(), build = build)
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

#' The schema of gr_step_retrieve(): the ranking settings of the read schema,
#' in its order.
#' @noRd
.gr_retrieve_step_schema <- do.call(hr_schema, unname(unclass(.gr_read_schema)[
  intersect(names(.gr_read_schema),
            c("top_k", "min_score", "mmr", "fusion", "rrf_k", "lexical_blend",
              "bm25_k1", "bm25_b"))]))

#' A built-in step takes no skill: its requests are built by the stage it
#' runs, not sent through ctx$call(), so a skill would never reach them.
#' @noRd
step_refuse_skill <- function(given, fun) {
  if ("skill" %in% given) {
    gr_abort(sprintf(paste0("%s does not take a skill: its requests are built by the stage it ",
                            "runs, so the skill would not reach them. Give a skill to a step of ",
                            "your own, built with hr_step(), that sends its requests through ",
                            "ctx$call()."), fun),
             class = c("hr_bad_skill", "gr_bad_setting"))
  }
  invisible(NULL)
}

#' The arguments given to a step, named as a call to its spec constructor
#' would match them, so a setting given by position or by a partial name
#' reaches the schema under its full name.
#' @noRd
step_args <- function(ctor, args) {
  if (!length(args)) return(list())
  m <- match.call(ctor, as.call(c(list(quote(ctor)), args)), expand.dots = TRUE)
  out <- as.list(m)[-1]
  if (length(out) && (is.null(names(out)) || any(!nzchar(names(out))))) {
    gr_abort("Every setting given to a step must be named.", class = "gr_bad_setting")
  }
  out
}

#' The spec constructor called on a step's settings. The settings were
#' resolved by the schema when the step was built, which already warned
#' about an effort level it does not know, so the constructor's own check
#' does not warn again.
#' @noRd
step_spec <- function(ctor, params) {
  withCallingHandlers(do.call(ctor, params),
                      gr_effort_unknown = function(w) invokeRestart("muffleWarning"))
}

#' The package's version, which a built-in step records as its own.
#' @noRd
step_version <- function() {
  tryCatch(as.character(utils::packageVersion("harnessr")), error = function(e) "0.0.0")
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
