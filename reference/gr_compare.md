# Run several recipes over one document and compare them

Each recipe is an independent pipeline, so a recipe's answer is
identical whether it is run alone or alongside others. Extraction is
shared through the ingest cache, and segmentation is shared between
recipes whose segment specs are identical, so comparing five readers
over one chunking costs one chunking, not five.

## Usage

``` r
gr_compare(
  source,
  question,
  recipes = c("fast", "needle", "thorough"),
  client = NULL,
  allow_duplicates = FALSE,
  on_error = c("continue", "stop"),
  correct = NULL,
  ...
)
```

## Arguments

- source:

  File path, web address, or raw text; see
  [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md).

- question:

  The question.

- recipes:

  A character vector of recipe names, or a list of `gr_recipe`s.

- client:

  A `gr_client`.

- allow_duplicates:

  Run duplicates anyway (useful at temperature \> 0 to measure
  variance).

- on_error:

  `"continue"` keeps going and records the failure; `"stop"` aborts the
  whole comparison.

- correct:

  How to tell whether an answer is right, for the `correct` and
  `usd_per_correct` columns. `NULL` (the default) adds neither. A
  character vector marks an answer right when its text contains any of
  the strings, ignoring case and runs of white space; an answer that
  found nothing, or a recipe that failed, is wrong, and one that found
  nothing because a limit stopped it is `NA`: the spending, token or
  call limit, the model allow-list or the output ceiling. A function is
  called with each recipe's
  [gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)
  and returns `TRUE`, `FALSE` or `NA` (not known); when it fails or
  returns anything else, a warning of class `gr_bad_correct` names the
  recipe and its `correct` is `NA`. An invalid `correct` argument is an
  error of the same class.

- ...:

  Overrides applied to every recipe.

## Value

A list with `answers` (named list of
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)),
`summary`, `trace` (shared across all recipes, so it records every
recipe's calls) and `document` (source and ingestion stats). `summary`
is a data frame with one row per recipe and these columns:

- `recipe`, `segmenter`, `chunks`, `reader`, `signature`, `settings`:

  Which pipeline the row is, and what was changed from the recipe's
  defaults.

- `partial`, `chunks_used`, `answer_chars`, `not_found`, `error`:

  What the answer is, and what went wrong, if anything.

- `calls`, `tokens_in`, `tokens_out`:

  The model and embeddings requests the recipe made, its segmentation's
  included, and the tokens of those that were billed: a request answered
  from a cache or a recording is counted in `calls` and costs nothing.

- `usd`:

  What those requests cost, at the prices registered with
  [`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md).
  `NA` when a model the recipe used has no registered price.

- `usd_estimated`:

  The share of `usd` spent on requests whose token counts were estimated
  locally because the provider reported none, from 0 to 1. `NA` when no
  request records how its counts were obtained, or when `usd` is 0 or
  unknown.

- `correct`, `usd_per_correct`:

  Only with `correct`: whether the answer was right, and `usd` divided
  by the number of right answers, which is `usd` for a right answer,
  `Inf` for a wrong one that cost something and `NA` for a wrong one
  that cost nothing or one whose correctness is not known.

- `premise`:

  Only when a recipe checks the question's premise: what the model said
  the document states instead, or `NA`; see `premise` in
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).

## Details

Recipes that resolve to identical ingestion, identical segmentation
*and* an identical read spec are collapsed with a warning rather than
billed twice. A shared reader signature alone is not enough: two
`retrieve` recipes with different `top_k` share a signature and are
genuinely different runs.

Each row of `summary` says what its recipe cost, priced from the
requests on the trace by the model each one used (see
[`gr_trace_cost()`](https://elkronos.github.io/harnessr/reference/gr_trace_cost.md)).
A recipe is charged what it would cost run alone: a segmentation it
shares with an earlier recipe is charged to both, as `max_calls` counts
it for both, so `sum(summary$usd)` can be more than the comparison
spent, which is `sum(gr_trace_cost(trace)$usd)`. Give `correct` and each
row also says whether the answer was right and what a right answer cost.

A comparison is one run for the spending and token limits:
`max_cost_usd` and `max_tokens_total` in
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
are checked against what every recipe and every segmentation has spent
and used so far, so a recipe that reaches either limit stops `partial`
and the ones after it are refused and recorded as failed. `max_calls` is
counted for each recipe on its own, its segmentation included, so a
recipe's answer does not depend on its position in the list. A
segmentation that a limit cut short is not shared with a later recipe.

## See also

[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
[`gr_recipes()`](https://elkronos.github.io/harnessr/reference/gr_recipes.md),
[`gr_recipe()`](https://elkronos.github.io/harnessr/reference/gr_recipe.md),
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")

# Three pipelines over one document. Extraction is shared, so this costs one
# extraction, not three; only the segmentation and the reader vary.
cmp <- gr_compare(gr_example(), "What was revenue?",
                  c("fast", "precise", "needle"), client = cl)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Segmenting with 'sentence' (cap 600 tokens, overlap 60).
#> Reading with 'skim' (all|N+1|none) over 2 chunk(s).
#> Segmenting with 'semantic' (cap 500 tokens, overlap 50).
#> Reading with 'retrieve' (topk|1|none) over 2 chunk(s).
cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "signature", "chunks_used")]
#>    recipe segmenter chunks   reader    signature chunks_used
#> 1    fast paragraph      1    stuff   all|1|none           1
#> 2 precise  sentence      2     skim all|N+1|none           2
#> 3  needle  semantic      2 retrieve  topk|1|none           2

# One trace covers all three, so this is the cost of the whole comparison.
gr_trace_summary(cmp$trace)
#>                          run_id calls cached steps tokens_in tokens_out errors
#> 1 run_20261106103537.693_67245a     5      0    16      2122         65      0
#>   elapsed_s embed_calls embed_tokens tokens_reasoning tokens_cached_in
#> 1      0.11           0            0                0                0
#>   usage_estimated
#> 1               1

# What each recipe cost, and what a right answer cost. The mock is free, so
# register a price for it under another name to see the columns filled.
gr_register_model("priced-mock", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)
cmp <- gr_compare(gr_example(), "What was revenue?", c("fast", "precise"),
                  client = cl, model = "priced-mock", correct = "45.2 million")
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Segmenting with 'sentence' (cap 600 tokens, overlap 60).
#> Reading with 'skim' (all|N+1|none) over 2 chunk(s).
cmp$summary[, c("recipe", "calls", "usd", "correct", "usd_per_correct")]
#>    recipe calls      usd correct usd_per_correct
#> 1    fast     1 0.001318    TRUE        0.001318
#> 2 precise     3 0.001998    TRUE        0.001998
```
