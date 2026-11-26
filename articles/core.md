# The core: calls, clients and results

harnessr has two layers. The core (the `hr_` functions) sends requests
to a model and keeps the record of them. The document layer (the `gr_`
functions) reads files, cuts them into chunks and asks questions of
them, and every request it makes goes through the core. You can use the
core on its own, with no document at all: to send a prompt, check the
reply, count what it cost and reproduce it later.

The sections below start from one call and work outwards: what a call
returns, the clients that answer it, the trace that records it,
structured replies, checks on a reply, signals, and the classes of the
errors and warnings. Every example runs offline with no API key. The
calls that would reach a real provider are shown but not run.

## Setting up

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
```

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
sets options for the session and returns the values it replaced, so the
last chunk of this guide can put them back with `hr_options(old)`.
`verbose = FALSE` stops the line each document stage prints; the calls
below print nothing either way.

## A first call

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
sends one request and returns one result. It needs a client, the object
that answers, and the prompt.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
builds a client from an R function, so you can practise without a key:

``` r

cl <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
res <- hr_call(cl, "What was revenue in 2024?")
res
#> <gr_result> ok=TRUE model=mock-model in=12 out=13
#> Revenue was 45.2 million dollars.
```

The first line of the printed result says the call succeeded
(`ok=TRUE`), which model it asked for, and the size of the prompt and
the reply in tokens. The second line is the reply. A mock answers to the
model id `"mock-model"` unless the call names another one.

The prompt can be one string, as here, which
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
sends as a single user message. For more than one message, pass a list
of `list(role =, content =)`. The roles are `"system"`, `"developer"`,
`"user"` and `"assistant"`:

``` r

msgs <- list(
  list(role = "system", content = "Answer in one sentence."),
  list(role = "user", content = "What was revenue in 2024?"))
hr_call(cl, msgs)$text
#> [1] "Revenue was 45.2 million dollars."
```

Before it sends anything,
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
does three things:

- It counts the prompt’s tokens with the session’s tokenizer.
- It sets the reply’s cap, `max_output`: the value you give, or the
  model’s own output limit, held to that limit and to the room the
  model’s context window leaves after the prompt.
- It checks the request against the run’s limits (see [Limits and
  refusals](#refusals) below). A request that would pass one is not
  sent.

Each call stands alone. harnessr keeps no conversation between calls, so
a second call sees only the messages you pass it. To continue a
conversation, pass the earlier turns again as `"assistant"` and `"user"`
messages.

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
has a few more arguments, each covered further down: `trace` and `label`
record the call, `schema` and `schema_name` ask for a structured reply,
`temperature` sets the sampling temperature, `effort` the reasoning
effort, and `draw_index` marks repeated draws of one request. Named
arguments it does not know go into the request body of an
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
as extra fields; a mock or a backend handler never sees them.

`effort` reaches only a model the registry lists as a reasoning model.
For any other model the call goes out with no effort, and no warning:

``` r

effort_seen <- hr_mock_client(function(messages, params) {
  paste("effort:", if (is.null(params$effort)) "none" else params$effort)
})
hr_call(effort_seen, "What was revenue?", model = "gpt-5.6-luna", effort = "low")$text
#> [1] "effort: low"
hr_call(effort_seen, "What was revenue?", model = "gpt-4o", effort = "low")$text
#> [1] "effort: none"
```

[`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md)
covers effort in full: the levels, an effort per stage, what it costs,
and effort that rises only when a stage goes wrong.

## What a result holds

A call returns a `gr_result`, a list with the same fields every time,
whichever client answered:

``` r

str(unclass(res), give.attr = FALSE)
#> List of 14
#>  $ ok           : logi TRUE
#>  $ text         : chr "Revenue was 45.2 million dollars."
#>  $ error        : NULL
#>  $ status       : int NA
#>  $ usage        :List of 3
#>   ..$ input     : int 12
#>   ..$ output    : int 13
#>   ..$ provenance: chr "estimated"
#>  $ model        : chr "mock-model"
#>  $ finish_reason: chr NA
#>  $ retryable    : logi FALSE
#>  $ raw          : NULL
#>  $ cached       : logi FALSE
#>  $ served_model : chr NA
#>  $ response_id  : chr NA
#>  $ fingerprint  : chr NA
#>  $ attempts     : int 1
```

| Field | What it holds |
|----|----|
| `ok` | `TRUE` when a usable reply came back. `FALSE` for a failed request, an error from the provider, and a reply with no text. |
| `text` | The reply, one string. `""` when `ok` is `FALSE`, never `NULL`. Line breaks are kept. |
| `error` | What went wrong, or `NULL`. |
| `status` | The HTTP status. `NA` when the client gave none, as a mock or a handler usually does, and `0` when no request was sent (a refusal, a prompt that leaves no room for a reply). |
| `usage` | `input` and `output` tokens, and `provenance`: `"reported"` by the provider, `"counted"` here with the `"tiktoken"` tokenizer or as a zero for a request that failed or was not sent, or `"estimated"` with another tokenizer. `reasoning` and `cached_input` appear when the provider reports them, as parts of `output` and `input`. |
| `model` | The model the call asked for. Prices, the cache and a replay look the call up by it. |
| `finish_reason` | Why the reply ended. `"length"` means it was cut off at the output cap, whatever the provider called it. `NA` when the client reports none, as the mock above does. |
| `retryable` | Whether trying the same request again could help (a rate limit, a server error). |
| `raw` | The parsed response body from an [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md), `NULL` from a handler or a cache. |
| `cached` | `TRUE` when an [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md) or a replay answered, so nothing was paid. |
| `served_model`, `response_id`, `fingerprint` | What the provider said about its reply: the model that answered, its response id and its system fingerprint. `NA` where it said nothing. |
| `attempts` | Requests sent for this reply, retries included. 0 for a reply from a cache or a recording, `NA` when the transport does not say. |

