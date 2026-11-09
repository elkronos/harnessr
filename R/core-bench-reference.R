# core-bench-reference.R: the items, labels and clusters a benchmark scores.
#
# A reference is locked once a benchmark starts to score it. After that no
# item can be added to it, so an analyst cannot pick gold items after seeing
# which ones the arms got right. The lock lives in an environment shared by
# every copy of the reference and every reference grown from it with
# hr_reference_add(), so copying the object does not get round it.

#' The splits a reference item can belong to, in the order of the plan: dev
#' tunes, exploratory holds the early experiments, calibration sets signal
#' thresholds, test is reported, final is run once per release.
#' @noRd
.hr_splits <- c("dev", "exploratory", "calibration", "test", "final")

#' A reference set to score arms against
#'
#' A reference holds the items a benchmark runs every arm on, the label each
#' item is scored against, the cluster it belongs to (the unit whose items
#' share errors, such as a document or a task), and the split it is in.
#'
#' The splits keep tuning apart from evidence. `"dev"` is for tuning prompts
#' and thresholds, and [hr_benchmark()] marks its rows as not reportable.
#' `"exploratory"` is for early experiments kept out of the test set,
#' `"calibration"` for setting signal thresholds, `"test"` for the reported
#' comparison, and `"final"` for a held-out set run once per release.
#'
#' `inclusion_prob` is the probability with which each item was drawn into
#' the reference, for estimates that weight items by it (see
#' [hr_ht_estimate()]); 1 means every item of the population is in the
#' reference.
#'
#' A reference is locked when a benchmark starts scoring it. After that
#' [hr_reference_add()] refuses to add items to it or to any reference built
#' from it, with an error of class `hr_reference_locked`, so gold items
#' cannot be chosen after the results are seen. The lock is shared by every
#' copy of the reference. The `hash` is a SHA-256 hash of the ids, payloads,
#' labels, clusters, splits, inclusion probabilities, strata and coders;
#' [hr_benchmark()] refuses a reference whose content no longer matches it.
#'
#' @param items The items, one per element: a named list whose names are the
#'   item ids and whose elements are the payloads the arms are given (any R
#'   object: a question, a question with a file path, a record), a named
#'   character vector (names are ids, values payloads), or an unnamed
#'   character vector of ids, which are then their own payloads.
#' @param labels The label of each item, one per item: an atomic vector, or a
#'   list whose elements may hold several accepted answers. `NA` for an item
#'   with no label, which is scored `NA`.
#' @param cluster The cluster of each item, one per item, or one value for
#'   all. Taken as text.
#' @param split The split of each item, one per item, or one value for all:
#'   `"dev"`, `"exploratory"`, `"calibration"`, `"test"` or `"final"`. When
#'   `split` is not given, every item goes in `"dev"`.
#' @param inclusion_prob The probability each item was drawn into the
#'   reference, in (0, 1]: one per item or one for all.
#' @param strata The sampling stratum of each item, or `NULL`.
#' @param coders The labels individual coders gave, one row per item and one
#'   column per coder (a matrix or data frame), or `NULL`.
#' @param reference An `hr_reference`.
#' @return An object of class `hr_reference`: a list of `ids`, `items` (the
#'   payloads, named by id), `labels`, `cluster`, `split`, `inclusion_prob`,
#'   `strata`, `coders` and `hash`. `hr_reference_add()` returns a new
#'   reference holding the old items and the new ones, sharing the old one's
#'   lock.
#' @seealso [hr_benchmark()], [hr_arm()]
#' @family harness
#' @export
#' @examples
#' ref <- hr_reference(
#'   items = list(q1 = "Capital of France?", q2 = "Capital of Peru?",
#'                q3 = "Capital of Chad?"),
#'   labels = c("Paris", "Lima", "N'Djamena"),
#'   cluster = c("europe", "americas", "africa"),
#'   split = "test")
#' ref
#'
#' # Items can be added until a benchmark has scored the reference.
#' ref <- hr_reference_add(ref, list(q4 = "Capital of Fiji?"), "Suva", "oceania",
#'                         split = "test")
#' length(ref$ids)
hr_reference <- function(items, labels, cluster,
                         split = c("dev", "exploratory", "calibration", "test", "final"),
                         inclusion_prob = 1, strata = NULL, coders = NULL) {
  ref <- new_reference(items, labels, cluster, split, inclusion_prob, strata, coders,
                       missing(split))
  ref$.lock <- new.env(parent = emptyenv())
  ref$.lock$locked <- FALSE
  structure(ref, class = "hr_reference")
}

