# Effort: how hard the model reasons

A reasoning model works through a request in text you never see before
it writes the reply. The provider bills that text as output and counts
it inside the reply’s output cap. The reasoning effort tells the model
how much of it to do: `"low"` for a quick answer, `"high"` for a request
that needs more thought.

harnessr sends no effort unless you ask for one, and each request then
goes out at the provider’s default. This guide covers how to ask:

- which models take an effort, and what happens with one that does not;
- one effort for every call, or one per stage of your code;
- what effort does to the cost, the response cache and the trace;
- effort that starts low and rises for the next stage only when
  something went wrong, with
  [`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
  [`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md)
  and
  [`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md);
- measuring whether that saves money without losing answers, with
  [`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md).

Every example runs offline with no API key. The calls that would reach a
real provider are shown but not run.

## Setting up

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
```

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
returns the values it replaced, and the last chunk of this guide puts
them back with `hr_options(old)`.

The examples use a stand-in reasoning model. Its prices are illustrative
and appear so that the costs below are not `NA`; use your provider’s
current prices for a real model:

``` r

# Illustrative figures, in USD per million tokens.
hr_register_model("reasoner", context_window = 32000, max_output = 8000,
                  input_usd = 1, output_usd = 4, reasoning = TRUE)
```

## Which models take an effort

harnessr sends an effort only to a model whose registry entry says it
reasons.
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
has a `reasoning` column, and
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
gives one model’s flag:

``` r

m <- hr_models()
m$id[m$reasoning %in% TRUE]
#>  [1] "gpt-5"         "gpt-5-mini"    "gpt-5-nano"    "gpt-5.4"      
#>  [5] "gpt-5.4-mini"  "gpt-5.5"       "gpt-5.6-luna"  "gpt-5.6-sol"  
#>  [9] "gpt-5.6-terra" "reasoner"
hr_model_info("gpt-5.6-luna")$reasoning
#> [1] TRUE
hr_model_info("gpt-4o")$reasoning
#> [1] FALSE
```

A model you register is a reasoning model when you say so with
`reasoning = TRUE`, as `"reasoner"` above.
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)
covers registering a model.

A stand-in client shows what each call was sent.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
hands its function the effort in `params$effort`:

``` r

effort_seen <- hr_mock_client(function(messages, params) {
  paste("effort:", if (is.null(params$effort)) "none" else params$effort)
})
hr_call(effort_seen, "What was revenue in 2024?", model = "reasoner", effort = "low")$text
#> [1] "effort: low"
hr_call(effort_seen, "What was revenue in 2024?", model = "gpt-4o", effort = "low")$text
#> [1] "effort: none"
```

gpt-4o does not reason, so harnessr left the effort out of its request,
with no warning. A provider refuses an effort sent to such a model, and
leaving it out lets one setting cover a run that sends some requests to
a cheap model that does not reason and others to one that does. The
trace records the effort each request carried (see [Effort in the
trace](#trace)).

A model the registry does not list is guessed. An id that matches a
family pattern takes the family’s flag, so a new `gpt-5` model counts as
reasoning, and any other id gets the default entry, with
`reasoning = FALSE`, and is sent no effort until you register it:

``` r

suppressWarnings(c(new_gpt5 = hr_model_info("gpt-5.9-preview")$reasoning,
                   unknown = hr_model_info("house-model")$reasoning))
#> new_gpt5  unknown 
#>     TRUE    FALSE
```

### The levels

harnessr knows six levels: `"none"`, `"minimal"`, `"low"`, `"medium"`,
`"high"` and `"xhigh"`. Which of them a model accepts is the provider’s
rule. `"none"` is a level the request carries, asking for no reasoning;
leaving `effort` unset sends no level at all.

A level harnessr does not know is sent as given, since providers add
levels, with a warning of class `gr_effort_unknown`. When the level is
close to a known one, the warning names it, because the provider would
refuse every request a typo goes out with:

``` r

res <- withCallingHandlers(
  hr_call(effort_seen, "What was revenue in 2024?", model = "reasoner", effort = "hihg"),
  gr_effort_unknown = function(w) {
    message(conditionMessage(w))
    invokeRestart("muffleWarning")
  })
