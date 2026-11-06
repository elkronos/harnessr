# Call a model

Call a model

## Usage

``` r
gr_call(
  client,
  messages,
  model = NULL,
  max_output = NULL,
  temperature = NULL,
  schema = NULL,
  schema_name = "result",
  trace = NULL,
  label = "call",
  ...,
  effort = NULL,
  draw_index = 0L
)
```

## Arguments

- client:

  A `gr_client`.

- messages:

  A list of `list(role=, content=)` items, or a single string, which is
  wrapped as one user message. `role` may be `"system"`, `"developer"`,
  `"user"` or `"assistant"`.

- model:

  Overrides the client default.

- max_output:

  Maximum completion tokens. Clamped to the model's limit and to what
  the context window actually leaves after the prompt. A value that is
  not a single number (`NA`, text) warns and uses the model's limit, as
  `NULL` does. For a reasoning model (see
  [`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md))
  the cap an API request carries also bounds the model's hidden
  reasoning, so a small cap is sent as at least 2048 tokens (within the
  model's limit and the context window); otherwise the reasoning can use
  all of it and the reply come back empty. The reply is then no longer
  held to the smaller cap by the API, and the extra tokens are billed if
  the model uses them.

- temperature:

  Sampling temperature; dropped automatically for reasoning models that
  reject it.

- schema:

  Optional JSON Schema (as a list) requesting structured output.

- schema_name:

  Name for the schema.

- trace:

  Optional `gr_trace` to record this call into.

- label:

  Short label for the trace entry.

- ...:

  Extra top-level body fields.

- effort:

  Reasoning effort for this call, or `NULL` (the default) to send none.
  One string, or a character vector named by label prefix, resolved
  against `label` as
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  describes. Sent only when `model` is a reasoning model (see
  [`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md)),
  as `reasoning = {effort}` on the Responses API and `reasoning_effort`
  on Chat Completions; a
  [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
  or
  [`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
  handler finds it in `params$effort`. Must be named in full, since it
  follows `...`.

- draw_index:

  Which draw of a sampled request this is: 0 (the default) for an
  ordinary call, or 1, 2, ... for repeated draws of the same request.
  Above 0 it is part of the
  [`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
  key, so N identical calls with draw indexes 1 to N are N cached
  replies rather than one reply N times, and a
  [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  answers draw k with the k-th recorded reply to the request. A
  [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
  or
  [`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
  handler finds it in `params$draw_index`, and the trace records it in
  the step's `params`; at 0 neither carries it, so an unsampled call is
  unchanged. Must be named in full, since it follows `...`.

## Value

A
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md).
**Never** `NULL`; `$text` is always a single string, `""` on failure. A
successful HTTP call that returned no text (a refusal, a content filter)
is reported as `ok = FALSE`, so an empty completion is never passed
downstream as evidence. `$cached` is `TRUE` when the response came from
a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
or a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
instead of the network. A reply cut off at the output cap keeps
`ok = TRUE`, since its text is what the model wrote, but always carries
`finish_reason = "length"`, whatever the provider called it
(`"max_tokens"`, `"MAX_TOKENS"`, a Responses API status of
`"incomplete"`); check for it wherever a complete reply matters. Such a
reply is not written to a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md).
`$served_model`, `$response_id` and `$fingerprint` are what the provider
said about its reply (`NA` where it said nothing; `$model` stays the
model asked for), and `$attempts` is how many requests were sent for it,
retries included, 0 for a reply from a cache or a recording. A request
that would pass one of the run's limits (see
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md))
is not sent: it comes back with `ok = FALSE`, `$refused = TRUE`, an
`$error` naming the limit and the condition in `$refusal`, after a
condition of class `hr_budget_refused` is signalled. It is not recorded
as a step of the trace.

## See also

[`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md),
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md),
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md),
[`gr_budget()`](https://elkronos.github.io/harnessr/reference/gr_budget.md),
[`gr_cache_client()`](https://elkronos.github.io/harnessr/reference/gr_cache_client.md),
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)

## Examples

``` r
cl <- gr_mock_client(function(messages, params) "The answer is 42.")
res <- gr_call(cl, "What is the answer?")
c(ok = res$ok, text = res$text)
#>                  ok                text 
#>              "TRUE" "The answer is 42." 

# A failed call still returns a usable object.
bad <- gr_call(gr_mock_client(function(m, p) stop("network down")), "hi")
c(ok = bad$ok, text = sprintf("<%s>", bad$text), error = bad$error)
#>             ok           text          error 
#>        "FALSE"           "<>" "network down" 

# A reasoning effort reaches a reasoning model, and the handler sees it.
seen <- gr_mock_client(function(m, p) {
  paste("effort:", if (is.null(p$effort)) "none" else p$effort)
})
gr_call(seen, "hi", model = "gpt-5.6-luna", effort = "low")$text
#> [1] "effort: low"
gr_call(seen, "hi", model = "gpt-4o", effort = "low")$text   # not a reasoning model
#> [1] "effort: none"

# Draws of one request, each cached under its own key.
n <- 0
sampler <- gr_mock_client(function(m, p) { n <<- n + 1; paste("draw", n) })
sampler <- gr_cache_client(sampler, gr_cache(file.path(tempdir(), "harnessr-draws")))
vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")  # cached
#> [1] "draw 1" "draw 2" "draw 3"
```
