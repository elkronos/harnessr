# doc-extract-agreement.R: how far two extraction tables agree, field by
# field.
#
# A model's extraction is checked the way a second human extractor is: both
# fill the same schema for the same documents and the cells are compared. One
# number for the whole table hides the field that matters, since a schema
# mixes a design label any reader gets right with a sample size people misread,
# so every field gets its own Krippendorff's alpha at the level its values
# have. "Not reported" is a finding, not a gap, so a field one side left empty
# and the other filled is a disagreement and is counted as one.

#' Bookkeeping columns of an extraction table, never compared as fields.
#' @noRd
.gr_extract_bookkeeping <- c("document", "document_id", "n_filled", "n_unverified",
                             "conflicts", "status", "duplicate_of", "error")

#' The label "not reported" takes as a nominal category.
#' @noRd
.gr_not_reported <- "not reported"

#' Agreement between two extraction tables, field by field
#'
#' Compares two tables that filled one schema for the same documents: a
#' model's [gr_extract()] result against a person's, or two people's. Rows are
#' matched on the `by` column and each field is compared on its own, with
#' Krippendorff's alpha at the level of measurement the field has.
#'
#' @param x,y The two tables: [gr_extract()] results, or data frames with a
#'   `by` column and one column per field. Which is the reference does not
#'   matter, since alpha and percent agreement are symmetric.
#' @param fields Which fields to compare: a character vector of column names,
#'   a [gr_fields()] schema or a [gr_protocol()]. A schema or protocol also
#'   gives each field's type, from which its level and the way its values are
#'   read follow. `NULL` takes the schema of `x` (or `y`) when it is a
#'   [gr_extract()] result, and otherwise every column the two tables share
#'   other than `by` and the extraction table's bookkeeping columns.
#' @param levels The level of measurement of each field: `"nominal"`,
#'   `"ordinal"`, `"interval"` or `"ratio"`. A character vector named by
#'   field, or one unnamed value for every field. A field not named takes its
#'   level from its type: `"interval"` for `integer` and `number` fields,
#'   `"nominal"` for `string`, `enum` and `boolean` ones. An ordinal `enum`
#'   field is ordered as its `values` are declared; the ordinal level is an
#'   error for a field with no declared order (a `string` field, or a column
#'   with no schema that is not numeric or logical). The interval and ratio
#'   levels are an error for `enum` and `boolean` fields.
#' @param by The column that names the document in both tables.
#' @param B,conf,seed Bootstrap resamples for the alpha interval (0 for none),
#'   the confidence level, and the seed. The caller's random state is left as
#'   it was.
#'
#' @return An object of class `gr_extract_agreement`:
#'   \describe{
#'     \item{`table`}{One row per field and part: `field`, `part`, `level`,
#'       `n` (documents compared), `percent_agreement`, `alpha`, `lower`,
#'       `upper`, `not_reported_x`, `not_reported_y`, `unknown` (matched
#'       documents left out because a cell was unknown) and `note`, which says
#'       why alpha is `NA` when it is.}
#'     \item{`pairs`}{Long form, one row per document and field: `document`,
#'       `field`, the two values as text (`x`, `y`) and whether each was a
#'       value, not reported or unknown (`x_state`, `y_state`). Filter it on
#'       `x != y` to read the disagreements.}
#'     \item{`unmatched`}{The documents only one table has, as a list with
#'       `x` and `y`. They are not compared.}
#'     \item{`notes`, `conf`, `bootstrap`}{As in [hr_agreement()].}
#'   }
#'
#' @section Not reported:
#' A cell that is empty, `NA`, or says "not reported", "not stated", "N/A" or
#' the like is read as the document not reporting the field. In a nominal
#' field that is one more category, so one side filling a field the other
#' found unreported is a disagreement like any other. An ordinal, interval or
#' ratio field cannot place "not reported" on its scale, so it gets two rows:
#' `part = "reported"`, the nominal agreement on whether the field is reported
#' at all, and `part = "value"`, the agreement on the value among the
#' documents where both tables report it. A nominal field has the single row
#' `part = "value"`.
#'
#' A cell is unknown, and left out of that field, when the value is there but
#' cannot be read as the field's type ("120 (60 per arm)" in an integer field,
#' an undeclared `enum` value), and in a [gr_extract()] result when the
#' document was not read in full: a `"failed"` or `"skipped"` row is unknown in
#' every field, and an empty cell of an `"incomplete"` row is unknown rather
#' than not reported. A row that duplicates another document is left out, so
#' no document counts twice. A data frame with a `status` column is read the
#' same way.
#'
#' @section How values are compared:
#' A `string` value is compared after folding case, quote marks, spaces and a
#' trailing full stop, as [gr_extract()] does when two parts of one document
#' give one value two ways. Nothing else is folded, so "RCT" and "randomised
#' controlled trial" are two values. An `enum` value is matched to the
#' declared values ignoring case. Numbers are read as [gr_field()] describes
#' and compared exactly, so percent agreement on a numeric field counts
#' identical values; alpha at the interval or ratio level gives partial credit
#' for near misses.
#'
#' @section Alpha:
#' Krippendorff's alpha is 1 - D_o / D_e, observed over expected disagreement
#' computed from the coincidence matrix with the difference function of the
#' level (Krippendorff 2011). Its interval is a percentile bootstrap over
#' documents (Hayes and Krippendorff 2007). Alpha is reported only when at
#' least 30 documents are compared and the field is not constant; otherwise it
#' is `NA`, `note` says why, and percent agreement is the figure to read.
#' Agreement between a model and a person measures how far the model's table
#' could stand in for a person's, not which of the two is right.
#'
#' @references
#' Hayes, A. F. and Krippendorff, K. (2007). Answering the call for a standard
#' reliability measure for coding data. *Communication Methods and Measures*,
#' 1(1), 77-89.
#'
#' Krippendorff, K. (2011). Computing Krippendorff's alpha-reliability.
#' University of Pennsylvania, Annenberg School for Communication.
#'
#' @seealso [gr_extract()], [hr_agreement()], [gr_fields()]
#' @export
#' @examples
#' fields <- gr_fields(
#'   design = gr_field("Study design", type = "enum",
#'                     values = c("rct", "cohort", "case series")),
#'   n      = gr_field("Number randomised", type = "integer")
#' )
#' model <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf", "d.pdf"),
#'                     design = c("rct", "cohort", "rct", NA),
#'                     n = c(120, 85, NA, 40))
#' person <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf", "d.pdf"),
#'                      design = c("RCT", "cohort", "rct", "case series"),
#'                      n = c(120, 58, NA, 40))
#' ag <- gr_extract_agreement(model, person, fields = fields, B = 0)
#' ag
#' subset(ag$pairs, x != y)
gr_extract_agreement <- function(x, y, fields = NULL, levels = NULL, by = "document",
                                 B = 2000, conf = 0.95, seed = 1) {
  check_conf(conf)
  check_boot(B, seed)
  by <- as_chr1(by)
  if (!is.null(fields) && !is.character(fields) &&
      !inherits(fields, c("gr_fields", "gr_protocol"))) {
    gr_abort("`fields` must be field names, a gr_fields() schema or a gr_protocol().",
             class = "gr_bad_setting")
  }
  tx <- agreement_rows(x, "x", by)
  ty <- agreement_rows(y, "y", by)

  schema <- if (inherits(fields, "gr_protocol")) fields$fields
            else if (inherits(fields, "gr_fields")) fields
            else if (inherits(x, "gr_extraction")) x$fields
            else if (inherits(y, "gr_extraction")) y$fields
            else NULL
  nms <- if (is.character(fields)) unique(fields)
         else if (!is.null(schema)) names(schema)
         else setdiff(intersect(names(tx$table), names(ty$table)),
                      c(by, .gr_extract_bookkeeping))
  if (!length(nms)) gr_abort("There are no fields to compare.", class = "gr_bad_setting")
  for (side in list(tx, ty)) {
    miss <- setdiff(nms, names(side$table))
    if (length(miss)) {
      gr_abort(sprintf("`%s` has no column for field(s): %s.", side$arg,
                       paste(miss, collapse = ", ")), class = "gr_bad_setting")
    }
  }
  lv <- agreement_levels(levels, nms)

  keys <- intersect(tx$key, ty$key)
  if (!length(keys)) {
    gr_abort(sprintf("No `%s` is in both tables, so there is nothing to compare.", by),
             class = "gr_bad_setting")
  }
  ix <- match(keys, tx$key); iy <- match(keys, ty$key)
  unmatched <- list(x = setdiff(tx$key, keys), y = setdiff(ty$key, keys))

  rows <- list(); pairs <- list(); notes <- character(0)
  for (nm in nms) {
    field <- agreement_field(nm, schema, tx$table[[nm]], ty$table[[nm]])
    level <- if (!is.na(lv[[nm]])) lv[[nm]] else
      if (field$type %in% c("integer", "number")) "interval" else "nominal"
    # Text with no declared order would otherwise be ranked alphabetically,
    # and labels read as numbers would all turn unknown; both hide the cause.
    if (level == "ordinal" && !field$type %in% c("integer", "number", "boolean") &&
        !(identical(field$type, "enum") && length(field$values))) {
      gr_abort(sprintf(paste0("Field `%s` has no declared order; declare it as an enum with ",
                              "its values in order, or use the nominal level."), nm),
               class = "gr_bad_setting")
    }
    if (level %in% c("interval", "ratio") && field$type %in% c("enum", "boolean")) {
      gr_abort(sprintf(paste0("Field `%s` is of type %s, but the %s level needs numbers; ",
                              "use the nominal or ordinal level."), nm, field$type, level),
               class = "gr_bad_setting")
    }
    cx <- agreement_cells(tx$table[[nm]][ix], field, level, tx$unknown[ix], tx$partial[ix],
                          nm, tx$unknown_fields[ix])
    cy <- agreement_cells(ty$table[[nm]][iy], field, level, ty$unknown[iy], ty$partial[iy],
                          nm, ty$unknown_fields[iy])
    pairs[[nm]] <- data.frame(document = keys, field = nm, x = cx$label, y = cy$label,
                              x_state = cx$state, y_state = cy$state,
                              stringsAsFactors = FALSE)
    known <- cx$state != "unknown" & cy$state != "unknown"
    nr_x <- sum(known & cx$state == "not reported")
    nr_y <- sum(known & cy$state == "not reported")
    unknown <- sum(!known)
    if (level == "nominal") {
      a <- cx$label[known]; b <- cy$label[known]
      res <- agreement_part(a, b, "nominal", B, conf, seed)
      rows[[length(rows) + 1L]] <- agreement_row(nm, "value", level, res, nr_x, nr_y, unknown)
    } else {
      rx <- ifelse(cx$state == "value", "reported", .gr_not_reported)
      ry <- ifelse(cy$state == "value", "reported", .gr_not_reported)
      res <- agreement_part(rx[known], ry[known], "nominal", B, conf, seed)
      rows[[length(rows) + 1L]] <- agreement_row(nm, "reported", "nominal", res, nr_x, nr_y,
                                                 unknown)
      both <- known & cx$state == "value" & cy$state == "value"
      vx <- cx$value[both]; vy <- cy$value[both]
      if (level == "ratio" && any(c(unlist(vx), unlist(vy)) < 0)) {
        gr_abort(sprintf("Field `%s` has a value below zero, so it cannot be at the ratio level.",
                         nm), class = "gr_bad_setting")
      }
      if (level == "ordinal" && identical(field$type, "enum")) {
        vx <- factor(unlist(vx), levels = field$values)
        vy <- factor(unlist(vy), levels = field$values)
      } else {
        vx <- unlist(vx); vy <- unlist(vy)
      }
      res <- agreement_part(vx, vy, level, B, conf, seed)
      rows[[length(rows) + 1L]] <- agreement_row(nm, "value", level, res, nr_x, nr_y, unknown)
    }
  }
  table <- do.call(rbind, rows)
  rownames(table) <- NULL
  pairs <- do.call(rbind, pairs)
  rownames(pairs) <- NULL
  if (length(unmatched$x) || length(unmatched$y)) {
    notes <- c(notes, sprintf(paste0("%d document(s) only in `x` and %d only in `y` were not ",
                                     "compared; see $unmatched."),
                              length(unmatched$x), length(unmatched$y)))
  }
  dropped <- tx$duplicates + ty$duplicates
  if (dropped) {
    notes <- c(notes, sprintf(paste0("%d row(s) repeating another document's text were left ",
                                     "out, so no document counts twice."), dropped))
  }
  structure(list(table = table, pairs = pairs, unmatched = unmatched, notes = notes,
                 conf = conf, bootstrap = list(B = as.integer(B), seed = seed)),
            class = "gr_extract_agreement")
}

