# doc-read-answer.R -- AXIS 3 machinery: the answer object, prompt building,
# evidence.
#
# WHY THIS FILE EXISTS
# In the old repository the five "modes" were not five methodologies. Traced
# through `main.R`:
#
#   * "Chunked" and "Semantic" called `gpt_read_chunked(chunks, question,
#     use_parallel = use_parallel, ...)` -- the same function with the same
#     arguments on the same already-sorted `chunks` object. Running both issued
#     14 API calls where 7 would do, and `identical(res$Chunked, res$Semantic)`
#     was TRUE.
#   * "MultiPass" re-executed Retrieval and Chunked verbatim, so selecting
#     Retrieval + Chunked + MultiPass ran each of them twice.
#   * "Hierarchical" was map-then-single-reduce, i.e. `map_reduce` with a
#     summarise prompt instead of an answer prompt -- one level, never
#     recursive, and it blew the context window the moment N x 512 summary
#     tokens exceeded the model's limit.
#   * `chunk_method` was decided once for the whole run, so ticking "Semantic"
#     silently changed the chunking -- and therefore the answer -- of every
#     other mode in the same run.
#
# Distinctness is now a property the package can *check*. Every reader declares
# a `signature`: the shape of its traversal (how chunks are selected, how many
# calls it makes, whether state flows forward). `gr_compare()` refuses to bill
# you twice for two recipes that resolve to the same ingestion, the same
# segmentation AND the same read spec -- the signature alone is not the test,
# because two recipes can share a signature and still differ in `top_k`,
# `min_score` or a token cap, all of which change what the model sees.