A request the run’s limits stopped also has `refused = TRUE` and the
condition in `refusal`.

### When a call fails

A failed call returns a result too. It does not stop your script, so a
loop over many prompts keeps going when one request fails. A handler
that raises an error gives `ok = FALSE` with the message in `error`:

``` r

down <- hr_mock_client(function(messages, params) stop("network down"))
bad <- hr_call(down, "What was revenue in 2024?")
bad
#> <gr_result> ok=FALSE model=mock-model in=12 out=0 error=network down
bad$text
#> [1] ""
```

A reply with no text is a failure too. Providers send an empty reply for
a refusal or a content filter, and
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
reports it with `ok = FALSE` and `finish_reason = "empty"`, so an empty
string never passes as an answer. The mock’s `mode` argument makes it
misbehave the way a provider can; `"refuse"` sends empty replies:

``` r

refusing <- hr_mock_client(function(messages, params) "unused", mode = "refuse")
r <- hr_call(refusing, "What was revenue in 2024?")
c(ok = r$ok, finish_reason = r$finish_reason, error = r$error)
#>                 ok      finish_reason              error 
#>            "FALSE"            "empty" "empty completion"
```

A reply cut off at the output cap keeps `ok = TRUE`, because its text is
what the model wrote, but its `finish_reason` is `"length"`. Check for
it wherever you need the whole reply. `mode = "at_cap"` marks every
reply as cut off:

``` r

capped <- hr_mock_client(function(messages, params) "Revenue was", mode = "at_cap")
r <- hr_call(capped, "What was revenue in 2024?", max_output = 20)
r
#> <gr_result> ok=TRUE model=mock-model in=12 out=20 truncated
#> Revenue was
r$finish_reason
#> [1] "length"
```

Check a result in this order: `ok` first, then `finish_reason`, then the
text itself.

A mock given a vector of HTTP status codes answers call `i` with the
`i`-th status. Here the provider is rate limited (429), then fails
(500), then answers:

``` r

flaky <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.",
                        mode = c(429, 500, 200))
t(vapply(1:3, function(i) {
  r <- hr_call(flaky, "What was revenue in 2024?")
  c(ok = r$ok, status = r$status, retryable = r$retryable)
}, numeric(3)))
#>      ok status retryable
#> [1,]  0    429         1
#> [2,]  0    500         1
#> [3,]  1     NA         0
```

