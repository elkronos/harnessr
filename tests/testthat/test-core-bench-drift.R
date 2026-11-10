# test-core-bench-drift.R: hr_drift_check() against mock clients whose
# answers change for a known set of items.

# n_clusters clusters of `per` items; every label is "yes".
drift_ref <- function(n_clusters, per) {
  n <- n_clusters * per
  hr_reference(sprintf("q%03d", seq_len(n)), labels = rep("yes", n),
               cluster = rep(sprintf("doc%02d", seq_len(n_clusters)), each = per),
               split = "test")
}

# Answers "yes" except on the items in `wrong`, where it answers "no". With
# `p_right`, a named vector of chances by item, it answers "yes" at random
# with that chance on every call instead.
drift_client <- function(wrong = character(0), p_right = NULL) {
  gr_mock_client(function(messages, params) {
    item <- messages[[1]]$content
    if (!is.null(p_right)) return(if (stats::runif(1) < p_right[[item]]) "yes" else "no")
    if (item %in% wrong) "no" else "yes"
  })
}

drift_arm <- function() hr_arm("echo", function(item, ctx) ctx$call(item)$text)

# Room for every call of the larger references below, frozen and live.
roomy <- function() hr_governor(max_calls = 5000)

test_that("nothing changes: no drift, no excess flips, alert not crossed", {
  ref <- drift_ref(6, 4)
  arm <- drift_arm()
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client("q002"))
  d <- hr_drift_check(frozen, arm, alert = 0.05, client = drift_client("q002"),
                      reference = ref, B = 500)
  expect_s3_class(d, "hr_drift_check")
  expect_false(d$drift)
  expect_identical(d$accuracy$change, 0)
  expect_identical(d$accuracy$lower, 0)
  expect_identical(d$accuracy$upper, 0)
  expect_false(d$accuracy$detected)
  expect_identical(d$accuracy$p_value, 1)
  expect_identical(d$mcnemar$statistic, 0)
  expect_identical(d$mcnemar$p_value, 1)
  expect_true(d$mcnemar$agrees)
  expect_identical(d$instability$excess, 0)
  expect_false(d$instability$detected)
  expect_false(d$alert_crossed)
  expect_false(d$alert_not_ruled_out)
  expect_true(all(d$items$change == "same"))
  expect_identical(nrow(d$replicate_pairs), 10L)
  expect_identical(nrow(d$cross_pairs), 25L)
  expect_s3_class(d$live, "hr_bench")
  expect_output(print(d), "Drift: no; alert at 0.050: not crossed, ruled out")
})

test_that("a noisy arm rerun with fresh draws shows no drift", {
  ref <- drift_ref(30, 4)
  arm <- drift_arm()
  # Each item has its own chance of a right answer, the same before and
  # after: run-to-run flips but no change.
  p_right <- stats::setNames(rep(c(0.95, 0.8, 0.6, 1), 30), ref$ids)
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client(p_right = p_right),
                         seed = 11, governor = roomy())
  d <- hr_drift_check(frozen, arm, alert = 0.03, client = drift_client(p_right = p_right),
                      reference = ref, B = 1000, governor = roomy())
  # The live runs drew fresh answers, so frozen and live differ item by item.
  expect_identical(d$seed, 12)
  expect_gt(sum(d$items$change != "same"), 0)
  expect_gt(d$instability$replicate_flip, 0.1)
  expect_false(d$accuracy$detected)
  expect_false(d$instability$detected)
  expect_false(d$mcnemar$detected)
  expect_false(d$drift)
  # The interval is wider than the alert, so a change of 0.03 is not ruled
  # out, but none is shown.
  expect_false(d$alert_crossed)
  expect_true(d$alert_not_ruled_out)
  expect_output(print(d), "not crossed, but cannot be ruled out")
  expect_output(print(d), "moved item\\(s\\) had runs that disagreed")
  # The mean flip rate over frozen pairs is the mean replicate flip over
  # items, and the same holds for frozen-live pairs.
  expect_equal(mean(d$replicate_pairs$flip_rate), d$instability$replicate_flip)
  expect_equal(mean(d$cross_pairs$flip_rate), d$instability$cross_flip)
})

