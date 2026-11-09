# hr_assign_splits(): whole clusters, the same answer from the same seed and
# ids whatever the row order, and shares as documented.

quiet <- function(expr) suppressWarnings(expr)

splits_items <- function() {
  # Clusters of unequal size, so a split that cut a cluster would show.
  sizes <- c(1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 2, 2, 7, 1, 3, 3, 4, 2)
  data.frame(item_id = sprintf("q%03d", seq_len(sum(sizes))),
             document = rep(sprintf("doc%02d.pdf", seq_along(sizes)), times = sizes),
             stringsAsFactors = FALSE)
}

test_that("every cluster lands whole in one split, with either method", {
  qa <- splits_items()
  for (m in c("stable", "balanced")) {
    sp <- hr_assign_splits(qa, seed = 11, method = m)
    per_doc <- tapply(sp$items$split, sp$items$document, function(s) length(unique(s)))
    expect_true(all(per_doc == 1L))
    expect_equal(sum(sp$counts$items), nrow(qa))
    expect_equal(sum(sp$counts$clusters), 20L)
    expect_setequal(sp$items$split, sp$clusters$split)
  }
})

test_that("the assignment follows from the seed and the ids alone", {
  qa <- splits_items()
  a <- hr_assign_splits(qa, seed = 11)
  shuffled <- qa[c(seq(2, nrow(qa), 2), seq(1, nrow(qa), 2)), ]
  b <- hr_assign_splits(shuffled, seed = 11)
  expect_identical(b$items$split[match(qa$item_id, b$items$item_id)], a$items$split)
  expect_identical(hr_assign_splits(qa, seed = 11), a)
  # Integer and double seeds of the same value agree.
  expect_identical(hr_assign_splits(qa, seed = 11L)$items$split, a$items$split)
  # No random numbers are drawn, so the caller's stream is untouched.
  set.seed(5)
  before <- .Random.seed
  hr_assign_splits(qa, seed = 11, method = "balanced")
  expect_identical(.Random.seed, before)
  # Another seed moves at least one document.
  expect_false(identical(quiet(hr_assign_splits(qa, seed = 12))$clusters$split, a$clusters$split))
})

test_that("cluster numbers are pinned to literal values", {
  # SHA-256 of "harnessr-split", the seed and the id; these must not change
  # between platforms or releases, or recorded splits could not be redrawn.
  # Two clusters leave two splits empty, which warns; that is tested below.
  u <- quiet(hr_assign_splits(c("a", "b"), cluster = c("doc01.pdf", "doc02.pdf"),
                              seed = 2026))$clusters$u
  expect_equal(u, c(0.2937642922665411, 0.15299630091951322), tolerance = 1e-15)
  u2 <- quiet(hr_assign_splits("x", cluster = "\u00e9vora.pdf", seed = "abc"))$clusters$u
  expect_equal(u2, 0.63242082987006176, tolerance = 1e-15)
  sp <- quiet(hr_assign_splits(c("a", "b"), cluster = c("doc01.pdf", "doc02.pdf"), seed = 2026))
  # 0.294 falls in calibration (0.2 to 0.5), 0.153 in exploratory (0.1 to 0.2).
  expect_identical(sp$items$split, c("calibration", "exploratory"))
})

test_that("a stable split does not move documents when others are added", {
  qa <- splits_items()
  small <- qa[qa$document %in% sprintf("doc%02d.pdf", 1:8), ]
  a <- quiet(hr_assign_splits(small, seed = 3))
  b <- hr_assign_splits(qa, seed = 3)
  expect_identical(b$items$split[match(small$item_id, b$items$item_id)], a$items$split)
})

