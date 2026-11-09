# doc-bench-qa.R: a reference of questions about documents, and the scorer
# that judges a gr_answer against it.
#
# Answers are free text, so an exact match would score "Revenue was 45.2
# million dollars" wrong against "45.2 million". The scorer instead asks
# whether the answer contains an accepted string, after folding the ways the
# same figure is written. A question the document cannot answer is right only
# when the reader said so, and only when nothing stopped the run from
# looking.

#' A reference of questions about documents
#'
#' Builds an [hr_reference()] whose items are questions about documents, for
#' benchmarking reading recipes with [gr_arm()] and scoring them with
#' [gr_scorer_answer()].
#'
#' Each item's payload, what an arm is given, is a list of `question` and
#' `document`. Its label is the list of acceptable answers, any one of
#' which an answer must contain to be right. An unanswerable item, one the
#' document does not answer, is labelled `"NOT_IN_DOCUMENT"`: the reader is
#' right when it says the document does not hold the answer. That an item is
#' unanswerable is held in its label alone, so an arm cannot read it from the
#' payload. An answer given
#' as `"NOT_IN_DOCUMENT"` marks its item unanswerable too. An item that is
#' neither unanswerable nor given an answer has no label, and every run on it
#' is scored `NA`.
#'
#' Items are clustered by document by default, since questions about one
#' document share its errors: a document given as a path or address is its
#' own cluster name, and text or chunks are named by a hash of their content.
#'
#' @param questions The questions, a character vector. Its names, when every
#'   question has one, are the item ids; otherwise the ids are `q1`, `q2`,
#'   and so on, zero-padded to a common width so they sort in order (`q01`
#'   to `q10` for ten questions).
#' @param documents The document each question is about: a character vector
#'   of file paths, web addresses or text (one per question, or one for all),
#'   or a list whose elements may also be chunks from [gr_segment()].
#' @param answers The acceptable answers, one element per question: a
#'   character vector with one answer each, or a list whose elements are
#'   character vectors of alternatives. `NA` or an empty element for a
#'   question with no answer (an unanswerable one, or one not yet labelled).
#'   Numbers are taken as text.
#' @param split The split of each item, one per item or one for all; see
#'   [hr_reference()]. When `split` is not given, every item goes in `"dev"`.
#' @param cluster The cluster of each item, one per item or one for all. By
#'   default, the document.
#' @param unanswerable Which questions the document does not answer: `NULL`
#'   for none, a logical vector (one per question, or one for all), item ids,
#'   or positions.
#' @return An [hr_reference()].
#' @seealso [gr_arm()], [gr_scorer_answer()], [hr_benchmark()]
#' @family harness
#' @export
#' @examples
#' ref <- gr_qa_reference(
#'   questions = c(revenue = "What was revenue in 2024?",
#'                 units = "How many units did Sheffield produce?",
#'                 ceo = "Who is the chief executive?"),
#'   documents = gr_example(),
#'   answers = list(c("45.2 million", "45,200,000"), "12,400", NA),
#'   unanswerable = "ceo", split = "test")
#' ref
#' ref$labels$ceo
gr_qa_reference <- function(questions, documents, answers, split, cluster = documents,
                            unanswerable = NULL) {
  if (!is.character(questions) || !length(questions) || anyNA(questions) ||
      any(!nzchar(trimws(questions)))) {
    gr_abort("`questions` must be a character vector of non-blank questions.",
             class = "hr_bad_reference")
  }
  n <- length(questions)
  ids <- names(questions)
  if (is.null(ids) || anyNA(ids) || any(!nzchar(trimws(ids)))) {
    ids <- sprintf("q%0*d", nchar(as.character(n)), seq_len(n))
  }
  questions <- unname(to_utf8(questions))

  docs <- qa_documents(documents, n)
  if (missing(cluster)) {
    cluster <- vapply(docs, document_cluster, character(1))
  }
  labels <- qa_answers(answers, n)
  absent <- qa_unanswerable(unanswerable, n, ids)
  for (i in seq_len(n)) {
    given <- labels[[i]]
    sentinel <- vapply(given, is_not_found, logical(1))
    if (any(sentinel) && !all(sentinel)) {
      gr_abort(sprintf(paste0("Item '%s' gives both NOT_IN_DOCUMENT and an answer; an item is ",
                              "either answerable or not."), ids[i]), class = "hr_bad_reference")
    }
    if (length(given) && all(sentinel)) absent[i] <- TRUE
    if (absent[i] && length(given) && !all(sentinel)) {
      gr_abort(sprintf("Item '%s' is marked unanswerable but has answers: %s.", ids[i],
                       paste(sprintf("'%s'", given), collapse = ", ")),
               class = "hr_bad_reference")
    }
    labels[[i]] <- if (absent[i]) .NOT_FOUND else if (length(given)) given else NA_character_
  }
  # The payload is what the arm sees, so it holds no part of the label:
  # whether an item is unanswerable is in its label alone.
  items <- lapply(seq_len(n), function(i) {
    list(question = questions[[i]], document = docs[[i]])
  })
  names(items) <- ids
  args <- list(items = items, labels = labels, cluster = cluster)
  if (!missing(split)) args$split <- split
  do.call(hr_reference, args)
}