#> Reasoning effort 'hihg' is not one of none, minimal, low, medium, high, xhigh, but 'high' is. It is sent as given, since a provider can add levels, and a provider that does not know it will refuse every request it is sent with.
res$text
#> [1] "effort: hihg"
```

A setting of the wrong shape stops before anything is sent, with an
error of class `gr_bad_setting`: a value that is not text, a blank or
missing value, two values for the calls no name covers, or a name given
twice.

``` r

tryCatch(hr_call(effort_seen, "hi", model = "reasoner", effort = c("low", "high")),
         gr_bad_setting = function(e) "refused: two values with no names")
#> [1] "refused: two values with no names"
```

`effort` follows `...` in
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md),
so name it in full.

## Where the effort goes in a request

An
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
puts the effort in the field its API reads:
`reasoning = list(effort = ...)` on the Responses API, and
`reasoning_effort` on Chat Completions. A mock or backend handler finds
it in `params$effort`, as above.

A client can carry a default effort of its own in `extra_body`, which
goes on every request it sends. The `effort` of a call is more specific,
so it wins for that call, and the rest of the client’s `reasoning`
object is kept:

``` r

cl <- hr_client(api = "responses",
                extra_body = list(reasoning = list(effort = "low", summary = "auto")))
# Sent with reasoning = {effort: "low", summary: "auto"}.
hr_call(cl, "Summarise the notes.", model = "gpt-5.6-luna")
# Sent with reasoning = {effort: "high", summary: "auto"}.
hr_call(cl, "Check the summary against the notes.", model = "gpt-5.6-luna",
        effort = "high")
```

The trace’s `effort` column and the escalation policy below read the
call’s `effort`, so they do not see an `extra_body` effort; only the
step’s `params_sent`, the request as it went out, shows it. It is part
of the client, so it does change the response cache key. Prefer the
call’s `effort` when you want the record to show it.

An
[`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
cannot take an effort per call, because ellmer sets it on the chat
object. The first call through the client that asks for one warns with
class `gr_effort_unsupported`, and every call goes out at the chat’s own
setting. Build the chat with the effort you want:

``` r

chat <- ellmer::chat_openai(model = "gpt-5.6-luna")
el <- hr_ellmer_client(chat)
hr_call(el, "Summarise the notes.", model = "gpt-5.6-luna", effort = "low")
#> Warning: Reasoning effort is set on the ellmer chat object, not per call, ...
```

The trace step of such a call keeps the effort it asked for as
`params$unsent_effort`, not `params$effort`, so the trace does not claim
an effort the request never carried.

## One effort for every call, or one per stage

