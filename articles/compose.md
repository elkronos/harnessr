# Composing steps into chains

A step does one part of a run: a model call, a check, a program to run,
or a stage of the document layer.
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
runs steps in order as one arm. That arm is an ordinary
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
so
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
compares it with recipes and with other chains on the same labelled
questions, as
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
does for recipes. A recipe such as `needle` runs a fixed sequence of
stages: segment the document, rank the chunks, read the best. A chain
can add what a recipe lacks, such as a check after the answer or a step
that rewrites the question.

Steps and chains are part of the core. Most examples below chain the
document layer’s stages over the example report, because a short
document makes each step’s input and output easy to see. The coding
sub-agent near the end reads no document. A step makes its requests
through its `ctx`, so the trace, the limits and the cache apply to them
as to any call
([`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md)
and
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)).

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
passes each step’s output to the next step. A step’s settings come from
its schema and reach it as `ctx$step_params`. No step that is not held
may follow a held command step:

![hr_chain() runs ingest (document in, doc out), segment (doc in, chunks
out), retrieve (chunks in, chunks out) and read (chunks in, answer out),
each step handing its output to the next. Settings declared with
hr_param() and hr_schema() pass through hr_step() and hr_validate() to
ctx\$step_params; hr_settings() lists them by path, hr_set() changes
them and hr_sweep() makes one arm per row. A coding loop runs draft,
visible check, revise and held check, and the held command step comes
last.](../reference/figures/composition.svg)

Everything here runs offline on a stand-in model.

``` r

library(harnessr)
old <- hr_options(verbose = FALSE, embedder = "lexical")
cl <- hr_mock_client(function(messages, params) {
  if (grepl("You grade one response", messages[[1]]$content, fixed = TRUE)) {
    return('{"verdict": "pass", "reason": "It gives the figure."}')
  }
  "Revenue was 45.2 million dollars."
})
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?"),
  documents = gr_example(), answers = list("45.2 million"), split = "test")
```

## Steps

A step is a function of `(input, ctx)` that does one part of a run.
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
builds a step for a document stage: `"ingest"`, `"segment"` or `"read"`.
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
builds a step that ranks the chunks and keeps the best without asking
for an answer. Both take the settings the stage’s spec takes, and both
check them when they build the step:

``` r

gr_step_retrieve(top_k = 4)
#> <gr_step> retrieve (retrieve): top_k=4
try(gr_step("read", reader = "no_such_reader"))
#> Error in registry_get("reader", spec$reader) : 
#>   Unknown reader 'no_such_reader'. Registered: ensemble, extract, hierarchical, iterative, map_reduce, preview, refine, rerank, retrieve, screen, skim, stuff.
```

[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
builds a step of your own. Inside a chain, `ctx` is the context that
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
gives an arm: its client, its trace, the `judge` and `note` shortcuts,
and `params`. `ctx$step` holds the step’s name and `ctx$step_params` its
settings. The step below grades the answer with a model and records the
verdict as a signal of the run:

``` r

judge <- hr_step("judge", function(a, ctx) {
  j <- ctx$judge(a$answer, mode = "grade", reference = "45.2 million",
                 rubric = "Does it give the figure?", orders = 1)
  ctx$note("judged", j$verdicts$verdict[1])
  a
}, input = "answer", output = "answer")
```

The optional `input` and `output` arguments declare what a step takes
and returns: `"document"`, `"doc"`, `"chunks"`, `"answer"` or `"state"`.
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
uses them to check the order of the steps.

## Chains

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
runs its steps in order. The first step gets the item, each later step
gets what the step before it returned, and the chain returns what the
last step returns. The name you give each argument is that step’s name
in the chain.

``` r

checked <- hr_chain(segment = gr_step("segment"),
                    retrieve = gr_step_retrieve(top_k = 4),
                    read = gr_step("read", reader = "stuff"),
                    judge = judge, name = "checked")
checked
#> <hr_arm checked> version 0.0.1
#>   params: retrieve.top_k = 4, read.reader = stuff 
#>   hash: 8e8f4986488f
```

The arm records each step’s settings as `"step.setting"`, so a benchmark
of `checked` has a `param.retrieve.top_k` column. To derive one chain
from another, pass the old chain and name the steps to change:

- `NULL` drops a step.
- A step under an existing name replaces that step where it stands.
- A step under a new name goes at the end.

``` r

nojudge <- hr_chain(checked, judge = NULL, name = "nojudge")
wider <- hr_chain(checked, retrieve = gr_step_retrieve(top_k = 8), name = "wider")
names(attr(wider, "hr_steps"))
#> [1] "segment"  "retrieve" "read"     "judge"
```

The three chains run side by side like any other arms. Each run sends
its requests at its own draw, so a cache does not hand one run’s reply
to the next (“Repeated draws” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)):

``` r

bench <- hr_benchmark(list(checked, nojudge, wider), ref, runs = 5, client = cl,
                      scorer = gr_scorer_answer())
aggregate(correct ~ arm + param.retrieve.top_k, bench, mean)
#>       arm param.retrieve.top_k correct
#> 1 checked                    4       1
#> 2 nojudge                    4       1
#> 3   wider                    8       1
head(hr_signals(bench, "judged")[, c("arm", "run", "item", "value")], 3)
#>       arm run    item value
#> 1 checked   1 revenue  pass
#> 2 checked   2 revenue  pass
#> 3 checked   3 revenue  pass
```

### What a chain checks when it is built

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
warns with class `hr_chain_gap` when a step takes chunks and no step
before it returns them. Without the warning, a read step would cut the
document at the default settings without saying so. A segment step first
in a chain does not warn, though it reads the document at the default
ingest settings; put an ingest step before it to choose them.

After a step that returns the answer, only steps that take `"answer"` or
`"state"`, or declare nothing, can follow.

``` r

tryCatch(hr_chain(read = gr_step("read", reader = "stuff"), name = "gap"),
         hr_chain_gap = function(w) conditionMessage(w))
#> [1] "Chain 'gap': step 'read' takes chunks, but no step before it returns them, so it will cut the document into chunks at the default settings. Add a segment step before it to choose them."
try(hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
             retrieve = gr_step_retrieve(), name = "late"))