#' The documents of a QA reference, one per question.
#' @noRd
qa_documents <- function(documents, n) {
  if (inherits(documents, "gr_chunks")) documents <- list(documents)
  if (is.character(documents)) documents <- as.list(documents)
  ok <- is.list(documents) && !is.data.frame(documents) && length(documents) %in% c(1L, n)
  if (ok) {
    ok <- all(vapply(documents, function(d) {
      inherits(d, "gr_chunks") || is_nonblank(d)
    }, logical(1)))
  }
  if (!ok) {
    gr_abort(sprintf(paste0("`documents` must give each of the %d question(s) a document (a path, ",
                            "address, text or chunks from gr_segment()), or one for all."), n),
             class = "hr_bad_reference")
  }
  if (length(documents) == 1L) documents <- rep(documents, n)
  unname(documents)
}

#' The default cluster of a document: a path or address names itself, and
#' text or chunks are named by their content, so the same document is the
#' same cluster however it was passed.
#' @noRd
document_cluster <- function(d) {
  if (is.character(d) && !grepl("\n", d, fixed = TRUE) && nchar(d, type = "bytes") <= 256L &&
      (is_url(d) || file.exists(d))) {
    return(d)
  }
  content <- if (inherits(d, "gr_chunks")) d$chunks$text else d
  paste0("doc-", substr(gr_hash(enc2utf8(as.character(content))), 1, 12))
}

#' The acceptable answers, as a list with a character vector per question
#' (empty when it has none).
#' @noRd
qa_answers <- function(answers, n) {
  if (missing(answers) || is.null(answers) || is.data.frame(answers) ||
      !(is.atomic(answers) || is.list(answers)) || length(answers) != n) {
    gr_abort(sprintf(paste0("`answers` must give each of the %d question(s) its acceptable ",
                            "answers: a vector, or a list of alternatives, with NA for none."), n),
             class = "hr_bad_reference")
  }
  lapply(as.list(answers), function(a) {
    if (is.null(a)) return(character(0))
    if (is.list(a)) a <- unlist(a, use.names = FALSE)
    if (!is.atomic(a)) {
      gr_abort("Each element of `answers` must be text, numbers or NA.",
               class = "hr_bad_reference")
    }
    # One number at a time: format() gives a vector a common number of
    # decimals, which would turn 1204 into "1204.0" beside 45.2.
    a <- if (is.numeric(a)) {
      vapply(a, function(v) format(v, scientific = FALSE, trim = TRUE, digits = 15),
             character(1))
    } else {
      as.character(a)
    }
    a <- unname(a[!is.na(a)])
    to_utf8(a[nzchar(trimws(a))])
  })
}

#' Which questions are unanswerable, as one logical per question.
#' @noRd
qa_unanswerable <- function(unanswerable, n, ids) {
  if (is.null(unanswerable)) return(rep(FALSE, n))
  if (is.logical(unanswerable) && !anyNA(unanswerable) && length(unanswerable) %in% c(1L, n)) {
    return(rep_len(unanswerable, n))
  }
  if (is.character(unanswerable) && !anyNA(unanswerable) && all(unanswerable %in% ids)) {
    return(ids %in% unanswerable)
  }
  if (is.numeric(unanswerable) && !anyNA(unanswerable) && all(unanswerable == round(unanswerable)) &&
      all(unanswerable >= 1 & unanswerable <= n)) {
    return(seq_len(n) %in% unanswerable)
  }
  gr_abort(paste0("`unanswerable` must be NULL, a logical per question (or one for all), ",
                  "item ids or positions."), class = "hr_bad_reference")
}

