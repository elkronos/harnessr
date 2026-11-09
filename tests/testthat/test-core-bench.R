# test-core-bench.R: arms, references, scorers and hr_benchmark() against
# mock clients.

# Four items in two clusters, every item on the test split.
bench_ref <- function(split = "test") {
  hr_reference(items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
               labels = c("Paris", "Lima", "N'Djamena", "Suva"),
               cluster = c("a", "a", "b", "b"), split = split)
}

# Answers every country right except Chad, which it spells without the
# apostrophe.
capital_client <- function() {
  capitals <- c(France = "Paris", Peru = "Lima", Chad = "Ndjamena", Fiji = "Suva")
  gr_mock_client(function(messages, params) {
    capitals[[sub("Capital of ", "", messages[[1]]$content)]]
  })
}

ask_arm <- function(name = "ask") {
  hr_arm(name, function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
}

# ---- hr_arm ------------------------------------------------------------------

test_that("hr_arm validates its arguments and hashes what makes the arm", {
  a <- hr_arm("a", function(item, ctx) "x", params = list(k = 1))
  expect_s3_class(a, "hr_arm")
  expect_identical(nchar(a$hash), 64L)
  b <- hr_arm("a", function(item, ctx) "x", params = list(k = 2))
  expect_false(identical(a$hash, b$hash))
  expect_error(hr_arm("", function(item, ctx) 1), class = "hr_bad_arm")
  expect_error(hr_arm("a", "not a function"), class = "hr_bad_arm")
  expect_error(hr_arm("a", function(item) 1), class = "hr_bad_arm")
  expect_error(hr_arm("a", function(item, ctx) 1, params = list(1)), class = "hr_bad_arm")
  expect_error(hr_arm("a", function(item, ctx) 1, derived_from = "a"), class = "hr_bad_arm")
  expect_identical(hr_arm("b", function(...) 1, derived_from = a)$derived_from, "a")
  expect_output(print(a), "<hr_arm a> version 0.0.1")
  # `run` has no default: an arm that answers nothing is a mistake.
  expect_error(hr_arm("x"), class = "hr_bad_arm")
})

test_that("an arm from a factory keeps its hash through saveRDS and is accepted", {
  make <- function(p) hr_arm(paste0("arm_", p), function(item, ctx) paste(p, item))
  x <- make("x")
  # The hash rests on the code and the value of `p`, not on where the
  # closure lives, so a second build of the same arm matches it.
  expect_identical(make("x")$hash, x$hash)
  expect_false(identical(make("y")$hash, x$hash))
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  saveRDS(x, f)
  back <- readRDS(f)
  expect_identical(back$hash, x$hash)
  ref <- hr_reference(list(q1 = "France"), "x France", "a", split = "test")
  b <- hr_benchmark(back, ref, runs = 5, client = NULL)
  expect_identical(b$correct, rep(TRUE, 5))
  expect_identical(attr(b, "arms")$hash, x$hash)
})

test_that("an arm derived from one outside the benchmark warns", {
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  child <- hr_arm("child", function(item, ctx) "Paris", derived_from = "parent")
  expect_warning(hr_benchmark(child, ref, runs = 5, client = NULL),
                 class = "hr_unknown_parent_arm")
})

test_that("hr_benchmark refuses repeated arm names and arms changed after they were built", {
  ref <- bench_ref()
  cl <- capital_client()
  expect_error(hr_benchmark(list(ask_arm(), ask_arm()), ref, client = cl),
               class = "hr_bad_arm")
  a <- ask_arm()
  a$version <- "9"
  expect_error(hr_benchmark(a, ref, client = cl), class = "hr_bad_arm")
})

# ---- hr_reference ------------------------------------------------------------

test_that("hr_reference checks lengths, ids, splits and inclusion probabilities", {
  ref <- bench_ref()
  expect_s3_class(ref, "hr_reference")
  expect_identical(ref$ids, c("q1", "q2", "q3", "q4"))
  expect_identical(ref$split, rep("test", 4))
  expect_identical(ref$inclusion_prob, rep(1, 4))
  expect_identical(nchar(ref$hash), 64L)
  expect_identical(ref$items$q3, "Chad")
  # Left as the default, every item is on dev.
  expect_identical(hr_reference(c("x", "y"), c(1, 2), "c")$split, c("dev", "dev"))
  # Ids as their own payloads; a named character vector maps ids to payloads.
  expect_identical(hr_reference(c("x", "y"), c(1, 2), "c")$items, list(x = "x", y = "y"))
  expect_identical(hr_reference(c(x = "p", y = "q"), c(1, 2), "c")$items,
                   list(x = "p", y = "q"))
  expect_error(hr_reference(list("a", "b"), 1:2, "c"), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "x"), 1:2, "c"), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:3, "c"), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, c("c", "d", "e")), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, c("c", NA)), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", split = "train"),
               class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", split = c("dev", "test", "test")),
               class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", inclusion_prob = 0),
               class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", inclusion_prob = c(0.5, 1.2)),
               class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", strata = "s"), class = "hr_bad_reference")
  expect_error(hr_reference(c("x", "y"), 1:2, "c", coders = matrix(1, 3, 2)),
               class = "hr_bad_reference")
  ok <- hr_reference(c("x", "y"), 1:2, "c", split = c("dev", "test"),
                     inclusion_prob = c(0.5, 1), strata = c("s1", "s2"),
                     coders = cbind(ann = 1:2, bo = c(1L, 1L)))
  expect_identical(ok$inclusion_prob, c(0.5, 1))
  expect_identical(names(ok$coders), c("ann", "bo"))
  expect_output(print(ok), "2 item\\(s\\) in 1 cluster\\(s\\)")
})

