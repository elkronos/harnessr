# test-core-embed.R: vector comparison refuses mixed spaces, and BM25 scores
# are what the textbook formula gives.

test_that("cosine_similarity() errors on vectors of different lengths", {
  a <- rep(1, 64); b <- rep(1, 1536)
  expect_error(harnessr:::cosine_similarity(a, b), class = "hr_dim_mismatch")
  err <- tryCatch(harnessr:::cosine_similarity(a, b), error = identity)
  expect_identical(err$dims, c(64L, 1536L))
  expect_match(conditionMessage(err), "64 and 1536 dimensions", fixed = TRUE)
  expect_error(harnessr:::cosine_similarity(numeric(0), 1), class = "hr_dim_mismatch")
  # Equal lengths behave as before.
  expect_equal(harnessr:::cosine_similarity(c(1, 0, 0), c(1, 1, 0)), 1 / sqrt(2))
  expect_equal(harnessr:::cosine_similarity(c(0, 0), c(1, 1)), 0)
  expect_equal(harnessr:::cosine_similarity(NULL, 1), 0)
})

test_that("cosine_against() errors when the vector is not as wide as the matrix", {
  m <- matrix(runif(3 * 1536), nrow = 3)
  expect_error(harnessr:::cosine_against(m, rep(1, 512)), class = "hr_dim_mismatch")
  m2 <- rbind(c(1, 0), c(0, 1), c(0, 0))
  expect_equal(harnessr:::cosine_against(m2, c(1, 1)), c(1, 1, 0) / c(sqrt(2), sqrt(2), 1))
  expect_identical(harnessr:::cosine_against(m2[0, , drop = FALSE], c(1, 1)), numeric(0))
})

test_that("bm25_scores() matches the formula worked by hand", {
  docs <- c("revenue rose revenue", "costs fell", "revenue and costs", "")
  q <- "revenue costs"
  k1 <- 1.5; b <- 0.75
  terms <- lapply(docs, function(d) harnessr:::lexical_terms(d, min_chars = 2L))
  lens <- lengths(terms)
  avg <- mean(lens[lens > 0])
  N <- length(docs)
  idf <- function(t) {
    n <- sum(vapply(terms, function(d) t %in% d, logical(1)))
    log(1 + (N - n + 0.5) / (n + 0.5))
  }
  expected <- vapply(seq_along(docs), function(i) {
    if (!lens[i]) return(0)
    sum(vapply(c("revenue", "costs"), function(t) {
      f <- sum(terms[[i]] == t)
      if (!f) return(0)
      idf(t) * f * (k1 + 1) / (f + k1 * (1 - b + b * lens[i] / avg))
    }, numeric(1)))
  }, numeric(1))
  expect_equal(harnessr:::bm25_scores(docs, q), expected)
  expect_identical(harnessr:::bm25_scores(docs, ""), rep(0, 4))
  # A repeated query word counts once.
  expect_identical(harnessr:::bm25_scores(docs, "revenue revenue costs"),
                   harnessr:::bm25_scores(docs, q))
})

test_that("bm25_scores() counts each term's document frequency once", {
  # Counted inside the loop over documents, the membership tests grew with the
  # square of the number of documents; counted once per term they grow with
  # it. Doubling the documents should about double the calls, not quadruple
  # them. A ratio rather than a fixed bound, so other calls to `%in%` made per
  # document (in lexical_terms(), say) do not matter.
  calls <- function(n) {
    docs <- rep(c("alpha beta", "gamma delta", "alpha gamma"), length.out = n)
    ctr <- new.env()
    ctr$n <- 0L
    suppressMessages(trace("%in%", bquote(assign("n", get("n", .(ctr)) + 1L, envir = .(ctr))),
                           print = FALSE))
    s <- tryCatch(harnessr:::bm25_scores(docs, "alpha gamma zeta"),
                  finally = suppressMessages(untrace("%in%")))
    expect_length(s, n)
    ctr$n
  }
  small <- calls(400L)
  large <- calls(800L)
  expect_gt(small, 0L)
  expect_lt(large / small, 3)
})
