# test-core-judge.R: hr_judge() in both orders, the validation record and its
# key, the judge scorer, and the PPI correction of judge-scored accuracy.

# A mock judge that logs every request and answers with `rule(content)`, a
# verdict letter or grade.
judge_client <- function(rule) {
  log <- new.env()
  log$sent <- list()
  cl <- gr_mock_client(function(messages, params) {
    log$sent[[length(log$sent) + 1L]] <- list(messages = messages, params = params)
    sprintf('{"verdict": "%s", "reason": "checked"}', rule(messages[[2]]$content))
  })
  list(client = cl, log = log)
}

# Picks whichever candidate says Paris.
paris_rule <- function(txt) {
  if (grepl("Candidate A:\nParis", txt, fixed = TRUE)) "A" else "B"
}

# Binary judge and human labels with known counts: 60 human positives of
# which the judge calls 54 positive, 60 negatives of which it calls 12
# positive.
known_labels <- function() {
  human <- rep(c(TRUE, FALSE), c(60, 60))
  judge <- c(rep(TRUE, 54), rep(FALSE, 6), rep(TRUE, 12), rep(FALSE, 48))
  data.frame(judge = judge, human = human,
             consistent = c(rep(FALSE, 6), rep(TRUE, 114)))
}

grade_config <- function(...) {
  hr_judge_config("mock-model", "Does the response give the reference's answer?",
                  mode = "grade", ...)
}

test_that("hr_judge sends both orders with the candidates anonymised", {
  j <- judge_client(paris_rule)
  res <- hr_judge(c(first = "Paris", second = "Lyon"), j$client, mode = "select",
                  rubric = "Which candidate names the capital of France?")
  expect_s3_class(res, "hr_judgement")
  expect_length(j$log$sent, 2L)
  users <- vapply(j$log$sent, function(s) s$messages[[2]]$content, "")
  expect_match(users[1], "Candidate A:\nParis\n\nCandidate B:\nLyon", fixed = TRUE)
  expect_match(users[2], "Candidate A:\nLyon\n\nCandidate B:\nParis", fixed = TRUE)
  # The candidates' names never reach the model.
  expect_false(any(grepl("first|second", users)))
  expect_identical(res$outcome, "answered")
  expect_identical(res$value, "first")
  expect_identical(res$verdicts$verdict, c("A", "B"))
  expect_identical(res$verdicts$value, c("first", "first"))
  expect_identical(res$verdicts$shown, c("first,second", "second,first"))
  expect_identical(res$verdicts$label, c("judge.select.o1", "judge.select.o2"))
  steps <- res$trace$steps
  expect_identical(vapply(steps, function(s) s$label, ""), c("judge.select.o1", "judge.select.o2"))
  expect_true(res$swap_checked)
  expect_true(is.na(res$degradation))
})

test_that("a verdict that flips with the order is unresolved", {
  j <- judge_client(function(txt) "A")
  res <- hr_judge(c("Paris", "Lyon"), j$client, mode = "select",
                  rubric = "Which candidate names the capital of France?")
  expect_identical(res$outcome, "unresolved")
  expect_true(is.na(res$value))
  expect_identical(res$degradation, "judge_inconsistent")
  expect_identical(res$verdicts$value, c("1", "2"))

  # Pairwise: a tie in both orders is answered, A then tie is not.
  tie <- judge_client(function(txt) "tie")
  expect_identical(hr_judge(c("x", "y"), tie$client, mode = "pairwise",
                            rubric = "Which is clearer?")$value, "tie")
  n <- 0
  mixed <- judge_client(function(txt) { n <<- n + 1; if (n == 1) "A" else "tie" })
  expect_identical(hr_judge(c("x", "y"), mixed$client, mode = "pairwise",
                            rubric = "Which is clearer?")$outcome, "unresolved")
})

test_that("more than two candidates are shown in cyclic rotations", {
  j <- judge_client(function(txt) {
    # Picks the letter shown with "right".
    m <- regmatches(txt, regexpr("Candidate [A-C]:\nright", txt))
    substr(m, 11, 11)
  })
  res <- hr_judge(c(a = "wrong", b = "right", c = "also wrong"), j$client, mode = "select",
                  orders = 3, rubric = "Pick the right one.")
  expect_identical(res$verdicts$shown, c("a,b,c", "b,c,a", "c,a,b"))
  expect_identical(res$verdicts$verdict, c("B", "A", "C"))
  expect_identical(res$value, "b")
  expect_error(hr_judge(c("x", "y"), j$client, mode = "select", orders = 3, rubric = "r"),
               class = "gr_bad_setting")
})

