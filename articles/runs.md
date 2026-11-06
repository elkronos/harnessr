# Cost, limits and reproducible runs

Every stage of harnessr except one is a pure function of its input.
Extraction, cleaning, segmentation, ranking and merging give the same
result every time. The model call is the only step that costs money, the
only step that can die halfway through a long run, and, above a
temperature of zero, the only step that does not return the same thing
twice.

This guide covers what harnessr does about that: what a run records, the
limits every request is checked against before it is sent, the cache
that makes a repeat free, and the replay that reproduces a run from its
trace with no key and no spend.
[`vignette("harnessr")`](https://elkronos.github.io/readgpt/articles/harnessr.md)
introduces the package and its ideas.

## Setting up

The examples run offline.
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
plays the part of the model, and `embedder = "lexical"` gives free,
deterministic word-overlap vectors in place of an embeddings endpoint.

A mock costs nothing, which would leave every limit below with nothing
to count. So the examples give it a price:
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md)
registers a model id at \$2 per million input tokens and \$8 per million
output tokens, and each run names that model, so every request is priced
at those rates.

``` r

library(harnessr)

gr_register_model("priced-mock", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)
old <- gr_options(verbose = FALSE, embedder = "lexical")

cl <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

## What a run records

Everything below is recorded on the answer, and `print(ans)` sums it up:
the cost, where the evidence came from and, when the answer is partial,
why.

``` r

ans <- answer_document(gr_example(), "What was revenue?", "thorough",
                       client = cl, model = "priced-mock", max_tokens = 150)
ans
#> <gr_answer> reader=map_reduce
#>   Q: What was revenue?
#>   11 model call(s), 2444 in / 143 out tokens, 0 error(s), $0.0060 across priced-mock
#>   ---
#> Revenue was 45.2 million dollars. 
#>   ---
#>   Evidence: chunk 1, chunk 2, chunk 3 ("Operations"), chunk 4, chunk 5, chunk 6, and 4 more
```

Check `ans$partial` first. `TRUE` means something degraded, and
`ans$notes` says what: `dropped_chunks`, `failed_calls`, `unread_pages`,
`call_cap_reached`, `cost_cap_reached` and so on. `ans$warnings` holds
every warning raised while the document was read.

The trace holds every request the run made.
[`gr_trace_summary()`](https://elkronos.github.io/readgpt/reference/gr_trace_summary.md)
gives the totals,
[`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md)
the bill by model, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) one row
per request with its stage, tokens, cost, time, prompt and reply:

``` r

gr_trace_summary(ans$trace)[, c("calls", "cached", "tokens_in", "tokens_out", "errors")]
#>   calls cached tokens_in tokens_out errors
#> 1    11      0      2444        143      0
gr_trace_cost(ans$trace)[, c("model", "calls", "paid_calls", "usd")]
#>         model calls paid_calls      usd
#> 1 priced-mock    11         11 0.006032
as.data.frame(ans$trace)[, c("step", "stage", "tokens_in", "tokens_out", "usd")]
#>    step      stage tokens_in tokens_out      usd
#> 1     4 map.answer       204         13 0.000512
#> 2     5 map.answer       210         13 0.000524
#> 3     6 map.answer       227         13 0.000558
#> 4     7 map.answer       179         13 0.000462
#> 5     8 map.answer       221         13 0.000546
#> 6     9 map.answer       221         13 0.000546
#> 7    10 map.answer       228         13 0.000560
#> 8    11 map.answer       226         13 0.000556
#> 9    12 map.answer       205         13 0.000514
#> 10   13 map.answer       227         13 0.000558
#> 11   14     reduce       296         13 0.000696
```

