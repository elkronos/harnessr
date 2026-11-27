# core-verify-command.R: a step that runs a program the user names.
#
# hr_step_command() builds a step that runs one program with its arguments
# (a test file, a linter, a script) and reads its result as passed or
# failed. The user writes the command; the package never chooses one, never
# takes one from a model's reply and never isolates the program it runs. A
# command step sends no request, so it adds nothing to a run's cost, and a
# chain without one sends what it sent before.

#' The settings of a command step. The settings table reads the same
#' evidence from .gr_stage_evidence, and a test checks the two agree.
#' @noRd
.hr_command_schema <- hr_schema(
  hr_param("parse", "enum", default = "exit", choices = c("exit", "testthat"),
           help = "How the result is read: the exit code, or a testthat summary line.",
           cost_class = "local",
           evidence = ev_untested(paste0(
             "\"exit\" reads what every program reports; a choice, not a tuned value."))),
  hr_param("timeout", "number", default = 60, min = 1, max = 86400,
           help = "Seconds the program may run before it is stopped.",
           cost_class = "local", tier = "advanced",
           evidence = ev_untested(paste0(
             "A minute, enough for a small test file; set when the step was written, ",
             "not tuned."))),
  hr_param("held", "boolean", default = FALSE,
           help = "Whether the result is kept from the next step and left for the scorer.",
           cost_class = "none", tier = "advanced",
           evidence = ev_untested(paste0(
             "Off, so the result is visible to the steps after it; a choice for the ",
             "chain, not a tuned value."))))

#' The environment variables a command never sees, by name: a pattern list
#' matched without regard to case, and the names harnessr and the common
#' providers read in full. hr_options(command_hide_env =) adds patterns, and
#' a variable whose value is one of hr_options("api_headers") is hidden as
#' well (see command_hidden_env()).
#' @noRd
.hr_command_hidden_patterns <- c("_API_KEY$", "_TOKEN$", "_SECRET$", "_PASSWORD$", "_PAT$",
                                 "_SECRET_ACCESS_KEY$")

#' @noRd
.hr_command_hidden_names <- c("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GOOGLE_API_KEY",
                              "GEMINI_API_KEY", "AZURE_OPENAI_API_KEY", "GITHUB_PAT",
                              "GITHUB_TOKEN", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
                              "HF_TOKEN")

#' The fewest characters an api_headers value needs before a variable that
#' holds it is hidden: the length mask_secrets() needs to mask a value.
#' @noRd
.hr_command_header_min <- 8L

#' The most of a command's output, in bytes, kept in its result.
#' @noRd
.hr_command_output_cap <- 65536L

