# test-core-signals.R: recording self-signals, calibrating them, and the gate.
#
# Reference values are written out by hand in the comments beside them, or
# come from qbeta() for the Clopper-Pearson bounds. Random draws run under
# harnessr's private seed so no test moves the session's random stream.

seeded <- function(seed, expr) harnessr:::with_private_rng(seed, expr)

sig_key <- function(...) {
  utils::modifyList(list(served_model = "mock-model-2026-01-01", version = "2026-01-01",
                         task = "qa", format = "md", prompt_hash = "p1", effort = NA,
                         module = "iterative"), list(...))
}

# A calibration record whose calibration half is exactly `d` (columns p and
# correct), so the gate can be checked against arithmetic on known counts.
cal_with_half <- function(d, grid, cluster = "c") {
  g <- data.frame(score = rep(c(0.9, 0.1), 10), correct = rep(c(TRUE, FALSE), 10),
                  answerable = rep(c(TRUE, FALSE), c(15, 5)))
  cal <- hr_calibrate_signal("demo", g, sig_key(), method = "none", seed = 1, B = 0)
  cal$data <- data.frame(item_id = as.character(seq_len(nrow(d))), cluster = cluster,
                         score = d$p, correct = d$correct, answerable = TRUE,
                         half = "calibration", p = d$p, stringsAsFactors = FALSE)
  cal$grid <- grid
  cal
}

# ---- recording ----------------------------------------------------------------

test_that("hr_signal records a local step and hr_signals reads it back", {
  tr <- gr_trace()
  s <- hr_signal("demo.flag", TRUE, tr, item_id = "q1", refs = list(round = 2L))
  expect_s3_class(s, "hr_signal")
  expect_equal(s$step, 1L)
  hr_signal("demo.score", c(0.25, 0.75), tr, item_id = c("q2", "q3"),
            refs = list(section = 1:2, kind = "x"))
  expect_equal(tr$calls, 0L)
  expect_equal(nrow(as.data.frame(tr)), 0L)
  expect_equal(tr$steps[[1]]$kind, "local")
  tab <- hr_signals(tr)
  expect_equal(tab$signal, c("demo.flag", "demo.score", "demo.score"))
  expect_equal(tab$item_id, c("q1", "q2", "q3"))
  expect_equal(tab$score, c(1, 0.25, 0.75))
  expect_equal(tab$value, c("TRUE", "0.25", "0.75"))
  expect_equal(tab$index, c(1L, 1L, 2L))
  expect_equal(tab$refs, c('{"round":2}', '{"section":1,"kind":"x"}', '{"section":2,"kind":"x"}'))
  expect_equal(nrow(hr_signals(tr, name = "demo.flag")), 1L)
  # A trace given twice in a list is read once.
  expect_equal(nrow(hr_signals(list(tr, tr))), 3L)
  # NULL records nothing and still returns the signal.
  expect_true(is.na(hr_signal("demo.flag", FALSE)$step))
  expect_error(hr_signal("demo", NA, tr), class = "gr_bad_setting")
  expect_error(hr_signal("demo", 1:3, tr, item_id = c("a", "b")), class = "gr_bad_setting")
  expect_equal(nrow(hr_signals(gr_trace())), 0L)
})

