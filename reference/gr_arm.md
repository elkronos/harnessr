# A reading recipe as an arm of a benchmark

`gr_arm()` wraps one recipe as an
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
so recipes can be compared with
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
on a reference of questions about documents, such as one from
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md).
`gr_arms()` builds one arm per recipe.

## Usage

``` r
gr_arm(recipe, settings = list(), name = NULL)

gr_arms(recipes, settings = list())
```

## Arguments

- recipe:

  A recipe: a name from
  [`gr_recipes()`](https://elkronos.github.io/harnessr/reference/gr_recipes.md),
  `"auto"`, a reader name, a
  [`gr_recipe()`](https://elkronos.github.io/harnessr/reference/gr_recipe.md)
  or a named list of `ingest`, `segment` and `read`.

- settings:

  A named list of overrides applied to the recipe, as the `...` of
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  takes them (for example `model`, `top_k`, `max_tokens`). An unknown
  name is an error when the arm is built.

- name:

  The arm's name. By default the recipe's name.

- recipes:

  A character vector of recipe names, or a list of recipes. The names of
  a named list or vector are used as the arms' names.

## Value

`gr_arm()` returns an
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md).
`gr_arms()` returns a list of them, named by arm.

## Details

Each run reads the item's `document` and answers its `question`: with
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
when the document is a file path, a web address or text, or with
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
when it is already cut into chunks by
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md).
It returns the
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md),
which the benchmark's scorer then judges;
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
is the scorer made for it.

The run uses the benchmark's client and records every request into the
trace the benchmark made for that run (`ctx$trace`), so the run's
tokens, cost and refusals are counted and held to the benchmark's
limits, and the answer's `trace` is that run's trace. That trace also
gives every request of the run the run's draw index (see `draw_index` in
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)),
segmenter and reader requests included, so the runs of one arm on one
item are separate draws under a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
or a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
rather than one stored reply repeated, which
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
would refuse.

A reader checks before it starts whether the run's call and spending
limits leave room for it. When they do not, the run returns a
`"NOT_IN_DOCUMENT"` answer marked `partial`, with `call_cap_reached` or
`cost_cap_reached` in its notes as
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
records them, and
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
scores it as a `"budget_stop"`.

A recipe given as `"auto"` chooses `"fast"` or `"thorough"` per
document, as
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
does; it needs a document that is not yet chunked.

The arm's `params` are the recipe's name and the settings, and its
version is the version of harnessr, since readers and prompts change
between versions.

## See also

[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
for a single descriptive comparison

Other harness:
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?",
                ceo = "Who is the chief executive?"),
  documents = gr_example(),
  answers = list("45.2 million", NA),
  unanswerable = "ceo", split = "test")
arms <- gr_arms(c("fast", "thorough"))
bench <- hr_benchmark(arms, ref, runs = 5, client = cl, scorer = gr_scorer_answer())
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
bench
#> <hr_bench> 2 arm(s) x 2 item(s) in 1 cluster(s) x 5 run(s); split test; scorer answer_contains
#>  arm      accuracy runs wrong failed budget_stop usd   
#>  fast     0.500    10   5     0      0           0.0000
#>  thorough 0.500    10   5     0      0           0.0000
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
```