test_that("the content hash follows the content, and a changed reference is refused", {
  a <- bench_ref()
  expect_identical(a$hash, bench_ref()$hash)
  expect_false(identical(a$hash, bench_ref(split = "dev")$hash))
  a$labels$q1 <- "Lyon"
  expect_error(hr_benchmark(ask_arm(), a, runs = 5, client = capital_client()),
               class = "hr_bad_reference")
})

test_that("a scored reference is locked, with every copy and every reference grown from it", {
  ref <- bench_ref()
  grown <- hr_reference_add(ref, list(q5 = "Chile"), "Santiago", "c", split = "test")
  expect_identical(grown$ids, c("q1", "q2", "q3", "q4", "q5"))
  expect_false(identical(grown$hash, ref$hash))
  expect_error(hr_reference_add(ref, list(q1 = "Chile"), "Santiago", "c"),
               class = "hr_bad_reference")
  copy <- ref
  hr_benchmark(ask_arm(), ref, runs = 5, client = capital_client())
  expect_error(hr_reference_add(ref, list(q6 = "Peru"), "Lima", "a"),
               class = "hr_reference_locked")
  expect_error(hr_reference_add(copy, list(q6 = "Peru"), "Lima", "a"),
               class = "hr_reference_locked")
  expect_error(hr_reference_add(grown, list(q6 = "Peru"), "Lima", "a"),
               class = "hr_reference_locked")
  expect_output(print(ref), "locked")
})

# ---- scorers -----------------------------------------------------------------