test_that("the iterative, preview and ensemble readers record their signals", {
  ch <- suppressMessages(gr_segment(gr_example(), list(method = "sentence", max_tokens = 150)))
  cl <- gr_mock_client(function(m, p) {
    sys <- as.character(m[[1]]$content)
    if (grepl("reading iteratively", sys, fixed = TRUE)) {
      return('{"can_answer": true, "answer": "45.2 million dollars.", "next_query": ""}')
    }
    if (grepl("You plan how to read a document", sys, fixed = TRUE)) {
      n <- as.integer(sub(".*each of the ([0-9]+) sections.*", "\\1",
                          as.character(m[[length(m)]]$content)))
      tr <- rep_len(c("read", "skip"), n)
      return(as.character(jsonlite::toJSON(list(sections = data.frame(
        id = seq_len(n), treatment = tr, reason = "r")), auto_unbox = TRUE)))
    }
    "Revenue was 45.2 million dollars."
  })
  it <- suppressMessages(gr_read(ch, "What was revenue?", cl, "iterative"))
  s <- hr_signals(it)
  expect_equal(s$signal, "gr.iterative.can_answer")
  expect_equal(s$value, "TRUE")
  expect_equal(s$refs, '{"round":1}')

  pv <- suppressWarnings(suppressMessages(gr_read(ch, "What was revenue?", cl, "preview")))
  s <- hr_signals(pv, name = "gr.preview.skip")
  n <- pv$notes$sections
  expect_equal(nrow(s), n)
  expect_equal(s$score, as.numeric(rep_len(c(FALSE, TRUE), n)))
  expect_equal(s$refs[1], '{"section":1,"treatment":"read"}')

  en <- suppressWarnings(suppressMessages(gr_read(ch, "What was revenue?", cl, "ensemble")))
  s <- hr_signals(en, name = "gr.ensemble.adjudicate")
  expect_equal(s$value, "model")
  expect_equal(s$refs, '{"members":2,"answered":2}')
})

# ---- metrics ------------------------------------------------------------------

test_that("the Brier decomposition matches a hand example and the identity holds", {
  # p = 0.2 for four items with one right, p = 0.8 for six with five right.
  # N = 10, mean y = 0.6.
  #   reliability = 0.4 * (0.2 - 0.25)^2 + 0.6 * (0.8 - 5/6)^2 = 1/600
  #   resolution  = 0.4 * (0.25 - 0.6)^2 + 0.6 * (5/6 - 0.6)^2 = 0.0816667 (= 49/600)
  #   uncertainty = 0.6 * 0.4 = 0.24
  #   Brier = (3 * 0.04 + 0.64 + 5 * 0.04 + 0.64) / 10 = 0.16
  p <- rep(c(0.2, 0.8), c(4, 6))
  y <- c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE)
  b <- harnessr:::brier_parts(p, y, harnessr:::mass_bins(p, 10L))
  expect_equal(b$brier, 0.16)
  expect_equal(b$reliability, 1 / 600)
  expect_equal(b$resolution, 49 / 600)
  expect_equal(b$uncertainty, 0.24)
  expect_equal(b$within_var, 0)
  expect_equal(b$within_cov, 0)

  # Continuous forecasts in equal-mass bins: the two within-bin terms close
  # the identity exactly.
  seeded(11, {
    p <- stats::runif(300)
    y <- stats::runif(300) < p^2
  })
  for (nb in c(5L, 10L)) {
    b <- harnessr:::brier_parts(p, y, harnessr:::mass_bins(p, nb))
    expect_equal(b$brier, b$reliability - b$resolution + b$uncertainty + b$within_var -
                   2 * b$within_cov, tolerance = 1e-12)
  }
})

test_that("AUROC2 and AURC match a hand example", {
  # Right items score 0.9, 0.8 and 0.6; wrong ones 0.7, 0.5 and 0.4.
  # Pairs with the right item above: 3 + 3 + 2 = 8 of 9.
  p <- c(0.9, 0.8, 0.7, 0.6, 0.5, 0.4)
  y <- c(TRUE, TRUE, FALSE, TRUE, FALSE, FALSE)
  expect_equal(harnessr:::auroc2(p, y), 8 / 9)
  # One right and one wrong at the same score: a tie counts half.
  expect_equal(harnessr:::auroc2(c(0.5, 0.5), c(TRUE, FALSE)), 0.5)
  # Accepted in order, errors 0 0 1 0 1 1: risks 0, 0, 1/3, 1/4, 2/5, 3/6.
  rc <- harnessr:::risk_curve(p, y)
  expect_equal(rc, c(0, 0, 1 / 3, 1 / 4, 2 / 5, 1 / 2))
  expect_equal(mean(rc), (1 / 3 + 1 / 4 + 2 / 5 + 1 / 2) / 6)
  # Tied scores enter together: two items at 0.9 with one error give an
  # expected risk of 0.5 at k = 1 and at k = 2.
  expect_equal(harnessr:::risk_curve(c(0.9, 0.9, 0.1), c(TRUE, FALSE, TRUE)),
               c(0.5, 0.5, 1 / 3))
})

