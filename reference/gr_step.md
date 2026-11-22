# Built-in steps for composing a run by hand

`gr_step()` builds one stage of a run as a step: a function of
`(input, ctx)` that ingests, segments or reads. `gr_step_retrieve()`
builds a step that ranks the chunks against the question and keeps the
best, as the `retrieve` reader does, without the answer request. The
settings are checked when the step is built, by the spec constructors
([`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)),
so a misspelt or out-of-range setting fails there and not on the
hundredth run of a benchmark.

## Usage

``` r
gr_step(kind = c("ingest", "segment", "read"), ..., name = NULL)

gr_step_retrieve(top_k = 6L, ..., name = NULL)
```

## Arguments

- kind:

  `"ingest"`, `"segment"` or `"read"`.

- ...:

  Settings for the stage's spec constructor:
  [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
  for `"ingest"`,
  [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  for `"segment"`,
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  for `"read"` (`reader = "stuff"`, say). For `gr_step_retrieve()`, the
  other ranking settings of
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md):
  `min_score`, `mmr`, `fusion`, `rrf_k`, `lexical_blend`, `bm25_k1`,
  `bm25_b`.

- name:

  The step's name; defaults to `kind`, or `"retrieve"`.

- top_k:

  How many chunks to keep, as in
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).

## Value

A function of `(input, ctx)` with class `gr_step`.

## Details

A step uses `ctx$client` for its requests and records them on
`ctx$trace`, which is what
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
gives an arm's run function: inside an
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
every request a step makes is counted, held to the benchmark's limits
and sent at the run's draw. Outside a benchmark, pass a list such as
`list(client = cl, trace = gr_trace())`.

Steps pass a list along. The first step takes the item
([`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
items are lists with `question` and `document`); `"ingest"` adds `doc`,
`"segment"` adds `chunks` (ingesting `document` first when there is no
`doc`), and `gr_step_retrieve()` replaces `chunks` with the chunks it
kept, best first, with their scores in a `score` column. `"read"` reads
`chunks` (segmenting first when there are none) and returns the
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md),
so it is the last step. Chaining them is a fold:
`Reduce(function(x, step) step(x, ctx), steps, item)`.

Each step is a function with class `gr_step` and attributes `kind`,
`name` and `spec`, which [`print()`](https://rdrr.io/r/base/print.html)
shows. A later `hr_chain()` reads the same attributes, so the steps
built now are the ones it will take.

## See also

[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
which run steps inside an arm;
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
for a whole recipe as one arm.

Other reading functions:
[`gr_answer`](https://elkronos.github.io/harnessr/reference/gr_answer.md),
[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md),
[`gr_methods_text()`](https://elkronos.github.io/harnessr/reference/gr_methods_text.md),
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
[`gr_reader_signature()`](https://elkronos.github.io/harnessr/reference/gr_reader_signature.md),
[`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md),
[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md),
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md),
[`new_answer()`](https://elkronos.github.io/harnessr/reference/new_answer.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ctx <- list(client = cl, trace = gr_trace())
steps <- list(gr_step("segment", method = "paragraph", max_tokens = 120),
              gr_step_retrieve(top_k = 2),
              gr_step("read", reader = "stuff"))
item <- list(question = "What was revenue?", document = gr_example())
ans <- Reduce(function(x, step) step(x, ctx), steps, item)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 120 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 2 chunk(s).
ans$chunks_used
#> [1] 2 6

# The same steps as an arm a benchmark can run.
arm <- hr_arm("segment-rank-read",
              function(item, ctx) Reduce(function(x, step) step(x, ctx), steps, item))
steps[[2]]
#> <gr_step> retrieve (retrieve): top_k=2
```