Give `effort` one level and every call it is passed to goes out at that
level. harnessr has no session-wide effort option in
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md):
the effort is a setting of each call. To keep one effort across your
code, hold it in one place and pass it to each call, for example as an
arm’s setting that each call reads (see [Does more effort
pay?](#check)), or as a client’s `extra_body`.

Calls in a run differ. A run that reads forty chunks and then writes one
answer makes forty small requests and one that judges. Name each call
with `label`, and give `effort` a character vector named by label:

``` r

by_stage <- c(extract = "low", synthesise = "medium", "synthesise.section" = "high")
labels <- c("extract.chunk", "synthesise.merge.level2", "synthesise.section",
            "outline", "extractor")
vapply(labels, function(l) {
  hr_call(effort_seen, "hi", model = "reasoner", label = l, effort = by_stage)$text
}, character(1))
#>           extract.chunk synthesise.merge.level2      synthesise.section 
#>           "effort: low"        "effort: medium"          "effort: high" 
#>                 outline               extractor 
#>          "effort: none"          "effort: none"
```

The rules the output follows:

- A name covers a label equal to it, or one that starts with it and a
  dot. `extract` covers `extract.chunk` but not `extractor`.
- When several names cover a label, the longest wins:
  `synthesise.section` goes out at `"high"` and the merge under
  `synthesise` at `"medium"`.
- An unnamed value, or one named `"default"`, covers every label no name
  covers. With none, as here, such a call is sent no effort: `outline`
  and `extractor` went out at the provider’s default.

``` r

hr_call(effort_seen, "hi", model = "reasoner", label = "outline",
        effort = c(extract = "low", default = "medium"))$text
#> [1] "effort: medium"
```

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
does not check the names against your labels. A misspelt name covers no
call, and those calls go out at the provider’s default with nothing
said:

``` r

hr_call(effort_seen, "hi", model = "reasoner", label = "extract.chunk",
        effort = c(extrac = "low"))$text
#> [1] "effort: none"
```

Check the trace’s `effort` column after a first run. The document layer
checks its own maps against the labels its readers declare (see [Where
the document layer builds on this](#document-layer)).

## What effort costs

Reasoning is output. The provider counts the reasoning tokens inside the
reply’s `output` tokens and bills them at the output price, so a higher
effort costs more on every request it reaches. A provider that reports
them puts the reasoning count in `usage$reasoning`, as part of `output`.

Here a backend stands in for a provider that reasons more at a higher
effort and reports what it spent:

``` r

thinking <- c(low = 200L, medium = 800L, high = 3000L)
thinks <- hr_backend_client(function(messages, params) {
  r <- if (is.null(params$effort)) 1500L else thinking[[params$effort]]
  structure(list(ok = TRUE, text = "Revenue was 45.2 million dollars.",
                 usage = list(input = 120L, output = r + 9L, reasoning = r,
                              provenance = "reported")),
            class = "gr_result")
})
tr <- hr_trace()
for (e in c("low", "medium", "high")) {
  hr_call(thinks, "What was revenue in 2024?", model = "reasoner", effort = e,
          trace = tr, label = paste0("ask.", e))
}
invisible(hr_call(thinks, "What was revenue in 2024?", model = "reasoner",
                  trace = tr, label = "ask.unset"))
as.data.frame(tr)[, c("stage", "effort", "tokens_out", "tokens_reasoning", "usd")]
#>        stage effort tokens_out tokens_reasoning      usd
#> 1    ask.low    low        209              200 0.000956
#> 2 ask.medium medium        809              800 0.003356
#> 3   ask.high   high       3009             3000 0.012156
#> 4  ask.unset   <NA>       1509             1500 0.006156
```

The reply is nine tokens each time, and the cost follows the reasoning.
Unset, the request went out at the provider’s default, which this
stand-in puts between medium and high. A real provider’s default is its
own, so measure it rather than assume it is cheap. The figures in
`tokens_reasoning` and `usd` come from what the provider reports;
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
prices any count you give it, reasoning included in `output_tokens`:

``` r

hr_estimate_cost("reasoner", input_tokens = 120, output_tokens = 3009)
#> [1] 0.012156
```

### Reasoning and the output cap

The output cap bounds the reasoning and the reply together. A request at
`"high"` with a small cap can spend the whole cap reasoning and come
back cut off, with `finish_reason` `"length"` and little or no text. A
cut-off reply is not cached, so a second run asks again.

harnessr guards against this for short requests. An HTTP request to a
reasoning model is sent with a cap of at least
`hr_options("reasoning_floor")` tokens, 2,048 by default, where the
model’s limit and the context window leave room. The cache key, the
trace’s `params$max_output` and a mock or backend handler see the cap
you asked for; the trace’s `params_sent` records the cap the HTTP
request carried, and the spending limits check the request at that cap.
[The output cap floor](#set-reasoning-floor) below covers the setting.

## Effort and the response cache

The effort a request carries is part of the response cache key, as the
temperature is, so replies at two efforts are never traded:

``` r

n <- 0
counting <- hr_mock_client(function(messages, params) {
  n <<- n + 1
  "Revenue was 45.2 million dollars."
})
cache <- hr_cache(file.path(tempdir(), "effort-guide-cache"))
cached <- hr_cache_client(counting, cache)
c(low       = hr_call(cached, "What was revenue?", model = "reasoner", effort = "low")$cached,
  low_again = hr_call(cached, "What was revenue?", model = "reasoner", effort = "low")$cached,
  high      = hr_call(cached, "What was revenue?", model = "reasoner", effort = "high")$cached,
  unset     = hr_call(cached, "What was revenue?", model = "reasoner")$cached)
#>       low low_again      high     unset 
#>     FALSE      TRUE     FALSE     FALSE
n
#> [1] 3
```

Three requests reached the model: the repeat at `"low"` came from the
cache, and `"high"` and the unset call each missed. The key holds the
effort the request carried, not the one the call asked for, so a model
that does not reason shares one entry whatever effort you pass:

``` r

c(gpt4o_high  = hr_call(cached, "What was revenue?", model = "gpt-4o", effort = "high")$cached,
  gpt4o_unset = hr_call(cached, "What was revenue?", model = "gpt-4o")$cached)
#>  gpt4o_high gpt4o_unset 
#>       FALSE        TRUE
```

With no effort set, the key has no effort part, so a cache written
before you used effort still answers calls that use none. A replay
matches each call on its effort too, and a call at an effort the
recording does not hold stops with an error of class `gr_replay_miss`
that names the efforts it does hold:

``` r

f <- tempfile(fileext = ".json")
hr_trace_save(tr, f)
rp <- hr_replay_client(f)
hr_call(rp, "What was revenue in 2024?", model = "reasoner", effort = "low",
        label = "ask.low")$text
#> [1] "Revenue was 45.2 million dollars."
tryCatch(hr_call(rp, "What was revenue in 2024?", model = "reasoner", effort = "xhigh"),
         gr_replay_miss = function(e) conditionMessage(e))
#> [1] "No recorded response for this prompt. The same prompt IS recorded for this model at reasoning effort 'low' or effort 'medium' or effort 'high' or no effort, and this call asked for effort 'xhigh'; replay the run with the `effort` it was recorded with."
```

## Effort in the trace

Each request’s trace step keeps the effort it carried in
`params$effort`, and leaves the field out when it carried none:

``` r

str(tr$steps[[1]]$params)
#> List of 6
#>  $ model        : chr "reasoner"
#>  $ max_output   : int 8000
#>  $ temperature  : NULL
#>  $ schema_name  : chr "result"
#>  $ prompt_tokens: int 12
#>  $ effort       : chr "low"
str(tr$steps[[4]]$params)
#> List of 5
#>  $ model        : chr "reasoner"
#>  $ max_output   : int 8000
#>  $ temperature  : NULL
#>  $ schema_name  : chr "result"
#>  $ prompt_tokens: int 12
```

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) of a
trace has an `effort` column only when some request carried an effort,
so a trace without effort reads as it did before effort existed. `NA` in
the column marks a request sent no effort, such as the unset call above
or a request to a model that does not reason. A run that raises its
effort adds `"effort.escalate"` and `"effort.resolve"` steps, and
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md)
adds `"effort.event"` steps; both are covered next.

## Effort that rises only when needed

A fixed `"high"` pays for reasoning on every request, including the many
that a low effort answers as well. A fixed `"low"` saves that, and loses
the requests that needed more.
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
builds a policy in between: every stage starts at a base effort, and
when something went wrong in one stage, the next stage is sent at a
raised effort.

``` r

pol <- hr_effort_escalate(base = "low", to = "high",
                          replies = c(not_in_document = "NOT FOUND"))
pol
#> <hr_effort_escalate>
#>   base: low; raised to high for the next stage, at most 1 time(s) a run
#>   on:   truncated, parse_failure, schema_failure, verify_failed, not_in_document, unclear, disagreement
```

Pass the policy as a call’s `effort`, with the same trace on every call
of the run. The policy keeps its state on the trace: which stage the run
is in, whether it was raised and how many raises are left. A call with
no trace is sent at the base effort.

Its arguments:

- `base`: the starting effort, one level or a map named by label,
  resolved as a fixed effort is.
- `to`: the raised effort, one level.
- `on`: the triggers that raise the next stage, all seven by default.
- `max_escalations`: the most raises in one run (one trace), 1 by
  default.
- `replies`: reply texts that count as triggers, named by trigger.

### Stages

A stage is a call label up to its second dot, with a merge level
(`.level2`), a summary level (`.L2`) or a judge’s order (`.o2`) at the
end left off. `map.answer` and `reduce` are stages, and `reduce.level1`
belongs to `reduce`. The effort changes only when a call starts a new
stage, never part way through one, so the requests of one stage share an
effort and a provider’s prompt cache.

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
labels a call `"call"` unless you give a `label`, so a run of unlabelled
calls is one stage and is never raised. Label each stage.

### Triggers

The core sees three triggers for itself:

- `"truncated"`: a `"truncate"` step on the trace, which
  [`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
  and
  [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
  write when given the trace (see
  [`vignette("context")`](https://elkronos.github.io/harnessr/articles/context.md)),
  or a reply cut off at its output cap.
- `"parse_failure"`: a reply to one of harnessr’s own structured
  requests that is not JSON. These are `ctx$call_json()` in a benchmark
  arm, a judge and the document readers.
- `"schema_failure"`: such a reply that does not fit its schema.

`hr_call(schema = )` does not parse its reply, so a reply to it never
fires either trigger by itself. Check the reply in your code and report
it with
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
as [Reporting a trigger](#report-trigger) shows.

`replies` turns a reply into a trigger. With
`c(not_in_document = "NOT FOUND")`, the trigger fires when every request
of a stage replied with text that starts with `NOT FOUND`. The other
default triggers, `"verify_failed"`, `"unclear"` and `"disagreement"`,
and any name of your own, fire when your code reports them with
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md).

### A raise, step by step

The stand-in below finds nothing at low effort when asked to find
something, and answers at any other effort:

``` r

finder <- hr_mock_client(function(messages, params) {
  if (startsWith(messages[[1]]$content, "Find") && identical(params$effort, "low")) {
    return("NOT FOUND")
  }
  paste("answered at", params$effort)
})
tr <- hr_trace()
step <- function(prompt, label) {
  hr_call(finder, prompt, model = "reasoner", trace = tr, label = label, effort = pol)$text
}
step("Find the revenue figure in part 1.", "find.part1")
#> [1] "NOT FOUND"
step("Find the revenue figure in part 2.", "find.part2")
#> [1] "answered at high"
step("Check the figure.", "check")
#> [1] "answered at low"
step("Write the answer.", "answer")
#> [1] "answered at low"
as.data.frame(tr)[, c("step", "stage", "effort", "reply")]
#>   step      stage effort            reply
#> 1    1 find.part1    low        NOT FOUND
#> 2    3 find.part2   high answered at high
#> 3    5      check    low  answered at low
#> 4    6     answer    low  answered at low
```

Stage `find.part1` went out low, and its only request replied
`NOT FOUND`. When `find.part2` started, the policy saw the trigger and
sent that stage high, where it found the figure. With one raise allowed
and used, `check` and `answer` went back to low. The step numbers skip 2
and 4: those are the policy’s own steps.

### The log: `hr_effort_log()`

[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)
returns one row per raise:

``` r

hr_effort_log(tr)
#>        after      stage        triggers   to calls resolved
#> 1 find.part1 find.part2 not_in_document high     1     TRUE
```

`after` is the stage the triggers fired in, `stage` the stage sent
raised, `calls` the requests the raised stage sent and `resolved`
whether the raised stage fired none of the same triggers. `TRUE` here:
at high effort the search found what low effort missed. A raise whose
stage is the last of the run is settled from the trace as it is when you
ask.

The trace holds the same facts as an `"effort.escalate"` step at the
raise and an `"effort.resolve"` step when the raised stage ends:

``` r

local_steps <- Filter(function(s) identical(s$kind, "local"), tr$steps)
for (s in local_steps) {
  cat(s$label, ": ", paste(names(s$detail), unlist(s$detail), sep = " = ", collapse = "; "),
      "\n", sep = "")
}
#> effort.escalate: after = find.part1; stage = find.part2; triggers = not_in_document; to = high
#> effort.resolve: stage = find.part2; triggers = not_in_document; resolved = TRUE; calls = 1
```

### Reporting a trigger: `hr_effort_event()`

Some trouble only your code can see: two reviewers that disagree, a
quotation that failed a check.
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md)
records it as an `"effort.event"` step, and the policy reads it at the
next stage boundary. This policy allows two raises, starts the `draft`
stage at low and every other stage at medium:

``` r

pol2 <- hr_effort_escalate(base = c(draft = "low", default = "medium"), to = "xhigh",
                           max_escalations = 2)
cut_off <- hr_backend_client(function(messages, params) {
  long <- grepl("long", messages[[1]]$content) && !identical(params$effort, "xhigh")
  structure(list(ok = TRUE, text = paste("at", params$effort),
                 finish_reason = if (long) "length" else "stop",
                 usage = list(input = 10L, output = 5L)),
            class = "gr_result")
})
tr2 <- hr_trace()
go <- function(prompt, label) {
  hr_call(cut_off, prompt, model = "reasoner", trace = tr2, label = label, effort = pol2)
}
go("Write a long draft.", "draft")$finish_reason
#> [1] "length"
go("Review the draft.", "review")$text
#> [1] "at xhigh"
hr_effort_event(tr2, "disagreement", note = "the two reviewers differ")
go("Write the final text.", "final")$text
#> [1] "at xhigh"
go("Polish the wording.", "polish")$text
#> [1] "at medium"
hr_effort_log(tr2)
#>    after  stage     triggers    to calls resolved
#> 1  draft review    truncated xhigh     1     TRUE
#> 2 review  final disagreement xhigh     1     TRUE
```

The draft was cut off at its cap, the `"truncated"` trigger, so the
review went out at xhigh. During the review, the code reported a
disagreement, so the final stage went out raised too. That was the
second and last raise, so `polish` went back to its base of medium. Both
raises resolved: each raised stage fired none of the triggers that
raised it. A third trigger would have raised nothing.

[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md)
returns `TRUE` when it recorded the event, invisibly, so the call in the
chunk above printed nothing. It records nothing, and returns `FALSE`, on
a trace no escalation policy has sent a request on, so a run without a
policy records nothing new:

``` r

print(hr_effort_event(hr_trace(), "disagreement"))
#> [1] FALSE
```

A reply to `hr_call(schema = )` that is not JSON is a trigger only when
your code reports it. This policy narrows `on` to `"parse_failure"`, so
no other trigger raises a stage:

``` r

pol3 <- hr_effort_escalate(base = "low", to = "high", on = "parse_failure")
extractor <- hr_mock_client(function(messages, params) {
  if (identical(params$effort, "low")) "Revenue was 45.2." else '{"revenue": 45.2}'
})
revenue_schema <- list(type = "object",
                       properties = list(revenue = list(type = "number")),
                       required = list("revenue"))
tr3 <- hr_trace()
ask <- function(label) {
  hr_call(extractor, "Give the revenue as JSON.", model = "reasoner", trace = tr3,
          label = label, effort = pol3, schema = revenue_schema, schema_name = "revenue")
}
first <- ask("extract")
first$text
#> [1] "Revenue was 45.2."
if (!jsonlite::validate(first$text)) {
  print(hr_effort_event(tr3, "parse_failure", label = "extract"))
}
#> [1] TRUE
ask("extract_again")$text
#> [1] "{\"revenue\": 45.2}"
hr_effort_log(tr3)[, c("after", "stage", "to", "resolved")]
#>     after         stage   to resolved
#> 1 extract extract_again high     TRUE
```

The first reply came back as prose,
[`jsonlite::validate()`](https://rdrr.io/pkg/jsonlite/man/validate.html)
found it was not JSON, and the code reported `"parse_failure"`, which
printed `TRUE`. The next stage went out at high and returned JSON, so
the raise resolved.

### What escalation does not do

- It does not send a stage again. The stage that fired a trigger keeps
  its replies; the raise applies to the stage after it. To retry a
  request at a higher effort, call again with that effort yourself.
- It does not change the effort part way through a stage.
- It does not raise more often than `max_escalations` allows, and a
  run’s state lives on its trace, so two runs on two traces raise
  separately.
- It has not been shown to keep accuracy. Measure that on your own task,
  as the next section does.

## Does more effort pay? `hr_effort_check()`

A policy that starts low pays off if it answers as well as a fixed
effort and costs less.
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
tests the first part with the non-inferiority test of
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
and reports the cost of each arm, with the raised requests counted. It
reads a benchmark you build with
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md);
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
covers benchmarks, references and the test.

The benchmark below has three arms of one two-stage task: a fixed
`"low"`, a fixed `"high"` and the escalation policy. Each arm reads its
effort from its `params`, which is one way to hold a run’s effort in one
place. In the stand-in, five of the hundred items are hard: at low
effort the first stage finds nothing and the answer is wrong. Reasoning
costs 100 tokens a request at low and 1,500 at high:

``` r

ref <- hr_reference(sprintf("q%03d", 1:100), labels = rep("yes", 100),
                    cluster = sprintf("c%02d", rep(1:50, each = 2)), split = "test")
task <- function(item, ctx) {
  e <- ctx$params$effort
  hr_call(ctx$client, paste("find", item), model = "reasoner", trace = ctx$trace,
          label = "task.find", effort = e)
  hr_call(ctx$client, paste("answer", item), model = "reasoner", trace = ctx$trace,
          label = "task.answer", effort = e)$text
}
esc <- hr_effort_escalate(replies = c(not_in_document = "NOT FOUND"))
arms <- list(hr_arm("low", task, params = list(effort = "low")),
             hr_arm("high", task, params = list(effort = "high")),
             hr_arm("escalate", task, params = list(effort = esc)))

reasoning_at <- c(low = 100L, high = 1500L)
provider <- hr_backend_client(function(messages, params) {
  q <- messages[[1]]$content
  hard <- grepl("q00[1-5]", q) && identical(params$effort, "low")
  text <- if (!hard) "yes" else if (startsWith(q, "find")) "NOT FOUND" else "no"
  r <- reasoning_at[[params$effort]]
  structure(list(ok = TRUE, text = text,
                 usage = list(input = 50L, output = r + 2L, reasoning = r,
                              provenance = "reported")),
            class = "gr_result")
})
bench <- hr_benchmark(arms, ref, runs = 5, client = provider,
                      governor = hr_governor(max_calls = 4000, max_cost_usd = 50))
chk <- hr_effort_check(bench, "escalate", margin = 0.10, B = 500)
chk
#> <hr_effort_check> escalate against low, high (post hoc: no registration)
#>   vs low          margin 10.0 pts, difference +5.0 pts, lower bound -0.9: not shown
#>   vs high         margin 10.0 pts, difference +0.0 pts, lower bound -5.1: non-inferior
#>   best fixed comparator: high
#>       arm accuracy      usd calls escalations escalated_calls resolved priced
#>       low     0.95 0.000916     2        0.00            0.00       NA   TRUE
#>      high     1.00 0.012116     2        0.00            0.00       NA   TRUE
#>  escalate     1.00 0.001196     2        0.05            0.05        1   TRUE
#>    as_of certain
#>  2026-11    TRUE
#>  2026-11    TRUE
#>  2026-11    TRUE
```

The first block tests the policy against each fixed effort: every other
arm, since `comparators` was left out. `margin` is the largest loss of
accuracy you accept, here 10 points, and the policy is non-inferior to
an arm when the lower bound of the difference stays above minus the
margin. The bounds come from `B` bootstrap resamples drawn with `seed`
(1 by default), and Holm’s procedure adjusts the tests for there being
more than one comparison. “best fixed comparator” names the most
accurate of the fixed arms, the one the policy most needs to match. The
cost table gives, per arm, the accuracy, the mean cost per run (`usd`),
the requests per run (`calls`), the raises per run (`escalations`), the
requests sent raised per run (`escalated_calls`) and the share of raises
that resolved. Its last three columns say where `usd`’s prices came
from: `priced` is `TRUE` when every run’s models have a price, `as_of`
is the oldest month among those prices, and `certain` is `TRUE` when
every model’s registry entry is a fact rather than a guess from a
pattern.

Here the policy answered every item, as `"high"` did, at about a tenth
of its cost: only the hard items’ answer stage went out raised. Against
`"low"` it is “not shown” for the other part of the test. By default
(`cost_test = TRUE`) a verdict also needs the policy to cost less than
the arm it replaces, with the upper bound of the cost difference below
zero, and it costs more than a fixed `"low"`:

``` r

chk$contrasts[, c("reference", "estimate", "lower", "accuracy_holds",
                  "cost_diff", "cost_holds", "verdict")]
#>   reference estimate        lower accuracy_holds cost_diff cost_holds verdict
#> 1       low     0.05 -0.009183507           TRUE   0.00028      FALSE   FALSE
#> 2      high     0.00 -0.050756784           TRUE  -0.01092       TRUE    TRUE
```

With `cost_test = FALSE`, the verdict rests on accuracy alone. Here it
is run against `"high"` alone, through `comparators`:

``` r

chk_acc <- hr_effort_check(bench, "escalate", comparators = "high", margin = 0.10,
                           cost_test = FALSE, B = 500)
chk_acc$contrasts[, c("reference", "estimate", "lower", "accuracy_holds", "verdict")]
#>   reference estimate       lower accuracy_holds verdict
#> 1      high        0 -0.03881637           TRUE    TRUE
```

With one comparison, Holm’s procedure has nothing to adjust, and the
verdict follows the accuracy test.

The header says “post hoc”: the margin was chosen after the benchmark
was scored, so the result is evidence for running a registered
comparison, not a verdict. Register the contrasts and margin with
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
before the benchmark runs and pass them as `registration`, as
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
shows; the check then tests those contrasts at their registered margins.
Either way the benchmark’s rows must be on the test or final split.

[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
plans nothing: the arms, the items and the runs are yours. The stand-in
makes the policy look good by design, so run the check on your own task
before you change a default.

## Choosing the settings

One option belongs to effort. The walkthrough says what it controls, the
signs that point to changing it, where its default came from and how to
test a change.

### The output cap floor: `reasoning_floor`

**What it controls.** The smallest output cap an HTTP request to a
reasoning model is sent with, 2,048 tokens by default. A call that asks
for a smaller cap is sent with the floor instead, held to the model’s
output limit and to the room the context window leaves after the prompt.
A cap at or above the floor is sent as it is, and `0` turns the raise
off. It trades a short request’s spend for room to reason: without it, a
call that asks for 100 tokens can spend all 100 reasoning and return
nothing.

**Signs it needs changing.** Short structured requests to a reasoning
model that come back cut off, with `finish_reason` `"length"`,
`tokens_reasoning` near the cap and no text, point to a higher floor.
Requests that use far less than the floor at the effort you send, on a
model that bills by tokens used, need no change, since unused cap costs
nothing; a lower floor matters only when the spending limits refuse
requests checked at the raised cap.

**Where the default came from.** The constant the code had before the
option existed, from the observation that a reasoning model can spend a
few hundred to a couple of thousand tokens before it replies. It was not
measured, and `gr_settings_table("options")` lists it as untested.

**How to test it.** A value other than the default joins the response
cache key, so replies cached at one floor are not reused at another:

``` r

hr_call(cached, "What was revenue?", model = "reasoner", effort = "low")$cached
#> [1] TRUE
prev <- hr_options(reasoning_floor = 4096)
hr_call(cached, "What was revenue?", model = "reasoner", effort = "low")$cached
#> [1] FALSE
hr_options(prev)
```

The same request was answered from the cache at the default floor and
missed at 4,096. The floor joins the key for every model, not only the
reasoning ones, because the key records the option and not what it did
to a request.

Then run your short requests at each floor you consider with a real
client, and compare `finish_reason`, `tokens_reasoning` and the trace’s
`params_sent$max_output`:

``` r

hr_options(reasoning_floor = 4096)
tr <- hr_trace()
res <- hr_call(hr_client(), "Score this passage from 0 to 10.", model = "gpt-5.6-luna",
               max_output = 50, effort = "medium", trace = tr, label = "score")
c(res$finish_reason, res$usage$reasoning)
tr$steps[[1]]$params_sent$max_output
```

## Where the document layer builds on this

A read takes an effort map as the `effort` setting of
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
and its `effort_mode = "escalate"` builds an
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
policy from it. The document layer checks the names of a map against the
labels its readers declare, and stops with an error of class
`hr_unknown_effort_key` for one that covers no call. “Reasoning effort,
stage by stage” in
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
lists each reader’s labels, and
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
raises the effort of a read with `effort_mode`.

## Next

- [`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md):
  the calls an effort is sent with, and the trace that records it.
- [`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md):
  which models reason, and registering one.
- [`vignette("context")`](https://elkronos.github.io/harnessr/articles/context.md):
  the cuts that fire the `"truncated"` trigger.
- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  benchmarks, references and the non-inferiority test
  [`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
  uses.
