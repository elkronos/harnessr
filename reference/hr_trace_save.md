# Save a trace to a file

Writes the trace as JSON, in the form
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
produces. The file is everything
[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
needs, so this is how a run leaves the session it happened in.

## Usage

``` r
hr_trace_save(trace, path)
```

## Arguments

- trace:

  A `gr_trace`.

- path:

  Destination file.

## Value

`path`, invisibly.

## Details

With `hr_options(mask_secrets = TRUE)` key-shaped strings in the file
(an API key echoed in an error, a token in a prompt) are replaced with
`<masked>`, and a top-level field `masked` says how many. The trace in
your session is left as it was, and each step's `replay_key` was taken
from the prompt as it was sent, so a replay of the file still finds its
replies.
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
lists the shapes masked.

## See also

[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md),
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md),
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)

## Examples

``` r
cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).

f <- tempfile(fileext = ".json")
hr_trace_save(ans$trace, f)
file.exists(f)
#> [1] TRUE
```