#> Error in chain_check_order(steps, what) : 
#>   Chain 'late': step 'retrieve' takes "chunks", but it comes after step 'read', which returns the answer. After an answer only steps that take "answer" or "state" can follow.
```

Step names cannot repeat, and they cannot contain a dot, because
settings are named `"step.setting"`.

### When two chains are the same

A chain’s configuration is a hash of its steps’ code, the values that
code reads, and their resolved settings. Two chains with the same
configuration send the same requests, and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
warns with class `hr_same_config` when you ask it to compare them. A
setting given at its default gives the same configuration as the setting
left out:

``` r

a <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(), name = "a")
b <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = 6),
              name = "b")
identical(attr(a, "hr_config"), attr(b, "hr_config"))
#> [1] TRUE
```

## Registering a step

[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
files a module in the registry under a kind. The kinds are
`"extractor"`, `"cleaner"`, `"segmenter"`, `"reader"`, `"embedder"`,
`"protocol"` and `"step"`. The first six belong to the document layer,
and
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
registers them. For any other kind,
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
raises an error of class `hr_unknown_kind`.

A step from
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
registers under the kind `"step"`. Its version is the step’s own unless
you give
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
another:

``` r

hr_register("step", "shout", fn = hr_step("shout", function(input, ctx) toupper(input),
                                          input = "answer", output = "state",
                                          version = "0.2.0"))
hr_modules("step")[, c("name", "input", "output", "version", "contract")]
#>    name  input output version contract
#> 1 shout answer  state   0.2.0      0.2
```

[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
with no kind lists the modules of every kind in one table, with the call
stems each declares as a list column. Give it a kind, as above, to add
that kind’s own columns:

``` r

m <- hr_modules()
table(m$kind)
#> 
#>   cleaner  embedder extractor  protocol    reader segmenter      step 
#>        14         2         6         4        12         9         1
```

### Checking a module

[`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md)
runs a module once and reports which of your rules it breaks. It works
for a module of any kind. Give it three things:

- the module’s function;
- a closure of no arguments that runs the module once;
- a named list of rules, each a function of the value the closure
  returned.

