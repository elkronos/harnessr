# test-command.R: hr_step_command(), a step that runs a program the user names.
#
# Every command here is Rscript from R.home(), never one found on the PATH,
# so the tests run the R that runs them.

command_rscript <- function() file.path(R.home("bin"), "Rscript")

command_r <- function(code, ...) {
  hr_step_command("check", c(command_rscript(), "-e", code), ...)
}

command_testfile <- function(body) {
  f <- tempfile("hr-command-test-", fileext = ".R")
  writeLines(c("library(testthat)", body), f)
  f
}

command_testthat_argv <- function(f) {
  c(command_rscript(), "-e",
    sprintf("testthat::test_file('%s', stop_on_failure = TRUE)", gsub("\\\\", "/", f)))
}

test_that("a command step is an hr_step with three settings and no default command", {
  s <- command_r("quit(status = 0)")
  expect_s3_class(s, c("hr_step_command", "hr_step", "function"))
  expect_identical(names(attr(s, "schema")), c("parse", "timeout", "held"))
  expect_identical(attr(s, "resolved"), list(parse = "exit", timeout = 60, held = FALSE))
  expect_identical(attr(s, "params"), list())
  expect_error(hr_step_command("check"), class = "hr_bad_step")
  expect_error(hr_step_command("check", character(0)), class = "hr_bad_step")
  expect_error(hr_step_command("check", c(command_rscript(), NA)), class = "hr_bad_step")
  expect_error(hr_step_command("check", 1), class = "hr_bad_step")
  expect_error(hr_step_command("check", "x", wd = 1), class = "hr_bad_step")
  expect_error(hr_step_command("check", "x", parse = "junit"), class = "gr_bad_setting")
})

test_that("exit 0 passes and a non-zero exit fails, with nothing printed", {
  ok <- command_r("cat('fine')")
  expect_silent(r <- ok(list(draft = 1), list())$check)
  expect_s3_class(r, "hr_command_result")
  expect_identical(r$status, "passed")
  expect_identical(r$exit, 0L)
  expect_identical(r$stdout, "fine")
  expect_true(is.na(r$degradation))
  bad <- command_r("quit(status = 1)")
  expect_silent(r <- bad(list(draft = 1), list())$check)
  expect_identical(r$status, "failed")
  expect_identical(r$exit, 1L)
  expect_true(all(r$status %in% harnessr:::.hr_command_statuses))
})

test_that("a command stopped at its time limit is a timeout, with no warning", {
  slow <- command_r("Sys.sleep(5)", timeout = 1)
  expect_silent(r <- slow(list(), list())$check)
  expect_identical(r$status, "timeout")
  expect_identical(r$degradation, "command_timeout")
  expect_true(r$degradation %in% harnessr:::.hr_degradation_codes)
  expect_lt(r$seconds, 4)
})

test_that("a program that cannot be found is an error, not a failure", {
  s <- hr_step_command("check", file.path(tempdir(), "no-such-program"))
  r <- s(list(), list())$check
  expect_identical(r$status, "error")
  expect_true(is.na(r$exit))
})

test_that("parse = 'testthat' reads the summary line, never the exit code alone", {
  fail <- command_testfile("test_that('x', expect_equal(1, 2))")
  pass <- command_testfile("test_that('x', expect_equal(1, 1))")
  on.exit(unlink(c(fail, pass)), add = TRUE)
  rf <- hr_step_command("check", command_testthat_argv(fail), parse = "testthat")(list(), list())
  expect_identical(rf$check$status, "failed")
  expect_identical(rf$check$counts$fail, 1L)
  rp <- hr_step_command("check", command_testthat_argv(pass), parse = "testthat")(list(), list())
  expect_identical(rp$check$status, "passed")
  expect_identical(rp$check$counts, list(fail = 0L, warn = 0L, skip = 0L, pass = 1L))
  # Exit 0 with no summary line is an error under "testthat", a pass under "exit".
  none <- command_r("cat('no summary')", parse = "testthat")(list(), list())
  expect_identical(none$check$status, "error")
  expect_identical(none$check$exit, 0L)
  expect_null(none$check$counts)
  expect_identical(command_r("cat('no summary')")(list(), list())$check$status, "passed")
})

