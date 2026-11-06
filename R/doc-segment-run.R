# doc-segment-run.R -- AXIS 2: the public segmentation entry point.

#' Describe a segmentation configuration
#'
#' @param method Segmenter name; see `gr_segmenters()`.
#' @param max_tokens Hard cap on chunk size, in tokens. Always enforced: a
#'   segmenter cannot emit an oversized chunk, which the old `chunk_text_semantic()`
#'   routinely did. An oversized chunk is re-split, down to single characters
#'   if it has to be; if the active tokenizer counts even one character as more
#'   than the cap, [gr_segment()] stops with an error of class
#'   `"gr_cap_unenforceable"` rather than pass the chunk on.
#' @param overlap_tokens Tokens of trailing context copied into the start of the
#'   next chunk. Overlap is what stops an answer straddling a boundary from being
#'   lost by both chunks. Honoured by every segmenter except `page` (a page is
#'   the unit) and `proposition` (propositions are already self-contained).
#'   It is cut at sentences, then words; text written without spaces (Chinese,
#'   Japanese, Thai) is cut by characters. A chunk's page, section and block
#'   count the overlap it opens with, so one that carries a sentence from the
#'   page before reports `NA` rather than the page it goes on to.
#' @param min_tokens A chunk smaller than this is merged **backward** into the
#'   chunk before it. Ignored by `page` and `fixed`.
#' @param separators For `method = "recursive"`: the cascade, strongest first.
#'   Each piece keeps the separator it was cut at; past the last one, text is
#'   cut at sentence ends, then whitespace, then characters, the same way. With
#'   no overlap, the chunks joined end to end are the document text exactly.
#' @param prefix_section For `method = "structural"`: prepend the heading.
#'   When the extractor supplies no sections, headings are found inline: a
#'   markdown `#` line, or a short line that is numbered and starts with a
#'   capital of any script (or a letter of a script without case), or is in
#'   capitals.
#' @param semantic_window,semantic_percentile For `method = "semantic"`: how many
#'   sentences to embed together, and how extreme a distance counts as a
#'   boundary (higher = fewer, larger chunks).
#' @param context_source For `method = "contextual"`: `"metadata"` (free) or
#'   `"llm"` (one call per chunk). Room for the context line is held back from
#'   each chunk's text before packing -- 90 tokens for `"llm"`, the longest
#'   header the document could need for `"metadata"`, never more than half of
#'   `max_tokens` -- so no chunk is cut again once its header is added, and a
#'   header that still does not fit is shortened, never the text. Under
#'   `"llm"`, a chunk whose call failed or was skipped at the run's limits
#'   keeps its text without a context line; `$extra$blurbs_missing` counts
#'   them and a `"gr_segment_fallback"` warning says so, which also reaches
#'   the answer's warnings.
#' @param proposition_batch_tokens For `method = "proposition"`: batch size.
#' @param parallel Parallelise per-chunk model work in segmenters that do any.
#' @param ... Extra fields for custom segmenters.
#' @return A list of class `gr_segment_spec`.
#'
#' @section Out-of-range values:
#' Arguments are clamped into a usable range and the change is warned about,
#' never applied silently: `max_tokens` \[32, 1e6\], `overlap_tokens`
#' \[0, max_tokens - 1\], `min_tokens` \[0, max_tokens\], `semantic_window`
#' \[1, 10\], `semantic_percentile` \[50, 99.5\], `proposition_batch_tokens`
#' \[200, 4000\].
#'
#' @seealso [gr_segmenters()] for the available methods and their costs,
#'   [gr_segment()], [gr_chunk_stats()]
#' @family segmentation functions
#' @export
#' @examples
#' gr_segment_spec("semantic", max_tokens = 800, overlap_tokens = 80)$overlap_tokens
#'
#' # An impossible setting is corrected loudly.
#' suppressWarnings(gr_segment_spec("paragraph", max_tokens = 100,
#'                                  overlap_tokens = 500)$overlap_tokens)
gr_segment_spec <- function(method = "paragraph", max_tokens = 1200L,
                            overlap_tokens = 0L, min_tokens = 0L,
                            separators = NULL, prefix_section = TRUE,
                            semantic_window = 2L, semantic_percentile = 90,
                            context_source = c("metadata", "llm"),
                            proposition_batch_tokens = 900L, parallel = NULL, ...) {
  warn_near_miss(list(...), names(formals(gr_segment_spec)), "segment")
  # Out-of-range settings are clamped rather than accepted, but the clamp is
  # ANNOUNCED. Silently rewriting a user's parameter is how v1 ended up feeding
  # documents to the model backwards: a negative token limit went straight into
  # `split(tokens, ceiling(seq_along(tokens) / limit))` with nothing said. The
  # ranges are in the schema (.gr_segment_schema).
  p <- hr_validate(.gr_segment_schema, mget(names(.gr_segment_schema), environment()))
  structure(c(list(method = p$method, max_tokens = p$max_tokens,
                   overlap_tokens = p$overlap_tokens, min_tokens = p$min_tokens,
                   separators = p$separators, prefix_section = p$prefix_section,
                   semantic_window = p$semantic_window,
                   semantic_percentile = p$semantic_percentile,
                   context_source = p$context_source,
                   proposition_batch_tokens = p$proposition_batch_tokens,
                   parallel = p$parallel), list(...)),
            class = "gr_segment_spec")
}

