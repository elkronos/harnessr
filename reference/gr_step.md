# Built-in steps for composing a run

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

A function of `(input, ctx)` with class
`c("gr_step", "hr_step", "function")`.

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
[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md).
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
runs steps in order as one arm; by hand, the same is a fold:
`Reduce(function(x, step) step(x, ctx), steps, item)`.

Each step is an
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
with class `gr_step` added and the attributes `kind` and `spec`, which
[`print()`](https://rdrr.io/r/base/print.html) shows. Its settings are
checked against the stage's schema:
[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)'s,
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)'s
or
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)'s
for `gr_step()`, and for `gr_step_retrieve()` the ranking settings
`top_k`, `min_score`, `mmr`, `fusion`, `rrf_k`, `lexical_blend`,
`bm25_k1` and `bm25_b`. Any other setting passed to `gr_step_retrieve()`
reaches
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
as it is. A step declares what it takes and returns, which
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
checks: ingest takes a document and returns a doc, segment takes a doc
and returns chunks, retrieve takes and returns chunks, and read takes
chunks and returns the answer.

These steps take no skill
([`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md)):
their requests are built by the stage, not sent through `ctx$call()`, so
a skill would not reach them. Passing `skill` is an error of class
`hr_bad_skill`.

## See also

[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
which runs steps as one arm;
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
for a step of your own;
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
arm <- hr_chain(segment = steps[[1]], retrieve = steps[[2]], read = steps[[3]],
                name = "segment-rank-read")
steps[[2]]
#> <gr_step> retrieve (retrieve): top_k=2
```
