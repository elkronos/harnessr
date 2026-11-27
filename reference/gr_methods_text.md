# A methods paragraph from a run's record

Writes what a run's record says about how it was made as one plain
paragraph, for the methods section of a paper or a report: the harnessr
version, the models the requests asked for and the models the provider
said answered, how many requests were made and how many a cache
answered, the tokens sent and received (a request a cache or a recording
answered sent nothing, and its recorded tokens are given apart), the
settings changed from their defaults, and a hash of each distinct system
prompt, by stage. For a benchmark it adds the arms, items, runs per item
and the scorer.

## Usage

``` r
gr_methods_text(x)
```

## Arguments

- x:

  A
  [gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)
  (its own run's steps; see
  [gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)),
  a `gr_trace` (see
  [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)),
  or a benchmark from
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md).

## Value

A character string, one paragraph, of class `gr_methods_text`;
[`print()`](https://rdrr.io/r/base/print.html) wraps it.

## Details

Everything in it is read from the record: the trace's request steps and
its pre-flight notes, or the benchmark's columns and attributes. It
makes no claim the record does not hold. It does not say the answers are
right, and where the record lacks something (the provider did not report
the model that answered, say) the paragraph says that it is not
recorded. Prompt hashes are the first 12 hex digits of the SHA-256 hash
harnessr keys its records with, taken of each system message, so two
runs that sent the same instructions show the same hash; the full
prompts stay in the trace.

## See also

[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
and
[`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md)
for the full record,
[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
for a readable account of one answer

Other reading functions:
[`gr_answer`](https://elkronos.github.io/harnessr/reference/gr_answer.md),
[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md),
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
[`gr_reader_signature()`](https://elkronos.github.io/harnessr/reference/gr_reader_signature.md),
[`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md),
[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md),
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md),
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md),
[`new_answer()`](https://elkronos.github.io/harnessr/reference/new_answer.md)

## Examples

``` r
ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 150))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 150 tokens, overlap 0).
cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ans <- gr_read(ch, "What was revenue?", cl, gr_read_spec("retrieve", top_k = 3))
#> Reading with 'retrieve' (topk|1|none) over 5 chunk(s).
gr_methods_text(ans)
#> The run was made with harnessr 0.7.0. It read once with the 'retrieve'
#> reader with these settings changed from their defaults: top_k = 3. It
#> made 1 model request(s), which asked for 'mock-model'. The provider did
#> not report which model answered them. They sent 478 prompt token(s) and
#> received 13 reply token(s). Their system prompts, by stage, have the
#> hashes retrieve.answer cdd84211f69d. This paragraph restates the run's
#> record and makes no claim beyond it.
```