#' Build a `gr_answer`, the object every reader must return
#'
#' Exported because it is part of the extension API: [gr_read()] rejects
#' anything that does not inherit `"gr_answer"`, so a custom reader registered
#' with [gr_register_reader()] cannot be written without this. Using it also
#' means your reader reports `partial`, `evidence` and `notes` the same way the
#' built-ins do, so [gr_compare()] can put it in the same table.
#'
#' @param text The answer string. Use `"NOT_IN_DOCUMENT"` when the chunks did
#'   not contain the answer; [gr_compare()] counts that separately from a
#'   failure.
#' @param reader Your reader's name, as registered.
#' @param question The question, carried through for the record.
#' @param chunks_used Integer `chunk_id`s that CONTRIBUTED to the answer, not
#'   every chunk you sent.
#' @param trace The `gr_trace` passed to your reader. Pass it through; do not
#'   create a new one, or your calls will not appear in the run's totals.
#' @param evidence Optional data frame of supporting spans; build it with the
#'   columns `chunk_id`, `text`, `page`, `section`, `score`.
#' @param partial `TRUE` if anything degraded: a failed call, a dropped chunk,
#'   a truncated prompt. Callers are told to check this before trusting
#'   `$answer`, so setting it honestly matters more than it looks.
#' @param chunks_sent Chunk ids the reader actually put in front of the model,
#'   when that is more than `chunks_used`. Used only to tell a fabricated
#'   citation from a faithful one: a per-chunk reader drops the chunks that
#'   answered "not in this excerpt", and citing one of those is not an invention.
#'   Defaults to `chunks_used`.
#' @param notes Named list of whatever your reader wants to report.
#' @param premise Whether, and how, the question's premise was checked; see
#'   `premise` in [gr_read_spec()]. `NULL` (the default) when your reader did
#'   not check it, which leaves the field out of the answer. `NA` or `FALSE`
#'   when it checked and the model reported nothing contradicting it.
#'   Otherwise the sentence in which the model said what the document states
#'   instead, which should then be `text` as well, so that `$answer` says it
#'   and [is_not_found()] is `FALSE`. Any other value, `TRUE` among them, is
#'   an error.
#' @return A [gr_answer].
#' @seealso [gr_register_reader()], [gr_answer], [gr_read()], [new_chunks()]
#' @family reading functions
#' @export
#' @examples
#' # The minimum a custom reader has to return.
#' tr <- gr_trace()
#' a <- new_answer("Revenue was 45.2 million.", "my_reader", "What was revenue?",
#'                 chunks_used = 1L, trace = tr, notes = list(strategy = "first chunk"))
#' a$partial
#' a$notes$strategy
new_answer <- function(text, reader, question, chunks_used, trace, evidence = NULL,
                       partial = FALSE, notes = list(), chunks_sent = NULL, premise = NULL) {
  text <- as_chr1(text)

  # A citation pointing at a chunk that was never sent is a fabrication, and the
  # most convincing kind there is: it looks like the thing that would let you
  # check. Parsing for it costs nothing and runs on every answer, including the
  # ones that never asked for citations, where it finds nothing.
  #
  # Compared against what was SENT, not against `chunks_used`. For the per-chunk
  # readers `chunks_used` is only the chunks that CONTRIBUTED, so a model that
  # faithfully cited a chunk which had answered "not in this excerpt" was
  # reported as having fabricated the citation -- a false positive in a
  # hallucination check, which is the one place a false positive is least
  # affordable.
  cited <- cited_chunks(text)
  unknown <- setdiff(cited, as.integer(chunks_sent %||% chunks_used))
  if (length(unknown)) {
    notes$cited_unknown <- unknown
    partial <- TRUE
  }
  # A citation the grammar cannot read is one nobody checked, which is not the
  # same as one that checked out.
  unreadable <- unparsed_citations(text, "chunk")
  if (length(unreadable)) {
    notes$cited_unparsed <- unreadable
    partial <- TRUE
  }

  # Evidence a reader could not verify against its own source. Only readers
  # whose evidence is model-written carry the columns to check, so this is a
  # no-op for the rest.
  if (is.data.frame(evidence) && !is.null(evidence$verified)) {
    bad <- sum(!is.na(evidence$verified) & !evidence$verified)
    if (bad > 0L) {
      notes$unverified_evidence <- bad
      partial <- TRUE
    }
  }

  out <- structure(list(
    answer = text,
    reader = as_chr1(reader),
    question = as_chr1(question),
    evidence = evidence,
    chunks_used = chunks_used,
    partial = isTRUE(partial),
    notes = notes,
    trace = trace,
    warnings = character(0),
    # Which of the trace's steps are this answer's (answer_trace()). A trace
    # is shared by reference, so a caller who passes one trace to several runs
    # has every run in it, those made after this answer included. Steps up to
    # here are the most this run can have made; where it started is known only
    # to the caller that began it (gr_read(), answer_document()), which moves
    # `first` up.
    trace_steps = if (inherits(trace, "gr_trace"))
      c(first = 1L, last = length(trace$steps)) else NULL
  ), class = "gr_answer")
  # Only when the reader checked the premise (read-premise.R): an answer from a
  # run that did not ask has no such field, as it never had, so it prints,
  # serialises and compares exactly as it did. NA is "checked, nothing
  # flagged", which a blank sentence and FALSE are too.
  if (!is.null(premise)) {
    if (is.logical(premise) && length(premise) == 1L && !isTRUE(premise)) premise <- NA_character_
    # Anything else that is not a sentence is refused, not coerced: TRUE, or
    # FALSE in a vector, became the correction "TRUE" or "FALSE", and the
    # answer said the model had contradicted the question when nothing had.
    if (!is.character(premise)) {
      gr_abort(paste0("`premise` must be NULL, NA, FALSE, or the sentence in which the model ",
                      "said what the document states instead."), class = "gr_bad_setting")
    }
    p <- as_chr1(premise, NA_character_)
    out$premise <- if (is_nonblank(p)) p else NA_character_
  }
  out
}

#' The part of an answer's trace that is this answer's run.
#'
#' `x$trace` is the whole of a trace the caller may have shared with other
#' runs. Where the answer records its steps (`trace_steps`, from new_answer()
#' and the caller that began the run), this is a trace holding only those
#' steps, with the counts, errors and cost worked out from them
#' (trace_slice()); otherwise, or where they are the whole trace, it is
#' `x$trace` itself. What as_json(), print() and the audit report say about
#' one answer comes from this, so one run's record does not carry another
#' document's prompts, calls or cost.
#' @noRd
answer_trace <- function(x) {
  tr <- x[["trace", exact = TRUE]]
  if (!inherits(tr, "gr_trace")) return(tr)
  r <- suppressWarnings(as.integer(x[["trace_steps", exact = TRUE]]))
  n <- length(tr$steps)
  if (length(r) != 2L || anyNA(r)) return(tr)
  first <- max(1L, r[1L])
  last <- min(n, r[2L])
  if (first <= 1L && last >= n) return(tr)
  trace_slice(tr, if (last >= first) seq.int(first, last) else integer(0))
}

