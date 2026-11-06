# core-registry-contract.R: the module contract, and the check that runs a
# module and says which of its rules the module breaks.
#
# A layer above the core writes the rules for its own kinds of module (what a
# reader must return, what a segmenter must not do) and hands them to
# hr_check_module() with a closure that runs the module once. The core knows
# nothing about any kind: it runs the closure, keeps what went wrong, and asks
# each rule about what came back.

#' The version of the module contract this core implements.
#'
#' Frozen while the contract is being written: a module checked against it
#' later can say which version it was written for.
#' @noRd
hr_contract_version <- function() "0.1"

#' Check a module against a set of rules
#'
#' Runs a module once and reports which of a list of rules it breaks. It is a
#' report and nothing more: registering a module does not run it, and a
#' module that breaks a rule is still registered and still runs.
#' [gr_check_reader()] and [gr_check_segmenter()] use it with the rules for
#' readers and segmenters.
#'
#' `run()` is called with no arguments inside a temporary working directory,
#' which is removed afterwards, so a module that writes files leaves nothing
#' behind. An error it raises is caught and reported by the `runs` rule; its
#' warnings are caught too, kept in the `warnings` attribute and not shown.
#'
#' Each rule is a function of one argument, the value `run()` returned. It
#' returns `TRUE` when the module passes, `FALSE` when it breaks the rule, and
#' `NA` when the rule could not be checked on this run, or a list with `ok`
#' (one of those three) and `detail` (one string saying why). A rule that
#' raises an error is reported as broken, with the error as its detail. When
#' `run()` fails, no rule is asked and each is reported as `NA`.
#'
#' @param fn The module's function. The `is_function` rule checks that it is
#'   one.
#' @param run A function of no arguments that calls the module once and
#'   returns what the rules are to check.
#' @param rules A named list of rule functions, checked in order.
#' @param kind The kind of module, such as `"reader"`, for the report.
#' @param name The module's name, for the report.
#' @return An object of class `hr_conformance`: a data frame with one row per
#'   rule and the columns `rule`, `ok` (logical, `NA` for a rule that was not
#'   checked) and `detail` (character, `""` when there is nothing to say). Its
#'   attributes are `kind`, `name`, `contract` (the contract version it was
#'   checked against) and `warnings` (the messages of the warnings the run
#'   raised). The first two rows are always `is_function` and `runs`.
#'   `print()` lists the broken rules first.
#' @seealso [gr_check_reader()], [gr_check_segmenter()]
#' @export
#' @examples
#' double_it <- function(x) x * 2
#' hr_check_module(double_it, function() double_it(2),
#'   rules = list(numeric = function(v) is.numeric(v),
#'                above_three = function(v) list(ok = v > 3, detail = sprintf("got %s", v))),
#'   kind = "function", name = "double_it")
hr_check_module <- function(fn, run, rules = list(), kind = "module", name = NA_character_) {
  if (!is.function(run)) gr_abort("`run` must be a function of no arguments.",
                                  class = "gr_bad_setting")
  if (!is.list(rules) || (length(rules) && (is.null(names(rules)) ||
                                            !all(has_visible(names(rules)))))) {
    gr_abort("`rules` must be a named list of functions.", class = "gr_bad_setting")
  }
  if (!all(vapply(rules, is.function, logical(1)))) {
    gr_abort("Every element of `rules` must be a function of one argument.",
             class = "gr_bad_setting")
  }
  out <- contract_run(run)
  rows <- list(
    list(rule = "is_function", ok = is.function(fn),
         detail = if (is.function(fn)) "" else sprintf("got an object of class %s",
                                                       paste(class(fn), collapse = "/"))),
    list(rule = "runs", ok = is.null(out$error),
         detail = if (is.null(out$error)) "" else as_chr1(conditionMessage(out$error), "")))
  for (nm in names(rules)) {
    rows[[length(rows) + 1L]] <- if (!is.null(out$error)) {
      list(rule = nm, ok = NA, detail = "not checked: the module did not run")
    } else {
      c(list(rule = nm), contract_rule(rules[[nm]], out$value))
    }
  }
  df <- data.frame(rule = vapply(rows, function(r) r$rule, character(1)),
                   ok = vapply(rows, function(r) r$ok, logical(1)),
                   detail = vapply(rows, function(r) r$detail, character(1)),
                   stringsAsFactors = FALSE)
  structure(df, class = c("hr_conformance", "data.frame"),
            kind = as_chr1(kind, "module"), name = as_chr1(name, NA_character_),
            contract = hr_contract_version(), warnings = out$warnings)
}

#' Run a module's closure in a temporary working directory, keeping its value,
#' the error that stopped it, if any, and the messages of its warnings.
#' @noRd
contract_run <- function(run) {
  dir <- tempfile("hr-check-")
  dir.create(dir)
  old <- setwd(dir)
  on.exit({
    setwd(old)
    unlink(dir, recursive = TRUE)
  }, add = TRUE)
  warns <- character(0)
  err <- NULL
  value <- tryCatch(withCallingHandlers(run(), warning = function(w) {
    warns <<- c(warns, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    err <<- e
    NULL
  })
  list(value = value, error = err, warnings = warns)
}

#' Ask one rule about a module's value, and put its answer in the form a row
#' of the report takes: `ok` one logical, `detail` one string.
#' @noRd
contract_rule <- function(rule, value) {
  got <- tryCatch(rule(value), error = function(e) {
    list(ok = FALSE, detail = paste("the rule failed:", conditionMessage(e)))
  })
  if (is.list(got)) {
    ok <- got[["ok", exact = TRUE]]
    detail <- as_chr1(got[["detail", exact = TRUE]], "")
  } else {
    ok <- got
    detail <- ""
  }
  if (!is.logical(ok) || length(ok) != 1L) {
    return(list(ok = FALSE, detail = "the rule did not return TRUE, FALSE or NA"))
  }
  if (is.na(ok) && !nzchar(detail)) detail <- "not checked"
  list(ok = ok, detail = detail)
}

#' @export
print.hr_conformance <- function(x, ...) {
  name <- attr(x, "name")
  cat(sprintf("<hr_conformance> %s%s, contract %s\n", attr(x, "kind") %||% "module",
              if (is.null(name) || is.na(name)) "" else sprintf(" '%s'", name),
              attr(x, "contract") %||% "?"))
  ok <- x$ok
  n <- length(ok)
  failed <- which(!is.na(ok) & !ok)
  skipped <- which(is.na(ok))
  passed <- which(!is.na(ok) & ok)
  if (!length(failed) && !length(skipped)) {
    cat(sprintf("  passes all %d rules\n", n))
  } else if (!length(failed)) {
    cat(sprintf("  passes all %d rules checked; %d not checked\n", length(passed),
                length(skipped)))
  } else {
    cat(sprintf("  fails %d of %d rules\n", length(failed), n))
  }
  line <- function(i, tag) {
    cat(sprintf("  %-5s %s%s\n", tag, x$rule[i],
                if (nzchar(x$detail[i])) paste0(": ", x$detail[i]) else ""))
  }
  for (i in failed) line(i, "FAIL")
  for (i in skipped) line(i, "skip")
  for (i in passed) line(i, "ok")
  warns <- attr(x, "warnings") %||% character(0)
  if (length(warns)) cat(sprintf("  %d warning(s) raised while it ran\n", length(warns)))
  invisible(x)
}
