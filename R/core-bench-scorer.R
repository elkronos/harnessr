# core-bench-scorer.R: how an arm's output for one item is scored against its
# label.
#
# The contract is small on purpose: a scorer says whether the output was
# correct, what outcome it saw, and when it was wrong, why. The reasons are a
# fixed set, so a report can count parse failures and refusals apart from
# plain wrong answers and run its sensitivity analysis without them, while
# every one of them still counts as wrong in the main figures.

#' The reasons a run can be scored wrong.
#' @noRd
.hr_failure_kinds <- c("parse_failure", "refusal", "not_in_document", "wrong", "budget_stop",
                       "error")

#' A rule for scoring an arm's output
#'
#' A scorer is a function `fn(item, output, label)` that [hr_benchmark()]
#' calls once per run of an arm on an item. `item` is the item's payload,
#' `output` what the arm returned, and `label` the item's label from
#' [hr_reference()]. It returns a list of
#' \describe{
#'   \item{`correct`}{`TRUE`, `FALSE`, or `NA` when the item cannot be scored
#'     (it has no label).}
#'   \item{`outcome`}{What the scorer saw, as one string (for the exact
#'     scorer, the answer as compared), or `NA`.}
#'   \item{`failure_kind`}{Why a wrong output was wrong: `"parse_failure"`,
#'     `"refusal"`, `"not_in_document"`, `"wrong"`, `"budget_stop"` or
#'     `"error"`. `NA` when the output was correct.}
#' }
#' A wrong output whose `failure_kind` is `NA` is recorded as `"wrong"`. An
#' output with a `failure_kind` is counted wrong, so a `correct` of `NA`
#' beside one is recorded as `FALSE`, and `TRUE` beside one is an error in
#' the scorer. The exception is an item with no label: every run on it is
#' recorded `NA`, with its `failure_kind` kept.
#'
#' `hr_scorer_exact()` compares the output's text with the label, and is the
#' default scorer. The text is `output` itself when it is one string, or its
#' `answer` or `text` element when it is a list (a [gr_result] has `text`).
#' A label may hold several accepted answers; matching any one is correct.
#' A number in a label is compared as written in plain digits, so the label
#' `100000` accepts `"100000"` (not `"1e+05"`). With `normalise = TRUE` both sides are folded first: lower case, white
#' space trimmed and runs of it collapsed to one space. Before comparing, it
#' sorts out the outputs that are not answers:
#' * an output with a `failure_kind` element from the list above is wrong for
#'   that reason, so an arm can report a refusal or a parse failure itself;
#' * a [gr_result] with `ok = FALSE` is an `"error"`;
#' * no text at all (`NULL`, `NA`, an empty string, something with no
#'   `answer` or `text`) is a `"parse_failure"`;
#' * the text `NOT_IN_DOCUMENT` (in any case) is `"not_in_document"` unless
#'   the label accepts it.
#'
#' @param fn A function of `(item, output, label)` returning the list above.
#' @param name The scorer's name, one string; it is recorded with the
#'   benchmark.
#' @param normalise `TRUE` to fold case and white space before comparing.
#' @return An object of class `hr_scorer`: a list of `name` and `fn`.
#' @seealso [hr_benchmark()]
#' @family harness
#' @export
#' @examples
#' exact <- hr_scorer_exact()
#' exact$fn("Capital of France?", "  paris ", "Paris")
#' exact$fn("Capital of France?", "Lyon", "Paris")$failure_kind
#'
#' # A scorer of your own: a number within 1% of the label.
#' near <- hr_scorer(function(item, output, label) {
#'   x <- suppressWarnings(as.numeric(output))
#'   if (is.na(x)) return(list(correct = FALSE, outcome = NA, failure_kind = "parse_failure"))
#'   list(correct = abs(x - label) <= 0.01 * abs(label), outcome = format(x),
#'        failure_kind = NA)
#' }, name = "within_1pct")
#' near$fn(NULL, "45.3", 45.2)
hr_scorer <- function(fn, name) {
  if (!is.function(fn)) {
    gr_abort("`fn` must be a function of (item, output, label).", class = "hr_bad_scorer")
  }
  args <- names(formals(fn))
  if (!("..." %in% args) && length(args) < 3L) {
    gr_abort("`fn` must take three arguments, (item, output, label).", class = "hr_bad_scorer")
  }
  if (!is_bench_string(name)) {
    gr_abort("`name` must be one non-blank string.", class = "hr_bad_scorer")
  }
  structure(list(name = name, fn = fn), class = "hr_scorer")
}

