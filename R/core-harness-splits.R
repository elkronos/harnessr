# core-harness-splits.R: which split each reference item belongs to.
#
# A comparison is only evidence if the items it is scored on played no part
# in tuning what is compared. Items from one document share its wording, its
# layout and its quirks, so a document with questions on both sides of the
# line leaks the test into the tuning. Splits are therefore drawn by cluster:
# every item of a document goes where the document goes.

#' The splits an item can be assigned to, in the order they are reported.
#' @noRd
.hr_split_names <- c("dev", "exploratory", "calibration", "test", "final")

#' Assign reference items to splits by cluster
#'
#' Puts every item of a cluster (a document, usually) in the same split, so
#' that no document has items on both sides of a tuning and a scoring split.
#' The assignment is worked out from the seed and the cluster ids alone: the
#' order of the rows, the session's random state and the other clusters in
#' the set do not change it (with `method = "stable"`).
#'
#' @section The splits:
#' * `dev` tunes prompts, settings and margins. Its scores are not evidence.
#' * `exploratory` is kept out of the test set for exploratory comparisons.
#' * `calibration` is for calibrating signals and choosing gate thresholds
#'   ([hr_calibrate_signal()], [hr_gate_threshold()]), kept apart from both
#'   tuning and testing.
#' * `test` is what reported comparisons are scored on.
#' * `final` is an optional held-back set, run once per release.
#'
#' `props` names any of these. A split given a share of 0 receives nothing.
#'
#' @section How clusters are assigned:
#' Each cluster gets a number `u` in \[0, 1) from the first 13 hex digits of
#' the SHA-256 digest of `"harnessr-split"`, the seed and the cluster id
#' (as UTF-8, joined by a separator), divided by 16^13.
#'
#' * `method = "stable"` (the default) cuts \[0, 1) into consecutive
#'   intervals whose widths are `props`, in the order `props` is given, and a
#'   cluster goes to the interval `u` falls in. A cluster's split depends only
#'   on the seed and its own id, so adding documents to the set later, or
#'   dropping some, never moves another document between splits. The shares
#'   are those of `props` on average over clusters; with few clusters they
#'   can be some way off, and `counts` shows how far.
#' * `method = "balanced"` sorts the clusters by `u` and gives each split
#'   its share of the clusters, rounded by largest remainders (Hamilton's
#'   method), in the order `props` is given. The number of clusters per split
#'   is then as close to `props` as whole clusters allow, but a cluster added
#'   later can shift others across a boundary, so the assignment should be
#'   drawn once and stored.
#'
#' Shares are shares of clusters. Item counts follow from cluster sizes and
#' are reported beside them.
#'
#' @param items The items: a vector of item ids, or a data frame with one row
#'   per item. A data frame's ids come from its `item_id` column, else its
#'   `id` column, else the row number.
#' @param cluster The cluster of each item: a vector as long as `items`, or
#'   for a data frame the name of a column. With a data frame one string is
#'   always read as a column name; for a one-row frame and a literal cluster
#'   value, wrap it in [I()]. `NULL` takes a data frame's
#'   `cluster` column, else its `document` column; for a vector of ids, or a
#'   data frame with neither column, each item is its own cluster.
#' @param props Named shares, from `"dev"`, `"exploratory"`, `"calibration"`,
#'   `"test"` and `"final"`, each at least 0, adding up to 1.
#' @param seed One number or one string. Required: the assignment is a
#'   function of the seed and the ids, so the seed has to be recorded with it.
#' @param method `"stable"` or `"balanced"`; see "How clusters are assigned".
#' @return An object of class `hr_splits`, a list with:
#'   \describe{
#'     \item{`items`}{The items with a `split` column: the data frame given,
#'       or a data frame of `item_id`, `cluster` and `split`.}
#'     \item{`clusters`}{One row per cluster: `cluster`, `n_items`, `u` and
#'       `split`.}
#'     \item{`counts`}{One row per split in `props`: `split`, `target` (the
#'       share asked for), `clusters`, `items`, `cluster_share` and
#'       `item_share`.}
#'     \item{`props`, `seed`, `method`}{As given.}
#'     \item{`notes`}{Remarks, such as a split that was given a share and
#'       received no cluster.}
#'   }
#'   It has a `print()` method.
#' @seealso [gr_label_sheet()] to write sheets for people to label the
#'   items, [hr_calibrate_signal()].
#' @family reference sets
#' @export
#' @examples
#' qa <- data.frame(item_id = sprintf("q%02d", 1:40),
#'                  document = rep(sprintf("doc%02d.pdf", 1:10), each = 4))
#' sp <- hr_assign_splits(qa, seed = 2026)
#' sp
#' table(sp$items$split)
#'
#' # Whole clusters, split as close to the shares as ten documents allow.
#' hr_assign_splits(qa, seed = 2026, method = "balanced")$counts
hr_assign_splits <- function(items, cluster = NULL,
                             props = c(dev = 0.1, exploratory = 0.1, calibration = 0.3,
                                       test = 0.5),
                             seed, method = c("stable", "balanced")) {
  method <- match.arg(method)
  if (missing(seed) || is.null(seed) || length(seed) != 1L || is.na(seed) ||
      !(is.numeric(seed) || is.character(seed)) ||
      (is.numeric(seed) && !is.finite(seed)) || (is.character(seed) && !nzchar(seed))) {
    gr_abort(paste0("`seed` is required: one number or one string, recorded with the ",
                    "assignment so it can be drawn again."), class = "gr_bad_setting")
  }
  props <- split_props(props)
  is_df <- is.data.frame(items)
  if (!is_df && !(is.atomic(items) && is.null(dim(items)))) {
    gr_abort("`items` must be a vector of item ids or a data frame.", class = "gr_bad_setting")
  }
  n <- if (is_df) nrow(items) else length(items)
  if (!n) gr_abort("`items` has no items.", class = "gr_bad_setting")

  ids <- if (!is_df) items
         else if (!is.null(items$item_id)) items$item_id
         else if (!is.null(items$id)) items$id
         else seq_len(n)
  ids <- as.character(ids)
  if (anyNA(ids) || any(!nzchar(trimws(ids)))) {
    gr_abort(sprintf("Item %d has no id.", which(is.na(ids) | !nzchar(trimws(ids)))[1]),
             class = "gr_bad_setting")
  }
  if (anyDuplicated(ids)) {
    gr_abort(sprintf("Item id '%s' appears more than once.", ids[anyDuplicated(ids)]),
             class = "gr_bad_setting")
  }

  notes <- character(0)
  # For a data frame a single string is always a column name, so a misspelt
  # name stops even on a one-row frame; wrap a literal value in I().
  if (is_df && is.character(cluster) && length(cluster) == 1L && !inherits(cluster, "AsIs")) {
    if (is.null(items[[cluster]])) {
      gr_abort(sprintf("`items` has no column '%s' to take clusters from.", cluster),
               class = "gr_bad_setting")
    }
    cluster <- items[[cluster]]
  } else if (is.null(cluster)) {
    cluster <- if (is_df && !is.null(items$cluster)) items$cluster
               else if (is_df && !is.null(items$document)) items$document
               else NULL
    if (is.null(cluster)) {
      cluster <- ids
      notes <- c(notes, "No cluster was given, so each item is its own cluster.")
    }
  }
  if (length(cluster) != n) {
    gr_abort(sprintf("`cluster` has %d value(s) for %d item(s).", length(cluster), n),
             class = "gr_bad_setting")
  }
  cluster <- enc2utf8(as.character(cluster))
  bad <- is.na(cluster) | !nzchar(trimws(cluster))
  if (any(bad)) {
    gr_abort(sprintf("Item '%s' has no cluster.", ids[which(bad)[1]]), class = "gr_bad_setting")
  }

  cl <- unique(cluster)
  u <- split_uniform(seed, cl)
  breaks <- c(0, cumsum(props)[-length(props)])
  if (method == "stable") {
    which_split <- findInterval(u, breaks)
  } else {
    # Hamilton's method: the whole part of each quota first, then one more
    # to the largest remainders, ties going to the split listed first.
    quota <- props * length(cl)
    take <- floor(quota + 1e-9)
    left <- length(cl) - sum(take)
    if (left > 0L) {
      rem <- quota - take
      extra <- order(-rem, seq_along(rem))[seq_len(left)]
      take[extra] <- take[extra] + 1
    }
    ord <- order(u, cl)
    which_split <- integer(length(cl))
    which_split[ord] <- rep(seq_along(props), times = take)
  }
  split_of <- names(props)[which_split]
  sizes <- tabulate(match(cluster, cl), length(cl))
  clusters <- data.frame(cluster = cl, n_items = sizes, u = u, split = split_of,
                         stringsAsFactors = FALSE)
  item_split <- split_of[match(cluster, cl)]

  n_cl <- vapply(names(props), function(s) sum(split_of == s), numeric(1))
  n_it <- vapply(names(props), function(s) sum(item_split == s), numeric(1))
  counts <- data.frame(split = names(props), target = unname(props),
                       clusters = as.integer(n_cl), items = as.integer(n_it),
                       cluster_share = unname(n_cl) / length(cl),
                       item_share = unname(n_it) / n, stringsAsFactors = FALSE)
  empty <- counts$split[counts$target > 0 & counts$clusters == 0L]
  if (length(empty)) {
    msg <- sprintf(paste0("Split(s) %s were given a share but received no cluster: %d ",
                          "cluster(s) are too few for these shares."),
                   paste(sprintf("'%s'", empty), collapse = ", "), length(cl))
    notes <- c(notes, msg)
    gr_warn(msg, class = "hr_empty_split")
  }

  out_items <- if (is_df) {
    it <- items
    it$split <- item_split
    it
  } else {
    data.frame(item_id = ids, cluster = cluster, split = item_split, stringsAsFactors = FALSE)
  }
  rownames(out_items) <- NULL
  structure(list(items = out_items, clusters = clusters, counts = counts, props = props,
                 seed = seed, method = method, notes = notes),
            class = "hr_splits")
}

