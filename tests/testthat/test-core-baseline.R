# test-core-baseline.R: tf-idf features, the ridge logistic fit, the
# cross-fitted classifier and the active-learning ranker.
#
# Synthetic texts are built from fixed word lists under harnessr's private
# seed, so every run sees the same sets and the session's stream does not move.

seeded <- function(seed, expr) harnessr:::with_private_rng(seed, expr)

# n texts per topic, each six words drawn from the topic's own words plus two
# shared ones, so the topics separate on vocabulary but share some terms.
topic_texts <- function(n_a, n_b, seed = 11) {
  seeded(seed, {
    a <- c("masks", "infection", "trial", "ward", "virus", "fever")
    b <- c("budget", "policy", "school", "survey", "income", "tax")
    shared <- c("study", "data", "report", "results")
    one <- function(words) paste(c(sample(words, 6, TRUE), sample(shared, 2)), collapse = " ")
    c(vapply(seq_len(n_a), function(i) one(a), ""), vapply(seq_len(n_b), function(i) one(b), ""))
  })
}

# ---- hr_tfidf ---------------------------------------------------------------

test_that("hr_tfidf weights match the smoothed idf and unit rows by hand", {
  m <- hr_tfidf(c(d1 = "Masks cut infection.", d2 = "Masks and handwashing.",
                  d3 = "Handwashing cut infection."))
  # "and" is in one text only, so min_df = 2 drops it. Every kept term is in
  # two of three texts: idf = log((1 + 3) / (1 + 2)) + 1.
  expect_identical(colnames(m), c("cut", "handwashing", "infection", "masks"))
  expect_identical(rownames(m), c("d1", "d2", "d3"))
  expect_equal(unname(attr(m, "idf")), rep(log(4 / 3) + 1, 4))
  expect_equal(unname(m[1, ]), c(1, 0, 1, 1) / sqrt(3))
  expect_equal(unname(m[2, ]), c(0, 1, 0, 1) / sqrt(2))
  expect_equal(unname(rowSums(m^2)), c(1, 1, 1))
})

test_that("hr_tfidf counts repeats, keeps the most frequent terms and leaves empty rows at 0", {
  m <- hr_tfidf(c("alpha alpha beta", "alpha beta gamma", "gamma", NA), min_df = 1)
  idf <- attr(m, "idf")
  # alpha and beta and gamma: df 2 of 4, so log(5 / 3) + 1 each.
  expect_equal(unname(idf), rep(log(5 / 3) + 1, 3))
  # Row 1 has counts (2, 1, 0) times equal idf, normalised.
  expect_equal(unname(m[1, ]), c(2, 1, 0) / sqrt(5))
  expect_equal(unname(m[4, ]), c(0, 0, 0))
  top <- hr_tfidf(c("alpha alpha beta", "alpha beta gamma", "gamma"), min_df = 1,
                  max_features = 1)
  expect_identical(colnames(top), "alpha")
})

test_that("hr_tfidf tokens are lower-cased runs of letters and digits", {
  toks <- harnessr:::baseline_tokens(c("COVID-19 and SARS-CoV-2.", "Café au lait", NA))
  expect_identical(toks[[1]], c("covid", "19", "and", "sars", "cov", "2"))
  expect_identical(toks[[2]], c("café", "au", "lait"))
  expect_identical(toks[[3]], character(0))
})

test_that("hr_tfidf with no term above min_df stops with hr_baseline_no_terms", {
  expect_error(hr_tfidf(c("one", "two")), class = "hr_baseline_no_terms")
  expect_error(hr_tfidf(c("a a", "a"), min_df = 0), class = "gr_bad_setting")
})

# ---- ridge logistic ---------------------------------------------------------

test_that("ridge_logistic with a tiny penalty matches glm", {
  x <- cbind(c(0.2, 1.1, -0.4, 0.8, -1.3, 0.5, 2.0, -0.7, 0.1, 1.6),
             c(1, 0, 1, 1, 0, 0, 1, 0, 1, 1))
  y <- c(0, 1, 0, 1, 0, 1, 1, 0, 1, 0)
  fit <- harnessr:::ridge_logistic(x, y, lambda = 1e-9)
  ref <- coef(glm(y ~ x, family = binomial()))
  expect_equal(c(fit$b0, fit$beta), unname(ref), tolerance = 1e-6)
})

