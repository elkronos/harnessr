# Cost, limits and reproducible runs

Every stage of harnessr except one is a pure function of its input.
Extraction, cleaning, segmentation, ranking and merging give the same
result every time. The model call is the exception. It is the only step
that costs money and the only one that can die halfway through a long
run. Above a temperature of zero, it is also the only step whose reply
can differ from one call to the next.

This guide covers how harnessr handles that step: the record each run
keeps, the limits every request is checked against before it is sent, a
cache that makes a repeat free, and a replay that reproduces a run from
its trace with no key and no spend.
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
introduces the package and its ideas.

## Setting up

The examples run offline.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
plays the part of the model, and `embedder = "lexical"` gives free,
deterministic word-overlap vectors in place of an embeddings endpoint.

A mock costs nothing, so the spending limits below would have nothing to
count. The examples give it a price instead.
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
registers the model id `"priced-mock"` at \$2 per million input tokens
and \$8 per million output tokens. Runs that name that model are priced
at those rates, and most runs below do.

``` r

library(harnessr)

hr_register_model("priced-mock", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)
old <- hr_options(verbose = FALSE, embedder = "lexical")

cl <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

## What a run records

The answer carries everything in this section, and `print(ans)` sums it
up: the cost, where the evidence came from and, for a partial answer,
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
`ans$notes` lists what: `dropped_chunks`, `failed_calls`,
`unread_pages`, `call_cap_reached`, `cost_cap_reached` and so on.
`ans$warnings` holds every warning raised while the document was read.

The trace holds every request the run made.
[`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)
gives the totals,
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md)
the bill by model, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) one row
per request with its stage, tokens, cost, time, prompt and reply:

``` r

hr_trace_summary(ans$trace)[, c("calls", "cached", "tokens_in", "tokens_out", "errors")]
#>   calls cached tokens_in tokens_out errors
#> 1    11      0      2444        143      0
hr_trace_cost(ans$trace)[, c("model", "calls", "paid_calls", "usd")]
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

The token totals measure the prompts and replies, so they show the size
of a run. The bill comes from
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md),
which counts only the calls that were issued. A call answered from a
cache or a recording spent nothing, however long its prompt. A model
with no registered price contributes `NA`, never 0, so no total can
leave one out unnoticed.

[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
prices a run before you make it:

``` r

hr_estimate_cost("priced-mock", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.272
```

### What each request records

Each request is one entry in `trace$steps`. Besides its label, prompt,
reply and the model requested, a step records:

- `params`, what the call asked for, and `params_sent`, the request as
  it went out with every default resolved: the model, `api`, `base_url`,
  the output cap sent, the temperature (`NA` when none was sent), the
  effort, the schema name, and SHA-256 hashes of the JSON schema and of
  any extra body fields. A small cap sent to a reasoning model is raised
  to 2048, and `params_sent` shows the raised cap.
- `served_model`, `response_id` and `fingerprint`, where the provider
  returns them. `model` keeps the model requested, and the step is
  priced and replayed by that model.
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
#>  $ started_utc: chr "2026-11-26T00:57:21.807Z"
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
[`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)
gives the share of requests whose counts were estimated as
`usage_estimated`, and [`print()`](https://rdrr.io/r/base/print.html) on
a trace reports that share when it is above zero.

`refine` and `hierarchical` also record the length of the state they
carry forward:

- Each `refine.draft` and `refine.revise` step has `state$tokens_in`,
  the length of the draft the request carried, and `state$tokens_out`,
  the length of the draft carried on from it (the old draft when the
  reply was unusable).
- Each `hier.summarise.L<k>` step has the length of the text it
  summarised and of the summary it returned.
- Each level adds a local `hier.state.L<k>` step with the number of
  summaries handed on and their combined length.

A draft that shrinks sharply in one revision shows up in these fields.

Each cut made to fit a limit writes a local `truncate` step. It holds
where the cut was made (`detail$where`), the token limit, and the tokens
before, kept and dropped. A `refine` or `hierarchical` answer also adds
up the tokens cut in `notes$tokens_truncated`, and printing the answer
reports how many tokens were cut to fit. Here a model with a 1,000-token
window makes `refine` cut its growing draft:

``` r

hr_register_model("small-window", context_window = 1000, max_output = 500,
                  input_usd = 2, output_usd = 8)
long_draft <- paste(rep("Revenue was 45.2 million dollars, and the draft says so.", 30),
                    collapse = " ")
cut <- answer_document(gr_example(), "What was revenue?", "fast",
                       client = hr_mock_client(function(messages, params) long_draft),
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

A cut can also be made at `refine.excerpt`, `hier.summaries`,
`preview.skim`, `preview.outline`, `<label>.input` for a finding cut to
fit a merge, `<label>.giveup` for the capped findings a failed merge
returns, `segment.contextual.header`, `segment.contextual.document`,
`screen.opening`, `synthesise.gaps` and `embed.input`.

A trace also records who the run is for and the settings it ran under.
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
takes `system`, `owner`, `run_by`, `purpose` and `approved_by`.
`hr_options(actor = list(...))` sets them for every trace, and a field
you set in neither place is `NA`. `trace$config` is a snapshot of the
options in force when the trace was made, plus the R version. It leaves
out the values of `api_headers`, since they can hold credentials.

``` r

tr <- hr_trace(owner = "finance team", run_by = "ana", purpose = "Q3 check")
tr
#> <gr_trace run_20261126005722.159_7fd1f0>  0 steps, 0 model calls, 0 in / 0 out tokens, 0 error(s)
#>   cost: no cost recorded
#>   actor: owner = finance team, run_by = ana, purpose = Q3 check 
#>   started: 2026-11-26T00:57:22.159Z
names(tr$config)
#> [1] "options"   "r_version"
```

`as_json(ans)` writes the answer with every prompt and response of its
run.
[`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md)
writes the trace alone, and a replay reads that file.

