# compat-deprecate.R: warn once per session about a deprecated name, and read
# options under their old names.

.warn_once <- local({
  seen <- character(0)
  function(id, msg) {
    if (id %in% seen) return(invisible(NULL))
    # Emit FIRST, mark second. Marking first meant that a handler which turned
    # the warning into an error -- options(warn = 2), or a tryCatch(warning=)
    # that aborts -- consumed the one and only notice: the user saw a failure,
    # fixed their handler, ran again, and got no deprecation warning at all.
    gr_warn(msg, class = "gr_deprecated")
    seen <<- c(seen, id)
    invisible(NULL)
  }
})

#' An option under its harnessr name, or else under the readgpt name it had
#' before the package was renamed.
#'
#' Scripts written for readgpt set `readgpt.api_key` and
#' `readgpt.allow_local_urls`. Those still work, with one warning per session
#' naming the new option, so a key set the old way is not silently ignored.
#' The new name wins when both are set.
#' @noRd
renamed_option <- function(new, old, default = NULL) {
  v <- getOption(new)
  if (!is.null(v)) return(v)
  v <- getOption(old)
  if (is.null(v)) return(default)
  .warn_once(paste0("option:", old), sprintf(
    "options(%s =) is deprecated; the package is now harnessr, so set options(%s =) instead.",
    old, new))
  v
}

#' Forget which deprecation warnings have been emitted.
#'
#' Session state that persists across `test_that()` blocks makes a test suite
#' order-dependent: whichever test runs first sees the warning and the rest do
#' not. Tests call this in `setup`/`on.exit` so each one starts clean.
#' @noRd
.warn_once_reset <- function() {
  environment(.warn_once)$seen <- character(0)
  invisible(NULL)
}