test_that("ridge_logistic solves the penalised score equations, in both forms", {
  x <- seeded(5, matrix(runif(40), 8, 5))
  y <- c(1, 0, 1, 1, 0, 0, 1, 0)
  # Five columns and eight rows use the p by p system; nine columns and
  # eight rows use the n by n one.
  for (X in list(x, cbind(x, x[, 1:4] * 2))) {
    fit <- harnessr:::ridge_logistic(X, y, lambda = 0.7)
    mu <- plogis(drop(fit$b0 + X %*% fit$beta))
    expect_equal(sum(y - mu), 0, tolerance = 1e-8)
    expect_equal(drop(crossprod(X, y - mu)) - 0.7 * fit$beta, rep(0, ncol(X)),
                 tolerance = 1e-8)
  }
  # Separable data stays finite under the penalty.
  sep <- harnessr:::ridge_logistic(matrix(c(-2, -1, 1, 2), 4), c(0, 0, 1, 1), lambda = 1)
  expect_true(all(is.finite(c(sep$b0, sep$beta))))
})

# ---- hr_baseline_classifier -------------------------------------------------

test_that("the classifier separates a separable set out of fold", {
  texts <- topic_texts(40, 40)
  labels <- rep(c("health", "economy"), each = 40)
  fit <- hr_baseline_classifier(texts, labels)
  expect_s3_class(fit, "hr_baseline_classifier")
  expect_gte(fit$accuracy$est, 0.95)
  expect_identical(fit$accuracy$n, 80L)
  expect_identical(fit$classes, c("economy", "health"))
  expect_equal(unname(rowSums(fit$prob)), rep(1, 80))
  expect_identical(fit$folds$n_train + fit$folds$n_test, rep(80L, 5))
  expect_identical(fit$folds$n_train, rep(64L, 5))
  expect_output(print(fit), "accuracy: ")
})

test_that("no fold trains on its own test items, and clusters stay whole", {
  texts <- topic_texts(30, 30)
  labels <- rep(c(TRUE, FALSE), each = 30)
  cluster <- rep(sprintf("doc%02d", 1:20), each = 3)
  for (cl in list(NULL, cluster)) {
    fit <- hr_baseline_classifier(texts, labels, folds = 4, cluster = cl)
    fold <- fit$predictions$fold
    for (f in 1:4) {
      test <- which(fold == f)
      expect_length(intersect(fit$train_items[[f]], test), 0)
      expect_setequal(c(fit$train_items[[f]], test), 1:60)
      if (!is.null(cl)) expect_length(intersect(cl[fit$train_items[[f]]], cl[test]), 0)
    }
  }
})

test_that("cluster folds stop a model from scoring by memorising a cluster", {
  # Forty pairs. Both texts of a pair share a token no other pair has and the
  # pair's label, which is otherwise random. When a pair is split between
  # training and test, the shared token gives the label away; with the pair as
  # the cluster it never is, and accuracy falls to chance. min_df = 1, since a
  # pair token is in only one training text when its pair is split.
  labels <- rep(seeded(3, sample(rep(c("yes", "no"), 20))), each = 2)
  texts <- sprintf("pair%02d record entry", rep(1:40, each = 2))
  pair <- rep(1:40, each = 2)
  split <- hr_baseline_classifier(texts, labels, folds = 5, min_df = 1)
  whole <- hr_baseline_classifier(texts, labels, folds = 5, cluster = pair, min_df = 1)
  expect_gte(split$accuracy$est, 0.7)
  expect_lte(whole$accuracy$est, 0.6)
})

test_that("more than two labels are fitted one against the rest", {
  texts <- c(topic_texts(15, 15), vapply(1:15, function(i) {
    paste(c("river", "flood", "rain", "dam", "storm", "river")[c(i %% 6 + 1, 1:5)],
          collapse = " ")
  }, ""))
  labels <- rep(c("health", "economy", "weather"), each = 15)
  fit <- hr_baseline_classifier(texts, labels, folds = 3)
  expect_identical(fit$settings$model, "ridge logistic, one-vs-rest")
  expect_identical(colnames(fit$prob), c("economy", "health", "weather"))
  expect_equal(unname(rowSums(fit$prob)), rep(1, 45))
  expect_gte(fit$accuracy$est, 0.9)
})