#' @rdname hr_scorer
#' @export
hr_scorer_exact <- function(normalise = TRUE) {
  if (!isTRUE(normalise) && !isFALSE(normalise)) {
    gr_abort("`normalise` must be TRUE or FALSE.", class = "hr_bad_scorer")
  }
  fold <- if (normalise) normalise_answer else function(x) x
  hr_scorer(function(item, output, label) {
    given <- output_failure(output)
    if (!is.na(given)) return(list(correct = FALSE, outcome = NA_character_,
                                   failure_kind = given))
    text <- output_text(output)
    if (is.na(text) || !nzchar(trimws(text))) {
      return(list(correct = FALSE, outcome = NA_character_, failure_kind = "parse_failure"))
    }
    seen <- fold(text)
    accepted <- label_text(label)
    accepted <- accepted[!is.na(accepted)]
    if (!length(accepted)) return(list(correct = NA, outcome = seen, failure_kind = NA_character_))
    accepted <- fold(accepted)
    if (seen %in% accepted) return(list(correct = TRUE, outcome = seen,
                                        failure_kind = NA_character_))
    abstain <- identical(toupper(trimws(text)), "NOT_IN_DOCUMENT")
    list(correct = FALSE, outcome = seen,
         failure_kind = if (abstain) "not_in_document" else "wrong")
  }, name = if (normalise) "exact_normalised" else "exact")
}

#' @export
print.hr_scorer <- function(x, ...) {
  cat(sprintf("<hr_scorer %s>\n", x$name))
  invisible(x)
}

#' The accepted answers in a label, as text. A number is written in plain
#' digits, one at a time, as gr_qa_reference() writes it: as.character()
#' gives "1e+05" for 100000, which no answer written as 100000 can match.
#' NA stays NA.
#' @noRd
label_text <- function(label) {
  one <- function(a) {
    if (is.null(a)) return(character(0))
    if (is.list(a)) return(unlist(lapply(a, one), use.names = FALSE))
    if (is.factor(a)) return(as.character(a))
    if (is.numeric(a)) {
      return(vapply(a, function(v) {
        if (is.na(v)) NA_character_ else format(v, scientific = FALSE, trim = TRUE, digits = 15)
      }, character(1), USE.NAMES = FALSE))
    }
    as.character(unname(a))
  }
  out <- one(label)
  if (is.null(out)) character(0) else out
}

#' Fold case and white space.
#' @noRd
normalise_answer <- function(x) {
  x <- gsub("[[:space:]]+", " ", enc2utf8(as.character(x)), perl = TRUE)
  tolower(trimws(x))
}

#' The failure an output reports about itself, or NA: its own failure_kind,
#' or "error" for a failed gr_result.
#' @noRd
output_failure <- function(output) {
  if (!is.list(output)) return(NA_character_)
  kind <- output[["failure_kind", exact = TRUE]]
  if (is.character(kind) && length(kind) == 1L && kind %in% .hr_failure_kinds) return(kind)
  if (inherits(output, "gr_result") && !isTRUE(output$ok)) return("error")
  NA_character_
}

#' The text of an output: itself when it is one string, else its answer or
#' text element. NA when there is none.
#' @noRd
output_text <- function(output) {
  pick <- function(x) if (is.character(x) && length(x) == 1L) x else NA_character_
  if (is.character(output)) return(pick(output))
  if (is.list(output)) {
    a <- pick(output[["answer", exact = TRUE]])
    if (!is.na(a)) return(a)
    return(pick(output[["text", exact = TRUE]]))
  }
  NA_character_
}

#' Call a scorer and hold what it returns to the contract.
#' @noRd
score_output <- function(scorer, item, output, label, where, labelled = TRUE) {
  res <- scorer$fn(item, output, label)
  bad <- function(why) {
    gr_abort(sprintf("Scorer '%s' broke its contract on %s: %s.", scorer$name, where, why),
             class = "hr_bad_scorer")
  }
  if (!is.list(res) || !"correct" %in% names(res)) bad("it must return a list with `correct`")
  correct <- res$correct
  if (!is.logical(correct) || length(correct) != 1L) bad("`correct` must be TRUE, FALSE or NA")
  kind <- res[["failure_kind", exact = TRUE]]
  kind <- if (is.null(kind) || (length(kind) == 1L && is.na(kind))) NA_character_ else kind
  if (!is.character(kind) || length(kind) != 1L || (!is.na(kind) && !kind %in% .hr_failure_kinds)) {
    bad(sprintf("`failure_kind` must be NA or one of %s",
                paste(.hr_failure_kinds, collapse = ", ")))
  }
  outcome <- res[["outcome", exact = TRUE]]
  if (!is.null(outcome) && !(is.atomic(outcome) && length(outcome) == 1L)) {
    bad("`outcome` must be one value or NA")
  }
  outcome <- if (is.null(outcome)) NA_character_ else as.character(outcome)
  if (isTRUE(correct) && !is.na(kind)) bad("a correct output cannot have a `failure_kind`")
  # An unlabelled item cannot be scored either way, failure or not.
  if (!labelled) {
    correct <- NA
  } else {
    if (!is.na(kind)) correct <- FALSE
    if (isFALSE(correct) && is.na(kind)) kind <- "wrong"
  }
  list(correct = correct, outcome = outcome, failure_kind = kind)
}