test_that("ECE is near 0 for a perfectly calibrated signal", {
  g <- seeded(5, {
    p <- stats::runif(4000)
    data.frame(cluster = rep(1:400, each = 10), score = p, correct = stats::runif(4000) < p,
               answerable = rep(c(TRUE, FALSE), c(3000, 1000)))
  })
  cal <- hr_calibrate_signal("demo", g, sig_key(), method = "none", seed = 2, B = 0)
  ece <- cal$metrics$estimate[cal$metrics$metric == "ece"]
  expect_lt(ece, 0.02)
  # The plug-in error on the same bins sits at the noise floor instead,
  # about sqrt(sum w * p(1 - p) / n_k), roughly 0.03 here.
  half <- cal$data[cal$data$half == "calibration", ]
  bin <- harnessr:::mass_bins(half$p, 10L)
  plug <- sqrt(sum(tapply(seq_along(bin), bin, function(i) {
    length(i) / nrow(half) * (mean(half$p[i]) - mean(half$correct[i]))^2
  })))
  expect_gt(plug, ece)
  expect_equal(cal$bins, 10L)
})

test_that("Platt scaling improves an overconfident signal over no calibration", {
  g <- seeded(9, {
    q <- stats::runif(2000, 0.05, 0.95)
    data.frame(cluster = rep(1:200, each = 10),
               score = stats::plogis(3 * stats::qlogis(q)),
               correct = stats::runif(2000) < q,
               answerable = rep(c(TRUE, TRUE, TRUE, FALSE), 500))
  })
  platt <- hr_calibrate_signal("demo", g, sig_key(), seed = 4, B = 0)
  none <- hr_calibrate_signal("demo", g, sig_key(), method = "none", seed = 4, B = 0)
  # The same seed gives the same split.
  expect_identical(platt$data$half, none$data$half)
  m <- function(cal, k) cal$metrics$estimate[cal$metrics$metric == k]
  expect_lt(m(platt, "brier"), m(none, "brier"))
  expect_lt(m(platt, "ece"), m(none, "ece"))
  expect_gt(m(none, "ece"), 0.05)
  expect_equal(platt$map$method, "platt")
  expect_gt(platt$map$b, 0)
  # The split is by cluster: every cluster has items in both halves.
  per <- tapply(platt$data$half, platt$data$cluster, function(h) length(unique(h)))
  expect_true(all(per == 2L))
  # Fewer than 100 errors would leave the record advisory with a reason; here
  # there are plenty, and the only reason is the missing gate.
  expect_equal(platt$status, "advisory")
  expect_equal(platt$reasons, "no gate threshold has been set")
})

test_that("a signal that points the wrong way reads as one and stays advisory", {
  # The signal is higher when the item is wrong. Platt fits a negative slope,
  # which would turn the ranking of p the right way round; AUROC2 and AURC
  # are taken on the raw score, so the record shows the signal as it is.
  g <- seeded(4, {
    s <- stats::runif(600)
    data.frame(score = s, correct = stats::runif(600) < 1 - s,
               answerable = rep(c(TRUE, TRUE, FALSE), 200))
  })
  cal <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 0)
  expect_lt(cal$map$b, 0)
  m <- function(k) cal$metrics$estimate[cal$metrics$metric == k]
  half <- cal$data[cal$data$half == "calibration", ]
  expect_lt(m("auroc2"), 0.5)
  expect_equal(m("auroc2"), harnessr:::auroc2(half$score, half$correct))
  expect_equal(m("aurc"), mean(harnessr:::risk_curve(half$score, half$correct)))
  expect_true("the fitted map does not increase with the signal" %in% cal$reasons)
  gated <- hr_gate_threshold(cal, "stop", alpha = 0.5)
  expect_equal(gated$status, "advisory")
  expect_true("the fitted map does not increase with the signal" %in% gated$reasons)
})