A rule returns `TRUE`, `FALSE`, `NA` (could not be checked), or a list
with `ok` and a `detail` string. The closure runs in a temporary working
directory that
[`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md)
removes afterwards, and the `runs` rule reports any error the closure
raises.

``` r

double_it <- function(x) x * 2
hr_check_module(double_it, function() double_it(2),
  rules = list(numeric = function(v) is.numeric(v),
               above_three = function(v) list(ok = v > 3, detail = sprintf("got %s", v))),
  kind = "function", name = "double_it")
#> <hr_conformance> function 'double_it', contract 0.2
#>   passes all 4 rules
#>   ok    is_function
#>   ok    runs
#>   ok    numeric
#>   ok    above_three: got 4
```

The reader and segmenter checks of the document layer use it (“Checking
a module against the contract” in
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)).

## Settings and sweeps

Every step built with a schema has settings:

- a
  [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  step has the settings the stage’s spec takes;
- a
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  step has the ranking settings;
- a step of your own has the settings its `schema` declares.

In a chain, each setting is named by its path, `"step.setting"`.
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
lists them all. For each one it gives the value the step resolved,
whether you gave it, and the default, range and evidence the schema
declares:

``` r

s <- hr_settings(checked)
nrow(s)
#> [1] 71
s[s$set, c("step", "param", "value", "default", "range")]
#>        step  param value    default      range
#> 21 retrieve  top_k     4          6 [1, 10000]
#> 35     read reader stuff map_reduce
s[s$step == "retrieve", c("param", "value", "range", "status")]
#>            param   value       range   status
#> 21         top_k       4  [1, 10000] untested
#> 22     min_score    -Inf             untested
#> 23           mmr       1      [0, 1] untested
#> 24       bm25_k1     1.5     [0, 10]    cited
#> 25        bm25_b    0.75      [0, 1]    cited
#> 26 lexical_blend     0.5      [0, 1] untested
#> 27        fusion default default|rrf untested
#> 28         rrf_k      60  [1, 10000]    cited
```

[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
builds the chain again with some settings changed and the rest as they
were. It builds each changed step again from its settings, so the new
values go through the same checks as when the step was first built. The
new chain has the configuration of its new settings:

``` r

wide <- hr_set(checked, retrieve.top_k = 8, read.max_answer_tokens = 400)
wide$params
#> $retrieve.top_k
#> [1] 8
#> 
#> $read.reader
#> [1] "stuff"
#> 
#> $read.max_answer_tokens
#> [1] 400
identical(attr(wide, "hr_config"), attr(checked, "hr_config"))
#> [1] FALSE
```

A number outside its range moves to the nearest bound with a warning of
class `hr_param_clamped`. A path that is not a setting of a step’s
schema is an error of class `hr_unknown_setting`, and its message lists
the step’s settings.

[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
cannot change a setting that a step keeps fixed either.
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md),
for example, keeps a `max_answer_tokens` you give it fixed: it passes
the value to the read spec and does not rank by it. To change a fixed
setting, build the step again and replace it with
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md).

``` r

tryCatch(hr_set(checked, retrieve.top_k = 50000),
         hr_param_clamped = function(w) conditionMessage(w))
#> [1] "`top_k` 50000 is outside [1, 10000]; using 10000."
try(hr_set(checked, retrieve.topk = 8))
#> Error in hr_set(checked, retrieve.topk = 8) : 
#>   'retrieve.topk' is not a setting of chain 'checked'. Settings of 'retrieve': retrieve.top_k, retrieve.min_score, retrieve.mmr, retrieve.bm25_k1, retrieve.bm25_b, retrieve.lexical_blend, retrieve.fusion, retrieve.rrf_k.
```

For a single step, the setting’s own name is enough:
`hr_set(gr_step_retrieve(), top_k = 2)`.

[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
takes a chain and a grid whose columns are paths, and builds one chain
per row with
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md).
Each arm records its settings, so you can group the benchmark by its
`param.retrieve.top_k` column. When a row builds the configuration of an
earlier row,
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
drops it with a message of class `hr_sweep_collapsed`.

``` r

arms <- hr_sweep(nojudge, data.frame(retrieve.top_k = c(2, 4, 8)))
names(arms)
#> [1] "nojudge:retrieve.top_k=2" "nojudge:retrieve.top_k=4"
#> [3] "nojudge:retrieve.top_k=8"
bench <- hr_benchmark(arms, ref, runs = 5, client = cl, scorer = gr_scorer_answer())
aggregate(correct ~ param.retrieve.top_k, bench, mean)
#>   param.retrieve.top_k correct
#> 1                    2       1
#> 2                    4       1
#> 3                    8       1
```

Changing a setting the chain’s steps never use changes nothing that is
sent, so a sweep over it compares the chain with itself.
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
finds such settings from the requests each arm sent. Here the read step
sends every chunk it gets, so its own `top_k` does nothing:

``` r

stuffed <- hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
                    name = "stuffed")
