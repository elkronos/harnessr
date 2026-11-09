# core-stats-alttest.R: may a model's labels stand in for people's?

# The epsilon rule of thumb of Calderon, Reichart and Dror (2025), by the
# expertise of the human annotators being replaced.
.hr_alt_epsilon <- c(expert = 0.2, skilled = 0.15, crowd = 0.1)

#' The alternative annotator test
#'
#' Tests whether a model's labels can be used in place of human annotators,
#' with the leave-one-out procedure of Calderon, Reichart and Dror (2025) as
#' implemented in their reference code (github.com/nitaytech/alttest).
#'
#' For each human annotator j in turn, on every item j labelled:
#' 1. score the model's label against the labels of the other annotators of
#'    that item, and score j's label the same way (`metric`: the share of
#'    them it matches for `"accuracy"`, minus the root mean squared difference
#'    for `"neg_rmse"`);
#' 2. W_model = 1 where the model's score is at least j's, W_human = 1 where
#'    j's is at least the model's (a tie counts for both);
#' 3. test H0: mean(W_human - W_model) >= epsilon against the one-sided
#'    alternative that it is below epsilon, with a one-sample t test. Rejecting
#'    says the model is not worse than j by more than epsilon.
#'
#' The p-values of all annotators are corrected with Benjamini-Yekutieli at
#' level `q`. The winning rate omega is the share of annotators for whom the
#' test rejects, and the model passes when omega >= 0.5. The advantage
#' probability rho is the mean of W_model over items, averaged over
#' annotators: how often the model represents the others at least as well as
#' the person it replaces.
#'
#' epsilon is the penalty paid by the human annotators for being slower and
#' dearer. The authors' rule of thumb sets it by their expertise: 0.2 for
#' experts, 0.15 for skilled annotators such as trained students, 0.1 for
#' crowd workers, and lower than that when the people agree poorly with each
#' other. `expertise` has no default so the choice is always made on purpose.
#' Because the verdict depends on epsilon, omega is also reported for each
#' epsilon from 0.05 to 0.20 in steps of 0.05.
#'
#' Requirements: at least 3 human annotators (the authors accept 2 but advise
#' 3, since with two the test only asks which of them the model resembles),
#' and at least 30 items with a model label and two or more human labels,
#' where the t test's normal approximation starts to hold; fewer is an error.
#' Below 50 items there is a warning, as the authors recommend 50 to 100.
#' An annotator with fewer than 30 such items is left out of the test, as in
#' the reference code, and the result names them.
#'
#' A t statistic is undefined when W_human - W_model is constant. Then the
#' p-value is 0 when that constant is below epsilon and 1 otherwise, the limit
#' of the test as the spread goes to zero.
#'
#' @param model_labels The model's label for each item: a vector with one
#'   value per row of `human_labels`, `NA` where it gave none.
#' @param human_labels A matrix or data frame, items in rows and human
#'   annotators in columns, `NA` where an annotator did not label an item.
#'   Column names, when given, must be unique and non-empty; they name the
#'   rows of `per_annotator`.
#' @param expertise The annotators' expertise: `"expert"`, `"skilled"` or
#'   `"crowd"`. Required.
#' @param epsilon The cost-benefit margin. `NULL` takes it from `expertise`.
#' @param q False discovery rate for the Benjamini-Yekutieli correction.
#' @param metric `"accuracy"` for categorical labels, `"neg_rmse"` for
#'   numeric ones.
#' @return An object of class `hr_alt_test`, a list with `passed`, `omega`,
#'   `rho`, `epsilon`, `expertise`, `q`, `metric`, `n_items`,
#'   `per_annotator` (a data frame: `annotator`, `n`, `rho_model`,
#'   `rho_human`, `p_value`, `p_adjusted`, `rejected`), `sweep` (a data frame
#'   of `epsilon`, `omega` and `passed`), `skipped` and `notes`.
#' @references
#' Calderon, N., Reichart, R. and Dror, R. (2025). The alternative annotator
#' test for LLM-as-a-judge: how to statistically justify replacing human
#' annotators with LLMs. *Proceedings of the 63rd Annual Meeting of the
#' Association for Computational Linguistics*, 16051-16081.
#'
#' Benjamini, Y. and Yekutieli, D. (2001). The control of the false discovery
#' rate in multiple testing under dependency. *Annals of Statistics* 29(4),
#' 1165-1188.
#' @family statistics
#' @export
#' @examples
#' set.seed(3)
#' gold <- sample(c("a", "b", "c"), 80, replace = TRUE)
#' noisy <- function(p) ifelse(runif(80) < p, gold, sample(c("a", "b", "c"), 80, TRUE))
#' people <- sapply(1:4, function(j) noisy(0.75))
#' hr_alt_test(noisy(0.95), people, expertise = "skilled")
hr_alt_test <- function(model_labels, human_labels, expertise, epsilon = NULL, q = 0.05,
                        metric = c("accuracy", "neg_rmse")) {
  metric <- match.arg(metric)
  if (missing(expertise) || !is.character(expertise) || length(expertise) != 1L ||
      !expertise %in% names(.hr_alt_epsilon)) {
    gr_abort("`expertise` is required: one of \"expert\", \"skilled\" or \"crowd\".",
             class = "gr_bad_setting")
  }
  if (is.null(epsilon)) epsilon <- .hr_alt_epsilon[[expertise]]
  if (!is.numeric(epsilon) || length(epsilon) != 1L || is.na(epsilon) || epsilon < 0 || epsilon >= 1) {
    gr_abort("`epsilon` must be one number in [0, 1).", class = "gr_bad_setting")
  }
  if (!is.numeric(q) || length(q) != 1L || is.na(q) || q <= 0 || q >= 1) {
    gr_abort("`q` must be one number strictly between 0 and 1.", class = "gr_bad_setting")
  }
  if (!is.matrix(human_labels) && !is.data.frame(human_labels)) {
    gr_abort("`human_labels` must be a matrix or data frame, items in rows and annotators in columns.",
             class = "gr_bad_setting")
  }
  H <- as.data.frame(human_labels, stringsAsFactors = FALSE)
  if (ncol(H) < 3L) {
    gr_abort(sprintf("The test needs at least 3 human annotators; `human_labels` has %d.", ncol(H)),
             class = "gr_bad_setting")
  }
  if (length(model_labels) != nrow(H)) {
    gr_abort(sprintf("`model_labels` must have one label per row of `human_labels` (%d), not %d.",
                     nrow(H), length(model_labels)), class = "gr_bad_setting")
  }
  ids <- if (is.null(colnames(human_labels))) paste0("annotator_", seq_len(ncol(H))) else
    colnames(human_labels)
  # Each annotator's results are keyed by its name, so a repeated or empty
  # name would drop an annotator from the test without a word.
  bad_ids <- is.na(ids) | !nzchar(ids)
  if (any(bad_ids) || anyDuplicated(ids)) {
    what <- if (any(bad_ids)) sprintf("%d empty name(s)", sum(bad_ids)) else
      sprintf("repeated name(s): %s", paste(unique(ids[duplicated(ids)]), collapse = ", "))
    gr_abort(sprintf("Every annotator column of `human_labels` needs a unique, non-empty name; found %s.",
                     what), class = "gr_bad_setting")
  }
  if (metric == "neg_rmse") {
    ok_num <- function(v) is.numeric(v) || all(is.na(v))
    if (!ok_num(model_labels) || !all(vapply(H, ok_num, logical(1)))) {
      gr_abort("The neg_rmse metric needs numeric labels.", class = "gr_bad_setting")
    }
    M <- as.matrix(H); m <- as.numeric(model_labels)
  } else {
    M <- vapply(H, as.character, character(nrow(H)))
    M <- matrix(M, nrow = nrow(H))
    m <- as.character(model_labels)
  }
  usable <- !is.na(m) & rowSums(!is.na(M)) >= 2L
  n_items <- sum(usable)
  if (n_items < 30L) {
    gr_abort(sprintf("The test needs at least 30 items with a model label and two or more human labels; there are %d.",
                     n_items), class = "gr_bad_setting")
  }
  notes <- character(0)
  if (n_items < 50L) {
    msg <- sprintf("Only %d usable items; 50 to 100 are recommended for the test to have power.", n_items)
    gr_warn(msg, class = "gr_small_sample")
    notes <- c(notes, msg)
  }
  M <- M[usable, , drop = FALSE]; m <- m[usable]
  score <- function(pred, others) {
    if (metric == "accuracy") mean(pred == others) else -sqrt(mean((pred - others)^2))
  }
  # The paired differences per annotator do not depend on epsilon, so they are
  # computed once and reused for the sweep.
  diffs <- list(); rows <- list(); skipped <- character(0)
  for (j in seq_len(ncol(M))) {
    items <- which(!is.na(M[, j]))
    if (length(items) < 30L) {
      skipped <- c(skipped, ids[j])
      next
    }
    wm <- wh <- numeric(length(items))
    for (t in seq_along(items)) {
      i <- items[t]
      others <- M[i, -j]; others <- others[!is.na(others)]
      sh <- score(M[i, j], others); sm <- score(m[i], others)
      wm[t] <- as.numeric(sm >= sh); wh[t] <- as.numeric(sh >= sm)
    }
    diffs[[ids[j]]] <- wh - wm
    rows[[ids[j]]] <- data.frame(annotator = ids[j], n = length(items), rho_model = mean(wm),
                                 rho_human = mean(wh), stringsAsFactors = FALSE)
  }
  if (length(skipped)) {
    notes <- c(notes, sprintf("Left out for labelling fewer than 30 usable items: %s.",
                              paste(skipped, collapse = ", ")))
  }
  if (length(diffs) < 3L) {
    gr_abort(sprintf("Only %d annotator(s) labelled 30 or more usable items; the test needs 3.",
                     length(diffs)), class = "gr_bad_setting")
  }
  run <- function(eps) {
    p <- vapply(diffs, alt_pvalue, numeric(1), epsilon = eps)
    adj <- stats::p.adjust(p, method = "BY")
    list(p = p, adj = adj, rejected = adj <= q)
  }
  main <- run(epsilon)
  per <- do.call(rbind, rows)
  per$p_value <- unname(main$p); per$p_adjusted <- unname(main$adj)
  per$rejected <- unname(main$rejected)
  rownames(per) <- NULL
  omega <- mean(main$rejected)
  grid <- seq(0.05, 0.20, by = 0.05)
  sweep_omega <- vapply(grid, function(e) mean(run(e)$rejected), numeric(1))
  sweep <- data.frame(epsilon = grid, omega = sweep_omega, passed = sweep_omega >= 0.5)
  structure(list(passed = omega >= 0.5, omega = omega, rho = mean(per$rho_model),
                 epsilon = epsilon, expertise = expertise, q = q, metric = metric,
                 n_items = n_items, per_annotator = per, sweep = sweep, skipped = skipped,
                 notes = notes),
            class = "hr_alt_test")
}