The token totals are the size of the prompts and replies, which is the
shape of a run, not its bill.
[`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md)
counts only the calls that were issued: a call answered from a cache or
a recording spent nothing, however long its prompt. A model with no
registered price contributes `NA`, never 0, so a total cannot quietly
leave one out.

You can also ask what a run would cost before you make it:

``` r

gr_estimate_cost("priced-mock", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.272
```

### What each request records

Each request is one entry in `trace$steps`. Besides its label, prompt,
reply and the model it asked for, a step records:

- `params`, what the call asked for, and `params_sent`, the request as
  it went out with every default resolved: the model, `api`, `base_url`,
  the output cap sent, the temperature (`NA` when none was sent), the
  effort, the schema name, and SHA-256 hashes of the JSON schema and of
  any extra body fields. A reasoning model’s small cap goes out raised
  to 2048, and `params_sent` shows the raised one.
- `served_model`, `response_id` and `fingerprint`, where the provider
  returns them. `model` stays the model asked for, which is what the
  step is priced and replayed by.
- `attempts`, the number of requests sent, retries included (0 for a
  reply from a cache or a recording), and `started_utc` and `ended_utc`
  in ISO 8601 UTC.
- `tokens`, with `provenance`: `"reported"` by the provider, `"counted"`
  here with the `"tiktoken"` tokenizer, or `"estimated"` with another
  one. Reasoning and cached input tokens the provider reports are kept
  as `tokens$reasoning` and `tokens$cached_input`, as parts of `output`
  and `input` rather than additions.

``` r

step <- ans$trace$steps[[length(ans$trace$steps)]]
str(step[c("label", "attempts", "started_utc", "tokens")])
#> List of 4
#>  $ label      : chr "reduce"
#>  $ attempts   : int 1
#>  $ started_utc: chr "2026-11-06T09:17:44.968Z"
#>  $ tokens     :List of 3
#>   ..$ input     : int 296
#>   ..$ output    : int 13
#>   ..$ provenance: chr "estimated"
str(step$params_sent)
#> List of 9
#>  $ model          : chr "priced-mock"
#>  $ api            : chr "mock"
#>  $ base_url       : chr "mock://"
#>  $ max_output     : int 1500
#>  $ temperature    : num NA
#>  $ effort         : chr NA
#>  $ schema_name    : chr NA
#>  $ schema_hash    : chr NA
#>  $ extra_body_hash: chr NA
```

A mock reports no usage, so its counts are estimated.
[`gr_trace_summary()`](https://elkronos.github.io/readgpt/reference/gr_trace_summary.md)
gives the share of requests whose counts were estimated as
`usage_estimated`, and [`print()`](https://rdrr.io/r/base/print.html) on
a trace says so when it is above zero.

`refine` and `hierarchical` also record the length of the state they
carry forward. Each `refine.draft` and `refine.revise` step has
`state$tokens_in`, the draft the request carried, and
`state$tokens_out`, the draft carried on from it (the old one when the
reply was unusable). Each `hier.summarise.L<k>` step has the length of
the text it summarised and of the summary it returned, and each level
adds a local `hier.state.L<k>` step with the number of summaries handed
on and their combined length. A draft that shrinks sharply in one
revision shows up there.

Every cut made to fit a limit writes a local `truncate` step with where
it was made (`detail$where`), the token limit, and the tokens before,
kept and dropped. `refine` and `hierarchical` answers add the tokens cut
as `notes$tokens_truncated`, and printing one says how many tokens were
cut to fit. Here a model with a 1,000-token window makes `refine` cut
its growing draft:

``` r

gr_register_model("small-window", context_window = 1000, max_output = 500,
                  input_usd = 2, output_usd = 8)
long_draft <- paste(rep("Revenue was 45.2 million dollars, and the draft says so.", 30),
                    collapse = " ")
cut <- answer_document(gr_example(), "What was revenue?", "fast",
                       client = gr_mock_client(function(messages, params) long_draft),
                       reader = "refine", model = "small-window",
                       max_tokens = 120, max_answer_tokens = 200)
cuts <- Filter(function(s) identical(s$label, "truncate"), cut$trace$steps)
str(cuts[[1]]$detail)
#> List of 6
#>  $ where         : chr "refine.draft"
#>  $ limit         : int 280
#>  $ tokens_before : int 453
#>  $ tokens_kept   : int 271
#>  $ tokens_dropped: int 182
#>  $ chunk_id      : int 2
cut$notes$tokens_truncated
#> [1] 910
```

The other places a cut can be made are `refine.excerpt`,
`hier.summaries`, `preview.skim`, `preview.outline`, `<label>.input` for
a finding cut to fit a merge, `<label>.giveup` for the capped findings a
failed merge returns, `segment.contextual.header`,
`segment.contextual.document`, `screen.opening`, `synthesise.gaps` and
`embed.input`.

A trace also records who the run is for and what it ran under.
[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md)
takes `system`, `owner`, `run_by`, `purpose` and `approved_by`, and
`gr_options(actor = list(...))` sets them for every trace; a field named
nowhere is `NA`. `trace$config` is a snapshot of the options in force
when the trace was made, with the R version. The values of `api_headers`
are left out, since they can hold credentials.

``` r

tr <- gr_trace(owner = "finance team", run_by = "ana", purpose = "Q3 check")
tr
#> <gr_trace run_20261106091745.338_fd68b9>  0 steps, 0 model calls, 0 in / 0 out tokens, 0 error(s)
#>   cost: no cost recorded
#>   actor: owner = finance team, run_by = ana, purpose = Q3 check 
#>   started: 2026-11-06T09:17:45.338Z
names(tr$config)
#> [1] "options"   "r_version"
```

`as_json(ans)` writes the answer with every prompt and response from the
same run, and
[`gr_trace_save()`](https://elkronos.github.io/readgpt/reference/gr_trace_save.md)
writes the trace alone, which is what a replay reads.

### Errors and warnings by class

Errors are classed, so you can catch a specific failure:
`gr_auth_error`, `gr_file_not_found`, `gr_empty_document`,
`gr_unsupported_format`, `gr_overflow`, `gr_call_cap`, `gr_cost_cap`,
`gr_budget_error`, `gr_unknown_model`, `gr_unknown_override`,
`gr_no_recipes`, `gr_bad_ensemble`, `gr_missing_dep`, `gr_bad_setting`
for a setting outside its choices
([`vignette("extending")`](https://elkronos.github.io/readgpt/articles/extending.md)),
`hr_unknown_effort_key` and `hr_unpriced_model` (both below), and
`hr_dim_mismatch` when two vectors of different lengths are compared,
such as a lexical fallback vector against an API embedding. Degradations
are classed warnings: `gr_segment_fallback`, `gr_embed_fallback`,
`gr_rerank_degraded`, `gr_iterative_degraded`, `gr_ensemble_degenerate`,
`gr_duplicate_recipe`, `gr_deprecated`, `gr_ocr_unavailable`,
`gr_clamped` with `hr_param_clamped` for a parameter moved to its
nearest bound
([`vignette("extending")`](https://elkronos.github.io/readgpt/articles/extending.md)),
`gr_parallel_share` for a parallel item whose share refused a later
request (below), `gr_bad_correct` for a
[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md)
`correct` function that fails (below), and `gr_unclear_dropped` when
[`gr_extract()`](https://elkronos.github.io/readgpt/reference/gr_extract.md)
leaves unclear screening records out
([`vignette("review")`](https://elkronos.github.io/readgpt/articles/review.md)).

In an interactive session a long read keeps one line up to date with how
many chunks it has read and what it has spent, and
[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md)
gives the spend so far before each document.

## Limits

Two limits are on by default: a run may spend \$5 and make 400 calls.

``` r

unlist(gr_options()[c("max_cost_usd", "max_calls")])
#> max_cost_usd    max_calls 
#>            5          400
```

They are checked twice. Before the first request, a run is refused with
a classed error naming the option to change when it would need more
calls than `max_calls`, or when its reader sends every chunk and sending
them would already cost more than `max_cost_usd`. Here `map_reduce` over
five chunks needs six calls:

``` r

chunks <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
spec <- gr_read_spec(reader = "map_reduce", model = "priced-mock")

tryCatch(
  gr_read(chunks, "What was revenue?", cl, spec,
          trace = gr_trace(governor = hr_governor(max_calls = 3))),
  gr_call_cap = function(e) conditionMessage(e))
#> [1] "Reader 'map_reduce' over 5 chunks would need about 6 more model calls (0 already made this run), above the 3-call cap. Use a larger `max_tokens` when segmenting (fewer chunks), pick a top-k reader, or raise gr_options(max_calls = ...)."
```

### Every request is checked before it is sent

Then every request is checked before it goes out, against what the run
has spent plus the most the request could cost: its prompt at the input
price and its output cap at the output price. The prompt is counted with
the JSON schema and extra body fields the request carries and a few
tokens of framing per message, then raised by `safety_margin`, since the
provider bills for all of that. A request that could take the run past a
limit is not sent, so a run ends at or under its limit rather than one
request over it.

Under a limit of one cent, the five chunk requests below go out and the
merge does not. Its reply cap is 1500 tokens, which at \$8 per million
could cost more than the run has left, so the answer comes back partial:

``` r

tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.01))
capped <- gr_read(chunks, "What was revenue?", cl, spec, trace = tr)
capped$partial
#> [1] TRUE
data.frame(calls = tr$calls, spent_usd = tr$spent_usd, stop_reason = tr$stop_reason)
#>   calls spent_usd stop_reason
#> 1     5  0.002428        cost
tr$refusals[[1]]$message
#> [1] "spending limit reached: the 'reduce' request could cost up to $0.01 (up to 232 prompt tokens, and 1500 reply tokens at its cap), and the run has spent $0.0024 of its $0.01 limit, so it was not sent; raise gr_options(max_cost_usd =) or ask for a smaller max_output"
```

The bound rests on two things harnessr cannot see: that the provider
stops each reply at its cap, and that it counts the prompt within
`safety_margin` of the local tokenizer. A run that leaves its output
caps at the model’s limit stops while it still has headroom a smaller
cap would have used. With the merge’s reply held to 500 tokens, the same
run fits:

``` r