test_that("the exact scorer folds case and white space and sorts out non-answers", {
  s <- hr_scorer_exact()
  expect_identical(s$name, "exact_normalised")
  expect_identical(s$fn(NULL, "  PARIS\n", "Paris"),
                   list(correct = TRUE, outcome = "paris", failure_kind = NA_character_))
  expect_identical(s$fn(NULL, "New  York", "new york")$correct, TRUE)
  expect_identical(s$fn(NULL, "Lyon", "Paris")$failure_kind, "wrong")
  # Several accepted answers.
  expect_true(s$fn(NULL, "NYC", list(c("New York", "NYC")))$correct)
  expect_identical(s$fn(NULL, "", "Paris")$failure_kind, "parse_failure")
  expect_identical(s$fn(NULL, NULL, "Paris")$failure_kind, "parse_failure")
  expect_identical(s$fn(NULL, 42, "Paris")$failure_kind, "parse_failure")
  expect_identical(s$fn(NULL, "not_in_document", "Paris")$failure_kind, "not_in_document")
  expect_true(s$fn(NULL, "NOT_IN_DOCUMENT", "NOT_IN_DOCUMENT")$correct)
  expect_identical(s$fn(NULL, list(answer = "x", failure_kind = "refusal"), "x")$failure_kind,
                   "refusal")
  expect_true(s$fn(NULL, list(answer = "Paris"), "Paris")$correct)
  failed <- structure(list(ok = FALSE, text = "Paris"), class = "gr_result")
  expect_identical(s$fn(NULL, failed, "Paris")$failure_kind, "error")
  expect_true(is.na(s$fn(NULL, "Paris", NA)$correct))
  # Without folding, case counts.
  strict <- hr_scorer_exact(normalise = FALSE)
  expect_identical(strict$name, "exact")
  expect_false(strict$fn(NULL, "paris", "Paris")$correct)
  expect_error(hr_scorer_exact(normalise = NA), class = "hr_bad_scorer")
})

test_that("hr_scorer checks its function and the benchmark holds scorers to the contract", {
  expect_error(hr_scorer("x", "s"), class = "hr_bad_scorer")
  expect_error(hr_scorer(function(item, output) TRUE, "s"), class = "hr_bad_scorer")
  expect_error(hr_scorer(function(item, output, label) TRUE, ""), class = "hr_bad_scorer")
  ref <- bench_ref()
  cl <- capital_client()
  run <- function(fn) hr_benchmark(ask_arm(), ref, runs = 5, client = cl,
                                   scorer = hr_scorer(fn, "custom"))
  expect_error(run(function(item, output, label) TRUE), class = "hr_bad_scorer")
  expect_error(run(function(item, output, label) list(correct = "yes")),
               class = "hr_bad_scorer")
  expect_error(run(function(item, output, label) list(correct = FALSE, failure_kind = "odd")),
               class = "hr_bad_scorer")
  expect_error(run(function(item, output, label) list(correct = TRUE, failure_kind = "wrong")),
               class = "hr_bad_scorer")
  # A wrong output with no reason is "wrong"; a reason beside NA counts wrong.
  b <- run(function(item, output, label) {
    if (identical(item, "Peru")) list(correct = NA, outcome = "x", failure_kind = "refusal")
    else list(correct = FALSE)
  })
  expect_identical(unique(b$failure_kind[b$item == "q1"]), "wrong")
  expect_identical(unique(b$failure_kind[b$item == "q2"]), "refusal")
  expect_false(any(b$correct))
  expect_identical(unique(b$outcome[b$item == "q2"]), "x")
})

# ---- hr_benchmark ------------------------------------------------------------

test_that("hr_benchmark returns one row per cluster x item x arm x run", {
  ref <- bench_ref()
  b <- hr_benchmark(list(ask_arm("one"), ask_arm("two")), ref, runs = 5,
                    client = capital_client())
  expect_s3_class(b, "hr_bench")
  expect_identical(nrow(b), 4L * 2L * 5L)
  expect_identical(names(b), c(
    "cluster", "item", "arm", "run", "split", "correct", "outcome", "failure_kind",
    "tokens_in", "tokens_out", "tokens_reasoning", "tokens_cached", "usd", "usd_provenance",
    "seconds", "draw_index", "ledger_id", "reportable"))
  expect_identical(b$cluster, rep(c("a", "b"), each = 20))
  expect_identical(b$item, rep(c("q1", "q2", "q3", "q4"), each = 10))
  expect_identical(b$arm, rep(rep(c("one", "two"), each = 5), 4))
  expect_identical(b$run, rep(1:5, 8))
  expect_identical(b$correct, b$item != "q3")
  expect_identical(b$failure_kind, ifelse(b$item == "q3", "wrong", NA_character_))
  expect_identical(unique(b$outcome[b$item == "q3"]), "ndjamena")
  expect_true(all(b$tokens_in > 0L & b$tokens_out > 0L))
  expect_identical(b$usd, rep(0, 40))
  expect_true(all(b$usd_provenance %in% c("counted", "estimated")))
  expect_true(all(b$reportable))
  expect_false(anyDuplicated(b$ledger_id) > 0)
  # Every row's trace is kept under its ledger id, and its steps carry it in
  # the benchmark's trace.
  traces <- attr(b, "traces")
  expect_identical(names(traces), b$ledger_id)
  expect_identical(traces[[7]]$calls, 1L)
  tr <- attr(b, "trace")
  expect_identical(tr$calls, 40L)
  expect_identical(vapply(tr$steps, function(s) s$ledger_id, ""), b$ledger_id)
  expect_identical(attr(b, "arms")$arm, c("one", "two"))
  expect_identical(attr(b, "reference_hash"), ref$hash)
  out <- capture.output(print(b))
  expect_true(any(grepl("2 arm\\(s\\) x 4 item\\(s\\) in 2 cluster\\(s\\) x 5 run\\(s\\)", out)))
  expect_true(any(grepl("^ one +0\\.750 +20 +5", out)))
  expect_true(any(grepl("Descriptive only", out)))
  # A column subset prints as a plain table.
  expect_output(print(b[1:2, c("item", "run")]), "q1")
})

