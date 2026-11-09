# core-bench-baseline.R: baselines that use no model calls.
#
# A comparison that only pits model configurations against each other can miss
# that a plain classifier trained on a few hundred labels does as well. These
# baselines are the floor every confirmatory report is read against: tf-idf
# features, a ridge-penalised logistic regression cross-fitted on the
# reference, and a simulated active-learning ranker for screening. All of it
# is base R and stats, so the floor is always available.

# ---- tf-idf -----------------------------------------------------------------

#' Lower-cased runs of letters and digits, one character vector per text.
#'
#' Bytes that are not valid UTF-8 become spaces rather than stopping the
#' regex; missing texts become empty documents.
#' @noRd
baseline_tokens <- function(texts) {
  x <- enc2utf8(as.character(texts))
  x[is.na(x)] <- ""
  bad <- !validUTF8(x)
  if (any(bad)) x[bad] <- iconv(x[bad], "UTF-8", "UTF-8", sub = " ")
  x[is.na(x)] <- ""
  x <- tolower(x)
  regmatches(x, gregexpr("[\\p{L}\\p{N}]+", x, perl = TRUE))
}

#' Stop unless `texts` is a character vector of at least `min` texts.
#' @noRd
check_texts <- function(texts, min = 2L) {
  if (!is.character(texts) || length(texts) < min) {
    gr_abort(sprintf("`texts` must be a character vector of at least %d texts.", min),
             class = "gr_bad_setting")
  }
  invisible(texts)
}

#' Stop unless `x` is one whole number of at least `min`.
#' @noRd
check_count <- function(x, what, min = 1L) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x < min ||
      x != round(x)) {
    gr_abort(sprintf("`%s` must be one whole number, at least %d.", what, min),
             class = "gr_bad_setting")
  }
  invisible(as.integer(x))
}

#' Vocabulary and inverse document frequencies from tokenised training texts.
#'
#' Terms in fewer than `min_df` texts are dropped. When more than
#' `max_features` remain, the most frequent across the set are kept (ties by
#' document frequency, then by the term in C-locale order, so the cut does not
#' depend on the session locale). The idf is the smoothed form
#' log((1 + n) / (1 + df)) + 1.
#' @noRd
tfidf_fit <- function(tokens, min_df, max_features) {
  n <- length(tokens)
  df <- table(unlist(lapply(tokens, unique), use.names = FALSE))
  vocab <- names(df)[df >= min_df]
  if (!length(vocab)) {
    gr_abort(sprintf(paste0("No term appears in at least %d of the %d texts, so there are no ",
                            "features. Lower `min_df` or give longer texts."), min_df, n),
             class = "hr_baseline_no_terms")
  }
  if (length(vocab) > max_features) {
    tot <- table(unlist(tokens, use.names = FALSE))[vocab]
    keep <- order(-as.numeric(tot), -as.numeric(df[vocab]), vocab, method = "radix")
    vocab <- vocab[keep[seq_len(max_features)]]
  }
  vocab <- sort(vocab, method = "radix")
  idf <- log((1 + n) / (1 + as.numeric(df[vocab]))) + 1
  names(idf) <- vocab
  idf
}

#' Row-normalised tf-idf matrix of tokenised texts over a fixed vocabulary.
#'
#' Counts are placed with one tabulate() over linear indices; a text with no
#' term from the vocabulary stays a row of zeros.
#' @noRd
tfidf_apply <- function(tokens, idf) {
  n <- length(tokens)
  vocab <- names(idf)
  v <- length(vocab)
  if (as.double(n) * v > .Machine$integer.max) {
    gr_abort(sprintf(paste0("A dense %d by %d matrix is too large. Lower `max_features` or ",
                            "split the texts."), n, v), class = "gr_bad_setting")
  }
  col <- match(unlist(tokens, use.names = FALSE), vocab)
  row <- rep.int(seq_len(n), lengths(tokens))
  ok <- !is.na(col)
  m <- matrix(tabulate((col[ok] - 1L) * n + row[ok], nbins = n * v), n, v,
              dimnames = list(NULL, vocab))
  m <- m * rep(idf, each = n)
  norm <- sqrt(rowSums(m^2))
  pos <- norm > 0
  m[pos, ] <- m[pos, , drop = FALSE] / norm[pos]
  m
}