tr <- gr_trace(governor = hr_governor(max_cost_usd = 0.01))
fits <- gr_read(chunks, "What was revenue?", cl,
                gr_read_spec(reader = "map_reduce", model = "priced-mock",
                             max_answer_tokens = 500),
                trace = tr)
fits$partial
#> [1] FALSE
data.frame(calls = tr$calls, spent_usd = tr$spent_usd)
#>   calls spent_usd
#> 1     6  0.002922
```

A refused request is not a call. It adds nothing to the trace’s calls,
steps or spend.
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md)
returns it as a failed result with `refused = TRUE` and an error naming
the limit, after signalling a condition of class `hr_budget_refused`,
which you can catch to stop instead. The trace lists it in `refusals`,
sets `budget_stop` and names the limit in `stop_reason`: `"calls"`,
`"cost"`, `"tokens"`, `"output"`, `"model"` or `"unpriced"`. Readers and
review stages mark the answer or section partial and do not count the
request as failed.

The check sits on the call path itself, so it covers every request:
readers, judges, the ensemble’s adjudication, conflict resolution in
[`gr_extract()`](https://elkronos.github.io/readgpt/reference/gr_extract.md),
context and proposition segmentation, claims, outlines, screening,
synthesis, embeddings, and any request a custom reader or a script makes
with
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md).

### A governor for one run

[`hr_governor()`](https://elkronos.github.io/readgpt/reference/hr_governor.md)
holds a run’s limits. Attach one with `gr_trace(governor = )`; a trace
without one reads the limits from
[`gr_options()`](https://elkronos.github.io/readgpt/reference/gr_options.md)
each time it checks. It has six:

| limit | what it holds | default |
|----|----|----|
| `max_calls` | requests the run may make, cache hits and embeddings included | 400 |
| `max_cost_usd` | what the run may spend, in USD | 5 |
| `max_tokens_total` | tokens of every prompt, reply and embedded text | off |
| `max_output_tokens` | the largest output cap one request may carry; a request with a larger one is refused, not cut down | off |
| `allowed_models` | the model ids the run may call, text and embedding models alike | any |
| `allow_unpriced` | whether a model with no registered price may be called under a spending limit | `FALSE` |

Each is also an option of the same name, so
`gr_options(max_tokens_total = 50000)` sets it for every run, and each
trace’s config snapshot lists them all. `NULL` or `Inf` removes a limit.
A limit that cannot be compared is refused when you set it:

``` r