#' The rows of one side, keyed on `by`, with what each row says about the
#' cells it leaves empty.
#'
#' `unknown` marks rows whose every cell is unknown (the document was not
#' read), `partial` rows where an empty cell is unknown rather than not
#' reported (some requests failed), and `unknown_fields` the fields each
#' row's answer recorded as given but unreadable.
#' @noRd
agreement_rows <- function(t, arg, by) {
  answers <- if (inherits(t, "gr_extraction")) t$answers else NULL
  if (inherits(t, "gr_extraction")) t <- t$table
  if (!is.data.frame(t)) {
    gr_abort(sprintf("`%s` must be a gr_extract() result or a data frame.", arg),
             class = "gr_bad_setting")
  }
  if (!by %in% names(t)) {
    gr_abort(sprintf("`%s` has no `%s` column to match documents on.", arg, by),
             class = "gr_bad_setting")
  }
  # A blank duplicate_of, as a table saved with write.csv(na = "") reads back,
  # is not a duplicate, as in as_screening_table().
  dup <- if ("duplicate_of" %in% names(t)) {
    d <- as.character(t$duplicate_of)
    !is.na(d) & nzchar(trimws(d))
  } else rep(FALSE, nrow(t))
  t <- t[!dup, , drop = FALSE]
  key <- as.character(t[[by]])
  if (anyNA(key) || any(!nzchar(key))) {
    gr_abort(sprintf("`%s` has a row with no `%s`.", arg, by), class = "gr_bad_setting")
  }
  if (anyDuplicated(key)) {
    gr_abort(sprintf("`%s` has more than one row for `%s` %s.", arg, by,
                     key[anyDuplicated(key)]), class = "gr_bad_setting")
  }
  status <- if ("status" %in% names(t)) as.character(t$status) else rep(NA_character_, nrow(t))
  # gr_extract() names its answers by document, whatever column rows match on.
  doc <- if ("document" %in% names(t)) as.character(t$document) else key
  unknown_fields <- lapply(doc, function(k) {
    a <- if (length(answers)) answers[[k]] else NULL
    if (is.null(a)) character(0) else as.character(unlist(a$notes$unknown))
  })
  list(table = t, key = key, arg = arg, unknown = status %in% c("failed", "skipped"),
       partial = status %in% "incomplete", unknown_fields = unknown_fields,
       duplicates = sum(dup))
}