#' Tf-idf features from texts
#'
#' Turns texts into an l2-normalised tf-idf matrix, the feature set the
#' baselines [hr_baseline_classifier()] and [hr_baseline_ranker()] use.
#'
#' * Tokens are runs of letters and digits after lower-casing (`"COVID-19"`
#'   gives `"covid"` and `"19"`). There is no stemming and no stop word list.
#' * A term is kept when it appears in at least `min_df` texts. If more than
#'   `max_features` terms pass, the most frequent across all texts are kept.
#' * The weight of term j in text i is tf(i, j) * idf(j), where tf is the raw
#'   count and idf(j) = log((1 + n) / (1 + df(j))) + 1, with n texts and df(j)
#'   the number of texts containing j. This is the smoothed idf of
#'   scikit-learn's `TfidfVectorizer`, which ASReview uses.
#' * Each row is then divided by its Euclidean norm. A text with no kept term
#'   is a row of zeros.
#'
#' The result is an ordinary dense base R matrix. That is fine at the sizes a
#' benchmark reference or a screening set has (a few thousand texts by at most
#' `max_features` terms is tens of megabytes); it is not meant for a corpus of
#' millions.
#'
#' @param texts Character vector of texts. `NA` is read as an empty text.
#' @param min_df Smallest number of texts a term must appear in.
#' @param max_features Largest number of terms kept.
#' @return A numeric matrix with one row per text (named by `names(texts)`
#'   when present) and one column per term, in C-locale order. The idf
#'   weights are attached as the named vector `attr(, "idf")`.
#' @references
#' Salton, G. and Buckley, C. (1988). Term-weighting approaches in automatic
#' text retrieval. *Information Processing and Management* 24(5), 513-523.
#'
#' Pedregosa, F. et al. (2011). Scikit-learn: machine learning in Python.
#' *Journal of Machine Learning Research* 12, 2825-2830.
#' @family baselines
#' @export
#' @examples
#' m <- hr_tfidf(c("Masks cut infection.", "Masks and handwashing.",
#'                 "Handwashing cut infection."))
#' round(m, 3)
#' attr(m, "idf")
hr_tfidf <- function(texts, min_df = 2, max_features = 5000) {
  check_texts(texts, min = 1L)
  min_df <- check_count(min_df, "min_df")
  max_features <- check_count(max_features, "max_features")
  tokens <- baseline_tokens(texts)
  idf <- tfidf_fit(tokens, min_df, max_features)
  m <- tfidf_apply(tokens, idf)
  rownames(m) <- names(texts)
  attr(m, "idf") <- idf
  m
}

# ---- ridge logistic regression ----------------------------------------------

#' Weighted ridge least squares with an unpenalised intercept.
#'
#' Minimises sum(w * (z - b0 - X b)^2) + lambda * sum(b^2). Centring X and z
#' by their weighted means profiles the intercept out exactly. With more
#' columns than rows the p by p system is replaced by an n by n one through
#' (lambda I + A'WA)^-1 A' = A' (lambda I + W A A')^-1, so a few hundred
#' labelled texts against thousands of terms costs a few hundred squared.
#' @noRd
weighted_ridge <- function(X, z, w, lambda) {
  sw <- sum(w)
  xm <- colSums(X * w) / sw
  zm <- sum(w * z) / sw
  Xc <- X - rep(xm, each = nrow(X))
  zc <- z - zm
  if (ncol(X) <= nrow(X)) {
    A <- crossprod(Xc, Xc * w)
    diag(A) <- diag(A) + lambda
    beta <- drop(solve(A, crossprod(Xc, w * zc)))
  } else {
    M <- tcrossprod(Xc) * w
    diag(M) <- diag(M) + lambda
    beta <- drop(crossprod(Xc, solve(M, w * zc)))
  }
  list(b0 = zm - sum(xm * beta), beta = beta)
}

#' Penalised negative log-likelihood of a logistic model.
#' @noRd
ridge_objective <- function(eta, y, beta, lambda) {
  softplus <- pmax(eta, 0) + log1p(exp(-abs(eta)))
  sum(softplus - y * eta) + lambda / 2 * sum(beta^2)
}

