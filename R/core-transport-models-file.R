# core-transport-models-file.R: model registry files and registry entries.
#
# WHY THIS FILE EXISTS
# The built-in models used to be written out in R, prices included, and a
# price could only be corrected by a package release. harnessr now ships each
# built-in model's limits in inst/extdata/models.csv and no prices: providers
# change prices more often than the package is released, so the user sets
# them, one model at a time with hr_register_model() or many at once with
# hr_load_models(). Both build their entries with model_entry(), so a row of
# a file and a call to hr_register_model() with the same values register the
# same entry.
#
# A file is checked in full before anything is registered, so a bad row
# leaves the registry as it was. The shipped file is checked more strictly
# and fails loudly: an unreadable or empty built-in file stops the package
# from loading, because an empty registry would put every model on the
# conservative fallback limits without a word.

# The columns a models file may have, and the type of each.
models_file_columns <- c(
  id = "string", context_window = "count", max_output = "count",
  input_usd = "price", output_usd = "price", cached_input_usd = "price",
  reasoning = "flag", supports_temperature = "flag", kind = "kind",
  dimensions = "count", as_of = "month"
)

# The columns of the shipped file, all required, in the order of the entries
# it builds. It has no price columns.
models_file_seed_columns <- c("id", "context_window", "max_output", "reasoning",
                              "supports_temperature", "kind", "dimensions", "as_of")

#' Stop on a malformed models file, naming the row and column.
#'
#' `row` is the data row (the header is row 0) and `column` a column name, or
#' NA for a problem with the file as a whole. The condition carries `file`,
#' `row` and `column` so a caller can read them without parsing the message.
#' @noRd
models_file_abort <- function(file, row, column, problem, shipped = FALSE) {
  where <- if (!is.na(row) && !is.na(column)) {
    sprintf("row %d, column '%s'", row, column)
  } else if (!is.na(column)) {
    sprintf("column '%s'", column)
  } else if (!is.na(row)) {
    sprintf("row %d", row)
  } else {
    NULL
  }
  head <- if (shipped) {
    sprintf("harnessr's built-in model file '%s' is malformed; reinstall harnessr", file)
  } else {
    sprintf("Models file '%s'", file)
  }
  msg <- paste0(head, if (!is.null(where)) paste0(", ", where), ": ", problem)
  gr_abort(msg, class = "hr_bad_models_file", file = file, row = row, column = column)
}

#' Convert one column of a models file from text to its type.
#'
#' Blank cells (and "NA") are NA: not given. A cell that cannot be read as
#' its column's type stops with the row and column named.
#' @noRd
models_file_cells <- function(x, column, type, fail) {
  n <- length(x)
  blank <- is.na(x) | !nzchar(trimws(x))
  x <- trimws(x)
  bad <- function(i, what) fail(i, column, sprintf("'%s' is not %s.", x[i], what))
  switch(type,
    string = {
      out <- ifelse(blank, NA_character_, x)
      out
    },
    count = {
      v <- suppressWarnings(as.numeric(x))
      for (i in which(!blank)) {
        if (is.na(v[i]) || !is.finite(v[i]) || v[i] < 0 || v[i] != round(v[i]) ||
            v[i] > .Machine$integer.max) {
          bad(i, "a whole number of tokens of 0 or more")
        }
      }
      out <- rep(NA_integer_, n)
      out[!blank] <- as.integer(v[!blank])
      out
    },
    price = {
      v <- suppressWarnings(as.numeric(x))
      for (i in which(!blank)) {
        if (is.na(v[i]) || !is.finite(v[i]) || v[i] < 0) {
          bad(i, "a price; give USD per 1M tokens as a number of 0 or more, such as 2.5")
        }
      }
      v[blank] <- NA_real_
      v
    },
    flag = {
      up <- toupper(x)
      out <- rep(NA, n)
      for (i in which(!blank)) {
        if (!up[i] %in% c("TRUE", "FALSE")) bad(i, "TRUE or FALSE")
        out[i] <- identical(up[i], "TRUE")
      }
      out
    },
    kind = {
      for (i in which(!blank)) {
        if (!x[i] %in% c("chat", "embedding")) bad(i, "a kind; use chat or embedding")
      }
      ifelse(blank, NA_character_, x)
    },
    month = {
      for (i in which(!blank)) {
        if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", x[i])) {
          bad(i, "a month; write it as YYYY-MM, such as 2026-11")
        }
      }
      ifelse(blank, NA_character_, x)
    }
  )
}