#' Score a reading recipe's answer against acceptable answers
#'
#' An [hr_scorer()] for the [gr_answer]s that [gr_arm()] returns, against a
#' reference from [gr_qa_reference()]. An answer is right when its text
#' contains any of the item's acceptable answers, after both are folded the
#' same way: lower case, runs of white space as one space, and thousands
#' separators dropped between digits, so `"1,204"`, `"1 204"` (with a
#' no-break or thin space) and `"1204"` are the same. A number in a label is
#' written in plain digits, so the label `100000` accepts `"100,000"`. A
#' number is matched whole: `"45.2"` is not found in `"145.2"` or `"45.25"`,
#' and `"12"` is not found in `".12"` (the decimal 0.12) or in
#' `"-12"`. A unit written against a number does not hide it (`"45.2m"` and
#' `"5mg"` contain `"45.2"` and `"5"`), and a hyphen between two numbers is
#' a range, not a minus sign (`"12-15"` contains `"15"`). On an unanswerable
#' item, labelled `"NOT_IN_DOCUMENT"`, the answer is right when
#' [is_not_found()] says it reports the document does not hold the answer.
#'
#' An answer that is not right gets the first of these failure kinds that
#' applies:
#' \describe{
#'   \item{`"parse_failure"`}{There is no answer text: the output is not a
#'     string or has no `answer` or `text`, or the text is blank.}
#'   \item{`"budget_stop"`}{The answer is `partial` and notes that a limit
#'     stopped it: the spending limit (`cost_cap_reached`), the call limit
#'     (`call_cap_reached`), or another limit that refused a request
#'     (`limit_refused`).}
#'   \item{`"refusal"`}{A model refused a request of the run: a step of the
#'     answer's trace finished with reason `"refusal"` or `"content_filter"`,
#'     or the output is a refused [gr_result].}
#'   \item{`"not_in_document"`}{An answer was expected and the reader said
#'     the document does not hold one.}
#'   \item{`"wrong"`}{Anything else, an answer to an unanswerable question
#'     included.}
#' }
#' An output that carries its own `failure_kind` keeps it, and a failed
#' [gr_result] is an `"error"`, as with [hr_scorer_exact()]. A stopped or
#' refused run that still found an acceptable answer is right. A not-found
#' answer from a run that was stopped or refused is that stop on an
#' unanswerable item as well: a reader that ran out of budget did not look.
#'
#' The `outcome` is the answer's folded text.
#'
#' @return An [hr_scorer()] named `"answer_contains"`.
#' @seealso [gr_qa_reference()], [gr_arm()], [hr_benchmark()], [hr_scorer()]
#' @family harness
#' @export
#' @examples
#' s <- gr_scorer_answer()
#' item <- list(question = "How many units?", document = gr_example())
#' s$fn(item, "Sheffield produced 12,400 units.", "12400")$correct
#' s$fn(item, "NOT_IN_DOCUMENT", "12400")$failure_kind
#' s$fn(item, "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT")$correct
gr_scorer_answer <- function() {
  hr_scorer(score_answer, name = "answer_contains")
}

#' The body of gr_scorer_answer().
#' @noRd
score_answer <- function(item, output, label) {
  fail <- function(kind, seen = NA_character_) {
    list(correct = FALSE, outcome = seen, failure_kind = kind)
  }
  # A refused reply is a refusal, not an error, before the generic check.
  if (inherits(output, "gr_result") && !isTRUE(output$ok) &&
      is_refusal_reason(output$finish_reason)) {
    return(fail("refusal"))
  }
  given <- output_failure(output)
  if (!is.na(given)) return(fail(given))
  text <- output_text(output)
  if (is.na(text) || !nzchar(trimws(text))) return(fail("parse_failure"))
  seen <- fold_answer(text)

  accepted <- label_text(label)
  accepted <- accepted[!is.na(accepted) & nzchar(trimws(accepted))]
  sentinel <- vapply(accepted, is_not_found, logical(1))
  # Only the label says an item is unanswerable: the item is what the arm is
  # given, and must not tell it.
  absent_ok <- any(sentinel)
  wanted <- unique(fold_answer(accepted[!sentinel]))
  if (!absent_ok && !length(wanted)) {
    return(list(correct = NA, outcome = seen, failure_kind = NA_character_))
  }
  stop <- answer_stop(output)
  found <- !is_not_found(text)
  if (found && any(vapply(wanted, contains_answer, logical(1), text = seen))) {
    return(list(correct = TRUE, outcome = seen, failure_kind = NA_character_))
  }
  if (!found && absent_ok && is.na(stop)) {
    return(list(correct = TRUE, outcome = seen, failure_kind = NA_character_))
  }
  if (!is.na(stop)) return(fail(stop, seen))
  fail(if (!found && length(wanted)) "not_in_document" else "wrong", seen)
}

