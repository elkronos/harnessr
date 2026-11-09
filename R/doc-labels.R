# doc-labels.R: sheets for people to label, and reading them back.
#
# Every number the harness reports rests on a set somebody labelled by hand:
# the answers to the QA questions, the screening reference, the extracted
# fields, the graded set a signal is calibrated on, the verdicts a judge is
# checked against. Those labels are slow to collect and easy to spoil. A
# person shown the model's answer tends to agree with it, a row deleted in a
# spreadsheet silently drops an item, and "Yes " or "maybe" in a yes-or-no
# column turns into a missing value that nobody notices until the figures
# look odd. So the sheets are written blind by default, carry an id per row,
# and are read back strictly: a value that is not one of the allowed ones
# stops the read and names the row.

#' What each kind of sheet holds: the item columns copied onto it when
#' present (`context`), the ones it cannot do without (`need`), and the
#' columns a person fills in (`decisions`), the first of which says whether
#' the row has been labelled. `note` is the free-text column.
#' @noRd
.gr_label_kinds <- list(
  qa = list(context = c("document", "document_id", "title", "question"),
            need = c("document", "question"),
            decisions = c("answerable", "answer", "quote"), note = "note"),
  screening = list(context = c("document", "document_id", "title", "authors", "year",
                               "journal", "abstract"),
                   need = "document", decisions = "human_decision", note = "human_note"),
  extraction = list(context = c("document", "document_id", "title"),
                    need = "document", decisions = character(0), note = "note"),
  calibration = list(context = c("document", "document_id", "title", "question"),
                     need = c("document", "question"),
                     decisions = c("answerable", "answer"), note = "note"),
  judge = list(context = c("document", "document_id", "question", "criterion", "candidate"),
               need = "candidate", decisions = "verdict", note = "note")
)

#' Item columns about how the item was sampled or assigned. They are never
#' written to a sheet (the stratum or inclusion probability of a screening
#' row says what the model decided), and gr_read_labels() joins them back
#' from `items`.
#' @noRd
.gr_label_design <- c("cluster", "split", "stratum", "strata", "inclusion_prob", "weight",
                      "frame_n", "screened_n", "sampled_from")