#' Read and check a models file.
#'
#' Returns a list: `n` (rows), `columns` (the column names, in file order) and
#' `cells` (one typed vector per column, NA where the cell is blank). Checks
#' the shape of the file, every cell's type and that ids are unique. With
#' `shipped = TRUE` it also checks the rules of the built-in file: exactly
#' its columns, no prices, and no blank cell but an empty `dimensions` for a
#' chat model.
#' @noRd
models_file_read <- function(file, shipped = FALSE) {
  if (!is_nonblank(file)) {
    gr_abort("`file` must be the path to a CSV file of models.", class = "hr_bad_models_file",
             file = NA_character_, row = NA_integer_, column = NA_character_)
  }
  fail <- function(row, column, problem) {
    models_file_abort(file, row, column, problem, shipped = shipped)
  }
  if (!file.exists(file) || dir.exists(file)) fail(NA_integer_, NA_character_, "no such file.")
  # Count the fields of every line first. read.csv() fills a short row with
  # blanks and wraps a long one onto a new row, so a missing or extra comma
  # would shift values into the wrong columns without an error.
  fields <- tryCatch(
    utils::count.fields(file, sep = ",", quote = "\"", blank.lines.skip = TRUE,
                        comment.char = ""),
    error = function(e) fail(NA_integer_, NA_character_,
                             paste0("could not be read: ", conditionMessage(e)))
  )
  if (!length(fields)) fail(NA_integer_, NA_character_, "the file is empty.")
  if (anyNA(fields)) {
    fail(which(is.na(fields))[1] - 1L, NA_character_, "a quoted value is not closed.")
  }
  uneven <- which(fields != fields[1])
  if (length(uneven)) {
    fail(uneven[1] - 1L, NA_character_,
         sprintf("it has %d values, and the header has %d columns.",
                 fields[uneven[1]], fields[1]))
  }
  raw <- tryCatch(
    utils::read.csv(file, colClasses = "character", na.strings = c("", "NA"),
                    check.names = FALSE, strip.white = TRUE, fill = FALSE,
                    comment.char = "", encoding = "UTF-8", stringsAsFactors = FALSE),
    error = function(e) fail(NA_integer_, NA_character_,
                             paste0("could not be read: ", conditionMessage(e)))
  )
  columns <- trimws(names(raw))
  unknown <- setdiff(columns, names(models_file_columns))
  if (length(unknown)) {
    fail(0L, unknown[1], sprintf("not a column a models file can have. The columns are: %s.",
                                 paste(names(models_file_columns), collapse = ", ")))
  }
  twice <- columns[duplicated(columns)]
  if (length(twice)) fail(0L, twice[1], "the column appears twice.")
  if (!"id" %in% columns) fail(0L, "id", "the file has no id column.")
  if (shipped) {
    priced <- intersect(columns, c("input_usd", "output_usd", "cached_input_usd"))
    if (length(priced)) fail(0L, priced[1], "the built-in file carries no prices.")
    absent <- setdiff(models_file_seed_columns, columns)
    if (length(absent)) fail(0L, absent[1], "the column is missing.")
  }
  n <- nrow(raw)
  if (!n) fail(NA_integer_, NA_character_, "the file has a header but no rows.")
  cells <- stats::setNames(lapply(seq_along(columns), function(j) {
    models_file_cells(raw[[j]], columns[j], models_file_columns[[columns[j]]], fail)
  }), columns)
  for (i in which(is.na(cells$id))) fail(i, "id", "the id is blank.")
  dup <- which(duplicated(cells$id))
  if (length(dup)) {
    fail(dup[1], "id", sprintf("'%s' is on row %d already.", cells$id[dup[1]],
                               match(cells$id[dup[1]], cells$id)))
  }
  if (shipped) {
    for (col in setdiff(models_file_seed_columns, "dimensions")) {
      for (i in which(is.na(cells[[col]]))) fail(i, col, "the cell is blank.")
    }
    for (i in which(cells$kind == "embedding" & is.na(cells$dimensions))) {
      fail(i, "dimensions", "an embedding model needs its dimensions.")
    }
    for (i in which(cells$context_window <= 0L)) {
      fail(i, "context_window", "the context window must be above 0.")
    }
  }
  list(n = n, columns = columns, cells = cells)
}

#' The built-in models, from the shipped file.
#'
#' A named list of entries with the fields and order the entries had when they
#' were written in R: `id`, `context_window`, `max_output`, `input_usd` and
#' `output_usd` (both NA: harnessr ships no prices), `reasoning`,
#' `supports_temperature`, `kind`, `dimensions` and `as_of`.
#' @noRd
models_file_seed <- function(file) {
  if (!is_nonblank(file)) {
    gr_abort("harnessr's built-in model file (inst/extdata/models.csv) was not found; reinstall harnessr.",
             class = "hr_bad_models_file", file = NA_character_, row = NA_integer_,
             column = NA_character_)
  }
  f <- models_file_read(file, shipped = TRUE)
  cl <- f$cells
  out <- lapply(seq_len(f$n), function(i) {
    list(id = cl$id[i], context_window = cl$context_window[i], max_output = cl$max_output[i],
         input_usd = NA_real_, output_usd = NA_real_, reasoning = cl$reasoning[i],
         supports_temperature = cl$supports_temperature[i], kind = cl$kind[i],
         dimensions = cl$dimensions[i], as_of = cl$as_of[i])
  })
  stats::setNames(out, cl$id)
}

