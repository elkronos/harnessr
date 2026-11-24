# Build one arm per row of a grid of settings

`hr_sweep()` turns a grid of settings into arms for
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
one per row, each named after its settings and recording them, so the
benchmark gets a `param.<name>` column per setting and a sweep is
summarised with [`aggregate()`](https://rdrr.io/r/stats/aggregate.html)
or
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
like any other comparison.

## Usage

``` r
hr_sweep(base, grid, name = NULL)
```

## Arguments

- base:

  A function of the grid's columns that returns an
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
  an arm made by
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
  or a chain made by
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md).

- grid:

  A data frame with one row per arm and one column per setting, or a
  named list of values, which is crossed with
  [`expand.grid()`](https://rdrr.io/r/base/expand.grid.html). A setting
  whose values are not single values (an `effort` map, a vector of
  cleaners) goes in a list column, for instance with
  [`I()`](https://rdrr.io/r/base/AsIs.html).

- name:

  `NULL` to name each arm after the base arm's name and its settings, as
  `"needle:top_k=2,max_tokens=200"`; one string to use in place of the
  base arm's name; or one string per row.

## Value

A list of
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
objects named by arm, one per distinct row, each with its row's settings
recorded.

## Details

`base` is either a function or an arm:

- A function:

  Called once per row with the row's values as named arguments, and must
  return an
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md).
  A column it has no argument for (and no `...` to take) is an error.

- An arm made by
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md):

  Each row's values replace the arm's settings of the same name, and the
  arm is built again with
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md).
  A column may be any setting
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  takes as an override (see
  [`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)),
  or `recipe`. A name that is none of these is an error that lists the
  names that are.

- A chain made by
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md):

  Each column is a setting's path, `"step.setting"`, as
  [`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
  lists them, and the chain is built again with the row's values by
  [`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md):
  `hr_sweep(chain, data.frame(retrieve.top_k = c(2, 8)))`. A path that
  is not a setting of a step's schema is an error that lists the paths
  that are.

An arm made by
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
alone records no settings, so it cannot be swept by name; give a
function that builds it instead.

Rows that build the same configuration are collapsed: the first is kept
and the others are dropped with a message of class `hr_sweep_collapsed`
naming them. Two arms from
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
have the same configuration when their recipes resolve to the same
settings, so a row that sets a setting to the recipe's own value is the
base arm again. Any other two arms have the same configuration when
everything but their names is the same, including the values their code
reads and the values read by any helper function it calls by name: a
function that ignores one of its arguments builds the same arm for every
value of it. A value held in an environment rather than read by name is
not compared, and neither is a helper reached through a list or another
object (`h$ask()`), whose code is compared but not the values it reads.
Two such arms can look like one configuration here and still send
different requests, and a sweep would keep only one of them: call such
helpers by name, or check with
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md),
which compares what was sent.

Sweeping one setting at a time on the dev split, then comparing the arm
chosen with the default on test, is the order
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
follows.
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
then says which settings changed nothing that was sent.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md),
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md),
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)

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
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
# Sweep a recipe's settings by name.
arms <- hr_sweep(gr_arm("needle"), list(top_k = c(2, 4, 8)))
names(arms)
#> [1] "needle:top_k=2" "needle:top_k=4" "needle:top_k=8"

# The same with a function, crossing two settings.
arms <- hr_sweep(function(top_k, max_tokens) {
  gr_arm("needle", list(top_k = top_k, max_tokens = max_tokens))
}, expand.grid(top_k = c(2, 8), max_tokens = c(200, 500)))
names(arms)
#> [1] "needle:top_k=2,max_tokens=200" "needle:top_k=8,max_tokens=200"
#> [3] "needle:top_k=2,max_tokens=500" "needle:top_k=8,max_tokens=500"

cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?"),
  documents = gr_example(), answers = list("45.2 million"), split = "test")
old <- gr_options(verbose = FALSE, embedder = "lexical")
bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
                      scorer = gr_scorer_answer())
aggregate(correct ~ param.top_k + param.max_tokens, bench, mean)
#>   param.top_k param.max_tokens correct
#> 1           2              200       1
#> 2           8              200       1
#> 3           2              500       1
#> 4           8              500       1
gr_options(old)
```