#' `props` checked: named from .hr_split_names, no repeats, each at least 0,
#' summing to 1 within rounding.
#' @noRd
split_props <- function(props) {
  if (!is.numeric(props) || !length(props) || anyNA(props) || any(!is.finite(props)) ||
      is.null(names(props))) {
    gr_abort("`props` must be a named numeric vector of shares.", class = "gr_bad_setting")
  }
  bad <- setdiff(names(props), .hr_split_names)
  if (length(bad)) {
    gr_abort(sprintf("`props` names unknown split(s) %s; use %s.",
                     paste(sprintf("'%s'", bad), collapse = ", "),
                     paste(sprintf("'%s'", .hr_split_names), collapse = ", ")),
             class = "gr_bad_setting")
  }
  if (anyDuplicated(names(props))) {
    gr_abort(sprintf("`props` names '%s' twice.", names(props)[anyDuplicated(names(props))]),
             class = "gr_bad_setting")
  }
  if (any(props < 0)) gr_abort("Every share in `props` must be at least 0.", class = "gr_bad_setting")
  if (abs(sum(props) - 1) > 1e-8) {
    gr_abort(sprintf("The shares in `props` must add up to 1; they add up to %s.",
                     format(sum(props), digits = 6)), class = "gr_bad_setting")
  }
  props
}

