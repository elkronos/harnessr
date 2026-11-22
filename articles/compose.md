# Composing steps into chains

A recipe such as `needle` is a fixed sequence of stages: segment the
document, rank the chunks, read the best. When you want a sequence of
your own, with a check after the answer or a step that rewrites the
question, you build it from steps and run the steps in order as one arm.
The arm is an ordinary
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
so
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
compares it with recipes and with other chains on the same labelled
questions, as
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
does for recipes.

Everything here runs offline on a stand-in model.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")
cl <- gr_mock_client(function(messages, params) {
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
builds the document stages, `"ingest"`, `"segment"` and `"read"`, and
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
builds a step that ranks the chunks and keeps the best without asking
for an answer. Their settings are the ones the stage’s spec takes, and
they are checked when the step is built:

``` r

gr_step_retrieve(top_k = 4)
#> <gr_step> retrieve (retrieve): top_k=4
try(gr_step("read", reader = "no_such_reader"))
#> Error in registry_get("readers", spec$reader, "readers", state = gr_state) : 
#>   Unknown reader 'no_such_reader'. Registered: ensemble, extract, hierarchical, iterative, map_reduce, preview, refine, rerank, retrieve, screen, skim, stuff.
```

[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
builds a step of your own. Inside a chain, `ctx` is the context
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
gives an arm (its client, trace, `judge` and `note` shortcuts, and
`params`), with the step’s name in `ctx$step` and its settings in
`ctx$step_params`. This one grades the answer with a model and records
the verdict as a signal of the run:

``` r

judge <- hr_step("judge", function(a, ctx) {
  j <- ctx$judge(a$answer, mode = "grade", reference = "45.2 million",
                 rubric = "Does it give the figure?", orders = 1)
  ctx$note("judged", j$verdicts$verdict[1])
  a
}, input = "answer", output = "answer")
```

`input` and `output` declare what a step takes and returns:
`"document"`, `"doc"`, `"chunks"`, `"answer"` or `"state"`. They are
optional, and
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
uses them to check the order of the steps.

## Chains

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
runs its steps in order: the first gets the item, each later step gets
what the step before returned, and the chain returns what the last step
returns. An argument’s name is the step’s name in the chain.

``` r

checked <- hr_chain(segment = gr_step("segment"),
                    retrieve = gr_step_retrieve(top_k = 4),
                    read = gr_step("read", reader = "stuff"),
                    judge = judge, name = "checked")
checked
#> <hr_arm checked> version 0.0.1
#>   params: retrieve.top_k = 4, read.reader = stuff 
#>   hash: 4cb127da751d
```

The arm records each step’s settings as `"step.setting"`, so a benchmark
gets a `param.retrieve.top_k` column for it. A chain is derived from
another by naming steps: `NULL` drops one, a step under an existing name
replaces it where it stands, and a step under a new name is added at the
end.

``` r

nojudge <- hr_chain(checked, judge = NULL, name = "nojudge")
wider <- hr_chain(checked, retrieve = gr_step_retrieve(top_k = 8), name = "wider")
names(attr(wider, "hr_steps"))
#> [1] "segment"  "retrieve" "read"     "judge"
```

The three run side by side like any arms. Each run sends its requests at
its own draw, so a cache does not hand one run’s reply to the next:

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

A step that takes chunks when no step before it returns chunks warns
with class `hr_chain_gap`: a read step would cut the document at the
default settings without saying so. A segment step first in a chain does
not warn, though it reads the document at the default ingest settings;
put an ingest step before it to choose them. After a step that returns
the answer, only steps that take `"answer"` or `"state"`, or declare
nothing, can follow.

``` r

tryCatch(hr_chain(read = gr_step("read", reader = "stuff"), name = "gap"),
         hr_chain_gap = function(w) conditionMessage(w))
#> [1] "Chain 'gap': step 'read' takes chunks, but no step before it returns them, so it will cut the document into chunks at the default settings. Add a segment step before it to choose them."
try(hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
             retrieve = gr_step_retrieve(), name = "late"))
#> Error in chain_check_order(steps, what) : 
#>   Chain 'late': step 'retrieve' takes "chunks", but it comes after step 'read', which returns the answer. After an answer only steps that take "answer" or "state" can follow.
```

Step names cannot contain a dot, since settings are named
`"step.setting"`, and cannot repeat.

### When two chains are the same

A chain’s configuration is a hash of its steps’ code, the values that
code reads, and their resolved settings. Two chains with the same
configuration send the same requests, and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
warns (`hr_same_config`) when asked to compare them. A setting given at
its default gives the same configuration as the setting left out:

``` r

a <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(), name = "a")
b <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = 6),
              name = "b")
identical(attr(a, "hr_config"), attr(b, "hr_config"))
#> [1] TRUE
```

## Next

- [`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md):
  comparing arms, sweeping a setting over its values, and reading the
  report.
- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  references, scorers, judges and signals.
- [`?hr_step`](https://elkronos.github.io/harnessr/reference/hr_step.md)
  and
  [`?hr_chain`](https://elkronos.github.io/harnessr/reference/hr_chain.md):
  every argument, and what a chain records.