#' Write a sheet for people to label
#'
#' Writes a CSV with one row per item, an `item_id` column, the columns a
#' person needs to judge the item, and empty columns for their decisions,
#' with a short instructions file beside it. Read the filled sheet back with
#' [gr_read_labels()].
#'
#' @section Kinds of sheet:
#' \describe{
#'   \item{`"qa"`}{Questions about documents. Items need `document` and
#'     `question`. The person fills `answerable` (yes or no: is the answer in
#'     the document), `answer` (required when answerable) and `quote` (the
#'     passage that gives it).}
#'   \item{`"screening"`}{Records to judge for eligibility. Items need
#'     `document`; `title`, `authors`, `year`, `journal` and `abstract` are
#'     copied when present. The person fills `human_decision` (include or
#'     exclude) and `human_note`, the columns [gr_calibrate()] reads.}
#'   \item{`"extraction"`}{Documents to extract fields from. Items need
#'     `document`, one row per document, and `fields` names the fields. The
#'     person fills one column per field, writing "not reported" when the
#'     document does not report it.}
#'   \item{`"calibration"`}{The graded set a signal is calibrated on. Items
#'     need `document` and `question`, and must include questions the
#'     document cannot answer. The person fills `answerable` and `answer`, and
#'     on a sheet with `blind = FALSE`, `correct` (yes or no: is the model's
#'     answer, shown beside it, right).}
#'   \item{`"judge"`}{Candidates a judge scores, to validate the judge
#'     against. Items need `candidate`, the text being judged, and may give
#'     `question` or `criterion`. The person fills `verdict` (pass or fail).}
#' }
#' Every sheet also has a free-text `note` column (`human_note` for
#' screening).
#'
#' @section Blind sheets:
#' With `blind = TRUE` only the columns listed above for the kind are copied
#' from `items`; nothing else is, so no model output, score, verdict or
#' sampling detail reaches the sheet by accident. With `blind = FALSE` the
#' other columns are copied too, each named `model_<name>` unless it already
#' starts with `model_`. Columns about how items were sampled or assigned
#' (`cluster`, `split`, `stratum`, `strata`, `inclusion_prob`, `weight`,
#' `frame_n`, `screened_n`, `sampled_from`) are never written, except on a
#' screening sheet. There a blind sheet carries the frame as the opaque key a
#' blind [gr_reference()] sheet carries, made from plain frame names when
#' `items` has them (a stacked frame also needs `stratum`, `inclusion_prob`,
#' `frame_n` and `screened_n`), so the sheet read back without `items` still
#' tells [gr_calibrate()] what was sampled; with `blind = FALSE` the columns
#' are written as they are. Give the same `items` to [gr_read_labels()] to
#' join the rest back.
#'
#' Calibration grading needs the model's answer, so a blind calibration sheet
#' has no `correct` column: the person records the reference answer, and the
#' model's answers are scored against it afterwards.
#'
#' @section Several reviewers:
#' With `reviewers = k` above 1, each reviewer gets a sheet of their own,
#' `<name>_r1.csv` to `<name>_r<k>.csv`, with a `reviewer` column already
#' filled, so that no reviewer sees another's decisions. [gr_read_labels()]
#' reads them together.
#'
#' @section How many items each set needs:
#' These are the sizes harnessr's development plan budgets for its own
#' evaluation, given here as a starting point, not as rules.
#' \describe{
#'   \item{QA}{About 480 questions over 88 documents, plus 88 explanatory
#'     questions, labelled by two people and adjudicated, with quotes. At an
#'     intraclass correlation of 0.2 for the paired difference between two
#'     settings within a document, this supports about an 8 point margin before a Holm correction; a contrast that sets a default needs
#'     about 136 scored documents, or a margin of about 10.5 points.}
#'   \item{Screening reference}{7 to 9 reviews, about 200 eligible and 1,800
#'     ineligible records, with two blind reviewers on one recent review. See
#'     [gr_screen_sample_size()] for the sample a recall target needs.}
#'   \item{Extraction}{60 documents by 10 fields, two people, with
#'     Krippendorff's alpha per field at its level of measurement
#'     ([gr_extract_agreement()]).}
#'   \item{Calibration graded set}{Sized from the error count it needs, not
#'     from the QA set: n >= 100 / (1 - accuracy) items, so that about 100 are
#'     wrong, with accuracy from a pilot. At 85% accuracy that is about 670
#'     items, on top of the QA set; at 80-90% accuracy the 480 QA questions
#'     hold only about 48 to 96 errors.}
#'   \item{Judge validation}{100 to 200 blind labels with at least 50
#'     positive and 50 negative items, plus 50 labelled by two people for the
#'     agreement between them. A bare total is not enough: at 10% prevalence
#'     100 labels hold 10 positives.}
#' }
#' The default shares of [hr_assign_splits()] put 10% of documents in `dev`,
#' 10% in `exploratory`, 30% in `calibration` and 50% in `test`.
#'
#' @section The file:
#' The CSV is UTF-8 with a byte-order mark, as [gr_reference()] writes it, so
#' a spreadsheet opens accented text correctly; save it back as "CSV UTF-8".
#' Leave a decision empty only for an item not yet labelled.
#'
#' @param kind `"qa"`, `"screening"`, `"extraction"`, `"calibration"` or
#'   `"judge"`; see "Kinds of sheet".
#' @param items A data frame with one row per item. Its ids come from an
#'   `item_id` column, else an `id` column; without either they are made
#'   from the kind and the row number (`"qa-0001"`), so pass the same rows in
#'   the same order to [gr_read_labels()].
#' @param path Where to write the CSV. `NULL` returns the sheet without
#'   writing. The instructions go to `<name>_instructions.txt` beside it.
#' @param blind Leave model output out of the sheet; see "Blind sheets".
#' @param reviewers How many people label each item, a whole number of at
#'   least 1; see "Several reviewers".
#' @param fields For `kind = "extraction"`, the fields: names, a [gr_fields()]
#'   schema or a [gr_protocol()]. A schema's descriptions and allowed values
#'   go into the instructions.
#' @return The sheet as a data frame (several reviewers' sheets stacked, with
#'   their `reviewer` column), invisibly when written; then its `paths`
#'   attribute holds the files written.
#' @seealso [gr_read_labels()], [hr_assign_splits()], [gr_reference()]
#' @family reference sets
#' @export
#' @examples
#' qa <- data.frame(document = c("a.pdf", "a.pdf", "b.pdf"),
#'                  question = c("What was revenue?", "Who audited it?",
#'                               "When did the trial start?"),
#'                  model_answer = c("45.2 million", "Not stated", "2019"))
#' gr_label_sheet("qa", qa)
#'
#' path <- file.path(tempdir(), "qa-labels.csv")
#' gr_label_sheet("qa", qa, path = path)
#' readLines(sub("[.]csv$", "_instructions.txt", path))
gr_label_sheet <- function(kind = c("qa", "screening", "extraction", "calibration", "judge"),
                           items, path = NULL, blind = TRUE, reviewers = 1, fields = NULL) {
  kind <- match.arg(kind)
  if (!isTRUE(blind) && !isFALSE(blind)) {
    gr_abort("`blind` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  rv <- suppressWarnings(as.numeric(reviewers))
  if (length(rv) != 1L || is.na(rv) || !is.finite(rv) || rv < 1 || rv != floor(rv)) {
    gr_abort("`reviewers` must be a single whole number of at least 1.", class = "gr_bad_setting")
  }
  if (!is.data.frame(items) || !nrow(items)) {
    gr_abort("`items` must be a data frame with one row per item.", class = "gr_bad_setting")
  }
  if (!is.null(path) && (!is.character(path) || length(path) != 1L || is.na(path) ||
                         !nzchar(path))) {
    gr_abort("`path` must be one file path, or NULL.", class = "gr_bad_setting")
  }
  spec <- label_spec(kind, fields, blind)
  miss <- setdiff(spec$need, names(items))
  if (length(miss)) {
    gr_abort(sprintf("A %s sheet needs `items` column(s) %s.", kind,
                     paste(sprintf("`%s`", miss), collapse = ", ")), class = "gr_bad_setting")
  }
  for (col in spec$need) {
    v <- trimws(as.character(items[[col]]))
    blank <- which(is.na(v) | !nzchar(v))
    if (length(blank)) {
      gr_abort(sprintf("Item %d has no `%s`.", blank[1], col), class = "gr_bad_setting")
    }
  }
  if (kind == "extraction" && anyDuplicated(as.character(items$document))) {
    gr_abort(sprintf("An extraction sheet has one row per document; '%s' appears twice.",
                     items$document[anyDuplicated(as.character(items$document))]),
             class = "gr_bad_setting")
  }
  ids <- label_ids(items, kind)

  sheet <- data.frame(item_id = ids, stringsAsFactors = FALSE)
  ctx <- intersect(spec$context, names(items))
  for (col in ctx) sheet[[col]] <- items[[col]]
  if (kind == "screening" && !is.null(items$sampled_from)) {
    # gr_calibrate() needs the frame, and a sheet read back without `items`
    # has nothing else to give it. A blind sheet carries it as the opaque key
    # gr_reference(blind = TRUE) writes, made here from plain frame names, so
    # it says nothing to the person reading it.
    if (blind) {
      keys <- label_frame_keys(items)
      if (is.null(keys)) {
        gr_warn(paste0("The items' `sampled_from` cannot be written as a key (a stacked ",
                       "frame needs `stratum`, `inclusion_prob`, `frame_n` and `screened_n`), ",
                       "so it is left off the sheet. Pass the same `items` to ",
                       "gr_read_labels() to join it back."), class = "gr_labels_missing")
      } else {
        sheet$sampled_from <- keys
      }
    } else {
      sheet$sampled_from <- items$sampled_from
      for (col in intersect(c("stratum", "inclusion_prob", "frame_n", "screened_n"),
                            names(items))) {
        sheet[[col]] <- items[[col]]
      }
    }
  }
  if (!blind) {
    rest <- setdiff(names(items), c("item_id", "id", spec$context, .gr_label_design,
                                    names(sheet)))
    for (col in rest) {
      nm <- if (startsWith(col, "model_")) col else paste0("model_", col)
      if (!nm %in% names(sheet)) sheet[[nm]] <- items[[col]]
    }
  }
  for (col in c(spec$decisions, spec$note)) sheet[[col]] <- NA_character_
  rownames(sheet) <- NULL

  sheets <- lapply(seq_len(rv), function(k) {
    if (rv == 1) return(sheet)
    cbind(sheet[, "item_id", drop = FALSE], reviewer = as.character(k),
          sheet[, -1L, drop = FALSE], stringsAsFactors = FALSE)
  })
  out <- if (rv == 1) sheet else do.call(rbind, sheets)
  rownames(out) <- NULL
  attr(out, "label_kind") <- kind
  if (is.null(path)) return(out)

  stem <- sub("[.]csv$", "", path, ignore.case = TRUE)
  files <- if (rv == 1) paste0(stem, ".csv") else sprintf("%s_r%d.csv", stem, seq_len(rv))
  for (k in seq_len(rv)) write_reference_csv(sheets[[k]], files[k])
  guide <- paste0(stem, "_instructions.txt")
  writeLines(enc2utf8(label_instructions(kind, spec, blind, rv, files)), guide, useBytes = TRUE)
  gr_msg(sprintf("Wrote %d item(s) to %s, with instructions in '%s'. Read the filled %s back with gr_read_labels().",
                 nrow(sheet), paste(sprintf("'%s'", files), collapse = ", "), guide,
                 if (rv == 1) "sheet" else "sheets"))
  attr(out, "paths") <- c(files, guide)
  invisible(out)
}

#' Read a filled label sheet
#'
#' Reads one or more sheets written by [gr_label_sheet()], checks every
#' value and id, and returns the labels in the form the package's
#' comparisons take: a screening reference for [gr_calibrate()], a table for
#' [gr_extract_agreement()], calibration labels, or labels to compare a
#' judge's verdicts with in [hr_agreement()]. A calibration sheet written
#' with `blind = FALSE` gives a graded set [hr_calibrate_signal()] takes; a
#' blind one gives reference answers, and the model's answers must be scored
#' against them to make the `correct` column it needs.
#'
#' @section What is checked:
#' * Every row has an `item_id`, and no id appears twice for one reviewer.
#'   With `items`, every id is one of the items', and an item missing from
#'   the sheets is reported with a warning of class `gr_labels_missing`.
#' * Yes-or-no columns (`answerable`, `correct`) hold yes, no, y, n, true,
#'   false, 1 or 0, in any case. `human_decision` holds include or exclude,
#'   and `verdict` pass or fail.
#' * An answerable QA or calibration item has an `answer`, and one that is
#'   not answerable has none; an item whose
#'   `answerable` is empty has no other decision filled; a calibration sheet
#'   with a `correct` column has it filled on every labelled row.
#' * An extraction row with any field filled has every field filled (with
#'   "not reported" where the document does not report it), and with a
#'   schema each value reads as its field's type: a whole number, a number,
#'   yes or no, or one of an `enum` field's values.
#'
#' Every value that fails is collected, and the error, of class
#' `gr_bad_labels`, names the sheet, the row (counting the header as row 1,
#' as a spreadsheet does) and the item. Its `problems` field holds them all.
#' A row whose first decision column is empty is an item not yet labelled: it
#' is returned with its decisions `NA`, and counted.
#'
#' @param path One or more CSV files written by [gr_label_sheet()] (one per
#'   reviewer), or the sheet as a data frame.
#' @param kind The kind the sheet was written as.
#' @param items The items the sheet was written from. Optional; with them,
#'   ids are checked against the items and the items' other columns
#'   (`cluster`, `split`, `inclusion_prob`, a signal's `score` and so on) are
#'   joined to the labels by `item_id`.
#' @param fields For `kind = "extraction"`: names, a [gr_fields()] schema or
#'   a [gr_protocol()]. A schema also checks each value's type. `NULL` takes
#'   every column of the sheet that is not an id, item, model or note column.
#' @return A data frame with one row per sheet row: `item_id`, `reviewer`
#'   when there are several, the item columns, the decisions and the note,
#'   then any columns joined from `items`. An item column named like one of
#'   the sheet's decision or note columns (`answer`, `verdict` and so on,
#'   often the model's own output) is joined as `model_<name>`, unless the
#'   sheet already has a column of that name. `answerable` and `correct` are
#'   logical; `human_decision` and `verdict` are lower case; extraction values
#'   are text as written. A calibration result has a `cluster` column (from
#'   `items`, else `document`), and a `correct` column only when the sheet
#'   was written with `blind = FALSE`; only then is it ready for
#'   [hr_calibrate_signal()]. Attributes `label_kind` and `unlabelled` (the
#'   number of rows not yet labelled) are set.
#' @seealso [gr_label_sheet()], [gr_calibrate()], [gr_extract_agreement()],
#'   [hr_calibrate_signal()], [hr_agreement()]
#' @family reference sets
#' @export
#' @examples
#' qa <- data.frame(document = c("a.pdf", "a.pdf", "b.pdf"),
#'                  question = c("What was revenue?", "Who audited it?",
#'                               "When did the trial start?"))
#' path <- file.path(tempdir(), "qa-read.csv")
#' gr_label_sheet("qa", qa, path = path)
#'
#' # A person fills it in; here the filling is simulated.
#' sheet <- read.csv(path, fileEncoding = "UTF-8-BOM")
#' sheet$answerable <- c("yes", "no", "yes")
#' sheet$answer <- c("45.2 million dollars", NA, "March 2019")
#' write.csv(sheet, path, row.names = FALSE, na = "")
#'
#' gr_read_labels(path, "qa", items = qa)
gr_read_labels <- function(path, kind, items = NULL, fields = NULL) {
  kinds <- names(.gr_label_kinds)
  if (missing(kind) || !is.character(kind) || length(kind) != 1L || !kind %in% kinds) {
    gr_abort(sprintf("`kind` must be one of %s.", paste(sprintf("'%s'", kinds), collapse = ", ")),
             class = "gr_bad_setting")
  }
  if (!is.null(items) && (!is.data.frame(items) || !nrow(items))) {
    gr_abort("`items` must be the data frame the sheet was written from, or NULL.",
             class = "gr_bad_setting")
  }
  spec <- label_spec(kind, fields, blind = TRUE, need_fields = FALSE)
  d <- label_read_sheets(path)
  if (!"item_id" %in% names(d)) {
    gr_abort("The sheet has no `item_id` column; read it from a sheet gr_label_sheet() wrote.",
             class = "gr_bad_labels")
  }
  known <- c("item_id", "reviewer", spec$context, .gr_label_design, spec$note,
             ".sheet", ".row", "correct", "answerable", "answer", "quote", "human_decision",
             "verdict")
  if (kind == "extraction") {
    if (!length(spec$fields)) {
      spec$fields <- setdiff(names(d), c(known, grep("^model_", names(d), value = TRUE)))
    }
    if (!length(spec$fields)) {
      gr_abort("The sheet has no field columns to read.", class = "gr_bad_labels")
    }
    spec$decisions <- spec$fields
  }
  miss <- setdiff(spec$decisions, names(d))
  if (length(miss)) {
    gr_abort(sprintf("This is not a %s sheet: it has no column(s) %s.", kind,
                     paste(sprintf("`%s`", miss), collapse = ", ")), class = "gr_bad_labels")
  }
  if (kind == "calibration" && "correct" %in% names(d)) spec$decisions <- c(spec$decisions, "correct")
  for (col in intersect(c("item_id", "reviewer", spec$decisions, spec$note), names(d))) {
    v <- trimws(d[[col]])
    v[!is.na(v) & !nzchar(v)] <- NA_character_
    d[[col]] <- v
  }

  probs <- list()
  flag <- function(rows, msg) {
    if (length(rows)) {
      probs[[length(probs) + 1L]] <<- data.frame(sheet = d$.sheet[rows], row = d$.row[rows],
                                                 item_id = d$item_id[rows], problem = msg,
                                                 stringsAsFactors = FALSE)
    }
  }
  flag(which(is.na(d$item_id)), "`item_id` is empty.")
  rv_key <- if (is.null(d$reviewer)) rep("", nrow(d)) else ifelse(is.na(d$reviewer), "", d$reviewer)
  key <- paste(rv_key, d$item_id, sep = "\u0001")
  dup <- which(!is.na(d$item_id) & duplicated(key))
  flag(dup, sprintf("item '%s' appears more than once%s.", d$item_id[dup],
                    ifelse(nzchar(rv_key[dup]), sprintf(" for reviewer %s", rv_key[dup]), "")))
  if (!is.null(d$reviewer)) flag(which(is.na(d$reviewer)), "`reviewer` is empty.")
  item_ids <- if (!is.null(items)) label_ids(items, kind) else NULL
  if (!is.null(item_ids)) {
    bad <- which(!is.na(d$item_id) & !d$item_id %in% item_ids)
    flag(bad, sprintf("item '%s' is not one of `items`.", d$item_id[bad]))
  }

  check_set <- function(col, allowed, what) {
    v <- lower_text(d[[col]])
    bad <- which(!is.na(v) & !v %in% allowed)
    flag(bad, sprintf("`%s` must be %s; found '%s'.", col, what, d[[col]][bad]))
    v
  }
  yes_no <- function(col) {
    v <- check_set(col, c(.gr_true_words, .gr_false_words), "yes or no")
    out <- rep(NA, length(v))
    out[v %in% .gr_true_words] <- TRUE
    out[v %in% .gr_false_words] <- FALSE
    out
  }
  labelled <- switch(kind,
    qa = , calibration = {
      ans <- yes_no("answerable")
      need <- which(ans %in% TRUE & is.na(d$answer))
      flag(need, "`answerable` is yes but `answer` is empty.")
      flag(which(ans %in% FALSE & !is.na(d$answer)),
           "`answerable` is no but `answer` is filled; clear one of them.")
      others <- intersect(c("answer", "quote", "correct"), names(d))
      filled <- Reduce(`|`, lapply(others, function(c) !is.na(d[[c]])))
      early <- which(is.na(d$answerable) & filled)
      flag(early, "`answerable` is empty but other decisions are filled.")
      if ("correct" %in% spec$decisions) {
        d$correct <- yes_no("correct")
        flag(which(!is.na(d$answerable) & is.na(d$correct)), "`correct` is empty.")
      }
      d$answerable <- ans
      !is.na(d$answerable)
    },
    screening = {
      d$human_decision <- check_set("human_decision", .gr_reference_decisions,
                                    "include or exclude")
      !is.na(d$human_decision)
    },
    judge = {
      d$verdict <- check_set("verdict", c("pass", "fail"), "pass or fail")
      !is.na(d$verdict)
    },
    extraction = {
      cells <- as.data.frame(lapply(d[spec$fields], function(v) !is.na(v)))
      any_filled <- rowSums(cells) > 0
      for (f in spec$fields) {
        gap <- which(any_filled & is.na(d[[f]]))
        flag(gap, sprintf("`%s` is empty; write 'not reported' if the document does not report it.", f))
        fd <- spec$schema[[f]]
        if (is.null(fd)) next
        v <- d[[f]]
        bad <- which(!is.na(v) & vapply(v, function(x) {
          is.null(agreement_read(x, fd)) && !is_one_of_words(x, .gr_unreported_words)
        }, logical(1)))
        flag(bad, sprintf("`%s` must be %s; found '%s'.", f, label_type_words(fd), v[bad]))
      }
      any_filled
    })

  if (length(probs)) {
    p <- do.call(rbind, probs)
    p <- p[order(p$sheet, p$row), , drop = FALSE]
    rownames(p) <- NULL
    shown <- utils::head(p, 8L)
    lines <- sprintf("%s row %d (item '%s'): %s", shown$sheet, shown$row,
                     ifelse(is.na(shown$item_id), "?", shown$item_id), shown$problem)
    more <- if (nrow(p) > nrow(shown)) sprintf("\n... and %d more.", nrow(p) - nrow(shown)) else ""
    gr_abort(sprintf("%d value(s) in the %s sheet cannot be read:\n%s%s", nrow(p), kind,
                     paste(lines, collapse = "\n"), more),
             class = "gr_bad_labels", problems = p)
  }

  if (!is.null(item_ids)) {
    groups <- if (is.null(d$reviewer)) list(d$item_id) else split(d$item_id, d$reviewer)
    lost <- unique(unlist(lapply(groups, function(g) setdiff(item_ids, g))))
    if (length(lost)) {
      gr_warn(sprintf("%d item(s) are missing from the %s, starting with '%s'.", length(lost),
                      if (length(groups) > 1L) "reviewers' sheets" else "sheet", lost[1]),
              class = "gr_labels_missing")
    }
  } else if (!is.null(d$reviewer)) {
    groups <- split(d$item_id, d$reviewer)
    all_ids <- unique(d$item_id)
    short <- names(groups)[vapply(groups, function(g) length(setdiff(all_ids, g)) > 0L,
                                  logical(1))]
    if (length(short)) {
      gr_warn(sprintf("Reviewer(s) %s do not have every item the others have.",
                      paste(short, collapse = ", ")), class = "gr_labels_missing")
    }
  }

  cols <- c("item_id", if (!is.null(d$reviewer)) "reviewer",
            setdiff(names(d), c("item_id", "reviewer", spec$decisions, spec$note,
                                ".sheet", ".row")),
            spec$decisions, intersect(spec$note, names(d)))
  out <- d[, cols, drop = FALSE]
  if (!is.null(items)) {
    at <- match(out$item_id, item_ids)
    # An item column named like a decision is usually the model's own output
    # (its answer, or a judge's verdict), the thing the labels are compared
    # with, so it comes back as model_<name>, as a blind = FALSE sheet names it.
    own <- c(spec$decisions, "correct", spec$note)
    for (col in setdiff(names(items), c("item_id", "id"))) {
      nm <- if (col %in% own) paste0("model_", col) else col
      if (!nm %in% names(out)) out[[nm]] <- items[[col]][at]
    }
  }
  if (kind == "calibration" && is.null(out$cluster)) out$cluster <- out$document
  rownames(out) <- NULL
  n_empty <- sum(!labelled)
  attr(out, "label_kind") <- kind
  attr(out, "unlabelled") <- n_empty
  msg <- sprintf("Read %d row(s): %d labelled, %d not yet labelled.", nrow(out),
                 nrow(out) - n_empty, n_empty)
  if (kind == "judge") {
    n_pass <- sum(out$verdict %in% "pass")
    n_fail <- sum(out$verdict %in% "fail")
    msg <- paste0(msg, sprintf(" %d pass, %d fail.", n_pass, n_fail))
    if (min(n_pass, n_fail) < 50L) {
      msg <- paste0(msg, " Validating a judge needs at least 50 of each.")
    }
  }
  gr_msg(msg)
  out
}

#' The columns of one kind of sheet, with the extraction fields resolved.
#' `schema` is the gr_fields schema when one was given, for the type check.
#' @noRd
label_spec <- function(kind, fields, blind, need_fields = TRUE) {
  spec <- .gr_label_kinds[[kind]]
  spec$fields <- character(0)
  spec$schema <- NULL
  if (kind == "calibration" && !blind) spec$decisions <- c(spec$decisions, "correct")
  if (kind != "extraction") return(spec)
  if (!is.null(fields) && !is.character(fields) &&
      !inherits(fields, c("gr_fields", "gr_protocol"))) {
    gr_abort("`fields` must be field names, a gr_fields() schema or a gr_protocol().",
             class = "gr_bad_setting")
  }
  schema <- if (inherits(fields, "gr_protocol")) fields$fields
            else if (inherits(fields, "gr_fields")) fields else NULL
  nms <- if (is.character(fields)) unique(fields) else names(schema)
  if (need_fields && !length(nms)) {
    gr_abort("An extraction sheet needs `fields`: names, a gr_fields() schema or a gr_protocol().",
             class = "gr_bad_setting")
  }
  if (length(nms) && (anyNA(nms) || any(!nzchar(nms)))) {
    gr_abort("Every field needs a name.", class = "gr_bad_setting")
  }
  # The other kinds' decision columns too: a sheet read back without `fields`
  # takes every column that is not one of these as a field, so a field named
  # `answer` would be skipped there without a word.
  clash <- intersect(nms, c("item_id", "reviewer", spec$context, spec$note, .gr_label_design,
                            "answerable", "answer", "quote", "correct", "human_decision",
                            "human_note", "verdict", ".sheet", ".row"))
  if (length(clash)) {
    gr_abort(sprintf("Field name(s) %s clash with the sheet's own columns.",
                     paste(sprintf("'%s'", clash), collapse = ", ")), class = "gr_bad_setting")
  }
  spec$fields <- nms
  spec$schema <- schema
  spec$decisions <- nms
  spec
}

#' The frame of each screening item as the key a blind gr_reference() sheet
#' carries: a key already is one, a plain "excluded", "kept" or "all" becomes
#' frame_key() over the rows of that frame, and a plain "stacked" row
#' becomes stacked_key() from its stratum and inclusion probability. NULL
#' when a row cannot be keyed; an empty `sampled_from` stays empty.
#' @noRd
label_frame_keys <- function(items) {
  raw <- as.character(items$sampled_from)
  plain <- lower_text(trimws(raw))
  out <- rep(NA_character_, length(raw))
  int_col <- function(col, i) {
    v <- if (is.null(items[[col]])) NA else suppressWarnings(as.numeric(items[[col]][i]))
    if (is.na(v)) NA_integer_ else as.integer(round(v))
  }
  docs <- as.character(items$document)
  for (i in seq_along(raw)) {
    if (is.na(raw[i]) || !nzchar(plain[i])) next
    if (!is.null(frame_unkey(raw[i]))) {
      out[i] <- raw[i]
    } else if (plain[i] == "stacked") {
      st <- if (is.null(items$stratum)) NA else lower_text(trimws(items$stratum[i]))
      p <- if (is.null(items$inclusion_prob)) NA
           else suppressWarnings(as.numeric(items$inclusion_prob[i]))
      size <- int_col("frame_n", i)
      scr <- int_col("screened_n", i)
      if (is.na(st) || !st %in% c("kept", "excluded") || is.na(p) || is.na(size) ||
          is.na(scr)) {
        return(NULL)
      }
      out[i] <- stacked_key(st, size, as.integer(round(p * size)), scr, docs[i])
    } else if (!plain[i] %in% c("excluded", "kept", "all")) {
      return(NULL)
    }
  }
  # One key per frame and size, salted with its own rows' documents as
  # gr_reference() salts it.
  todo <- which(is.na(out) & !is.na(raw) & nzchar(plain))
  if (length(todo)) {
    fn <- vapply(todo, function(i) int_col("frame_n", i), integer(1))
    sn <- vapply(todo, function(i) int_col("screened_n", i), integer(1))
    grp <- paste(plain[todo], fn, sn, sep = ":")
    for (g in unique(grp)) {
      at <- todo[grp == g]
      j <- which(grp == g)[1]
      out[at] <- frame_key(plain[todo[j]], fn[j], sn[j], docs[at])
    }
  }
  out
}

#' The id of each item: its `item_id` column, else its `id` column, else
#' the kind and the row number. Checked for blanks and repeats.
#' @noRd
label_ids <- function(items, kind) {
  ids <- if (!is.null(items$item_id)) items$item_id
         else if (!is.null(items$id)) items$id
         else sprintf("%s-%s", kind, formatC(seq_len(nrow(items)),
                                             width = max(4L, nchar(nrow(items))), flag = "0"))
  ids <- trimws(as.character(ids))
  blank <- which(is.na(ids) | !nzchar(ids))
  if (length(blank)) gr_abort(sprintf("Item %d has no id.", blank[1]), class = "gr_bad_setting")
  if (anyDuplicated(ids)) {
    gr_abort(sprintf("Item id '%s' appears more than once.", ids[anyDuplicated(ids)]),
             class = "gr_bad_setting")
  }
  ids
}

#' Read the sheets as text, every column, and stack them, with the file and
#' spreadsheet row of each row in `.sheet` and `.row`. Sheets without a
#' `reviewer` column are numbered in the order given when there are several.
#' @noRd
label_read_sheets <- function(path) {
  if (is.data.frame(path)) {
    d <- as.data.frame(lapply(path, function(v) {
      v <- if (is.factor(v)) as.character(v) else v
      if (is.logical(v)) ifelse(v, "yes", "no") else as.character(v)
    }), stringsAsFactors = FALSE, optional = TRUE)
    sheets <- list(d)
    names_of <- "the sheet"
  } else {
    if (!is.character(path) || !length(path) || anyNA(path)) {
      gr_abort("`path` must be the sheet file(s) gr_label_sheet() wrote, or a data frame.",
               class = "gr_bad_setting")
    }
    gone <- path[!file.exists(path)]
    if (length(gone)) {
      gr_abort(sprintf("No sheet at '%s'.", gone[1]), class = "gr_bad_setting")
    }
    sheets <- lapply(path, function(p) {
      # Blank lines are kept so that row numbers match the spreadsheet's;
      # rows with every cell empty are dropped below, once numbered.
      read_reference_csv(p, na.strings = "", colClasses = "character", check.names = FALSE,
                         blank.lines.skip = FALSE)
    })
    names_of <- basename(path)
  }
  for (i in seq_along(sheets)) {
    s <- sheets[[i]]
    if (!ncol(s)) gr_abort(sprintf("'%s' is empty.", names_of[i]), class = "gr_bad_labels")
    s$.row <- seq_len(nrow(s)) + 1L
    cells <- as.matrix(s[setdiff(names(s), ".row")])
    s <- s[rowSums(!is.na(cells) & nzchar(trimws(cells))) > 0L, , drop = FALSE]
    if (length(sheets) > 1L && is.null(s$reviewer)) s$reviewer <- rep(as.character(i), nrow(s))
    s$.sheet <- rep(names_of[i], nrow(s))
    sheets[[i]] <- s
  }
  all_cols <- unique(unlist(lapply(sheets, names)))
  sheets <- lapply(sheets, function(s) {
    for (col in setdiff(all_cols, names(s))) s[[col]] <- rep(NA_character_, nrow(s))
    s[, all_cols, drop = FALSE]
  })
  d <- do.call(rbind, sheets)
  rownames(d) <- NULL
  d
}

#' What a field's value must be, in words, for an error message.
#' @noRd
label_type_words <- function(field) {
  switch(field$type,
         integer = "a whole number or 'not reported'",
         number = "a number or 'not reported'",
         boolean = "yes, no or 'not reported'",
         enum = sprintf("one of %s, or 'not reported'",
                        paste(sprintf("'%s'", field$values), collapse = ", ")),
         "text or 'not reported'")
}

#' The instructions file for a sheet, as lines of text.
#' @noRd
label_instructions <- function(kind, spec, blind, reviewers, files) {
  what <- switch(kind,
    qa = c("Each row is a question about one document. Read the document and fill in:",
           "  answerable  yes or no: does the document answer the question?",
           "  answer      the answer, in your own words (required when answerable is yes)",
           "  quote       the passage of the document that gives the answer"),
    screening = c("Each row is a record to judge against the review's eligibility criteria. Fill in:",
                  "  human_decision  include or exclude",
                  "  human_note      why, briefly, when the decision was not obvious"),
    extraction = c("Each row is one document. Fill in every field column; write 'not reported'",
                   "when the document does not report the field. The fields:",
                   label_field_lines(spec)),
    calibration = c("Each row is a question about one document. Some questions cannot be answered",
                    "from their document; that is on purpose. Fill in:",
                    "  answerable  yes or no: does the document answer the question?",
                    "  answer      the answer (required when answerable is yes)",
                    if ("correct" %in% spec$decisions)
                      "  correct     yes or no: is the model's answer, shown in the model_ columns, right?"),
    judge = c("Each row is a candidate text to judge. Fill in:",
              "  verdict  pass or fail, judged against the question or criterion given"))
  c(sprintf("Labelling instructions: %s sheet", kind),
    "",
    what,
    "",
    sprintf("Use the `%s` column for anything worth recording about a row.", spec$note),
    "Leave a row's decisions empty only if you have not labelled it yet.",
    "Do not change, add or delete `item_id` values or rows.",
    if (blind) "The sheet is blind: it does not show what the model said. Do not look it up."
    else "The sheet shows the model's output in the model_ columns. Judge the item on its own merits.",
    if (reviewers > 1) c("",
      sprintf("There is one sheet per reviewer (%s). Fill only your own and do not", paste(basename(files), collapse = ", ")),
      "compare decisions until every sheet is done."),
    "",
    "Save the file as CSV UTF-8, keeping its name and columns.",
    "Read it back in R with gr_read_labels().")
}

#' One line per extraction field: its name, type and description.
#' @noRd
label_field_lines <- function(spec) {
  vapply(spec$fields, function(f) {
    fd <- spec$schema[[f]]
    if (is.null(fd)) return(sprintf("  %s", f))
    type <- if (identical(fd$type, "enum")) paste(fd$values, collapse = " / ") else fd$type
    sprintf("  %s (%s): %s", f, type, fd$description)
  }, character(1), USE.NAMES = FALSE)
}