#' A copy of a trace holding only steps `idx`, for reporting on one run.
#'
#' The counts are worked out from the steps as trace_record() and
#' trace_note() make them: a request is any step not marked `"local"`, an
#' embeddings request's tokens are `embed_tokens`, and a step answered from a
#' cache costs nothing. An error is kept when it names one of the steps.
#' Steps keep their numbers, which say where each is in the whole trace, as
#' the errors' `step` does.
#' @noRd
trace_slice <- function(trace, idx) {
  out <- new.env(parent = emptyenv())
  for (nm in ls(trace, all.names = TRUE)) assign(nm, get(nm, envir = trace), envir = out)
  steps <- trace$steps[idx]
  req <- Filter(function(s) is.list(s) && !identical(s$kind, "local"), steps)
  emb <- vapply(req, function(s) identical(s$kind, "embedding"), logical(1))
  cached <- vapply(req, function(s) isTRUE(s$cached), logical(1))
  tin <- vapply(req, function(s) as_int1(s$tokens$input, 0L), integer(1))
  tout <- vapply(req, function(s) as_int1(s$tokens$output, 0L), integer(1))
  usd <- vapply(seq_along(req), function(i) {
    if (cached[i]) return(0)
    v <- tryCatch(suppressWarnings(as.numeric(gr_estimate_cost(
      as_chr1(req[[i]]$model, "unknown"), tin[i], tout[i]))), error = function(e) NA_real_)
    if (length(v) == 1L && !is.na(v)) v else 0
  }, numeric(1))
  num <- vapply(steps, function(s) as_int1(s$step, NA_integer_), integer(1))
  out$steps <- steps
  out$calls <- length(req)
  out$cached <- sum(cached)
  out$tokens_in <- sum(tin[!emb])
  out$tokens_out <- sum(tout[!emb])
  out$embed_tokens <- sum(tin[emb])
  out$spent_usd <- sum(usd)
  out$errors <- Filter(function(e) is.list(e) && as_int1(e$step, NA_integer_) %in% num,
                       trace$errors)
  class(out) <- class(trace)
  out
}

#' @export
print.gr_answer <- function(x, ...) {
  cat(sprintf("<gr_answer> reader=%s%s\n", x$reader, if (x$partial) " (PARTIAL)" else ""))
  cat(sprintf("  Q: %s\n", substr(x$question, 1, 160)))
  tr <- answer_trace(x)
  if (inherits(tr, "gr_trace")) {
    s <- gr_trace_summary(tr)
    recovered <- sum(vapply(tr$errors, is_recovered_error, logical(1)))
    # Model calls and embeddings requests apart, as print.gr_trace() counts
    # them: `calls` has both, so a needle run that made one model call printed
    # "7 model call(s)". The tokens are the model calls' alone either way.
    cat(sprintf("  %d model call(s)%s%s, %d in / %d out tokens, %d error(s)%s, %s\n",
                s$calls - s$embed_calls,
                if (s$cached > 0L) sprintf(" (%d cached)", s$cached) else "",
                if (s$embed_calls > 0L)
                  sprintf(", %d embeddings request(s) (%d tokens)", s$embed_calls, s$embed_tokens)
                else "",
                s$tokens_in, s$tokens_out, s$errors,
                if (recovered > 0L) sprintf(" (%d recovered by a fallback)", recovered) else "",
                format_trace_cost(tr)))
  }
  cat("  ---\n")
  # The model's verdict, and said to be the model's: nothing checked it against
  # the document, and "the premise is false" would claim that something had.
  if (premise_flagged(x)) {
    cat("  The model reports that the document contradicts an assumption in the question. ",
        "What it says the document states instead:\n", sep = "")
  }
  if (is_not_found(x$answer)) cat(not_found_wording(x), "\n", sep = "") else cat(x$answer, "\n")
  cat("  ---\n")
  if (!is.null(x$evidence) && nrow(x$evidence)) {
    cat(sprintf("  Evidence: %s\n", evidence_locations(x$evidence)))
  }
  if (x$partial) {
    why <- partial_reasons(x)
    cat(sprintf("  Partial because: %s\n",
                if (length(why)) paste(why, collapse = "; ") else "see $notes"))
  }
  w <- x[["warnings", exact = TRUE]] %||% character(0)
  if (length(w)) {
    cat(sprintf("  %d warning(s), in $warnings. First: %s\n", length(w),
                substr(w[[1]], 1, 140)))
  }
  invisible(x)
}