#' Build a registry entry for `id` from the values given.
#'
#' `given` is a named list holding only the arguments the caller gave. With
#' both `context_window` and `max_output` in it, the entry is built in full and
#' every value left out takes hr_register_model()'s default. Without both, the
#' entry starts from the model's current one (registered first, then built
#' in) and changes only what is given; a model with no entry is an error.
#' `as_of` is NULL to stamp the current month, except that an entry whose
#' prices are kept from a priced entry keeps that entry's month, so a price's
#' age stays visible. Errors carry a `column` naming the field at fault.
#' @noRd
model_entry <- function(id, given, as_of = NULL) {
  has <- function(nm) nm %in% names(given)
  full <- has("context_window") && has("max_output")
  base <- NULL
  if (!full) {
    base <- hr_state$models[[id]] %||% hr_state$seed_models[[id]]
    if (is.null(base)) {
      miss <- if (has("context_window")) "max_output" else "context_window"
      gr_abort(sprintf(paste0(
        "Model '%s' is not in the registry, so it has no limits to keep: give both ",
        "`context_window` and `max_output` to register it."), id),
        class = "gr_bad_setting", column = miss)
    }
  }
  defaults <- list(input_usd = NA_real_, output_usd = NA_real_, reasoning = FALSE,
                   supports_temperature = TRUE, kind = "chat", dimensions = NA_integer_,
                   cached_input_usd = NA_real_)
  pick <- function(nm) {
    if (has(nm)) return(given[[nm]])
    if (!is.null(base) && !is.null(base[[nm]])) return(base[[nm]])
    defaults[[nm]]
  }
  kind <- as_chr1(pick("kind"), NA_character_)
  if (!kind %in% c("chat", "embedding")) {
    gr_abort("`kind` must be \"chat\" or \"embedding\".", class = "gr_bad_setting",
             column = "kind")
  }
  context_window <- as_int1(pick("context_window"))
  max_output <- as_int1(pick("max_output"))
  if (is.na(context_window) || context_window <= 0L) {
    gr_abort("`context_window` must be a positive integer.", column = "context_window")
  }
  if (is.na(max_output) || max_output < 0L) {
    gr_abort("`max_output` must be >= 0.", column = "max_output")
  }
  input_usd <- as_num1(pick("input_usd"))
  output_usd <- as_num1(pick("output_usd"))
  # Half a price is refused here, where the omission is made, rather than
  # discovered later as a cost that cannot be computed. Pricing the missing
  # half as free is what this used to do: output_usd left out costed a run's
  # replies at $0 and a max_cost_usd limit never tripped.
  if (kind == "chat" && xor(is.na(input_usd), is.na(output_usd))) {
    gr_abort(sprintf(paste0("Model '%s' has %s but no %s. Give both prices (USD per 1M tokens), ",
                            "or neither to register it unpriced, in which case harnessr reports ",
                            "the cost as unknown rather than guessing."),
                     id, if (is.na(input_usd)) "`output_usd`" else "`input_usd`",
                     if (is.na(input_usd)) "`input_usd`" else "`output_usd`"),
             class = "gr_bad_setting",
             column = if (is.na(input_usd)) "input_usd" else "output_usd")
  }
  # Checked only when a limit is given: a built-in entry's limits are kept as
  # they are, and gpt-4 lists its 8192-token output cap as equal to its window.
  if ((has("context_window") || has("max_output")) && max_output >= context_window &&
      kind == "chat") {
    gr_abort(sprintf(paste0("`max_output` (%d) must be smaller than `context_window` (%d): a model ",
                            "cannot emit its entire context. This exact inversion is what made the ",
                            "previous implementation compute negative input budgets."),
                     max_output, context_window), column = "max_output")
  }
  if (is.null(as_of)) {
    priced_base <- !is.null(base) && !is.na(as_num1(base$input_usd))
    prices_given <- any(c("input_usd", "output_usd", "cached_input_usd") %in% names(given))
    as_of <- if (priced_base && !prices_given) {
      as_chr1(base$as_of, format(Sys.Date(), "%Y-%m"))
    } else {
      format(Sys.Date(), "%Y-%m")
    }
  }
  # Every field below becomes a column in hr_models(). NULL or a zero-length
  # value here does not store "unknown": modifyList() deletes the key and
  # data.frame() drops the column, so one such registration made hr_models()
  # fail for the whole session. Coerce to a scalar, or to NA.
  list(
    id = id, context_window = context_window, max_output = max_output,
    input_usd = input_usd, output_usd = output_usd,
    reasoning = isTRUE(pick("reasoning")),
    supports_temperature = isTRUE(pick("supports_temperature")), kind = kind,
    dimensions = as_int1(pick("dimensions")), certain = TRUE, as_of = as_of,
    cached_input_usd = as_num1(pick("cached_input_usd"))
  )
}