#' The schema of gr_segment_spec(), in the order the constructor resolved its
#' arguments before the schema existed. The overlap and the smallest chunk are
#' bounded by `max_tokens`, so they come after it.
#'
#' NA and anything that is not a number fall back to the default of each
#' setting, never the bottom of its range: a missing semantic_percentile once
#' became 50, splitting at the median boundary rather than the 90th
#' percentile, which multiplies the chunk count and the cost. The defaults
#' match the formals; max_tokens once fell back to 800 while its formal said
#' 1200, and a test now checks every one.
#' @noRd
.gr_segment_schema <- hr_schema(
  hr_param("context_source", "enum", choices = c("metadata", "llm"), cost_class = "per_unit",
           help = "For contextual: where the context line comes from.", tier = "advanced"),
  hr_param("max_tokens", "integer", default = 1200L, min = 32, max = 1e6,
           help = "Hard cap on chunk size, in tokens.", cost_class = "per_unit"),
  hr_param("overlap_tokens", "integer", default = 0L, min = 0,
           max = function(p) p$max_tokens - 1L,
           help = "Tokens of trailing context copied into the start of the next chunk."),
  hr_param("min_tokens", "integer", default = 0L, min = 0, max = function(p) p$max_tokens,
           help = "A smaller chunk is merged into the one before it.", tier = "advanced"),
  hr_param("method", "module_ref", default = "paragraph", kind = "segmenter",
           help = "The segmentation strategy.", resolve = param_as_given),
  hr_param("separators", "string_vector", default = NULL, tier = "advanced",
           help = "For recursive: the separator cascade, strongest first.",
           resolve = param_as_given),
  hr_param("prefix_section", "boolean", default = TRUE, strict = FALSE, tier = "advanced",
           help = "For structural: prepend the heading."),
  hr_param("semantic_window", "integer", default = 2L, min = 1, max = 10, tier = "advanced",
           help = "For semantic: sentences embedded together."),
  hr_param("semantic_percentile", "number", default = 90, min = 50, max = 99.5,
           tier = "advanced", help = "For semantic: how extreme a distance counts as a boundary."),
  hr_param("proposition_batch_tokens", "integer", default = 900L, min = 200, max = 4000,
           cost_class = "per_unit", tier = "advanced",
           help = "For proposition: the size of each batch sent to the model."),
  hr_param("parallel", "boolean", default = NULL, affects_output = FALSE, tier = "advanced",
           help = "Parallelise per-chunk model work.", resolve = param_as_given)
)

#' The settings of a segment spec that differ from its defaults, as
#' read_settings() does for a read spec.
#' @noRd
segment_settings <- function(spec) {
  spec_settings(spec, suppressWarnings(gr_segment_spec(method = spec$method)), drop = "method")
}