test_that("grade mode swaps the reference and the response, and one order is grade only", {
  j <- judge_client(function(txt) {
    if (grepl("Response to grade:\nParis", txt, fixed = TRUE)) "pass" else "fail"
  })
  res <- hr_judge("Paris", j$client, mode = "grade", reference = "Paris",
                  rubric = "Is the response right?")
  users <- vapply(j$log$sent, function(s) s$messages[[2]]$content, "")
  expect_lt(regexpr("Reference answer", users[1]), regexpr("Response to grade", users[1]))
  expect_gt(regexpr("Reference answer", users[2]), regexpr("Response to grade", users[2]))
  expect_identical(res$verdicts$shown, c("reference,response", "response,reference"))
  expect_identical(res$value, "pass")

  one <- hr_judge("Lyon", j$client, mode = "grade", reference = "Paris", orders = 1,
                  rubric = "Is the response right?")
  expect_identical(one$value, "fail")
  expect_false(one$swap_checked)
  expect_identical(nrow(one$verdicts), 1L)
  expect_error(hr_judge(c("x", "y"), j$client, mode = "select", orders = 1, rubric = "r"),
               class = "gr_bad_setting")
  expect_error(hr_judge("Paris", j$client, mode = "grade", rubric = "r"),
               class = "gr_bad_setting")
  expect_error(hr_judge(c("x", "y"), j$client, mode = "grade", reference = "x", rubric = "r"),
               class = "gr_bad_setting")
})

test_that("a reply with no allowed verdict, or a failed call, makes the judgement failed", {
  bad <- judge_client(function(txt) "C")
  res <- hr_judge(c("x", "y"), bad$client, mode = "select", rubric = "r")
  expect_identical(res$outcome, "failed")
  expect_true(is.na(res$value))
  down <- gr_mock_client(function(m, p) stop("network down"))
  expect_identical(hr_judge(c("x", "y"), down, mode = "select", rubric = "r")$outcome, "failed")
})

test_that("judge cost is recorded apart from the run it judges", {
  gr_register_model("judge-priced", context_window = 128000L, max_output = 4096L,
                    input_usd = 2, output_usd = 8)
  j <- judge_client(paris_rule)
  run <- gr_trace()
  invisible(gr_call(j$client, "Answer the question.", trace = run, label = "run.answer"))
  before <- gr_trace_cost(run)
  res <- hr_judge(c("Paris", "Lyon"), j$client, mode = "select", model = "judge-priced",
                  rubric = "Which names the capital of France?", trace = run)
  # The run's calls, tokens and dollars are as they were.
  expect_identical(run$calls, 1L)
  expect_equal(gr_trace_cost(run), before)
  # The judge's own ledger holds both requests and their price.
  expect_identical(res$judge_cost$calls, 2L)
  expect_identical(res$trace$calls, 2L)
  expect_gt(res$judge_cost$usd, 0)
  expect_equal(res$judge_cost$usd, sum(gr_trace_cost(res$trace)$usd))
  expect_identical(res$judge_cost$tokens_in, res$trace$tokens_in)
  expect_identical(res$judge_cost$tokens_out, res$trace$tokens_out)
  # The run gets a local note pointing at the judge's ledger.
  note <- run$steps[[length(run$steps)]]
  expect_identical(note$kind, "local")
  expect_identical(note$detail$judge_trace, res$trace$run_id)
  expect_equal(note$detail$usd, res$judge_cost$usd)
})

test_that("judge calls are held to what the run's governor has left", {
  j <- judge_client(paris_rule)
  run <- gr_trace(governor = hr_governor(max_calls = 2))
  invisible(gr_call(j$client, "Answer.", trace = run))
  res <- suppressWarnings(hr_judge(c("Paris", "Lyon"), j$client, mode = "select",
                                   rubric = "r", trace = run))
  # One call left: the first order is asked, the second refused.
  expect_identical(res$outcome, "failed")
  expect_identical(res$trace$calls, 1L)
  expect_identical(res$verdicts$ok, c(TRUE, FALSE))
  expect_length(j$log$sent, 2L)
})