test_that("many lost items are drift, and the flips name exactly those items", {
  ref <- drift_ref(30, 4)
  arm <- drift_arm()
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client(), governor = roomy())
  lost <- ref$ids[seq(1, 120, by = 3)]
  d <- hr_drift_check(frozen, arm, alert = 0.1, client = drift_client(lost),
                      reference = ref, B = 1000, governor = roomy())
  expect_true(d$drift)
  expect_equal(d$accuracy$change, -40 / 120)
  expect_true(d$accuracy$detected)
  expect_lt(d$accuracy$upper, 0)
  expect_true(d$mcnemar$detected)
  expect_true(d$mcnemar$agrees)
  expect_true(d$instability$detected)
  expect_gt(d$instability$lower, 0)
  expect_true(d$alert_crossed)
  expect_true(d$alert_not_ruled_out)
  expect_setequal(d$items$item[d$items$change == "lost"], lost)
  expect_true(all(d$items$change[!d$items$item %in% lost] == "same"))
  hit <- d$items[d$items$item %in% lost, ]
  expect_true(all(hit$frozen_outcome == "yes" & hit$live_outcome == "no"))
  expect_true(all(hit$cross_flip == 1 & hit$replicate_flip == 0))
  expect_output(print(d), "lost 40, gained 0")
})

test_that("losses and gains that cancel are caught by excess instability alone", {
  ref <- drift_ref(30, 4)
  arm <- drift_arm()
  # Frozen: wrong on every fourth item. Live: right there, wrong on the item
  # after it. Accuracy is unchanged, and half the items changed sides.
  was <- ref$ids[seq(1, 120, by = 4)]
  now <- ref$ids[seq(2, 120, by = 4)]
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client(was),
                         governor = roomy())
  d <- hr_drift_check(frozen, arm, client = drift_client(now), reference = ref, B = 1000,
                      governor = roomy())
  expect_identical(d$accuracy$change, 0)
  expect_false(d$accuracy$detected)
  expect_false(d$mcnemar$detected)
  expect_equal(d$instability$excess, 60 / 120)
  expect_true(d$instability$detected)
  expect_true(d$drift)
  expect_setequal(d$items$item[d$items$change == "gained"], was)
  expect_setequal(d$items$item[d$items$change == "lost"], now)
})

test_that("noisy items that turn deterministic are caught by excess instability", {
  ref <- drift_ref(30, 4)
  arm <- drift_arm()
  # Frozen: every item a coin flip. Live: half the items always right, half
  # always wrong. Accuracy stays near 0.5, and frozen-live flips alone match
  # the frozen flips in expectation, so only the live replicate flips (all
  # 0 now) show that every item changed, by (0.5 - q)^2 = 0.25 each.
  p_right <- stats::setNames(rep(0.5, 120), ref$ids)
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client(p_right = p_right),
                         seed = 3, governor = roomy())
  d <- hr_drift_check(frozen, arm, client = drift_client(ref$ids[seq(2, 120, by = 2)]),
                      reference = ref, B = 1000, governor = roomy())
  expect_false(d$accuracy$detected)
  expect_identical(d$instability$live_flip, 0)
  expect_true(all(d$items$live_flip == 0))
  y <- d$items
  expect_equal(y$excess, y$cross_flip - y$replicate_flip / 2)
  expect_gt(d$instability$excess, 0.15)
  expect_gt(d$instability$lower, 0)
  expect_true(d$instability$detected)
  expect_true(d$drift)
})

test_that("a single live run is refused", {
  ref <- drift_ref(4, 2)
  arm <- drift_arm()
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client())
  expect_error(hr_drift_check(frozen, arm, runs = 1, client = drift_client(), reference = ref),
               class = "gr_bad_setting")
})