test_that("each run is its own draw, numbered 1 to runs, and reaches the request", {
  seen <- integer(0)
  cl <- gr_mock_client(function(messages, params) {
    seen[length(seen) + 1L] <<- params$draw_index
    "Paris"
  })
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  b <- hr_benchmark(ask_arm(), ref, runs = 7, client = cl)
  expect_identical(b$draw_index, 1:7)
  expect_identical(seen, 1:7)
  # Under a cache the seven draws are seven entries, and a second benchmark
  # reads them back as the same seven distinct draws.
  n <- 0
  counting <- gr_mock_client(function(messages, params) {
    n <<- n + 1
    paste("Paris", n)
  })
  d <- tempfile("bench-cache-")
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  cached <- gr_cache_client(counting, gr_cache(d))
  first <- hr_benchmark(ask_arm(), ref, runs = 5, client = cached)
  again <- hr_benchmark(ask_arm(), ref, runs = 5, client = cached)
  expect_identical(first$outcome, paste("paris", 1:5))
  expect_identical(again$outcome, first$outcome)
  expect_identical(again$usd_provenance, rep("none", 5))
})

test_that("an arm whose runs are copies of one stored reply is refused", {
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  d <- tempfile("bench-cache-")
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  cached <- gr_cache_client(gr_mock_client(function(m, p) "Paris"), gr_cache(d))
  # No draw index: run 2 is the cache entry run 1 wrote.
  undrawn <- hr_arm("undrawn", function(item, ctx) {
    gr_call(ctx$client, paste0("Capital of ", item), trace = ctx$trace)$text
  })
  expect_error(hr_benchmark(undrawn, ref, runs = 5, client = cached),
               class = "hr_duplicate_draw")
  # The same draw index on every run is no better.
  fixed <- hr_arm("fixed", function(item, ctx) {
    gr_call(ctx$client, paste0("Capital of ", item), trace = ctx$trace, draw_index = 1)$text
  })
  expect_error(hr_benchmark(fixed, ref, runs = 5, client = cached),
               class = "hr_duplicate_draw")
  # One run cannot repeat an earlier one.
  expect_silent(suppressWarnings(hr_benchmark(undrawn, ref, runs = 1, client = cached)))
})

test_that("a reply whose response id repeats across runs is refused", {
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  same_id <- gr_mock_client(function(m, p) {
    harnessr:::gr_result(TRUE, text = "Paris", response_id = "resp_1")
  })
  expect_error(hr_benchmark(ask_arm(), ref, runs = 5, client = same_id),
               class = "hr_duplicate_draw")
  fresh_id <- gr_mock_client(function(m, p) {
    harnessr:::gr_result(TRUE, text = "Paris",
                         response_id = paste0("resp_", p$draw_index))
  })
  fresh <- hr_benchmark(ask_arm(), ref, runs = 5, client = fresh_id)
  expect_identical(fresh$correct, rep(TRUE, 5))
})

