# core-stats-alpha.R: Krippendorff's alpha for any number of coders.

# Alpha below this many pairable items is not reported (Hayes and
# Krippendorff 2007 on its instability with few units).
.hr_alpha_min_items <- 30L

#' The coders branch of hr_agreement().
#' @noRd
agreement_coders <- function(coders, level, B, conf, seed) {
  m <- coder_matrix(coders, level)
  ka <- kripp_alpha(m$values, level = level, categories = m$categories)
  notes <- character(0)
  alpha <- ka$alpha
  ci <- c(NA_real_, NA_real_)
  if (ka$n_items < .hr_alpha_min_items) {
    notes <- c(notes, sprintf(
      "Only %d pairable item(s); alpha needs at least %d, so percent agreement is reported instead.",
      ka$n_items, .hr_alpha_min_items))
    alpha <- NA_real_
  } else if (is.na(alpha)) {
    notes <- c(notes, "Every value is the same, so alpha is undefined; percent agreement is reported instead.")
  } else if (B > 0) {
    ci <- kripp_boot(ka, B = B, conf = conf, seed = seed)
  }
  if (m$dropped) {
    notes <- c(notes, sprintf("%d item(s) with fewer than two labels are not pairable and were left out.",
                              m$dropped))
  }
  stats <- data.frame(statistic = c("percent agreement", "Krippendorff's alpha"),
                      estimate = c(ka$po, alpha), se = NA_real_,
                      lower = c(NA_real_, ci[1]), upper = c(NA_real_, ci[2]),
                      stringsAsFactors = FALSE)
  structure(list(type = "coders", level = level, n = ka$n_items, dropped = m$dropped,
                 coders = ncol(m$values), categories = m$categories,
                 table = ka$coincidence, stats = stats, po = ka$po, kappa = NA_real_,
                 alpha = alpha, paradox_flag = NA, positive = NULL, notes = notes,
                 conf = conf, bootstrap = list(B = as.integer(B), seed = seed)),
            class = "hr_agreement")
}

#' Coder labels as a matrix of category indices, with the categories.
#'
#' Nominal and ordinal labels become indices into the sorted (or factor
#' level) categories, with the coders' factor levels merged by
#' merge_levels(); interval and ratio labels must be numeric and their
#' distinct values are the categories.
#' @noRd
coder_matrix <- function(coders, level) {
  if (!is.matrix(coders) && !is.data.frame(coders)) {
    gr_abort("`coders` must be a matrix or data frame, items in rows and coders in columns.",
             class = "gr_bad_setting")
  }
  cols <- if (is.data.frame(coders)) as.list(coders) else
    lapply(seq_len(ncol(coders)), function(j) coders[, j])
  if (length(cols) < 2L) gr_abort("`coders` needs at least two coders (columns).",
                                  class = "gr_bad_setting")
  if (!nrow(coders)) gr_abort("`coders` has no items (rows).", class = "gr_bad_setting")
  numeric_level <- level %in% c("interval", "ratio")
  if (numeric_level) {
    if (!all(vapply(cols, function(v) is.numeric(v) || all(is.na(v)), logical(1)))) {
      gr_abort(sprintf("The %s level needs numeric labels.", level), class = "gr_bad_setting")
    }
    vals <- sort(unique(unlist(lapply(cols, function(v) v[!is.na(v)]))))
    if (level == "ratio" && any(vals < 0)) {
      gr_abort("The ratio level needs labels of zero or more.", class = "gr_bad_setting")
    }
    idx <- vapply(cols, function(v) match(v, vals), integer(nrow(coders)))
  } else {
    facs <- vapply(cols, is.factor, logical(1))
    vals <- if (any(facs)) merge_levels(lapply(cols[facs], levels), level) else character(0)
    rest <- unique(unlist(lapply(cols, function(v) as.character(v[!is.na(v)]))))
    extra <- setdiff(rest, vals)
    # Numbers sort as numbers, so an ordinal 1-10 scale is not read as "1", "10", "2".
    if (length(extra)) {
      num <- suppressWarnings(as.numeric(extra))
      extra <- if (!anyNA(num)) extra[order(num)] else sort(extra)
    }
    vals <- c(vals, extra)
    idx <- vapply(cols, function(v) match(as.character(v), vals), integer(nrow(coders)))
  }
  idx <- matrix(idx, nrow = nrow(coders))
  pairable <- rowSums(!is.na(idx)) >= 2L
  list(values = idx[pairable, , drop = FALSE], categories = vals,
       dropped = sum(!pairable))
}