#' What "not found" means for this answer, in a sentence.
#'
#' The sentinel is a value for code to test, not a sentence for a person. And
#' "not found" says less than it appears to from a run that did not read the
#' whole document, whether because something failed (partial) or by design (a
#' top-k reader reads a few chunks), so only a complete read of every chunk
#' earns the stronger wording.
#' @noRd
not_found_wording <- function(x) {
  whole <- !isTRUE(x$partial) && startsWith(as_chr1(x$signature, ""), "all|")
  if (whole) "Not found in the document."
  else "Not found in the part of the document that was read."
}

#' Where the evidence came from, in a line: chunk, then page and section.
#' @noRd
evidence_locations <- function(ev, max_rows = 6L) {
  ids <- unique(ev$chunk_id)
  one <- function(id) {
    row <- ev[ev$chunk_id == id, , drop = FALSE][1, , drop = FALSE]
    where <- c(if (!is.null(row$page) && !is.na(row$page)) sprintf("p. %s", row$page),
               if (!is.null(row$section) && !is.na(row$section) &&
                   nzchar(as.character(row$section)))
                 sprintf("\"%s\"", substr(as.character(row$section), 1, 40)))
    if (length(where)) sprintf("chunk %s (%s)", id, paste(where, collapse = ", "))
    else sprintf("chunk %s", id)
  }
  shown <- vapply(utils::head(ids, max_rows), one, character(1))
  more <- length(ids) - length(shown)
  paste0(paste(shown, collapse = ", "), if (more > 0L) sprintf(", and %d more", more) else "")
}

#' Why an answer's evidence did not verify, in words, for partial_reasons().
#'
#' One count covers two different things. A quotation that is not in the
#' document is one; an extracted value whose quotation IS there, word for word,
#' but does not state the value is the other, and calling that "not found" sent
#' a reader looking for a fabrication that was not there. The evidence table
#' tells them apart (cited_verbatim(): a whole match on a row cited for a field).
#' @noRd
unverified_reasons <- function(x, n) {
  if (!n) return(NULL)
  ev <- x$evidence
  if (!is.data.frame(ev) || !nrow(ev) || is.null(ev$verified)) {
    return(sprintf("%s quotation(s) not found in the document", format(n, scientific = FALSE)))
  }
  stated <- min(n, sum(!is.na(ev$verified) & !ev$verified & cited_verbatim(ev)))
  c(if (n - stated > 0) sprintf("%s quotation(s) not found in the document",
                                format(n - stated, scientific = FALSE)),
    if (stated > 0) sprintf("%s quotation(s) found but not stating the value cited",
                            format(stated, scientific = FALSE)))
}