#' A number in [0, 1) for each cluster id, from the SHA-256 digest of the
#' seed and the id. 13 hex digits are 52 bits, which a double holds exactly,
#' so the value is the same on every platform.
#' @noRd
split_uniform <- function(seed, ids) {
  s <- if (is.numeric(seed)) sprintf("%.17g", as.numeric(seed)) else enc2utf8(seed)
  vapply(ids, function(id) {
    h <- digest::digest(charToRaw(paste("harnessr-split", s, enc2utf8(id), sep = "\u0001")),
                        algo = "sha256", serialize = FALSE)
    hex <- strsplit(substr(h, 1L, 13L), "", fixed = TRUE)[[1]]
    sum(strtoi(hex, 16L) * 16^(12:0)) / 16^13
  }, numeric(1), USE.NAMES = FALSE)
}

#' @export
print.hr_splits <- function(x, ...) {
  cat(sprintf("<hr_splits> %d item(s) in %d cluster(s), method %s, seed %s\n\n",
              nrow(x$items), nrow(x$clusters), x$method, format(x$seed)))
  ct <- x$counts
  ct$target <- round(ct$target, 3)
  ct$cluster_share <- round(ct$cluster_share, 3)
  ct$item_share <- round(ct$item_share, 3)
  print(ct, row.names = FALSE)
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}