bench <- hr_benchmark(hr_sweep(stuffed, list(read.top_k = c(2, 8))), ref, runs = 5,
                      client = cl, scorer = gr_scorer_answer())
hr_sweep_check(bench)
#>                    arm              same_as runs requests           settings
#> 1 stuffed:read.top_k=8 stuffed:read.top_k=2    5        5 read.top_k: 2 vs 8
```

A swept chain is a chain like any other: you can derive a chain from it
with
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
and change it further with
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md).

A replay of a recorded benchmark (“Replaying a run” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md))
matches each run’s sampled requests by the arm’s name. A renamed or
swept chain therefore does not replay a recording made under another
name; record the benchmark again under the new names.

## Skills

A skill is a folder of instructions for one step. It holds:

- a `SKILL.md` file with a short header and the instructions;
- optional text files under `references/`;
- optional scripts under `scripts/`.

[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md)
reads a folder you choose. harnessr never looks for skills on its own,
and a model never chooses one: you pick the skill and the step it goes
to.

The header sits between two `---` lines.
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md)
reads it without a YAML parser, so each line is a plain `key: value`.
`name` is required, and
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md)
keeps `description` and `version`. Any other key warns with class
`hr_skill_unknown_key`, and a nested or multi-line value is an error of
class `hr_bad_skill`. The example writes this skill into a temporary
folder:

``` r