#' Why an answer is partial, in words, from the notes its reader left.
#'
#' Read with `[[exact = TRUE]]`: `$` would partial-match `degraded` to
#' `degraded_to_bm25` and report a fallback that never happened.
#' @noRd
partial_reasons <- function(x) {
  # as.list(): new_answer() accepts a named vector for notes, and `[[` on one
  # is an error for a name it does not have.
  n <- as.list(x$notes %||% list())
  get <- function(k) n[[k, exact = TRUE]]
  num <- function(k) {
    v <- suppressWarnings(as.numeric(get(k)))
    if (length(v) == 1L && !is.na(v)) v else 0
  }
  flag <- function(k) isTRUE(get(k))
  cnt <- function(k, what) if (num(k) > 0) sprintf(what, format(num(k), scientific = FALSE))
  why <- c(
    cnt("failed_calls", "%s request(s) failed"),
    cnt("truncated_calls", "%s response(s) cut off at the output cap"),
    cnt("scoring_failures", "%s relevance score(s) failed"),
    cnt("failed_summaries", "%s summary request(s) failed"),
    cnt("dropped_chunks", "%s chunk(s) did not fit"),
    cnt("chunks_dropped", "%s chunk(s) did not fit"),
    if (!is.null(get("call_cap_reached")))
      sprintf("stopped at the %s-request limit",
              format(get("call_cap_reached"), scientific = FALSE)),
    if (!is.null(get("cost_cap_reached")))
      sprintf("stopped at the $%s spending limit",
              format(get("cost_cap_reached"), scientific = FALSE)),
    if (length(get("cited_unknown")))
      sprintf("cites chunk(s) never sent: %s", paste(get("cited_unknown"), collapse = ", ")),
    if (length(get("cited_unparsed")))
      sprintf("citation(s) that could not be checked: %s",
              paste(utils::head(get("cited_unparsed"), 5), collapse = ", ")),
    unverified_reasons(x, num("unverified_evidence")),
    if (length(get("unread_pages")))
      sprintf("page(s) never read: %s", paste(utils::head(get("unread_pages"), 10), collapse = ", ")),
    if (flag("summaries_truncated")) "summaries cut to fit",
    cnt("truncations", "text cut to fit %s time(s)"),
    cnt("tokens_truncated", "%s token(s) cut to fit"),
    cnt("skipped", "%s section(s) skipped by the plan"),
    if (flag("degraded_to_bm25")) "relevance scoring fell back to word matching",
    if (identical(get("prefilter"), "spread"))
      "no chunk shared a word with the question, so the candidates were an evenly spread sample",
    if (flag("embedding_fallback")) "embeddings fell back to word matching",
    if (flag("degraded")) "fell back to a simpler method",
    # `skim` merges no answers: what it consolidates is the evidence it
    # extracted, and "could not be merged" sent a reader looking for answers.
    if (identical(get("merge_ok"), FALSE)) {
      if (identical(as_chr1(x$reader, ""), "skim")) "the evidence could not be consolidated"
      else "the answers could not be merged"
    }
  )
  err <- as_chr1(get("error"), "")
  # This answer's own steps: a trace shared with other runs holds their
  # failures too, and one of them is not why this answer is partial.
  tr <- answer_trace(x)
  if (!nzchar(err) && inherits(tr, "gr_trace") && length(tr$errors)) {
    # The first failure nothing recovered from, when there is one: an
    # embeddings request the lexical fallback replaced is not why an answer is
    # partial, and named first it hid the request that was. Failing that, the
    # first recovered one, which says why the fallback was needed.
    errs <- tr$errors
    open <- Filter(Negate(is_recovered_error), errs)
    err <- as_chr1((if (length(open)) open else errs)[[1]]$error, "")
  }
  if (nzchar(err)) why <- c(why, sprintf("first error: %s", substr(err, 1, 120)))
  # An ensemble member's own reason is in its notes, not these. Named, so a
  # member that fell back or cut its text is not hidden behind a failure the
  # ensemble happens to count, or behind an embeddings error a fallback
  # recovered from; after the rest, which say what the ensemble itself saw.
  members <- as.character(unlist(get("partial_members"), use.names = FALSE))
  if (length(members)) {
    why <- c(why, sprintf("member(s) %s returned a partial answer",
                          paste(sprintf("'%s'", members), collapse = ", ")))
  }
  if (!length(why) && is_nonblank(get("reason"))) why <- get("reason")
  why
}

#' Is a `trace$errors` entry a failure the pipeline recovered from?
#' @noRd
is_recovered_error <- function(e) is.list(e) && isTRUE(e[["recovered", exact = TRUE]])

#' The notes fields that list things: chunk ids, pages, member names, queries,
#' field names. Counts (`dropped_chunks`, `skipped`) are numbers, not lists,
#' and stay out. A new notes field that lists things belongs here too.
#' @noRd
.gr_answer_note_arrays <- c(
  "cited_unknown", "cited_unparsed", "unread_pages", "queries",
  "members", "signatures", "answered", "partial_members",
  "not_reported", "unknown", "unsupported", "dropped_unverified", "unreadable", "unresolved",
  "premise_chunks", "premise_members")

#' An answer's notes as as_json() writes them: an object, with each field that
#' lists things an array at every length (json_arrays()), an ensemble's
#' members' notes included.
#' @noRd
answer_notes_json <- function(notes) {
  notes <- as.list(notes %||% list())
  if (!length(notes)) return(structure(list(), names = character(0)))
  notes <- json_arrays(notes, .gr_answer_note_arrays)
  if (is.list(notes[["member_notes", exact = TRUE]])) {
    notes$member_notes <- lapply(notes$member_notes, answer_notes_json)
  }
  if (is.list(notes[["collapsed_members", exact = TRUE]])) {
    notes$collapsed_members <- lapply(notes$collapsed_members, function(g) I(as.character(g)))
  }
  notes
}