test_that("one cluster gives no intervals and few clusters are noted", {
  g <- seeded(6, data.frame(cluster = "a", score = stats::runif(20),
                            correct = stats::runif(20) < 0.5,
                            answerable = rep(c(TRUE, FALSE), 10)))
  cal <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 50)
  expect_true(all(is.na(cal$metrics$lower)))
  expect_true(all(is.na(cal$metrics$upper)))
  expect_true(all(is.finite(cal$metrics$estimate)))
  expect_match(cal$notes, "one cluster")
  g$cluster <- rep(c("a", "b", "c", "d"), 5)
  few <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 50)
  expect_match(few$notes, "rest on 4 clusters")
  # Six items in the calibration half leave room for only three ECE bins.
  small <- hr_calibrate_signal("demo", g[1:12, ], sig_key(), seed = 1, B = 0)
  expect_lt(small$bins, 5L)
  expect_match(small$reasons[1], "ECE uses")
})

test_that("isotonic needs 1000 items and the graded set needs unanswerable items", {
  g <- data.frame(score = rep(c(0.9, 0.1), 50), correct = rep(c(TRUE, FALSE), 50),
                  answerable = rep(c(TRUE, FALSE), c(90, 10)))
  expect_error(hr_calibrate_signal("demo", g, sig_key(), method = "isotonic", seed = 1),
               class = "hr_bad_calibration")
  g$answerable <- TRUE
  expect_error(hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 0),
               class = "hr_bad_calibration")
  g$answerable <- rep(c(TRUE, FALSE), 50)
  expect_error(hr_calibrate_signal("demo", g, sig_key()), class = "gr_bad_setting")
  expect_error(hr_calibrate_signal("demo", g, list(task = "qa"), seed = 1),
               class = "gr_bad_setting")
  cal <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 50)
  # Two values of p (0.9 and 0.1) give 2 ECE bins, a reason of its own that
  # comes first; the error count is the next.
  expect_match(cal$reasons[1], "the ECE uses 2 bins")
  expect_match(cal$reasons[2], "fewer than the 100")
  expect_true(all(is.finite(cal$metrics$lower[cal$metrics$metric == "brier"])))
  js <- jsonlite::fromJSON(as_json(cal))
  expect_equal(js$signal, "demo")
  expect_equal(js$key$contract_version, harnessr:::hr_contract_version())
})

test_that("isotonic regression fits a non-decreasing map at 1000 items or more", {
  g <- seeded(3, {
    s <- stats::runif(1200)
    data.frame(score = s, correct = stats::runif(1200) < s, answerable = rep(c(TRUE, FALSE), 600))
  })
  cal <- hr_calibrate_signal("demo", g, sig_key(), method = "isotonic", seed = 1, B = 0)
  expect_false(is.unsorted(cal$map$y))
  # Pool adjacent violators on a hand example: 1, 3, 2 with equal weights
  # pools the last two to 2.5.
  expect_equal(harnessr:::pava(c(1, 3, 2), c(1, 1, 1)), c(1, 2.5, 2.5))
  expect_equal(harnessr:::pava(c(1, 3, 2), c(1, 1, 3)), c(1, 2.25, 2.25))
})

