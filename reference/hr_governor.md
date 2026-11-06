# Limits on what a run may send

A governor holds the limits that every request a run makes is checked
against before it is sent: how many calls the run may make, what it may
spend, the largest output cap one request may carry, and which models it
may call.
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md),
and every reader, judge, adjudication, segmenter and embeddings request
in the package, goes through the same check, so a limit holds whether or
not the code that makes the call looks at it.

## Usage

``` r
hr_governor(
  max_calls = gr_options("max_calls"),
  max_cost_usd = gr_options("max_cost_usd"),
  max_tokens_total = gr_options("max_tokens_total"),
  max_output_tokens = gr_options("max_output_tokens"),
  allowed_models = gr_options("allowed_models"),
  allow_unpriced = gr_options("allow_unpriced")
)
```

## Arguments

- max_calls:

  Most requests the run may make, cache hits and embeddings requests
  included. `NULL` or `Inf` for no limit.

- max_cost_usd:

  Most the run may spend, in USD. `NULL` or `Inf` for no limit.

- max_tokens_total:

  Most tokens the run may use, prompts, replies and embedded text
  together. `NULL` or `Inf` for no limit.

- max_output_tokens:

  Largest output cap one request may be sent with. A request with a
  larger cap is refused, not cut down. `NULL` or `Inf` for no limit.

- allowed_models:

  Character vector of the model ids the run may call (chat and embedding
  models alike), or `NULL` for any.

- allow_unpriced:

  `TRUE` to send requests to models with no registered price under a
  spending limit.

## Value

An object of class `hr_governor`: a list of the six limits.

## Details

A request is checked against its worst case: the most prompt tokens it
can be billed for at the model's input price, plus its output cap as
sent (for a reasoning model the raised cap; see
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md))
at the output price. The prompt is counted as the trace counts it, with
the JSON schema and extra body fields the request carries, a few tokens
for each message's framing, and `safety_margin` (see
[`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md))
on top. One that would take the run past `max_cost_usd` is refused, so a
run ends at or under the limit rather than one request over it. That
bound rests on two things the governor cannot see: that a provider stops
a reply at its cap (a
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
or
[`gr_backend_client()`](https://elkronos.github.io/readgpt/reference/gr_backend_client.md)
handler that returns more is charged for what it returned), and that the
provider counts the prompt within the margin of the local tokenizer. A
provider that reports more prompt tokens than that, or a tokenizer far
from the provider's (the `"heuristic"` one, say), can leave a run a
little over the limit. A run whose requests leave their output cap at
the model's limit is stopped while it still has headroom that a smaller
cap would have used.

A refused request is not sent and is not a call: it adds nothing to the
trace's `calls`, steps or spend. It comes back from
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md)
as a failed
[gr_result](https://elkronos.github.io/readgpt/reference/gr_result.md)
with `refused = TRUE` and an error that names the limit, and a condition
of class `hr_budget_refused` is signalled, which a caller can catch with
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) or
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) to stop instead.
The trace records the refusal in `refusals`, sets `budget_stop` and
names the limit in `stop_reason`: `"calls"`, `"cost"`, `"tokens"` (the
token ceiling), `"output"` (the per-call ceiling), `"model"` (not an
allowed model) or `"unpriced"`.

A text-generation model with no registered price cannot be held to a
spending limit, so while `max_cost_usd` is a finite number a request to
one is refused (a condition of class `hr_unpriced_model` as well as
`hr_budget_refused`), unless `allow_unpriced = TRUE`. With
`allow_unpriced = TRUE` the request is sent, the trace prices it at
`NA`, never 0, and `max_calls`, `max_tokens_total` and the other limits
still apply: `max_tokens_total` is the limit that bounds such a run,
since the spending limit cannot. An embedding model with no price is not
refused; its requests count against `max_calls` and add nothing to the
spend, as
[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md)
warns.
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
makes no paid requests and is never refused as unpriced. A request a
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
answers spends nothing and is checked only against `max_calls`,
`max_output_tokens` and `allowed_models`.

`max_tokens_total` holds the tokens of the run: the prompt and reply
tokens of every call the trace records, cache hits included, and the
text sent to be embedded. A request is refused when what the run has
used plus its own worst case (prompt as above, reply at its cap) would
pass it.

A governor is attached to a run with `gr_trace(governor = )`, and then
governs the requests recorded into that trace. A stage that keeps a
trace of its own and folds it into the one it is given
([`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md),
[`gr_claims()`](https://elkronos.github.io/readgpt/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/readgpt/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/readgpt/reference/gr_synthesise.md))
holds its requests to that trace's governor, less what the given trace
has already spent and used in tokens; `max_calls` stays a limit per
document for
[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md)
and per stage for the others, as with the options. A trace made without
one, including those the package makes for itself, reads the limits from
[`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md)
each time it checks, so changing an option affects runs that are already
going, as it always has.

## See also

[`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md)
for the session defaults,
[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md),
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md)
to give a model its prices

## Examples

``` r
cl <- gr_mock_client(function(m, p) "ok")
tr <- gr_trace(governor = hr_governor(max_calls = 2))
vapply(1:3, function(i) gr_call(cl, "hi", trace = tr)$ok, logical(1))
#> [1]  TRUE  TRUE FALSE
tr$calls
#> [1] 2
tr$stop_reason
#> [1] "calls"

# A request whose worst case would pass the spending limit is not sent.
tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.001))
res <- gr_call(cl, "hi", model = "gpt-4o", trace = tr)
res$refused
#> [1] TRUE
res$error
#> [1] "spending limit reached: the 'call' request could cost up to $0.16 (up to 13 prompt tokens, and 16384 reply tokens at its cap), and the run has spent $0 of its $0.001 limit, so it was not sent; raise gr_options(max_cost_usd =) or ask for a smaller max_output"
```
