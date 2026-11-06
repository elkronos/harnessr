# Create a run trace

Create a run trace

## Usage

``` r
gr_trace(
  run_id = NULL,
  meta = list(),
  system = NULL,
  owner = NULL,
  run_by = NULL,
  purpose = NULL,
  approved_by = NULL,
  governor = NULL
)

# S3 method for class 'gr_trace'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)
```

## Arguments

- run_id:

  Optional identifier; generated when omitted.

- meta:

  Named list of run-level metadata.

- system, owner, run_by, purpose, approved_by:

  Who the run is for and who ran it: the system it belongs to, the
  person or team accountable for that system, the person who ran it,
  what it was for, and who approved it. Each is one string. One left
  `NULL` is taken from `gr_options("actor")`, and is `NA` when that does
  not name it either.

- governor:

  An
  [`hr_governor()`](https://elkronos.github.io/readgpt/reference/hr_governor.md)
  holding the limits every request recorded into this trace is checked
  against before it is sent, or `NULL` (the default) to read them from
  [`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md)
  at each check.

- x:

  A `gr_trace`.

- row.names:

  Optional row names for the result.

- optional, ...:

  Ignored; part of the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

## Value

A `gr_trace`. It is an environment, so it accumulates by reference: pass
the same trace to several calls and they all record into it. Fields:
`run_id`, `started`, `meta`, `actor`, `config`, `steps`, `calls`,
`cached`, `tokens_in`, `tokens_out`, `embed_tokens`, `errors`,
`budget_stop`, `stop_reason`, `spent_usd`, `replayed_usd`, `refusals`,
`governor`.

`actor` holds the five fields above. `config` is a snapshot of the
options in force when the trace was made
([`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md),
with the values of `api_headers` left out, since they can hold
credentials) and the R version, so a saved trace says what it ran under.
[`as_json()`](https://elkronos.github.io/readgpt/reference/as_json.md)
writes `started` in UTC, as ISO 8601 with a trailing `Z`. `cached`
counts the calls answered from a
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
or a
[`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md)
rather than the network, so `calls - cached` is what the run paid for.
`calls` includes requests to an embeddings endpoint, recorded as steps
labelled `"embed.request"`. Their tokens are counted in `embed_tokens`,
not in `tokens_in`, so `tokens_in` and `tokens_out` stay the size of the
model calls' prompts and replies.

`errors` has one entry per request that failed: its `step`, `label` and
`error`. A failure the run recovered from without losing any input also
carries `recovered = TRUE`: the document was read in full, and
[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md)
does not count it as failed. Only some fallbacks mark the answer
partial. An embeddings request replaced by
[`gr_embed()`](https://elkronos.github.io/readgpt/reference/gr_embed.md)'s
lexical fallback does when the vectors ranked the chunks a reader sent
(the `retrieve`, `rerank` and `iterative` readers). The same fallback
while
[`gr_segment()`](https://elkronos.github.io/readgpt/reference/gr_segment.md)
made semantic cuts, and a proposition batch kept as written, leave the
answer unmarked and say so in its `$warnings`. A contextual header that
could not be written leaves no mark on the answer at all, and this entry
is the record of it.

`budget_stop` is `TRUE` once a limit stopped the run, and `stop_reason`
says which: `"calls"` for `max_calls`, `"cost"` for `max_cost_usd`,
`"tokens"` for `max_tokens_total`, and `"output"`, `"model"` or
`"unpriced"` for the other limits of
[`hr_governor()`](https://elkronos.github.io/readgpt/reference/hr_governor.md)
(see
[`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md)).
`refusals` has one entry per request the governor did not send: its
`label`, `model`, the `limit` it would have passed, its worst-case cost
`worst_usd`, the run's `calls` and `spent_usd` at that moment, and the
`message`. A refused request is not a call and has no step. `spent_usd`
is what the calls so far cost. A call to a model with no registered
price (sent under `allow_unpriced = TRUE`) adds nothing to it, so
[`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md)
is the full account. `replayed_usd` is what the calls a
[`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md)
answered cost when they were recorded, counted when the spending limit
stopped the recorded run: nothing was paid for them, but `max_cost_usd`
is checked against `spent_usd + replayed_usd`, so the replay stops at
the same call. A call answered from a
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
adds to neither, so a re-run through a warm cache under the same limit
reads further than the run that filled it.
[`as_json()`](https://elkronos.github.io/readgpt/reference/as_json.md)
and
[`gr_trace_save()`](https://elkronos.github.io/readgpt/reference/gr_trace_save.md)
write `budget_stop`, `stop_reason`, `spent_usd` and `replayed_usd`, so a
saved run says whether it was cut short, and `refusals` and `governor`
when there are any.

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on a
trace returns one row per request; see below.

## Steps

Each request is one entry in `steps`. Besides its label, prompt, reply
and the model it asked for (`model`), a step records:

- `params`:

  What the call asked for: the parameters a
  [`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
  or
  [`gr_backend_client()`](https://elkronos.github.io/readgpt/reference/gr_backend_client.md)
  handler is given, which is also what a
  [`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md)
  looks a call up by.

- `params_sent`:

  The request as it went out, every default resolved: `model`, `api`,
  `base_url`, `max_output` (for a reasoning model, the larger cap its
  request is sent with; see
  [`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md)),
  `temperature` (`NA` when none was sent), `effort`, `schema_name`, and
  SHA-256 hashes of the JSON schema (`schema_hash`) and of the extra
  body fields the client and the call added (`extra_body_hash`). For a
  [`gr_client()`](https://elkronos.github.io/readgpt/reference/gr_client.md)
  it is read from the request body; for a handler, from the parameters
  the handler was given, which carry no extra body fields. A call
  answered from a
  [`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
  records what would have been sent, and one a replay answered records
  what the recorded call sent.

- `tokens`:

  `input` and `output`, plus `reasoning` and `cached_input` when the
  provider reported them (they are parts of `output` and `input`, not
  additions), and `provenance`: `"reported"` when the provider gave the
  counts, `"counted"` when they were counted here with the `"tiktoken"`
  tokenizer, `"estimated"` when they were estimated with another one,
  and `NA` for a reply cached or recorded before provenance was kept.

- `served_model`, `response_id`, `fingerprint`:

  The model the provider said answered, its response id and its system
  fingerprint, where it returned them, else `NA`. None of them is part
  of a cache or replay key.

- `attempts`:

  How many requests were sent for this one, retries included: 0 when a
  cache or a recording answered it.

- `started_utc`, `ended_utc`:

  When the request started and ended, ISO 8601 in UTC with a trailing
  `Z`.

## One row per request

`as.data.frame(trace)` has one row for each request the run made, in the
order they were made, and none for local steps such as segmentation:

- `step`:

  The step's number in `trace$steps`, where the full record is.

- `document`:

  The document the request was about, when the run recorded one: the
  file name, web address or `"<inline text>"`.

- `recipe`:

  The recipe the request belonged to, when recorded.

- `stage`:

  What the request was for, such as `"map.answer"` or `"reduce"`.

- `model`, `ok`, `cached`:

  The model, whether a usable reply came back, and whether it came from
  a
  [`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
  or a
  [`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md).

- `tokens_in`, `tokens_out`:

  The size of the prompt and the reply.

- `usd`:

  What the request cost, 0 when it came from a cache or failed without
  sending any tokens. `NA` when the model has no registered price, as in
  [`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md),
  whose total the column adds up to.

- `seconds`:

  How long the request took, retries included. `NA` for a trace written
  by a version of readgpt that did not time requests.

- `error`:

  The error, or `NA`.

- `prompt`, `reply`:

  The messages sent, each as `"[role] text"`, and the text that came
  back.

- `effort`:

  The reasoning effort the request was sent with, `NA` for one sent
  none. Present only when some request in the trace carried one (see
  `effort` in
  [`gr_read_spec()`](https://elkronos.github.io/readgpt/reference/gr_read_spec.md)).

- `tokens_reasoning`, `tokens_cached_in`, `served_model`:

  The reasoning and cached input tokens the provider reported and the
  model it said answered, `NA` where it did not. Each is present only
  when some request in the trace has it.

A request's `usd` prices its cached input tokens at the model's cached
input rate when
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md)
gave it one, and at the input rate otherwise.

## See also

[`gr_trace_summary()`](https://elkronos.github.io/readgpt/reference/gr_trace_summary.md),
[`as_json()`](https://elkronos.github.io/readgpt/reference/as_json.md),
[gr_answer](https://elkronos.github.io/readgpt/reference/gr_answer.md),
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)

## Examples

``` r
tr <- gr_trace(meta = list(purpose = "demo"))
cl <- gr_mock_client(function(m, p) "an answer")
ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'sentence' (cap 150 tokens, overlap 0).
invisible(gr_read(ch, "What was revenue?", cl, "map_reduce", trace = tr))
#> Reading with 'map_reduce' (all|N+logN|tree) over 5 chunk(s).
print(tr)
#> <gr_trace run_20261106065733.540_7016c3>  7 steps, 6 model calls, 1118 in / 36 out tokens, 0 error(s)
#>   steps: map.answer x5, preflight x1, reduce x1 
#>   cost: $0.0000 across mock-model
#>   usage: estimated locally for 100% of requests (the provider reported none)
#>   started: 2026-11-06T06:57:33.540Z 

# One row per request, with what each cost and how long it took.
reqs <- as.data.frame(tr)
reqs[, c("step", "stage", "tokens_in", "tokens_out", "usd", "seconds")]
#>   step      stage tokens_in tokens_out usd seconds
#> 1    2 map.answer       201          6   0   0.001
#> 2    3 map.answer       210          6   0   0.001
#> 3    4 map.answer       187          6   0   0.001
#> 4    5 map.answer       193          6   0   0.001
#> 5    6 map.answer       163          6   0   0.001
#> 6    7     reduce       164          6   0   0.001
```