#' The declared level of each field, NA where none was declared.
#' @noRd
agreement_levels <- function(levels, nms) {
  ok <- c("nominal", "ordinal", "interval", "ratio")
  out <- stats::setNames(rep(NA_character_, length(nms)), nms)
  if (is.null(levels)) return(out)
  if (!is.character(levels) || anyNA(levels) || !all(levels %in% ok)) {
    gr_abort("`levels` must be \"nominal\", \"ordinal\", \"interval\" or \"ratio\".",
             class = "gr_bad_setting")
  }
  if (is.null(names(levels))) {
    if (length(levels) != 1L) {
      gr_abort("Name `levels` by field, or give one unnamed level for every field.",
               class = "gr_bad_setting")
    }
    out[] <- levels
    return(out)
  }
  extra <- setdiff(names(levels), nms)
  if (length(extra)) {
    gr_abort(sprintf("`levels` names field(s) not compared: %s.", paste(extra, collapse = ", ")),
             class = "gr_bad_setting")
  }
  out[names(levels)] <- levels
  out
}

#' The schema entry for a field, or one inferred from its two columns: a
#' number if either column is numeric, a boolean if either is logical, and
#' otherwise a string.
#' @noRd
agreement_field <- function(nm, schema, a, b) {
  if (!is.null(schema) && !is.null(schema[[nm]])) return(schema[[nm]])
  type <- if (is.numeric(a) || is.numeric(b)) "number"
          else if (is.logical(a) && !all(is.na(a)) || is.logical(b) && !all(is.na(b))) "boolean"
          else "string"
  list(type = type, values = NULL)
}