test_that("judge requests use the cache with their draw index", {
  j <- judge_client(paris_rule)
  dir <- file.path(tempdir(), paste0("judge-cache-", as.integer(Sys.time())))
  cached <- gr_cache_client(j$client, gr_cache(dir))
  ask <- function(d) hr_judge(c("Paris", "Lyon"), cached, mode = "select", rubric = "r",
                              draw_index = d)
  first <- ask(1)
  expect_length(j$log$sent, 2L)
  expect_identical(j$log$sent[[1]]$params$draw_index, 1L)
  again <- ask(1)
  expect_length(j$log$sent, 2L)
  expect_true(all(vapply(again$trace$steps, function(s) s$cached, TRUE)))
  expect_identical(again$value, first$value)
  invisible(ask(2))
  expect_length(j$log$sent, 4L)
  unlink(dir, recursive = TRUE)
})

test_that("hr_judge_validate reports kappa, sensitivity, specificity and swap inconsistency", {
  cfg <- grade_config()
  v <- hr_judge_validate(cfg, known_labels(), B = 500)
  expect_s3_class(v, "hr_judge_validation")
  expect_identical(c(v$n, v$n_pos, v$n_neg, v$n_unresolved), c(120L, 60L, 60L, 0L))
  # po = 102 / 120 = 0.85, pe = (66 * 60 + 54 * 60) / 120^2 = 0.5.
  expect_equal(v$kappa$estimate, 0.7)
  expect_lt(v$kappa$lower, 0.7)
  expect_gt(v$kappa$upper, 0.7)
  # Wilson intervals, as prop.test(x, n, correct = FALSE) gives them.
  expect_equal(v$sensitivity$estimate, 0.9)
  expect_equal(c(v$sensitivity$lower, v$sensitivity$upper),
               c(0.7985053528, 0.9533571655), tolerance = 1e-7)
  expect_equal(v$specificity$estimate, 0.8)
  expect_equal(c(v$specificity$lower, v$specificity$upper),
               c(0.6821819419, 0.8817149468), tolerance = 1e-7)
  expect_equal(v$sens_halfwidth, (0.9533571655 - 0.7985053528) / 2, tolerance = 1e-7)
  expect_identical(c(v$swap_inconsistency$x, v$swap_inconsistency$n), c(6L, 120L))
  expect_equal(v$swap_inconsistency$estimate, 0.05)
  expect_identical(v$config_hash, cfg$hash)
  expect_output(print(v), "swap inconsistency")

  # Unresolved items count as not called positive, as the scorer counts them,
  # and in the swap rate.
  lab <- known_labels()
  lab$consistent <- NULL
  lab$judge[c(1, 61)] <- NA
  u <- hr_judge_validate(cfg, lab, B = 0)
  expect_identical(u$n_unresolved, 2L)
  expect_identical(u$sensitivity$n, 60L)
  expect_equal(u$sensitivity$estimate, 53 / 60)
  expect_equal(c(u$sensitivity$lower, u$sensitivity$upper),
               c(0.7782121198, 0.9423227936), tolerance = 1e-7)
  # Row 61 was a false positive; unresolved, it now counts as a right negative.
  expect_equal(u$specificity$estimate, 49 / 60)
  expect_equal(c(u$specificity$lower, u$specificity$upper),
               c(0.7008024625, 0.8944220311), tolerance = 1e-7)
  expect_identical(c(u$swap_inconsistency$x, u$swap_inconsistency$n), c(2L, 120L))

  # A one-order judge has no swap check.
  one <- hr_judge_validate(grade_config(orders = 1), known_labels(), B = 0)
  expect_true(is.na(one$swap_inconsistency$n))
})