skill_dir <- file.path(tempdir(), "units-skill")
dir.create(file.path(skill_dir, "references"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("---",
             "name: units",
             "description: State every amount with its unit and currency.",
             "version: 1.0.0",
             "---",
             "Give every amount with its unit and its currency, as in",
             "'45.2 million dollars', never a bare number."),
           file.path(skill_dir, "SKILL.md"))
writeLines("Write 'million' in full; do not write 'M' or 'mn'.",
           file.path(skill_dir, "references", "style.md"))
units <- hr_skill(skill_dir)
units
#> <hr_skill> units version 1.0.0 (f1cdea95dadd)
#>   State every amount with its unit and currency. 
#>   instructions: 100 characters
#>   references: style.md
```

harnessr puts the skill’s text into the prompt as it is written. A skill
from someone else can carry instructions you did not mean to send
(prompt injection), so read a skill before you use it. harnessr lists
the scripts and never runs them. To run one, wrap it in a command step
yourself, as in
`hr_step_command("lint", c(rscript, units$scripts[["check.R"]]))`.

Give a skill to a step of your own with `hr_step(skill = )`. Inside a
chain, the step’s `ctx$call()` and `ctx$call_json()` then send the
instructions and the references as a system message before the step’s
own messages, and `ctx$skill` holds the skill. The built-in steps of
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
and
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
refuse a skill, because they build their requests in the stage they run.
The stand-in model below answers with the unit only when the skill’s
instructions reach it:

``` r

units_cl <- hr_mock_client(function(messages, params) {
  skilled <- messages[[1]]$role == "system" &&
    grepl("unit and its currency", messages[[1]]$content, fixed = TRUE)
  if (skilled) "Revenue was 45.2 million dollars." else "Revenue was 45.2."
})
answer <- function(skill = NULL) {
  hr_step("answer", function(item, ctx) ctx$call(item$question)$text,
          input = "state", output = "answer", skill = skill)
}
baseline <- hr_chain(answer = answer(), name = "no-skill")
skilled <- hr_chain(answer = answer(units), name = "units-skill")
skilled$params
#> $answer.skill
#> [1] "units@f1cdea95dadd"
identical(attr(baseline, "hr_config"), attr(skilled, "hr_config"))
#> [1] FALSE
```

The skill’s hash covers its header, instructions, references and every
byte of its scripts. The hash is part of the step’s fingerprint, so the
two chains have different configurations. The chain records the skill as
the setting `answer.skill`, and a benchmark shows it as
`param.answer.skill`. When the skill has a version, the step takes that
version.

To test whether a skill does what it says, compare the chain with and
without it on the same questions, using a scorer that checks the skill’s
rule. The scorer here checks that the answer names the currency:

``` r

questions <- c(q1 = "What was revenue in 2024?", q2 = "What was revenue in 2023?",
               q3 = "What was the operating cost?", q4 = "What was the order backlog?",
               q5 = "What was spent on research?", q6 = "What was the net income?")
units_ref <- hr_reference(lapply(as.list(questions), function(q) list(question = q)),
                          labels = rep("dollars", length(questions)),
                          cluster = names(questions), split = "test")
has_unit <- hr_scorer(function(item, output, label) {
  ok <- grepl(label, output, fixed = TRUE)
  list(correct = ok, outcome = if (ok) "unit" else "bare", failure_kind = NA)
}, name = "has_unit")
units_bench <- hr_benchmark(list(baseline, skilled), units_ref, runs = 5,
                            client = units_cl, scorer = has_unit)
units_report <- hr_report(units_bench, B = 200)
units_report$accuracy[, c("arm", "estimate", "lower", "upper")]
#>           arm estimate     lower     upper
#> 1    no-skill        0 0.0000000 0.3930378
#> 2 units-skill        1 0.6069622 1.0000000
units_report$contrasts[, c("arm1", "arm2", "estimate", "lower", "upper")]
#>       arm1        arm2 estimate lower      upper
#> 1 no-skill units-skill       -1    -1 0.04821512
```

A skill is not a setting of a step’s schema, so neither
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
nor a sweep by path can swap it. To sweep a skill, give
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
a function that builds the chain from a grid column:

``` r

arms <- hr_sweep(function(use_skill) {
  hr_chain(answer = answer(if (use_skill) units), name = "answer")
}, data.frame(use_skill = c(FALSE, TRUE)))
names(arms)
#> [1] "answer:use_skill=FALSE" "answer:use_skill=TRUE"
```

## A coding sub-agent

Steps do not have to read documents. A coding sub-agent drafts code with
a model, runs the tests on the draft, and asks the model to fix a draft
that failed.
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
(see
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md))
runs the tests: it runs one program you name and reads its result as
`"passed"` or `"failed"`.

The loop has two checks:

- A visible check runs after the draft. The revise step reads its result
  in `input$check`.
- A held check runs last. Only the scorer sees it, in
  `attr(output, "hr_held")`.

A revise step that saw the scoring check could fit the code to that
check, so a held step must come last.
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
refuses a step that is not held after one that is, with an error of
class `hr_held_not_last`. Here the visible and the held check run the
same tests; a held check can also run tests the loop never sees.

The example puts the tests and the drafts in a temporary folder. The
stand-in model drafts a `clamp()` with a bug, and sends the fixed
version when told the draft failed:

``` r

rscript <- file.path(R.home("bin"), "Rscript")
work <- file.path(tempdir(), "coding-loop")
dir.create(work, showWarnings = FALSE)
tests <- file.path(work, "test-clamp.R")
writeLines(c("stopifnot(clamp(5, 0, 3) == 3)", "stopifnot(clamp(2, 0, 3) == 2)"), tests)
coder <- hr_mock_client(function(messages, params) {
  text <- messages[[length(messages)]]$content
  if (grepl("failed its tests", text, fixed = TRUE)) {
    "clamp <- function(x, lo, hi) max(lo, min(x, hi))"
  } else {
    "clamp <- function(x, lo, hi) max(lo, max(x, hi))"
  }
})
```

The draft step writes the reply to a file, the command runs the tests on
that file, and the revise step sends the code and what the tests
printed:

``` r

draft <- hr_step("draft", function(item, ctx) {
  code <- tempfile("clamp-", tmpdir = work, fileext = ".R")
  writeLines(ctx$call(item$task)$text, code)
  list(code = code)
})
run_tests <- function(input, ctx) {
  c(rscript, "-e", sprintf("source('%s'); source('%s')",
                           gsub("\\\\", "/", input$code), gsub("\\\\", "/", tests)))
}
revise <- hr_step("revise", function(input, ctx) {
  if (identical(input$check$status, "passed")) return(input)
  fixed <- ctx$call(paste0("This code failed its tests:\n",
                           paste(readLines(input$code), collapse = "\n"),
                           "\nWhat the tests printed:\n", input$check$stderr))$text
  writeLines(fixed, input$code)
  input
})
coding <- hr_chain(draft = draft,
                   check = hr_step_command("check", run_tests),
                   revise = revise,
                   held = hr_step_command("held", run_tests, held = TRUE),
                   name = "coding")
```

The scorer reads the held check. The second arm is the same chain
without the visible check and the revise step, so it scores the first
draft. The loop passes on every run:

``` r

first <- hr_chain(coding, check = NULL, revise = NULL, name = "first-draft")
held_passes <- hr_scorer(function(item, output, label) {
  s <- attr(output, "hr_held")$held$status
  list(correct = identical(s, label), outcome = s, failure_kind = NA)
}, name = "held_passes")
tasks <- hr_reference(list(clamp = list(task = "Write clamp(x, lo, hi) in R.")),
                      labels = "passed", cluster = "clamp", split = "test")
cb <- hr_benchmark(list(coding, first), tasks, runs = 5, client = coder,
                   scorer = held_passes)
table(cb$arm, cb$outcome)
#>              
#>               failed passed
#>   coding           0      5
#>   first-draft      5      0
hr_signals(cb, "command.held")[1:2, c("arm", "run", "value")]
#>      arm run  value
#> 1 coding   1 passed
#> 2 coding   2 passed
unlink(work, recursive = TRUE)
```

For a testthat file, give the check `parse = "testthat"`. It reads the
last `[ FAIL n | WARN n | SKIP n | PASS n ]` line the run printed, and a
run with a failed test is `"failed"` whatever its exit code. Run the
file with a reporter that prints that line, such as the default,
`"progress"` or `"check"`. A run that prints no such line, as under
`"summary"`, reads as `"error"`. Pass `stop_on_failure = TRUE` to
[`testthat::test_file()`](https://testthat.r-lib.org/reference/test_file.html)
as well if you want the exit code to agree with the result.

A stand-in model’s handler must be stateless: its reply should depend
only on the messages and settings it gets, as `coder`’s does. A handler
that counts its calls, or remembers the last request, answers by the
order the requests come in. That order changes when runs go to parallel
workers, when a cache or a recording answers some requests, and when you
add arms. The same benchmark would then score differently from one run
to the next.

## Two goals, start to finish

### Run your own tests on the recipes

Here you sweep a recipe over a grid of its settings and run your own arm
beside it, on the same questions and under one spending limit (“A
governor for one run” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)).
Given a function,
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
builds one arm per row of the grid, and each arm records its settings as
`param.*` columns:

``` r

my_arm <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = 4),
                   read = gr_step("read", reader = "stuff"), name = "mine")