#' Segment a document into chunks
#'
#' Segmentation is deliberately separate from ingestion: one extraction can feed
#' many different segmentations, so comparing chunking strategies costs one file
#' read, not one per strategy.
#'
#' @param doc A `gr_document` from `gr_ingest()`, or anything `gr_ingest()`
#'   accepts.
#' @param spec A `gr_segment_spec`, a segmenter name, or a named list.
#' @param client A `gr_client`, needed only by `semantic`, `proposition` and
#'   `contextual(context_source = "llm")`.
#' @param trace Optional `gr_trace`. When none is given one is made, so the
#'   model calls a segmenter makes are held to `gr_options(max_calls =,
#'   max_cost_usd =)` and recorded, and it is returned as `$trace`.
#' @return A [gr_chunks] object. If the requested segmenter could not run it
#'   falls back and records the fallback in `$method`, e.g.
#'   `"semantic->paragraph"` when no `client` was supplied. `proposition` and
#'   `contextual` chunks carry a `source_text` column: the document text each
#'   chunk was made from, without the rewrite or the context line, which is
#'   what a quote from the chunk is checked against. When no `trace` was
#'   passed, `$trace` is the one this call recorded into. `page` keeps blocks
#'   that have no page number, in a document whose other blocks have one, as
#'   chunks of their own with page `NA`, and warns.
#' @seealso [gr_segmenters()], [gr_segment_spec()], [gr_chunk_stats()], [gr_chunks]
#' @family segmentation functions
#' @export
#' @examples
#' doc <- gr_ingest(gr_example())
#'
#' # The same document, three boundary hypotheses. No API calls.
#' do.call(rbind, lapply(c("fixed", "paragraph", "sentence", "structural"),
#'   function(m) gr_chunk_stats(gr_segment(doc, list(method = m, max_tokens = 120)))))
gr_segment <- function(doc, spec = NULL, client = NULL, trace = NULL) {
  # The run's limits are counted on a trace. With none, the limit check had
  # nothing to count against and let every request through, and nothing was
  # recorded: a proposition segmentation under max_calls = 2 made nine calls
  # and left no account of them, and the Shiny preview did exactly that.
  # gr_read() makes its own for the same reason.
  own_trace <- is.null(trace)
  trace <- trace %||% gr_trace(meta = list(stage = "segment"))
  if (!inherits(doc, "gr_document")) doc <- gr_ingest(doc, trace = trace)
  spec <- as_segment_spec(spec)
  seg <- registry_get("segmenters", spec$method, "segmenters", state = gr_state)
  rec <- warning_recorder()

  gr_msg(sprintf("Segmenting with '%s' (cap %d tokens, overlap %d).",
                 spec$method, spec$max_tokens, spec$overlap_tokens))

  # Whether the segmenter said itself that it fell back, whoever raised the
  # warning: a registered segmenter cannot call gr_warn(), so its own warning
  # is a plain condition of the class and not a gr_warning.
  said_fallback <- FALSE
  out <- withCallingHandlers(seg$fn(doc, spec, client, trace),
    gr_warning = rec$record,
    gr_segment_fallback = function(w) said_fallback <<- TRUE)
  if (!inherits(out, "gr_chunks")) gr_abort(sprintf("Segmenter '%s' did not return a gr_chunks object.", spec$method))
  # Checked after the segmenter has run, so one fallback gives one warning. The
  # built-ins name what they fell back to, and so can a registered segmenter;
  # this generic warning is for one that stays silent. When this was decided
  # before the call, from a list of built-in names, a registered segmenter that
  # warned got a second warning and a silent one registered under a built-in's
  # name got none.
  if (isTRUE(seg$needs_client) && is.null(client) && !said_fallback) {
    withCallingHandlers(
      gr_warn(sprintf("Segmenter '%s' needs a client and none was supplied, so it ran without one.",
                      spec$method), class = "gr_segment_fallback"),
      gr_warning = rec$record)
  }

  # Final invariant check. A segmenter that violates the cap is a bug in the
  # segmenter, not something to pass downstream where it becomes an HTTP 400.
  over <- which(out$chunks$tokens > spec$max_tokens)
  if (length(over)) {
    gr_msg(sprintf("Enforcing the token cap on %d oversized chunk(s) from '%s'.",
                   length(over), spec$method))
    src <- out$chunks
    pieces <- lapply(seq_len(nrow(src)), function(i) {
      if (src$tokens[i] <= spec$max_tokens) src$text[i]
      else hard_split(src$text[i], spec$max_tokens)
    })
    # Carry provenance across the split: every piece inherits the page, section
    # and block of the chunk it came from. Rebuilding without this silently
    # turned page/section into NA and broke citations for the whole run.
    rep_n <- vapply(pieces, length, integer(1))
    # And the source text, which is what a quote from a piece is checked
    # against: losing it here would put the model's words back in its place.
    # A piece cut from text that was the document's own is still its own.
    src_text <- src[["source_text", exact = TRUE]]
    out2 <- new_chunks(unlist(pieces, use.names = FALSE), out$method, spec,
                       page = rep(src$page, rep_n),
                       section = rep(src$section, rep_n),
                       block_id = rep(src$block_id, rep_n),
                       source_text = if (!is.null(src_text)) rep(src_text, rep_n))
    out2$extra <- c(out$extra, list(cap_enforced = length(over)))
    out <- out2
    # hard_split() measures every piece and goes down to single characters, so
    # nothing should be left over the cap. This pass used to run once and pass
    # whatever came back, and 2,311-token chunks went on under a 500-token cap.
    # A chunk still over it now means the tokenizer counts one character as
    # more than the cap, and sending it would be the HTTP 400 this is here to
    # prevent.
    still <- which(out$chunks$tokens > spec$max_tokens)
    if (length(still)) {
      gr_abort(sprintf(paste0("Cannot hold '%s' chunks to the %d-token cap: %d chunk(s) are over it ",
                              "even split to single characters, so the tokenizer ('%s') counts ",
                              "one character as more than the cap."),
                       spec$method, spec$max_tokens, length(still), gr_tokenizer()),
               class = "gr_cap_unenforceable")
    }
  }
  if (!nrow(out$chunks)) {
    gr_abort(sprintf("Segmenter '%s' produced no chunks from a %d-token document.",
                     spec$method, doc$stats$tokens), class = "gr_empty_chunks")
  }
  trace_note(trace, "segment", c(list(method = spec$method),
                                 as.list(gr_chunk_stats(out))[-1],
                                 list(settings = segment_settings(spec))))
  # What the document could not give, carried to whatever reads these chunks:
  # the warnings raised while it was ingested and cut, and the pages that never
  # became text. gr_read() puts both on the answer.
  out$warnings <- c(doc$warnings %||% character(0), rec$get())
  out$unread_pages <- doc$stats$unread_pages %||% integer(0)
  # A trace the caller passed is theirs already, and a pipeline's trace would
  # only bloat every chunk set it touched.
  if (own_trace) out$trace <- trace
  out
}