test_that("hr_judge_validate measures the rule the scorer applies to unresolved items", {
  cfg <- grade_config()
  human <- rep(c(TRUE, FALSE), c(50, 50))
  judge <- human
  judge[1:30] <- NA
  v <- hr_judge_validate(cfg, data.frame(judge = judge, human = human), B = 0)
  # The scorer calls the 30 unresolved positives wrong, so sensitivity is
  # 20 / 50, not 20 / 20.
  expect_identical(v$sensitivity$n, 50L)
  expect_equal(v$sensitivity$estimate, 0.4)
  # prop.test(20, 50, correct = FALSE)$conf.int
  expect_equal(c(v$sensitivity$lower, v$sensitivity$upper),
               c(0.2760838973, 0.5381856225), tolerance = 1e-7)
  expect_equal(v$specificity$estimate, 1)
  expect_identical(v$specificity$n, 50L)
  expect_lt(v$kappa$estimate, 1)
  expect_identical(v$n_unresolved, 30L)
})

test_that("hr_judge_validate takes the configuration's positive grade for text labels", {
  cfg <- grade_config()
  h <- rep(c(TRUE, FALSE), c(50, 50))
  j <- h
  j[c(1, 51)] <- !j[c(1, 51)]
  lab <- data.frame(judge = ifelse(j, "pass", "fail"), human = ifelse(h, "pass", "fail"))
  v <- hr_judge_validate(cfg, lab, B = 0)
  expect_identical(c(v$n_pos, v$n_neg), c(50L, 50L))
  expect_equal(v$sensitivity$estimate, 0.98)
  expect_equal(v$specificity$estimate, 0.98)
  # A `positive` that no label carries is named in the error.
  expect_error(hr_judge_validate(cfg, lab, positive = "yes", B = 0),
               class = "gr_bad_setting", regexp = "\"pass\"")
})

test_that("hr_judge_validate refuses a judge column on another scale than human", {
  cfg <- grade_config()
  h <- rep(c(TRUE, FALSE), c(60, 60))
  # 57 of 60 positives and 55 of 60 negatives called right.
  j <- h
  j[c(1:3, 61:65)] <- !j[c(1:3, 61:65)]
  text <- data.frame(judge = ifelse(j, "pass", "fail"), human = ifelse(h, "pass", "fail"))
  v <- hr_judge_validate(cfg, text, B = 0)
  # sens = 57 / 60 = 0.95, spec = 55 / 60; po = 112 / 120,
  # pe = (62 * 60 + 58 * 60) / 120^2 = 0.5, kappa = (112 / 120 - 0.5) / 0.5 = 13 / 15.
  expect_equal(v$sensitivity$estimate, 0.95)
  expect_equal(v$specificity$estimate, 55 / 60)
  expect_equal(v$kappa$estimate, 13 / 15)
  # Logical judge calls beside text labels never equal "pass"; before the fix
  # they were counted as all negative (sensitivity 0, specificity 1, kappa 0).
  mixed <- data.frame(judge = j, human = text$human)
  expect_error(hr_judge_validate(cfg, mixed, B = 0), class = "gr_bad_setting",
               regexp = "holds \"FALSE\", \"TRUE\" and the human column \"pass\", \"fail\"")
  # The same holds with unresolved calls among them.
  mixed$judge[c(10, 70)] <- NA
  expect_error(hr_judge_validate(cfg, mixed, B = 0), class = "gr_bad_setting")
  # A grade the humans never used is allowed when the scales share a value:
  # "partial" counts as not positive, so sensitivity is 56 / 60.
  partial <- text
  partial$judge[4] <- "partial"
  w <- hr_judge_validate(cfg, partial, B = 0)
  expect_equal(w$sensitivity$estimate, 56 / 60)
})

test_that("hr_judge_validate reads the optional columns by exact name only", {
  cfg <- grade_config()
  lab <- known_labels()
  lab$consistent <- NULL
  lab$judge[c(1, 70)] <- NA
  # No `consistent` or `outcome` column: the two NA verdicts are the
  # inconsistent items, 2 of 120.
  base <- hr_judge_validate(cfg, lab, B = 0)
  expect_identical(c(base$swap_inconsistency$x, base$swap_inconsistency$n), c(2L, 120L))
  # Unrelated columns whose names start with a reserved name change nothing.
  # Before the fix `consistently_long` gave 0 of 120 and `outcomes_note` gave
  # NA (not measured); `config_hash_note` stopped with hr_judge_config_mismatch.
  for (extra in c("consistently_long", "outcomes_note", "config_hash_note")) {
    l2 <- lab
    l2[[extra]] <- if (extra == "consistently_long") TRUE else "x"
    v <- hr_judge_validate(cfg, l2, B = 0)
    expect_identical(c(v$swap_inconsistency$x, v$swap_inconsistency$n), c(2L, 120L))
    # Wilson centre aside, the point estimate is 2 / 120 = 0.01667.
    expect_equal(v$swap_inconsistency$estimate, 2 / 120)
  }
})

