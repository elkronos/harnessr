# Limits on what a run may send

A governor holds the limits that every request a run makes is checked
against before it is sent: how many calls the run may make, what it may
spend, the largest output cap one request may carry, and which models it
may call.
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md),
and every reader, judge, adjudication, segmenter and embeddings request
in the package, goes through the same check, so a limit holds whether or
not the code that makes the call looks at it.

## Usage

``` r
hr_governor(
  max_calls = hr_options("max_calls"),
  max_cost_usd = hr_options("max_cost_usd"),
  max_tokens_total = hr_options("max_tokens_total"),
  max_output_tokens = hr_options("max_output_tokens"),
  allowed_models = hr_options("allowed_models"),
  allow_unpriced = hr_options("allow_unpriced"),
  reserve_calls = hr_options("reserve_calls"),
  reserve_usd = hr_options("reserve_usd")
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
  spending limit, with a warning once per model per session; `FALSE` to
  refuse them.

- reserve_calls:

  Calls held back from `max_calls` for closing requests, a whole number
  of 0 or more, at most `max_calls`. 0 holds none back.

- reserve_usd:

  Dollars held back from `max_cost_usd` for closing requests, 0 or more,
  at most `max_cost_usd`. 0 holds none back.

## Value

An object of class `hr_governor`: a list of the six limits, plus
`reserve_calls` and `reserve_usd` when either is above 0.

## Details

A request is checked against its worst case: the most prompt tokens it
can be billed for at the model's input price, plus its output cap as
sent (for a reasoning model the raised cap; see
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md))
at the output price. The prompt is counted as the trace counts it, with
the JSON schema and extra body fields the request carries, a few tokens
for each message's framing, and `safety_margin` (see
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md))
on top. One that would take the run past `max_cost_usd` is refused, so a
run ends at or under the limit rather than one request over it. That
bound rests on two things the governor cannot see: that a provider stops
a reply at its cap (a
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
or
[`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md)
handler that returns more is charged for what it returned), and that the
provider counts the prompt within the margin of the local tokenizer. A
provider that reports more prompt tokens than that, or a tokenizer far
from the provider's (the `"heuristic"` one, say), can leave a run a
little over the limit. A run whose requests leave their output cap at
the model's limit is stopped while it still has headroom that a smaller
cap would have used.

A refused request is not sent and is not a call: it adds nothing to the
trace's `calls`, steps or spend. It comes back from
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
as a failed
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md)
with `refused = TRUE` and an error that names the limit, and a condition
of class `hr_budget_refused` is signalled, which a caller can catch with
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) or
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) to stop instead.
The trace records the refusal in `refusals`, sets `budget_stop` and
names the limit in `stop_reason`: `"calls"`, `"cost"`, `"tokens"` (the
token ceiling), `"output"` (the per-call ceiling), `"model"` (not an
allowed model) or `"unpriced"`.

A text-generation model with no registered price cannot be held to a
spending limit. harnessr ships no prices, so by default
(`allow_unpriced = TRUE`) a request to one is sent while `max_cost_usd`
is a finite number, and the trace prices it at `NA`, never 0. The first
such request to each model in a session warns, with class
`hr_unpriced_model`, that the spending limit does not cover the model
until you set its prices with
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
or
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md).
`max_calls`, `max_tokens_total` and the other limits still apply:
`max_tokens_total` is the limit that bounds such a run, since the
spending limit cannot. With `allow_unpriced = FALSE` the request is
refused instead (a condition of class `hr_unpriced_model` as well as
`hr_budget_refused`), for a run in which every request must be priced.
An embedding model with no price is neither refused nor warned about
here; its requests count against `max_calls` and add nothing to the
spend, as
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
warns.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
makes no paid requests, so it is never refused or warned about as
unpriced. A request an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
answers spends nothing and is checked only against `max_calls`,
`max_output_tokens` and `allowed_models`.

`max_tokens_total` holds the tokens of the run: the prompt and reply
tokens of every call the trace records, cache hits included, and the
text sent to be embedded. A request is refused when what the run has
used plus its own worst case (prompt as above, reply at its cap) would
pass it.