test_that("parse = 'testthat' needs a reporter that prints the summary line, not stop_on_failure", {
  fail <- command_testfile("test_that('x', expect_equal(1, 2))")
  on.exit(unlink(fail), add = TRUE)
  run <- function(stop, reporter) {
    argv <- c(command_rscript(), "-e", sprintf(
      "testthat::test_file('%s', stop_on_failure = %s, reporter = '%s')",
      gsub("\\\\", "/", fail), stop, reporter))
    hr_step_command("check", argv, parse = "testthat")(list(), list())$check
  }
  # Without stop_on_failure the run exits with 0, and is still "failed".
  r <- run("FALSE", "progress")
  expect_identical(r$status, "failed")
  expect_identical(r$exit, 0L)
  # stop_on_failure = TRUE only makes the exit code agree.
  r <- run("TRUE", "progress")
  expect_identical(r$status, "failed")
  expect_false(identical(r$exit, 0L))
  # The summary reporter prints no summary line, so the run is an error.
  expect_identical(run("TRUE", "summary")$status, "error")
})

test_that("the API key is unset for the command and put back after it", {
  old <- Sys.getenv("OPENAI_API_KEY", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("OPENAI_API_KEY") else Sys.setenv(OPENAI_API_KEY = old),
          add = TRUE)
  Sys.setenv(OPENAI_API_KEY = "sk-FAKE123")
  r <- command_r("cat('[', Sys.getenv('OPENAI_API_KEY'), ']', sep = '')")(list(), list())$check
  expect_identical(r$stdout, "[]")
  expect_false(grepl("sk-FAKE123", r$stdout, fixed = TRUE))
  expect_identical(Sys.getenv("OPENAI_API_KEY"), "sk-FAKE123")
  # Unset before the call stays unset after it.
  Sys.unsetenv("OPENAI_API_KEY")
  command_r("cat(1)")(list(), list())
  expect_true(is.na(Sys.getenv("OPENAI_API_KEY", unset = NA)))
})

test_that("shell metacharacters in an argument reach the program as written", {
  odd <- "a;b $HOME `echo x` \"q\" 'single' | > out.txt & *"
  wd <- tempfile("hr-command-wd-")
  dir.create(wd)
  on.exit(unlink(wd, recursive = TRUE), add = TRUE)
  s <- hr_step_command("check", c(command_rscript(), "-e", "cat(commandArgs(TRUE))", odd),
                       wd = wd)
  r <- s(list(), list())$check
  expect_identical(r$stdout, odd)
  expect_identical(list.files(wd), character(0))
})

test_that("wd is where the command runs, and the working directory is put back", {
  wd <- normalizePath(tempfile("hr-command-wd-"), mustWork = FALSE)
  dir.create(wd)
  on.exit(unlink(wd, recursive = TRUE), add = TRUE)
  here <- getwd()
  r <- hr_step_command("check", c(command_rscript(), "-e", "cat(normalizePath(getwd()))"),
                       wd = wd)(list(), list())$check
  expect_identical(r$stdout, normalizePath(wd))
  expect_identical(getwd(), here)
  gone <- hr_step_command("check", command_rscript(),
                          wd = file.path(wd, "missing"))(list(), list())$check
  expect_identical(gone$status, "error")
  expect_identical(getwd(), here)
})

test_that("argv can be a function of the input, and its result is checked", {
  f <- tempfile(fileext = ".R")
  writeLines("quit(status = 2)", f)
  on.exit(unlink(f), add = TRUE)
  s <- hr_step_command("run", function(input, ctx) c(command_rscript(), input$file))
  r <- s(list(file = f), list())$check
  expect_identical(r$exit, 2L)
  expect_identical(r$argv, c(command_rscript(), f))
  bad <- hr_step_command("run", function(input, ctx) 42)
  expect_error(bad(list(), list()), class = "hr_bad_step")
})