test_that("hr_judge_validate refuses fewer than 50 items per class", {
  cfg <- grade_config()
  lab <- known_labels()
  expect_error(hr_judge_validate(cfg, lab[-(1:11), ], B = 0), class = "hr_judge_too_few_labels")
  expect_error(hr_judge_validate(cfg, lab[-(110:120), ], B = 0), class = "hr_judge_too_few_labels")
  # The minimum cannot be lowered.
  expect_error(hr_judge_validate(cfg, lab[-(1:11), ], n_pos_min = 30, B = 0),
               class = "gr_bad_setting")
  # Rows without a human label are not counted.
  lab$human[1:11] <- NA
  expect_error(hr_judge_validate(cfg, lab, B = 0), class = "hr_judge_too_few_labels")
  # Labels on another configuration's outputs are refused.
  lab <- known_labels()
  lab$config_hash <- grade_config(orders = 1)$hash
  expect_error(hr_judge_validate(cfg, lab, B = 0), class = "hr_judge_config_mismatch")
})

test_that("a change to any keyed part of the configuration voids the record", {
  cfg <- grade_config()
  v <- hr_judge_validate(cfg, known_labels(), B = 0)
  expect_true(hr_judge_valid(v, cfg))
  expect_true(hr_judge_valid(v, grade_config()))
  changed <- list(
    model = hr_judge_config("other-model", cfg$rubric, mode = "grade"),
    rubric = hr_judge_config("mock-model", "Is it right?", mode = "grade"),
    orders = grade_config(orders = 1),
    positive = grade_config(positive = "fail"))
  for (part in names(changed)) {
    ok <- hr_judge_valid(v, changed[[part]])
    expect_false(ok)
    expect_match(attr(ok, "reason"), part)
  }
  # A record edited after it was made is not valid.
  edited <- v
  edited$sensitivity$estimate <- 0.99
  expect_false(hr_judge_valid(edited, cfg))
  # Nor is a configuration edited after it was built.
  bent <- cfg
  bent$model <- "other-model"
  expect_false(hr_judge_valid(v, bent))
  expect_false(hr_judge_valid(NULL, cfg))
})

test_that("hr_scorer_judge refuses to score without a valid record", {
  cfg <- grade_config()
  j <- judge_client(function(txt) "pass")
  expect_error(hr_scorer_judge(cfg, client = j$client), class = "hr_judge_unvalidated")
  expect_error(hr_scorer_judge(cfg, NULL, j$client), class = "hr_judge_unvalidated")
  v_other <- hr_judge_validate(grade_config(orders = 1), known_labels(), B = 0)
  expect_error(hr_scorer_judge(cfg, v_other, j$client), class = "hr_judge_unvalidated")
  expect_length(j$log$sent, 0L)
})

test_that("hr_scorer_judge grades runs, counts unresolved as wrong and keeps its own ledger", {
  cfg <- grade_config()
  v <- hr_judge_validate(cfg, known_labels(), B = 0)
  j <- judge_client(function(txt) {
    same <- grepl("Reference answer:\nParis", txt, fixed = TRUE) &&
      grepl("Response to grade:\nParis", txt, fixed = TRUE)
    if (same) "pass" else "fail"
  })
  sc <- hr_scorer_judge(cfg, v, j$client)
  expect_s3_class(sc, "hr_scorer")
  right <- sc$fn("Capital of France?", "Paris", "Paris")
  expect_true(right$correct)
  expect_identical(right$outcome, "pass")
  wrong <- sc$fn("Capital of France?", "Lyon", "Paris")
  expect_false(wrong$correct)
  expect_identical(wrong$failure_kind, "wrong")
  expect_true(is.na(sc$fn("q", "Paris", NA)$correct))
  expect_identical(sc$fn("q", "", "Paris")$failure_kind, "parse_failure")
  expect_identical(sc$trace$calls, 4L)

  n <- 0
  flip <- judge_client(function(txt) { n <<- n + 1; if (n %% 2) "pass" else "fail" })
  unres <- hr_scorer_judge(cfg, v, flip$client)$fn("q", "Paris", "Paris")
  expect_false(unres$correct)
  expect_identical(unres$outcome, "judge_unresolved")

  # In a benchmark the judge's calls stay out of the runs' traces.
  ref <- hr_reference(list(q1 = "France", q2 = "Peru"), labels = c("Paris", "Lima"),
                      cluster = c("d1", "d2"), split = "test")
  answers <- gr_mock_client(function(m, p) "Paris")
  arm <- hr_arm("ask", function(item, ctx) ctx$call(paste("Capital of", item))$text)
  sc2 <- hr_scorer_judge(cfg, v, j$client)
  bench <- suppressWarnings(hr_benchmark(arm, ref, runs = 2, client = answers, scorer = sc2))
  expect_identical(bench$correct, c(TRUE, TRUE, FALSE, FALSE))
  labels <- vapply(attr(bench, "trace")$steps, function(s) s$label, "")
  expect_false(any(startsWith(labels, "judge")))
  expect_identical(sc2$trace$calls, 8L)
})

