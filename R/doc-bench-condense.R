# doc-bench-condense.R: a test of what a reader keeps as it condenses a
# document. Facts are planted in a document, with lures (the same fact about
# a near-namesake, with another value) and a later correction of one fact,
# and the document is read forwards and in reverse. A reader that rewrites a
# running draft (refine) can lose an early fact, take a lure's value, or keep
# a figure the document later corrected; the scoring finds each in the
# answer's text, with no model judge.

#' Reverse the order of a text's paragraphs or sentences
#'
#' Turns a document around, unit by unit, so a reader that goes through it
#' in order meets the end first. Paragraphs are split at blank lines;
#' sentences at a full stop, question mark or exclamation mark followed by
#' white space. The units are joined as they were split, by a blank line or a
#' space. [gr_condensation_check()] reads each planted document forwards and
#' reversed with it.
#'
#' @param text A single string.
#' @param unit `"paragraph"` or `"sentence"`.
#' @return A single string.
#' @seealso [gr_condensation_check()]
#' @family harness
#' @export
#' @examples
#' gr_reverse_text("First part.\n\nSecond part.\n\nThird part.")
#' gr_reverse_text("One. Two. Three.", unit = "sentence")
gr_reverse_text <- function(text, unit = c("paragraph", "sentence")) {
  unit <- match.arg(unit)
  text <- as_chr1(text, "")
  if (identical(unit, "paragraph")) {
    parts <- strsplit(text, "\n[[:space:]]*\n")[[1]]
    parts <- parts[nzchar(trimws(parts))]
    return(paste(rev(trimws(parts)), collapse = "\n\n"))
  }
  parts <- strsplit(text, "(?<=[.!?])\\s+", perl = TRUE)[[1]]
  parts <- parts[nzchar(trimws(parts))]
  paste(rev(trimws(parts)), collapse = " ")
}

#' The places, things and measures the synthetic documents are built from.
#' @noRd
.gr_condense_entities <- c("Harbour depot", "Northgate clinic", "Riverside school",
                           "Elm Street library", "Westfield mill", "Hillcrest station",
                           "Lakeside farm", "Oakwood bridge", "Fenwick hall", "Marsh lane yard")
.gr_condense_measures <- c(budget = "the budget of the %s was %s million dollars",
                           staff = "the staff count of the %s was %s",
                           area = "the floor area of the %s was %s square metres",
                           visits = "the yearly visits to the %s came to %s")
.gr_condense_questions <- c(budget = "What was the budget of the %s?",
                            staff = "What was the staff count of the %s?",
                            area = "What was the floor area of the %s?",
                            visits = "How many yearly visits did the %s have?")
.gr_condense_filler <- c(
  "The committee met in the spring and reviewed the schedule without changes.",
  "Several contractors submitted their reports on time, and none raised concerns.",
  "The minutes record a short discussion of the parking arrangements.",
  "A survey of residents was planned for the following year.",
  "The auditors asked for copies of the signed agreements.",
  "Work on the access road continued through the summer months.",
  "Staff training sessions were held in the main meeting room.",
  "The board thanked the volunteers who organised the open day.",
  "Weather delayed the delivery of materials by about a week.",
  "The next review is due once the current phase is complete.")

