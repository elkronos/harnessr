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
#' Each row of `summary` says what its recipe cost, priced from the requests
#' on the trace by the model each one used (see [gr_trace_cost()]). A recipe is
#' charged what it would cost run alone: a segmentation it shares with an
#' earlier recipe is charged to both, as `max_calls` counts it for both, so
#' `sum(summary$usd)` can be more than the comparison spent, which is
#' `sum(gr_trace_cost(trace)$usd)`. Give `correct` and each row also says
#' whether the answer was right and what a right answer cost.
#'
#' The comparison is descriptive: one run of each recipe on one question,
#' with no interval. Run-to-run spread can exceed the gap between recipes, so
#' to say one recipe is better, compare them over a reference of questions
#' with repeated runs: build the arms with [gr_arms()] and the questions with
#' [gr_qa_reference()], run them with [hr_benchmark()], and read the
#' intervals from [hr_report()].
#'
#' A comparison is one run for the spending and token limits: `max_cost_usd`
#' and `max_tokens_total` in [gr_options()] are checked against what every
#' recipe and every segmentation has spent and used so far, so a recipe that
#' reaches either limit stops `partial` and the ones after it are refused and
#' recorded as failed. `max_calls` is counted for
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
#' @param correct How to tell whether an answer is right, for the `correct`
#'   and `usd_per_correct` columns. `NULL` (the default) adds neither. A
#'   character vector marks an answer right when its text contains any of the
#'   strings, ignoring case and runs of white space; an answer that found
#'   nothing, or a recipe that failed, is wrong, and one that found nothing
#'   because a limit stopped it is `NA`: the spending, token or call limit,
#'   the model allow-list or the output ceiling. A function is called with
#'   each recipe's [gr_answer] and returns `TRUE`, `FALSE` or `NA` (not
#'   known); when it fails or returns anything else, a warning of class
#'   `gr_bad_correct` names the recipe and its `correct` is `NA`. An invalid
#'   `correct` argument is an error of the same class.
#' @param ... Overrides applied to every recipe.
#' @return A list with `answers` (named list of [gr_answer]), `summary`, `trace`
#'   (shared across all recipes, so it records every recipe's calls) and
#'   `document` (source and ingestion stats). `summary` is a data frame with
#'   one row per recipe and these columns:
#'   \describe{
#'     \item{`recipe`, `segmenter`, `chunks`, `reader`, `signature`,
#'       `settings`}{Which pipeline the row is, and what was changed from the
#'       recipe's defaults.}
#'     \item{`partial`, `chunks_used`, `answer_chars`, `not_found`,
#'       `error`}{What the answer is, and what went wrong, if anything.}
#'     \item{`calls`, `tokens_in`, `tokens_out`}{The model and embeddings
#'       requests the recipe made, its segmentation's included, and the tokens
#'       of those that were billed: a request answered from a cache or a
#'       recording is counted in `calls` and costs nothing.}
#'     \item{`usd`}{What those requests cost, at the prices registered with
#'       [gr_register_model()]. `NA` when a model the recipe used has no
#'       registered price.}
#'     \item{`usd_estimated`}{The share of `usd` spent on requests whose token
#'       counts were estimated locally because the provider reported none, from
#'       0 to 1. `NA` when no request records how its counts were obtained, or
#'       when `usd` is 0 or unknown.}
#'     \item{`correct`, `usd_per_correct`}{Only with `correct`: whether the
#'       answer was right, and `usd` divided by the number of right answers,
#'       which is `usd` for a right answer, `Inf` for a wrong one that cost
#'       something and `NA` for a wrong one that cost nothing or one whose
#'       correctness is not known.}
#'     \item{`premise`}{Only when a recipe checks the question's premise: what
#'       the model said the document states instead, or `NA`; see `premise` in
#'       [gr_read_spec()].}
#'   }
#' @seealso [answer_document()], [gr_recipes()], [gr_recipe()], [gr_answer],
#'   [hr_benchmark()] for the comparison with intervals
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#'
#' # Three pipelines over one document. Extraction is shared, so this costs one
#' # extraction, not three; only the segmentation and the reader vary.
#' cmp <- gr_compare(gr_example(), "What was revenue?",
#'                   c("fast", "precise", "needle"), client = cl)
#' cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "signature", "chunks_used")]
#'
#' # One trace covers all three, so this is the cost of the whole comparison.
#' gr_trace_summary(cmp$trace)
#'
#' # What each recipe cost, and what a right answer cost. The mock is free, so
#' # register a price for it under another name to see the columns filled.
#' gr_register_model("priced-mock", context_window = 128000, max_output = 4096,
#'                   input_usd = 2, output_usd = 8)
#' cmp <- gr_compare(gr_example(), "What was revenue?", c("fast", "precise"),
#'                   client = cl, model = "priced-mock", correct = "45.2 million")
#' cmp$summary[, c("recipe", "calls", "usd", "correct", "usd_per_correct")]
gr_compare <- function(source, question, recipes = c("fast", "needle", "thorough"),
                       client = NULL, allow_duplicates = FALSE,
                       on_error = c("continue", "stop"), correct = NULL, ...) {
  on_error <- match.arg(on_error)
  if (!is.null(correct) && !is.function(correct) &&
      !(is.character(correct) && length(correct) && all(vapply(correct, is_nonblank, logical(1))))) {
    gr_abort("`correct` must be NULL, a function of a gr_answer, or non-empty strings.",
             class = "gr_bad_correct")
  }
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
  # Where in the comparison's trace each shared chunking's requests are, so a
  # recipe that reuses one is charged for it in the cost columns.
  seg_at <- new.env(parent = emptyenv())
  steps_of <- list()
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
    tseed <- c(tokens_in = 0, tokens_out = 0, embed_tokens = 0)
    seeded_calls <- 0L
    seg_steps <- 0L
    skey <- NULL
    seg_hit <- FALSE
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
      # And the tokens, for `max_tokens_total`, which is a limit on the run in
      # the same way: started from zero, each recipe could use the whole limit.
      for (k in names(tseed)) {
        tseed[[k]] <- as_num1(trace[[k]], 0)
        sub[[k]] <- as.integer(tseed[[k]])
      }
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
        seg_hit <- TRUE
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
      notes <- list(error = conditionMessage(e))
      # A limit that refused the recipe before it read anything is noted as
      # gr_read() notes one that stops it part way, so `correct` can tell a
      # recipe that was not tried from one that got it wrong.
      # An unpriced model under a spending limit is stopped by that limit too.
      if (inherits(e, c("gr_cost_cap", "hr_unpriced_model"))) {
        notes$cost_cap_reached <- gr_options("max_cost_usd")
      }
      if (inherits(e, "gr_call_cap")) notes$call_cap_reached <- gr_options("max_calls")
      if (inherits(e, "hr_budget_refused") && is.null(notes$cost_cap_reached)) {
        notes$limit_refused <- TRUE
      }
      a <- new_answer(.NOT_FOUND, r$read$reader, question, integer(0), trace,
                      partial = TRUE, notes = notes)
      a$recipe <- nm
      a
    })
    # Only this recipe's spend and requests are folded in: the seeds are
    # already there.
    sub$spent_usd <- sub$spent_usd - seed
    sub$replayed_usd <- as_num1(sub$replayed_usd, 0) - rseed
    for (k in names(tseed)) sub[[k]] <- as.integer(as_num1(sub[[k]], 0) - tseed[[k]])
    sub$calls <- sub$calls - seeded_calls
    off <- length(trace$steps)
    own <- off + seq_along(sub$steps)
    trace_absorb(trace, sub)
    if (seg_hit) {
      own <- c(seg_at[[skey]], own)
    } else if (!is.null(skey) && !is.null(seg_cache[[skey]]) && is.null(seg_at[[skey]])) {
      seg_at[[skey]] <- off + seq_len(seg_steps)
    }
    steps_of[[nm]] <- own
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
               recipe_cost(trace$steps[steps_of[[nm]] %||% integer(0)]),
               stringsAsFactors = FALSE)
  }))
  if (!is.null(correct)) {
    summary$correct <- unname(vapply(names(answers), function(nm)
      answer_correct(answers[[nm]], correct, nm), logical(1)))
    per <- summary$usd / as.numeric(summary$correct)
    per[is.nan(per)] <- NA_real_
    summary$usd_per_correct <- per
  }
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