#' Merge the coders' factor levels into one order.
#'
#' Each coder's levels must keep their relative order in the merged order, so
#' levels low, high and low, mid, high merge to low, mid, high. The merge is a
#' topological sort of the "comes before" pairs within each coder's levels,
#' taking ties in order of first appearance. For the ordinal level the order
#' must be fixed by the coders' levels: conflicting orders (low, high and
#' high, low) or levels with no order between them (low, mid and low, high)
#' are an error. For other levels the order only names the categories, so
#' ties and conflicts fall back to order of first appearance.
#' @noRd
merge_levels <- function(lev_list, level) {
  all_lev <- unique(unlist(lev_list))
  if (length(lev_list) < 2L || length(unique(lev_list)) == 1L) return(all_lev)
  k <- length(all_lev)
  before <- matrix(FALSE, k, k)
  for (lv in lev_list) {
    i <- match(lv, all_lev)
    if (length(i) > 1L) before[cbind(i[-length(i)], i[-1L])] <- TRUE
  }
  out <- integer(0)
  left <- seq_len(k)
  while (length(left)) {
    free <- left[colSums(before[left, left, drop = FALSE]) == 0]
    if (level == "ordinal" && length(free) != 1L) {
      gr_abort(paste0(
        "The coders' factors carry levels that do not fix one order for the ordinal level (",
        paste(vapply(lev_list, paste, character(1), collapse = " < "), collapse = "; "),
        "). Give every coder a factor with the same levels in the same order."),
        class = "gr_bad_setting")
    }
    if (!length(free)) return(all_lev)
    out <- c(out, free[1L])
    left <- setdiff(left, free[1L])
  }
  all_lev[out]
}

#' Krippendorff's alpha from a matrix of category indices.
#'
#' Follows Krippendorff (2011): each pairable unit u with m_u values adds
#' 1 / (m_u - 1) to the coincidence cell of every ordered pair of its values,
#' n_c are the margins and n their total, and
#'   alpha = 1 - (n - 1) sum o_ck d_ck / sum n_c n_k d_ck
#' with d the squared difference of the level. Each unit's contribution is
#' kept as a row of `per_unit`, so a bootstrap replicate is a weighted sum of
#' rows.
#' @noRd
kripp_alpha <- function(values, level = "nominal", categories = NULL) {
  values <- as.matrix(values)
  if (is.null(categories)) {
    categories <- sort(unique(as.vector(values[!is.na(values)])))
    values <- matrix(match(values, categories), nrow = nrow(values))
  }
  K <- length(categories)
  per_unit <- matrix(0, nrow(values), K * K)
  for (u in seq_len(nrow(values))) {
    v <- values[u, ]; v <- v[!is.na(v)]
    mu <- length(v)
    if (mu < 2L) next
    cnt <- tabulate(v, K)
    o <- (outer(cnt, cnt) - diag(cnt, K)) / (mu - 1)
    per_unit[u, ] <- as.vector(o)
  }
  delta <- kripp_delta(categories, level, colSums(matrix(colSums(per_unit), K, K)))
  res <- kripp_from_o(colSums(per_unit), K, delta, level, categories)
  c(res, list(per_unit = per_unit, n_items = sum(rowSums(per_unit) > 0),
              K = K, level = level, categories = categories))
}

#' Alpha and percent agreement from a flattened coincidence matrix.
#' @noRd
kripp_from_o <- function(o_vec, K, delta, level, categories) {
  o <- matrix(o_vec, K, K, dimnames = list(categories, categories))
  nc <- rowSums(o); n <- sum(o)
  # The ordinal metric depends on the margins, so a resample recomputes it.
  if (level == "ordinal") delta <- kripp_delta(categories, level, nc)
  de <- sum(outer(nc, nc) * delta)
  alpha <- if (n > 1 && de > 1e-12) 1 - (n - 1) * sum(o * delta) / de else NA_real_
  list(alpha = alpha, po = if (n > 0) sum(diag(o)) / n else NA_real_, coincidence = o,
       delta = delta)
}

#' Squared difference function of Krippendorff (2011) for one level.
#' @noRd
kripp_delta <- function(categories, level, nc) {
  K <- length(categories)
  switch(level,
    nominal = 1 - diag(K),
    ordinal = {
      cs <- cumsum(nc)
      d <- matrix(0, K, K)
      for (c in seq_len(K)) for (k in seq_len(K)) {
        lo <- min(c, k); hi <- max(c, k)
        d[c, k] <- ((cs[hi] - if (lo > 1) cs[lo - 1] else 0) - (nc[c] + nc[k]) / 2)^2
      }
      d
    },
    interval = outer(categories, categories, "-")^2,
    ratio = {
      s <- outer(categories, categories, "+")
      ifelse(s == 0, 0, (outer(categories, categories, "-") / s)^2)
    })
}

#' Percentile bootstrap interval for alpha, resampling items.
#' @noRd
kripp_boot <- function(ka, B, conf, seed) {
  units <- which(rowSums(ka$per_unit) > 0)
  pu <- ka$per_unit[units, , drop = FALSE]
  nu <- length(units)
  counts <- with_private_rng(seed, stats::rmultinom(B, nu, rep(1 / nu, nu)))
  ovecs <- crossprod(pu, counts)
  al <- apply(ovecs, 2L, function(o) {
    kripp_from_o(o, ka$K, ka$delta, ka$level, ka$categories)$alpha
  })
  if (all(is.na(al))) return(c(NA_real_, NA_real_))
  a <- 1 - conf
  stats::quantile(al, c(a / 2, 1 - a / 2), names = FALSE, na.rm = TRUE, type = 7)
}