#' @rdname hr_reference
#' @export
hr_reference_add <- function(reference, items, labels, cluster,
                             split = c("dev", "exploratory", "calibration", "test", "final"),
                             inclusion_prob = 1, strata = NULL, coders = NULL) {
  check_reference(reference)
  if (isTRUE(reference$.lock$locked)) {
    gr_abort(sprintf(paste0(
      "This reference was locked when a benchmark began scoring it (%s), so no items can be ",
      "added: gold items chosen after the results are seen would bias every comparison. ",
      "Build a new reference with hr_reference() and score it from the start."),
      reference$.lock$locked_at), class = "hr_reference_locked")
  }
  add <- new_reference(items, labels, cluster, split, inclusion_prob, strata, coders,
                       missing(split))
  clash <- intersect(add$ids, reference$ids)
  if (length(clash)) {
    gr_abort(sprintf("Item ids already in the reference: %s.", paste(clash, collapse = ", ")),
             class = "hr_bad_reference")
  }
  if (is.null(reference$strata) != is.null(add$strata) ||
      is.null(reference$coders) != is.null(add$coders)) {
    gr_abort(paste0("New items must give `strata` and `coders` exactly when the reference ",
                    "has them."), class = "hr_bad_reference")
  }
  if (!is.null(add$coders) && !identical(colnames(add$coders), colnames(reference$coders))) {
    gr_abort("New items must name the same coders as the reference.",
             class = "hr_bad_reference")
  }
  out <- list(ids = c(reference$ids, add$ids),
              items = c(reference$items, add$items),
              labels = c(reference$labels, add$labels),
              cluster = c(reference$cluster, add$cluster),
              split = c(reference$split, add$split),
              inclusion_prob = c(reference$inclusion_prob, add$inclusion_prob),
              strata = if (!is.null(add$strata)) c(reference$strata, add$strata),
              coders = if (!is.null(add$coders)) rbind(reference$coders, add$coders))
  out$hash <- reference_hash(out)
  # The same lock: a benchmark that scores either one locks both.
  out$.lock <- reference$.lock
  structure(out, class = "hr_reference")
}

#' Check and assemble the parts of a reference, without the lock.
#' @noRd
new_reference <- function(items, labels, cluster, split, inclusion_prob, strata, coders,
                          split_missing) {
  if (is.character(items) && is.null(names(items))) {
    ids <- items
    payload <- as.list(items)
  } else if ((is.list(items) && !is.data.frame(items)) || is.character(items)) {
    ids <- names(items)
    if (is.null(ids)) {
      gr_abort("`items` given as a list must be named by item id.", class = "hr_bad_reference")
    }
    payload <- as.list(items)
  } else {
    gr_abort(paste0("`items` must be a named list of payloads (names are the item ids) or a ",
                    "character vector of ids."), class = "hr_bad_reference")
  }
  n <- length(ids)
  if (!n) gr_abort("A reference needs at least one item.", class = "hr_bad_reference")
  if (anyNA(ids) || any(!nzchar(trimws(ids)))) {
    gr_abort("Every item needs a non-blank id.", class = "hr_bad_reference")
  }
  dup <- unique(ids[duplicated(ids)])
  if (length(dup)) {
    gr_abort(sprintf("Item ids must be unique; repeated: %s.",
                     paste(utils::head(dup, 5), collapse = ", ")), class = "hr_bad_reference")
  }
  names(payload) <- ids
  per_item <- function(x, what, recycle = TRUE) {
    if (length(x) == n) return(x)
    if (recycle && length(x) == 1L) return(rep(x, n))
    gr_abort(sprintf("`%s` must have one value per item (%d)%s, not %d.", what, n,
                     if (recycle) " or one for all" else "", length(x)),
             class = "hr_bad_reference")
  }
  if (missing(labels) || is.null(labels) || !(is.atomic(labels) || is.list(labels)) || is.data.frame(labels)) {
    gr_abort("`labels` must be a vector or list with one label per item.",
             class = "hr_bad_reference")
  }
  labels <- as.list(per_item(labels, "labels", recycle = FALSE))
  names(labels) <- ids
  if (missing(cluster) || is.null(cluster) || !is.atomic(cluster) || anyNA(cluster)) {
    gr_abort("`cluster` must give each item a cluster, with no NA.", class = "hr_bad_reference")
  }
  cluster <- as.character(per_item(cluster, "cluster"))
  # Left as the default it is "dev": an item is only evidence when it was put
  # in a reported split on purpose.
  if (isTRUE(split_missing)) split <- "dev"
  if (!is.character(split) || anyNA(split) || !all(split %in% .hr_splits)) {
    bad <- unique(split[!split %in% .hr_splits])
    gr_abort(sprintf("`split` values must be among %s; not: %s.",
                     paste(.hr_splits, collapse = ", "), paste(bad, collapse = ", ")),
             class = "hr_bad_reference")
  }
  split <- per_item(split, "split")
  if (!is.numeric(inclusion_prob) || anyNA(inclusion_prob) ||
      any(inclusion_prob <= 0 | inclusion_prob > 1)) {
    gr_abort("`inclusion_prob` must be in (0, 1], with no NA.", class = "hr_bad_reference")
  }
  inclusion_prob <- as.numeric(per_item(inclusion_prob, "inclusion_prob"))
  if (!is.null(strata)) {
    if (!is.atomic(strata) || anyNA(strata)) {
      gr_abort("`strata` must give each item a stratum, with no NA.", class = "hr_bad_reference")
    }
    strata <- as.character(per_item(strata, "strata", recycle = FALSE))
  }
  if (!is.null(coders)) {
    if (!(is.matrix(coders) || is.data.frame(coders)) || nrow(coders) != n) {
      gr_abort(sprintf("`coders` must be a matrix or data frame with one row per item (%d).", n),
               class = "hr_bad_reference")
    }
    coders <- as.data.frame(coders, stringsAsFactors = FALSE)
    rownames(coders) <- ids
  }
  ref <- list(ids = ids, items = payload, labels = labels, cluster = cluster, split = split,
              inclusion_prob = inclusion_prob, strata = strata, coders = coders)
  ref$hash <- reference_hash(ref)
  ref
}