#' @export
as_json.gr_answer <- function(x, pretty = TRUE, ...) {
  w <- x[["warnings", exact = TRUE]] %||% character(0)
  used <- x$chunks_used %||% integer(0)
  # Written only when the premise was checked, so the record of a run that did
  # not check it is the one it always was. NA, checked and not flagged, is null.
  premise <- x[["premise", exact = TRUE]]
  as_json.default(c(list(answer = x$answer),
                    if (!is.null(premise)) list(premise = as_chr1(premise, NA_character_)),
                    list(
    reader = x$reader, question = x$question,
    # Arrays at every length: `auto_unbox` wrote one chunk id as a number and
    # two as an array, and no notes at all as `[]` rather than an object, so a
    # consumer that iterated over them broke on the short case.
    partial = x$partial,
    chunks_used = I(if (is.numeric(used)) as.integer(used) else as.vector(used)),
    notes = answer_notes_json(x$notes),
    # No evidence is no rows, as a table with none is: `[]`, not `null`.
    evidence = x$evidence %||% list(),
    # A list of pairs rather than a named vector: two warnings of one class would
    # otherwise become one JSON object with a repeated key.
    warnings = lapply(seq_along(w), function(i)
      list(class = as_chr1(names(w)[i], "gr_warning"), message = unname(w[[i]]))),
    # This run's steps only (answer_trace()): with a trace shared across runs,
    # the whole of it put other documents' text, in their prompts, into this
    # answer's record, and runs made after it too.
    trace = trace_as_list(answer_trace(x))
  )), pretty = pretty, ...)
}

#' Sentinel the readers use to mark "this chunk had nothing".
#' @noRd
.NOT_FOUND <- "NOT_IN_DOCUMENT"

#' Did the model report that the document does not contain the answer?
#'
#' Every reader is instructed to reply with exactly `"NOT_IN_DOCUMENT"` when the
#' excerpts do not answer the question. Use this rather than
#' `grepl("NOT_IN_DOCUMENT", ans$answer)`: a real answer can quote the sentinel
#' ("the log said NOT_IN_DOCUMENT, but revenue was 45.2 million"), and models do
#' not reproduce the token byte-exactly. They wrap it in quotes, bold it, or
#' add a full stop, in the punctuation of the language they are writing:
#' Japanese corner brackets, an ideographic full stop, French guillemets. This
#' matches the sentinel alone, modulo that decoration (any punctuation, symbol
#' or space around it), and treats a blank answer as not-found too.
#'
#' Models also explain themselves: `"NOT_IN_DOCUMENT. The excerpt only covers
#' costs."`, `"NOT_IN_DOCUMENT (the excerpt covers costs only)"`, or the
#' sentinel and then a blank line and a sentence. A reply that OPENS with the
#' sentinel, written as the token (with its underscores, or in capitals), and
#' breaks off there (a full stop, colon, semicolon or comma before a space, an
#' ideographic full stop or comma, a dash, an opening bracket, or a line
#' break) is the not-found verdict whatever follows, and counts as not-found.
#' That includes `"NOT_IN_DOCUMENT. However, ..."`: the model's
#' verdict is the sentinel, and what it adds is not an answer to the question.
#' The sentinel anywhere else in a reply, or opening a sentence that goes on
#' ("NOT_IN_DOCUMENT is what the log printed"), is part of a real answer.
#'
#' The v1 test was `grepl("not found|no information|not applicable", ...)` over
#' the whole response, which threw away every answer that happened to contain
#' one of those phrases.
#'
#' @param x An answer string, or `ans$answer`.
#' @return `TRUE` if the string is the not-found sentinel (or blank), or opens
#'   with it as described above.
#' @seealso [gr_answer], [gr_compare()], whose `summary$not_found` column is
#'   this predicate applied per recipe
#' @family reading functions
#' @export
#' @examples
#' is_not_found("NOT_IN_DOCUMENT")
#' is_not_found("**NOT_IN_DOCUMENT.**")     # models decorate it
#' is_not_found("")                          # nothing came back
#' is_not_found("NOT_IN_DOCUMENT. The excerpt only covers costs.")
#'
#' # A real answer that merely mentions the sentinel is NOT not-found.
#' is_not_found("The log said NOT_IN_DOCUMENT, but revenue was 45.2 million.")
is_not_found <- function(x) {
  x <- trimws(to_utf8(as_chr1(x)))
  if (!nzchar(x)) return(TRUE)
  # The sentinel alone, modulo surrounding punctuation and formatting, and a
  # space instead of the underscores.
  if (grepl(.gr_not_found_alone, x, perl = TRUE, ignore.case = TRUE)) return(TRUE)
  # The sentinel opening the reply and breaking off, then an explanation.
  # Only as the token, with an underscore or in capitals: "Not in document
  # form; the figures were in a spreadsheet" is an answer.
  if (!grepl(.gr_sentinel_opens, x, perl = TRUE, ignore.case = TRUE)) return(FALSE)
  m <- regmatches(x, regexec(.gr_sentinel_opens, x, perl = TRUE, ignore.case = TRUE))[[1]]
  grepl("_", m[2], fixed = TRUE) || identical(m[2], toupper(m[2]))
}

