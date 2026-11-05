# doc-corpus-store.R: per-document results saved to disk and read back.

#' Identity of one (document, question, pipeline, model) job.
#'
#' A file is identified by path, size and a hash of its bytes, so an edited
#' document is a new job rather than a stale hit. Anything that is not an
#' existing file is identified by its own text.
#' @noRd
corpus_key <- function(src, question, rec, client) {
  ident <- if (is.character(src) && length(src) == 1L && !is.na(src) &&
               nchar(src, type = "bytes") < 1000L && file.exists(src)) {
    info <- file.info(src)
    # The bytes, not the mtime. format(mtime) is local-time text to the second:
    # resumed in another time zone (cron in UTC, a server, a colleague) every
    # entry missed and every document was paid for again, and a file rewritten
    # within the same second at the same size came back "restored" with the
    # answer to its old text. A hash is the same wherever and whenever the
    # file is read, and changes whenever the file does, on a filesystem that
    # keeps mtime to the second as on any other.
    list("file", normalizePath(src, winslash = "/", mustWork = FALSE),
         info$size, unname(tools::md5sum(src)))
  } else {
    list("text", key_text(as.character(src)))
  }
  # The embedder the readers and the semantic segmenter would use. They call
  # gr_embed() without naming one, so it comes from gr_options(embedder =) or the
  # client. An unregistered name is an error for the run to raise, not the key.
  embedder <- tryCatch(as_chr1(resolve_embedder(client)$name, "?"),
                       error = function(e) as_chr1(gr_options("embedder"), "?"))
  # v3: the client's extra_body and the embedding configuration joined the key.
  # v4: a file is identified by its content rather than its mtime.
  gr_hash(list("readgpt-corpus-v4", ident, key_text(question),
               # The tokenizer, because it is what turns `max_tokens = 300` into
               # an actual chunk boundary: the same document under "chars" and
               # under "words" segments differently and is answered differently.
               # Without it the store handed back an answer built from a
               # segmentation this run would never have produced.
               as_chr1(gr_options("tokenizer"), "?"),
               unclass(rec$ingest), unclass(rec$segment), unclass(rec$read),
               as_chr1(client$model, "?"), as_chr1(client$api, "?"),
               as_chr1(client$base_url, "?"),
               # As in cache_key(): for a closure-backed client the transport
               # fields are identical constants, so without this a store restored
               # one client's answers for a different client's run.
               as_chr1(client$.client_id, "<url-addressed>"),
               # Also as in cache_key(): extra_body goes into every request
               # (reasoning effort, seed, provider routing) and changes the reply.
               # Without it a rerun at a higher effort restored the low-effort
               # answers, made no calls, and compared a run with itself.
               gr_hash(client$extra_body %||% list()),
               # What ranks the chunks for the embedding readers and places the
               # semantic segmenter's cuts: another model or embedder is another
               # set of chunks in front of the model.
               as_chr1(client$embedding_model, "?"), embedder))
}

#' The `duplicate_of` a store entry without a hash was saved with, when it
#' names a row earlier in this run; NA otherwise.
#'
#' Without a hash nothing says whether its first copy is still the same text,
#' so a label that is not in this run is dropped rather than left naming a row
#' that does not exist.
#' @noRd
corpus_stored_duplicate <- function(stored, earlier) {
  d <- as_chr1(stored, NA_character_)
  if (!is.na(d) && d %in% earlier) d else NA_character_
}

#' @noRd
corpus_store_path <- function(store, key) file.path(store, paste0(key, ".rds"))

#' A store entry, or NULL when there is none that can be trusted.
#'
#' A store is a directory, and a directory gets shared, synced, and unpacked
#' from somebody else's archive. `readRDS()` rebuilds any R object: an
#' environment whose active bindings run code the moment a field is read, or
#' anything at all carrying a class attribute, which is all `inherits()` and
#' `is.data.frame()` look at. Checking the shape and then using the object
#' therefore ran whatever the file's author chose, in this session. So nothing
#' in an entry is read until all of it is known to be plain data, and the row
#' and the answer are rebuilt from it, not used as they came. Anything else is
#' a miss and the document is read again, which is always safe.
#' @noRd
corpus_restore <- function(store, key) {
  path <- corpus_store_path(store, key)
  if (!file.exists(path)) return(NULL)
  entry <- tryCatch(readRDS(path), error = function(e) NULL, warning = function(w) NULL)
  tryCatch(corpus_entry(entry), error = function(e) NULL, warning = function(w) NULL)
}

