# The result of one model call

Returned by
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md).
Designed so a caller can never be handed `NULL` or `character(0)` where
a string is expected.
[`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md)
shows each field on a worked call.

## Fields

- `ok`:

  Logical(1). `FALSE` for transport failures, HTTP errors, and
  **successful calls that returned no text** (a refusal or content
  filter).

- `text`:

  Character(1), always. `""` when `ok` is `FALSE`. Never `NULL`, never
  `character(0)`, and newlines are preserved.

- `error`:

  Character or `NULL`. What went wrong, including the HTTP body for
  API-side errors.

- `usage`:

  List with `input` and `output` token counts and their `provenance`:
  `"reported"` by the provider, `"counted"` here with the `"tiktoken"`
  tokenizer or as a zero for a request that failed or was not sent, or
  `"estimated"` with another tokenizer. `reasoning` and `cached_input`
  are added when the provider reports them, as parts of `output` and
  `input`.

- `status`, `finish_reason`, `retryable`, `model`, `raw`:

  HTTP status, the API's stop reason (`"length"` for a reply cut off at
  the output cap, whatever the provider called it, and `NA` when the
  client reports none), whether a retry could help, the model id the
  call asked for, and the parsed response body.

- `cached`:

  `TRUE` when the reply came from an
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
  or an
  [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
  rather than the network.

- `served_model`, `response_id`, `fingerprint`:

  What the provider said about its reply: the model that answered, its
  response id and its system fingerprint. `NA` where it said nothing.

- `attempts`:

  Requests sent for this reply, retries included: 0 for a reply from a
  cache or a recording, `NA` when the transport does not say.

A request the run's limits did not send (see
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md))
also carries `refused = TRUE` and the condition in `refusal`.

## Methods

[`print()`](https://rdrr.io/r/base/print.html) shows `ok`, the model,
the token usage and either the text or the error.

## See also

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
which returns one,
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md),
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md),
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md),
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)

## Examples

``` r
res <- hr_call(hr_mock_client(function(m, p) "hello"), "hi")
c(ok = res$ok, text = res$text)
#>      ok    text 
#>  "TRUE" "hello" 
```
