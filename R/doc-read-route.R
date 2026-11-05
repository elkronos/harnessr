# doc-read-route.R -- the top-level orchestrator.
#
# WHY THIS FILE EXISTS
# `answer_question()` had six separate defects packed into 60 lines:
#
#   1. `match.arg(mode, several.ok = TRUE)` on a five-element default meant that
#      calling `answer_question(f, q)` with no mode ran ALL FIVE modes -- 41 API
#      calls where the obvious reading of the signature suggests one.
#   2. One `chunk_method` and one `chunks` object were shared by every mode, so
#      modes contaminated each other (see pipeline.R).
#   3. `answers[[m]] <- NULL` DELETES the element in R, so a mode whose API call
#      failed vanished from the result. With two modes requested and one failing,
#      the caller got a bare unnamed string and the Shiny UI labelled it with
#      both mode names.
#   4. No `tryCatch` around the loop, so one failure discarded every
#      already-paid-for answer.
#   5. `...` was never forwarded to `parse_text()`, so no ingestion option was
#      reachable from the only public entry point -- and passing one anyway
#      (`remove_numbers = FALSE`) was silently swallowed by a downstream `...`.
#   6. `refine_answer(chunks, question, ans, ...)` forwarded `...` into a
#      function with no `...` formal, so any extra argument produced
#      "unused arguments (temperature = 0.2)". It also called `search_text()`,
#      which is not defined anywhere in the repository -- `refine = TRUE` could
#      never work.

#' Answer a question about a document
#'
#' One recipe, one pipeline: ingest, segment, read. The answer and its full
#' trace come from a single run, so the trace always explains the answer you got.
#'
#' @param source File path, web address, or raw text; see [gr_ingest()].
#' @param question The question.
#' @param recipe A `gr_recipe`, a recipe name from `gr_recipes()`, a reader name,
#'   or a named list of `ingest`/`segment`/`read`. The default, `"auto"`, picks
#'   `"fast"` or `"thorough"` from the document's length; see "Choosing the
#'   recipe" below.
#' @param client A `gr_client`; one is built from options when omitted.
#' @param return `"answer"` (a `gr_answer`), `"text"` (the string), or `"json"`
#'   (answer plus trace, serialised).
#' @param trace Optional `gr_trace` to accumulate into.
#' @param ... Convenience overrides applied to the recipe: any `gr_read_spec`,
#'   `gr_segment_spec` or `gr_ingest_spec` field (for example `model`,
#'   `max_tokens`, `top_k`, `clean`). Unknown names raise an error instead of
#'   being silently discarded.
#' @return Depends on `return`. The `gr_answer` carries `$partial`; check it
#'   before trusting `$answer`.
#'
#' @section Choosing the recipe:
#' With `recipe = "auto"` the document is ingested first, and its length
#' decides how it is read. `"fast"` sends the whole document in one request.
#' It is used for a document of at most 50,000 tokens that also fills no more
#' than half of the room one request leaves for the document, which is less on
#' a model with a small context window. Anything longer is read with
#' `"thorough"`: one request per chunk, then the requests that combine their
#' answers. Both send every chunk, so the choice changes the number of requests
#' and the cost, not how much of the document is read.
#'
#' The room is measured for the model that answers: the one passed as `model`
#' in `...`, or else the client's. A model whose limits harnessr has to guess
#' (see [gr_model_info()]) always gets `"thorough"`; register its real limits
#' with [gr_register_model()].
#'
#' The answer's `recipe` names the recipe used, `notes$auto_recipe` records that
#' `"auto"` chose it, and the trace has an `auto_recipe` step with the token
#' count and the limit the choice was made on. A [gr_replay_client()] repeats
#' the recorded choice rather than making it again. Overrides in `...` apply to
#' whichever recipe is chosen. [gr_read_many()], [gr_compare()] and the review
#' functions need one fixed recipe and refuse `"auto"`.
#' @seealso [gr_recipes()] for the built-in pipelines, [gr_compare()] to run
#'   several, [gr_answer] for the returned object, [gr_options()] for the cost
#'   and call caps
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "The answer is 42.")
#' txt <- "Chapter one.\n\nThe answer to the great question is 42, as recorded."
#' answer_document(txt, "What is the answer?", "fast", client = cl, return = "text")
answer_document <- function(source, question, recipe = "auto", client = NULL,
                            return = c("answer", "text", "json"), trace = NULL, ...) {
  return <- match.arg(return)
  # UTF-8 and labelled, before it is pasted next to the document's text; see
  # gr_read().
  if (is.character(question)) question <- to_utf8(question)
  if (!is_nonblank(question)) gr_abort("`question` must be a non-empty string.")
  # "auto" is decided once the document's length is known. Both candidates are
  # built now, so an override that applies to neither fails before any work.
  auto <- is_auto_recipe(recipe)
  if (auto) {
    cand <- lapply(c(fast = "fast", thorough = "thorough"), auto_candidate, list(...))
    # A warning both raise is about the overrides, not the choice: shown now,
    # before the document is read, as it would be for a named recipe.
    both <- auto_shared_warnings(cand)
    for (w in both$shared) warning(w)
    cand <- both$cand
    first <- cand$fast$recipe
  } else {
    rec <- apply_overrides(as_recipe(recipe), list(...))
    first <- rec
  }
  client <- client %||% gr_client(model = first$read$model)
  # Before ingestion: a missing key fails every request, and finding that out
  # after an OCR pass over a long scan wastes the wait.
  stop_if_no_credentials(client)
  trace <- trace %||% gr_trace(meta = list(recipe = if (auto) "auto" else first$name,
                                           question = question,
                                           source = source_label(source)))
  # Where this run's steps start, so they can be labelled with the document and
  # the recipe once "auto" has chosen: a trace passed in may hold other runs.
  from <- length(trace$steps) + 1L

  # The two candidates ingest alike, so the document is read once either way.
  doc <- gr_ingest(source, first$ingest, trace = trace)
  if (auto) {
    # Measured for the model that answers: the one named by `model` or the
    # recipe, or else the client's, which is what gr_read() reads with when the
    # spec names none.
    models <- first$read$model %||% as_chr1(client[["model", exact = TRUE]], "")
    pick <- pick_auto_recipe(gr_count_tokens(doc$text), first, models, client, trace,
                             key = gr_hash(list("auto", doc$text, question)))
    for (w in cand[[pick]]$warnings) warning(w)
    rec <- cand[[pick]]$recipe
  }
  chunks <- gr_segment(doc, segment_effort(rec$segment, rec$read), client = client, trace = trace)
  ans <- finish_answer(gr_read(chunks, question, client, rec$read, trace = trace),
                       doc, chunks, rec$name)
  if (auto) ans$notes$auto_recipe <- rec$name
  trace_stamp(trace, from, source = source_label(source), recipe = rec$name)
  # This run's steps, its ingestion and segmentation as well as its read, so
  # the answer's record (answer_trace()) covers the whole run and no other
  # on a trace passed in. Before as_json() below, which reads it.
  ans$trace_steps <- c(first = from, last = length(trace$steps))

  switch(return,
    answer = ans,
    text = ans$answer,
    json = as_json(ans))
}