#' What one recipe's requests cost, as the cost columns of gr_compare().
#'
#' Priced by gr_trace_cost() on the recipe's own steps. The estimated share is
#' of the dollars, not of the requests (gr_trace_summary() gives that): an
#' estimated count on a cheap request matters less than one on a long prompt.
#' Requests with no recorded provenance are left out of the share's
#' denominator, since nothing says whether their counts were estimated.
#' @noRd
recipe_cost <- function(steps) {
  steps <- Filter(function(s) is.list(s) && !identical(s$kind, "local") && is.list(s$tokens),
                  steps)
  prov <- vapply(steps, function(s) as_chr1(s$tokens$provenance, NA_character_), character(1))
  usd_of <- function(st) {
    if (!length(st)) return(0)
    sum(gr_trace_cost(structure(list(steps = st), class = "gr_trace"))$usd)
  }
  cost <- if (length(steps)) gr_trace_cost(structure(list(steps = steps), class = "gr_trace"))
          else NULL
  usd <- if (is.null(cost)) 0 else sum(cost$usd)
  known <- usd_of(steps[!is.na(prov)])
  est <- usd_of(steps[prov %in% "estimated"])
  share <- if (!any(!is.na(prov)) || is.na(known) || known <= 0) NA_real_ else est / known
  data.frame(calls = length(steps),
             tokens_in = as.integer(if (is.null(cost)) 0L else sum(cost$paid_in)),
             tokens_out = as.integer(if (is.null(cost)) 0L else sum(cost$paid_out)),
             usd = usd, usd_estimated = share)
}