test_that("a replay that runs out of draws and repeats one is refused", {
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  recorded <- suppressWarnings(hr_benchmark(ask_arm(), ref, runs = 2,
                                            client = capital_client()))
  rec <- attr(recorded, "trace")
  # The recording holds draws 1 and 2; draws 3 to 5 would repeat draw 2.
  replay <- gr_replay_client(rec, on_exhausted = "flag")
  expect_error(hr_benchmark(ask_arm(), ref, runs = 5, client = replay),
               class = "hr_duplicate_draw")
  # Within what was recorded, the replay gives the recorded draws.
  again <- suppressWarnings(hr_benchmark(ask_arm(), ref, runs = 2,
                                         client = gr_replay_client(rec)))
  expect_identical(again$outcome, c("paris", "paris"))
  expect_identical(again$usd_provenance, c("none", "none"))
})

test_that("an item with no label is NA on every run and left out of accuracy", {
  ref <- hr_reference(list(q1 = "France", q2 = "Peru"), c("Paris", NA), "a", split = "test")
  # Draws 1 and 2 come back empty (parse failures), the rest answer Paris.
  cl <- gr_mock_client(function(messages, params) {
    if (params$draw_index <= 2) "" else "Paris"
  })
  b <- hr_benchmark(ask_arm(), ref, runs = 5, client = cl)
  q2 <- b[b$item == "q2", ]
  expect_identical(q2$correct, rep(NA, 5))
  expect_identical(q2$failure_kind, c("parse_failure", "parse_failure", NA, NA, NA))
  expect_identical(b$correct[b$item == "q1"], c(FALSE, FALSE, TRUE, TRUE, TRUE))
  out <- capture.output(print(b))
  expect_true(any(grepl("^ ask +0\\.600 ", out)))
  # A budget stop or an error on an unlabelled item is NA as well.
  broken <- hr_arm("broken", function(item, ctx) stop("no route"))
  e <- hr_benchmark(broken, ref, runs = 5, client = NULL)
  expect_identical(e$correct, rep(c(FALSE, NA), each = 5))
  expect_identical(e$failure_kind, rep("error", 10))
})

test_that("rows on the dev split are not reportable", {
  ref <- hr_reference(list(q1 = "France", q2 = "Peru", q3 = "Chad"),
                      c("Paris", "Lima", "N'Djamena"), c("a", "a", "b"),
                      split = c("dev", "test", "calibration"))
  b <- hr_benchmark(ask_arm(), ref, runs = 5, client = capital_client(),
                    split = c("dev", "test"))
  expect_identical(unique(b$item), c("q1", "q2"))
  expect_identical(b$reportable, rep(c(FALSE, TRUE), each = 5))
  expect_identical(b$split, rep(c("dev", "test"), each = 5))
  expect_output(print(b), "5 row\\(s\\) on the dev split are not reportable")
  # q1 (dev) is right every run and q2 (test) too, but only q2 is accuracy:
  # make the dev item wrong to see that it stays out.
  wrong_dev <- gr_mock_client(function(messages, params) {
    if (grepl("France", messages[[1]]$content)) "Lyon" else "Lima"
  })
  w <- hr_benchmark(ask_arm(), ref, runs = 5, client = wrong_dev, split = c("dev", "test"))
  out <- capture.output(print(w))
  expect_true(any(grepl("^ arm +accuracy +dev ", out)))
  expect_true(any(grepl("^ ask +1\\.000 +0\\.000 ", out)))
  # The default is the test split alone.
  expect_identical(unique(hr_benchmark(ask_arm(), ref, runs = 5,
                                       client = capital_client())$item), "q2")
  expect_error(hr_benchmark(ask_arm(), ref, runs = 5, client = capital_client(),
                            split = "final"), class = "hr_bad_reference")
  expect_error(hr_benchmark(ask_arm(), ref, runs = 5, client = capital_client(),
                            split = "train"), class = "gr_bad_setting")
})

