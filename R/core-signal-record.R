# core-signal-record.R: self-signals, recorded into a run's trace.
#
# A self-signal is a value the package produces about its own work: the
# iterative reader saying it can answer, the preview reader deciding to skip
# a section, the ensemble choosing how to settle its members. Each one is
# written into the trace as a local step, so that it can later be joined to
# graded items and calibrated. Recording one never sends a request, so the
# requests a run makes and their cache keys are the same with or without it.

#' Record a self-signal
#'
#' `hr_signal()` writes a value the package produced about its own work into
#' a run's trace, and `hr_signals()` reads every recorded signal back as one
#' table. Recording is all that happens: no signal changes what a reader does
#' unless a calibration record and a passing threshold allow it (see
#' [hr_calibrate_signal()], [hr_gate_threshold()] and [hr_apply_signal()]).
#'
#' A signal is stored as a local step labelled `"signal"`, with the name,
#' value, item and references in its `detail`. A local step is not a request,
#' so it is not a row of `as.data.frame(trace)`, is not counted in
#' `trace$calls`, and changes no request or cache key.
#'
#' Three signals are recorded by the readers:
#' \describe{
#'   \item{`gr.iterative.can_answer`}{One per step of the `iterative` reader
#'     whose reply parsed: `TRUE` when the step said it could answer.
#'     `refs$round` is the round.}
#'   \item{`gr.preview.skip`}{One value per section after the `preview`
#'     reader's plan: `TRUE` for a section the plan marked skip.
#'     `refs$section` is the section number and `refs$treatment` what the
#'     plan said.}
#'   \item{`gr.ensemble.adjudicate`}{How the `ensemble` reader settled its
#'     members: `"model"` when the adjudication request answered,
#'     `"concatenated"` when it failed and the findings were joined, or
#'     `"single member"` when only one member answered.}
#' }
#'
#' @param name For `hr_signal()`, the signal's name, one string, such as
#'   `"gr.iterative.can_answer"`. For `hr_signals()`, the names to keep, or
#'   `NULL` (the default) for every signal.
#' @param value The value: a logical, numeric or character vector with at
#'   least one element and no `NA` for a logical or numeric one. Several
#'   values record several observations of the signal in one step.
#' @param trace A `gr_trace` to record into, or an object holding one in
#'   `$trace` (an answer). `NULL` records nothing and only returns the signal.
#' @param item_id The item each value is about: one value, or one per element
#'   of `value`. `NA` when the caller has no item id.
#' @param refs `NULL`, or a named list of references (a round, a section
#'   number), each element either one value or one per element of `value`.
#' @return `hr_signal()` returns an `hr_signal` invisibly: a list with `name`,
#'   `value`, `type` (`"logical"`, `"numeric"` or `"character"`), `item_id`,
#'   `refs` and `step` (the step number in the trace, or `NA`).
#' @seealso [hr_calibrate_signal()], [hr_signal_policy()]
#' @family signals
#' @export
#' @examples
#' tr <- gr_trace()
#' hr_signal("demo.confident", TRUE, tr, item_id = "q1")
#' hr_signal("demo.confident", c(0.9, 0.2), tr, item_id = c("q2", "q3"))
#' hr_signals(tr)
#'
#' # The readers record their own signals.
#' cl <- gr_mock_client(function(m, p) {
#'   '{"can_answer": true, "answer": "45.2 million dollars", "next_query": ""}'
#' })
#' ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
#' ans <- gr_read(ch, "What was revenue?", cl, "iterative")
#' hr_signals(ans)
hr_signal <- function(name, value, trace = NULL, item_id = NA_character_, refs = NULL) {
  if (!is.character(name) || length(name) != 1L || !is_nonblank(name)) {
    gr_abort("`name` must be one non-blank string.", class = "gr_bad_setting")
  }
  type <- signal_type(value)
  n <- length(value)
  if (!is.atomic(item_id) || !length(item_id) || !length(item_id) %in% c(1L, n)) {
    gr_abort("`item_id` must have one value or one per element of `value`.",
             class = "gr_bad_setting")
  }
  item_id <- as.character(item_id)
  if (!is.null(refs)) {
    if (!is.list(refs) || is.null(names(refs)) || any(!nzchar(names(refs)))) {
      gr_abort("`refs` must be NULL or a named list.", class = "gr_bad_setting")
    }
    bad <- !vapply(refs, function(r) is.atomic(r) && length(r) %in% c(1L, n), logical(1))
    if (any(bad)) {
      gr_abort(sprintf("Each element of `refs` must be one value or one per element of `value` (%s).",
                       paste(names(refs)[bad], collapse = ", ")), class = "gr_bad_setting")
    }
  }
  tr <- signal_trace(trace)
  step <- NA_integer_
  if (!is.null(tr)) {
    trace_note(tr, "signal", list(signal = name, type = type, value = value,
                                  item_id = item_id, refs = refs))
    step <- length(tr$steps)
  }
  invisible(structure(list(name = name, value = value, type = type, item_id = item_id,
                           refs = refs, step = step), class = "hr_signal"))
}