#' Whether a recipe's answer is right, for gr_compare()'s `correct` column.
#'
#' Strings are matched as written, not as patterns, after folding case and
#' white space, so "45.2 million" matches "45.2  Million" and a "." in the
#' expected text means a full stop.
#' @noRd
answer_correct <- function(a, correct, recipe) {
  if (is.function(correct)) {
    # Called after every recipe has run and been paid for, so a judge that
    # fails costs the caller one cell, not the answers, summary and trace.
    v <- tryCatch(correct(a), error = function(e) e)
    if (inherits(v, "error")) {
      gr_warn(sprintf("`correct` failed for recipe '%s': %s; its `correct` is NA.",
                      recipe, conditionMessage(v)), class = "gr_bad_correct")
      return(NA)
    }
    if (!is.logical(v) || length(v) != 1L) {
      gr_warn(sprintf("`correct` returned %s for recipe '%s'; it must return TRUE, FALSE or NA, so its `correct` is NA.",
                      class(v)[1], recipe), class = "gr_bad_correct")
      return(NA)
    }
    return(v)
  }
  txt <- as_chr1(a$answer, "")
  if (is_not_found(txt)) {
    # A limit that stopped the recipe before it found anything says nothing
    # about whether the recipe gets it right: it was not tried.
    # That includes a request another limit refused (the token limit, the
    # allowed models, the output ceiling), which gr_read() notes as
    # `limit_refused`.
    if (!is.null(a$notes$cost_cap_reached) || !is.null(a$notes$call_cap_reached) ||
        !is.null(a$notes$limit_refused)) return(NA)
    # A recipe that failed is answered not-found (gr_compare()), so this covers it.
    return(FALSE)
  }
  fold <- function(x) tolower(gsub("[[:space:]]+", " ", trimws(x)))
  any(vapply(correct, function(k) grepl(fold(k), fold(txt), fixed = TRUE), logical(1)))
}
