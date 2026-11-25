# Read a skill folder

`hr_skill()` reads a skill: a folder you chose that holds instructions
for one step of a run. Give the skill to a step with
`hr_step(..., skill = s)`; inside
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
the step's `ctx$call()` and `ctx$call_json()` then send the skill's
instructions and references as a system message before the step's own
messages, and `ctx$skill` holds the skill.

## Usage

``` r
hr_skill(path)
```

## Arguments

- path:

  The skill's folder, one string.

## Value

A list of class `hr_skill` with `name`, `description` and `version`
(`NULL` when the header has none), `instructions` (one string),
`references` (a named character vector of file texts, named by path
under `references/`), `scripts` (a named character vector of full paths,
named by path under `scripts/`), `path` (the folder's full path) and
`hash`.

## Details

The folder holds:

- `SKILL.md`:

  Required. It starts with a header between two lines that are exactly
  `---`. Each header line is `key: value`, with the value on the same
  line; matching quotes around it are removed. `name` is required, and
  `description` and `version` are kept. Any other key warns with class
  `hr_skill_unknown_key` and is ignored. A value that is indented,
  nested or spread over lines (`|` or `>`) is an error, since the header
  is read without a YAML parser. Everything after the closing `---` is
  the instructions.

- `references/`:

  Optional text files, added after the instructions. A file with a nul
  byte, or that is not UTF-8 text, is an error. Line endings are read as
  `"\n"`, so a CRLF copy gives the same text and hash.

- `scripts/`:

  Optional. The scripts are listed by path and never run. To run one,
  wrap it yourself in a command step, as in
  `hr_step_command("lint", c(rscript, s$scripts[["check.R"]]))`.

The folder is read only where you point: the package never looks for
skills, and a model never chooses one. A file that is a link to
somewhere outside the folder is an error, and so are a broken link, a
`references/` or `scripts/` folder that is a link to somewhere outside,
a link to a folder under either of them, and a folder with more than 50
reference files, more than 50 scripts, or more than 200,000 bytes in
all. These limits are fixed. All errors have class `hr_bad_skill`.

A skill's text goes into the prompt as it is, so a skill from someone
else can carry instructions you did not mean to send (prompt injection).
Read a skill before you use it.

The skill's `hash` covers the header, the instructions, each reference
and every byte of each script, so editing any of them changes it. A step
given a skill has the hash among its fixed settings and in its
fingerprint, so a chain with a skill has a different configuration from
the same chain without it, and a benchmark gets a `param.<step>.skill`
column naming the skill and the start of its hash.

## See also

[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)

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
[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
dir <- file.path(tempdir(), "units-skill")
dir.create(file.path(dir, "references"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("---", "name: units", "description: Give amounts with units.",
             "version: 1.0.0", "---",
             "Always state the unit and the currency of every amount."),
           file.path(dir, "SKILL.md"))
writeLines("Write million in full.", file.path(dir, "references", "style.md"))
s <- hr_skill(dir)
s
#> <hr_skill> units version 1.0.0 (1af7430e0b8c)
#>   Give amounts with units. 
#>   instructions: 55 characters
#>   references: style.md 

# In a chain, the step's requests carry the skill as a system message.
cl <- hr_mock_client(function(m, p) "45.2 million dollars")
ask <- hr_step("ask", function(input, ctx) ctx$call(input)$text, skill = s)
chain <- hr_chain(ask = ask, name = "with-skill")
chain$params
#> $ask.skill
#> [1] "units@1af7430e0b8c"
#> 
ref <- hr_reference(list(q1 = "What was revenue?"), labels = "45.2 million dollars",
                    cluster = "a", split = "test")
bench <- hr_benchmark(chain, ref, runs = 5, client = cl, scorer = hr_scorer_exact())
sent <- cl$calls()[[1]]$messages
vapply(sent, function(m) m$role, "")
#> [1] "system" "user"  
unique(bench$param.ask.skill)
#> [1] "units@1af7430e0b8c"
unlink(dir, recursive = TRUE)
```
