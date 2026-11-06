# doc-ingest-cache.R: the cache of ingested documents.

#' Clear the session's document and embedding caches
#'
#' harnessr keeps two caches in memory for the life of the R session: the
#' documents [gr_ingest()] has already extracted and cleaned, keyed on the file
#' and every setting that changes the result, and the vectors the built-in
#' `"api"` embedder has already fetched (see [gr_embed()]). This empties them.
#' The next ingestion of a file reads and cleans it again, and the next ranking
#' sends its embeddings requests again, which are counted against `max_calls`
#' and `max_cost_usd` like any others.
#'
#' Each cache is bounded: when what it holds passes its budget (256 MB of
#' documents, 128 MB of vectors) the entries used least recently are dropped,
#' so a long session or a Shiny server does not need this to stay within
#' memory. It is for starting again from nothing: to give the memory back at
#' once, or to time or test a run as a fresh session would see it.
#'
#' Not to be confused with [gr_cache_clear()], which deletes the model
#' *responses* a [gr_cache()] keeps in a directory on disk. Neither touches
#' the other's cache: this leaves every stored response in place, and
#' [gr_cache_clear()] leaves every document and vector in memory.
#' `gr_options(cache_documents = FALSE, cache_embeddings = FALSE)` turns the
#' two memory caches off instead.
#'
#' @param what One or more of `"all"` (the default), `"documents"` and
#'   `"embeddings"`.
#' @return Invisibly, the caches cleared: `"documents"`, `"embeddings"` or both.
#' @seealso [gr_cache_clear()] for the on-disk response cache, [gr_options()]
#'   for `cache_documents` and `cache_embeddings`, [gr_ingest()], [gr_embed()]
#' @export
#' @examples
#' doc <- gr_ingest(gr_example())
#' gr_flush_caches("documents")
#' gr_flush_caches()
gr_flush_caches <- function(what = "all") {
  # Not gr_cache_clear(): while this was called that, it shadowed the exported
  # function of the name. R collates R/core-state.R after R/core-cache.R, so
  # this definition silently won and was exported under the other one's help.
  what <- match.arg(what, c("all", "documents", "embeddings"), several.ok = TRUE)
  if ("all" %in% what) what <- c("documents", "embeddings")
  if ("documents"  %in% what) gr_state$doc_cache   <- new.env(parent = emptyenv())
  if ("embeddings" %in% what) hr_state$embed_cache <- new.env(parent = emptyenv())
  invisible(what)
}

#' How much the session's document cache holds, in bytes, before the
#' documents used least recently are dropped from it.
#' @noRd
.gr_doc_cache_bytes <- 256 * 1024^2

#' The session's document cache, kept within .gr_doc_cache_bytes.
#'
#' It kept every document ingested under every setting for the life of the R
#' process, and a Shiny server that shows documents under several presets
#' only ever grew. A document is now dropped when the documents held come to
#' more than the budget and it is the one used least recently; the one just
#' stored always stays. Dropping one costs its extraction again, never a wrong
#' document: the key is unchanged. The order of use and the sizes are kept in
#' the cache itself, under names ls() does not list, so clearing the cache
#' clears them too.
#' @noRd
doc_cache_get <- function(key) {
  cache <- gr_state$doc_cache
  doc <- cache[[key]]
  if (!is.null(doc)) cache$.order <- c(setdiff(cache$.order, key), key)
  doc
}

#' @noRd
doc_cache_put <- function(key, doc, budget = .gr_doc_cache_bytes) {
  cache <- gr_state$doc_cache
  sizes <- cache$.sizes %||% numeric(0)
  sizes[[key]] <- as.numeric(utils::object.size(doc))
  cache[[key]] <- doc
  order <- c(setdiff(cache$.order %||% character(0), key), key)
  while (length(order) > 1L && sum(sizes[order], na.rm = TRUE) > budget) {
    if (exists(order[1L], envir = cache, inherits = FALSE)) rm(list = order[1L], envir = cache)
    sizes <- sizes[names(sizes) != order[1L]]
    order <- order[-1L]
  }
  cache$.order <- order
  cache$.sizes <- sizes
  invisible(NULL)
}