#' The type a signal value is recorded as, checked.
#' @noRd
signal_type <- function(value) {
  if (is.factor(value)) value <- as.character(value)
  if (!is.atomic(value) || !length(value) || !is.null(dim(value))) {
    gr_abort("`value` must be a logical, numeric or character vector with at least one element.",
             class = "gr_bad_setting")
  }
  type <- if (is.logical(value)) "logical" else if (is.numeric(value)) "numeric"
          else if (is.character(value)) "character" else NA_character_
  if (is.na(type)) {
    gr_abort("`value` must be logical, numeric or character.", class = "gr_bad_setting")
  }
  if (type != "character" && anyNA(value)) {
    gr_abort("A logical or numeric signal `value` must not contain NA.", class = "gr_bad_setting")
  }
  type
}

#' The trace a signal goes into: the trace itself, or the one an answer holds.
#' @noRd
signal_trace <- function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "gr_trace")) return(x)
  if (is.list(x) && inherits(x[["trace", exact = TRUE]], "gr_trace")) return(x$trace)
  gr_abort("`trace` must be a gr_trace, an object holding one in `$trace`, or NULL.",
           class = "gr_bad_trace")
}

#' @rdname hr_signal
#' @param x For `hr_signals()`: a `gr_trace`, an object holding one in
#'   `$trace` (an answer, a stage result), or a list of these, such as the
#'   answers of several runs.
#' @return `hr_signals()` returns a data frame with one row per recorded value:
#'   `run_id`, `step`, `source` and `recipe` (the document and recipe the step
#'   was stamped with, or `NA`), `signal`, `type`, `item_id`, `index` (the
#'   value's position within its step), `value` (as text), `score` (the value
#'   as a number: 1 or 0 for a logical, the number for a numeric, `NA` for
#'   text) and `refs` (the references for that value as a JSON object, or
#'   `NA`). A trace recorded into twice by the same run, as a comparison
#'   does, lists each step once.
#' @export
hr_signals <- function(x, name = NULL) {
  traces <- signal_traces(x)
  rows <- list()
  seen <- character(0)
  for (tr in traces) {
    key <- paste0(tr$run_id, "\r", length(tr$steps))
    if (key %in% seen) next
    seen <- c(seen, key)
    for (st in tr$steps) {
      if (!identical(st$label, "signal") || !is.list(st$detail)) next
      rows[[length(rows) + 1L]] <- signal_rows(st, tr$run_id)
    }
  }
  out <- if (length(rows)) do.call(rbind, rows) else signal_rows(NULL, character(0))
  if (!is.null(name)) out <- out[out$signal %in% name, , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The traces in `x`, however it holds them.
#' @noRd
signal_traces <- function(x) {
  if (inherits(x, "gr_trace")) return(list(x))
  if (is.list(x) && inherits(x[["trace", exact = TRUE]], "gr_trace")) return(list(x$trace))
  if (is.list(x) && is.null(attr(x, "class", exact = TRUE))) {
    return(unlist(lapply(x, signal_traces), recursive = FALSE))
  }
  gr_abort("`x` must be a gr_trace, an object holding one in `$trace`, or a list of these.",
           class = "gr_bad_trace")
}

#' One signal step as table rows, one per value. With `st = NULL`, the empty
#' table.
#' @noRd
signal_rows <- function(st, run_id) {
  if (is.null(st)) {
    return(data.frame(run_id = character(0), step = integer(0), source = character(0),
                      recipe = character(0), signal = character(0), type = character(0),
                      item_id = character(0), index = integer(0), value = character(0),
                      score = numeric(0), refs = character(0), stringsAsFactors = FALSE))
  }
  d <- st$detail
  value <- d$value
  n <- length(value)
  type <- as_chr1(d$type, "character")
  score <- switch(type,
                  logical = as.numeric(as.logical(value)),
                  numeric = as.numeric(value),
                  rep(NA_real_, n))
  refs <- d$refs
  ref_txt <- if (is.null(refs) || !length(refs)) rep(NA_character_, n) else {
    vapply(seq_len(n), function(i) {
      one <- lapply(refs, function(r) if (length(r) == 1L) r else r[[i]])
      as.character(jsonlite::toJSON(one, auto_unbox = TRUE, null = "null", na = "null",
                                    digits = NA))
    }, character(1))
  }
  data.frame(run_id = as_chr1(run_id, NA_character_),
             step = as_int1(st$step, NA_integer_),
             source = as_chr1(st$source, NA_character_),
             recipe = as_chr1(st$recipe, NA_character_),
             signal = as_chr1(d$signal, NA_character_),
             type = type,
             item_id = rep_len(as.character(d$item_id %||% NA_character_), n),
             index = seq_len(n),
             value = as.character(value),
             score = score,
             refs = ref_txt,
             stringsAsFactors = FALSE)
}

#' @export
print.hr_signal <- function(x, ...) {
  cat(sprintf("<hr_signal> %s (%s), %d value%s", x$name, x$type, length(x$value),
              if (length(x$value) == 1L) "" else "s"))
  if (!is.na(x$step)) cat(sprintf(", step %d", x$step))
  cat("\n")
  print(utils::head(x$value, 10L))
  invisible(x)
}
