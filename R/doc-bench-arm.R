# doc-bench-arm.R: reading recipes as arms of a benchmark.
#
# An arm built here answers one question about one document per run, the way
# answer_document() does, so the benchmark compares recipes on the code a
# user runs. Every request goes on the run's own trace, which is how the
# benchmark counts and limits the run, and carries the run's draw index, so
# repeated runs under a cache or a recording are separate draws.

#' A reading recipe as an arm of a benchmark
#'
#' `gr_arm()` wraps one recipe as an [hr_arm()], so recipes can be compared
#' with [hr_benchmark()] on a reference of questions about documents, such as
#' one from [gr_qa_reference()]. `gr_arms()` builds one arm per recipe.
#'
#' Each run reads the item's `document` and answers its `question`: with
#' [answer_document()] when the document is a file path, a web address or
#' text, or with [gr_read()] when it is already cut into chunks by
#' [gr_segment()]. It returns the [gr_answer], which the benchmark's scorer
#' then judges; [gr_scorer_answer()] is the scorer made for it.
#'
#' The run uses the benchmark's client and records every request into the
#' trace the benchmark made for that run (`ctx$trace`), so the run's tokens,
#' cost and refusals are counted and held to the benchmark's limits, and the
#' answer's `trace` is that run's trace. That trace also gives every request
#' of the run the run's draw index (see `draw_index` in [gr_call()]), segmenter
#' and reader requests included, so the runs of one arm on one item are
#' separate draws under a [gr_cache()] or a [gr_replay_client()] rather than
#' one stored reply repeated, which [hr_benchmark()] would refuse.
#'
#' A reader checks before it starts whether the run's call and spending
#' limits leave room for it. When they do not, the run returns a
#' `"NOT_IN_DOCUMENT"` answer marked `partial`, with `call_cap_reached` or
#' `cost_cap_reached` in its notes as [gr_compare()] records them, and
#' [gr_scorer_answer()] scores it as a `"budget_stop"`.
#'
#' A recipe given as `"auto"` chooses `"fast"` or `"thorough"` per document,
#' as [answer_document()] does; it needs a document that is not yet chunked.
#'
#' The arm's `params` are the recipe's name and the settings, and its version
#' is the version of harnessr, since readers and prompts change between
#' versions. The arm also records them as its settings, which [hr_benchmark()]
#' reports in `param.<name>` columns and [hr_sweep()] overrides by name. Two
#' recipe arms whose settings resolve to the same recipe (a setting given at
#' the recipe's own value, say) have the same configuration, and
#' [hr_benchmark()] warns when it is given both.
#'
#' @param recipe A recipe: a name from [gr_recipes()], `"auto"`, a reader
#'   name, a [gr_recipe()] or a named list of `ingest`, `segment` and `read`.
#' @param settings A named list of overrides applied to the recipe, as the
#'   `...` of [answer_document()] takes them (for example `model`, `top_k`,
#'   `max_tokens`). An unknown name is an error when the arm is built.
#' @param name The arm's name. By default the recipe's name.
#' @param recipes A character vector of recipe names, or a list of recipes.
#'   The names of a named list or vector are used as the arms' names.
#' @return `gr_arm()` returns an [hr_arm()]. `gr_arms()` returns a list of
#'   them, named by arm.
#' @seealso [gr_qa_reference()], [gr_scorer_answer()], [hr_benchmark()],
#'   [hr_report()], [gr_compare()] for a single descriptive comparison
#' @family harness
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ref <- gr_qa_reference(
#'   questions = c(revenue = "What was revenue in 2024?",
#'                 ceo = "Who is the chief executive?"),
#'   documents = gr_example(),
#'   answers = list("45.2 million", NA),
#'   unanswerable = "ceo", split = "test")
#' arms <- gr_arms(c("fast", "thorough"))
#' bench <- hr_benchmark(arms, ref, runs = 5, client = cl, scorer = gr_scorer_answer())
#' bench
gr_arm <- function(recipe, settings = list(), name = NULL) {
  if (!is.list(settings) || is.data.frame(settings) ||
      (length(settings) && (is.null(names(settings)) || anyNA(names(settings)) ||
                            any(!nzchar(names(settings)))))) {
    gr_abort("`settings` must be a named list of recipe overrides.", class = "hr_bad_arm")
  }
  if (is_auto_recipe(recipe)) {
    # Built now so that an override neither candidate takes fails here, not
    # on every run of the benchmark.
    invisible(lapply(c("fast", "thorough"), auto_candidate, settings))
    rec <- "auto"
    label <- "auto"
    overrides <- settings
  } else {
    rec <- apply_overrides(as_recipe(recipe), settings)
    label <- rec$name
    overrides <- list()
  }
  if (!is.null(name) && !is_bench_string(name)) {
    gr_abort("`name` must be one non-blank string, or NULL.", class = "hr_bad_arm")
  }
  version <- tryCatch(as.character(utils::packageVersion("harnessr")),
                      error = function(e) "0.0.0")
  arm <- hr_arm(name %||% label, doc_arm_run(rec, overrides),
                params = c(list(recipe = label), settings), version = version)
  # What hr_sweep() and hr_benchmark() read: the settings, a hash of the
  # resolved recipe (two arms whose settings resolve alike run alike), and how
  # to build the arm again with some settings changed.
  arm_annotate(arm, settings = c(list(recipe = label), settings),
               config = hr_hash(list(recipe = fingerprint_value(rec),
                                     overrides = fingerprint_value(overrides),
                                     version = version)),
               rebuild = doc_arm_rebuild(recipe, settings),
               known = doc_arm_settings())
}

#' The names a recipe arm's settings may take: `recipe`, and every override
#' apply_overrides() accepts.
#' @noRd
doc_arm_settings <- function() {
  unique(c("recipe", setdiff(c(names(formals(gr_ingest_spec)), names(formals(gr_segment_spec)),
                               names(formals(gr_read_spec))), "...")))
}

#' A function that builds a recipe arm again with some settings changed, for
#' hr_sweep(). A `recipe` among them replaces the recipe.
#' @noRd
doc_arm_rebuild <- function(recipe, settings) {
  force(recipe)
  force(settings)
  function(changes, name) {
    s <- settings
    for (k in setdiff(names(changes), "recipe")) s[k] <- list(changes[[k]])
    rec <- if ("recipe" %in% names(changes)) changes[["recipe"]] else recipe
    gr_arm(rec, s, name = name)
  }
}

#' @rdname gr_arm
#' @export
gr_arms <- function(recipes, settings = list()) {
  # A single gr_recipe is itself a list, of its four fields.
  if (inherits(recipes, "gr_recipe")) recipes <- list(recipes)
  # So is one recipe given as a named list of its parts.
  if (is.list(recipes) && length(recipes) && !is.null(names(recipes)) &&
      all(names(recipes) %in% c("ingest", "segment", "read", "name"))) {
    recipes <- list(recipes)
  }
  if (!length(recipes) || !(is.character(recipes) || is.list(recipes))) {
    gr_abort("`recipes` must be recipe names or a list of recipes, at least one.",
             class = "hr_bad_arm")
  }
  nms <- names(recipes)
  arms <- lapply(seq_along(recipes), function(i) {
    nm <- if (!is.null(nms) && !is.na(nms[i]) && nzchar(nms[i])) nms[i]
    gr_arm(recipes[[i]], settings, name = nm)
  })
  names(arms) <- vapply(arms, function(a) a$name, character(1))
  dup <- unique(names(arms)[duplicated(names(arms))])
  if (length(dup)) {
    gr_abort(sprintf("Arm names must be unique; repeated: %s. Name the recipes to tell them apart.",
                     paste(dup, collapse = ", ")), class = "hr_bad_arm")
  }
  arms
}

#' The run of a recipe arm. Made in its own function so the arm's hash rests
#' on the recipe and overrides alone (see arm_parts()).
#' @noRd
doc_arm_run <- function(recipe, overrides) {
  function(item, ctx) {
    item <- qa_item(item)
    # Every request this run makes, however deep in the reader, is the run's
    # draw: hr_benchmark() hands the arm a trace that carries it (bench_ctx()).
    tryCatch({
      if (inherits(item$document, "gr_chunks")) {
        if (identical(recipe, "auto")) {
          gr_abort(paste0("'auto' chooses a recipe from the document's length, so it needs the ",
                          "document itself, not chunks."), class = "gr_bad_recipe")
        }
        client <- ctx$client %||% gr_client(model = recipe$read$model)
        gr_read(item$document, item$question, client, recipe$read, trace = ctx$trace)
      } else {
        do.call(answer_document, c(list(item$document, item$question, recipe,
                                         client = ctx$client, return = "answer",
                                         trace = ctx$trace), overrides))
      }
    }, gr_call_cap = function(e) {
      stopped_answer(e, recipe, item$question, ctx, list(call_cap_reached = ctx$governor$max_calls))
    }, gr_cost_cap = function(e) {
      stopped_answer(e, recipe, item$question, ctx,
                     list(cost_cap_reached = ctx$governor$max_cost_usd))
    })
  }
}

#' The answer of a run whose reader refused to start because the run's call
#' or spending limit left too little for it. A reader's pre-flight check
#' raises an error rather than a governor refusal, which the benchmark would
#' record as an error; noted as gr_compare() notes it, the scorer reads it as
#' the budget stop it is. A governor refusal (hr_budget_refused) is left to
#' the benchmark, which records it as a budget stop itself.
#' @noRd
stopped_answer <- function(e, recipe, question, ctx, notes) {
  if (inherits(e, "hr_budget_refused")) stop(e)
  # The pre-flight check stops the reader before any request, so the run's
  # trace holds no refusal saying which limit. Leave a note naming it for
  # hr_benchmark()'s warning. The trace's stop_reason is left alone: it is
  # folded into the benchmark's trace, where a replay reads it.
  trace_note(ctx$trace, "budget.preflight",
             list(limit = as_chr1(e$limit, if (inherits(e, "gr_cost_cap")) "cost" else "calls")))
  reader <- if (is.list(recipe)) as_chr1(recipe$read$reader, NA_character_) else "auto"
  notes <- notes[!vapply(notes, is.null, logical(1))]
  if (!length(notes)) notes <- list(limit_refused = TRUE)
  notes$error <- conditionMessage(e)
  new_answer(.NOT_FOUND, reader, question, integer(0), ctx$trace, partial = TRUE, notes = notes)
}

#' An item of a question-answering reference: a list with a question and a
#' document.
#' @noRd
qa_item <- function(item) {
  if (!is.list(item) || !is_nonblank(item[["question", exact = TRUE]]) ||
      is.null(item[["document", exact = TRUE]])) {
    gr_abort(paste0("A recipe arm's item must be a list with `question` and `document`, as ",
                    "gr_qa_reference() builds it."), class = "hr_bad_reference")
  }
  item
}