#' @noRd
as_segment_spec <- function(spec) {
  if (inherits(spec, "gr_segment_spec")) return(spec)
  if (is.null(spec)) return(gr_segment_spec())
  if (is.character(spec) && length(spec) == 1L) return(gr_segment_spec(method = spec))
  if (is.list(spec)) return(do.call(gr_segment_spec, spec))
  gr_abort("`segment` must be a gr_segment_spec, a segmenter name, or a named list.")
}

#' The label a built-in segmenter's requests carry: "" for one that sends
#' none, and NA for any other segmenter, including another function registered
#' under a built-in's name. By function, not by name, for that reason.
#' @noRd
segment_effort_label <- function(segment) {
  fn <- gr_state$segmenters[[as_chr1(segment$method, "")]]$fn
  if (is.null(fn)) return(NA_character_)
  is_fn <- function(f) identical(fn, f)
  if (is_fn(seg_proposition)) return("segment.proposition")
  if (is_fn(seg_contextual)) {
    return(if (identical(as_chr1(segment$context_source, ""), "llm")) "segment.context" else "")
  }
  silent <- list(seg_fixed, seg_paragraph, seg_sentence, seg_recursive, seg_structural, seg_page,
                 seg_semantic)
  if (any(vapply(silent, is_fn, logical(1)))) "" else NA_character_
}