#' One-sided p-value of the alternative annotator test for one annotator.
#'
#' H0: mean(d) >= epsilon, alternative mean(d) < epsilon, with d = W_human -
#' W_model, as scipy's ttest_1samp(d, epsilon, alternative = "less").
#' @noRd
alt_pvalue <- function(d, epsilon) {
  n <- length(d)
  s <- stats::sd(d)
  if (!is.finite(s) || s < 1e-12) return(if (mean(d) < epsilon) 0 else 1)
  stats::pt((mean(d) - epsilon) / (s / sqrt(n)), df = n - 1L)
}

#' @export
print.hr_alt_test <- function(x, digits = 3, ...) {
  cat(sprintf("<hr_alt_test> %s: omega = %s with epsilon = %g (%s annotators), q = %g\n",
              if (x$passed) "passed" else "not passed", format(round(x$omega, digits)),
              x$epsilon, x$expertise, x$q))
  cat(sprintf("%d items, metric %s, advantage probability rho = %s\n\n", x$n_items, x$metric,
              format(round(x$rho, digits))))
  per <- x$per_annotator
  num <- vapply(per, is.numeric, logical(1))
  per[num] <- lapply(per[num], function(v) signif(v, digits))
  print(per, row.names = FALSE)
  cat("\nomega by epsilon:\n")
  print(x$sweep, row.names = FALSE)
  for (n in x$notes) cat("Note:", n, "\n")
  invisible(x)
}