arms <- hr_sweep(function(top_k, max_tokens) {
  gr_arm("needle", list(top_k = top_k, max_tokens = max_tokens))
}, expand.grid(top_k = c(2, 4, 8), max_tokens = c(200, 500)))
bench <- hr_benchmark(c(arms, list(my_arm)), ref, runs = 5, client = cl,
                      scorer = gr_scorer_answer(),
                      governor = hr_governor(max_cost_usd = 5))
aggregate(correct ~ param.top_k + param.max_tokens, bench, mean)
#>   param.top_k param.max_tokens correct
#> 1           2              200       1
#> 2           4              200       1
#> 3           8              200       1
#> 4           2              500       1
#> 5           4              500       1
#> 6           8              500       1
aggregate(correct ~ arm, bench, mean)
#>                             arm correct
#> 1                          mine       1
#> 2 needle:top_k=2,max_tokens=200       1
#> 3 needle:top_k=2,max_tokens=500       1
#> 4 needle:top_k=4,max_tokens=200       1
#> 5 needle:top_k=4,max_tokens=500       1
#> 6 needle:top_k=8,max_tokens=200       1
#> 7 needle:top_k=8,max_tokens=500       1
hr_sweep_check(bench)
#>                             arm                       same_as runs requests
#> 1 needle:top_k=8,max_tokens=200 needle:top_k=4,max_tokens=200    5        5
#> 2 needle:top_k=4,max_tokens=500 needle:top_k=2,max_tokens=500    5        5
#> 3 needle:top_k=8,max_tokens=500 needle:top_k=2,max_tokens=500    5        5
#>        settings
#> 1 top_k: 4 vs 8
#> 2 top_k: 2 vs 4
#> 3 top_k: 2 vs 8
```

The first table covers only the swept arms. Your arm has no `param.*`
settings, so [`aggregate()`](https://rdrr.io/r/stats/aggregate.html)
leaves its rows out. The second table has one row per arm, yours
included, so it compares the grid with your arm.

The example document is short. In chunks of 200 tokens, a `top_k` of 4
keeps every chunk; in chunks of 500 tokens, a `top_k` of 2 does.
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
finds the arms that sent the same requests as another arm, and those
rows compare a configuration with itself.

### Chain steps into a sub-agent of your own

Here you compare a chain that has a judge step with the same chain
without it, and sweep the chain over `top_k`. A cache answers any
request sent twice. The judge step grades the answer against a rubric
with `ctx$judge()` and records the verdict with `ctx$note()`:

``` r