test_that("a visible step needs a list input and adds $check", {
  s <- command_r("quit(status = 0)")
  expect_error(s("text", list()), class = "hr_bad_step")
  out <- s(list(draft = "x", check = list(old = TRUE)), list())
  expect_identical(out$draft, "x")
  expect_null(out$check$old)
  expect_identical(out$check$status, "passed")
})

test_that("a held step passes its input on and attaches the result for the scorer", {
  s <- command_r("quit(status = 1)", held = TRUE)
  tr <- gr_trace()
  out <- s(list(draft = "x"), list(trace = tr, item_id = "q1", step = "check"))
  expect_identical(unclass(out)[["draft"]], "x")
  expect_null(out$check)
  expect_identical(attr(out, "hr_held")$check$status, "failed")
  sig <- hr_signals(tr)
  expect_identical(sig$signal, "command.check")
  expect_identical(sig$value, "failed")
  expect_identical(sig$item, "q1")
  expect_error(s(NULL, list()), class = "hr_bad_step")
})

test_that("the trace notes the run by hash, never its output", {
  s <- command_r("cat('secret-output-text')")
  tr <- gr_trace()
  s(list(), list(trace = tr))
  steps <- tr$steps
  expect_length(steps, 1L)
  expect_identical(steps[[1]]$label, "step.command")
  d <- steps[[1]]$detail
  expect_identical(sort(names(d)), sort(c("name", "argv_hash", "exit", "status", "seconds",
                                          "degradation", "stdout_hash")))
  expect_false(grepl("secret-output-text", paste(unlist(d), collapse = " "), fixed = TRUE))
  expect_identical(nrow(as.data.frame(tr)), 0L)
})

test_that("output is kept to its last 64 KB", {
  big <- command_r("cat(strrep('a', 70000), 'END', sep = '')")(list(), list())$check
  expect_identical(nchar(big$stdout, type = "bytes"), 65536L)
  expect_true(endsWith(big$stdout, "END"))
})

test_that("a held step must come last in a chain", {
  draft <- hr_step("draft", function(input, ctx) list(item = input))
  after <- hr_step("after", function(input, ctx) input)
  held <- command_r("quit(status = 0)", held = TRUE)
  expect_error(hr_chain(draft = draft, check = held, after = after, name = "c"),
               class = "hr_held_not_last")
  expect_error(hr_chain(draft = draft, check = held, after = after, name = "c"),
               class = "hr_bad_chain")
  # Held steps may follow each other, and a visible one may come first.
  visible <- command_r("quit(status = 0)")
  ch <- hr_chain(draft = draft, look = visible, check = held,
                 again = command_r("quit(status = 1)", held = TRUE), name = "c")
  expect_s3_class(ch, "hr_arm")
  # Making a middle step held through hr_set() is refused the same way.
  mid <- hr_chain(draft = draft, look = visible, after = after, name = "m")
  expect_error(hr_set(mid, look.held = TRUE), class = "hr_held_not_last")
})

test_that("a chain with a held check runs in a benchmark and the scorer reads the result", {
  ref <- hr_reference(list(q1 = "a", q2 = "b"), labels = c("passed", "passed"),
                      cluster = c("a", "b"), split = "test")
  draft <- hr_step("draft", function(input, ctx) list(item = input))
  chain <- hr_chain(draft = draft,
                    check = hr_step_command("check", function(input, ctx) {
                      c(command_rscript(), "-e",
                        sprintf("quit(status = %d)", as.integer(input$item == "b")))
                    }, held = TRUE), name = "held")
  passes <- hr_scorer(function(item, output, label) {
    s <- attr(output, "hr_held")$check$status
    list(correct = identical(s, label), outcome = s, failure_kind = NA)
  }, name = "passes")
  bench <- hr_benchmark(chain, ref, runs = 5, client = NULL, scorer = passes)
  expect_identical(tapply(bench$correct, bench$item, mean)[["q1"]], 1)
  expect_identical(tapply(bench$correct, bench$item, mean)[["q2"]], 0)
  expect_true(all(bench$usd == 0))
  sig <- hr_signals(bench)
  expect_setequal(unique(sig$signal), "command.check")
  expect_identical(nrow(sig), 10L)
})

