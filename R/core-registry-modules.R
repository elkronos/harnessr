# core-registry-modules.R: one way to register and list modules of any kind.
#
# The kinds and how to reach each one's registry live in hr_state (see
# core-registry-kinds.R). The registries themselves stay with the layer that
# registered the kind, so this file reads and writes them only through the
# `get` and `set` functions that layer gave hr_register_kind().

#' The `get` and `set` functions of a kind, or an error of class
#' `hr_unknown_kind` naming the kinds that have the one asked for.
#' @noRd
kind_access <- function(kind, need = c("get", "set")) {
  need <- match.arg(need)
  access <- hr_state$kind_access
  usable <- names(access)[vapply(access, function(a) is.function(a[[need]]), logical(1))]
  if (!is_nonblank(kind) || !(kind %in% usable)) {
    gr_abort(sprintf("Unknown kind of module '%s'. Kinds you can %s: %s.",
                     as_chr1(kind, "<missing>"),
                     if (need == "set") "register" else "list",
                     paste(usable, collapse = ", ")),
             class = "hr_unknown_kind")
  }
  access[[kind]][[need]]
}

#' Register a module of any kind
#'
#' `hr_register()` files a module under a kind, such as `"reader"` or
#' `"segmenter"`, through the same checks as that kind's own registration
#' function: `hr_register("reader", ...)` runs what [gr_register_reader()]
#' runs, so a reader named `"auto"` or with a malformed `signature` is refused
#' here as it is there. [hr_modules()] lists the kinds and what each holds.
#'
#' The kinds the package brings, and the function each one goes through:
#' `"extractor"` ([gr_register_extractor()]), `"cleaner"`
#' ([gr_register_cleaner()]), `"segmenter"` ([gr_register_segmenter()]),
#' `"reader"` ([gr_register_reader()]) and `"embedder"`
#' ([gr_register_embedder()]). Protocols are not a kind of module; register
#' one with [gr_register_protocol()].
#'
#' @param kind The kind of module, one string. A kind the package does not
#'   know is an error of class `hr_unknown_kind`.
#' @param name The module's name, one string. Registering a name again
#'   replaces the module.
#' @param fn The module's function, with the arguments its kind calls it
#'   with (see the kind's own registration function).
#' @param ... The other arguments of the kind's own registration function,
#'   by name, such as `signature` for a reader or `extensions` for an
#'   extractor. A segmenter also takes `effort_label`, a function of the
#'   segment spec that returns the trace label its model requests carry, or
#'   `""` when it sends none. A run's `effort` setting then reaches the
#'   segmenter as the effort for that label alone. Without it, the segmenter
#'   gets the run's whole effort map.
#' @param description One-line description, shown by the kind's listing and
#'   by [hr_modules()].
#' @param calls The stems of the trace labels the module's model calls
#'   carry, for the kinds that declare them (readers and segmenters). `NULL`
#'   (the default) declares the module's name. Any other value for a kind
#'   that does not declare calls is an error of class `gr_bad_setting`.
#' @return Invisibly, `name`.
#' @seealso [hr_modules()], `vignette("extending")`
#' @family harness
#' @export
#' @examples
#' # A segmenter that makes one chunk per line, registered by kind.
#' hr_register("segmenter", "by_line", description = "one chunk per line",
#'   fn = function(doc, spec, client, trace) {
#'     new_chunks(strsplit(doc$text, "\n+")[[1]], "by_line", spec)
#'   })
#' subset(hr_modules("segmenter"), name == "by_line")[, c("kind", "name", "cost")]
#' nrow(gr_segment(gr_example(), list(method = "by_line"))$chunks)
#'
#' # A kind the package does not know is refused.
#' try(hr_register("ranker", "mine", fn = identity))
hr_register <- function(kind, name, fn, ..., description = "", calls = NULL) {
  set <- kind_access(kind, "set")
  set(name = name, fn = fn, ..., description = description, calls = calls)
  invisible(name)
}

#' List the registered modules of every kind
#'
#' One table across the kinds of module: each registered extractor, cleaner,
#' segmenter, reader and embedder, with its description and the call stems
#' it declares. Ask for one kind to add the columns only that kind has, such
#' as a reader's `signature` or an extractor's `extensions`. The kind's own
#' listing, such as [gr_readers()], keeps its own shape and is unchanged.
#'
#' @param kind `NULL` (the default) for every kind, or one kind, such as
#'   `"reader"`. A kind the package does not know is an error of class
#'   `hr_unknown_kind`.
#' @return A data frame with one row per module, sorted by kind in the order
#'   the kinds were registered and by name within a kind: `kind`, `name`,
#'   `description`, and `calls`, a list column of the call stems each module
#'   declares (`character(0)` for none). With `kind`, it also has a column
#'   for each other setting the kind's modules were registered with, except
#'   functions; a setting with more than one value per module, such as an
#'   extractor's `extensions`, is a list column.
#' @seealso [hr_register()], `vignette("extending")`
#' @family harness
#' @export
#' @examples
#' m <- hr_modules()
#' table(m$kind)
#'
#' # One kind, with that kind's own columns.
#' r <- hr_modules("reader")
#' r[r$name %in% c("stuff", "retrieve"), c("name", "signature", "cost_calls")]
#' r$calls[r$name == "refine"][[1]]
hr_modules <- function(kind = NULL) {
  if (is.null(kind)) {
    access <- hr_state$kind_access
    kinds <- names(access)[vapply(access, function(a) is.function(a$get), logical(1))]
    parts <- lapply(kinds, function(k) modules_frame(k, access[[k]]$get(), own = FALSE))
    if (!length(parts)) return(modules_frame(character(0), list(), own = FALSE))
    out <- do.call(rbind, parts)
    rownames(out) <- NULL
    return(out)
  }
  modules_frame(kind, kind_access(kind, "get")(), own = TRUE)
}

#' The rows of hr_modules() for one kind's registry entries. With `own`, a
#' column is added for each field the entries carry beyond the shared ones,
#' leaving out functions and the registration stamp.
#' @noRd
modules_frame <- function(kind, entries, own) {
  nms <- names(entries) %||% character(0)
  entries <- entries[order(nms, method = "radix")]
  nms <- names(entries) %||% character(0)
  out <- data.frame(kind = rep(as.character(kind), length(nms)), name = nms,
                    description = vapply(entries, function(e) as_chr1(e$description, ""),
                                         character(1), USE.NAMES = FALSE),
                    stringsAsFactors = FALSE)
  out$calls <- lapply(unname(entries), function(e) {
    if (is.character(e$calls)) e$calls else character(0)
  })
  if (!own) return(out)
  shared <- c("name", "description", "calls", "fn", "registered")
  fields <- setdiff(unique(unlist(lapply(entries, names), use.names = FALSE)), shared)
  for (f in fields) {
    vals <- lapply(unname(entries), `[[`, f)
    if (any(vapply(vals, is.function, logical(1)))) next
    scalar <- vapply(vals, function(v) is.null(v) || (is.atomic(v) && length(v) == 1L),
                     logical(1))
    out[[f]] <- if (all(scalar)) {
      unlist(lapply(vals, function(v) if (is.null(v)) NA else v), use.names = FALSE)
    } else {
      vals
    }
  }
  rownames(out) <- NULL
  out
}