#' Register a segmentation strategy
#'
#' Axis 2 is a registry, so "where does meaning break in this document?" is a
#' question you can answer for your own material rather than choosing from a
#' fixed list. A registered segmenter is a first-class one: it appears in
#' [gr_segmenters()], can be named in a [gr_recipe()], and goes through the same
#' token-cap enforcement and reporting as the built-ins.
#'
#' @param name Segmenter name, used in specs and recipes. Re-registering an
#'   existing name replaces it.
#' @param fn Function of `(doc, spec, client, trace)` returning a `gr_chunks`.
#'   Build the return value with [new_chunks()]; [gr_segment()] rejects
#'   anything else. `doc` is a [gr_document]; `spec` carries `max_tokens`,
#'   `overlap_tokens` and `min_tokens`, which [pack_units-style][new_chunks]
#'   helpers respect for you.
#' @param description One-line description, shown by [gr_segmenters()].
#' @param cost `"free"`, `"embedding"` or `"llm"`: what one run spends, so a
#'   UI can warn before it is spent.
#' @param needs_client Whether the segmenter requires a client. [gr_segmenters()]
#'   reports it, so a UI can check before offering the strategy. When `TRUE` and
#'   no client is supplied, [gr_segment()] calls `fn` and then warns with class
#'   `"gr_segment_fallback"`, unless `fn` raised a warning of that class itself,
#'   so one fallback gives one warning. Raising your own is better, because it
#'   can name what `fn` fell back *to*:
#'   `warning(warningCondition("No client; using 'paragraph'.", class =
#'   "gr_segment_fallback"))`. Record the downgrade in the returned `method`
#'   (`"mine->paragraph"`) so it survives into `gr_chunk_stats()`.
#' @param calls The stems of the trace labels the segmenter's model calls
#'   carry, such as `"mine.rewrite"`; `character(0)` for one that makes none.
#'   An `effort` map may only name declared stems (see [gr_read_spec()]).
#'   `NULL` (the default) declares the segmenter's name.
#' @return Invisibly, `name`.
#' @seealso [new_chunks()] to build the return value, [gr_segmenters()],
#'   [gr_segment()], [gr_segment_spec()], [gr_recipe()]
#' @family segmentation functions
#' @export
#' @examples
#' # One chunk per bullet list. Build the result with the same helper the
#' # built-ins use, so the token cap and reporting still apply.
#' gr_register_segmenter("by_bullet", description = "one chunk per bullet",
#'   fn = function(doc, spec, client, trace) {
#'     units <- unlist(strsplit(doc$text, "\n(?=[-*])", perl = TRUE))
#'     new_chunks(units, "by_bullet", spec)
#'   })
#' subset(gr_segmenters(), name == "by_bullet")
gr_register_segmenter <- function(name, fn, description = "",
                                  cost = c("free", "embedding", "llm"),
                                  needs_client = FALSE, calls = NULL) {
  cost <- match.arg(cost)
  if (!is.function(fn)) gr_abort("`fn` must be a function of (doc, spec, client, trace).")
  calls <- check_calls(calls, as_chr1(name, ""))
  registry_set("segmenters", name, list(name = name, fn = fn, description = description,
                                        cost = cost, needs_client = needs_client,
                                        calls = calls), state = gr_state)
}

#' List registered segmentation strategies
#'
#' The catalogue for axis 2. Use it to see which strategies are free, which
#' spend an embedding pass or a model call, and which need a client at all.
#' The last is checkable here rather than only in prose, because a segmenter
#' that needs a client and does not get one falls back to a different strategy.
#'
#' @return A data frame with one row per registered segmenter: `name`, `cost`
#'   (`"free"`, `"embedding"` or `"llm"`), `needs_client` (`"TRUE"`/`"FALSE"`;
#'   when `TRUE` and no client is supplied, [gr_segment()] warns and the
#'   segmenter falls back), `description`, and `calls`, the stems of the
#'   labels its model calls carry, joined by commas (empty for one that makes
#'   none).
#' @seealso [gr_segment()], [gr_segment_spec()], [gr_register_segmenter()],
#'   [gr_chunk_stats()] to compare what they produce
#' @family segmentation functions
#' @export
#' @examples
#' gr_segmenters()
#'
#' # The ones that cost money, and the ones that need a client to work at all.
#' subset(gr_segmenters(), cost != "free" | needs_client == "TRUE")[, 1:3]
gr_segmenters <- function() {
  with_calls(registry_table("segmenters", c("cost", "needs_client", "description"),
                            state = gr_state), gr_state$segmenters)
}