checked <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = 4),
                    read = gr_step("read", reader = "stuff"),
                    judge = hr_step("judge", function(a, ctx) {
                      j <- ctx$judge(a$answer, mode = "grade", reference = "45.2 million",
                                     rubric = "Does it give the figure?", orders = 1)
                      ctx$note("ok", j$verdicts$verdict[1])
                      a
                    }),
                    name = "checked")
bench <- hr_benchmark(c(list(checked, hr_chain(checked, judge = NULL, name = "nojudge")),
                        hr_sweep(checked, data.frame(retrieve.top_k = c(2, 8)))),
                      ref, runs = 5, client = hr_cache_client(cl, hr_cache(tempfile())),
                      scorer = gr_scorer_answer())
aggregate(correct ~ arm, bench, mean)
#>                        arm correct
#> 1                  checked       1
#> 2 checked:retrieve.top_k=2       1
#> 3 checked:retrieve.top_k=8       1
#> 4                  nojudge       1
table(hr_signals(bench, "ok")$arm)
#> 
#>                  checked checked:retrieve.top_k=2 checked:retrieve.top_k=8 
#>                        5                        5                        5
```

You build a coding sub-agent the same way, as in the section above: a
draft step, a visible check, a revise step, and the held check last.

## Next

- [`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md):
  comparing arms, sweeping a setting over its values, and reading the
  report.
- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  references, scorers, judges and signals.
- [`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md):
  the calls a step makes, and the trace that records them.
- [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md):
  the limits, the cache and the replay a chain runs under.
- [`?hr_step`](https://elkronos.github.io/harnessr/reference/hr_step.md)
  and
  [`?hr_chain`](https://elkronos.github.io/harnessr/reference/hr_chain.md):
  every argument, and what a chain records.
- [`?hr_register`](https://elkronos.github.io/harnessr/reference/hr_register.md),
  [`?hr_modules`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
  and
  [`?hr_check_module`](https://elkronos.github.io/harnessr/reference/hr_check_module.md):
  registering, listing and checking a module of any kind.
- [`?hr_settings`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
  and
  [`?hr_set`](https://elkronos.github.io/harnessr/reference/hr_set.md):
  listing and changing a chain’s settings by path.
- [`?hr_skill`](https://elkronos.github.io/harnessr/reference/hr_skill.md):
  what a skill folder holds and what is refused.
- [`?hr_step_command`](https://elkronos.github.io/harnessr/reference/hr_step_command.md):
  how a command step runs a program and reads its result, and what a
  held step does.