test_that("the governor holds the whole benchmark, and refused runs are budget stops", {
  ref <- bench_ref()
  b <- hr_benchmark(ask_arm(), ref, runs = 5, client = capital_client(),
                    governor = hr_governor(max_calls = 7))
  expect_identical(nrow(b), 20L)
  expect_identical(attr(b, "trace")$calls, 7L)
  expect_identical(b$failure_kind[8:20], rep("budget_stop", 13))
  expect_false(any(b$correct[8:20]))
  expect_true(all(b$correct[1:7]))
  expect_true(all(is.na(b$outcome[8:20])))
  expect_identical(b$tokens_in[8:20], rep(0L, 13))
  expect_true(attr(b, "trace")$budget_stop)
  expect_identical(attr(b, "trace")$stop_reason, "calls")
  expect_output(print(b), "budget_stop")
  # An arm that turns a refusal into an error is a budget stop too.
  stopping <- hr_arm("stopping", function(item, ctx) {
    withCallingHandlers(ctx$call(paste0("Capital of ", item))$text,
                        hr_budget_refused = function(cnd) stop(cnd))
  })
  b <- hr_benchmark(stopping, ref, runs = 5, client = capital_client(),
                    governor = hr_governor(max_calls = 2))
  expect_identical(b$failure_kind[3:20], rep("budget_stop", 18))
})

test_that("an arm that fails is recorded as an error with its message in the run's trace", {
  ref <- hr_reference(list(q1 = "France"), "Paris", "a", split = "test")
  broken <- hr_arm("broken", function(item, ctx) stop("no route"))
  b <- hr_benchmark(broken, ref, runs = 5, client = NULL)
  expect_identical(b$failure_kind, rep("error", 5))
  expect_identical(b$correct, rep(FALSE, 5))
  st <- attr(b, "traces")[[1]]$steps[[1]]
  expect_identical(st$label, "bench.error")
  expect_identical(st$detail$message, "no route")
})

test_that("fewer than five runs warns, and the arms' random stream is private and seeded", {
  ref <- hr_reference(list(q1 = "x", q2 = "y"), c("1", "2"), "a", split = "test")
  dice <- hr_arm("dice", function(item, ctx) as.character(sample(1:2, 1)))
  expect_warning(hr_benchmark(dice, ref, runs = 2, client = NULL), class = "hr_few_runs")
  set.seed(99)
  before <- stats::runif(1)
  set.seed(99)
  a <- hr_benchmark(dice, ref, runs = 5, client = NULL, seed = 3)
  expect_identical(stats::runif(1), before)
  b <- hr_benchmark(dice, ref, runs = 5, client = NULL, seed = 3)
  expect_identical(a$outcome, b$outcome)
  expect_error(hr_benchmark(dice, ref, runs = 0, client = NULL), class = "gr_bad_setting")
  expect_error(hr_benchmark(dice, ref, runs = 2.5, client = NULL), class = "gr_bad_setting")
  expect_error(hr_benchmark(dice, ref, client = "x"), class = "gr_bad_setting")
  expect_error(hr_benchmark(dice, ref, client = NULL, scorer = function(...) TRUE),
               class = "hr_bad_scorer")
})

test_that("an arm is given its context", {
  got <- NULL
  spy <- hr_arm("spy", function(item, ctx) {
    got <<- ctx
    "x"
  }, params = list(temperature = 0))
  ref <- hr_reference(list(q1 = "x"), "x", "a", split = "test")
  gov <- hr_governor(max_calls = 50)
  b <- hr_benchmark(spy, ref, runs = 5, client = capital_client(), governor = gov)
  expect_identical(got$draw_index, 5L)
  expect_identical(got$run, 5L)
  expect_identical(got$item_id, "q1")
  expect_identical(got$arm, "spy")
  expect_identical(got$params, list(temperature = 0))
  expect_s3_class(got$trace, "gr_trace")
  expect_s3_class(got$governor, "hr_governor")
  expect_identical(got$governor$max_calls, 50)
  expect_identical(got$trace$run_id, b$ledger_id[5])
  expect_s3_class(got$client, "gr_mock_client")
})
