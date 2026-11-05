# doc-bench-compare.R: several recipes run over one document and compared.

#' Run several recipes over one document and compare them
#'
#' Each recipe is an independent pipeline, so a recipe's answer is identical
#' whether it is run alone or alongside others. Extraction is shared through the
#' ingest cache, and segmentation is shared between recipes whose segment specs
#' are identical, so comparing five readers over one chunking costs one
#' chunking, not five.
#'
#' Recipes that resolve to identical ingestion, identical segmentation *and* an
#' identical read spec are collapsed with a warning rather than billed twice. A
#' shared reader signature alone is not enough: two `retrieve` recipes with
#' different `top_k` share a signature and are genuinely different runs.
#'
#' A comparison is one run for the spending limit: `max_cost_usd` in
#' [gr_options()] is checked against what every recipe and every segmentation
#' has spent so far, so a recipe that reaches it stops `partial` and the ones
#' after it are refused and recorded as failed. `max_calls` is counted for
#' each recipe on its own, its segmentation included, so a recipe's answer
#' does not depend on its position in the list. A segmentation that a limit
#' cut short is not shared with a later recipe.
#'
#' @param source File path, web address, or raw text; see [gr_ingest()].
#' @param question The question.
#' @param recipes A character vector of recipe names, or a list of `gr_recipe`s.
#' @param client A `gr_client`.
#' @param allow_duplicates Run duplicates anyway (useful at temperature > 0 to
#'   measure variance).
#' @param on_error `"continue"` keeps going and records the failure;
#'   `"stop"` aborts the whole comparison.
#' @param ... Overrides applied to every recipe.
#' @return A list with `answers` (named list of [gr_answer]), `summary` (a data
#'   frame with columns `recipe`, `segmenter`, `chunks`, `reader`, `signature`,
#'   `settings`, `partial`, `chunks_used`, `answer_chars`, `not_found`, `error`,
#'   and `premise` when a recipe checks the question's premise; see `premise`
#'   in [gr_read_spec()]), `trace`
#'   (shared across all recipes, so it records every recipe's calls) and
#'   `document` (source and ingestion stats).
#' @seealso [answer_document()], [gr_recipes()], [gr_recipe()], [gr_answer]
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#'
#' # Three pipelines over one document. Extraction is shared, so this costs one
#' # extraction, not three; only the segmentation and the reader vary.
#' cmp <- gr_compare(readgpt_example(), "What was revenue?",
#'                   c("fast", "precise", "needle"), client = cl)
#' cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "signature", "chunks_used")]
#'
#' # One trace covers all three, so this is the cost of the whole comparison.
#' gr_trace_summary(cmp$trace)
gr_compare <- function(source, question, recipes = c("fast", "needle", "thorough"),
                       client = NULL, allow_duplicates = FALSE,
                       on_error = c("continue", "stop"), ...) {
  on_error <- match.arg(on_error)
  # UTF-8 and labelled; see gr_read().
  if (is.character(question)) question <- to_utf8(question)
  if (!is_nonblank(question)) gr_abort("`question` must be a non-empty string.")
  # A single gr_recipe IS a list (name/ingest/segment/read), so iterating it
  # walked its four FIELDS and tried to treat each as a recipe. Wrap it.
  if (inherits(recipes, "gr_recipe")) recipes <- list(recipes)
  if (!length(recipes)) {
    gr_abort(paste0("`recipes` is empty. Pass at least one recipe name, reader name, ",
                    "gr_recipe or spec list; see gr_recipes() for the built-ins."),
             class = "gr_no_recipes")
  }
  recs <- lapply(seq_along(recipes), function(i) {
    nm <- if (!is.null(names(recipes))) names(recipes)[i] else NULL
    apply_overrides(as_recipe(recipes[[i]], fallback_name = nm), list(...))
  })
  names(recs) <- vapply(recs, function(r) r$name, character(1))
  if (anyDuplicated(names(recs))) names(recs) <- make.unique(names(recs), sep = "#")

  # Distinctness check: identical segmentation + identical reader signature
  # means identical work. This is precisely the Chunked/Semantic collapse.
  # Hash the WHOLE read spec, not a hand-picked subset. The subset omitted
  # rerank_candidates, min_score, temperature, max_levels, on_overflow,
  # skim_model and the token caps -- all of which change which chunks reach the
  # model or how it answers -- so genuinely different recipes were silently
  # collapsed into one and never run.
  keys <- vapply(recs, function(r) paste0(
    gr_hash(unclass(r$segment)), "|",
    tryCatch(gr_reader_signature(r$read), error = function(e) r$read$reader), "|",
    gr_hash(unclass(r$read)), "|",
    gr_hash(unclass(r$ingest))), character(1))
  if (!allow_duplicates && anyDuplicated(keys)) {
    dups <- split(names(recs), keys)
    dups <- dups[vapply(dups, length, integer(1)) > 1L]
    for (g in dups) {
      gr_warn(sprintf(paste0("Recipes %s are the same pipeline: identical ingestion, identical ",
                             "segmentation and the same reader signature. Running only '%s'. ",
                             "Pass allow_duplicates = TRUE to run them anyway."),
                      paste(sprintf("'%s'", g), collapse = ", "), g[1]),
              class = "gr_duplicate_recipe")
    }
    recs <- recs[!duplicated(keys)]
  }

  trace <- gr_trace(meta = list(question = question, recipes = names(recs),
                                source = source_label(source)))
  client <- client %||% gr_client(model = recs[[1]]$read$model)
  stop_if_no_credentials(client)
  doc <- gr_ingest(source, recs[[1]]$ingest, trace = trace)

  seg_cache <- new.env(parent = emptyenv())
  answers <- list()
  for (nm in names(recs)) {
    r <- recs[[nm]]
    # Each recipe gets its own call count, then its steps are folded into the
    # shared trace. Sharing the trace outright meant `max_calls` counted
    # earlier recipes against later ones, so the same recipe returned a
    # different answer depending on its position in the comparison. That
    # holds for its segmentation as much as its read: an LLM segmenter run on
    # the shared trace met the cap early, kept batches as written, and handed
    # the recipe different chunks than it got alone.
    # Made before the tryCatch and folded in after it, so a recipe that fails
    # after spending still has its requests in the comparison's trace.
    sub <- gr_trace(meta = list(recipe = nm, source = source_label(source)))
    # Where this recipe's steps start in the comparison's trace, for the answer
    # of a recipe that fails, which is made on that trace.
    start <- length(trace$steps)
    seed <- 0
    rseed <- 0
    seeded_calls <- 0L
    seg_steps <- 0L
    out <- tryCatch({
      d <- if (identical(gr_hash(unclass(r$ingest)), gr_hash(unclass(recs[[1]]$ingest)))) doc
           else gr_ingest(source, r$ingest, trace = trace)
      # Money is the exception. `max_cost_usd` is a limit on the run, and a
      # comparison is one run: a fresh count for each recipe let four recipes
      # spend four times the limit with nothing stopped and nothing partial.
      # So each recipe starts from what the comparison has spent, and its
      # segmentation, pre-flight and every request check the total.
      seed <- as_num1(trace$spent_usd, 0)
      sub$spent_usd <- seed
      # And what the calls a replay answered from its recording cost when they
      # were recorded, which the limit counts as well (budget_spent()): seeded
      # the same way, so a replay of a comparison the limit stopped stops each
      # recipe where the recording did, rather than going past the stop.
      rseed <- as_num1(trace$replayed_usd, 0)
      sub$replayed_usd <- rseed
      # What the comparison had spent beyond that, for the progress line, which
      # adds this trace's own spend. NA, when a cost is unknown, stays NA.
      sub$spent_before <- sum(gr_trace_cost(trace)$usd) - seed
      # Key on the document's actual TEXT, not its character count. Counting
      # characters meant any length-preserving cleaner produced a cache hit on
      # different text, and one recipe was handed another recipe's chunks --
      # order-dependent, silent, and wrong.
      # And on what the document could not give: chunks carry the unread pages
      # and the warnings of the ingestion that produced them, so two ingestions
      # with the same text but different losses must not share chunks.
      # With the reasoning effort a segmenter that calls a model sends: two
      # recipes differing in it must not share chunks one of them cut at the
      # other's effort. Unchanged without one, and for a segmenter that sends
      # none (segment_effort()).
      seg <- segment_effort(r$segment, r$read)
      skey <- gr_hash(list(d$text, unclass(seg), d$stats$unread_pages, d$warnings))
      hit <- seg_cache[[skey]]
      if (is.null(hit)) {
        ch <- gr_segment(d, seg, client = client, trace = sub)
        seg_steps <- length(sub$steps)
        # A chunking a limit cut short is this recipe's, not the one another
        # recipe with the same segment spec would get on its own.
        if (!isTRUE(sub$budget_stop)) seg_cache[[skey]] <- list(chunks = ch, calls = sub$calls)
      } else {
        ch <- hit$chunks
        # Charged the requests the chunking took, as it would be run alone, and
        # relieved of them below before its steps are folded in, since it did
        # not make them.
        seeded_calls <- as.integer(hit$calls)
        sub$calls <- sub$calls + seeded_calls
      }
      a <- gr_read(ch, question, client, r$read, trace = sub)
      finish_answer(a, d, ch, nm)
    }, error = function(e) {
      # Every recipe would fail the same way, so a missing key is not one
      # recipe's failure.
      if (inherits(e, "gr_auth_error")) stop(e)
      if (identical(on_error, "stop")) stop(e)
      gr_warn(sprintf("Recipe '%s' failed: %s", nm, conditionMessage(e)))
      # A failed recipe is RECORDED, not deleted. `answers[[nm]] <- NULL` in the
      # old code removed the key entirely and left the caller unable to tell
      # which mode had failed.
      a <- new_answer(.NOT_FOUND, r$read$reader, question, integer(0), trace,
                      partial = TRUE, notes = list(error = conditionMessage(e)))
      a$recipe <- nm
      a
    })
    # Only this recipe's spend and requests are folded in: the seeds are
    # already there.
    sub$spent_usd <- sub$spent_usd - seed
    sub$replayed_usd <- as_num1(sub$replayed_usd, 0) - rseed
    sub$calls <- sub$calls - seeded_calls
    off <- length(trace$steps)
    trace_absorb(trace, sub)
    # A failed recipe's answer is on the comparison's trace, which holds every
    # recipe: its steps are the ones from where it began to the requests just
    # folded in (answer_trace()).
    if (identical(out[["trace", exact = TRUE]], trace)) {
      out$trace_steps <- c(first = start + 1L, last = length(trace$steps))
    }
    # A chunking is the comparison's, shared with any later recipe that cuts
    # the document the same way, so its requests belong to no recipe in the
    # comparison's trace, as they did when they were made on it.
    for (i in off + seq_len(seg_steps)) trace$steps[[i]]$recipe <- NA_character_
    answers[[nm]] <- out
  }

  summary <- do.call(rbind, lapply(names(answers), function(nm) {
    a <- answers[[nm]]
    seg <- a$segmentation %||% list(method = NA_character_, n = NA_integer_)
    r <- recs[[nm]]
    data.frame(recipe = nm, segmenter = as_chr1(seg$method, NA_character_),
               chunks = as.integer(seg$n %||% NA), reader = a$reader,
               signature = as_chr1(a$signature, NA_character_),
               # Recipes differing only in a setting -- top_k, mmr, max_tokens --
               # were indistinguishable here. Name what was changed.
               settings = if (is.null(r)) NA_character_ else
                 format_settings(c(read_settings(r$read), segment_settings(r$segment))),
               partial = a$partial,
               chunks_used = length(a$chunks_used),
               answer_chars = nchar(a$answer),
               not_found = is_not_found(a$answer),
               error = answer_error(a),
               stringsAsFactors = FALSE)
  }))
  # What the model said the document states instead of the question's premise,
  # or NA, when any recipe checked it. Last, and only then, so a comparison that
  # did not check has the columns, in the places, it always had.
  if (any(vapply(recs, function(r) isTRUE(r$read$premise), logical(1)))) {
    summary$premise <- unname(vapply(names(answers), function(nm) answer_premise(answers[[nm]]),
                                     character(1)))
  }
  list(answers = answers, summary = summary, trace = trace,
       document = list(source = doc$source, stats = doc$stats))
}