tryCatch(gr_options(max_cost_usd = NA), error = function(e) conditionMessage(e))
#> [1] "gr_options(max_cost_usd = ) must be a single number or NULL, not NA. A limit that cannot be compared is not a limit, so this is refused here rather than ignored later."
```

A request to a model the run may not call is refused the same way as one
over budget:

``` r

tr <- gr_trace(governor = hr_governor(allowed_models = "gpt-4o"))
res <- gr_call(cl, "What was revenue?", model = "priced-mock", trace = tr)
data.frame(refused = res$refused, stop_reason = tr$stop_reason)
#>   refused stop_reason
#> 1    TRUE       model
```

[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md),
[`gr_claims()`](https://elkronos.github.io/readgpt/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/readgpt/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/readgpt/reference/gr_synthesise.md)
keep a trace of their own and fold it into the one they are given. They
hold their requests to that trace’s governor, less what it has already
spent and used in tokens; `max_calls` stays a limit per document and per
stage.
[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md)
holds the whole comparison to `max_cost_usd` and `max_tokens_total`.

### Models with no price

A language model with no registered price adds nothing to the spend, so
a spending limit could never stop it. While `max_cost_usd` is set, a
request to one is refused with a condition of class `hr_unpriced_model`,
and
[`gr_read()`](https://elkronos.github.io/readgpt/reference/gr_read.md)
stops before its first request.
[`gr_backend_client()`](https://elkronos.github.io/readgpt/reference/gr_backend_client.md)
wraps an R function as a paying client, so it shows the refusal offline:

``` r

