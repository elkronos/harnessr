# test-core-generality.R: a coding loop built from exported names only.
#
# The loop has nothing to do with documents: a model drafts an R function,
# a command step runs its tests, a revise step fixes a draft that failed,
# and a held check scores the result. That it runs as a benchmark arm,
# passes hr_check_module() and keeps its held check out of every prompt
# shows the core composes work of any kind. The chain is in helper-loop.R.

test_that("helper-loop.R uses only exported names from the package", {
  skip_if_not_installed("codetools")
  env <- new.env(parent = globalenv())
  sys.source(testthat::test_path("helper-loop.R"), envir = env)
  fns <- Filter(function(nm) is.function(env[[nm]]), ls(env))
  expect_true(length(fns) > 5L)
  pkg <- ls(asNamespace("harnessr"), all.names = TRUE)
  exported <- getNamespaceExports("harnessr")
  used <- unique(unlist(lapply(fns, function(nm) {
    codetools::findGlobals(env[[nm]], merge = TRUE)
  }), use.names = FALSE))
  used <- setdiff(used, fns)
  ours <- intersect(used, pkg)
  expect_true(all(c("hr_step", "hr_chain", "hr_step_command", "hr_scorer",
                    "hr_reference") %in% ours))
  expect_identical(setdiff(ours, exported), character(0))
  # Nor does it reach inside the package by `:::`.
  text <- readLines(testthat::test_path("helper-loop.R"))
  expect_false(any(grepl("harnessr:::", text, fixed = TRUE)))
})