#' A step that runs a program
#'
#' `hr_step_command()` builds a step that runs one program you name, such as
#' `Rscript` on a test file, and reads its result as `"passed"` or
#' `"failed"`. Put it in a chain after the step that writes what it checks,
#' so a benchmark can count how often a draft passes.
#'
#' The command runs through base [system2()] with the user's own privileges.
#' Each element of `argv` is one argument: they are quoted for the shell,
#' never split on spaces, so a `;` or a `$` in an argument reaches the
#' program as it is written. There is no default command, and a command is
#' never taken from a model's reply or a skill's text: write `argv` yourself.
#' Nothing isolates the program: it can read and write what you can. It
#' inherits the session's environment variables except the ones that look
#' like credentials (see "Credentials" below); R options never reach it. A
#' program stopped at its time limit is ended,
#' but processes it started in the background (or that ignore the signal)
#' can keep running, on any platform; on Windows, any process it started
#' can.
#'
#' The result is read by `parse`:
#' \describe{
#'   \item{`"exit"`}{`"passed"` when the program exits with 0, else
#'     `"failed"`.}
#'   \item{`"testthat"`}{The last `[ FAIL n | WARN n | SKIP n | PASS n ]`
#'     line the program printed: `"failed"` when `FAIL` is above 0,
#'     `"passed"` when it is 0 and the program exits with 0. With no such
#'     line, or a summary of no failures and a non-zero exit, the status is
#'     `"error"`. The exit code alone is not read, since
#'     [testthat::test_file()] exits with 0 when a test fails unless it is
#'     given `stop_on_failure = TRUE`. Use a reporter that prints the
#'     summary line, such as the default, `"progress"` or `"check"`: under
#'     `"summary"` no such line is printed and the status is `"error"`.
#'     `stop_on_failure = TRUE` makes the exit code agree with the result.}
#' }
#' A program stopped at `timeout` seconds is `"timeout"`, with the
#' degradation `"command_timeout"`, and a program that cannot be found is
#' `"error"`. No warning from [system2()] reaches the caller.
#'
#' With `held = FALSE` the step returns its input, a list, with the result
#' in `$check`, so the next step can read it (a revise step, say). With
#' `held = TRUE` the next step must not see it: the step returns its input
#' unchanged, records the status as the signal `"command.<step>"` (see
#' [hr_signal()]), and attaches the result to the output as
#' `attr(output, "hr_held")`, a list named by step, which a scorer from
#' [hr_scorer()] reads. A held step must come last: [hr_chain()] refuses a
#' step that is not held after one that is, with class `hr_held_not_last`.
#'
#' In a benchmark the step notes the run in the trace as a local step,
#' `"step.command"`, with hashes of `argv` and of the output, never the output
#' itself, and `hidden_env`, the number of variables hidden from the program
#' (never their names or values). It sends no request, so it costs nothing.
#'
#' @section Credentials:
#' The child process inherits the session's environment variables except the
#' ones that look like credentials, which are unset for the call and put back
#' after it. A variable is hidden when its name ends in `_API_KEY`, `_TOKEN`,
#' `_SECRET`, `_PASSWORD`, `_PAT` or `_SECRET_ACCESS_KEY` (in any case), when
#' it is one of the provider variables `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
#' `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `AZURE_OPENAI_API_KEY`, `GITHUB_PAT`,
#' `GITHUB_TOKEN`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` and
#' `HF_TOKEN`, when its name matches a regular expression in
#' `hr_options(command_hide_env =)`, or when its value is one of the values of
#' `hr_options(api_headers =)` and 8 characters or longer, such as a gateway
#' key read with [Sys.getenv()]; a shorter header value, such as `"true"`, is
#' no credential and hides nothing.
#' A program that needs one of these variables cannot read it; pass what it
#' needs another way. `hr_options(command_temp_home = TRUE)` also runs the
#' program with `HOME` (and `USERPROFILE` on Windows) set to an empty folder
#' made for the call and removed after it, so it does not read your
#' configuration files and stored logins.
#'
#' With `hr_options(mask_secrets = TRUE)` the `stdout` and `stderr` kept in
#' the result have key-shaped strings replaced with `<masked>`, and the step
#' records how many in the trace as `masked`. The hash of the output is taken
#' before masking. [hr_options()] lists the shapes masked. This is hygiene,
#' not a sandbox: the program still runs with your permissions and can read
#' your files.
#'
#' @param name The step's name, one string.
#' @param argv The command: a character vector whose first element is the
#'   program and the rest its arguments, or a function of `(input, ctx)` that
#'   returns one, such as a vector that names a file the step before it
#'   wrote.
#' @param parse How the result is read: `"exit"` or `"testthat"`.
#' @param timeout Seconds the program may run before it is stopped, from 1
#'   to 86400.
#' @param held Whether the result is kept from the steps after this one and
#'   left for the scorer.
#' @param wd The folder the program runs in, or `NULL` for the current one.
#'   The working directory is set back afterwards.
#' @return A step (see [hr_step()]) of class
#'   `c("hr_step_command", "hr_step", "function")` with the settings
#'   `parse`, `timeout` and `held`, which [hr_set()] and [hr_sweep()] change
#'   by path, as `"check.timeout"`. The result it records is a list of class
#'   `hr_command_result`: `name`, `argv`, `status`, `exit` (the exit code, or
#'   `NA`), `seconds`, `degradation` (`NA` unless timed out), `counts` (for
#'   `"testthat"`: `fail`, `warn`, `skip` and `pass`, else `NULL`), and
#'   `stdout` and `stderr`, each cut to its last 64 KB.
#' @seealso [hr_step()], [hr_chain()], [hr_scorer()]
#' @family harness
#' @export
#' @examples
#' rscript <- file.path(R.home("bin"), "Rscript")
#' check <- hr_step_command("check", c(rscript, "-e", "quit(status = 0)"))
#' check(list(draft = "x"), list())$check$status
#'
#' # The command can depend on the step's input.
#' f <- tempfile(fileext = ".R")
#' writeLines("stopifnot(1 + 1 == 2)", f)
#' run_file <- hr_step_command("run", function(input, ctx) c(rscript, input$file))
#' run_file(list(file = f), list())$check$status
#'
#' # Held back from later steps, for the scorer.
#' ref <- hr_reference(list(q1 = "f"), labels = "passed", cluster = "a", split = "test")
#' chain <- hr_chain(
#'   draft = hr_step("draft", function(input, ctx) list(item = input)),
#'   check = hr_step_command("check", c(rscript, "-e", "quit(status = 1)"),
#'                           held = TRUE),
#'   name = "held")
#' passes <- hr_scorer(function(item, output, label) {
#'   s <- attr(output, "hr_held")$check$status
#'   list(correct = identical(s, label), outcome = s, failure_kind = NA)
#' }, name = "passes")
#' bench <- hr_benchmark(chain, ref, runs = 5, client = NULL, scorer = passes)
#' table(bench$outcome)
#' unlink(f)
hr_step_command <- function(name, argv, parse = c("exit", "testthat"), timeout = 60,
                            held = FALSE, wd = NULL) {
  if (missing(name) || !is_bench_string(name)) {
    gr_abort("`name` must be one non-blank string.", class = c("hr_bad_step", "gr_bad_setting"))
  }
  what <- sprintf("Command step '%s'", name)
  if (missing(argv)) {
    gr_abort(sprintf("%s needs `argv`: the program and its arguments. There is no default.",
                     what), class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (!is.function(argv)) argv <- command_check_argv(argv, what)
  if (!is.null(wd) && !is_bench_string(wd)) {
    gr_abort(sprintf("%s: `wd` must be NULL or one folder.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  params <- list()
  # The value the step uses is recorded, so `parse = c("exit", "testthat")`
  # is "exit" and "test" is "testthat"; a value that matches no choice is
  # left for the schema to refuse.
  if (!missing(parse)) params$parse <- tryCatch(match.arg(parse), error = function(e) parse)
  if (!missing(timeout)) params$timeout <- timeout
  if (!missing(held)) params$held <- held
  build <- command_build(name, argv, wd)
  step <- hr_step(name, build = build, params = params, schema = .hr_command_schema,
                  version = "0.1.0")
  class(step) <- c("hr_step_command", class(step))
  step
}

#' The `build` function of a command step: the step's function from its
#' settings, with the command and folder it was given.
#' @noRd
command_build <- function(name, argv, wd) {
  force(name)
  force(argv)
  force(wd)
  function(p) {
    force(p)
    function(input, ctx) {
      ctx <- if (is.list(ctx)) ctx else list()
      step <- if (is_bench_string(ctx[["step"]])) ctx[["step"]] else name
      what <- sprintf("Command step '%s'", step)
      args <- if (is.function(argv)) command_check_argv(argv(input, ctx), what) else argv
      res <- command_exec(step, args, p$parse, p$timeout, wd)
      trace <- ctx[["trace"]]
      note <- list(
        name = step, argv_hash = hr_hash(args), exit = res$exit, status = res$status,
        seconds = res$seconds, degradation = res$degradation,
        stdout_hash = res$stdout_hash, hidden_env = res$hidden_env)
      if (!is.null(res$masked)) note$masked <- res$masked
      trace_note(trace, "step.command", note)
      res$stdout_hash <- NULL
      res$hidden_env <- NULL
      res$masked <- NULL
      if (isTRUE(p$held)) {
        if (is.null(input)) {
          gr_abort(sprintf("%s is held, so it passes its input on, but its input is NULL.",
                           what), class = "hr_bad_step")
        }
        hr_signal(paste0("command.", step), res$status, trace = trace,
                  item_id = as_chr1(ctx[["item_id"]], NA_character_))
        held <- attr(input, "hr_held", exact = TRUE)
        if (!is.list(held)) held <- list()
        held[[step]] <- res
        attr(input, "hr_held") <- held
        return(input)
      }
      if (!is.list(input)) {
        gr_abort(sprintf(paste0("%s returns its input with the result in `$check`, so its ",
                                "input must be a list; it is %s."), what, class(input)[1]),
                 class = "hr_bad_step")
      }
      input["check"] <- list(res)
      input
    }
  }
}

#' Check a command: a character vector, at least one element, none NA or
#' empty.
#' @noRd
command_check_argv <- function(argv, what) {
  if (!is.character(argv) || !length(argv) || anyNA(argv) || !nzchar(argv[[1]])) {
    gr_abort(sprintf(paste0("%s: `argv` must be a character vector with the program first ",
                            "and no NA, or a function of (input, ctx) that returns one."), what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  unname(argv)
}

#' Run a command and read its result. The variables that look like
#' credentials are unset for the call (and HOME pointed at an empty folder
#' when asked), the working directory set and put back, and system2()'s
#' warnings about a time limit or a failed start are turned into statuses.
#' @noRd
command_exec <- function(name, argv, parse, timeout, wd) {
  out <- tempfile("hr-cmd-out-")
  err <- tempfile("hr-cmd-err-")
  on.exit(unlink(c(out, err)), add = TRUE)
  started <- proc.time()[["elapsed"]]
  hidden <- command_hidden_env()
  mask <- isTRUE(hr_options("mask_secrets"))
  result <- function(status, exit, stdout = "", stderr = "", counts = NULL) {
    # The hash is of what the program printed, before any masking.
    hash <- hr_hash(stdout)
    masked <- NULL
    if (mask) {
      m_out <- mask_secrets(stdout, values = hidden)
      m_err <- mask_secrets(stderr, values = hidden)
      stdout <- m_out$text
      stderr <- m_err$text
      masked <- m_out$n + m_err$n
    }
    structure(list(
      name = name, argv = argv, status = status, exit = exit,
      seconds = round(proc.time()[["elapsed"]] - started, 3),
      degradation = if (identical(status, "timeout")) .hr_degradation_codes[["command_timeout"]]
                    else NA_character_,
      counts = counts, stdout = command_tail(stdout), stderr = command_tail(stderr),
      stdout_hash = hash, hidden_env = length(hidden), masked = masked),
      class = "hr_command_result")
  }
  if (!is.null(wd) && !dir.exists(wd)) {
    return(result("error", NA_integer_, stderr = sprintf("The folder '%s' does not exist.", wd)))
  }
  # The folder is set first, so a program named by a path relative to `wd`
  # (as "./run.sh") is looked up there.
  if (!is.null(wd)) {
    old <- setwd(wd)
    on.exit(setwd(old), add = TRUE)
  }
  if (!nzchar(Sys.which(argv[[1]]))) {
    return(result("error", NA_integer_,
                  stderr = sprintf("The program '%s' was not found.", argv[[1]])))
  }
  if (length(hidden)) {
    Sys.unsetenv(names(hidden))
    on.exit(do.call(Sys.setenv, as.list(hidden)), add = TRUE)
  }
  if (isTRUE(hr_options("command_temp_home"))) {
    home <- tempfile("hr-cmd-home-")
    dir.create(home)
    vars <- c("HOME", if (.Platform$OS.type == "windows") "USERPROFILE")
    before <- Sys.getenv(vars, unset = NA, names = TRUE)
    do.call(Sys.setenv, as.list(stats::setNames(rep(home, length(vars)), vars)))
    on.exit({
      set <- before[!is.na(before)]
      if (length(set)) do.call(Sys.setenv, as.list(set))
      if (any(is.na(before))) Sys.unsetenv(names(before)[is.na(before)])
      unlink(home, recursive = TRUE)
    }, add = TRUE)
  }
  timed_out <- FALSE
  # system2() quotes the program itself; the arguments are quoted here, as
  # it passes them to the shell as they are.
  exit <- withCallingHandlers(
    tryCatch(system2(argv[[1]], shQuote(argv[-1]), stdout = out, stderr = err,
                     timeout = timeout),
             error = function(e) NA_integer_),
    warning = function(w) {
      if (grepl("timed out", conditionMessage(w), fixed = TRUE)) timed_out <<- TRUE
      invokeRestart("muffleWarning")
    })
  exit <- as.integer(exit)[1]
  stdout <- command_read(out)
  stderr <- command_read(err)
  if (timed_out || identical(exit, 124L)) {
    return(result("timeout", exit, stdout, stderr))
  }
  if (is.na(exit)) return(result("error", exit, stdout, stderr))
  if (identical(parse, "testthat")) {
    counts <- command_testthat_counts(stdout)
    status <- if (is.null(counts) || anyNA(unlist(counts))) "error"
              else if (counts[["fail"]] > 0L) "failed"
              else if (exit == 0L) "passed" else "error"
    return(result(status, exit, stdout, stderr, counts = counts))
  }
  result(if (exit == 0L) "passed" else "failed", exit, stdout, stderr)
}

#' The environment variables a command is not shown, as a named character
#' vector of their values: those whose name matches
#' .hr_command_hidden_patterns or the patterns of
#' hr_options("command_hide_env"), those named in .hr_command_hidden_names,
#' and those whose value is one of hr_options("api_headers") and at least
#' .hr_command_header_min characters long.
#' @noRd
command_hidden_env <- function() {
  env <- Sys.getenv()
  env <- stats::setNames(as.character(env), names(env))
  if (!length(env)) return(character(0))
  nm <- names(env)
  pats <- c(.hr_command_hidden_patterns, as.character(hr_options("command_hide_env")))
  hit <- nm %in% .hr_command_hidden_names
  for (p in pats) hit <- hit | grepl(p, nm, ignore.case = TRUE, perl = TRUE)
  headers <- unlist(hr_options("api_headers") %||% list(), use.names = FALSE)
  headers <- as.character(headers)
  # A short header value, such as "true" or a team name, is no credential,
  # and a variable that happens to hold it stays visible.
  headers <- headers[!is.na(headers) & nchar(headers) >= .hr_command_header_min]
  if (length(headers)) hit <- hit | (env %in% headers & nzchar(env))
  env[hit]
}

#' A file's text, or "" when it is missing; a nul byte is dropped.
#' @noRd
command_read <- function(path) {
  n <- file.size(path)
  if (is.na(n) || n == 0) return("")
  b <- readBin(path, "raw", n)
  rawToChar(b[b != as.raw(0L)])
}

#' The last 64 KB of a command's output.
#' @noRd
command_tail <- function(x) {
  b <- charToRaw(x)
  if (length(b) <= .hr_command_output_cap) return(x)
  x <- rawToChar(utils::tail(b, .hr_command_output_cap))
  iconv(x, "UTF-8", "UTF-8", sub = "")
}

#' The counts on the last testthat summary line of a command's output, or
#' NULL when there is none.
#' @noRd
command_testthat_counts <- function(text) {
  pat <- "\\[ FAIL ([0-9]+) \\| WARN ([0-9]+) \\| SKIP ([0-9]+) \\| PASS ([0-9]+) \\]"
  hits <- regmatches(text, gregexpr(pat, text))[[1]]
  if (!length(hits)) return(NULL)
  # A count too large for an integer becomes NA, which the caller reads as
  # "error"; text a program prints never makes the step fail with an error.
  n <- suppressWarnings(as.integer(regmatches(hits[length(hits)],
                                              gregexpr("[0-9]+", hits[length(hits)]))[[1]]))
  list(fail = n[1], warn = n[2], skip = n[3], pass = n[4])
}

#' Whether a step is a held command step.
#' @noRd
step_held <- function(s) {
  inherits(s, "hr_step_command") && isTRUE(attr(s, "resolved", exact = TRUE)$held)
}
