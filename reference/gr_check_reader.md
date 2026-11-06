# Check a reader against the reader contract

Reads the bundled example document
([`gr_example()`](https://elkronos.github.io/readgpt/reference/gr_example.md))
with one registered reader, through an offline client, and reports which
rules of the reader contract it breaks. Nothing is refused: a reader
that fails a rule stays registered and runs as before. Use it on a
reader of your own after
[`gr_register_reader()`](https://elkronos.github.io/readgpt/reference/gr_register_reader.md).

## Usage

``` r
gr_check_reader(reader, client = NULL)
```

## Arguments

- reader:

  A registered reader's name; see
  [`gr_readers()`](https://elkronos.github.io/readgpt/reference/gr_readers.md).

- client:

  A `gr_client` to read with. `NULL` (the default) uses a
  [`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
  whose reply to a request with a JSON schema is an object of that
  schema's shape, and a fixed sentence otherwise.

## Value

An `hr_conformance` data frame; see
[`hr_check_module()`](https://elkronos.github.io/readgpt/reference/hr_check_module.md).

## Details

The document is cut with `list(method = "paragraph", max_tokens = 150)`
and read on a fresh
[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md).
Readers that need more than a question are given what they need:
`extract` one field, `screen` one inclusion criterion, and `ensemble`
the members `"stuff"` and `"retrieve"`.

## Rules

- `is_function`, `runs`:

  The reader's `fn` is a function, and
  [`gr_read()`](https://elkronos.github.io/readgpt/reference/gr_read.md)
  with it finishes without an error.

- `answer_class`:

  It returns a
  [gr_answer](https://elkronos.github.io/readgpt/reference/gr_answer.md).

- `answer_fields`:

  The answer has every field
  [gr_answer](https://elkronos.github.io/readgpt/reference/gr_answer.md)
  documents for
  [`gr_read()`](https://elkronos.github.io/readgpt/reference/gr_read.md):
  `answer`, `reader`, `question`, `chunks_used`, `partial`, `notes`,
  `trace`, `warnings` and `signature`, with `partial` one `TRUE` or
  `FALSE`.

- `answer_text`:

  `answer` is a single string, not `NA`.

- `evidence`:

  `evidence` is `NULL`, or a data frame with a `chunk_id` column whose
  ids are all chunks of the input. `NA` is allowed, for a span placed in
  no chunk.

- `chunks_used`:

  Every id in `chunks_used` is a chunk of the input.

- `calls_declared`:

  The label of every model call in the trace is covered by a stem the
  reader declared in `calls`, by the rule an `effort` map is checked
  with (a stem, a part of one up to a dot, or a label under one). For
  `ensemble`, its members' stems count too.

- `calls_within_cost`:

  The requests the run made, embeddings included, are no more than the
  worst case its `cost` function gave for this input, as the pre-flight
  check recorded it. `NA` for a reader registered without `cost`.

## See also

[`hr_check_module()`](https://elkronos.github.io/readgpt/reference/hr_check_module.md),
[`gr_check_segmenter()`](https://elkronos.github.io/readgpt/reference/gr_check_segmenter.md),
[`gr_register_reader()`](https://elkronos.github.io/readgpt/reference/gr_register_reader.md)

Other reading functions:
[`gr_answer`](https://elkronos.github.io/readgpt/reference/gr_answer.md),
[`gr_read()`](https://elkronos.github.io/readgpt/reference/gr_read.md),
[`gr_read_spec()`](https://elkronos.github.io/readgpt/reference/gr_read_spec.md),
[`gr_reader_signature()`](https://elkronos.github.io/readgpt/reference/gr_reader_signature.md),
[`gr_readers()`](https://elkronos.github.io/readgpt/reference/gr_readers.md),
[`gr_register_reader()`](https://elkronos.github.io/readgpt/reference/gr_register_reader.md),
[`is_not_found()`](https://elkronos.github.io/readgpt/reference/is_not_found.md),
[`new_answer()`](https://elkronos.github.io/readgpt/reference/new_answer.md)

## Examples

``` r
gr_check_reader("stuff")
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 150 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 5 chunk(s).
#> <hr_conformance> reader 'stuff', contract 0.1
#>   passes all 9 rules
#>   ok    is_function
#>   ok    runs
#>   ok    answer_class
#>   ok    answer_fields
#>   ok    answer_text
#>   ok    evidence
#>   ok    chunks_used
#>   ok    calls_declared: 1 call(s), all under declared stems
#>   ok    calls_within_cost: 1 request(s) made, at most 1 expected

# A reader whose calls carry a label it did not declare.
gr_register_reader("loose", signature = "one|1|none", calls = "loose.answer",
  fn = function(chunks, question, client, spec, trace) {
    res <- gr_call(client, list(list(role = "user", content = question)),
                   model = spec$model, trace = trace, label = "other.answer")
    new_answer(res$text, "loose", question, integer(0), trace)
  })
gr_check_reader("loose")
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 150 tokens, overlap 0).
#> Reading with 'loose' (one|1|none) over 5 chunk(s).
#> <hr_conformance> reader 'loose', contract 0.1
#>   fails 1 of 9 rules
#>   FAIL  calls_declared: label(s) 'other.answer' not under the declared stems loose.answer
#>   skip  calls_within_cost: not checked: no cost function declared
#>   ok    is_function
#>   ok    runs
#>   ok    answer_class
#>   ok    answer_fields
#>   ok    answer_text
#>   ok    evidence: no evidence
#>   ok    chunks_used
```