test_that("hr_scorer_judge passes its draw index to the cache", {
  cfg <- grade_config()
  v <- hr_judge_validate(cfg, known_labels(), B = 0)
  j <- judge_client(function(txt) "pass")
  dir <- file.path(tempdir(), paste0("scorer-cache-", as.integer(Sys.time())))
  cached <- gr_cache_client(j$client, gr_cache(dir))
  expect_error(hr_scorer_judge(cfg, v, cached, draw_index = -1), class = "gr_bad_setting")
  invisible(hr_scorer_judge(cfg, v, cached, draw_index = 3)$fn("q", "Paris", "Paris"))
  expect_length(j$log$sent, 2L)
  expect_identical(j$log$sent[[1]]$params$draw_index, 3L)
  invisible(hr_scorer_judge(cfg, v, cached, draw_index = 3)$fn("q", "Paris", "Paris"))
  expect_length(j$log$sent, 2L)
  invisible(hr_scorer_judge(cfg, v, cached, draw_index = 4)$fn("q", "Paris", "Paris"))
  expect_length(j$log$sent, 4L)
  unlink(dir, recursive = TRUE)
})

test_that("hr_judge_ppi corrects a judge with known bias", {
  set.seed(11)
  N <- 4000
  truth <- rbinom(N, 1, 0.6)
  # A lenient judge: it passes 95% of right answers and 30% of wrong ones,
  # so its raw accuracy is about 0.6 x 0.95 + 0.4 x 0.3 = 0.69.
  judge <- ifelse(truth == 1, rbinom(N, 1, 0.95), rbinom(N, 1, 0.3))
  human <- rep(NA_real_, N)
  lab <- sample(N, 400)
  human[lab] <- truth[lab]
  est <- hr_judge_ppi(judge, human)
  expect_gt(est$judge_mean - mean(truth), 0.05)
  expect_lt(abs(est$estimate - mean(truth)), 2 * est$se)
  expect_identical(est$method, "ppi++")
  # It is hr_ppi() on the labelled and unlabelled parts.
  direct <- hr_ppi(judge[-lab], judge[lab], truth[lab])
  expect_equal(est$estimate, direct$estimate)
  expect_equal(est$se, direct$se)

  # Labelled with unequal probabilities: items the judge failed are labelled
  # more often. The DSL form weights the correction by 1 / pi.
  pi <- ifelse(judge == 1, 0.05, 0.3)
  R <- rbinom(N, 1, pi) == 1
  human <- ifelse(R, truth, NA)
  dsl <- hr_judge_ppi(judge, human, inclusion_prob = pi)
  expect_identical(dsl$method, "dsl tuned")
  expect_lt(abs(dsl$estimate - mean(truth)), 2.5 * dsl$se)
  plain <- hr_judge_ppi(judge, human, inclusion_prob = pi, tune = FALSE)
  expect_equal(plain$estimate, mean(judge + R * (truth - judge) / pi))
  # One probability per labelled item gives the same.
  expect_equal(hr_judge_ppi(judge, human, inclusion_prob = pi[R], tune = FALSE)$estimate,
               plain$estimate)
  expect_error(hr_judge_ppi(judge, human[-1]), class = "gr_bad_setting")
})