test_that("a balanced split gives each split its share of clusters by largest remainders", {
  ten <- hr_assign_splits(sprintf("i%d", 1:10), cluster = sprintf("d%d", 1:10), seed = 1,
                          method = "balanced")
  expect_identical(ten$counts$clusters, c(1L, 1L, 3L, 5L))
  # Seven clusters: quotas 0.7, 0.7, 2.1, 3.5; whole parts 0, 0, 2, 3; the two
  # left over go to the largest remainders, dev and exploratory.
  seven <- hr_assign_splits(sprintf("i%d", 1:7), cluster = sprintf("d%d", 1:7), seed = 1,
                            method = "balanced")
  expect_identical(seven$counts$clusters, c(1L, 1L, 2L, 3L))
  # Clusters are taken in order of their number, so the dev cluster has the
  # smallest.
  cl <- seven$clusters
  expect_identical(cl$split[which.min(cl$u)], "dev")
  expect_identical(cl$split[which.max(cl$u)], "test")
})

test_that("ids, clusters and shares are read the documented ways", {
  v <- quiet(hr_assign_splits(c("x1", "x2", "x3"), cluster = c("A", "A", "B"), seed = 9,
                              props = c(test = 0.5, final = 0.5)))
  expect_named(v$items, c("item_id", "cluster", "split"))
  expect_identical(v$items$split[1], v$items$split[2])
  expect_true(all(v$items$split %in% c("test", "final")))

  df <- data.frame(id = c("x1", "x2", "x3"), grp = c("A", "A", "B"), cluster = c("Z", "Y", "X"))
  by_col <- quiet(hr_assign_splits(df, cluster = "grp", seed = 9,
                                  props = c(test = 0.5, final = 0.5)))
  expect_identical(by_col$items$split, v$items$split)
  # Without `cluster`, a data frame's own cluster column is used.
  expect_identical(quiet(hr_assign_splits(df, seed = 9))$clusters$cluster, c("Z", "Y", "X"))

  solo <- quiet(hr_assign_splits(c("x1", "x2"), seed = 9))
  expect_identical(solo$clusters$cluster, c("x1", "x2"))
  expect_true(any(grepl("own cluster", solo$notes)))
  expect_output(print(solo), "hr_splits")
})

test_that("bad settings stop with gr_bad_setting", {
  qa <- splits_items()
  expect_error(hr_assign_splits(qa), class = "gr_bad_setting")
  expect_error(hr_assign_splits(qa, seed = NA), class = "gr_bad_setting")
  expect_error(hr_assign_splits(qa, seed = 1, props = c(dev = 0.5, test = 0.4)),
               "add up to 1", class = "gr_bad_setting")
  expect_error(hr_assign_splits(qa, seed = 1, props = c(dev = 0.5, tset = 0.5)),
               "tset", class = "gr_bad_setting")
  expect_error(hr_assign_splits(qa, seed = 1, props = c(dev = -0.5, test = 1.5)),
               class = "gr_bad_setting")
  expect_error(hr_assign_splits(c("a", "a"), cluster = c("d", "e"), seed = 1),
               "more than once", class = "gr_bad_setting")
  expect_error(hr_assign_splits(c("a", "b"), cluster = c("d", NA), seed = 1),
               "no cluster", class = "gr_bad_setting")
  expect_error(hr_assign_splits(qa, cluster = "nope", seed = 1), "nope",
               class = "gr_bad_setting")
  # A cluster of blanks names the item it belongs to.
  expect_error(hr_assign_splits(c("a", "b"), cluster = c("x", "  "), seed = 1),
               "Item 'b' has no cluster", class = "gr_bad_setting")
  # On a one-row frame a misspelt column name is still an error, and a
  # literal cluster value goes in I().
  d1 <- data.frame(item_id = "a", document = "z")
  expect_error(hr_assign_splits(d1, cluster = "zz", seed = 1), "no column 'zz'",
               class = "gr_bad_setting")
  one <- quiet(hr_assign_splits(d1, cluster = I("zz"), seed = 1))
  expect_identical(one$clusters$cluster, "zz")
})

test_that("a split given a share and no cluster is a warning and a note", {
  expect_warning(sp <- hr_assign_splits(c("a", "b"), cluster = c("d1", "d2"), seed = 1,
                                        method = "balanced"),
                 class = "hr_empty_split")
  expect_true(any(grepl("received no cluster", sp$notes)))
  expect_identical(sum(sp$counts$clusters == 0L), 2L)
})