test_that("tied scores share an ECE bin, so the ECE ignores row order", {
  # Two values of p, 20 items each, rows grouped as documents would group
  # them. At p = 0.3, 12 of 20 are right (mean 0.6); at p = 0.8, 16 of 20
  # (mean 0.8). One bin per value, Kumar et al.'s debiased estimate:
  #   0.5 * ((0.3 - 0.6)^2 - 0.6 * 0.4 / 19) + 0.5 * ((0.8 - 0.8)^2 - 0.8 * 0.2 / 19)
  #   = 0.045 - 0.2 / 19 = 0.0344737, and sqrt(0.0344737) = 0.1856709.
  p <- rep(c(0.3, 0.8), each = 20)
  y <- c(rep(c(TRUE, FALSE), c(12, 8)), rep(c(TRUE, FALSE), c(16, 4)))
  e <- harnessr:::ece_debiased(p, y, 10L)
  expect_equal(e$ece, 0.18567090297223823, tolerance = 1e-12)
  expect_identical(e$bins, 2L)
  rev_e <- harnessr:::ece_debiased(rev(p), rev(y), 10L)
  expect_equal(rev_e$ece, e$ece, tolerance = 1e-14)
  # Calibrated at each value (6 of 20 right at 0.3, 16 of 20 at 0.8) the
  # estimate is 0: both terms are 0 minus a noise term, so the sum is below 0.
  y0 <- c(rep(c(TRUE, FALSE), c(6, 14)), rep(c(TRUE, FALSE), c(16, 4)))
  expect_identical(harnessr:::ece_debiased(p, y0, 10L)$ece, 0)
  # With more distinct values than bins, ties still share a bin. 40 items:
  # 0.05, 0.15, 0.25, 0.35 (ranks 1 to 4), 30 at 0.5 (ranks 5 to 34, average
  # 19.5), then 0.55 to 0.95 and 0.99 (ranks 35 to 40). The bin is
  # ceiling(rank * 10 / 40): 1 for ranks 1 to 4, 5 for 19.5, 9 for 35 and
  # 36, 10 for 37 to 40. Four bins, numbered 1 to 4 in order of p.
  q <- c(rep(0.5, 30), seq(0.05, 0.95, by = 0.1)[-5], 0.99)
  b <- harnessr:::mass_bins(q, 10L)
  expect_identical(b, c(rep(2L, 30), 1L, 1L, 1L, 1L, 3L, 3L, 4L, 4L, 4L, 4L))
  expect_identical(b, harnessr:::mass_bins(rev(q), 10L)[length(q):1])
})

test_that("a logical signal is measured over two bins and stays advisory", {
  # 200 documents of 10 items, a logical score, correctness shared within a
  # document; map "none" on the 0.3/0.8 recoding keeps two values of p.
  g <- seeded(1, {
    shift <- rep(stats::rnorm(200, 0, 0.15), each = 10)
    s <- rep(c(TRUE, FALSE), 1000)
    pr <- pmin(pmax(ifelse(s, 0.8, 0.3) + shift, 0), 1)
    data.frame(cluster = rep(1:200, each = 10), score = ifelse(s, 0.8, 0.3),
               correct = stats::runif(2000) < pr, answerable = rep(c(TRUE, FALSE), c(1500, 500)))
  })
  cal <- hr_calibrate_signal("demo", g, sig_key(), method = "none", seed = 1, B = 0)
  expect_identical(cal$bins, 2L)
  expect_match(cal$reasons[1], "the ECE uses 2 bins, fewer than 5")
  # The ECE is the per-value estimate, recomputed here from the half.
  h <- cal$data[cal$data$half == "calibration", ]
  s <- sum(vapply(split(seq_len(nrow(h)), h$p), function(i) {
    yk <- mean(h$correct[i])
    length(i) / nrow(h) * ((h$p[i[1]] - yk)^2 - yk * (1 - yk) / (length(i) - 1))
  }, numeric(1)))
  expect_equal(cal$metrics$estimate[cal$metrics$metric == "ece"], sqrt(max(0, s)),
               tolerance = 1e-12)
})

test_that("only the calibration split is calibrated on", {
  g <- seeded(3, {
    s <- stats::runif(400)
    data.frame(cluster = rep(1:40, each = 10), score = s, correct = stats::runif(400) < s,
               answerable = rep(c(TRUE, FALSE), 200),
               split = rep(c("calibration", "test", "dev", "calibration"), each = 100))
  })
  expect_message(cal <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 0),
                 "200 row\\(s\\) outside the calibration split were left out \\(dev 100, test 100\\)")
  # 400 rows, 200 of them in the calibration split.
  expect_identical(cal$n_items, 200L)
  expect_setequal(unique(cal$data$cluster), as.character(c(1:10, 31:40)))
  expect_identical(cal$notes[1], "200 row(s) outside the calibration split were left out (dev 100, test 100)")
  g$split <- "test"
  expect_error(hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 0),
               class = "hr_bad_calibration")
})