gr_register_model("unpriced-model", context_window = 128000, max_output = 4096)
backend <- gr_backend_client(function(messages, params) "Revenue was 45.2 million dollars.")

res <- gr_call(backend, "What was revenue?", model = "unpriced-model")
res$refused
#> [1] TRUE
res$error
#> [1] "unpriced model: 'unpriced-model' has no registered price, so what the 'call' request costs cannot be held to the $5 spending limit, and it was not sent. Register its prices with gr_register_model(input_usd =, output_usd =), or send it unpriced with gr_options(allow_unpriced = TRUE) or hr_governor(allow_unpriced = TRUE)"
```

Register the model’s prices with
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md),
or set `gr_options(allow_unpriced = TRUE)`. Then its requests are sent,
still count against `max_calls` and `max_tokens_total`, and are priced
`NA` in the trace. `max_tokens_total` is the limit that still bounds
such a run.
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
and replays are never refused for this, and neither are embedding models
with no price.

A
[`gr_ellmer_client()`](https://elkronos.github.io/readgpt/reference/gr_ellmer_client.md)
is priced as the model its ellmer object was built with, whatever a
recipe names, so one built on a model with no registered price is
refused too. Register that model at your provider’s current prices, or
let a local model run unpriced; the README’s “Connecting a model”
section shows both. Through ellmer, a `temperature` in a read spec is
ignored with a warning, because sampling parameters belong to the ellmer
object, and embeddings come from a function you pass as `embed =`;
without one, `retrieve` and the `semantic` segmenter fall back to
lexical vectors and say so.

### Parallel batches

With `parallel = TRUE`, per-chunk requests go out in batches that cannot
be stopped part way. Each worker’s items are held to an equal share of
the calls and dollars the run has left. If a worker’s share refuses an
item before it is sent, the item is run again in the calling process
against the run’s own limits. A batch the run’s limits cannot cover is
not split across workers; it runs in the calling process. Batch items
make one request each; an item that made more and had a later one
refused by its share warns with class `gr_parallel_share`, and the run
is not marked as stopped.

### How much the model reasons

`effort` sets how much a reasoning model reasons on each call, by stage;
[`vignette("readers")`](https://elkronos.github.io/readgpt/articles/readers.md)
explains how it is billed, which models it is sent to, and the label
each stage’s calls carry. In a review, the same vector goes to each
stage:
[`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md)
and
[`gr_extract()`](https://elkronos.github.io/readgpt/reference/gr_extract.md)
take it as a recipe override, and
[`gr_claims()`](https://elkronos.github.io/readgpt/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/readgpt/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/readgpt/reference/gr_synthesise.md)
take it as an argument, so
`effort = c(extract = "low", synthesise = "high")` keeps the per-chunk
extraction cheap and spends on the writing. A name that matches no
declared call stops with an error of class `hr_unknown_effort_key` that
lists the stems, so a misspelt `c(extrac = "low")` cannot send every
extraction at the provider’s default unnoticed.
[`?gr_read_spec`](https://elkronos.github.io/readgpt/reference/gr_read_spec.md)
lists every label and suggests a profile: low for the many per-chunk
calls, high for the few that judge.

## Paying once

[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
stores each successful response, keyed on the exact request. A repeat is
free and identical:

``` r

cache  <- gr_cache(file.path(tempdir(), "harnessr-runs-cache"))
cached <- gr_cache_client(cl, cache)

first  <- answer_document(gr_example(), "What was revenue?", "thorough",
                          client = cached, model = "priced-mock")
second <- answer_document(gr_example(), "What was revenue?", "thorough",
                          client = cached, model = "priced-mock")

gr_trace_summary(second$trace)[, c("calls", "cached", "tokens_in")]
#>   calls cached tokens_in
#> 1     1      1       607
gr_trace_cost(second$trace)[, c("calls", "paid_calls", "usd")]
#>   calls paid_calls usd
#> 1     1          0   0
```

`cached` counts the calls answered from the cache rather than the
network, so `calls - cached` is what the run paid for. The token counts
stay, since that is how big the prompts were, but a run with
`cached == calls` cost nothing, so do not hand its totals to
[`gr_estimate_cost()`](https://elkronos.github.io/readgpt/reference/gr_estimate_cost.md)
and call the result a bill.

The key covers everything that can change the reply: the messages, the
model, the resolved output cap, the temperature, the JSON schema, the
API shape and the base URL. It does not cover the API key, the headers,
the timeout or the retry policy, none of which the model sees. If a
header changes which model answers, give that client its own `base_url`
or `model` so the cache can tell them apart. Failures are never cached:
a rate limit or a refusal is a property of the moment, and storing one
would make a blip permanent. Neither is a reply cut off at its output
cap, or a structured reply that does not fit its schema, so running
again asks again.

The default directory is under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html), so a cache costs
nothing and vanishes with the session. For a long run, point it
somewhere real and the run becomes resumable. Restart after a crash and
every completed call is already paid for:

``` r

gr_options(cache_dir = tools::R_user_dir("harnessr", "cache"))
```

[`gr_cache_stats()`](https://elkronos.github.io/readgpt/reference/gr_cache_stats.md)
reports entries, bytes, hits, misses and writes, and
[`gr_cache_clear()`](https://elkronos.github.io/readgpt/reference/gr_cache_clear.md)
empties a cache. Set `write = FALSE` to run against a frozen cache, or
`read = FALSE` to refresh entries already stored.

### Repeated draws

At a temperature above zero a cache hit replays one sample instead of
drawing a new one. That is what makes a run reproducible, but it also
means N identical calls are one draw N times, and anything that compares
them sees perfect agreement. To keep N draws, give each call its own
`draw_index`. Above 0 it is part of the key, so draws 1 to N are N
entries, and a rerun gets the same N replies back in the same order:

``` r

n <- 0
sampler <- gr_mock_client(function(messages, params) { n <<- n + 1; paste("draw", n) })
sampler <- gr_cache_client(sampler, gr_cache(file.path(tempdir(), "harnessr-runs-draws")))

vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
vapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
```

The second line is answered from the cache. A call with the default
`draw_index = 0` keys as an ordinary call always has. Use a fresh
directory, or `read = FALSE`, when you want new replies for draws
already stored.

### Older caches

Entries are keyed by a SHA-256 hash under `harnessr-cache-v3`. Entries
written under the old key (`readgpt-cache-v2`, by readgpt 0.6.0 and
earlier builds of harnessr) are still read for calls with no draw index.
The first reply found that way in a session warns once, with class
`hr_legacy_key`, and
[`gr_cache_stats()`](https://elkronos.github.io/readgpt/reference/gr_cache_stats.md)
counts them as `legacy_hits`. Old entries are never rewritten, and
[`gr_cache_clear()`](https://elkronos.github.io/readgpt/reference/gr_cache_clear.md)
removes both. With `tools::R_user_dir("harnessr", "cache")` set, entries
readgpt kept in `tools::R_user_dir("readgpt", "cache")` are read too,
after it.

## Replaying a run

A trace records every prompt and every response. That makes it a
complete transcript of the only non-deterministic part of the pipeline,
so a trace plus the source document reproduces a run exactly, with no
key and no spend:

``` r

f <- file.path(tempdir(), "run.json")
gr_trace_save(first$trace, f)

replayed <- answer_document(gr_example(), "What was revenue?", "thorough",
                            client = gr_replay_client(f), model = "priced-mock")
identical(replayed$answer, first$answer)
#> [1] TRUE
```

Ship the trace next to the paper and a reader reproduces the run instead
of paying to approximate it. A trace file is also a re-runnable bug
report: it records exactly what went wrong.

A reply is matched on the key `harnessr-replay-v2`: the prompt messages,
the model the call asked for, its effort, its temperature once the
session default is filled in, the output cap asked for and its JSON
schema. Each step records it as `replay_key`. A prompt with no recorded
reply raises `gr_replay_miss` rather than inventing an answer. A miss
means the replay has diverged from the recording, and a result that
looks like the original but is not is worse than no replay at all. When
the prompt was recorded under other settings, the message names the
recorded temperature, cap or schema next to the ones asked for. Pass
`strict = FALSE` to run a partial recording anyway.

A replay that asks for more replies than were recorded is an error too,
of class `hr_replay_exhausted`. Draw k of a request is answered with the
reply recorded for that draw:

``` r

tr <- gr_trace()
n <- 0
sampler <- gr_mock_client(function(messages, params) { n <<- n + 1; paste("draw", n) })
invisible(lapply(1:3, function(k) gr_call(sampler, "Pick one.", draw_index = k, trace = tr)))

rp <- gr_replay_client(tr)
vapply(1:3, function(k) gr_call(rp, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
tryCatch(gr_call(rp, "Pick one.", draw_index = 4),
         hr_replay_exhausted = function(e) conditionMessage(e))
#> [1] "The recording holds no reply for draw 4 of this request; it holds 3 draw(s) of it. The replay is making more calls than the recorded run did, so it is not reproducing that run. Pass on_exhausted = \"flag\" to gr_replay_client() to repeat the last recorded reply instead, counted in $stats()$repeats."
```

`gr_replay_client(on_exhausted = "flag")` repeats the last recorded
reply instead, which is what every replay did before, and counts each
repeat in `$stats()$repeats`. A step recorded before `replay_key`
existed is looked up by the old key, `readgpt-replay-v1` (messages,
model and effort only), with one `hr_legacy_key` warning per recording
in a session.

### Embeddings in a replay

A trace records each embeddings request and what it cost, but not the
vectors that came back. A replay reproduces a run’s chunk ranking
exactly only when the recording used a deterministic embedder and the
replay uses the same one. Both conditions, not either: replaying an
API-embedded run with a deterministic local embedder would compute
vectors the original never saw while looking exact. Anything else warns
(`gr_replay_no_embeddings`) and falls back to lexical vectors. Those
place semantic cuts and rank chunks differently, so a replay of a run
that used embeddings (the `needle` recipe, the `retrieve` and
`iterative` readers, the `semantic` segmenter) usually sends prompts the
recording does not hold. A strict replay then stops with
`gr_replay_miss`, whose message names this cause.

Record a run you intend to publish with
`gr_options(embedder = "lexical")`, as this guide does, or with your own
embedder registered as `deterministic = TRUE`:

``` r

run <- answer_document(gr_example(), "What was revenue?", "needle",
                       client = cl, model = "priced-mock")
again <- answer_document(gr_example(), "What was revenue?", "needle",
                         client = gr_replay_client(run$trace), model = "priced-mock")
identical(again$chunks_used, run$chunks_used)
#> [1] TRUE
```

### Limits in a replay

A saved trace says whether a limit cut the run short (`budget_stop`,
`stop_reason`), and a replay under the limits it was recorded with stops
where it stopped. Replayed calls count against `max_calls` as they did
when recorded. When the spending limit stopped the recorded run, each
replayed call also counts what it cost when recorded against
`max_cost_usd`, in the trace’s `replayed_usd`, though nothing is spent;
for any other run it counts nothing, so a replay of an expensive run is
not stopped by the replaying session’s limit. A replay under a higher
limit that asks for a call past the recorded stop gets a
`gr_replay_miss` saying so.

Traces do not store the JSON schema a call requested, only a hash of it
in the step’s key. In a recording made before `replay_key` existed, two
calls that differ only by schema, temperature or output cap share a
reply.

## Comparing what recipes cost

[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md)
runs several recipes over one document on one trace. Its `summary` says
what each recipe cost: `calls`, `tokens_in`, `tokens_out` and `usd`,
priced at each model’s registered price, and `usd_estimated`, the share
of those dollars spent on requests whose token counts were estimated
locally. Give `correct`, strings a right answer contains or a function
of each answer, and it adds `correct` and `usd_per_correct`, the cost of
a right answer:

``` r

cmp <- gr_compare(gr_example(), "What was revenue?", c("fast", "precise", "thorough"),
                  client = cl, model = "priced-mock", correct = "45.2 million")
cmp$summary[, c("recipe", "reader", "calls", "usd", "usd_estimated",
                "correct", "usd_per_correct")]
#>     recipe     reader calls      usd usd_estimated correct usd_per_correct
#> 1     fast      stuff     1 0.001318             1    TRUE        0.001318
#> 2  precise       skim     3 0.001998             1    TRUE        0.001998
#> 3 thorough map_reduce     1 0.001318             1    TRUE        0.001318
```

`usd_per_correct` is `usd` for a right answer, `Inf` for a wrong one
that cost something, and `NA` when correctness is not known. A recipe a
limit stopped before it found anything is `NA`, not wrong. A recipe is
charged for a segmentation it shares with an earlier recipe, as it would
be run alone, so the column can add up to more than
`gr_trace_cost(cmp$trace)`.

## Models, prices and token counts

[`gr_models()`](https://elkronos.github.io/readgpt/reference/gr_models.md)
lists the context windows and prices harnessr knows, and
[`gr_model_limits()`](https://elkronos.github.io/readgpt/reference/gr_model_limits.md)
and
[`gr_model_info()`](https://elkronos.github.io/readgpt/reference/gr_model_info.md)
look one model up. Check them before a long run: an unregistered model
falls back to a conservative 128k window with no price, so its cost
shows as `NA` rather than a wrong figure.
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md)
fixes that in one line, and its `cached_input_usd` prices input the
provider served from its prompt cache at its own rate. A model with no
cached rate prices cached input as other input.

``` r

gr_register_model("priced-reasoner", context_window = 128000, max_output = 16000,
                  input_usd = 2, output_usd = 8, reasoning = TRUE)
gr_models()[gr_models()$id %in% c("priced-mock", "priced-reasoner"),
            c("id", "context_window", "reasoning", "input_usd_per_1m", "output_usd_per_1m")]
#>                 id context_window reasoning input_usd_per_1m output_usd_per_1m
#> 19     priced-mock         128000     FALSE                2                 8
#> 20 priced-reasoner         128000      TRUE                2                 8
```

[`gr_tokenizer()`](https://elkronos.github.io/readgpt/reference/gr_tokenizer.md)
says which counter is in use. The default, `"heuristic"`, needs nothing
installed. `gr_set_tokenizer("tiktoken")` switches to OpenAI’s own
tokenizer where the reticulate package and Python’s `tiktoken` are
installed: it counts in a model’s encoding when one is given and
otherwise, as the package’s budgets do, in the larger of `cl100k_base`
and `o200k_base`. For a model that is not OpenAI’s it is an estimate.
Without those packages it stops rather than falling back, because a
silent fallback would change every budget calculation.

[`gr_budget()`](https://elkronos.github.io/readgpt/reference/gr_budget.md)
does the context arithmetic for every request. It cannot return a
non-positive input budget; it raises an error that says what to change
instead.
[`?gr_options`](https://elkronos.github.io/readgpt/reference/gr_options.md)
documents every setting.

## Next

- [`vignette("readers")`](https://elkronos.github.io/readgpt/articles/readers.md):
  how each reader spends its calls, and choosing one.
- [`vignette("review")`](https://elkronos.github.io/readgpt/articles/review.md):
  limits and caching across many documents and a literature review.
- [`vignette("extending")`](https://elkronos.github.io/readgpt/articles/extending.md):
  declaring a reader’s calls and its `cost` function, so the check
  before the first request counts it correctly.
- [`?hr_governor`](https://elkronos.github.io/readgpt/reference/hr_governor.md),
  [`?gr_cache`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
  and
  [`?gr_replay_client`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md):
  the full rules.