test_that("one run of the loop passes hr_check_module() with the loop's rules", {
  work <- tempfile("hr-loop-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  chain <- loop_chain()
  item <- loop_reference("clamp", work)$items[[1]]
  cl <- loop_client()
  ctx <- loop_ctx(cl)
  report <- hr_check_module(chain$run, run = function() chain$run(item, ctx),
                            rules = loop_rules(), kind = "chain", name = chain$name)
  expect_s3_class(report, "hr_conformance")
  expect_identical(report$rule, c("is_function", "runs", names(loop_rules())))
  expect_true(all(report$ok), info = paste(report$rule, report$detail, collapse = "; "))
  # The core's step rules hold for the loop too: its held check is last and
  # attaches its result.
  ctx_steps <- loop_ctx(loop_client())
  steps <- hr_check_module(chain$run, run = function() chain$run(item, ctx_steps),
                           rules = harnessr:::hr_rules_step(chain), kind = "chain",
                           name = chain$name)
  expect_true(steps$ok[steps$rule == "held_attached"])
  expect_identical(steps$rule[!is.na(steps$ok) & !steps$ok], character(0))
  # The draft failed its visible check, so the model was asked to fix it.
  expect_length(cl$calls(), 2L)
  expect_match(cl$calls()[[2]]$messages[[1]]$content, "failed its tests", fixed = TRUE)

  # $check holds the visible result and the held one stays in the attribute:
  # their commands use different reporters, so a held result copied into
  # $check would show here.
  out <- chain$run(item, loop_ctx(loop_client()))
  expect_match(out$check$argv[[3]], "reporter = 'progress'", fixed = TRUE)
  expect_match(loop_held(out)$argv[[3]], "reporter = 'check'", fixed = TRUE)
  # A step after the held check could read its result, so hr_chain() refuses it.
  expect_error(hr_chain(draft = loop_draft(),
                        held = hr_step_command("held", loop_argv("check"),
                                               parse = "testthat", held = TRUE),
                        revise = loop_revise(), name = "held-early"),
               class = "hr_held_not_last")
})

test_that("the loop runs as a benchmark arm, one ledger per draw, and the passing attempt scores 1", {
  work <- tempfile("hr-loop-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  tasks <- c("clamp", "count_vowels", "last_n")
  ref <- loop_reference(tasks, work)
  loop <- loop_chain()
  # The same chain without the visible check and the revise step: the held
  # check then scores the first draft.
  first <- hr_chain(loop, check = NULL, revise = NULL, name = "first-draft")
  cl <- loop_client()
  keep <- new.env()
  keep$held <- list()
  bench <- withCallingHandlers(
    hr_benchmark(list(loop, first), ref, runs = 2, client = cl, scorer = loop_scorer(keep)),
    hr_few_runs = function(w) invokeRestart("muffleWarning"))

  expect_identical(nrow(bench), length(tasks) * 2L * 2L)
  # The loop's revised draft passes its held tests on every run; every
  # first draft is buggy and fails them.
  rate <- tapply(bench$correct, bench$arm, mean)
  expect_identical(as.numeric(rate[c("loop", "first-draft")]), c(1, 0))
  expect_true(all(bench$outcome[bench$arm == "loop"] == "passed"))
  expect_true(all(bench$outcome[bench$arm == "first-draft"] == "failed"))

  # One child ledger per draw: each arm and item has runs 1 and 2, each with
  # its own trace at that draw.
  traces <- attr(bench, "traces")
  expect_identical(names(traces), bench$ledger_id)
  expect_false(anyDuplicated(bench$ledger_id) > 0L)
  for (a in c("loop", "first-draft")) {
    for (t in tasks) {
      rows <- bench[bench$arm == a & bench$item == t, ]
      expect_identical(sort(rows$draw_index), 1:2)
    }
  }
  expect_identical(vapply(traces, function(tr) as.integer(tr$draw_index), integer(1)),
                   setNames(bench$draw_index, bench$ledger_id))
  # Every model request of a run went out at that run's draw.
  for (i in seq_along(traces)) {
    calls <- Filter(function(s) identical(s$label, "call"), traces[[i]]$steps)
    expect_true(length(calls) > 0L)
    sent <- vapply(calls, function(s) as.integer(s$params$draw_index), integer(1))
    expect_identical(unique(sent), bench$draw_index[[i]], info = bench$ledger_id[[i]])
  }
  # Each run of the loop noted both checks in its own trace; a first-draft
  # run noted only the held one.
  n_cmd <- vapply(traces, function(tr) {
    sum(vapply(tr$steps, function(s) identical(s$label, "step.command"), logical(1)))
  }, integer(1))
  expect_identical(unname(n_cmd), ifelse(bench$arm == "loop", 2L, 1L))
  # The held status is recorded as a signal of each run.
  sig <- hr_signals(bench, "command.held")
  expect_identical(nrow(sig), nrow(bench))
  expect_true(all(sig$value[sig$arm == "loop"] == "passed"))

  # The test files ran from copies in the work folder, so testthat wrote
  # its problems files there and nothing into the package's fixtures.
  for (item in ref$items) {
    expect_identical(normalizePath(dirname(dirname(item$test))), normalizePath(work))
  }
  expect_true(any(file.exists(file.path(work, tasks, "testthat-problems.rds"))))
  expect_length(list.files(loop_dir(), pattern = "^testthat-problems", recursive = TRUE), 0L)

  # Neither the held command nor what it printed reached any prompt.
  prompts <- loop_prompts(cl)
  expect_true(length(prompts) > 0L)
  expect_true(any(grepl("failed its tests", prompts, fixed = TRUE)))
  expect_length(keep$held, nrow(bench))
  # The held status comes from testthat's summary line: a passing run reports
  # both tests passed and none failed, a failing one reports failures.
  for (held in keep$held) {
    expect_identical(names(held$counts), c("fail", "warn", "skip", "pass"))
    if (identical(held$status, "passed")) {
      expect_identical(held$counts[c("fail", "pass")], list(fail = 0L, pass = 2L))
    } else {
      expect_gt(held$counts$fail, 0L)
    }
  }
  expect_identical(sum(vapply(keep$held, function(h) identical(h$status, "passed"), logical(1))),
                   sum(bench$arm == "loop"))
  for (held in keep$held) {
    expect_s3_class(held, "hr_command_result")
    pieces <- c(paste(held$argv, collapse = " "), held$argv[[3]], trimws(held$stdout))
    pieces <- pieces[nzchar(pieces)]
    for (p in pieces) {
      expect_false(any(grepl(p, prompts, fixed = TRUE)), info = p)
    }
  }
})

test_that("a task whose tests run past the time limit gives command_timeout", {
  work <- tempfile("hr-loop-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  ref <- loop_reference("slow_sum", work)
  slow <- hr_set(hr_chain(loop_chain(), check = NULL, revise = NULL, name = "slow"),
                 held.timeout = 1)
  expect_identical(slow$params$held.timeout, 1)
  out <- slow$run(ref$items[[1]], loop_ctx(loop_client()))
  held <- loop_held(out)
  expect_identical(held$status, "timeout")
  expect_identical(held$degradation, "command_timeout")
  expect_lt(held$seconds, 10)
})
