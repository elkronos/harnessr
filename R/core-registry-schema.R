# core-registry-schema.R: specs turned into plain lists of settings.

#' Normalise a list of named specs coming from a user (recipe fields).
#' @noRd
as_spec_list <- function(x, what = "spec") {
  if (is.null(x)) return(list())
  if (is.character(x) && length(x) == 1L) return(list(method = x))
  if (!is.list(x)) gr_abort(sprintf("`%s` must be a string or a named list, got <%s>.", what, class(x)[1]))
  x
}

# NOTE: there is deliberately no `str()` shim here. Defining one would shadow
# `utils::str` for every function in this package to save one qualified call in
# `gr_hash()`, which calls `utils::str()` directly instead.


#' The settings of a spec that differ from its defaults.
#'
#' A trace used to record the recipe's NAME and nothing else about how it was
#' configured, so two runs of `"thorough"` with `top_k = 3` and `top_k = 8`
#' produced traces -- and a `gr_compare()` summary -- that could not be told
#' apart. For a package whose point is comparing configurations, the
#' configuration has to be in the record. This returns only what was changed
#' from the defaults, so the record says what the run DID rather than restating
#' thirty defaults; `format_settings()` makes it one readable string.
#'
#' Defaults are taken from the constructor at the time of the call, so a
#' `model` or `parallel` that merely follows `gr_options()` is not reported as
#' a setting.
#' @noRd
spec_settings <- function(spec, defaults, drop = character(0)) {
  same <- function(a, b) isTRUE(all.equal(a, b, check.attributes = FALSE))
  out <- list()
  for (nm in setdiff(names(spec), drop)) {
    v <- spec[[nm]]
    if (is.null(v) || is.function(v) || is.environment(v)) next
    if (nm %in% names(defaults) && same(v, defaults[[nm]])) next
    out[[nm]] <- v
  }
  out
}

#' @noRd
read_settings <- function(spec) {
  spec_settings(spec, suppressWarnings(gr_read_spec(reader = spec$reader)), drop = "reader")
}

#' @noRd
segment_settings <- function(spec) {
  spec_settings(spec, suppressWarnings(gr_segment_spec(method = spec$method)), drop = "method")
}

#' One line, for a summary column: `top_k=3, mmr=0.7`.
#' @noRd
format_settings <- function(x) {
  if (!length(x)) return("")
  paste(vapply(names(x), function(nm) {
    v <- x[[nm]]
    # A named vector keeps its names: an effort map printed as "low+high"
    # would not say which stage ran at which.
    val <- if (is.character(v) && !is.null(names(v)) && any(nzchar(names(v))))
             paste(ifelse(nzchar(names(v)), paste0(names(v), ":", v), v), collapse = "+")
           else if (is.character(v)) paste(v, collapse = "+")
           else if (is.logical(v) || is.numeric(v)) paste(format(v, trim = TRUE), collapse = "+")
           else class(v)[1]
    paste0(nm, "=", val)
  }, character(1)), collapse = ", ")
}