### Errors and warnings by class

Errors are classed, so you can catch a specific failure:

- `gr_auth_error`, `gr_file_not_found`, `gr_empty_document`,
  `gr_unsupported_format`, `gr_overflow`, `gr_call_cap`, `gr_cost_cap`,
  `gr_budget_error`, `gr_unknown_model`, `gr_unknown_override`,
  `gr_no_recipes`, `gr_bad_ensemble` and `gr_missing_dep`.
- `gr_bad_setting` for a setting outside its choices
  ([`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)).
- `hr_unknown_effort_key` and `hr_unpriced_model`, both covered below.
- `hr_dim_mismatch` when two vectors of different lengths are compared,
  such as a lexical fallback vector against an API embedding.

Degradations are classed warnings:

- `gr_segment_fallback`, `gr_embed_fallback`, `gr_rerank_degraded`,
  `gr_iterative_degraded`, `gr_ensemble_degenerate`,
  `gr_duplicate_recipe` and `gr_ocr_unavailable`.
- `gr_clamped` with `hr_param_clamped` for a parameter moved to its
  nearest bound
  ([`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)).
- `gr_parallel_share` for a parallel item whose share refused a later
  request (below).
- `gr_bad_correct` for a
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  `correct` function that fails (below).
- `gr_unclear_dropped` when
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  leaves unclear screening records out
  ([`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)).

In an interactive session, a long read keeps one progress line up to
date with the number of chunks read and the spend so far.
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
also reports the spend so far before each document.

## Limits

Two limits are on by default: a run may spend \$5 and make 400 calls.

``` r

unlist(hr_options()[c("max_cost_usd", "max_calls")])
#> max_cost_usd    max_calls 
#>            5          400
```

They are checked at two points. Before the first request, a run is
refused, with a classed error that names the option to change, when:

- it would need more calls than `max_calls`, or
- its reader sends every chunk, and sending them would already cost more
  than `max_cost_usd`.

Here `map_reduce` over five chunks needs six calls:

``` r

chunks <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
spec <- gr_read_spec(reader = "map_reduce", model = "priced-mock")

tryCatch(
  gr_read(chunks, "What was revenue?", cl, spec,
          trace = hr_trace(governor = hr_governor(max_calls = 3))),
  gr_call_cap = function(e) conditionMessage(e))
#> [1] "Reader 'map_reduce' over 5 chunks would need about 6 more model calls (0 already made this run), above the 3-call cap. Use a larger `max_tokens` when segmenting (fewer chunks), pick a top-k reader, or raise hr_options(max_calls = ...)."
```

### Every request is checked before it is sent

The second check runs on every request before it goes out. It compares
the limit with what the run has spent plus the most the request could
cost: its prompt at the input price and its output cap at the output
price. The prompt count includes the JSON schema and extra body fields
the request carries and a few tokens of framing per message, since the
provider bills for all of that. That count is then raised by
`safety_margin`. A request that could take the run past a limit is not
sent, so a run ends at or under its limit rather than one request over
it.

Under a limit of one cent, the five chunk requests below go out and the
merge does not. The merge’s reply cap is 1500 tokens, which at \$8 per
million could cost more than the run has left, so the answer comes back
partial:

``` r

tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.01))
capped <- gr_read(chunks, "What was revenue?", cl, spec, trace = tr)
capped$partial
#> [1] TRUE
data.frame(calls = tr$calls, spent_usd = tr$spent_usd, stop_reason = tr$stop_reason)
#>   calls spent_usd stop_reason
#> 1     5  0.002428        cost
tr$refusals[[1]]$message
#> [1] "spending limit reached: the 'reduce' request could cost up to $0.01 (up to 232 prompt tokens, and 1500 reply tokens at its cap), and the run has spent $0.0024 of its $0.01 limit, so it was not sent; raise hr_options(max_cost_usd =) or ask for a smaller max_output"
```

The bound assumes two things harnessr cannot see. The provider must stop
each reply at its cap, and its count of the prompt must fall within
`safety_margin` of the local tokenizer’s.

A run that leaves its output caps at the model’s limit stops while it
still has headroom that a smaller cap would have used. With the merge’s
reply held to 500 tokens, the same run fits:

``` r