#' Register models from a CSV file
#'
#' Reads a file of models and registers each row as [hr_register_model()]
#' would. Use it to set the prices of many models at once: harnessr ships each
#' built-in model's limits but no prices, because providers change prices more
#' often than the package is released.
#'
#' @section File format:
#' A CSV file with a header row and one row per model. Only `id` is required;
#' a blank cell, or `NA`, means the value is not given.
#'
#' \describe{
#'   \item{`id`}{The model id, exactly as the API expects it. Each id may
#'     appear once.}
#'   \item{`input_usd`, `output_usd`}{Price per 1M tokens, in USD. Give both
#'     for a chat model, or neither. An embedding model needs only
#'     `input_usd`.}
#'   \item{`cached_input_usd`}{Price per 1M input tokens served from the
#'     provider's prompt cache. Blank prices them as other input tokens.}
#'   \item{`as_of`}{The month the prices were checked, as `YYYY-MM`. Blank
#'     stamps the current month. A cost computed from prices older than
#'     `hr_options("price_max_age_days")` warns with class
#'     `hr_stale_price`, once per model per session.}
#'   \item{`context_window`, `max_output`}{Limits in tokens.}
#'   \item{`reasoning`, `supports_temperature`}{`TRUE` or `FALSE`.}
#'   \item{`kind`}{`chat` or `embedding`.}
#'   \item{`dimensions`}{Embedding dimensions, for an embedding model.}
#' }
#'
#' A row that gives both `context_window` and `max_output` registers the
#' model in full, and a blank column takes [hr_register_model()]'s default.
#' A row that leaves either limit blank changes the model's current entry,
#' built in or registered, and keeps every value the row leaves blank. So a
#' row with only `id`, `input_usd` and `output_usd` prices a built-in model
#' and keeps its limits:
#'
#' \preformatted{
#' id,input_usd,output_usd,as_of
#' gpt-4o,2.50,10.00,2026-11
#' my-local-llama,0,0,2026-11
#' }
#'
#' The second row works only if `my-local-llama` is already registered.
#'
#' harnessr checks the whole file before it registers anything. A file it
#' cannot use stops with an error of class `hr_bad_models_file` that names the
#' row and column at fault (row 1 is the first row after the header) and
#' carries them as the condition's `row` and `column` fields; the registry is
#' then left as it was.
#'
#' @param file Path to the CSV file.
#' @return Invisibly, the ids registered, in file order.
#' @seealso [hr_register_model()] for one model, [hr_models()] to check the
#'   result, [hr_estimate_cost()]
#' @family cost and token functions
#' @export
#' @examples
#' # The prices here are illustrative: use your provider's current prices.
#' prices <- tempfile(fileext = ".csv")
#' writeLines(c("id,input_usd,output_usd,as_of",
#'              "gpt-4o,2.50,10.00,2026-11",
#'              "gpt-4o-mini,0.15,0.60,2026-11"), prices)
#' hr_load_models(prices)
#' m <- hr_models()
#' m[m$id %in% c("gpt-4o", "gpt-4o-mini"),
#'   c("id", "context_window", "input_usd_per_1m", "output_usd_per_1m", "as_of")]
#'
#' # A malformed file names the row and column, and registers nothing.
#' writeLines(c("id,input_usd,output_usd", "gpt-4o,two,10"), prices)
#' tryCatch(hr_load_models(prices), hr_bad_models_file = conditionMessage)
#' unlink(prices)
hr_load_models <- function(file) {
  f <- models_file_read(file)
  cl <- f$cells
  fields <- setdiff(f$columns, c("id", "as_of"))
  entries <- lapply(seq_len(f$n), function(i) {
    given <- list()
    for (nm in fields) if (!is.na(cl[[nm]][i])) given[[nm]] <- cl[[nm]][i]
    as_of <- if ("as_of" %in% f$columns && !is.na(cl$as_of[i])) cl$as_of[i]
    tryCatch(model_entry(cl$id[i], given, as_of = as_of),
             gr_error = function(e) {
               models_file_abort(file, i, as_chr1(e$column, "id"), conditionMessage(e))
             })
  })
  for (e in entries) registry_set("models", e$id, e, state = hr_state)
  invisible(cl$id)
}