#' Ridge-penalised logistic regression by iteratively reweighted least squares.
#'
#' Maximises sum(log-likelihood) - lambda / 2 * sum(beta^2), intercept not
#' penalised. Each step is the weighted ridge fit to the working response
#' z = eta + (y - mu) / w with w = mu (1 - mu), which is the Newton step for
#' this objective; a step that raises the objective is halved until it does
#' not, so the fit cannot diverge on separable data. `start` warm-starts from
#' an earlier fit, which the ranker uses after each batch.
#' @noRd
ridge_logistic <- function(X, y, lambda, start = NULL, maxit = 100L, tol = 1e-8) {
  if (is.null(start)) {
    b0 <- stats::qlogis(min(max(mean(y), 1e-4), 1 - 1e-4))
    beta <- numeric(ncol(X))
  } else {
    b0 <- start$b0
    beta <- start$beta
  }
  eta <- drop(b0 + X %*% beta)
  obj <- ridge_objective(eta, y, beta, lambda)
  iter <- 0L
  for (iter in seq_len(maxit)) {
    mu <- stats::plogis(eta)
    w <- pmax(mu * (1 - mu), 1e-10)
    fit <- weighted_ridge(X, eta + (y - mu) / w, w, lambda)
    step <- 1
    repeat {
      nb0 <- b0 + step * (fit$b0 - b0)
      nbeta <- beta + step * (fit$beta - beta)
      neta <- drop(nb0 + X %*% nbeta)
      nobj <- ridge_objective(neta, y, nbeta, lambda)
      if (nobj <= obj + 1e-12 * abs(obj) || step < 1e-6) break
      step <- step / 2
    }
    done <- abs(obj - nobj) <= tol * (abs(nobj) + tol)
    b0 <- nb0; beta <- nbeta; eta <- neta; obj <- nobj
    if (done) break
  }
  list(b0 = b0, beta = beta, iterations = iter, objective = obj)
}

#' Predicted probabilities from a ridge_logistic() fit.
#' @noRd
ridge_predict <- function(fit, X) stats::plogis(drop(fit$b0 + X %*% fit$beta))

#' Multinomial naive Bayes on non-negative features, as P(relevant).
#'
#' Term weights per class are the summed feature values plus Laplace
#' smoothing `alpha`, normalised; the class prior is the training share.
#' @noRd
nb_fit <- function(X, y, alpha = 1) {
  pos <- colSums(X[y == 1, , drop = FALSE]) + alpha
  neg <- colSums(X[y == 0, , drop = FALSE]) + alpha
  list(w = log(pos / sum(pos)) - log(neg / sum(neg)),
       b0 = log(mean(y)) - log(1 - mean(y)))
}

#' @noRd
nb_predict <- function(fit, X) stats::plogis(drop(fit$b0 + X %*% fit$w))

# ---- labels and folds -------------------------------------------------------

#' Labels as a factor with at least two levels and no missing values.
#' @noRd
baseline_labels <- function(labels, n) {
  if (length(labels) != n) {
    gr_abort(sprintf("`labels` has %d values for %d texts.", length(labels), n),
             class = "gr_bad_setting")
  }
  if (anyNA(labels)) gr_abort("`labels` must not contain NA.", class = "gr_bad_setting")
  f <- if (is.factor(labels)) droplevels(labels) else factor(as.character(labels))
  if (nlevels(f) < 2L) {
    gr_abort("`labels` must have at least two distinct values.", class = "gr_bad_setting")
  }
  f
}

#' Assign each item to a fold, under the private seed.
#'
#' Without clusters, items are shuffled within each label and dealt to the
#' folds in turn, so every fold has close to the overall label mix. With
#' clusters, whole clusters are shuffled and dealt, so no cluster is split
#' between training and test.
#' @noRd
baseline_folds <- function(labels, cluster, folds, seed) {
  n <- length(labels)
  with_private_rng(seed, {
    if (is.null(cluster)) {
      idx <- unlist(lapply(split(seq_len(n), labels), function(i) i[sample.int(length(i))]),
                    use.names = FALSE)
      out <- integer(n)
      out[idx] <- rep_len(seq_len(folds), n)
      out
    } else {
      ids <- unique(cluster)
      ids <- ids[sample.int(length(ids))]
      rep_len(seq_len(folds), length(ids))[match(cluster, ids)]
    }
  })
}

# ---- classifier -------------------------------------------------------------

