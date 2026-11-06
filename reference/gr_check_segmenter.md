# Check a segmenter against the segmenter contract

Cuts the bundled example document
([`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md))
with one registered segmenter and reports which rules of the segmenter
contract it breaks. Nothing is refused: a segmenter that fails a rule
stays registered and runs as before. Use it on a segmenter of your own
after
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md).

## Usage

``` r
gr_check_segmenter(segmenter, client = NULL)
```

## Arguments

- segmenter:

  A registered segmenter's name; see
  [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md).

- client:

  A `gr_client` to read with. `NULL` (the default) uses a
  [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
  whose reply to a request with a JSON schema is an object of that
  schema's shape, and a fixed sentence otherwise.

## Value

An `hr_conformance` data frame; see
[`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md).

## Details

The spec is
`gr_segment_spec(method = segmenter, max_tokens = 150, context_source = "llm")`,
so `contextual` writes its context lines with the model. A client you
pass is used whatever the segmenter declares, so `calls_declared` sees
every call it makes with one. With none, a segmenter that needs a
client, or declares calls, is given the offline one.

## Rules

- `is_function`, `runs`:

  The segmenter's `fn` is a function, and
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
  with it finishes without an error.

- `chunks_class`:

  It returns a
  [gr_chunks](https://elkronos.github.io/harnessr/reference/gr_chunks.md)
  whose `chunks` is a data frame.

- `chunk_columns`:

  `chunks` has the columns
  [gr_chunks](https://elkronos.github.io/harnessr/reference/gr_chunks.md)
  documents: `chunk_id`, `text`, `tokens`, `chars`, `page`, `section`
  and `block_id`.

- `chunk_text`:

  Every chunk has text that is not blank.

- `chunk_ids`:

  Chunk ids are unique and not `NA`.

- `within_cap`:

  No chunk the segmenter returned was over `max_tokens`.
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
  splits an oversized chunk and records it in `extra$cap_enforced`, and
  the segmenter is reported for each one it had to split.

- `calls_declared`:

  The label of every model call in the trace is covered by a stem the
  segmenter declared in `calls`, by the rule an `effort` map is checked
  with.

## See also

[`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md),
[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)

Other segmentation functions:
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md),
[`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md),
[`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
[`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)

## Examples

``` r
gr_check_segmenter("paragraph")
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 150 tokens, overlap 0).
#> <hr_conformance> segmenter 'paragraph', contract 0.1
#>   passes all 8 rules
#>   ok    is_function
#>   ok    runs
#>   ok    chunks_class
#>   ok    chunk_columns
#>   ok    chunk_text
#>   ok    chunk_ids
#>   ok    within_cap
#>   ok    calls_declared: no model calls
```