#' What a model puts around a one-word reply: punctuation, symbols and
#' spacing of any script (curly and CJK quote marks, guillemets, the
#' ideographic full stop, markdown bold).
#' @noRd
.gr_reply_decoration <- "[\\p{P}\\p{S}\\p{Z}\\s]*"

#' The sentinel and nothing but decoration: is_sentinel_reply()'s pattern,
#' made once.
#' @noRd
.gr_not_found_alone <- paste0("^", .gr_reply_decoration, "NOT[ _]IN[ _]DOCUMENT",
                              .gr_reply_decoration, "$")

#' The sentinel opening a reply, as its own word, then (past closing quote
#' marks, bold and brackets) a break: a sentence or clause mark before a
#' space, as the ideographic ones need none; a dash, a hyphen only with a
#' space after it; an opening bracket; or a line break. Not a full stop or a
#' hyphen inside a name ("NOT_IN_DOCUMENT.txt", "NOT_IN_DOCUMENT-2"). The
#' first group is the sentinel as written.
#' @noRd
.gr_sentinel_opens <- paste0(
  "^", .gr_reply_decoration, "(NOT[ _]IN[ _]DOCUMENT)[\"'`*_\\p{Pe}\\p{Pf}]*[ \\t\\p{Zs}]*",
  "(?:[.!?:;,](?=[\\s\\p{Z}])|(?!-)\\p{Pd}|-(?=[\\s\\p{Z}])|\\p{Ps}|",
  "[\u3001\u3002\uff01\uff0c\uff0e\uff1a\uff1b\uff1f]|\\R)")

#' Is `x` the one-word reply `word` (a regular expression) and nothing else
#' but decoration (.gr_reply_decoration)? Case is ignored.
#'
#' For the readers' sentinels: NOT_IN_DOCUMENT here, and NONE, which the
#' passage-extracting readers are told to reply with when an excerpt has
#' nothing (is_none_reply()).
#' @noRd
is_sentinel_reply <- function(x, word) {
  x <- to_utf8(as.character(x))
  !is.na(x) & grepl(paste0("^", .gr_reply_decoration, word, .gr_reply_decoration, "$"), x,
                    perl = TRUE, ignore.case = TRUE)
}

#' Did a passage-extracting reader's excerpt reply "nothing relevant"?
#'
#' The NONE the extraction prompt asks for, decorated in any script ("NONE.",
#' "**None**", or with an ideographic full stop or in corner brackets). Only
#' NONE alone: a passage copied verbatim may itself open with "None." ("None.
#' All patients completed the study."), and discarding it would lose evidence
#' without a word. Vectorised; NA is not a NONE.
#' @noRd
is_none_reply <- function(x) is_sentinel_reply(trimws(to_utf8(as.character(x))), "NONE")

#' A model call that succeeded but returned nothing usable.
#'
#' A blank completion is not an answer and must not be reported as one, nor
#' spliced into a downstream prompt as evidence.
#'
#' A reply cut off at its output cap passes: its text is real, and gr_result()
#' keeps it ok with finish_reason "length". It is not whole, though, so every
#' reader that takes one as an answer, a finding or a summary counts it with
#' reply_cut_off() in `notes$truncated_calls` and marks the answer partial.
#' @noRd
usable_text <- function(res) {
  isTRUE(res$ok) && nzchar(trimws(as_chr1(res$text)))
}