#' The content hash of a reference: everything but the hash and the lock.
#' @noRd
reference_hash <- function(ref) {
  hr_hash(unclass(ref)[c("ids", "items", "labels", "cluster", "split", "inclusion_prob",
                         "strata", "coders")])
}

#' A reference, checked: built by hr_reference() and not changed since.
#' @noRd
check_reference <- function(reference) {
  if (!inherits(reference, "hr_reference") || !is.environment(reference$.lock)) {
    gr_abort("`reference` must come from hr_reference().", class = "hr_bad_reference")
  }
  if (!identical(reference_hash(reference), reference$hash)) {
    gr_abort(paste0("The reference was changed after hr_reference() built it, so its hash ",
                    "no longer matches its content. Build it again with hr_reference()."),
             class = "hr_bad_reference")
  }
  invisible(reference)
}

# The hashes of every reference a benchmark has begun to score in this
# session, with the time it began. A reference rebuilt from the same
# arguments has the same hash but a fresh lock, so the lock alone cannot
# tell hr_register_contrasts() that its content was already scored.
.hr_locked_refs <- new.env(parent = emptyenv())

#' Lock a reference: from now on no item can be added to it.
#' @noRd
reference_lock <- function(reference, by) {
  lock <- reference$.lock
  if (!isTRUE(lock$locked)) {
    lock$locked <- TRUE
    lock$locked_at <- utc_stamp(Sys.time())
    lock$locked_by <- by
    lock$hash <- reference$hash
  }
  if (is.character(reference$hash) && length(reference$hash) == 1L &&
      is.null(.hr_locked_refs[[reference$hash]])) {
    assign(reference$hash, lock$locked_at, envir = .hr_locked_refs)
  }
  invisible(reference)
}

#' @export
print.hr_reference <- function(x, ...) {
  cat(sprintf("<hr_reference> %d item(s) in %d cluster(s)%s\n", length(x$ids),
              length(unique(x$cluster)),
              if (isTRUE(x$.lock$locked)) sprintf(", locked %s", x$.lock$locked_at) else ""))
  tab <- table(factor(x$split, levels = .hr_splits))
  tab <- tab[tab > 0]
  cat("  splits:", paste(sprintf("%s %d", names(tab), as.integer(tab)), collapse = ", "), "\n")
  if (any(x$inclusion_prob < 1)) {
    cat(sprintf("  inclusion_prob: %s to %s\n", format(min(x$inclusion_prob)),
                format(max(x$inclusion_prob))))
  }
  if (!is.null(x$strata)) cat(sprintf("  strata: %d\n", length(unique(x$strata))))
  if (!is.null(x$coders)) cat(sprintf("  coders: %s\n", paste(names(x$coders), collapse = ", ")))
  cat(sprintf("  hash: %s\n", substr(x$hash, 1, 12)))
  invisible(x)
}