#' Read one column of one side into states, labels and values.
#'
#' `state` is "value", "not reported" or "unknown"; `label` is the text the
#' nominal comparison and `$pairs` use; `value` is what the ordinal, interval
#' or ratio comparison uses.
#' @noRd
agreement_cells <- function(col, field, level, unknown_row, partial_row, nm, unknown_fields) {
  n <- length(col)
  state <- character(n); label <- character(n); value <- vector("list", n)
  # Interval and ratio need numbers whatever the schema says the field holds.
  read_as <- if (level %in% c("interval", "ratio") && !field$type %in% c("integer", "number"))
    list(type = "number") else field
  for (i in seq_len(n)) {
    v <- if (is.list(col)) col[[i]] else col[i]
    if (isTRUE(unknown_row[i]) || nm %in% unknown_fields[[i]]) {
      state[i] <- "unknown"; label[i] <- NA_character_; next
    }
    got <- agreement_read(v, read_as)
    if (is.null(got)) {
      # A value that is there but cannot be read is not a document that is
      # silent, and neither is an empty cell of a document not read in full.
      absent <- !unreadable_value(list(v))
      state[i] <- if (absent && !isTRUE(partial_row[i])) "not reported" else "unknown"
      label[i] <- if (state[i] == "not reported") .gr_not_reported else NA_character_
      next
    }
    state[i] <- "value"
    label[i] <- if (is.numeric(got)) sprintf("%.15g", got)
                else if (is.logical(got)) as.character(got)
                else value_key(got, read_as$type)
    value[[i]] <- if (is.character(got)) label[i] else got
  }
  list(state = state, label = label, value = value)
}