#' Cross-fitted text classifier baseline
#'
#' A ridge-penalised logistic regression on tf-idf features, fitted fold by
#' fold so that every prediction comes from a model that never saw the item.
#' Its accuracy is the floor a model configuration has to beat: a classifier
#' trained on the same labels costs no model calls.
#'
#' **Folds.** Items are dealt to `folds` folds under `seed`. Without
#' `cluster`, the deal is stratified by label. With `cluster` (a document id,
#' a source), whole clusters are dealt, so items that share a cluster are never
#' split between training and test; with fewer clusters than `folds`, there is
#' one fold per cluster. For each fold, the vocabulary and idf weights are
#' fitted on the training texts only ([hr_tfidf()] with `min_df` and
#' `max_features`) and applied to the held-out texts, so no word statistics
#' from a test text reach its model.
#'
#' **Model.** For two labels, one logistic regression of the second level
#' against the first. Its coefficients maximise
#' sum_i log L_i - (lambda / 2) * sum_j beta_j^2, with the intercept not
#' penalised, fitted by iteratively reweighted least squares (each step a
#' weighted ridge solve on the working response; Hastie, Tibshirani and
#' Friedman 2009, section 4.4) with step halving. `lambda = 1` is the same
#' penalty as scikit-learn's `LogisticRegression` default (`C = 1`). For more
#' than two labels, one model per label against the rest, with the
#' probabilities divided by their sum; a label missing from a training fold
#' gets probability 0 there. The predicted label is the most probable one,
#' the first in level order on a tie.
#'
#' **Accuracy.** The share of items whose predicted label equals the given
#' one, with a Wilson interval from [hr_prop_ci()]. The interval treats items
#' as independent; with `cluster`, read it as too narrow when clusters are
#' large, and use the out-of-fold predictions in a benchmark report for a
#' clustered interval.
#'
#' @param texts Character vector, one text per item.
#' @param labels The label of each item: a factor, character, logical or
#'   numeric vector with at least two distinct values and no `NA`.
#' @param folds Number of folds, at least 2.
#' @param cluster Optional cluster of each item; folds then keep clusters
#'   whole.
#' @param seed Seed for the fold deal, run on a private random stream so the
#'   session's stream does not move.
#' @param lambda Ridge penalty, a positive number.
#' @param min_df,max_features Passed to the tf-idf fit of each fold.
#' @return An `hr_baseline_classifier`, a list with:
#'   * `predictions`: one row per item with `item` (position), `id`
#'     (`names(texts)`, or the position), `fold`, `label`, `predicted` and
#'     `correct`.
#'   * `prob`: the out-of-fold probability matrix, one column per label.
#'   * `folds`: one row per fold with `fold`, `n_train`, `n_test` and
#'     `n_terms`.
#'   * `train_items`: the training item positions of each fold.
#'   * `accuracy`: the [hr_prop_ci()] row for the out-of-fold accuracy.
#'   * `classes`, `settings` and `note`.
#' @references
#' Hastie, T., Tibshirani, R. and Friedman, J. (2009). *The Elements of
#' Statistical Learning*, 2nd edition. Springer.
#'
#' le Cessie, S. and van Houwelingen, J. C. (1992). Ridge estimators in
#' logistic regression. *Applied Statistics* 41(1), 191-201.
#' @family baselines
#' @export
#' @examples
#' texts <- c(paste("trial randomised placebo", c("adults", "children", "elderly")),
#'            paste("survey interview opinion", c("adults", "children", "elderly")),
#'            paste("randomised placebo trial", c("women", "men")),
#'            paste("opinion survey interview", c("women", "men")))
#' labels <- rep(c("trial", "survey", "trial", "survey"), c(3, 3, 2, 2))
#' fit <- hr_baseline_classifier(texts, labels, folds = 2)
#' fit
#' fit$predictions
hr_baseline_classifier <- function(texts, labels, folds = 5, cluster = NULL, seed = 1,
                                   lambda = 1, min_df = 2, max_features = 5000) {
  check_texts(texts)
  n <- length(texts)
  labels <- baseline_labels(labels, n)
  folds <- check_count(folds, "folds", min = 2L)
  check_positive(lambda, "lambda")
  min_df <- check_count(min_df, "min_df")
  max_features <- check_count(max_features, "max_features")
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    gr_abort("`seed` must be one number.", class = "gr_bad_setting")
  }
  note <- character()
  if (!is.null(cluster)) {
    if (length(cluster) != n || anyNA(cluster)) {
      gr_abort("`cluster` must have one non-missing value per text.", class = "gr_bad_setting")
    }
    n_clusters <- length(unique(cluster))
    if (n_clusters < 2L) {
      gr_abort("`cluster` must have at least two distinct values to make folds.",
               class = "gr_bad_setting")
    }
    if (n_clusters < folds) {
      note <- c(note, sprintf("%d clusters, so %d folds rather than %d", n_clusters,
                              n_clusters, folds))
      folds <- n_clusters
    }
  } else if (folds > n) {
    gr_abort(sprintf("`folds` (%d) is more than the number of texts (%d).", folds, n),
             class = "gr_bad_setting")
  }
  fold <- baseline_folds(labels, cluster, folds, seed)
  classes <- levels(labels)
  k <- length(classes)
  tokens <- baseline_tokens(texts)
  prob <- matrix(NA_real_, n, k, dimnames = list(NULL, classes))
  fold_rows <- vector("list", folds)
  train_items <- vector("list", folds)
  for (f in seq_len(folds)) {
    test <- which(fold == f)
    train <- which(fold != f)
    train_items[[f]] <- train
    idf <- tfidf_fit(tokens[train], min_df, max_features)
    Xtr <- tfidf_apply(tokens[train], idf)
    Xte <- tfidf_apply(tokens[test], idf)
    ytr <- labels[train]
    # A fold whose training part lacks a label predicts it with probability 0,
    # which can drive accuracy to 0 with no other sign of why.
    missing <- setdiff(classes, as.character(ytr))
    if (length(missing) > 0L) {
      note <- c(note, sprintf("fold %d trains without label(s) %s, so it cannot predict them",
                              f, paste(missing, collapse = ", ")))
    }
    one <- function(cls) {
      y <- as.numeric(ytr == cls)
      if (all(y == y[1])) return(rep(y[1], length(test)))
      ridge_predict(ridge_logistic(Xtr, y, lambda), Xte)
    }
    if (k == 2L) {
      p2 <- one(classes[2])
      p <- cbind(1 - p2, p2)
    } else {
      p <- vapply(classes, one, numeric(length(test)))
      p <- matrix(p, nrow = length(test))
      s <- rowSums(p)
      p[s > 0, ] <- p[s > 0, , drop = FALSE] / s[s > 0]
      p[s == 0, ] <- 1 / k
    }
    prob[test, ] <- p
    fold_rows[[f]] <- data.frame(fold = f, n_train = length(train), n_test = length(test),
                                 n_terms = length(idf))
  }
  predicted <- classes[max.col(prob, ties.method = "first")]
  correct <- predicted == as.character(labels)
  ids <- if (is.null(names(texts))) as.character(seq_len(n)) else names(texts)
  structure(list(
    predictions = data.frame(item = seq_len(n), id = ids, fold = fold,
                             label = as.character(labels), predicted = predicted,
                             correct = correct, stringsAsFactors = FALSE),
    prob = prob,
    folds = do.call(rbind, fold_rows),
    train_items = train_items,
    accuracy = hr_prop_ci(sum(correct), n),
    classes = classes,
    settings = list(folds = folds, clustered = !is.null(cluster), seed = seed,
                    lambda = lambda, min_df = min_df, max_features = max_features,
                    model = if (k == 2L) "ridge logistic" else "ridge logistic, one-vs-rest"),
    note = note
  ), class = "hr_baseline_classifier")
}