test_that("graded columns are read by exact name", {
  # No `cluster` column but a `cluster_size` one: each item is its own
  # cluster, 100 of them, not one cluster made of the value 10.
  g <- seeded(2, data.frame(cluster_size = 10, score = stats::runif(100),
                            correct = stats::runif(100) < 0.6,
                            answerable = rep(c(TRUE, FALSE), 50)))
  cal <- hr_calibrate_signal("demo", g, sig_key(), seed = 1, B = 20)
  expect_identical(cal$n_clusters, 100L)
  expect_false(any(grepl("one cluster", cal$notes)))
  # `scores` is not `score`, and `values` is not `value`.
  g2 <- data.frame(scores = 0.5, correct = TRUE, answerable = c(TRUE, FALSE))
  expect_error(hr_calibrate_signal("demo", g2, sig_key(), seed = 1, B = 0), "`score`")
})

test_that("two traces that share a run_id are both read", {
  t1 <- gr_trace(run_id = "pilot")
  t2 <- gr_trace(run_id = "pilot")
  hr_signal("s", TRUE, t1, item_id = "q1")
  hr_signal("s", FALSE, t2, item_id = "q2")
  tab <- hr_signals(list(t1, t2))
  expect_identical(tab$item_id, c("q1", "q2"))
  expect_identical(tab$value, c("TRUE", "FALSE"))
  # The same trace twice is still read once.
  expect_identical(nrow(hr_signals(list(t1, t2, t1))), 2L)
})

# ---- the gate -----------------------------------------------------------------