#' The most tokens a document can have for `"auto"` to read it in one request:
#' about 70 pages of prose, and under a twentieth of the default model's window.
#' @noRd
.gr_auto_max_tokens <- 50000L

#' @noRd
is_auto_recipe <- function(x) {
  is.character(x) && length(x) == 1L && identical(unname(x), "auto")
}

#' One of the two recipes `"auto"` chooses between, with the overrides applied.
#'
#' "fast" and "thorough" differ in how the document is cut and read, never in
#' how it is ingested. The warnings the overrides raise are held back and
#' replayed only for the recipe that is used: `max_tokens = 100` puts
#' "thorough"'s 120-token overlap out of range, and a run that reads with
#' "fast" should not warn about it.
#' @noRd
auto_candidate <- function(name, overrides) {
  held <- list()
  rec <- withCallingHandlers(apply_overrides(gr_recipes(name), overrides),
    warning = function(w) {
      held[[length(held) + 1L]] <<- w
      invokeRestart("muffleWarning")
    })
  list(recipe = rec, warnings = held)
}

#' The warnings both candidates raised, and the candidates without them.
#' @noRd
auto_shared_warnings <- function(cand) {
  key <- function(ws) vapply(ws, function(w) paste(class(w)[1], conditionMessage(w)), character(1))
  kf <- key(cand$fast$warnings)
  kt <- key(cand$thorough$warnings)
  shared <- cand$fast$warnings[kf %in% kt]
  cand$fast$warnings <- cand$fast$warnings[!kf %in% kt]
  cand$thorough$warnings <- cand$thorough$warnings[!kt %in% kf]
  list(shared = shared, cand = cand)
}