test_that("the clustered McNemar test matches a hand computation", {
  # Four clusters of 3, 2, 3 and 2 items. Frozen right on 9 of 10 items,
  # live on 5. Cluster sums: frozen 3, 2, 2, 2; live 1, 2, 1, 1.
  # Residuals x - n p: frozen 0.3, 0.2, -0.7, 0.2; live -0.5, 1, -0.5, 0.
  # Their differences 0.8, -0.8, -0.2, 0.2 square to 1.36, so the variance
  # is 4 / 3 / 100 * 1.36 and X^2 = 0.4^2 / that = 150 / 17.
  ob <- harnessr:::obuchowski_test(c(3, 2, 2, 2), c(1, 2, 1, 1), c(3, 2, 3, 2))
  expect_equal(ob$statistic, 150 / 17)
  expect_equal(ob$p_value, 0.00297370943580994)

  ref <- hr_reference(sprintf("q%02d", 1:10), labels = rep("yes", 10),
                      cluster = rep(c("A", "B", "C", "D"), c(3, 2, 3, 2)), split = "test")
  arm <- drift_arm()
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client("q07"))
  d <- hr_drift_check(frozen, arm, client = drift_client(c("q02", "q03", "q06", "q07", "q10")),
                      reference = ref, B = 500)
  expect_equal(d$mcnemar$statistic, 150 / 17)
  expect_equal(d$mcnemar$p_value, 0.00297370943580994)
  expect_true(d$mcnemar$detected)
  expect_equal(d$accuracy$frozen, 0.9)
  expect_equal(d$accuracy$live, 0.5)
  # q07 was wrong before and is wrong now: no flip there.
  expect_identical(d$items$change[d$items$item == "q07"], "same")

  # A shared difference with no spread between clusters is conclusive, and
  # no difference is none.
  expect_identical(harnessr:::obuchowski_test(c(2, 2), c(1, 1), c(2, 2))$p_value, 0)
  expect_identical(harnessr:::obuchowski_test(c(2, 1), c(2, 1), c(2, 2))$p_value, 1)
  expect_true(is.na(harnessr:::obuchowski_test(3, 1, 3)$statistic))
})

test_that("fewer than 5 frozen runs is refused", {
  ref <- drift_ref(4, 2)
  arm <- drift_arm()
  expect_warning(frozen <- hr_benchmark(arm, ref, runs = 4, client = drift_client()),
                 class = "hr_few_runs")
  expect_error(hr_drift_check(frozen, arm, client = drift_client(), reference = ref),
               class = "hr_drift_few_runs")
})

test_that("another arm, reference or scorer, or a cached rerun, is refused", {
  ref <- drift_ref(4, 2)
  arm <- drift_arm()
  frozen <- hr_benchmark(arm, ref, runs = 5, client = drift_client())
  other <- hr_arm("echo", function(item, ctx) ctx$call(item)$text, version = "0.0.2")
  expect_error(hr_drift_check(frozen, other, client = drift_client(), reference = ref),
               class = "hr_drift_mismatch")
  expect_error(hr_drift_check(frozen, hr_arm("new", function(item, ctx) "yes"),
                              client = drift_client(), reference = ref),
               class = "hr_drift_mismatch")
  expect_error(hr_drift_check(frozen, arm, client = drift_client(),
                              reference = drift_ref(4, 3)),
               class = "hr_drift_mismatch")
  expect_error(hr_drift_check(frozen, arm, client = drift_client(), reference = ref,
                              scorer = hr_scorer(function(item, output, label) TRUE, "other")),
               class = "hr_drift_mismatch")
  expect_error(hr_drift_check(frozen, arm, alpha = 0.5, client = drift_client(),
                              reference = ref), class = "gr_bad_setting")
  expect_error(hr_drift_check(frozen, arm, alert = 1, client = drift_client(),
                              reference = ref), class = "gr_bad_setting")

  # A live client whose cache already holds the frozen replies answers from
  # it, which is the frozen sample again.
  dir <- tempfile("drift-cache")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  cached <- gr_cache_client(drift_client(), gr_cache(dir))
  frozen2 <- hr_benchmark(arm, ref, runs = 5, client = cached)
  expect_error(hr_drift_check(frozen2, arm, client = cached, reference = ref),
               class = "hr_drift_not_live")
})