#' Write on a reader's request step how long the state it carried was.
#'
#' For the readers that carry a running state from one request to the next:
#' refine's draft and hierarchical's summaries. `from` is the length of
#' `trace$steps` before the request, and the step written to is the first
#' request after it with `label`. A request refused before it was sent records
#' no step, and then nothing is written. `tokens_in` is the state the request
#' carried and `tokens_out` the state handed on from it; either may be NULL.
#'
#' Kept on the request's own step, not as a step of its own, so a state length
#' sits next to the request it describes. Without it a state that grew, or
#' collapsed after one rewrite, could only be guessed at from the token totals.
#' @noRd
trace_state <- function(trace, from, label, tokens_in = NULL, tokens_out = NULL) {
  if (!inherits(trace, "gr_trace")) return(invisible(NULL))
  n <- length(trace$steps)
  if (n <= from) return(invisible(NULL))
  state <- Filter(Negate(is.null), list(tokens_in = if (!is.null(tokens_in)) as.integer(tokens_in),
                                        tokens_out = if (!is.null(tokens_out)) as.integer(tokens_out)))
  for (k in seq.int(from + 1L, n)) {
    st <- trace$steps[[k]]
    if (identical(as_chr1(st$label), label) && !identical(st$kind, "local")) {
      trace$steps[[k]]$state <- state
      break
    }
  }
  invisible(NULL)
}

#' Turn per-chunk extraction results into an evidence table.
#' Stack evidence tables that need not have the same columns.
#'
#' `ensemble` combines its members' evidence, and members are different readers.
#' Only readers whose evidence is model-written carry the verification columns,
#' so a plain `rbind()` of a `skim` table and a `map_reduce` table fails on
#' "numbers of columns of arguments do not match" -- which is what happened the
#' moment verification was added, and what the v1 shim tests caught. Union the
#' columns and fill what is absent, so a reader may add a column without
#' breaking every reader it can be ensembled with.
#' @noRd
rbind_evidence <- function(tables) {
  tables <- Filter(function(d) is.data.frame(d) && nrow(d), tables)
  if (!length(tables)) return(NULL)
  cols <- unique(unlist(lapply(tables, names), use.names = FALSE))
  filled <- lapply(tables, function(d) {
    for (nm in setdiff(cols, names(d))) d[[nm]] <- NA
    d[, cols, drop = FALSE]
  })
  out <- do.call(rbind, filled)
  rownames(out) <- NULL
  out
}

#' @noRd
evidence_table <- function(chunk_ids, texts, pages = NA_integer_, sections = NA_character_,
                           scores = NA_real_, source_text = NULL,
                           kind = c("verbatim", "extracted", "answer"), extra = NULL) {
  kind <- match.arg(kind)
  n <- length(texts)
  if (!n) {
    out <- data.frame(chunk_id = integer(0), text = character(0), page = integer(0),
                      section = character(0), score = numeric(0), kind = character(0),
                      stringsAsFactors = FALSE)
    for (nm in names(extra)) out[[nm]] <- extra[[nm]][0]
    return(out)
  }
  df <- data.frame(chunk_id = rep(chunk_ids, length.out = n),
                   text = vapply(texts, as_chr1, character(1), USE.NAMES = FALSE),
                   page = rep(pages, length.out = n),
                   section = rep(sections, length.out = n),
                   score = rep(scores, length.out = n),
                   # PER ROW, not per answer. `ensemble` combines evidence from
                   # several readers, so one kind for the whole table said
                   # "mixed" and then string-matched a map_reduce ANSWER against
                   # its chunk -- reporting a correct run as fabricated evidence.
                   kind = kind,
                   stringsAsFactors = FALSE)
  # Only readers whose evidence is MODEL-WRITTEN carry their sources. For the
  # readers that put verbatim chunk text here, source and span are the same
  # string and storing it twice would double an answer's size to prove that a
  # thing equals itself.
  if (!is.null(source_text)) {
    df$source_text <- vapply(rep(source_text, length.out = n), as_chr1, character(1),
                             USE.NAMES = FALSE)
    v <- verify_spans(df$text, df$source_text)
    df$verified <- v$verified
    df$match <- v$match
    # The edit-distance matcher's verdict beside the one acted on (shadow
    # mode; see verify_spans()).
    for (nm in grep("^quote_", names(v), value = TRUE)) df[[nm]] <- v[[nm]]
  }
  # Per-row labels that have to survive the filter below. `extract` puts the
  # FIELD each span supports here; attaching it after the fact would line the
  # labels up against the wrong rows, because the filter drops empty spans and
  # renumbers nothing.
  for (nm in names(extra)) df[[nm]] <- rep(extra[[nm]], length.out = n)
  df[has_content(df$text), , drop = FALSE]
}
