# A step that runs a program

`hr_step_command()` builds a step that runs one program you name, such
as `Rscript` on a test file, and reads its result as `"passed"` or
`"failed"`. Put it in a chain after the step that writes what it checks,
so a benchmark can count how often a draft passes.

## Usage

``` r
hr_step_command(
  name,
  argv,
  parse = c("exit", "testthat"),
  timeout = 60,
  held = FALSE,
  wd = NULL
)
```

## Arguments

- name:

  The step's name, one string.

- argv:

  The command: a character vector whose first element is the program and
  the rest its arguments, or a function of `(input, ctx)` that returns
  one, such as a vector that names a file the step before it wrote.

- parse:

  How the result is read: `"exit"` or `"testthat"`.

- timeout:

  Seconds the program may run before it is stopped, from 1 to 86400.

- held:

  Whether the result is kept from the steps after this one and left for
  the scorer.

- wd:

  The folder the program runs in, or `NULL` for the current one. The
  working directory is set back afterwards.

## Value

A step (see
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md))
of class `c("hr_step_command", "hr_step", "function")` with the settings
`parse`, `timeout` and `held`, which
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
and
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
change by path, as `"check.timeout"`. The result it records is a list of
class `hr_command_result`: `name`, `argv`, `status`, `exit` (the exit
code, or `NA`), `seconds`, `degradation` (`NA` unless timed out),
`counts` (for `"testthat"`: `fail`, `warn`, `skip` and `pass`, else
`NULL`), and `stdout` and `stderr`, each cut to its last 64 KB.

## Details

The command runs through base
[`system2()`](https://rdrr.io/r/base/system2.html) with the user's own
privileges. Each element of `argv` is one argument: they are quoted for
the shell, never split on spaces, so a `;` or a `$` in an argument
reaches the program as it is written. There is no default command, and a
command is never taken from a model's reply or a skill's text: write
`argv` yourself. Nothing isolates the program: it can read and write
what you can. The child process inherits the session's environment
variables, except `OPENAI_API_KEY`, which is unset for the call and put
back after it; R options never reach it. A program stopped at its time
limit is ended, but processes it started in the background (or that
ignore the signal) can keep running, on any platform; on Windows, any
process it started can.

The result is read by `parse`:

- `"exit"`:

  `"passed"` when the program exits with 0, else `"failed"`.

- `"testthat"`:

  The last `[ FAIL n | WARN n | SKIP n | PASS n ]` line the program
  printed: `"failed"` when `FAIL` is above 0, `"passed"` when it is 0
  and the program exits with 0. With no such line, or a summary of no
  failures and a non-zero exit, the status is `"error"`. The exit code
  alone is not read, since
  [`testthat::test_file()`](https://testthat.r-lib.org/reference/test_file.html)
  exits with 0 when a test fails unless it is given
  `stop_on_failure = TRUE`. Use a reporter that prints the summary line,
  such as the default, `"progress"` or `"check"`: under `"summary"` no
  such line is printed and the status is `"error"`.
  `stop_on_failure = TRUE` makes the exit code agree with the result.

A program stopped at `timeout` seconds is `"timeout"`, with the
degradation `"command_timeout"`, and a program that cannot be found is
`"error"`. No warning from
[`system2()`](https://rdrr.io/r/base/system2.html) reaches the caller.

With `held = FALSE` the step returns its input, a list, with the result
in `$check`, so the next step can read it (a revise step, say). With
`held = TRUE` the next step must not see it: the step returns its input
unchanged, records the status as the signal `"command.<step>"` (see
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)),
and attaches the result to the output as `attr(output, "hr_held")`, a
list named by step, which a scorer from
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
reads. A held step must come last:
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
refuses a step that is not held after one that is, with class
`hr_held_not_last`.

In a benchmark the step notes the run in the trace as a local step,
`"step.command"`, with hashes of `argv` and of the output, never the
output itself. It sends no request, so it costs nothing.

## See also

[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md),
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
rscript <- file.path(R.home("bin"), "Rscript")
check <- hr_step_command("check", c(rscript, "-e", "quit(status = 0)"))
check(list(draft = "x"), list())$check$status
#> [1] "passed"

# The command can depend on the step's input.
f <- tempfile(fileext = ".R")
writeLines("stopifnot(1 + 1 == 2)", f)
run_file <- hr_step_command("run", function(input, ctx) c(rscript, input$file))
run_file(list(file = f), list())$check$status
#> [1] "passed"

# Held back from later steps, for the scorer.
ref <- hr_reference(list(q1 = "f"), labels = "passed", cluster = "a", split = "test")
chain <- hr_chain(
  draft = hr_step("draft", function(input, ctx) list(item = input)),
  check = hr_step_command("check", c(rscript, "-e", "quit(status = 1)"),
                          held = TRUE),
  name = "held")
passes <- hr_scorer(function(item, output, label) {
  s <- attr(output, "hr_held")$check$status
  list(correct = identical(s, label), outcome = s, failure_kind = NA)
}, name = "passes")
bench <- hr_benchmark(chain, ref, runs = 5, client = NULL, scorer = passes)
table(bench$outcome)
#> 
#> failed 
#>      5 
unlink(f)
```