#' Which of the two recipes reads this document: "fast" or "thorough".
#'
#' "fast" sends the whole document in one request, so it is chosen only when
#' the document is at most `.gr_auto_max_tokens` and fills at most half of the
#' room a request leaves for the document, on every model in `models`: the rest
#' absorbs the error in counting tokens locally. A model with a small window
#' lowers the threshold. A model whose limits are a guess (see gr_model_info())
#' is no basis for sending everything at once, and neither is a document whose
#' size cannot be counted; both are read the way that works at any size.
#' @noRd
pick_auto_recipe <- function(tokens, fast, models = fast$read$model %||% gr_options("model"),
                             client = NULL, trace = NULL, key = NULL) {
  # A replay makes the choice the recorded run made for this document and
  # question; see gr_replay_client().
  recorded <- if (is.function(client[["auto_choice", exact = TRUE]])) client$auto_choice(key)
  if (length(recorded) == 1L && recorded %in% c("fast", "thorough")) {
    trace_note(trace, "auto_recipe", list(chose = recorded, key = key, replayed = TRUE))
    return(recorded)
  }
  tokens <- as_num1(tokens, NA_real_)
  models <- unique(models[!is.na(models) & nzchar(models)])
  room <- vapply(models, function(m) {
    # The reader warns about an unrecognised model itself; once is enough.
    b <- tryCatch(suppressWarnings(gr_budget(m, reserve_output = fast$read$max_answer_tokens),
                                   classes = "gr_unknown_model"),
                  error = function(e) NULL)
    if (is.null(b) || !isTRUE(b$certain)) NA_real_ else as.numeric(b$input)
  }, numeric(1))
  limit <- if (!length(room) || anyNA(room)) NA_real_
           else floor(min(.gr_auto_max_tokens, min(room) / 2))
  pick <- if (!is.na(tokens) && !is.na(limit) && tokens <= limit) "fast" else "thorough"
  trace_note(trace, "auto_recipe", list(chose = pick, tokens = tokens, limit = limit,
                                        models = models, key = key))
  pick
}

#' What every answer drawn from a document carries beyond what the reader set.
#'
#' One place for it, so the three routes to an answer (one document, a
#' comparison, a folder) cannot drift apart. A quote is a sentence, and a
#' sentence is on one page. The reader only sees chunks, which may span several;
#' the document is in scope here, so this is where a citation stops being
#' "somewhere in chunk 4" and becomes "page 7".
#' @noRd
finish_answer <- function(ans, doc, chunks, recipe) {
  ans$evidence <- resolve_evidence_pages(ans$evidence, doc$blocks)
  ans$recipe <- recipe
  ans$document <- list(source = doc$source, stats = doc$stats)
  ans$segmentation <- as.list(gr_chunk_stats(chunks))
  ans
}

#' What went wrong in a run, in a line, for gr_compare()'s `error` column.
#'
#' The reader's own `notes$error` when it left one. A reader that counts its
#' failures in `notes$failed_calls` instead (map_reduce, skim or refine on a
#' 401) left the column NA beside `not_found = TRUE`, as if nothing had
#' failed; the first failure on the answer's own steps that nothing recovered
#' from says what did, as partial_reasons() finds it. NA when there is none.
#' @noRd
answer_error <- function(a) {
  err <- as_chr1(as.list(a$notes %||% list())[["error", exact = TRUE]], NA_character_)
  if (is_nonblank(err)) return(err)
  tr <- answer_trace(a)
  open <- if (inherits(tr, "gr_trace")) Filter(Negate(is_recovered_error), tr$errors) else list()
  if (length(open)) as_chr1(open[[1]]$error, NA_character_) else NA_character_
}