test_that("a chain's command settings are set and swept by path", {
  draft <- hr_step("draft", function(input, ctx) list(item = input))
  chain <- hr_chain(draft = draft, check = command_r("quit(status = 0)"), name = "c")
  s <- hr_settings(chain)
  expect_identical(s$param[s$step == "check"], c("parse", "timeout", "held"))
  five <- hr_set(chain, check.timeout = 5)
  expect_identical(attr(attr(five, "hr_steps")$check, "resolved")$timeout, 5)
  expect_s3_class(attr(five, "hr_steps")$check, "hr_step_command")
  expect_false(identical(attr(five, "hr_config"), attr(chain, "hr_config")))
  same <- hr_set(chain, check.timeout = 60)
  expect_identical(attr(same, "hr_config"), attr(chain, "hr_config"))
  expect_warning(hr_set(chain, check.timeout = 0), class = "hr_param_clamped")
  arms <- hr_sweep(chain, data.frame(check.timeout = c(5, 60)))
  expect_length(arms, 2L)
})

test_that("no command run reaches a golden fixture", {
  dir <- test_path("fixtures")
  files <- list.files(dir, recursive = TRUE, full.names = TRUE,
                      pattern = "\\.(json|csv|rds|txt)$")
  files <- files[!grepl("api\\.json$|layers\\.csv$", files)]
  for (f in files[!grepl("\\.rds$", files)]) {
    text <- paste(readLines(f, warn = FALSE), collapse = "\n")
    expect_false(grepl("step.command", text, fixed = TRUE), info = f)
    expect_false(grepl("hr-cmd-", text, fixed = TRUE), info = f)
  }
})

test_that("a program named relative to wd is found and run there", {
  skip_on_os("windows")
  wd <- tempfile("hr-command-rel-")
  dir.create(wd)
  on.exit(unlink(wd, recursive = TRUE), add = TRUE)
  writeLines(c("#!/bin/sh", "echo RAN"), file.path(wd, "run.sh"))
  Sys.chmod(file.path(wd, "run.sh"), "755")
  here <- getwd()
  r <- hr_step_command("check", "./run.sh", wd = wd)(list(), list())$check
  expect_identical(r$status, "passed")
  expect_match(r$stdout, "RAN", fixed = TRUE)
  expect_identical(getwd(), here)
  # A program missing from wd is still reported as not found.
  gone <- hr_step_command("check", "./nope.sh", wd = wd)(list(), list())$check
  expect_identical(gone$status, "error")
  expect_match(gone$stderr, "was not found", fixed = TRUE)
  expect_identical(getwd(), here)
})

test_that("an explicit parse is recorded as the value the step uses", {
  rs <- command_rscript()
  full <- hr_step_command("check", rs, parse = c("exit", "testthat"))
  expect_identical(attr(full, "params")$parse, "exit")
  expect_identical(attr(full, "resolved")$parse, "exit")
  part <- hr_step_command("check", rs, parse = "test")
  expect_identical(attr(part, "params")$parse, "testthat")
  expect_identical(attr(hr_chain(check = full, name = "a"), "hr_config"),
                   attr(hr_chain(check = hr_step_command("check", rs, parse = "exit"),
                                 name = "a"), "hr_config"))
  expect_error(hr_step_command("check", rs, parse = "junit"), class = "gr_bad_setting")
})

test_that("a testthat count beyond integer range gives status 'error', not an error", {
  line <- "[ FAIL 99999999999 | WARN 0 | SKIP 0 | PASS 3 ]"
  r <- expect_no_warning(command_r(sprintf("cat('%s')", line),
                                   parse = "testthat")(list(), list())$check)
  expect_identical(r$status, "error")
})