#' @noRd
corpus_entry <- function(entry) {
  if (!identical(typeof(entry), "list") || isS4(entry)) return(NULL)
  # .subset2() and unclass() throughout: `$` and `[[` dispatch on the class
  # attribute, which the file chose.
  entry <- unclass(entry)
  fmt <- .subset2(entry, "format")
  if (!identical(fmt, 1L) && !identical(fmt, 2L)) return(NULL)
  ans <- .subset2(entry, "answer")
  if (!is.null(ans)) {
    if (!identical(typeof(ans), "list") || isS4(ans) || !inherits(ans, "gr_answer")) return(NULL)
    ans <- unclass(ans)
    # Format 1 saved the answer's trace as the environment it is in memory.
    # Such an entry is read binding by binding in a way that cannot run
    # anything, and refused otherwise. 0.5.0 wrote format 1 under the older
    # store key, which corpus_key() no longer produces, so its entries are read
    # again once rather than reaching this; the path serves entries at the
    # current key, a planted one included.
    if (identical(fmt, 1L) && is.environment(.subset2(ans, "trace"))) {
      tr <- corpus_trace_bindings(.subset2(ans, "trace"))
      if (is.null(tr)) return(NULL)
      ans[["trace"]] <- tr
    }
    entry[["answer"]] <- ans
  }
  if (!corpus_is_plain(entry)) return(NULL)

  row <- .subset2(entry, "row")
  if (!is.data.frame(row)) return(NULL)
  cols <- unclass(row)
  nm <- names(cols)
  if (!length(cols) || is.null(nm) || !all(nzchar(nm)) || anyDuplicated(nm) ||
      !all(vapply(cols, function(v) is.atomic(v) && length(v) == 1L, logical(1)))) {
    return(NULL)
  }
  row <- structure(lapply(seq_along(cols), function(i) .subset2(cols, i)), names = nm,
                   row.names = c(NA_integer_, -1L), class = "data.frame")
  if (!is.null(ans)) {
    ans <- .subset2(entry, "answer")
    ans["trace"] <- list(corpus_trace_rebuild(.subset2(ans, "trace")))
    class(ans) <- "gr_answer"
  }
  h <- .subset2(entry, "doc_hash")
  if (!is.character(h) || length(h) != 1L || is.na(h)) h <- NULL
  list(format = fmt, key = .subset2(entry, "key"), created = .subset2(entry, "created"),
       row = row, answer = ans, doc_hash = h)
}

#' Atomic vectors and lists, all the way down, attributes included.
#'
#' What a store entry is made of when this package wrote it. Environments,
#' functions, calls, symbols, promises, external pointers and S4 objects are
#' the things that can run code or reach outside the file, and none of them is
#' ever part of a result.
#' @noRd
corpus_is_plain <- function(x) {
  if (isS4(x)) return(FALSE)
  if (!typeof(x) %in% c("NULL", "logical", "integer", "double", "complex", "character",
                        "raw", "list")) return(FALSE)
  if (is.list(x)) {
    u <- unclass(x)
    for (i in seq_along(u)) if (!corpus_is_plain(.subset2(u, i))) return(FALSE)
  }
  a <- attributes(x)
  for (i in seq_along(a)) if (!corpus_is_plain(a[[i]])) return(FALSE)
  TRUE
}

#' The bindings of a trace saved as an environment (store format 1), or NULL.
#'
#' Read without running anything: an active binding is refused before it is
#' touched, and `substitute()` returns a promise's code instead of forcing it,
#' which then fails the plain-data test. A gr_trace() has an empty parent and
#' only plain values, so a real one always passes.
#' @noRd
corpus_trace_bindings <- function(e) {
  if (isS4(e) || !inherits(e, "gr_trace") || !identical(parent.env(e), emptyenv())) return(NULL)
  out <- list()
  for (nm in ls(e, all.names = TRUE, sorted = TRUE)) {
    if (bindingIsActive(nm, e)) return(NULL)
    v <- eval(call("substitute", as.name(nm), e))
    if (!corpus_is_plain(v)) return(NULL)
    out[nm] <- list(v)
  }
  out
}

#' A gr_trace again, from the plain list a store entry holds.
#' @noRd
corpus_trace_rebuild <- function(x) {
  if (!is.list(x) || !length(x)) return(NULL)
  e <- list2env(x, envir = new.env(parent = emptyenv()))
  class(e) <- "gr_trace"
  e
}

#' Written to a temporary name and renamed, so an interrupt cannot leave a half
#' entry that a later run would have to tell from a real one.
#' @noRd
corpus_save <- function(store, key, row, answer, doc_hash = NULL) {
  path <- corpus_store_path(store, key)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  # Format 2: the answer's trace is saved as a plain list rather than as the
  # environment it is in memory, so the whole entry is plain data and
  # corpus_restore() can refuse anything that is not. `doc_hash` is additive
  # and did not move the format: an entry written before it existed is still a
  # perfectly good answer, it just cannot seed duplicate detection.
  if (!is.null(answer) && is.environment(answer$trace)) {
    answer$trace <- as.list.environment(answer$trace, all.names = TRUE)
  }
  ok <- tryCatch({
    saveRDS(list(format = 2L, key = key, created = Sys.time(), row = row,
                 answer = answer, doc_hash = doc_hash),
            tmp, compress = TRUE)
    file.rename(tmp, path)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok) && file.exists(tmp)) unlink(tmp)
  invisible(isTRUE(ok))
}