#' @rdname hr_baseline_classifier
#' @param x An `hr_baseline_classifier`.
#' @param ... Not used.
#' @export
print.hr_baseline_classifier <- function(x, ...) {
  a <- x$accuracy
  cat(sprintf("<hr_baseline_classifier> %s, %d labels, %d folds%s\n", x$settings$model,
              length(x$classes), x$settings$folds,
              if (x$settings$clustered) " by cluster" else ""))
  cat(sprintf("  accuracy: %.3f [%.3f, %.3f], %d of %d out of fold\n", a$est, a$lower,
              a$upper, as.integer(a$x), as.integer(a$n)))
  cat(sprintf("  training size per fold: %s\n",
              paste(x$folds$n_train, collapse = ", ")))
  for (nt in x$note) cat("  note:", nt, "\n")
  invisible(x)
}

# ---- ranker -----------------------------------------------------------------

#' Relevance labels as 0/1, for the ranker and the stopping test.
#' @noRd
relevance_labels <- function(labels, n = length(labels), what = "labels") {
  if (length(labels) != n) {
    gr_abort(sprintf("`%s` has %d values for %d texts.", what, length(labels), n),
             class = "gr_bad_setting")
  }
  if (anyNA(labels)) gr_abort(sprintf("`%s` must not contain NA.", what), class = "gr_bad_setting")
  if (is.logical(labels)) return(as.numeric(labels))
  if (is.numeric(labels) && all(labels %in% c(0, 1))) return(as.numeric(labels))
  gr_abort(sprintf("`%s` must be logical, or numeric 0 and 1 (1 = relevant).", what),
           class = "gr_bad_setting")
}