#' One cell as the field's type, or NULL when it holds no readable value.
#' @noRd
agreement_read <- function(v, field) {
  if (is.null(v) || length(v) != 1L || is.na(v)) return(NULL)
  if (is.factor(v)) v <- as.character(v)
  if (is.character(v)) {
    if (!nzchar(trimws(v)) || is_one_of_words(v, .gr_unreported_words)) return(NULL)
    # "None" can be a string field's answer (no conflicts of interest), so only
    # the placeholders that never are one read as not reported there.
    if (identical(field$type, "string") && is_one_of_words(v, c("null", "na", "n/a"))) {
      return(NULL)
    }
  }
  if (identical(field$type, "enum")) {
    s <- trimws(as_chr1(v))
    hit <- field$values[tolower(field$values) == tolower(s)]
    return(if (length(hit)) hit[1] else NULL)
  }
  coerce_field(v, field)
}

#' Alpha and percent agreement for one part of one field.
#' @noRd
agreement_part <- function(a, b, level, B, conf, seed) {
  if (!length(a)) {
    return(list(n = 0L, po = NA_real_, alpha = NA_real_, lower = NA_real_, upper = NA_real_,
                note = "No document has a value from both tables."))
  }
  ag <- hr_agreement(coders = data.frame(x = a, y = b, stringsAsFactors = FALSE),
                     level = level, B = B, conf = conf, seed = seed)
  st <- ag$stats[ag$stats$statistic == "Krippendorff's alpha", ]
  list(n = ag$n, po = ag$po, alpha = ag$alpha, lower = st$lower, upper = st$upper,
       note = if (length(ag$notes)) paste(ag$notes, collapse = " ") else NA_character_)
}

#' @noRd
agreement_row <- function(nm, part, level, res, nr_x, nr_y, unknown) {
  data.frame(field = nm, part = part, level = level, n = as.integer(res$n),
             percent_agreement = res$po, alpha = res$alpha, lower = res$lower,
             upper = res$upper, not_reported_x = nr_x, not_reported_y = nr_y,
             unknown = unknown, note = res$note, stringsAsFactors = FALSE)
}

#' @export
print.gr_extract_agreement <- function(x, digits = 3, ...) {
  tab <- x$table
  cat(sprintf("<gr_extract_agreement> %d field(s), %d document(s) matched\n\n",
              length(unique(tab$field)), length(unique(x$pairs$document))))
  show <- tab[, c("field", "part", "level", "n", "percent_agreement", "alpha", "lower",
                  "upper", "not_reported_x", "not_reported_y", "unknown")]
  num <- vapply(show, is.double, logical(1))
  show[num] <- lapply(show[num], round, digits = digits)
  print(show, row.names = FALSE)
  cat(sprintf("\nAlpha intervals at %g%%; bootstrap over documents, B = %d, seed %s.\n",
              100 * x$conf, x$bootstrap$B, format(x$bootstrap$seed)))
  has <- !is.na(tab$note)
  for (i in which(has)) cat(sprintf("Note (%s, %s): %s\n", tab$field[i], tab$part[i], tab$note[i]))
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}