tr <- hr_trace(governor = hr_governor(max_cost_usd = 0.01))
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

A refused request is not a call, and it adds nothing to the trace’s
calls, steps or spend.
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
first signals a condition of class `hr_budget_refused`, which you can
catch to stop the run there. Otherwise it returns the request as a
failed result with `refused = TRUE` and an error naming the limit. The
trace lists the request in `refusals`, sets `budget_stop` and names the
limit in `stop_reason`: `"calls"`, `"cost"`, `"tokens"`, `"output"`,
`"model"` or `"unpriced"`. Readers and review stages mark the answer or
section partial and do not count the refused request as failed.

The check sits on the call path itself, so it covers every request:
readers, judges, the ensemble’s adjudication, conflict resolution in
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
context and proposition segmentation, claims, outlines, screening,
synthesis, embeddings, and any request a custom reader or a script makes
with
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md).

### A governor for one run

[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
holds a run’s six limits. Attach one with `hr_trace(governor = )`. A
trace without a governor reads the limits from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
at each check.

| limit | what it holds | default |
|----|----|----|
| `max_calls` | requests the run may make, cache hits and embeddings included | 400 |
| `max_cost_usd` | what the run may spend, in USD | 5 |
| `max_tokens_total` | tokens of every prompt, reply and embedded text | off |
| `max_output_tokens` | the largest output cap one request may carry; a request with a larger one is refused, not cut down | off |
| `allowed_models` | the model ids the run may call, text and embedding models alike | any |
| `allow_unpriced` | whether a model with no registered price may be called under a spending limit | `FALSE` |

Each limit is also an option of the same name:
`hr_options(max_tokens_total = 50000)` sets it for every run, and each
trace’s config snapshot lists all six. `NULL` or `Inf` removes a limit.
A limit that cannot be compared is refused as soon as you set it:

``` r

tryCatch(hr_options(max_cost_usd = NA), error = function(e) conditionMessage(e))
#> [1] "hr_options(max_cost_usd = ) must be a single number or NULL, not NA. A limit that cannot be compared is not a limit, so this is refused here rather than ignored later."
```

A request to a model the run may not call is refused the same way as one
over budget:

``` r

tr <- hr_trace(governor = hr_governor(allowed_models = "gpt-4o"))
res <- hr_call(cl, "What was revenue?", model = "priced-mock", trace = tr)
data.frame(refused = res$refused, stop_reason = tr$stop_reason)
#>   refused stop_reason
#> 1    TRUE       model
```

[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
keep a trace of their own and fold it into the trace you pass them.
Their requests are held to that trace’s governor, less what it has
already spent and the tokens it has used. `max_calls` stays a limit per
document and per stage.
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
holds the whole comparison to `max_cost_usd` and `max_tokens_total`.

### Models with no price

A language model with no registered price adds nothing to the spend, so
no spending limit could stop it. With `max_cost_usd` set, a request to
such a model is refused with a condition of class `hr_unpriced_model`,
and
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
stops before its first request.
[`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md)
wraps an R function as a paying client, which lets this example show the
refusal offline:

``` r

hr_register_model("unpriced-model", context_window = 128000, max_output = 4096)
backend <- hr_backend_client(function(messages, params) "Revenue was 45.2 million dollars.")

res <- hr_call(backend, "What was revenue?", model = "unpriced-model")
res$refused
#> [1] TRUE
res$error
#> [1] "unpriced model: 'unpriced-model' has no registered price, so what the 'call' request costs cannot be held to the $5 spending limit, and it was not sent. Register its prices with hr_register_model(input_usd =, output_usd =), or send it unpriced with hr_options(allow_unpriced = TRUE) or hr_governor(allow_unpriced = TRUE)"
```

Register the model’s prices with
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md),
or set `hr_options(allow_unpriced = TRUE)`. Under `allow_unpriced`, its
requests are sent, still count against `max_calls` and
`max_tokens_total`, and are priced `NA` in the trace. `max_tokens_total`
is then the limit that still bounds the run.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
and replays are never refused for this, and neither are embedding models
with no price.

An
[`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
is priced as the model its ellmer object was built with, whatever a
recipe names, so one built on a model with no registered price is
refused too. Register that model at your provider’s current prices, or
let a local model run unpriced;
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
shows both.

Through ellmer, a `temperature` in a read spec is ignored with a
warning, because sampling parameters belong to the ellmer object.
Embeddings come from a function you pass as `embed =`. Without one,
`retrieve` and the `semantic` segmenter fall back to lexical vectors and
warn.

### Parallel batches

With `parallel = TRUE`, per-chunk requests go out in batches that cannot
be stopped part way. The limits apply to them like this:

- Each worker’s items are held to an equal share of the calls and
  dollars the run has left.
- An item that its worker’s share refuses before it is sent runs again
  in the calling process, against the run’s own limits.
- A batch the run’s limits cannot cover runs in the calling process
  instead of being split across workers.
- Batch items make one request each. An item that made more, and had a
  later one refused by its share, warns with class `gr_parallel_share`,
  and the run is not marked as stopped.

### How much the model reasons

`effort` sets how much a reasoning model reasons on each call, stage by
stage.
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
explains how effort is billed, which models it is sent to, and the label
each stage’s calls carry.

In a review, the same vector goes to each stage.
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
and
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
take it as a recipe override;
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
take it as an argument. With
`effort = c(extract = "low", synthesise = "high")`, the per-chunk
extraction stays cheap and the spending goes to the writing.

A name that matches no declared call stops with an error of class
`hr_unknown_effort_key` that lists the stems. A misspelt
`c(extrac = "low")` therefore cannot send every extraction at the
provider’s default unnoticed.
[`?gr_read_spec`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
lists every label and suggests a profile: low for the many per-chunk
calls, high for the few that judge.

## Paying once

[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
stores each successful response, keyed on the exact request. A repeat is
free and identical:

``` r

cache  <- hr_cache(file.path(tempdir(), "harnessr-runs-cache"))
cached <- hr_cache_client(cl, cache)

first  <- answer_document(gr_example(), "What was revenue?", "thorough",
                          client = cached, model = "priced-mock")
second <- answer_document(gr_example(), "What was revenue?", "thorough",
                          client = cached, model = "priced-mock")

hr_trace_summary(second$trace)[, c("calls", "cached", "tokens_in")]
#>   calls cached tokens_in
#> 1     1      1       607
hr_trace_cost(second$trace)[, c("calls", "paid_calls", "usd")]
#>   calls paid_calls usd
#> 1     1          0   0
```

`cached` counts the calls answered from the cache instead of the
network, so `calls - cached` is what the run paid for. The token counts
stay, since they show how big the prompts were. A run with
`cached == calls` cost nothing, though, so do not pass its totals to
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
and call the result a bill.

The key covers everything that can change the reply: the messages, the
model, the resolved output cap, the temperature, the reasoning effort,
the JSON schema, any extra body fields, the API shape and the base URL.
It leaves out the API key, the headers, the timeout and the retry
policy, since the model sees none of them. If a header changes which
model answers, give that client its own `base_url` or `model` so the
cache can tell the two apart.

These replies are never cached, so running again asks again:

- failures: a rate limit or a refusal belongs to the moment, and storing
  one would make a blip permanent;
- a reply cut off at its output cap;
- a structured reply that does not fit its schema.

The default directory is under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html), so a cache costs
nothing and vanishes with the session. For a long run, point it at a
lasting directory to make the run resumable. After a crash, a restart
gets every completed call from the cache instead of paying for it again:

``` r

hr_options(cache_dir = tools::R_user_dir("harnessr", "cache"))
```

[`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)
reports entries, bytes, hits, misses and writes, and
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
empties a cache. Set `write = FALSE` to run against a frozen cache, or
`read = FALSE` to refresh entries already stored.

### Repeated draws

At a temperature above zero, a cache hit replays one sample instead of
drawing a new one. That makes a run reproducible. It also turns N
identical calls into one draw repeated N times, so any check that
compares them sees perfect agreement. To keep N draws, give each call
its own `draw_index`. An index above 0 is part of the key, so draws 1 to
N are N entries, and a rerun gets the same N replies back in the same
order:

``` r

n <- 0
sampler <- hr_mock_client(function(messages, params) { n <<- n + 1; paste("draw", n) })
sampler <- hr_cache_client(sampler, hr_cache(file.path(tempdir(), "harnessr-runs-draws")))

vapply(1:3, function(k) hr_call(sampler, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
vapply(1:3, function(k) hr_call(sampler, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
```

The cache answers the second line. A call with the default
`draw_index = 0` keys as an ordinary call always has. For new replies to
draws already stored, use a fresh directory or `read = FALSE`.

### Older caches

Entries are keyed by a SHA-256 hash under `harnessr-cache-v3`. Calls
with no draw index still read entries written under the old key,
`readgpt-cache-v2`, by readgpt 0.6.0 and earlier builds of harnessr. The
first reply found that way in a session warns once, with class
`hr_legacy_key`, and
[`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)
counts these replies as `legacy_hits`. Old entries are never rewritten,
and
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
removes both kinds. With `tools::R_user_dir("harnessr", "cache")` set,
entries readgpt kept in `tools::R_user_dir("readgpt", "cache")` are read
too, after it.

## Replaying a run

A trace records every prompt and every response, which makes it a
complete transcript of the only non-deterministic part of the pipeline.
A trace plus the source document reproduces a run exactly, with no key
and no spend:

``` r

f <- file.path(tempdir(), "run.json")
hr_trace_save(first$trace, f)

replayed <- answer_document(gr_example(), "What was revenue?", "thorough",
                            client = hr_replay_client(f), model = "priced-mock")
identical(replayed$answer, first$answer)
#> [1] TRUE
```

Publish the trace with the paper, and a reader can reproduce the run
instead of paying to approximate it. A trace file also makes a bug
report you can run again, since it records exactly what went wrong.

A replay matches each reply on the key `harnessr-replay-v2`, which each
step records as `replay_key`. The key covers:

- the prompt messages;
- the model the call asked for, and its effort;
- its temperature, once the session default is filled in;
- the output cap asked for, and its JSON schema.

A prompt with no recorded reply raises `gr_replay_miss` rather than
getting an invented answer. A miss means the replay has diverged from
the recording, and a result that looks like the original but differs
from it is worse than no replay at all. If the prompt was recorded under
other settings, the error message names the recorded temperature, cap or
schema next to the ones asked for. Pass `strict = FALSE` to run a
partial recording anyway.

Asking a replay for more replies than were recorded is an error too, of
class `hr_replay_exhausted`. Draw k of a request gets the reply recorded
for that draw:

``` r

tr <- hr_trace()
n <- 0
sampler <- hr_mock_client(function(messages, params) { n <<- n + 1; paste("draw", n) })
invisible(lapply(1:3, function(k) hr_call(sampler, "Pick one.", draw_index = k, trace = tr)))

rp <- hr_replay_client(tr)
vapply(1:3, function(k) hr_call(rp, "Pick one.", draw_index = k)$text, "")
#> [1] "draw 1" "draw 2" "draw 3"
tryCatch(hr_call(rp, "Pick one.", draw_index = 4),
         hr_replay_exhausted = function(e) conditionMessage(e))
#> [1] "The recording holds no reply for draw 4 of this request; it holds 3 draw(s) of it. The replay is making more calls than the recorded run did, so it is not reproducing that run. Pass on_exhausted = \"flag\" to hr_replay_client() to repeat the last recorded reply instead, counted in $stats()$repeats."
```

`hr_replay_client(on_exhausted = "flag")` repeats the last recorded
reply instead, as every replay did before, and counts each repeat in
`$stats()$repeats`. A step recorded before `replay_key` existed is
looked up by the old key, `readgpt-replay-v1`, which covers messages,
model and effort only. Such a lookup warns with `hr_legacy_key` once per
recording in a session.

### Embeddings in a replay

A trace records each embeddings request and its cost. It does not keep
the vectors that came back. A replay reproduces a run’s chunk ranking
exactly only when the recording used a deterministic embedder and the
replay uses the same one. Both conditions must hold: a replay of an
API-embedded run with a deterministic local embedder would compute
vectors the original never saw, and the result would look exact.

In any other case the replay warns (`gr_replay_no_embeddings`) and falls
back to lexical vectors. Lexical vectors place semantic cuts and rank
chunks differently, so a replay of a run that used embeddings (the
`needle` recipe, the `retrieve` and `iterative` readers, the `semantic`
segmenter) usually sends prompts the recording does not hold. A strict
replay then stops with `gr_replay_miss`, and the error message names
this cause.

Record a run you intend to publish with
`hr_options(embedder = "lexical")`, as this guide does, or with your own
embedder registered as `deterministic = TRUE`:

``` r

run <- answer_document(gr_example(), "What was revenue?", "needle",
                       client = cl, model = "priced-mock")
again <- answer_document(gr_example(), "What was revenue?", "needle",
                         client = hr_replay_client(run$trace), model = "priced-mock")
identical(again$chunks_used, run$chunks_used)
#> [1] TRUE
```

### Limits in a replay

A saved trace records whether a limit cut the run short, in
`budget_stop` and `stop_reason`. A replay under the limits the run was
recorded with stops at the same point. Replayed calls count against
`max_calls` as they did when recorded.

Spend depends on how the recorded run ended. If the spending limit
stopped it, each replayed call counts its recorded cost against
`max_cost_usd`, in the trace’s `replayed_usd`, though nothing is spent.
For any other run, replayed calls count nothing against it, so the
replaying session’s limit does not stop a replay of an expensive run. A
replay under a higher limit that asks for a call past the recorded stop
gets a `gr_replay_miss` that says so.

A trace keeps only a hash of the JSON schema a call requested, in the
step’s key. In a recording made before `replay_key` existed, two calls
that differ only by schema, temperature or output cap share a reply.

## Comparing what recipes cost

[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
runs several recipes over one document on one trace. Its `summary` has a
row per recipe with what the recipe cost:

- `calls`, `tokens_in` and `tokens_out`;
- `usd`, priced at each model’s registered price;
- `usd_estimated`, the share of those dollars spent on requests whose
  token counts were estimated locally.

Pass `correct`, either strings a right answer contains or a function of
each answer, and the summary gains `correct` and `usd_per_correct`, the
cost of a right answer:

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
that cost something, and `NA` when correctness is not known. A recipe
that a limit stopped before it found anything is `NA`, not wrong. Each
recipe is charged for a segmentation it shares with an earlier recipe,
as if it ran alone, so the `usd` column can add up to more than
`hr_trace_cost(cmp$trace)`.

## Models, prices and token counts

[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
lists the context windows and prices harnessr knows;
[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md)
and
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
look up one model. Check them before a long run. An unregistered model
falls back to a conservative 128k window with no price, so its cost
shows as `NA` rather than a wrong figure. One
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
call fixes that. Its `cached_input_usd` sets a separate rate for input
the provider served from its prompt cache. Without that rate, cached
input is priced as other input.

``` r

hr_register_model("priced-reasoner", context_window = 128000, max_output = 16000,
                  input_usd = 2, output_usd = 8, reasoning = TRUE)
hr_models()[hr_models()$id %in% c("priced-mock", "priced-reasoner"),
            c("id", "context_window", "reasoning", "input_usd_per_1m", "output_usd_per_1m")]
#>                 id context_window reasoning input_usd_per_1m output_usd_per_1m
#> 19     priced-mock         128000     FALSE                2                 8
#> 20 priced-reasoner         128000      TRUE                2                 8
```

[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md)
reports which counter is in use. The default, `"heuristic"`, needs
nothing installed. `hr_set_tokenizer("tiktoken")` switches to OpenAI’s
own tokenizer where the reticulate package and Python’s `tiktoken` are
installed. It counts in a model’s encoding when one is given. Otherwise
it counts, as the package’s budgets do, in the larger of `cl100k_base`
and `o200k_base`. For a model that is not OpenAI’s, the count is an
estimate. Without those packages, `hr_set_tokenizer("tiktoken")` stops
rather than falling back, because a silent fallback would change every
budget calculation.

[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
does the context arithmetic for every request. It cannot return a
non-positive input budget: in that case it raises an error that says
what to change.
[`?hr_options`](https://elkronos.github.io/harnessr/reference/hr_options.md)
documents every setting.

## Choosing the settings

Three walkthroughs cover the settings that hold a run in: the limits
every run has, the governor a benchmark or a batch shares, and effort
that rises only when a stage needs it. Each gives what the setting
controls and what it trades off, the signs in your results that point to
changing it, where its default came from, and how to test a change.
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
lists every option with its default.

### The global limits

**What they control.** `max_cost_usd` and `max_calls` hold every run,
and `max_tokens_total`, `max_output_tokens`, `allowed_models` and
`allow_unpriced` hold it further when set (see “Limits” above). A limit
set too low ends runs early, with partial answers. One set too high lets
a mistake run up its full cost, such as a reader that sends every chunk
of a long document at a small chunk size.

**Signs they need changing.** Any of these means a limit stopped the
run:

- an answer with `partial = TRUE` and `cost_cap_reached` or
  `call_cap_reached` in its notes;
- a trace whose `stop_reason` is set;
- an error of class `gr_call_cap` or `gr_cost_cap` before the first
  request.

Raise the limit only after checking that the run should cost that much.
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
and
[`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)
tell you before anything is sent. If a run spends far less than its
limit every time, you can lower the limit to catch the run that does
not. A refusal with `stop_reason = "output"` means a request’s output
cap was larger than `max_output_tokens` allows. Lower the reader’s caps
(`max_answer_tokens`, `max_chunk_tokens`) to fit it.

**Where the defaults came from.** \$5 and 400 calls are limits for one
read, chosen so a mistake costs little. No measurement backs them, and
`gr_settings_table("options")` declares no evidence for them. The other
limits are off by default. `allow_unpriced` is `FALSE` because a
spending limit cannot hold a request whose cost it cannot see.

**How to test them.** A limit belongs to the run, not to an arm, so a
sweep can only test which settings fit under it. A reader’s output caps
decide how much of the limit each request reserves, so sweep the merge’s
cap and hold each arm’s five runs to the same \$0.02:

``` r

qa <- gr_qa_reference(questions = c(revenue = "What was revenue in 2024?"),
                      documents = gr_example(), answers = list("45.2 million"),
                      split = "dev")
arms <- hr_sweep(gr_arm("thorough", list(method = "sentence", max_tokens = 150,
                                         overlap_tokens = 0, model = "priced-mock")),
                 list(max_answer_tokens = c(1500, 500)))
vapply(arms, function(arm) {
  b <- suppressWarnings(hr_benchmark(arm, qa, runs = 5, client = cl, split = "dev",
                                     scorer = gr_scorer_answer(),
                                     governor = hr_governor(max_cost_usd = 0.02)))
  c(stopped = sum(b$failure_kind %in% "budget_stop"), usd = sum(b$usd))
}, numeric(2))
#>         thorough:max_answer_tokens=1500 thorough:max_answer_tokens=500
#> stopped                        3.000000                        0.00000
#> usd                            0.013344                        0.01485
```

With the merge’s reply capped at 1500 tokens, each merge reserves
\$0.012 of output, so 3 of the 5 runs were stopped before their merge.
Capped at 500, all five finished within the same limit.
[`suppressWarnings()`](https://rdrr.io/r/base/warning.html) hides the
`hr_budget_stopped` warning each benchmark gives; read it in your own
runs.

### The governor of a benchmark or a batch

**What it controls.**
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
holds limits for more than one run. `hr_benchmark(governor = )` holds
the whole benchmark to it, and each run to what the runs before it left.
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
and the review stages hold their documents to the governor of the trace
you pass them. A governor sized too small refuses the last arms or
documents. One sized too large lets a mistake in one arm spend the
budget meant for all of them.

**Signs it needs changing.**
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
warns with class `hr_budget_stopped`, naming how many runs were stopped
and by which limit, and the stopped runs have
`failure_kind = "budget_stop"`. If arms late in the list stopped more
than early ones, suspect a governor too small for the whole benchmark
rather than an arm that costs too much.

**Where the default came from.** `governor = NULL` takes the limits from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
when the benchmark starts. Those are set for one read (400 calls), and a
benchmark of two arms on 300 items for 5 runs needs several thousand.
Size the governor for the benchmark: arms x items x runs x requests per
run.

**How to test it.** Count the requests one run makes, multiply, and
check how much of the governor was used:

``` r

per_run <- 6  # map_reduce over five chunks: five chunk requests and a merge
needed <- length(arms) * 1 * 5 * per_run
bench <- hr_benchmark(arms, qa, runs = 5, client = cl, split = "dev",
                      scorer = gr_scorer_answer(),
                      governor = hr_governor(max_calls = needed, max_cost_usd = 1))
c(allowed = needed, used = attr(bench, "trace")$calls,
  stopped = sum(bench$failure_kind %in% "budget_stop"))
#> allowed    used stopped 
#>      60      60       0
```

[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
sizes a governor this way for every benchmark it runs.

### Effort that rises when needed: `effort_mode`

**What it controls.** With `effort_mode = "escalate"`, a read starts
every stage at its `effort` (`"low"` when `effort` is unset). It sends
the next stage at `"high"` when one of these went wrong in the stage
before:

- a cut;
- a reply stopped at its output cap;
- a reply that is not the JSON asked for;
- `NOT_IN_DOCUMENT` from every request of the stage;
- a quotation `iterative` could not verify;
- `ensemble` members that disagree.

Effort changes only at a stage boundary, at most once a read, and the
stage after a raised one goes back to the base effort. The setting
trades the cost of reasoning at a high effort on every request against
the cost of a wrong answer where low effort was not enough. A raise
costs nothing but the raised stage’s reasoning.

**Signs it needs changing.** Look for a fixed `"high"` effort whose bill
is mostly reasoning on requests that a low effort answers as well, or
for answers at a fixed `"low"` that come back cut off, unparsed or not
found. The trace records each raise as an `"effort.escalate"` step.
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)
shows which trigger fired and whether the raised stage fired it again.

**Where the default came from.** `"static"` sends the effort `effort`
names, as harnessr did before the setting existed; the settings table
marks it `untested`. No one has compared escalation with a fixed effort
here, and
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
makes that comparison.

**How to test it.** Here `refine` reads the report with a stand-in
reasoning model that, at low effort, finds nothing in the first chunk,
where `refine` drafts its answer:

``` r

hr_register_model("priced-reasoner", context_window = 128000, max_output = 8192,
                  input_usd = 1, output_usd = 4, reasoning = TRUE)
thinks <- hr_mock_client(function(messages, params) {
  if (identical(params$effort, "low") &&
      startsWith(messages[[2]]$content, "<excerpts>")) {
    return("NOT_IN_DOCUMENT")
  }
  "Revenue was 45.2 million dollars."
})
efforts <- hr_sweep(function(effort) {
  gr_arm("thorough", list(method = "sentence", max_tokens = 150, overlap_tokens = 0,
                          model = "priced-reasoner", reader = "refine",
                          effort = if (effort != "escalate") effort,
                          effort_mode = if (effort == "escalate") "escalate" else "static"))
}, list(effort = c("low", "high", "escalate")))
eb <- hr_benchmark(efforts, qa, runs = 5, client = thinks, split = "dev",
                   scorer = gr_scorer_answer(),
                   governor = hr_governor(max_calls = 200, max_cost_usd = 1))
sent <- do.call(rbind, lapply(seq_len(nrow(eb)), function(i) {
  d <- as.data.frame(attr(eb, "traces")[[eb$ledger_id[i]]])
  d <- d[!is.na(d$effort), ]
  data.frame(arm = eb$arm[i], stage = d$stage, effort = d$effort)
}))
table(sent$arm, paste(sent$stage, sent$effort))
#>                           
#>                            refine.draft high refine.draft low
#>   thorough:effort=escalate                 0                5
#>   thorough:effort=high                     5                0
#>   thorough:effort=low                      0                5
#>                           
#>                            refine.revise high refine.revise low
#>   thorough:effort=escalate                 20                 0
#>   thorough:effort=high                     20                 0
#>   thorough:effort=low                       0                20
hr_effort_log(attr(eb, "traces")[[eb$ledger_id[eb$arm == "thorough:effort=escalate"][1]]])
#>          after         stage        triggers   to calls resolved
#> 1 refine.draft refine.revise not_in_document high     4     TRUE
```

At `"low"` every request went out low, and at `"high"` every one went
out high. Under `"escalate"` the draft went out low and found nothing.
That raised the four revisions after it to high, and the log shows that
the raise resolved the trigger: the revisions found the figure.

Four of the five requests of each run went out raised here, because the
draft is one request. On a reader whose first stage is many requests
(`map_reduce`’s chunks), the raised stage is the smaller share.

[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
reads a benchmark of such arms with the non-inferiority test of
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md).
That test needs a reference with a test split and enough items and runs
for intervals, so run the check on your own benchmark:

``` r

chk <- hr_effort_check(bench, candidate = "thorough:effort=escalate", margin = 0.05)
chk$contrasts[, c("reference", "estimate", "lower", "verdict")]
chk$cost
```

Register the margin with
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
before the benchmark runs and pass it as `registration`; without one,
the result is marked post hoc.

## Next

- [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md):
  how each reader spends its calls, and choosing one.
- [`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md):
  limits and caching across many documents and a literature review.
- [`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md):
  declaring a reader’s calls and its `cost` function, so the check
  before the first request counts it correctly.
- [`?hr_governor`](https://elkronos.github.io/harnessr/reference/hr_governor.md),
  [`?hr_cache`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
  and
  [`?hr_replay_client`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md):
  the full rules.