#' Apply flat `...` overrides onto the right axis of a recipe.
#'
#' Unknown names are an ERROR. In the old code they were swallowed by a
#' downstream `...` -- `answer_question(f, q, remove_numbers = FALSE)` ran
#' cleanly and stripped every digit anyway.
#' @noRd
apply_overrides <- function(rec, overrides) {
  if (!length(overrides)) return(rec)
  if (is.null(names(overrides)) || any(!nzchar(names(overrides)))) {
    gr_abort("Overrides passed through `...` must be named.")
  }
  ing_f <- setdiff(names(formals(gr_ingest_spec)), "...")
  seg_f <- setdiff(names(formals(gr_segment_spec)), "...")
  rd_f  <- setdiff(names(formals(gr_read_spec)), "...")
  # `method` is ambiguous; `parallel` legitimately applies to both.
  seg_only <- setdiff(seg_f, c(ing_f, rd_f))
  rd_only  <- setdiff(rd_f, c(ing_f, seg_f))
  ing_only <- setdiff(ing_f, c(seg_f, rd_f))

  ing <- unclass(rec$ingest); seg <- unclass(rec$segment); rd <- unclass(rec$read)
  # `x[nm] <- list(v)`, not `x[[nm]] <- v`. `[[<-` with a NULL right-hand side
  # DELETES the element, and gr_recipe() then rebuilds the spec with
  # do.call(gr_segment_spec, seg), which supplies the constructor's formal
  # default -- not the recipe's value and not what the constructor would have
  # made of NULL. `answer_document(f, q, "fast", max_tokens = NULL)` silently
  # segmented at 1200 tokens instead of the recipe's 4000, and the trace's
  # `settings` lost the entry too, so the run record no longer said which cap
  # was used. Fourteen fields were affected.
  set1 <- function(x, nm, v) { x[nm] <- list(v); x }
  # NULL is a value only where the constructor itself defaults to NULL -- model,
  # temperature, skim_model, parallel and the like, where it means "use the
  # default model / the session option". Anywhere else NULL is not a setting,
  # and letting it through meant the constructor decided what it meant: a
  # silent FALSE for prefix_section, a warning and the formal default for
  # max_tokens, and "Unknown segmenter '<missing>'" for method -- raised after
  # the document had already been ingested. Refused here, before any work.
  null_ok <- function(ctor, nm) {
    f <- formals(ctor)
    nm %in% names(f) && is.null(f[[nm]])
  }
  for (nm in names(overrides)) {
    v <- overrides[[nm]]
    if (is.null(v)) {
      ctor <- if (nm %in% seg_only || nm == "method") gr_segment_spec else
        if (nm %in% rd_only) gr_read_spec else if (nm %in% ing_only) gr_ingest_spec else NULL
      if (!is.null(ctor) && nm != "parallel" && !null_ok(ctor, nm)) {
        gr_abort(sprintf(paste0("`%s = NULL` is not a setting. Leave `%s` out to keep the ",
                                "recipe's value (%s)."),
                         nm, nm, paste(format(unclass(
                           if (identical(ctor, gr_segment_spec)) rec$segment else
                             if (identical(ctor, gr_read_spec)) rec$read else rec$ingest)[[nm]]),
                           collapse = ", ")),
                 class = "gr_bad_override")
      }
    }
    if (nm %in% seg_only)       seg <- set1(seg, nm, v)
    else if (nm %in% rd_only)   rd  <- set1(rd, nm, v)
    else if (nm %in% ing_only)  ing <- set1(ing, nm, v)
    else if (nm == "parallel") { seg <- set1(seg, "parallel", v)
                                 rd <- set1(rd, "parallel", v)
                                 ing <- set1(ing, "parallel", v) }
    else if (nm == "method")    seg <- set1(seg, "method", v)
    else {
      gr_abort(sprintf(paste0("Unknown override '%s'. Ingest fields: %s. Segment fields: %s. ",
                              "Read fields: %s."),
                       nm, paste(ing_f, collapse = ", "), paste(seg_f, collapse = ", "),
                       paste(rd_f, collapse = ", ")), class = "gr_unknown_override")
    }
  }
  gr_recipe(rec$name, ingest = ing, segment = seg, read = rd)
}

#' A short, safe label for whatever the user passed as `source`.
#'
#' `basename()` is bounded by PATH_MAX -- 1024 bytes on macOS, and R warns or
#' errors past it. A document passed as raw text is a length-1 character vector,
#' so the obvious `is.character(x) && length(x) == 1L` guard handed the WHOLE
#' DOCUMENT to `basename()`. On macOS that warned on every run over ~1KB (which
#' is most documents) and put a mangled fragment of the document into the trace
#' where the filename belongs; on Linux it silently did the same thing without
#' warning. Test for a path the way `gr_ingest()` does, and label anything else
#' inline.
#' @noRd
source_label <- function(source, inline = "<inline text>") {
  if (!is.character(source) || length(source) != 1L || is.na(source)) return(inline)
  if (is_url(source)) return(trimws(source))
  if (grepl("\n", source, fixed = TRUE)) return(inline)
  if (nchar(source, type = "bytes") >= 1000L) return(inline)
  if (!file.exists(source)) return(inline)
  basename(source)
}
