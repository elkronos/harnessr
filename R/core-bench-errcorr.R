# core-bench-errcorr.R: how far the errors of a benchmark's arms go
# together. Two arms that fail on the same items add less than their
# accuracies suggest when they are combined or used to check each other, and
# a high accuracy for each can hide that they share one blind spot.

#' Correlated errors between the arms of a benchmark
#'
#' Says how far the arms of an [hr_benchmark()] fail on the same items, and
#' with the same wrong answer, and draws a sample of the items every arm got
#' wrong for a person to check by hand. It reads only the benchmark's rows
#' and sends nothing.
#'
#' Each arm is reduced to one result per item: an error when it was wrong on
#' more than half of its scored runs of the item. Items with no label (every
#' `correct` `NA`) are left out.
#'
#' \describe{
#'   \item{Phi within difficulty strata}{For each pair of arms, the phi
#'     coefficient (the correlation of two 0/1 error indicators over the
#'     items) within each stratum of item difficulty. Two arms both wrong on
#'     the hard items are correlated for that reason alone; within a stratum
#'     of items of like difficulty, what is left is the shared blind spot.
#'     Difficulty is the share of all the arms' scored runs on an item that
#'     were wrong, cut into `n_strata` groups at its quantiles, unless
#'     `strata` gives each item's stratum (as [hr_reference()]'s `strata`
#'     do). `phi_pooled` is the mean of the strata's phi weighted by their
#'     items, over strata where phi is defined (both arms right on some items
#'     and wrong on others). Because difficulty is read from the same runs,
#'     the strata are a coarse adjustment, not an independent one.}
#'   \item{Same wrong answer}{For each pair, of the items both got wrong
#'     where both gave an answer (`outcome` not `NA`), the share where they
#'     gave the same wrong answer (each arm's most frequent wrong outcome on
#'     the item, compared after case and surrounding space are set aside). Kim
#'     et al. (2025, "Correlated errors in large language models") report
#'     this rate for models that share a provider or architecture.}
#'   \item{Hand-check sample}{Up to `n_check` items every arm got wrong,
#'     drawn at random with `seed`, with each arm's wrong outcome, for a
#'     person to read. Unanimous errors are where a label can be the thing
#'     that is wrong.}
#' }
#'
#' Yen's Q3, the residual correlation of a one-parameter item response model
#' fitted as a mixed model, is not computed: it would need a mixed-model
#' package (lme4) that harnessr does not depend on. `$q3` says so.
#'
#' @param bench An `hr_bench` from [hr_benchmark()] with at least two arms.
#' @param strata `NULL` to stratify by difficulty, or each item's stratum: a
#'   vector named by item, or one value per item in the order of
#'   `unique(bench$item)`.
#' @param n_strata How many difficulty strata, when `strata` is `NULL`: a
#'   whole number from 1 to 10, default 3. Fewer are made when the items take
#'   fewer distinct difficulties.
#' @param n_check How many items every arm got wrong to sample for a hand
#'   check: a whole number, 0 or more, default 10.
#' @param held_out `TRUE` (the default) reads only the rows that count as
#'   evidence (`reportable`, so not the dev split); `FALSE` reads every row.
#' @param seed The seed of the private random stream the sample is drawn
#'   with; the caller's random state is left as it was.
#' @return A list of class `hr_error_correlation`:
#'   \describe{
#'     \item{`phi`}{One row per pair of arms and stratum: `arm_a`, `arm_b`,
#'       `stratum`, `items`, `both_wrong`, `phi` (`NA` where undefined).}
#'     \item{`pairs`}{One row per pair of arms: `arm_a`, `arm_b`, `items`,
#'       `phi_pooled`, `both_wrong`, `both_answered` (of those, the items
#'       where both gave an outcome), `same_wrong` and `same_wrong_rate`.}
#'     \item{`check`}{The hand-check sample: `item` and one column per arm
#'       holding its wrong outcome.}
#'     \item{`all_wrong`}{How many items every arm got wrong.}
#'     \item{`strata`}{Each item's stratum, named by item.}
#'     \item{`q3`}{Why Yen's Q3 is not given.}
#'   }
#' @seealso [hr_benchmark()], [hr_report()], `vignette("evaluate")`
#' @export
#' @examples
#' ref <- hr_reference(sprintf("q%02d", 1:12), labels = rep("yes", 12),
#'                     cluster = sprintf("c%02d", 1:12), split = "test")
#' says <- function(wrong_on) hr_arm(paste0("wrong-", length(wrong_on)), function(item, ctx) {
#'   if (item %in% wrong_on) "no" else "yes"
#' })
#' arms <- list(says(c("q01", "q02", "q03")), says(c("q01", "q02", "q04")))
#' bench <- suppressWarnings(hr_benchmark(arms, ref, runs = 1, client = NULL))
#' ec <- hr_error_correlation(bench, n_strata = 1)
#' ec$pairs
#' ec$check
hr_error_correlation <- function(bench, strata = NULL, n_strata = 3L, n_check = 10L,
                                 held_out = TRUE, seed = 1L) {
  if (!inherits(bench, "hr_bench")) {
    gr_abort("`bench` must be an hr_bench from hr_benchmark().", class = "gr_bad_setting")
  }
  whole <- function(x, lo, hi) is.numeric(x) && length(x) == 1L && !is.na(x) &&
    x == round(x) && x >= lo && x <= hi
  if (!whole(n_strata, 1, 10)) {
    gr_abort("`n_strata` must be a whole number from 1 to 10.", class = "gr_bad_setting")
  }
  if (!whole(n_check, 0, Inf)) {
    gr_abort("`n_check` must be a whole number, 0 or more.", class = "gr_bad_setting")
  }
  if (!is.logical(held_out) || length(held_out) != 1L || is.na(held_out)) {
    gr_abort("`held_out` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  d <- as.data.frame(bench)
  if (isTRUE(held_out) && "reportable" %in% names(d)) d <- d[d$reportable %in% TRUE, , drop = FALSE]
  d <- d[!is.na(d$correct), , drop = FALSE]
  arms <- unique(as.character(d$arm))
  if (length(arms) < 2L) {
    gr_abort(paste0("Error correlation needs scored runs of at least two arms",
                    if (isTRUE(held_out)) "; with held_out = TRUE the dev split is left out" else "",
                    "."), class = "gr_bad_setting")
  }
  items <- unique(as.character(d$item))
  # One result per arm and item: wrong on more than half of its runs. And
  # its most frequent wrong outcome, for comparing wrong answers.
  wrong <- matrix(NA, length(items), length(arms), dimnames = list(items, arms))
  said <- matrix(NA_character_, length(items), length(arms), dimnames = list(items, arms))
  for (a in arms) {
    da <- d[d$arm == a, , drop = FALSE]
    for (it in unique(as.character(da$item))) {
      r <- da[da$item == it, , drop = FALSE]
      wrong[it, a] <- mean(!r$correct) > 0.5
      o <- as.character(r$outcome[!r$correct])
      o <- o[!is.na(o)]
      if (length(o)) said[it, a] <- names(sort(table(o), decreasing = TRUE))[1]
    }
  }
  # Difficulty strata, or the caller's.
  if (is.null(strata)) {
    difficulty <- vapply(items, function(it) mean(!d$correct[d$item == it]), numeric(1))
    cuts <- unique(stats::quantile(difficulty, seq(0, 1, length.out = n_strata + 1L),
                                   names = FALSE))
    st <- if (length(cuts) < 2L) rep("1", length(items))
          else as.character(cut(difficulty, cuts, include.lowest = TRUE, labels = FALSE))
    names(st) <- items
  } else {
    if (!is.null(names(strata))) st <- as.character(strata[items])
    else if (length(strata) == length(items)) st <- as.character(strata)
    else gr_abort("`strata` must be named by item, or give one value per item.",
                  class = "gr_bad_setting")
    names(st) <- items
    if (anyNA(st)) gr_abort("`strata` gives no stratum for some items.", class = "gr_bad_setting")
  }
  norm <- function(x) tolower(trimws(x))
  pairs <- utils::combn(arms, 2L, simplify = FALSE)
  phi_rows <- list(); pair_rows <- list()
  for (p in pairs) {
    both <- !is.na(wrong[, p[1]]) & !is.na(wrong[, p[2]])
    x <- wrong[both, p[1]]; y <- wrong[both, p[2]]; s <- st[both]
    per <- lapply(sort(unique(s)), function(k) {
      in_k <- s == k
      data.frame(arm_a = p[1], arm_b = p[2], stratum = k, items = sum(in_k),
                 both_wrong = sum(x[in_k] & y[in_k]), phi = phi_coef(x[in_k], y[in_k]),
                 stringsAsFactors = FALSE)
    })
    per <- do.call(rbind, per)
    phi_rows[[length(phi_rows) + 1L]] <- per
    ok <- !is.na(per$phi)
    bw <- both & wrong[, p[1]] %in% TRUE & wrong[, p[2]] %in% TRUE
    answered <- bw & !is.na(said[, p[1]]) & !is.na(said[, p[2]])
    same <- sum(norm(said[answered, p[1]]) == norm(said[answered, p[2]]))
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      arm_a = p[1], arm_b = p[2], items = sum(both),
      phi_pooled = if (any(ok)) sum(per$phi[ok] * per$items[ok]) / sum(per$items[ok])
                   else NA_real_,
      both_wrong = sum(bw), both_answered = sum(answered), same_wrong = same,
      same_wrong_rate = if (sum(answered)) same / sum(answered) else NA_real_,
      stringsAsFactors = FALSE)
  }
  all_wrong <- items[rowSums(!is.na(wrong)) == length(arms) &
                       rowSums(wrong %in% TRUE & !is.na(wrong)) == length(arms)]
  pick <- if (!length(all_wrong) || n_check == 0) character(0) else
    with_private_rng(seed, sample(all_wrong, min(length(all_wrong), n_check)))
  check <- data.frame(item = pick, stringsAsFactors = FALSE)
  for (a in arms) check[[a]] <- unname(said[pick, a])
  rownames(check) <- NULL
  structure(list(
    phi = { out <- do.call(rbind, phi_rows); rownames(out) <- NULL; out },
    pairs = { out <- do.call(rbind, pair_rows); rownames(out) <- NULL; out },
    check = check, all_wrong = length(all_wrong), strata = st,
    q3 = paste0("Not computed: Yen's Q3 needs a one-parameter item response model fitted ",
                "as a mixed model, which needs lme4, a package harnessr does not depend on.")),
    class = "hr_error_correlation")
}

#' The phi coefficient of two logical vectors: NA when either is constant.
#' @noRd
phi_coef <- function(x, y) {
  n11 <- sum(x & y); n00 <- sum(!x & !y); n10 <- sum(x & !y); n01 <- sum(!x & y)
  den <- sqrt(as.numeric(n11 + n10) * (n01 + n00) * (n11 + n01) * (n10 + n00))
  if (!is.finite(den) || den == 0) return(NA_real_)
  (as.numeric(n11) * n00 - as.numeric(n10) * n01) / den
}

#' @export
print.hr_error_correlation <- function(x, ...) {
  cat("<hr_error_correlation>", nrow(x$pairs), "pair(s) of arms,",
      length(unique(x$strata)), "stratum(s)\n")
  print(x$pairs, row.names = FALSE)
  cat(sprintf("%d item(s) every arm got wrong; %d in the hand-check sample.\n",
              x$all_wrong, nrow(x$check)))
  invisible(x)
}
