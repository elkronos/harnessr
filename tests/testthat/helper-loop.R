# helper-loop.R: the coding loop of test-core-generality.R.
#
# A chain drafts an R function with a model, runs its tests, asks the model
# to revise a draft that failed, and runs the tests again as a held check
# that only the scorer sees. Every name it uses from the package is
# exported (test-core-generality.R checks this with codetools), so anyone
# can build the same loop from outside the package. The tasks are in
# fixtures/loop: each has a buggy first draft, the fixed version and a
# testthat file with two tests.

# The fixture folder, as an absolute path: hr_check_module() runs its
# closure in a temporary working directory.
loop_dir <- function() normalizePath(testthat::test_path("fixtures", "loop"), mustWork = TRUE)

loop_rscript <- function() file.path(R.home("bin"), "Rscript")

# A path as R code reads it inside single quotes on any platform.
loop_path <- function(path) gsub("\\\\", "/", path)

# The tasks, as a reference whose items say what to write, where the tests
# are and the folder drafts are written to. Every label is "passed": the
# held check should pass. Each task's test file is copied into its own
# folder under `work`, because testthat writes testthat-problems.rds next
# to a test file that fails, and that file must land in the temporary
# folder, never in the package's fixtures.
loop_reference <- function(tasks, work) {
  all <- utils::read.csv(file.path(loop_dir(), "tasks.csv"), stringsAsFactors = FALSE)
  all <- all[match(tasks, all$task), ]
  items <- lapply(seq_len(nrow(all)), function(i) {
    task <- all$task[[i]]
    dir <- file.path(work, task)
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    test <- file.path(dir, "test.R")
    stopifnot(file.copy(file.path(loop_dir(), task, "test.R"), test, overwrite = TRUE))
    list(task = task, prompt = all$prompt[[i]], test = test, work = work)
  })
  names(items) <- all$task
  hr_reference(items, labels = rep("passed", nrow(all)), cluster = all$task, split = "test")
}

# The stand-in model. It reads only the request: the task named on its
# first line, and whether the request reports failed tests. A first request
# gets the task's buggy draft, a request to fix one gets the fixed version.
# It keeps no state between requests, so every run of a benchmark gets the
# same replies.
loop_client <- function() {
  dir <- loop_dir()
  gr_mock_client(function(messages, params) {
    text <- messages[[length(messages)]]$content
    task <- sub("^Task: ([A-Za-z_]+).*$", "\\1", strsplit(text, "\n", fixed = TRUE)[[1]][1])
    file <- if (grepl("failed its tests", text, fixed = TRUE)) "fix.R" else "draft.R"
    paste(readLines(file.path(dir, task, file)), collapse = "\n")
  })
}

# The command that runs a task's tests on the current draft. The visible
# and the held check use different reporters, so their commands differ and
# a test can tell whether the held one reached a prompt.
loop_argv <- function(reporter) {
  force(reporter)
  function(input, ctx) {
    c(loop_rscript(), "-e", sprintf(
      "source('%s'); testthat::test_file('%s', stop_on_failure = TRUE, reporter = '%s')",
      loop_path(input$code), loop_path(input$test), reporter))
  }
}

# The draft step: ask for the function and write the reply to a file in the
# item's work folder.
loop_draft <- function() {
  hr_step("draft", function(input, ctx) {
    reply <- ctx$call(sprintf("Task: %s\n%s\nReply with R code only.",
                              input$task, input$prompt))
    code <- tempfile(paste0(input$task, "-"), tmpdir = input$work, fileext = ".R")
    writeLines(reply$text, code)
    list(task = input$task, test = input$test, code = code)
  })
}

# The revise step: when the visible check did not pass, send the code and
# what the tests printed, and write the reply over the draft.
loop_revise <- function() {
  hr_step("revise", function(input, ctx) {
    if (identical(input$check$status, "passed")) return(input)
    reply <- ctx$call(sprintf(
      "Task: %s\nThis code failed its tests:\n%s\nWhat the tests printed:\n%s\nReply with the fixed R code only.",
      input$task, paste(readLines(input$code), collapse = "\n"), input$check$stdout))
    writeLines(reply$text, input$code)
    input
  })
}

# The loop: draft, a visible check, revise, and a held check last.
loop_chain <- function(name = "loop") {
  hr_chain(draft = loop_draft(),
           check = hr_step_command("check", loop_argv("progress"), parse = "testthat"),
           revise = loop_revise(),
           held = hr_step_command("held", loop_argv("check"), parse = "testthat",
                                  held = TRUE),
           name = name)
}

# The held result of a run's output, or NULL.
loop_held <- function(output) attr(output, "hr_held", exact = TRUE)[["held"]]

# A scorer that reads only the held check. `keep`, when given, is an
# environment that collects every held result it sees.
loop_scorer <- function(keep = NULL) {
  hr_scorer(function(item, output, label) {
    held <- loop_held(output)
    if (!is.null(keep)) keep$held[[length(keep$held) + 1L]] <- held
    status <- if (is.null(held)) NA_character_ else held$status
    list(correct = identical(status, label), outcome = status, failure_kind = NA)
  }, name = "held_passes")
}

# The rules a run of the loop must meet, for hr_check_module().
loop_rules <- function() {
  list(
    returns_list = function(v) is.list(v),
    wrote_code = function(v) is.character(v$code) && file.exists(v$code),
    visible_check = function(v) {
      list(ok = inherits(v$check, "hr_command_result"),
           detail = "the visible check's result is in $check")
    },
    held_attached = function(v) {
      list(ok = inherits(loop_held(v), "hr_command_result"),
           detail = "the held check's result is in attr(output, \"hr_held\")")
    },
    held_passed = function(v) {
      held <- loop_held(v)
      list(ok = identical(held$status, "passed"),
           detail = sprintf("held status: %s", if (is.null(held)) "none" else held$status))
    })
}

# The context a chain gets outside a benchmark: the client and a call
# shortcut, as hr_benchmark() gives an arm.
loop_ctx <- function(client) {
  list(client = client, item_id = NA_character_,
       call = function(messages, ...) gr_call(client, messages, ...))
}

# Every message text the stand-in model was sent.
loop_prompts <- function(client) {
  unlist(lapply(client$calls(), function(call) {
    vapply(call$messages, function(m) as.character(m$content), character(1))
  }), use.names = FALSE)
}