test_that("the Learn-then-Test threshold matches a hand computation", {
  # Calibration half: 60 items at p = 0.95, all right; 40 at 0.85 with 1
  # wrong; 100 at 0.75 with 5 wrong; 100 at 0.65 with 20 wrong.
  d <- data.frame(p = rep(c(0.95, 0.85, 0.75, 0.65), c(60, 40, 100, 100)),
                  correct = c(rep(TRUE, 60), rep(c(FALSE, TRUE), c(1, 39)),
                              rep(c(FALSE, TRUE), c(5, 95)), rep(c(FALSE, TRUE), c(20, 80))))
  cal <- cal_with_half(d, c(0.9, 0.8, 0.7, 0.6))
  # alpha = delta = 0.05: n_min = ceiling(log(0.05) / log(0.95)) = 59.
  #   t = 0.9: n = 60,  k = 0, ucb = 1 - 0.05^(1/60)    = 0.04870 pass
  #   t = 0.8: n = 100, k = 1, ucb = qbeta(0.95, 2, 99)  = 0.04656 pass
  #   t = 0.7: n = 200, k = 6, ucb = qbeta(0.95, 7, 194) = 0.05835 fail, stop
  out <- hr_gate_threshold(cal, "stop", alpha = 0.05)
  g <- out$gate
  expect_equal(g$n_min, 59)
  expect_equal(g$status, "passed")
  expect_equal(g$threshold, 0.8)
  expect_equal(c(g$n, g$k), c(100, 1))
  expect_equal(g$ucb, 0.0465598114535389, tolerance = 1e-12)
  expect_equal(g$path$ucb[1:3], c(0.0487029133100975, 0.0465598114535389, 0.0583497603759109),
               tolerance = 1e-12)
  expect_equal(g$path$tested, c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(g$path$passed, c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(g$coverage, 100 / 300)

  # Miss rate: the 26 wrong items are the denominator at every threshold. At
  # alpha = 0.05 that is fewer than 59, so no test can pass.
  expect_equal(hr_gate_threshold(cal, "exclude", "miss_rate", alpha = 0.05)$gate$status,
               "too few items")
  # At alpha = 0.2, n_min = 14:
  #   t = 0.9: k = 0, ucb = 1 - 0.05^(1/26)     = 0.10883 pass
  #   t = 0.8: k = 1, ucb = qbeta(0.95, 2, 25)  = 0.16983 pass
  #   t = 0.7: k = 6, ucb = qbeta(0.95, 7, 20)  = 0.40535 fail
  mr <- hr_gate_threshold(cal, "exclude", "miss_rate", alpha = 0.2)$gate
  expect_equal(mr$threshold, 0.8)
  expect_equal(mr$path$ucb[1:3], c(0.1088303557607848, 0.1698312230003834, 0.4053538344311661),
               tolerance = 1e-12)

  # The plan's two worked examples at alpha = 0.05: 0 errors in 59 passes
  # (ucb 0.04951), 9 errors in 300 fails (ucb 0.05177).
  ok <- hr_gate_threshold(cal_with_half(data.frame(p = rep(0.9, 59), correct = TRUE), 0.5),
                          "stop", alpha = 0.05)$gate
  expect_equal(ok$ucb, 0.0495076098882270, tolerance = 1e-12)
  expect_equal(ok$status, "passed")
  bad <- hr_gate_threshold(cal_with_half(data.frame(p = rep(0.9, 300),
                                                    correct = rep(c(FALSE, TRUE), c(9, 291))), 0.5),
                           "stop", alpha = 0.05)$gate
  expect_equal(bad$path$ucb, 0.0517660618994999, tolerance = 1e-12)
  expect_equal(bad$status, "none passed")
  expect_true(is.na(bad$threshold))
  # Fewer than 59 acted-on items at every threshold: the sequence never starts.
  few <- hr_gate_threshold(cal_with_half(data.frame(p = rep(0.9, 58), correct = TRUE), 0.5),
                           "stop", alpha = 0.05)$gate
  expect_equal(few$status, "too few items")
  expect_error(hr_gate_threshold(cal, "stop"), class = "gr_bad_setting")
})

test_that("the gate bound counts clustered errors through the design effect", {
  # 200 items at p = 0.9 in 10 documents of 20; documents 1 and 2 hold 6
  # wrong items each, the rest none: n = 200, k = 12, r = 0.06.
  #   cluster variance: 10/9 * (2 * (6 - 1.2)^2 + 8 * 1.2^2)   = 64
  #   item variance:   200/199 * (12 * 0.94^2 + 188 * 0.06^2) = 11.33668
  #   deff = 64 / 11.33668 = 796/141 = 5.645390
  #   ucb = qbeta(0.95, 12/deff + 1, 188/deff) = 0.172054, above 0.10.
  # Taken as 200 independent items, ucb = qbeta(0.95, 13, 188) = 0.095401,
  # which passed.
  d <- data.frame(p = 0.9, correct = !c(rep(c(TRUE, FALSE), c(6, 14)),
                                        rep(c(TRUE, FALSE), c(6, 14)), rep(FALSE, 160)))
  cl <- rep(sprintf("doc%02d", 1:10), each = 20)
  g <- hr_gate_threshold(cal_with_half(d, 0.5, cluster = cl), "stop", alpha = 0.10)$gate
  expect_equal(c(g$path$n, g$path$k), c(200, 12))
  expect_equal(g$path$deff, 796 / 141, tolerance = 1e-12)
  expect_equal(g$path$ucb, 0.17205393389065216, tolerance = 1e-10)
  expect_equal(g$status, "none passed")
  # The same counts with every item its own cluster: deff is exactly 1 and
  # the bound is Clopper-Pearson's.
  solo <- hr_gate_threshold(cal_with_half(d, 0.5, cluster = as.character(1:200)), "stop",
                            alpha = 0.10)$gate
  expect_equal(solo$deff, 1)
  expect_equal(solo$n_eff, 200)
  expect_equal(solo$ucb, 0.095401417729877314, tolerance = 1e-12)
  expect_equal(solo$status, "passed")
  # Miss rate: the 12 wrong items are the units, all acted on at t = 0.5.
  # k = n, so the bound is 1 whatever the clusters.
  mr <- hr_gate_threshold(cal_with_half(d, 0.5, cluster = cl), "exclude", "miss_rate",
                          alpha = 0.2)$gate
  expect_equal(mr$path$ucb, 1)
})

# ---- validity and the policy ----------------------------------------------------

gating_record <- function() {
  g <- seeded(21, {
    s <- stats::runif(2000)
    data.frame(cluster = rep(1:200, each = 10), score = s,
               correct = stats::runif(2000) < ifelse(s > 0.5, 0.99, 0.3),
               answerable = rep(c(TRUE, TRUE, TRUE, TRUE, FALSE), 400))
  })
  cal <- hr_calibrate_signal("gr.iterative.can_answer", g, sig_key(), seed = 8, B = 0)
  hr_gate_threshold(cal, "stop", alpha = 0.15)
}

test_that("a key that differs in any field voids the record", {
  cal <- gating_record()
  expect_equal(cal$status, "gating")
  expect_true(hr_calibration_valid(cal, sig_key()))
  changes <- list(served_model = "mock-model-2026-06-01", version = "2026-06-01",
                  task = "screen", format = "pdf", prompt_hash = "p2", effort = "high",
                  module = "preview", contract_version = "9.9")
  for (f in names(changes)) {
    v <- hr_calibration_valid(cal, utils::modifyList(sig_key(), changes[f]))
    expect_false(v)
    expect_equal(attr(v, "differs"), f)
  }
  k <- sig_key()
  k$task <- NULL
  expect_equal(attr(hr_calibration_valid(cal, k), "differs"), "task")

  pol <- hr_signal_policy("gr.iterative.can_answer", "stop")
  sig <- hr_signal("gr.iterative.can_answer", c(0.99, 0.01))
  live <- hr_apply_signal(sig, pol, cal, sig_key())
  expect_equal(live$gated, c(TRUE, TRUE))
  expect_equal(live$act, c(TRUE, FALSE))
  expect_equal(live$route, c("act", "route_check"))
  void <- hr_apply_signal(sig, pol, cal, sig_key(served_model = "another-model"))
  expect_equal(void$gated, c(FALSE, FALSE))
  expect_equal(void$act, c(FALSE, FALSE))
  expect_match(void$reason[1], "served_model differs")
  # The wrong action, or no key, keeps it advisory too.
  expect_false(hr_apply_signal(sig, hr_signal_policy("gr.iterative.can_answer", "skip"),
                               cal, sig_key())$gated[1])
  expect_match(hr_apply_signal(sig, pol, cal)$reason[1], "no run key")
})

test_that("the policy stays advisory without a calibration record", {
  pol <- hr_signal_policy("gr.iterative.can_answer", "stop", on_fail = "route_person")
  out <- hr_apply_signal(hr_signal("gr.iterative.can_answer", TRUE), pol)
  expect_false(out$gated)
  expect_false(out$act)
  expect_true(out$would_act)
  expect_equal(out$route, "route_person")
  expect_equal(out$reason, "no calibration record")
  # A bare value is taken as the policy's signal.
  expect_false(hr_apply_signal(0.99, pol)$gated)
  expect_error(hr_apply_signal(hr_signal("other", TRUE), pol), class = "gr_bad_setting")
  # A record that never passed a gate keeps the signal advisory.
  g <- data.frame(score = rep(c(0.9, 0.1), 50), correct = rep(c(TRUE, FALSE), 50),
                  answerable = rep(c(TRUE, FALSE), 50))
  cal <- hr_calibrate_signal("gr.iterative.can_answer", g, sig_key(), seed = 1, B = 0)
  out <- hr_apply_signal(TRUE, pol, cal, sig_key())
  expect_false(out$gated)
  expect_equal(out$reason, "the record has no gate threshold")
})
