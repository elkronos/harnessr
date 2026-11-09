# test-doc-stop.R: the hypergeometric stopping test for prioritised
# screening, against hand-computed hypergeometric probabilities.

# The test's p-value after t records, written out with choose() rather than
# phyper(): the smallest, over the last m records, of P(X <= k) for X drawn
# m at a time from N - t + m records of which K - r + k are relevant.
p_by_hand <- function(y, t, n_total, target) {
  r <- sum(y[1:t])
  k_tar <- floor(r / target + 1e-9) + 1
  if (k_tar - r > n_total - t) return(0)
  min(vapply(1:t, function(m) {
    k <- sum(y[(t - m + 1):t])
    urn <- n_total - t + m
    white <- k_tar - r + k
    sum(choose(white, 0:k) * choose(urn - white, m - 0:k)) / choose(urn, m)
  }, numeric(1)))
}

test_that("a small order gives the hand-computed hypergeometric p-value", {
  # 20 records; 5 relevant then 5 irrelevant screened. K = floor(5 / 0.95) + 1
  # = 6, so at least one relevant record is unscreened under the null. The
  # last five records hold none: P(X = 0) drawing 5 of 15 with 1 relevant is
  # C(14, 5) / C(15, 5) = 10 / 15. Longer windows take in relevant records and
  # give larger values (6 records: (C(14, 6) + 2 C(14, 5)) / C(16, 6) = 0.875).
  st <- gr_stop_test(c(rep(1, 5), rep(0, 5), rep(NA, 10)))
  expect_equal(st$steps$p_value[10], 2 / 3)
  expect_identical(st$n_total, 20L)
  expect_identical(st$n_screened, 10L)
  expect_true(is.na(st$stop_at))
  expect_output(print(st), "not yet safe to stop")
})

test_that("the stopping point matches a product of hypergeometric terms", {
  # 1,000 records: 100 relevant, then 400 irrelevant. K = floor(100 / 0.95)
  # + 1 = 106, so 6 relevant records would remain. The last 400 records hold
  # none: P(X = 0) = prod((500 - i) / (900 - i), i = 0..5) = 0.0290096.
  seen <- c(rep(1, 100), rep(0, 400), rep(NA, 500))
  st <- gr_stop_test(seen)
  expect_equal(st$steps$p_value[500], prod((500 - 0:5) / (900 - 0:5)))
  expect_equal(st$steps$p_value[500], 0.02900956, tolerance = 1e-6)
  # After t records the best window is the 0s since the last relevant
  # record, of length t - 100 out of 1000 - 100: the first t where
  # prod((900 - (t - 100) - i) / (900 - i)) drops under 0.05.
  first <- which(vapply(101:500, function(t) {
    prod((1000 - t - 0:5) / (900 - 0:5)) < 0.05
  }, logical(1)))[1] + 100L
  expect_identical(st$stop_at, first)
  expect_identical(st$stop_at, 453L)
  expect_true(all(!st$steps$reject[seq_len(452)]))
  expect_equal(st$relevant_at_stop, 100)
  expect_equal(st$work_saved, 1 - 453 / 1000)
  expect_true(is.na(st$recall_at_stop))
})

test_that("every step agrees with the choose() form on a mixed order", {
  y <- c(1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
  st <- gr_stop_test(y, target = 0.8, n_total = 30)
  hand <- vapply(seq_along(y), function(t) p_by_hand(y, t, 30, 0.8), numeric(1))
  expect_equal(st$steps$p_value, hand, tolerance = 1e-12)
  expect_identical(st$steps$relevant_found, cumsum(y))
})

test_that("p is 0 once too few records remain for recall to be under target", {
  # 19 relevant then one irrelevant, one record left. Recall under 0.95 needs
  # R >= 21 (19 / 20 is not under 0.95), so two would have to be unscreened.
  st <- gr_stop_test(c(rep(1, 19), 0, NA))
  expect_identical(st$steps$p_value[20], 0)
  expect_identical(st$stop_at, 20L)
  # Everything screened: nothing can be missing.
  done <- gr_stop_test(c(1, 0, 1, 0))
  expect_identical(done$steps$p_value[4], 0)
  expect_equal(done$recall_at_stop, 1)
})

test_that("a ranker result is tested over its simulated order", {
  texts <- c(vapply(1:10, function(i) paste("masks infection ward virus", i %% 3), ""),
             vapply(1:60, function(i) paste("budget policy school income", i %% 4), ""))
  r <- hr_baseline_ranker(texts, rep(c(TRUE, FALSE), c(10, 60)))
  st <- gr_stop_test(r)
  expect_identical(st$n_total, 70L)
  expect_equal(st$steps$relevant_found, r$curve$found)
  expect_false(is.na(st$stop_at))
  expect_equal(st$recall_at_stop, st$relevant_at_stop / 10)
  expect_output(print(st), "safe to stop after")
})

test_that("gr_stop_test checks its inputs", {
  expect_error(gr_stop_test(c(1, NA, 0)), class = "gr_bad_setting")
  expect_error(gr_stop_test(c(1, 2)), class = "gr_bad_setting")
  expect_error(gr_stop_test(c(1, 0), target = 1), class = "gr_bad_setting")
  expect_error(gr_stop_test(c(1, 0), alpha = 0), class = "gr_bad_setting")
  expect_error(gr_stop_test(c(1, 0), n_total = 1), class = "gr_bad_setting")
  expect_error(gr_stop_test(logical(0)), class = "gr_bad_setting")
})