#' Fold an answer for matching: lower case, white space runs as one space,
#' and thousands separators between digits dropped.
#'
#' A comma, no-break space, narrow no-break space or thin space is a
#' separator when a digit comes before it and exactly three digits after, so
#' "1,204,000" folds to "1204000" while "2023,2024" and "1,2" stay as they
#' are. A plain space is left alone: "in 2023 1 204 cases" would otherwise
#' join two numbers.
#' @noRd
fold_answer <- function(x) {
  x <- enc2utf8(as.character(x))
  # Written as escapes, so the pattern is UTF-8 text and PCRE matches it by
  # character whatever the session's encoding.
  seps <- "\u00a0\u202f\u2009"
  x <- gsub(paste0("(?<=[0-9])[,", seps, "](?=[0-9]{3}(?![0-9]))"), "", x, perl = TRUE)
  x <- gsub(paste0("[\\s", seps, "]+"), " ", x, perl = TRUE)
  tolower(trimws(x))
}

#' Whether folded `text` contains folded `needle` as a whole word or
#' number: a needle that starts (ends) with a letter or digit must not have
#' a letter or digit right before (after) it, so "no" is not found in "not".
#' A needle that ends with a digit may be followed by a letter, since a unit
#' is often written against a number ("45.2m", "5mg"), but not by a digit or
#' a decimal part (".5", ",5"). A needle that starts with a digit must not
#' follow a decimal point or comma, with or without a digit before it, so
#' "12" is not found in ".12" or "1.12"; nor a minus sign, so "12" is not
#' found in "-12". A hyphen with a digit right before it joins a range, so
#' "15" is found in "12-15".
#' @noRd
contains_answer <- function(needle, text) {
  if (!nzchar(needle)) return(FALSE)
  at <- gregexpr(needle, text, fixed = TRUE)[[1]]
  if (at[1L] < 0L) return(FALSE)
  word_start <- grepl("^[[:alnum:]]", needle)
  word_end <- grepl("[[:alnum:]]$", needle)
  digit_start <- grepl("^[0-9]", needle)
  digit_end <- grepl("[0-9]$", needle)
  if (!word_start && !word_end) return(TRUE)
  len <- nchar(needle)
  for (s in at) {
    before <- substr(text, max(1L, s - 2L), s - 1L)
    after <- substr(text, s + len, s + len + 1L)
    clash_before <- (word_start && grepl("[[:alnum:]]$", before)) ||
      (digit_start && grepl("([.,]|(^|[^0-9])[-\u2212])$", before))
    clash_after <- if (digit_end) grepl("^([0-9]|[.,][0-9])", after)
                   else word_end && grepl("^[[:alnum:]]", after)
    if (!clash_before && !clash_after) return(TRUE)
  }
  FALSE
}

#' Whether a finish reason says the model refused.
#' @noRd
is_refusal_reason <- function(x) {
  x <- tolower(as_chr1(x, ""))
  x %in% c("refusal", "content_filter")
}

#' What stopped a reader before it could answer: "budget_stop" for a limit
#' noted on a partial answer, "refusal" for a refused request on its trace,
#' else NA.
#' @noRd
answer_stop <- function(output) {
  if (!is.list(output)) return(NA_character_)
  notes <- output[["notes", exact = TRUE]]
  notes <- if (is.list(notes)) notes else list()
  capped <- !is.null(notes[["cost_cap_reached", exact = TRUE]]) ||
    !is.null(notes[["call_cap_reached", exact = TRUE]]) ||
    !is.null(notes[["limit_refused", exact = TRUE]])
  if (isTRUE(output[["partial", exact = TRUE]]) && capped) return("budget_stop")
  tr <- if (inherits(output, "gr_answer")) answer_trace(output) else NULL
  if (inherits(tr, "gr_trace")) {
    refused <- vapply(tr$steps, function(st) {
      is.list(st) && is_refusal_reason(st[["finish_reason", exact = TRUE]])
    }, logical(1))
    if (any(refused)) return("refusal")
  }
  NA_character_
}