test_that("the classifier leaves the session's random stream alone and checks its inputs", {
  texts <- topic_texts(10, 10)
  labels <- rep(0:1, each = 10)
  set.seed(9)
  before <- .Random.seed
  a <- hr_baseline_classifier(texts, labels, folds = 2, seed = 4)
  expect_identical(.Random.seed, before)
  b <- hr_baseline_classifier(texts, labels, folds = 2, seed = 4)
  expect_identical(a$predictions, b$predictions)
  few <- hr_baseline_classifier(texts, labels, folds = 5, cluster = rep(1:3, length.out = 20))
  expect_identical(few$settings$folds, 3L)
  expect_match(few$note, "3 clusters")
  # clusters that line up with the labels leave each training fold one label
  lined <- hr_baseline_classifier(texts, labels, folds = 2, cluster = labels)
  expect_match(lined$note, "fold [12] trains without label\\(s\\) 0,? so", all = FALSE)
  expect_match(lined$note, "fold [12] trains without label\\(s\\) 1,? so", all = FALSE)
  expect_error(hr_baseline_classifier(texts, rep(1, 20)), class = "gr_bad_setting")
  expect_error(hr_baseline_classifier(texts, labels[-1]), class = "gr_bad_setting")
  expect_error(hr_baseline_classifier(texts, labels, folds = 1), class = "gr_bad_setting")
  expect_error(hr_baseline_classifier(texts, labels, lambda = 0), class = "gr_bad_setting")
})

# ---- hr_baseline_ranker -----------------------------------------------------

test_that("WSS@95 and the records to reach 95% recall match a hand count", {
  # Ten records, relevant at positions 1, 2, 4 and 7. ceiling(0.95 * 4) = 4,
  # so 95% recall needs the fourth relevant record, at position 7:
  # WSS@95 = (10 - 7) / 10 - 0.05 = 0.25. A random order reaches the 4th of 4
  # relevant records at 4 * (10 + 1) / (4 + 1) = 8.8 on average.
  w <- harnessr:::wss_at(c(1, 1, 0, 1, 0, 0, 1, 0, 0, 0))
  expect_identical(w$n_screened, 7L)
  expect_equal(w$wss, 0.25)
  expect_equal(w$random_n, 8.8)
  # Twenty relevant: ceiling(19) is 19, not 20, despite 0.95 * 20 in floating
  # point.
  w20 <- harnessr:::wss_at(c(rep(1, 19), rep(0, 80), 1))
  expect_identical(w20$n_screened, 19L)
  expect_equal(w20$wss, 81 / 100 - 0.05)
})

test_that("the ranker beats a random order on a synthetic set", {
  texts <- topic_texts(15, 135, seed = 21)
  labels <- rep(c(TRUE, FALSE), c(15, 135))
  for (model in c("logistic", "naive_bayes")) {
    r <- hr_baseline_ranker(texts, labels, model = model)
    expect_s3_class(r, "hr_baseline_ranker")
    expect_setequal(r$order, 1:150)
    expect_length(r$order, 150)
    expect_identical(sort(labels[r$prior]), c(FALSE, TRUE))
    expect_identical(r$order[1:2], r$prior)
    expect_identical(r$relevant, as.numeric(labels[r$order]))
    expect_equal(tail(r$curve$recall, 1), 1)
    # A random order needs 15 * 151 / 16 = 141.6 records on average.
    expect_equal(r$random_n_95, 15 * 151 / 16)
    expect_lt(r$n_95, 30)
    expect_gt(r$wss_95, 0.7)
    expect_equal(r$wss_95, (150 - r$n_95) / 150 - 0.05)
  }
  expect_output(print(r), "WSS@95")
})

test_that("the ranker is reproducible, batches its refits and checks seed_n", {
  texts <- topic_texts(8, 32, seed = 2)
  labels <- rep(c(1, 0), c(8, 32))
  set.seed(1)
  before <- .Random.seed
  a <- hr_baseline_ranker(texts, labels, seed = 3)
  expect_identical(.Random.seed, before)
  expect_identical(hr_baseline_ranker(texts, labels, seed = 3)$order, a$order)
  b <- hr_baseline_ranker(texts, labels, batch = 5, seed_n = c(2, 3))
  expect_length(b$prior, 5)
  expect_identical(sum(labels[b$prior]), 2)
  expect_lte(b$n_fits, ceiling(35 / 5))
  expect_error(hr_baseline_ranker(texts, labels, seed_n = c(9, 1)), class = "gr_bad_setting")
  expect_error(hr_baseline_ranker(texts, labels, seed_n = c(0, 1)), class = "gr_bad_setting")
  expect_error(hr_baseline_ranker(texts, labels + 1), class = "gr_bad_setting")
})