#' A test of what a reader keeps as it condenses a document
#'
#' Builds a benchmark for [hr_benchmark()]: documents with planted facts,
#' lures and a later correction, read forwards and reversed, with one
#' question per fact and a scorer that needs no model. Arms that differ in
#' how they carry a document (a [gr_read_spec()] `refine_state`, a
#' `context_policy`, a reader) are run on its `reference` and scored with
#' its `scorer`; [gr_condensation_summary()] reads the result.
#'
#' Each document is a run of plain paragraphs, from `text` or from neutral
#' filler sentences, with `n_facts` facts planted at evenly spread positions
#' from the first paragraph to the last: "The budget of the Harbour depot was
#' 41.3 million dollars." Each fact gets a question whose answer is its
#' value. For the first `n_lures` facts a lure is planted as well, the same
#' measure for a near-namesake ("the Harbour depot annexe") with another
#' value. With `correction = TRUE`, the last fact is first stated with a
#' wrong value in the opening paragraphs and corrected near the end
#' ("Correction: ... was 248. The figure of 212 given earlier was wrong."). Every document is then given
#' forwards and reversed by paragraph ([gr_reverse_text()]), so a fact near
#' the end for one order is near the start for the other.
#'
#' The values are fixed by `seed` with arithmetic, not by the random number
#' generator, so the same call builds the same benchmark in any session.
#'
#' The scorer finds the values in the answer as [gr_scorer_answer()] finds an
#' answer: folded, and as a whole number. A fact item is right when the
#' answer holds its value. A lure item is right when it holds the value and
#' not the lure's. A correction item is right when it holds the corrected
#' value and not the superseded one. The `outcome` names what was found:
#' `"answer"`, `"lure"`, `"superseded"`, `"answer+lure"`,
#' `"answer+superseded"`, `"not_found"` or `"other"`.
#'
#' @param text `NULL` for synthetic documents, or a document of your own as
#'   one string, whose paragraphs (split at blank lines) the facts are
#'   planted between. Its own text must not mention the planted places.
#' @param n_facts Facts per document, 2 to 10.
#' @param n_lures How many of the facts get a lure, 0 to `n_facts - 1`.
#' @param correction Whether the last fact is stated wrongly early and
#'   corrected late.
#' @param n_documents Synthetic documents to build, each its own cluster;
#'   1 when `text` is given.
#' @param paragraphs Filler paragraphs per synthetic document, at least
#'   `n_facts`.
#' @param orders `"forward"`, `"reversed"` or both.
#' @param seed A whole number that fixes the places and values.
#' @param split The split of every item; see [hr_reference()].
#' @param check A `gr_condensation_check`.
#' @param bench An [hr_benchmark()] result on `check$reference`.
#' @param x A `gr_condensation_check`.
#' @param ... Ignored.
#' @return `gr_condensation_check()` returns an object of class
#'   `gr_condensation_check`, a list of `reference` (an [hr_reference()]
#'   whose payloads are `question` and `document`, as [gr_qa_reference()]
#'   builds them), `scorer` (an [hr_scorer()] named `"condensation"`),
#'   `items` (a data frame of `item`, `document`, `order`, `kind` (`"fact"`,
#'   `"lure"` or `"correction"`), `position` (where the fact sits in the
#'   forward document, from 0 at the start to 1 at the end), `question`,
#'   `answer`, `lure` and `superseded`) and `documents` (the texts, named by
#'   document and order).
#'
#'   `gr_condensation_summary()` returns a data frame with one row per arm
#'   and order: `fact_recall` (the share of runs whose answer holds the
#'   fact's value, over every item), `lure_rate` (the share of runs on lure
#'   items whose answer holds the lure's value), `correction_won` (the share
#'   of runs on correction items that are right), `late_recall` (fact recall
#'   over the facts in the last third of the document as it was read) and
#'   `runs`.
#' @seealso [gr_reverse_text()], [hr_benchmark()], [gr_arm()],
#'   [gr_read_spec()] for `refine_state` and `context_policy`
#' @family harness
#' @export
#' @examples
#' chk <- gr_condensation_check(n_facts = 4, n_lures = 1)
#' chk
#' head(chk$items[, c("item", "kind", "question", "answer", "lure")])
#'
#' # Two arms that differ only in what refine carries, on a stand-in model
#' # that answers every question with the planted budget.
#' cl <- gr_mock_client(function(m, p) {
#'   if (grepl("Reply with the edits", m[[length(m)]]$content, fixed = TRUE)) return("NONE")
#'   "The budget was 41.3 million dollars."
#' })
#' arms <- hr_sweep(gr_arm("thorough", list(reader = "refine", method = "paragraph")),
#'                  list(refine_state = c("draft", "ledger")))
#' bench <- suppressWarnings(hr_benchmark(arms, chk$reference, runs = 1, client = cl,
#'                                        scorer = chk$scorer))
#' gr_condensation_summary(chk, bench)
gr_condensation_check <- function(text = NULL, n_facts = 6L, n_lures = 2L, correction = TRUE,
                                  n_documents = 1L, paragraphs = 12L,
                                  orders = c("forward", "reversed"), seed = 1L,
                                  split = "test") {
  whole <- function(x, lo, hi, what) {
    ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && x == round(x) && x >= lo && x <= hi
    if (!ok) gr_abort(sprintf("`%s` must be one whole number from %s to %s.", what, lo, hi),
                      class = "gr_bad_setting")
    as.integer(x)
  }
  n_facts <- whole(n_facts, 2, length(.gr_condense_entities), "n_facts")
  n_lures <- whole(n_lures, 0, n_facts - 1L, "n_lures")
  seed <- whole(seed, 0, 1e6, "seed")
  if (!isTRUE(correction) && !isFALSE(correction)) {
    gr_abort("`correction` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  if (!is.character(orders) || !length(orders) || !all(orders %in% c("forward", "reversed"))) {
    gr_abort("`orders` must be \"forward\", \"reversed\" or both.", class = "gr_bad_setting")
  }
  orders <- unique(orders)
  if (!is.null(text)) {
    text <- as_chr1(text, "")
    base <- strsplit(text, "\n[[:space:]]*\n")[[1]]
    base <- trimws(base[nzchar(trimws(base))])
    if (length(base) < 2L) {
      gr_abort("`text` needs at least two paragraphs, separated by a blank line.",
               class = "gr_bad_setting")
    }
    n_documents <- 1L
  } else {
    n_documents <- whole(n_documents, 1, 1000, "n_documents")
    paragraphs <- whole(paragraphs, n_facts, 1000, "paragraphs")
  }
  docs <- list()
  rows <- list()
  for (j in seq_len(n_documents)) {
    s <- seed + 97L * (j - 1L)
    paras <- if (!is.null(text)) base else condense_filler(paragraphs, s)
    built <- condense_plant(paras, n_facts, n_lures, correction, s)
    doc_id <- sprintf("d%0*d", nchar(as.character(n_documents)), j)
    for (o in orders) {
      body <- if (identical(o, "forward")) built$text else gr_reverse_text(built$text)
      docs[[paste(doc_id, o, sep = ".")]] <- body
      f <- built$facts
      rows[[length(rows) + 1L]] <- data.frame(
        item = sprintf("%s.%s%d.%s", doc_id, f$kind, seq_len(nrow(f)), o),
        document = doc_id, order = o, kind = f$kind, position = f$position,
        question = f$question, answer = f$answer, lure = f$lure,
        superseded = f$superseded, stringsAsFactors = FALSE)
    }
  }
  items <- do.call(rbind, rows)
  rownames(items) <- NULL
  payload <- lapply(seq_len(nrow(items)), function(i) {
    list(question = items$question[i], document = docs[[paste(items$document[i], items$order[i],
                                                             sep = ".")]])
  })
  names(payload) <- items$item
  labels <- lapply(seq_len(nrow(items)), function(i) {
    c(answer = items$answer[i], lure = items$lure[i], superseded = items$superseded[i])
  })
  ref <- hr_reference(payload, labels = labels,
                      cluster = paste(items$document, items$order, sep = "."), split = split)
  structure(list(reference = ref, scorer = hr_scorer(score_condensation, name = "condensation"),
                 items = items, documents = docs),
            class = "gr_condensation_check")
}

#' Filler paragraphs, picked by arithmetic on the seed.
#' @noRd
condense_filler <- function(n, seed) {
  k <- length(.gr_condense_filler)
  vapply(seq_len(n), function(i) {
    a <- (seed + i) %% k + 1L
    b <- (seed + i + 4L) %% k + 1L
    paste(.gr_condense_filler[a], .gr_condense_filler[b])
  }, character(1))
}

#' A value for fact `i`, distinct for different `i` and `shift`.
#' @noRd
condense_value <- function(measure, i, seed, shift = 0L) {
  base <- (seed * 13L + i * 29L + shift * 17L) %% 70L
  switch(measure,
         budget = sprintf("%d.%d", 12L + base, (i + seed + shift) %% 9L + 1L),
         staff = as.character(140L + 3L * base + i),
         area = format(2000L + 37L * base + 11L * i, big.mark = ","),
         visits = format(10000L + 211L * base + 13L * i, big.mark = ","))
}

#' Plant the facts, lures and correction in a list of paragraphs.
#' @noRd
condense_plant <- function(paras, n_facts, n_lures, correction, seed) {
  n <- length(paras)
  ents <- .gr_condense_entities
  ents <- ents[(seq_along(ents) + seed - 1L) %% length(ents) + 1L]
  measures <- names(.gr_condense_measures)
  sentence <- function(m, ent, v) {
    s <- sprintf(.gr_condense_measures[[m]], ent, v)
    paste0(toupper(substr(s, 1L, 1L)), substr(s, 2L, nchar(s)), ".")
  }
  # Where each fact goes: evenly from the first paragraph to the last.
  at <- if (n_facts == 1L) 1L else round(seq(1, n, length.out = n_facts))
  add <- vector("list", n)
  facts <- vector("list", n_facts)
  for (i in seq_len(n_facts)) {
    m <- measures[(i + seed) %% length(measures) + 1L]
    ent <- ents[i]
    value <- condense_value(m, i, seed)
    kind <- if (i <= n_lures) "lure" else if (correction && i == n_facts) "correction" else "fact"
    lure <- NA_character_
    old <- NA_character_
    place <- at[i]
    if (identical(kind, "correction")) {
      # Stated wrongly near the start, corrected near the end.
      old <- condense_value(m, i, seed, shift = 3L)
      add[[min(2L, n)]] <- c(add[[min(2L, n)]], sentence(m, ent, old))
      fix <- sprintf(.gr_condense_measures[[m]], ent, value)
      place <- max(n - 1L, 1L)
      msg <- sprintf("Correction: %s. The figure of %s given earlier was wrong.", fix, old)
      add[[place]] <- c(add[[place]], msg)
    } else {
      add[[place]] <- c(add[[place]], sentence(m, ent, value))
    }
    if (identical(kind, "lure")) {
      lure <- condense_value(m, i, seed, shift = 5L)
      near <- min(place + 1L, n)
      add[[near]] <- c(add[[near]], sentence(m, paste(ent, "annexe"), lure))
    }
    facts[[i]] <- data.frame(kind = kind,
                             position = if (n > 1L) (place - 1) / (n - 1) else 0,
                             question = sprintf(.gr_condense_questions[[m]], ent),
                             answer = value, lure = lure, superseded = old,
                             stringsAsFactors = FALSE)
  }
  out <- vapply(seq_len(n), function(k) paste(c(paras[k], add[[k]]), collapse = " "),
                character(1))
  list(text = paste(out, collapse = "\n\n"), facts = do.call(rbind, facts))
}

#' The body of the condensation scorer.
#' @noRd
score_condensation <- function(item, output, label) {
  fail <- function(kind, seen = NA_character_) {
    list(correct = FALSE, outcome = seen, failure_kind = kind)
  }
  given <- output_failure(output)
  if (!is.na(given)) return(fail(given))
  text <- output_text(output)
  if (is.na(text) || !nzchar(trimws(text))) return(fail("parse_failure"))
  seen <- fold_answer(text)
  val <- function(nm) {
    v <- unname(label[nm])
    if (!length(v) || is.na(v)) NA_character_ else fold_answer(v)
  }
  has <- function(v) !is.na(v) && contains_answer(v, seen)
  answer <- has(val("answer"))
  lure <- has(val("lure"))
  old <- has(val("superseded"))
  outcome <- if (answer && lure) "answer+lure" else if (answer && old) "answer+superseded"
             else if (answer) "answer" else if (lure) "lure" else if (old) "superseded"
             else if (is_not_found(text)) "not_found" else "other"
  if (answer && !lure && !old) {
    return(list(correct = TRUE, outcome = outcome, failure_kind = NA_character_))
  }
  stop <- answer_stop(output)
  if (!is.na(stop)) return(fail(stop, outcome))
  fail(if (identical(outcome, "not_found")) "not_in_document" else "wrong", outcome)
}

#' @rdname gr_condensation_check
#' @export
print.gr_condensation_check <- function(x, ...) {
  it <- x$items
  cat(sprintf("<gr_condensation_check> %d document(s), %s, %d item(s)\n",
              length(unique(it$document)), paste(unique(it$order), collapse = " and "),
              nrow(it)))
  k <- table(factor(it$kind, levels = c("fact", "lure", "correction")))
  cat(sprintf("  per order: %s\n", paste(sprintf("%d %s", as.integer(k) /
                                                   length(unique(it$order)), names(k)),
                                         collapse = ", ")))
  invisible(x)
}

#' @rdname gr_condensation_check
#' @export
gr_condensation_summary <- function(check, bench) {
  if (!inherits(check, "gr_condensation_check")) {
    gr_abort("`check` must come from gr_condensation_check().", class = "gr_bad_setting")
  }
  if (!is.data.frame(bench) || !all(c("item", "arm", "correct", "outcome") %in% names(bench))) {
    gr_abort("`bench` must be an hr_benchmark() result.", class = "gr_bad_setting")
  }
  it <- check$items
  b <- merge(as.data.frame(bench)[, c("item", "arm", "correct", "outcome")],
             it[, c("item", "order", "kind", "position")], by = "item")
  if (!nrow(b)) gr_abort("`bench` holds none of the check's items.", class = "gr_bad_setting")
  # Where a fact sits as the document was read: reversed, the end comes first.
  read_at <- ifelse(b$order == "reversed", 1 - b$position, b$position)
  b$late <- read_at >= 2 / 3
  b$holds <- grepl("^answer", b$outcome)
  b$lured <- grepl("lure", b$outcome)
  rate <- function(x) if (length(x)) mean(x) else NA_real_
  keys <- unique(b[, c("arm", "order")])
  out <- do.call(rbind, lapply(seq_len(nrow(keys)), function(k) {
    s <- b[b$arm == keys$arm[k] & b$order == keys$order[k], , drop = FALSE]
    data.frame(arm = keys$arm[k], order = keys$order[k],
               fact_recall = rate(s$holds),
               lure_rate = rate(s$lured[s$kind == "lure"]),
               correction_won = rate(s$correct[s$kind == "correction"] %in% TRUE),
               late_recall = rate(s$holds[s$late]),
               runs = nrow(s), stringsAsFactors = FALSE)
  }))
  out <- out[order(out$arm, out$order), , drop = FALSE]
  rownames(out) <- NULL
  out
}