The 429 and the 500 are marked `retryable`. The mock does not retry, so
each status costs one call.
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
retries those statuses itself (see [Retries and
timeouts](#set-retries)).

## Clients

A client is an R object you pass to each call. It is not a global
setting, so two clients with two keys can work side by side in one R
session. Each client is traced, held to the run’s limits, and can be
cached and replayed; the sections below say where one kind differs. Four
kinds of client send the request to a model or a function, one answers
from a recording, and a cache can be attached to any of them.

### A stand-in: `hr_mock_client()`

The mock answers with whatever its handler returns. The handler is a
function of `messages`, the list of messages sent, and `params`, what
the call asked for:

``` r

peek <- hr_mock_client(function(messages, params) {
  sprintf("%d message(s), model %s, cap %d tokens",
          length(messages), params$model, params$max_output)
})
hr_call(peek, msgs, max_output = 200)$text
#> [1] "2 message(s), model mock-model, cap 200 tokens"
str(peek$calls()[[1]]$params)
#> List of 6
#>  $ model        : chr "mock-model"
#>  $ max_output   : int 200
#>  $ temperature  : NULL
#>  $ schema       : NULL
#>  $ schema_name  : chr "result"
#>  $ prompt_tokens: int 21
```

`$calls()` lists every request the mock received, each with its
`messages`, `params`, `result` and `label`, so a test can check the
exact prompts your code sent. `$reset()` empties the list and starts a
`mode` sequence again. The handler may return a string or a `gr_result`,
as a backend handler can (below).

A mock is for tests and practice, and it sends nothing off the machine.
Its calls cost nothing unless you give its model a price, as [the
trace](#trace) section does below, and a mock’s model with no price
draws no `hr_unpriced_model` warning. `embed_handler` gives it
embeddings as well;
[`?hr_mock_client`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
covers that and the other modes, including `"bad_json"`, which appears
under [Structured replies](#structured).

### A function of your own: `hr_backend_client()`

[`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md)
turns any R function into a client: a company proxy, a local model, a
queue, another package’s client. Register the model first, with its real
context window and output limit, since harnessr sizes every prompt from
them. A price lets the spending limit count its calls; a local model
costs nothing, so register it at zero:

``` r

hr_register_model("my-backend", context_window = 8000, max_output = 1000,
                  input_usd = 0, output_usd = 0)

echo <- function(messages, params) {
  question <- messages[[length(messages)]]$content
  sprintf("You asked: %s (reply cap %d tokens)", question, params$max_output)
}
bk <- hr_backend_client(echo, model = "my-backend")
bk
#> <gr_backend_client> model=my-backend embeddings=none (lexical fallback), 0 call(s) made
hr_call(bk, "What was revenue in 2024?", max_output = 100)
#> <gr_result> ok=TRUE model=my-backend in=12 out=21
#> You asked: What was revenue in 2024? (reply cap 100 tokens)
```

`params` carries `model`, `max_output`, `temperature`, `schema`,
`schema_name` and `prompt_tokens`, and `effort` and `draw_index` when
the call has them. What the handler does with them is up to it.

A handler that returns a string gets its token counts estimated. One
that knows the real counts can return a `gr_result`-shaped list instead,
with `ok`, `text`, `usage` and any other field from the table above:

``` r

reporting <- hr_backend_client(function(messages, params) {
  structure(list(ok = TRUE, text = "Revenue was 45.2 million dollars.",
                 usage = list(input = 120L, output = 9L, provenance = "reported"),
                 finish_reason = "stop"),
            class = "gr_result")
}, model = "my-backend")
r <- hr_call(reporting, "What was revenue in 2024?")
str(r$usage)
#> List of 3
#>  $ input     : int 120
#>  $ output    : int 9
#>  $ provenance: chr "reported"
```

A backend does not retry: a handler that fails returns a failed result,
and only the handler can know whether trying again would help. A cache
cannot tell two handlers apart, so each backend client gets a new
identity when it is built, and its cache entries last only for the
session. Pass `id =` a stable name to reuse a cache across sessions, and
only for a handler that answers the same way every time.

### An HTTP provider: `hr_client()`

[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
talks to an OpenAI-compatible endpoint, on the Responses API
(`api = "responses"`, the default) or Chat Completions (`api = "chat"`).
Building one sends nothing and needs no key yet, and printing one hides
the key:

``` r

oa <- hr_client(model = "gpt-5.6-terra", api_key = "sk-example", timeout = 30)
oa
#> <gr_client> model=gpt-5.6-terra api=responses base_url=https://api.openai.com/v1
#>   auth: bearer key (hidden)
#>   embeddings=text-embedding-3-small timeout=30s retries=4 cache=none
```

The call itself needs a real key and the network, so it is not run here:

``` r

live <- hr_client(model = "gpt-5.6-terra")   # the key comes from OPENAI_API_KEY
res <- hr_call(live, "What was revenue in 2024?", max_output = 200)
res$served_model
res$usage
```

[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
reads its defaults from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
when you build it: the model, `api`, the base URL, headers, retries and
the timeout. Changing an option afterwards does not change a client you
already built. Build it again, or pass the value as an argument. For a
gateway that needs its own headers, pass `headers =`;
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
covers gateways and keys.

### Any provider ellmer supports: `hr_ellmer_client()`

[`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
takes a chat object from the [ellmer](https://ellmer.tidyverse.org/)
package, so Anthropic, Google, Bedrock, Ollama and the other providers
ellmer supports answer your calls. ellmer is optional, and this example
needs it and a key, so it is not run here:

``` r

library(ellmer)

# Illustrative figures, in USD per million tokens: use your provider's current
# prices.
hr_register_model("claude-sonnet-4-5", context_window = 200000, max_output = 64000,
                  input_usd = 3, output_usd = 15)
claude <- hr_ellmer_client(chat_anthropic(model = "claude-sonnet-4-5"))
hr_call(claude, "What was revenue in 2024?")$text
```

Each call runs on a fresh copy of your chat with its turns cleared, so
no history passes from one call to the next and your chat object is left
as it was. Three settings belong to the chat and not to the call: the
temperature and the reasoning effort are those the chat was built with
(a call that asks for another warns once), and the output cap carries
over only with ellmer 0.5.0 or later.
[`?hr_ellmer_client`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
lists what carries over.

### A cache: `hr_cache_client()`

[`hr_cache_client()`](https://elkronos.github.io/harnessr/reference/hr_cache_client.md)
attaches an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
to any client. A request answered once is answered from disk the next
time, at no cost:

``` r

n <- 0
counting <- hr_mock_client(function(messages, params) {
  n <<- n + 1
  "Revenue was 45.2 million dollars."
})
cache <- hr_cache(file.path(tempdir(), "core-guide-cache"))
cached <- hr_cache_client(counting, cache)

first <- hr_call(cached, "What was revenue in 2024?")
second <- hr_call(cached, "What was revenue in 2024?")
c(first = first$cached, second = second$cached)
#>  first second 
#>  FALSE   TRUE
n
#> [1] 1
hr_cache_stats(cache)[, c("entries", "hits", "misses", "writes")]
#>   entries hits misses writes
#> 1       1    1      1      1
```

The handler ran once. The second result says `cached = TRUE` and
`attempts = 0`, and a trace counts it as a call that cost nothing. The
key is the exact request: the messages, the model, the output cap, the
temperature, the schema, the effort, any extra body fields and the draw
index, with the client’s identity. Change any of them and the call
misses.

A failed reply is never stored, and neither is a reply cut off at its
cap, so running again asks again.
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
keeps its entries under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) unless you give it a
directory or set `hr_options(cache_dir =)`, so by default a cache lasts
only for the session.
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
empties one and returns the number of entries it removed, invisibly, so
[`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)
shows the result:

``` r

hr_cache_clear(cache)
hr_cache_stats(cache)[, c("entries", "hits", "misses", "writes")]
#>   entries hits misses writes
#> 1       0    0      0      0
```

Every count is back to 0. `entries` is read from disk, and the clear
also resets the session’s counts of `hits`, `misses` and `writes`.

“Paying once” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
covers keeping a cache across sessions, sampled calls and older caches.

### A recording: `hr_replay_client()`

[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
answers from a recorded trace instead of a model (traces are the next
section). Give it the trace of a run, or the file
[`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md)
wrote, and the same calls get the same replies, with no key, no network
and no spend:

``` r

tr <- hr_trace()
orig <- hr_call(cl, "What was revenue in 2024?", trace = tr)
f <- tempfile(fileext = ".json")
hr_trace_save(tr, f)

rp <- hr_replay_client(f)
again <- hr_call(rp, "What was revenue in 2024?")
identical(again$text, orig$text)
#> [1] TRUE
rp$stats()
#>   recorded distinct hits repeats misses legacy_hits
#> 1        1        1    1       0      0           0
```

`$stats()` counts the recording and its use: `recorded` is the requests
the trace holds, `distinct` the different requests among them, `hits`
the calls it answered, `repeats` the hits that reused the last reply,
`misses` the calls it could not answer, and `legacy_hits` the hits
matched by an older key.

A replay matches each call on its messages, its model, its effort, its
temperature, its output cap and its schema. A call the recording does
not hold stops with an error of class `gr_replay_miss`, since the run no
longer matches the recording:

``` r

tryCatch(hr_call(rp, "What was profit in 2024?"),
         gr_replay_miss = function(e) "not in the recording")
#> [1] "not in the recording"
```

`strict = FALSE` returns a failed result for a miss instead. A call made
more often than the recording made it raises `hr_replay_exhausted`,
unless you pass `on_exhausted = "flag"`, which repeats the last reply
and counts it in `$stats()$repeats`. A trace does not keep embedding
vectors, so a run that embedded replays only under conditions that
“Replaying a run” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
sets out, with the limits a replay is held to.

## The trace

A trace is the record of a run. Make one with
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
and pass it to each call as `trace =`; `label =` names what the call was
for:

``` r

# Illustrative prices for a stand-in model. For a real model, use your
# provider's current prices.
hr_register_model("priced-mock", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)

tr <- hr_trace(purpose = "core guide")
a <- hr_call(cl, "What was revenue in 2024?", model = "priced-mock",
             trace = tr, label = "draft")
b <- hr_call(cl, "Check the draft against the report.", model = "priced-mock",
             trace = tr, label = "check")
tr
#> <gr_trace run_20261126222131.915_ecae2b>  2 steps, 2 model calls, 23 in / 26 out tokens, 0 error(s)
#>   steps: check x1, draft x1 
#>   cost: $0.0003 across priced-mock, prices as of 2026-11
#>   usage: estimated locally for 100% of requests (the provider reported none)
#>   actor: purpose = core guide 
#>   started: 2026-11-26T22:21:31.916Z
```

The trace is an environment, so every call that is passed it records
into the same object, and you need not collect it from each result.
Printing it gives the number of steps and calls, the tokens, the errors,
the cost by model, the share of token counts that were estimated, and
who the run is for.

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) gives one
row per request:

``` r

as.data.frame(tr)[, c("step", "stage", "model", "ok", "cached",
                      "tokens_in", "tokens_out", "usd")]
#>   step stage       model   ok cached tokens_in tokens_out      usd
#> 1    1 draft priced-mock TRUE  FALSE        12         13 0.000128
#> 2    2 check priced-mock TRUE  FALSE        11         13 0.000126
```

The `stage` column is the label. The data frame also holds the time, the
error, the prompt and the reply of each request, and where its price
came from. Each row’s `step` points to the full record in `tr$steps`:

``` r

step <- tr$steps[[1]]
names(step)
#>  [1] "step"          "label"         "at"            "started_utc"  
#>  [5] "ended_utc"     "model"         "ok"            "cached"       
#>  [9] "prompt"        "response"      "error"         "tokens"       
#> [13] "seconds"       "attempts"      "served_model"  "response_id"  
#> [17] "fingerprint"   "finish_reason" "params"        "budget_usd"   
#> [21] "params_sent"   "replay_key"
str(step$params_sent)
#> List of 9
#>  $ model          : chr "priced-mock"
#>  $ api            : chr "mock"
#>  $ base_url       : chr "mock://"
#>  $ max_output     : int 4096
#>  $ temperature    : num NA
#>  $ effort         : chr NA
#>  $ schema_name    : chr NA
#>  $ schema_hash    : chr NA
#>  $ extra_body_hash: chr NA
```

`params` is what the call asked for, and `params_sent` the request as it
went out with every default filled in. `replay_key` is the key a replay
looks the call up by.
[`?hr_trace`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
describes every field.

[`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)
gives the totals in one row, and
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md)
the cost by model:

``` r

hr_trace_summary(tr)[, c("calls", "cached", "tokens_in", "tokens_out", "errors",
                         "usage_estimated")]
#>   calls cached tokens_in tokens_out errors usage_estimated
#> 1     2      0        23         26      0               1
hr_trace_cost(tr)[, c("model", "calls", "paid_calls", "usd", "priced", "as_of")]
#>         model calls paid_calls      usd priced   as_of
#> 1 priced-mock     2          2 0.000254   TRUE 2026-11
```

The prices above are illustrative, so the dollar figures are too. A mock
reports no token counts, so every count here was estimated, and
`usage_estimated` is 1. A provider’s own counts are marked `"reported"`.

[`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md)
writes the trace as JSON, the form
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
returns, and
[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
reads that file. The file holds every prompt and reply, so treat it as
you would the documents the run read.

### Who a run is for

A trace records five fields about who ran it and why: `system`, `owner`,
`run_by`, `purpose` and `approved_by`. Give them to
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md),
or set them once for every trace with `hr_options(actor =)`; a field set
in neither place is `NA`:

``` r

tr2 <- hr_trace(owner = "finance team", run_by = "ana", purpose = "Q3 check")
tr2$actor
#> $system
#> [1] NA
#> 
#> $owner
#> [1] "finance team"
#> 
#> $run_by
#> [1] "ana"
#> 
#> $purpose
#> [1] "Q3 check"
#> 
#> $approved_by
#> [1] NA
```

`tr2$config` keeps the options in force when the trace was made and the
R version, without the values of `api_headers`, which can hold
credentials.

### Limits and refusals

Every request is checked against the run’s limits before it is sent. By
default a run may spend \$5 and make 400 calls
(`hr_options(max_cost_usd =, max_calls =)`), and a trace built with
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
holds its own. A request that would pass a limit is not sent:

``` r

small <- hr_trace(governor = hr_governor(max_calls = 1))
one <- hr_call(cl, "What was revenue in 2024?", trace = small)
two <- hr_call(cl, "What was profit in 2024?", trace = small)
c(ok = two$ok, refused = two$refused)
#>      ok refused 
#>   FALSE    TRUE
small$stop_reason
#> [1] "calls"
```

The refused request comes back with `ok = FALSE` and `refused = TRUE`,
after a condition of class `hr_budget_refused` is signalled, which you
can catch with
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html). It is
not a step of the trace; `small$refusals` lists it with the limit it
would have passed.
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
covers every limit.

## Structured replies

To get data back rather than prose, pass `schema`, a JSON Schema written
as an R list, and `schema_name`.
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
sends it as the provider’s structured output setting, and a handler
finds it in `params$schema`:

``` r

revenue_schema <- list(
  type = "object",
  properties = list(revenue_musd = list(type = "number"),
                    year = list(type = "integer")),
  required = list("revenue_musd", "year"),
  additionalProperties = FALSE)

json_mock <- hr_mock_client(function(messages, params) {
  if (is.null(params$schema)) "Revenue was 45.2 million dollars."
  else '{"revenue_musd": 45.2, "year": 2024}'
})
res <- hr_call(json_mock, "What was revenue, and for which year?",
               schema = revenue_schema, schema_name = "revenue")
res$text
#> [1] "{\"revenue_musd\": 45.2, \"year\": 2024}"
str(jsonlite::fromJSON(res$text))
#> List of 2
#>  $ revenue_musd: num 45.2
#>  $ year        : int 2024
```

The reply is still text.
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
does not parse it or check it against the schema, so parse it yourself
and handle a reply that does not parse. Providers can send one, and
`mode = "bad_json"` makes the mock send JSON cut off part way:

``` r

broken <- hr_mock_client(function(messages, params) "unused", mode = "bad_json")
res <- hr_call(broken, "What was revenue?", schema = revenue_schema)
res$ok
#> [1] TRUE
tryCatch(jsonlite::fromJSON(res$text), error = function(e) "does not parse")
#> [1] "does not parse"
```

The call succeeded, so `ok` is `TRUE`; the text is the problem. Since
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
does not parse the reply, an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
stores this one like any other, and a re-run through the cache gets the
same broken text back. Inside an arm of a benchmark, `ctx$call_json()`
does the parsing: it returns the reply as a list when it meets the
schema, a failed result when it does not, and does not cache a reply
that fails
([`?hr_arm`](https://elkronos.github.io/harnessr/reference/hr_arm.md)).
Through ellmer, a schema ellmer cannot express is sent as an instruction
in the prompt instead, with a warning of class `gr_ellmer_schema`.

### Checking settings: `hr_param()`, `hr_schema()` and `hr_validate()`

A second kind of schema checks settings, not replies.
[`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
declares one setting,
[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
collects them, and
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
checks a list of values against them. Use it for the settings of your
own steps and modules:

``` r

reply_settings <- hr_schema(
  hr_param("max_words", "integer", default = 50L, min = 1, max = 500,
           help = "Longest reply, in words."),
  hr_param("style", "enum", choices = c("plain", "bullets"),
           help = "How the reply is laid out."))
reply_settings
#> <hr_schema> 2 parameter(s)
#>   max_words                  integer       basic     -         [1, 500]
#>   style                      enum          basic     -         plain|bullets
str(hr_validate(reply_settings, list(style = "bullets")))
#> List of 2
#>  $ max_words: int 50
#>  $ style    : chr "bullets"
```

The print gives one line per setting: its name, its type, its tier
(`"basic"` or `"advanced"`, for grouping the settings in an interface),
the status of the evidence for its default (`-` when none is declared)
and its bounds or choices.

A value left out gets its default. A number out of range moves to the
nearest bound with a `gr_clamped` warning, and a name the schema does
not have is an error of class `hr_unknown_param`:

``` r

tryCatch(hr_validate(reply_settings, list(max_word = 10)),
         hr_unknown_param = function(e) conditionMessage(e))
#> [1] "'max_word' not a parameter of this schema. Parameters: max_words, style."
```

“Parameter schemas” in
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
covers every type and field.

## Checking a reply

The checks in R come first: `ok`, then `finish_reason`, then whether the
text parses or says what it should. For a check that needs a program,
such as running code a model wrote,
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
builds a step that runs a command you name and reads its result as
`"passed"` or `"failed"`. Here a model writes R code, and the step runs
it with `Rscript`:

``` r

coder <- hr_mock_client(function(messages, params) {
  "total <- sum(c(12.1, 15.3, 17.8))\nstopifnot(abs(total - 45.2) < 1e-9)"
})
code <- hr_call(coder, "Write R code that adds up the quarterly revenue and checks it.")

rscript <- file.path(R.home("bin"), "Rscript")
run_code <- hr_step_command("run", function(input, ctx) {
  f <- tempfile(fileext = ".R")
  writeLines(input$code, f)
  c(rscript, f)
})
out <- run_code(list(code = code$text), list())
out$check[c("status", "exit")]
#> $status
#> [1] "passed"
#> 
#> $exit
#> [1] 0
```

A step is a function of its input and a context; called by hand, as
here, the context can be an empty list. The step returns its input with
the result added as `check`. Code that fails its own check exits with an
error, so the step reads it as `"failed"` and keeps what the program
printed:

``` r

wrong <- run_code(list(code = "stopifnot(sum(c(12.1, 15.3)) == 45.2)"), list())
wrong$check$status
#> [1] "failed"
cat(wrong$check$stderr)
#> Error: sum(c(12.1, 15.3)) == 45.2 is not TRUE
#> Execution halted
```

You write the command. harnessr never takes one from a model’s reply,
never chooses one, and does not isolate the program: it runs with your
permissions. The step sends no request, so it costs nothing.
`parse = "testthat"` reads a testthat summary line together with the
exit code: `"passed"` needs no failures and an exit code of 0. No
summary line, or no failures with a non-zero exit, gives `"error"`, as
does a program that cannot be found. `timeout` stops a program that runs
too long, with the status `"timeout"`. “Checks that run a program” in
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
covers those settings and how a benchmark counts the results, and
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
puts the step in a chain.

## Signals

A signal is a value your code records about its own work: whether the
code a model wrote ran, how sure a reply sounded, how long it was.
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
writes one into a trace, and
[`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
reads them all back as a table:

``` r

tr3 <- hr_trace()
code <- hr_call(coder, "Write the code.", trace = tr3)
out <- run_code(list(code = code$text), list())
hr_signal("demo.code_runs", out$check$status == "passed", tr3, item_id = "q1")
hr_signal("demo.reply_lines", length(strsplit(code$text, "\n")[[1]]), tr3,
          item_id = "q1")
hr_signals(tr3)[, c("step", "signal", "type", "item_id", "value", "score")]
#>   step           signal    type item_id value score
#> 1    2   demo.code_runs logical      q1  TRUE     1
#> 2    3 demo.reply_lines numeric      q1     2     2
```

`score` is the value as a number: 1 or 0 for a logical, the number
itself for a numeric value, and `NA` for text. A value may be logical,
numeric or text, and one call can record several values. A signal is a
local step of the trace: it is not a request, so it adds no call and no
cost and changes no cache key. Recording is all it does. No signal
changes what harnessr does unless you calibrate it against labelled
answers and set a threshold, which “Signals, calibration and gate
thresholds” in
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
covers.
[`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
also reads a list of traces and the runs of a benchmark.

## Errors and warnings by class

Every error and warning the core raises has a class, so you can catch
the one you expect and let the others through. Errors inherit from
`gr_error` and warnings from `gr_warning`:

``` r

tryCatch(hr_call(cl, "What was revenue?", draw_index = -1),
         gr_bad_setting = function(e) class(e))
#> [1] "gr_bad_setting" "gr_error"       "error"          "condition"
```

A failed request is not an error: it comes back as a result with
`ok = FALSE`. The classes below are the ones raised by the functions
this guide covers: a call, its clients, a trace, a schema and a check.
Benchmarks, chains and skills raise classes of their own, such as
`hr_bad_arm` and `hr_unknown_setting`; their help pages
([`?hr_arm`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`?hr_chain`](https://elkronos.github.io/harnessr/reference/hr_chain.md))
and
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
name them.

Errors:

- `gr_auth_error`: no API key could be found, or the key holds a control
  character. A key with a control character also has the class
  `gr_bad_key`.
- `gr_bad_setting`, `gr_bad_option` and `hr_unknown_param`: an argument,
  an option or a schema value that is not allowed.
- `hr_bad_step`: a step from
  [`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
  built with a bad argument, or called with an input it cannot take.
- `gr_file_not_found`:
  [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
  given a trace file that does not exist.
- `gr_header_error`: a malformed `headers` set for
  [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md).
- `gr_bad_backend`: an ellmer chat that lacks a method the adapter
  needs.
- `gr_replay_miss`, `hr_replay_exhausted`, `gr_replay_unreadable` and
  `gr_replay_empty`: a replay that diverged from its recording, ran past
  it, or could not read it.
- `gr_bad_trace`: something that is not a trace where one is needed.
- `gr_budget_error`: a prompt that cannot fit the model’s context
  window.
- `gr_call_cap` and `gr_cost_cap`: limits that leave a benchmark’s
  reader, or an embedding request, too little before it starts. Both are
  also warnings when a batch of requests cannot all fit under the
  limits.
- `gr_embed_error`: an embedding request that failed where no fallback
  was allowed.
- `gr_unknown_model` (under `unknown_model_action = "error"`) and
  `hr_bad_models_file`.
- `gr_missing_dep`: an optional package a feature needs is not
  installed.

Warnings:

- `gr_unknown_model`: a model id the registry does not hold, under the
  default `unknown_model_action = "warn"`.
- `gr_clamped` and `hr_param_clamped`: a setting moved to its nearest
  bound.
- `gr_bad_setting`: also a warning, when
  [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
  gets a `max_output` that is not one number and uses the model’s limit
  instead.
- `gr_effort_unknown`: an effort level harnessr does not know, sent as
  given.
- `hr_unpriced_model` and `hr_stale_price`: a request to a model with no
  price, and a cost computed from old prices.
- `hr_legacy_key`: a cache or a replay that matched a reply by an older
  key.
- `gr_ellmer_model`, `gr_ellmer_temperature`, `gr_effort_unsupported`,
  `gr_ellmer_max_output` and `gr_ellmer_schema`: a setting an ellmer
  chat cannot take per call. `gr_ellmer_model` means a call named a
  model other than the one the chat was built with.
- `gr_embed_fallback` and `gr_backend_no_embeddings`: embeddings
  replaced by word-overlap vectors, the second because the client has no
  way to embed.
- `gr_parallel_unavailable`: `parallel = TRUE` without the future and
  future.apply packages, so the work runs one item at a time.

Conditions that are neither: `hr_budget_refused`, signalled for each
request the limits stop, with `hr_model_not_allowed` added when the
model is not in `allowed_models`, and `hr_budget_stopped`, the warning a
benchmark gives when its limits stopped runs.
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
lists the document layer’s classes.

## API keys and options

[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
finds its key in this order: the `api_key` argument, the
`harnessr.api_key` option, then the `OPENAI_API_KEY` environment
variable.
[`hr_api_key()`](https://elkronos.github.io/harnessr/reference/hr_api_key.md)
resolves a key the same way and stops with a `gr_auth_error` that says
how to set one when it finds none. Given a key, it returns it with
spaces and line breaks around it dropped:

``` r

hr_api_key("  sk-example\n")
#> [1] "sk-example"
```

Called with no argument, it returns your real key, so do not print it
where others can see. A mock, backend or replay client needs no key.
“Connecting to a model” in
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
covers where to keep a key and how to reach a company gateway.

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
reads and sets the session’s options. With one name it returns that
option, with named values it sets them and returns the old ones, and
with no argument it returns them all:

``` r

hr_options("model")
#> [1] "gpt-5.6-terra"
prev <- hr_options(request_timeout = 60)
prev
#> $request_timeout
#> [1] 120
hr_options(prev)
```

[`?hr_options`](https://elkronos.github.io/harnessr/reference/hr_options.md)
documents each option, and
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
lists every setting with its default and where the default came from.

## Choosing the settings

Four walkthroughs cover the options a call reads: which model and
endpoint it goes to, how it retries, its temperature, and who a trace
says the run is for. Each says what the option controls, the signs that
point to changing it, where its default came from, and how to test a
change.

### Model and endpoint: `model`, `api`, `api_base`, `api_headers` and `embedding_model`

**What they control.** They are the defaults
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
takes when you build a client without naming them: `model` the chat
model, `embedding_model` the embedding model, `api` the request shape
(`"responses"` or `"chat"`), `api_base` the address requests go to, and
`api_headers` extra HTTP headers. A call that names a `model` overrides
the client’s. The model also decides the limits a call is held to, from
the model registry:

``` r

unlist(hr_model_info(hr_options("model"))[c("context_window", "max_output")])
#> context_window     max_output 
#>        1050000         128000
```

**Signs they need changing.** A `gr_unknown_model` warning means the
registry does not hold the model. harnessr then takes its limits from a
pattern that matches the id, or from a default profile (a 128,000-token
window and a 4,096-token output cap), and has no price for it, so
register the model with
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md).
An error reply with status 404 can mean the endpoint does not serve the
request shape `api` names; an endpoint that offers only Chat Completions
needs `api = "chat"`. A 401 or 403 from a gateway can mean it wants its
own headers in `api_headers`.

**Where the defaults came from.** `"gpt-5.6-terra"`, the Responses API
and OpenAI’s address are the package’s choice of a default provider. No
measurement backs them, and `gr_settings_table("options")` declares no
evidence for them.

**How to test them.** Two clients for two models are two values, so you
can compare them on the same prompts. A benchmark does this with
replicates and intervals
([`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)).
Before any spend, check what each model takes:

``` r

models <- c("gpt-5.6-terra", "my-backend")
t(vapply(models, function(m) {
  unlist(hr_model_info(m)[c("context_window", "max_output")])
}, numeric(2)))
#>               context_window max_output
#> gpt-5.6-terra        1050000     128000
#> my-backend              8000       1000
```

Building a client sends nothing, so you can check what a client will
send before it sends it. Here the options set a larger embedding model
and a team header, and a client built with a placeholder key shows them:

``` r

prev <- hr_options(embedding_model = "text-embedding-3-large",
                   api_headers = c("X-Team" = "finance"))
hr_client(api_key = "sk-example")
#> <gr_client> model=gpt-5.6-terra api=responses base_url=https://api.openai.com/v1
#>   auth: bearer key (hidden), 1 extra header(s), values hidden: X-Team
#>   embeddings=text-embedding-3-large timeout=120s retries=4 cache=none
hr_options(prev)
```

The print names each extra header and hides its value, since a gateway
header can hold a credential. `embeddings=` is the model
[`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
asks for. A client argument (`model`, `api`, `base_url`,
`embedding_model`, `headers`) overrides the option for that client
alone.

[`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
turns texts into vectors, one row per text, through the client’s
embeddings endpoint or the embed function it was built with. A mock
takes one as `embed_handler`:

``` r

embedding_mock <- hr_mock_client(embed_handler = function(texts, params) {
  m <- cbind(nchar(texts), 1)
  m / sqrt(rowSums(m^2))
})
e <- hr_embed(embedding_mock, c("Revenue rose.", "Costs fell sharply."))
dim(e)
#> [1] 2 2
attr(e, "embedding_source")
#> [1] "api"
```

The `"embedding_source"` attribute names the embedder that made the
rows: `"api"` for the client’s own, which here is the handler. A client
with no way to embed falls back to vectors of word overlap, with a
warning of class `gr_backend_no_embeddings`, and the attribute says so:

``` r

plain <- hr_backend_client(function(messages, params) "unused")
e2 <- withCallingHandlers(
  hr_embed(plain, c("Revenue rose.", "Costs fell sharply.")),
  gr_backend_no_embeddings = function(w) invokeRestart("muffleWarning"))
attr(e2, "embedding_source")
#> [1] "lexical"
```

Check that attribute before you treat the rows as meaning: word-overlap
vectors rank texts by shared words. `fallback = "error"` stops with
`gr_embed_error` instead.
[`?hr_embed`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
covers batching, the cache and the limits an embedding request is held
to.

### Retries and timeouts: `max_retries`, `retry_pause_base` and `request_timeout`

**What they control.**
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
retries a request that failed with a status worth retrying (408, 409,
425, 429, 500, 502, 503 and 504) or with no response at all, up to
`max_retries` times (4 by default). It waits a random time between half
and all of `retry_pause_base` times 2 to the power of n - 1 after the
n-th failed attempt. With the default of 2 seconds that is 1 to 2
seconds, then 2 to 4, then 4 to 8, at most 60 seconds, or what the
provider’s `Retry-After` header says, also at most 60 seconds. A 429
that says the account is out of quota is not retried. `request_timeout`
(120 seconds) is how long one request may take. These apply to
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
alone: a backend handler does its own retrying, and the mock does none.

**Signs they need changing.** A failed result with `retryable = TRUE`
means the retries ran out before the provider answered; raise
`max_retries`, or send fewer requests at once. Many `attempts` above 1
in the trace’s steps mean the run spends much of its time waiting on
rate limits. A request that fails with a transport error after
`request_timeout` seconds, on a long reply, needs a larger timeout.

**Where the defaults came from.** They were set when the HTTP client was
written and have not been tuned; `gr_settings_table("options")` lists
them as untested.

**How to test them.** The mock reproduces a sequence of statuses, so you
can check how your code handles a failure without waiting on a provider.
Each step of a trace records its `attempts`, so the trace of a real run
shows how often a retry was needed. The mock never retries, so each of
its steps shows one:

``` r

flaky$reset()
tr4 <- hr_trace()
for (i in 1:3) invisible(hr_call(flaky, "What was revenue?", trace = tr4))
data.frame(ok = vapply(tr4$steps, `[[`, NA, "ok"),
           attempts = vapply(tr4$steps, `[[`, 0L, "attempts"))
#>      ok attempts
#> 1 FALSE        1
#> 2 FALSE        1
#> 3  TRUE        1
```

### Sampling: `temperature`

**What it controls.** The sampling temperature a call sends when the
call does not give one. `NULL`, the default, sends none, and the model
uses its own default.
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
sends no temperature to a model the registry lists as a reasoning model
or as not taking one. A mock or backend handler is given only the
temperature the call names, in `params$temperature`, not this default.

**Signs it needs changing.** Replies to one prompt that differ from run
to run when you need them to agree. Set a low temperature, or cache the
reply so a re-run gets the same text. A cache key includes the
temperature, so changing it misses every cached reply.

**Where the default came from.** `NULL` leaves the choice to the model;
`gr_settings_table("options")` lists it as untested.

**How to test it.** Send the same request as several draws, with
`draw_index` 1 to N, and compare the replies. Each draw is its own cache
entry and its own replay entry, so the comparison can be run again for
nothing:

``` r

k <- 0
sampler <- hr_mock_client(function(messages, params) {
  k <<- k + 1
  sprintf("draw %d at temperature %s", k, format(params$temperature))
})
sampler <- hr_cache_client(sampler, hr_cache(file.path(tempdir(), "core-guide-draws")))
vapply(1:3, function(i) hr_call(sampler, "Pick a number.", temperature = 0.7,
                                draw_index = i)$text, "")
#> [1] "draw 1 at temperature 0.7" "draw 2 at temperature 0.7"
#> [3] "draw 3 at temperature 0.7"
vapply(1:3, function(i) hr_call(sampler, "Pick a number.", temperature = 0.7,
                                draw_index = i)$text, "")
#> [1] "draw 1 at temperature 0.7" "draw 2 at temperature 0.7"
#> [3] "draw 3 at temperature 0.7"
```

The second line came from the cache. A real model’s draws differ only as
much as its temperature lets them.

### Who a run is for: `actor`

**What it controls.** The five fields every new trace records unless
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
is given them: `system`, `owner`, `run_by`, `purpose` and `approved_by`.
They change no request and no key.

**Signs it needs changing.** Saved traces you cannot attribute to a
person or a project, or a review that asks who approved a run.

**Where the default came from.** Empty, so a trace records only the
fields you set.

**How to test it.** Set it once and check a new trace:

``` r

prev <- hr_options(actor = list(system = "core guide", owner = "finance team"))
hr_trace()$actor[c("system", "owner", "run_by")]
#> $system
#> [1] "core guide"
#> 
#> $owner
#> [1] "finance team"
#> 
#> $run_by
#> [1] NA
hr_options(prev)
```

## Where the document layer builds on this

Every reading function in the document layer makes its requests with
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
and records them in a trace, so everything above applies to a whole
document.
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
takes the same clients and returns the trace of its run in `$trace`;
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
starts there.

## Next

- [`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md):
  the model registry, setting prices, cost estimates and token counts.
- [`vignette("context")`](https://elkronos.github.io/harnessr/articles/context.md):
  how much room a prompt has, and what is cut when it does not fit.
- [`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md):
  how hard a reasoning model reasons, call by call or stage by stage.
- [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md):
  limits, the governor, caching across sessions, replaying a whole run,
  and model prices.
- [`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md):
  steps and chains built from calls like these, and a coding sub-agent
  that checks its own code.
- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  benchmarks, judges, checks that run a program, and calibrating
  signals.
- [`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md):
  parameter schemas, and registering your own modules.
- [`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md):
  every setting with its default.