#' Records screened to reach a recall level, and work saved over reading all.
#'
#' n_r is the position of the ceiling(r * R)-th relevant record in the order;
#' WSS@r = (N - n_r) / N - (1 - r) (Cohen et al. 2006).
#' @noRd
wss_at <- function(relevant_in_order, r = 0.95) {
  n <- length(relevant_in_order)
  total <- sum(relevant_in_order)
  need <- ceiling(r * total - 1e-9)
  at <- which(cumsum(relevant_in_order) >= need)[1]
  list(n_screened = at, wss = (n - at) / n - (1 - r),
       random_n = need * (n + 1) / (total + 1))
}

#' Active-learning screening baseline
#'
#' Simulates prioritised screening over a set where every record's relevance
#' is already known, the way ASReview's simulation mode does: the result shows
#' how much reading a cheap ranker would have saved, which a model screener
#' has to beat.
#'
#' **Procedure.** Under `seed`, `seed_n[1]` relevant and `seed_n[2]`
#' irrelevant records are drawn as the prior knowledge and screened first, in
#' a random order. Then, until every record is screened: fit the model on the
#' records screened so far, score the rest, and screen the `batch` with the
#' highest predicted probability of relevance (ties broken by a seeded random
#' order). Features are [hr_tfidf()] over all texts, which uses no labels.
#' Once the last relevant record has been screened, the remaining records are
#' ordered by the last model without refitting, since their order changes no
#' figure reported here.
#'
#' **Models.** `"logistic"` is the ridge logistic regression of
#' [hr_baseline_classifier()] with penalty `lambda`, warm-started from the
#' previous fit. `"naive_bayes"` is multinomial naive Bayes on the tf-idf
#' weights with add-one smoothing (ASReview's default classifier is also
#' multinomial naive Bayes, with alpha = 3.822).
#'
#' **Measures.** `recall` is the share of relevant records found after each
#' screened record. `n_95` is the number screened when recall first reaches
#' 0.95 (the position of the ceiling(0.95 R)-th relevant record, R relevant in
#' all), and WSS@95 = (N - n_95) / N - 0.05 (Cohen et al. 2006): the share of
#' records left unread at 95% recall, less the 5% a random order would leave
#' at that recall. `random_n_95` is the expected n_95 of a random order,
#' k (N + 1) / (R + 1) with k = ceiling(0.95 R). The seed records count as
#' screened. WSS depends on prevalence, so compare it only between methods on
#' the same set.
#'
#' The simulation fits one model per batch, so its cost grows with
#' N / `batch` fits; raise `batch` for sets of several thousand.
#'
#' @param texts Character vector, one text per record.
#' @param labels Relevance of each record: logical, or numeric 0 and 1.
#' @param seed_n Number of relevant and irrelevant records known at the
#'   start, each at least 1.
#' @param batch Records screened between refits.
#' @param model `"logistic"` or `"naive_bayes"`.
#' @param seed Seed for the prior records and tie order, on a private random
#'   stream.
#' @param lambda Ridge penalty for `"logistic"`.
#' @param min_df,max_features Passed to [hr_tfidf()].
#' @return An `hr_baseline_ranker`, a list with `order` (record positions in
#'   screening order), `relevant` (their labels in that order), `curve` (a
#'   data frame of `n_screened`, `item`, `relevant`, `found` and `recall`),
#'   `n_95`, `wss_95`, `random_n_95`, `prior` (the seed records), `n_fits`,
#'   `n_total`, `n_relevant` and `settings`. [gr_stop_test()] accepts it
#'   directly.
#' @references
#' Cohen, A. M., Hersh, W. R., Peterson, K. and Yen, P.-Y. (2006). Reducing
#' workload in systematic review preparation using automated citation
#' classification. *Journal of the American Medical Informatics Association*
#' 13(2), 206-219.
#'
#' van de Schoot, R. et al. (2021). An open source machine learning framework
#' for efficient and transparent systematic reviews. *Nature Machine
#' Intelligence* 3, 125-133.
#' @family baselines
#' @export
#' @examples
#' set.seed(1)
#' topic <- function(words, n) {
#'   vapply(seq_len(n), function(i) paste(sample(words, 6, TRUE), collapse = " "), "")
#' }
#' texts <- c(topic(c("masks", "infection", "trial", "ward", "virus"), 10),
#'            topic(c("budget", "policy", "school", "survey", "income"), 50))
#' labels <- rep(c(TRUE, FALSE), c(10, 50))
#' r <- hr_baseline_ranker(texts, labels)
#' r
#' head(r$curve, 12)
hr_baseline_ranker <- function(texts, labels, seed_n = c(1, 1), batch = 1,
                               model = c("logistic", "naive_bayes"), seed = 1,
                               lambda = 1, min_df = 2, max_features = 5000) {
  check_texts(texts)
  n <- length(texts)
  y <- relevance_labels(labels, n)
  model <- match.arg(model)
  if (!is.numeric(seed_n) || length(seed_n) != 2L || anyNA(seed_n) || any(seed_n < 1) ||
      any(seed_n != round(seed_n))) {
    gr_abort("`seed_n` must be two whole numbers, each at least 1.", class = "gr_bad_setting")
  }
  if (seed_n[1] > sum(y == 1) || seed_n[2] > sum(y == 0)) {
    gr_abort(sprintf(paste0("`seed_n` asks for %d relevant and %d irrelevant records, but ",
                            "there are %d and %d."), seed_n[1], seed_n[2], sum(y == 1),
                     sum(y == 0)), class = "gr_bad_setting")
  }
  batch <- check_count(batch, "batch")
  check_positive(lambda, "lambda")
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    gr_abort("`seed` must be one number.", class = "gr_bad_setting")
  }
  X <- hr_tfidf(texts, min_df = min_df, max_features = max_features)
  pick <- function(pool, k) pool[sample.int(length(pool), k)]
  drawn <- with_private_rng(seed, {
    prior <- c(pick(which(y == 1), seed_n[1]), pick(which(y == 0), seed_n[2]))
    list(prior = prior[sample.int(length(prior))], tie = sample.int(n))
  })
  order_out <- drawn$prior
  screened <- logical(n)
  screened[order_out] <- TRUE
  total <- sum(y)
  fit <- NULL
  n_fits <- 0L
  while (length(order_out) < n) {
    rest <- which(!screened)
    tr <- order_out
    if (is.null(fit) || sum(y[tr]) < total) {
      fit <- if (model == "logistic") {
        ridge_logistic(X[tr, , drop = FALSE], y[tr], lambda, start = fit)
      } else {
        nb_fit(X[tr, , drop = FALSE], y[tr])
      }
      n_fits <- n_fits + 1L
      take <- min(batch, length(rest))
    } else {
      take <- length(rest)
    }
    score <- if (model == "logistic") ridge_predict(fit, X[rest, , drop = FALSE])
             else nb_predict(fit, X[rest, , drop = FALSE])
    nxt <- rest[order(-score, drawn$tie[rest])][seq_len(take)]
    order_out <- c(order_out, nxt)
    screened[nxt] <- TRUE
  }
  rel <- y[order_out]
  found <- cumsum(rel)
  w <- wss_at(rel, 0.95)
  structure(list(
    order = order_out,
    relevant = rel,
    curve = data.frame(n_screened = seq_len(n), item = order_out, relevant = rel,
                       found = found, recall = found / total),
    n_95 = w$n_screened,
    wss_95 = w$wss,
    random_n_95 = w$random_n,
    prior = drawn$prior,
    n_fits = n_fits,
    n_total = n,
    n_relevant = total,
    settings = list(seed_n = as.integer(seed_n), batch = batch, model = model, seed = seed,
                    lambda = lambda, min_df = min_df, max_features = max_features)
  ), class = "hr_baseline_ranker")
}

#' @rdname hr_baseline_ranker
#' @param x An `hr_baseline_ranker`.
#' @param ... Not used.
#' @export
print.hr_baseline_ranker <- function(x, ...) {
  cat(sprintf("<hr_baseline_ranker> %s, %d records, %d relevant, %d fits\n",
              x$settings$model, x$n_total, x$n_relevant, x$n_fits))
  cat(sprintf("  95%% recall after %d records (random order: %.1f expected)\n", x$n_95,
              x$random_n_95))
  cat(sprintf("  WSS@95: %.3f\n", x$wss_95))
  invisible(x)
}