A governor is attached to a run with `hr_trace(governor = )`, and then
governs the requests recorded into that trace. A stage that keeps a
trace of its own and folds it into the one it is given
([`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md))
holds its requests to that trace's governor, less the calls the given
trace has already made and what it has spent and used in tokens, so the
governor's limits hold for the run as a whole. Without a governor,
`hr_options(max_calls =)` stays a limit per document for
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
and per stage for the others. A trace made without one, including those
the package makes for itself, reads the limits from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
each time it checks, so changing an option affects runs that are already
going, as it always has.

## A reserve for the closing call

A reader that works in rounds (the `iterative` reader's steps, the
`map_reduce` reader's chunks) makes its answer in one last request. When
the rounds use up `max_calls` or `max_cost_usd`, that request is
refused, and the rounds already paid for end as not found.
`reserve_calls` and `reserve_usd` hold part of each limit back for such
a request. An ordinary request is refused once it would reach into the
reserve: with `max_calls = 10` and `reserve_calls = 1`, ordinary
requests stop at 9 calls. A request marked as closing may spend the
reserve, up to the limit itself.

A request is marked closing by the code that sends it, with
`hr_call(closing = TRUE)`. The readers mark their final request: the
`iterative` reader's final answer (`iterative.final`), the `map_reduce`
reader's last merge (`reduce`), the answer request of the
`hierarchical`, `skim`, `preview` and `rerank` readers and of the
`refine` reader under `refine_state = "ledger"`, and the `ensemble`
reader's adjudication. The `stuff` and `retrieve` readers make one model
call each, and the `refine` reader's last revision is its answer
otherwise; they mark none. In an ensemble each member's closing request
may spend the reserve too, so hold back one call per member and one for
the adjudication. You set the reserve; nothing a model returns changes
it or marks a request.

Both reserves default to 0, which holds nothing back: requests, refusals
and cache keys are then what they were before the reserve existed. A
reserve larger than its limit is refused with an error of class
`hr_bad_reserve`. A reserve with no limit to hold back from (`max_calls`
or `max_cost_usd` `NULL`) has no effect. The requests of a parallel
batch are ordinary: each worker's share is taken from what is left
outside the reserve. Two governors combined (a judge's own and the
run's) hold an ordinary request to the lower of the two limits less
their reserves, and a closing request to the lower of the two limits.

## See also

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
for the session defaults,
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md),
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
to give a model its prices

## Examples

``` r
cl <- hr_mock_client(function(m, p) "ok")
tr <- hr_trace(governor = hr_governor(max_calls = 2))
vapply(1:3, function(i) hr_call(cl, "hi", trace = tr)$ok, logical(1))
#> [1]  TRUE  TRUE FALSE
tr$calls
#> [1] 2
tr$stop_reason
#> [1] "calls"

# A request whose worst case would pass the spending limit is not sent.
# The limit needs a price; this one is illustrative, so use your
# provider's current prices.
hr_register_model("my-priced-model", context_window = 128000, max_output = 4096,
                  input_usd = 2.5, output_usd = 10)
tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.001))
res <- hr_call(cl, "hi", model = "my-priced-model", trace = tr)
res$refused
#> [1] TRUE
res$error
#> [1] "spending limit reached: the 'call' request could cost up to $0.04 (up to 13 prompt tokens, and 4096 reply tokens at its cap), and the run has spent $0 of its $0.001 limit, so it was not sent; raise hr_options(max_cost_usd =) or ask for a smaller max_output"

# A reserve keeps one call for the closing request.
tr <- hr_trace(governor = hr_governor(max_calls = 3, reserve_calls = 1))
vapply(1:3, function(i) hr_call(cl, "hi", trace = tr)$ok, logical(1))
#> [1]  TRUE  TRUE FALSE
hr_call(cl, "answer", trace = tr, closing = TRUE)$ok
#> [1] TRUE
tr$calls
#> [1] 3
```
