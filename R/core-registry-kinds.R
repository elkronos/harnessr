# core-registry-kinds.R: the package's private state and its named registries.

gr_state <- new.env(parent = emptyenv())

gr_state$counter        <- 0L

gr_state$extractors     <- list()

gr_state$cleaners       <- list()

gr_state$segmenters     <- list()

gr_state$readers        <- list()

gr_state$embedders      <- list()

gr_state$protocols      <- list()

gr_state$models         <- list()

gr_state$model_patterns <- list()

gr_state$doc_cache      <- new.env(parent = emptyenv())

gr_state$embed_cache    <- new.env(parent = emptyenv())

gr_state$tokenizer      <- NULL

gr_state$client         <- NULL

#' Generic registry machinery.
#'
#' Every pluggable axis (extractors, cleaners, segmenters, readers) uses this,
#' so third-party additions behave exactly like built-ins.
#' @noRd
registry_set <- function(slot, name, entry) {
  if (!is_nonblank(name)) gr_abort("Registry name must be a non-empty string.")
  reg <- gr_state[[slot]]
  reg[[name]] <- entry
  gr_state[[slot]] <- reg
  invisible(name)
}

#' @noRd
registry_get <- function(slot, name, what = slot) {
  reg <- gr_state[[slot]]
  if (!is_nonblank(name) || is.null(reg[[name]])) {
    gr_abort(sprintf("Unknown %s '%s'. Registered: %s.",
                     sub("s$", "", what), as_chr1(name, "<missing>"),
                     paste(sort(names(reg)), collapse = ", ")),
             class = "gr_unknown_method")
  }
  reg[[name]]
}

#' @noRd
registry_table <- function(slot, cols) {
  reg <- gr_state[[slot]]
  if (!length(reg)) {
    empty <- as.data.frame(stats::setNames(
      rep(list(character(0)), length(cols) + 1L), c("name", cols)),
      stringsAsFactors = FALSE)
    return(empty)
  }
  rows <- lapply(names(reg), function(nm) {
    e <- reg[[nm]]
    vals <- lapply(cols, function(cl) as_chr1(e[[cl]], ""))
    stats::setNames(c(list(nm), vals), c("name", cols))
  })
  df <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  df <- df[order(df$name), , drop = FALSE]
  # Drop row names. rbind() over one-row frames keeps the registry key as a row
  # name, so every printed table showed the name twice -- once as a row label and
  # again in the `name` column.
  rownames(df) <- NULL
  df
}
