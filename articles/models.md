# Models, prices and tokens

Before harnessr sends a request, it looks the model up in its registry.
The entry gives the model’s context window and output cap, which size
every prompt, and the prices you set, which turn the tokens a request
used into dollars and let `max_cost_usd` hold. The tokens come from a
token counter, the same one that measures a prompt before it goes out.

The sections below show what the registry knows about a model and how
sure it is, how to add a model and set the prices you pay, what a cost
estimate says and when it is `NA`, and how harnessr counts tokens. Every
example runs offline with no API key. The prices in it are illustrative:
use your provider’s current prices, in US dollars per million tokens.

## Setting up

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
```

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
returns the values it replaced, and the last chunk of this guide puts
them back with `hr_options(old)`. Every registration below lasts for the
R session and changes nothing on disk.

## What harnessr knows about a model

[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
lists the registry, one row per model, chat models first:

``` r

m <- hr_models()
nrow(m)
#> [1] 20
table(m$kind)
#> 
#>      chat embedding 
#>        17         3
m[m$id %in% c("gpt-5.6-terra", "gpt-4o", "gpt-4", "text-embedding-3-small"), ]
#>                        id      kind context_window max_output reasoning
#> 2                   gpt-4      chat           8192       8192     FALSE
#> 7                  gpt-4o      chat         128000      16384     FALSE
#> 17          gpt-5.6-terra      chat        1050000     128000      TRUE
#> 19 text-embedding-3-small embedding           8191          0     FALSE
#>    input_usd_per_1m output_usd_per_1m   as_of cached_input_usd_per_1m
#> 2                NA                NA 2026-08                      NA
#> 7                NA                NA 2026-08                      NA
#> 17               NA                NA 2026-08                      NA
#> 19               NA                NA 2026-08                      NA
```

harnessr ships 20 models, 17 chat models and 3 embedding models, all
OpenAI’s, read from `inst/extdata/models.csv` when the package loads.
For each it ships the limits: `context_window` (prompt and reply
together, in tokens), `max_output` (the most tokens one reply may have),
whether it is a reasoning model and, for an embedding model, its
dimensions. The price columns are `NA` because harnessr ships no prices.
The table leaves out `supports_temperature` and `dimensions`;
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
has every field. For a model with no price, `as_of` is the month its
limits were last checked; once you set prices, it is the month of the
prices.

gpt-4 lists an output cap equal to its window. A prompt to it still has
room:
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
reserves a quarter of the usable window for the reply, not the whole
cap:

``` r

unlist(hr_budget("gpt-4")[c("context_window", "input", "output")])
#> context_window          input         output 
#>           8192           5529           1843
```

A tenth of the window is left unused, for error in the token count (see
[Counting tokens](#counting-tokens)).

### One model: `hr_model_info()`

[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
returns one model’s entry as a list:

``` r

str(hr_model_info("gpt-5.6-terra"))
#> List of 13
#>  $ context_window      : int 1050000
#>  $ max_output          : int 128000
#>  $ input_usd           : num NA
#>  $ output_usd          : num NA
#>  $ reasoning           : logi TRUE
#>  $ supports_temperature: logi FALSE
#>  $ kind                : chr "chat"
#>  $ dimensions          : int NA
#>  $ certain             : logi TRUE
#>  $ as_of               : chr "2026-08"
#>  $ cached_input_usd    : num NA
#>  $ id                  : chr "gpt-5.6-terra"
#>  $ source              : chr "builtin"
```

Three fields here change how an
[`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
request is built. A model with `reasoning = TRUE` gets no `temperature`,
and its output cap is raised to at least the `reasoning_floor` option
(2,048 tokens) where the window has room, because its reasoning is
billed as output inside the same cap. A model with
`supports_temperature = FALSE` gets no `temperature` either. A mock or
backend handler is given the temperature and cap the call asked for, and
passing them on is its business. `kind` says whether the model answers
prompts or returns embeddings.

`source` says where the entry came from, and `certain` says whether
harnessr knows the model or guessed. harnessr tries five places in order
and stops at the first that has the id:

| `source` | where the entry came from | `certain` |
|----|----|----|
| `"registered"` | [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md) or [`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md) in this session | `TRUE` |
| `"builtin"` | the shipped file | `TRUE` |
| `"alias"` | a dated or alternative name for a model above, such as `"chatgpt-4o-latest"` for gpt-4o | `TRUE` |
| `"pattern:..."` | a family pattern that matches the id, such as `^gpt-4o` | `FALSE` |
| `"default"` | nothing matched: a 128,000-token window and a 4,096-token output cap | `FALSE` |

A registered entry wins over a built-in one. An alias takes its target’s
entry, a registered one first, and keeps its own name as `id`:

``` r

str(hr_model_info("chatgpt-4o-latest")[c("id", "context_window", "max_output",
                                         "source", "certain")])
#> List of 5
#>  $ id            : chr "chatgpt-4o-latest"
#>  $ context_window: int 128000
#>  $ max_output    : int 16384
#>  $ source        : chr "alias"
#>  $ certain       : logi TRUE
```

An id the registry does not hold gets a guess, with a warning of class
`gr_unknown_model`. A dated gpt-4o name the registry has not heard of
matches the `^gpt-4o` pattern:

``` r

str(hr_model_info("gpt-4o-2027-01-15")[c("context_window", "max_output",
                                         "source", "certain")])
#> Warning in hr_model_info("gpt-4o-2027-01-15"): Model 'gpt-4o-2027-01-15' is not
#> in the registry; matched family pattern '^gpt-4o' -> 128000-token context,
#> 16384-token output. Verify with hr_model_info('gpt-4o-2027-01-15'), and correct
#> it with hr_register_model() if that is wrong.
#> List of 4
#>  $ context_window: int 128000
#>  $ max_output    : int 16384
#>  $ source        : chr "pattern:^gpt-4o"
#>  $ certain       : logi FALSE
```

An id that matches no pattern gets the default profile:

``` r

str(hr_model_info("acme-chat-7")[c("context_window", "max_output", "source",
                                   "certain")])
#> Warning in hr_model_info("acme-chat-7"): Model 'acme-chat-7' is not in the
#> registry. Falling back to a conservative 128000-token context with a 4096-token
#> output reserve. Register the real limits with hr_register_model('acme-chat-7',
#> context_window = ..., max_output = ...) so budgets and cost estimates are
#> correct.
#> List of 4
#>  $ context_window: int 128000
#>  $ max_output    : int 4096
#>  $ source        : chr "default"
#>  $ certain       : logi FALSE
```

The warning repeats on every call that names the model, so a run that
uses an unknown id says so for each request. Read it as “check this
before you trust a budget or a cost”: a guessed window can be far from
the real one, and a guessed entry has no price. A typo shows up the same
way, and its guess can look right. `"gpt-5.6-tera"` matches the
`^gpt-5\.6` family and gets gpt-5.6-terra’s window, but no price you set
for gpt-5.6-terra reaches it.

To stop instead of guessing, set `unknown_model_action` to `"error"`. A
lookup of an unknown id then raises an error of class
`gr_unknown_model`, and so does
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
before it sends anything:

``` r

prev <- hr_options(unknown_model_action = "error")
tryCatch(hr_model_info("gpt-5.6-tera"),
         gr_unknown_model = function(e) class(e))
#> [1] "gr_unknown_model" "gr_error"         "error"            "condition"
hr_options(prev)
```

### Two limits: `hr_model_limits()`

[`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md)
returns the window and the output cap alone:

``` r

hr_model_limits("gpt-4o")
#> $context_window
#> [1] 128000
#> 
#> $output_tokens
#> [1] 16384
```

The second element is named `output_tokens`, not `max_output` as in
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md).
It goes through the same lookup, so an unknown id warns here too.

## Adding a model or changing one

[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
adds an entry or changes one. It does not check the figures with the
provider: what you give is what harnessr uses.

### A model harnessr does not know

A model behind a company gateway, or a local one, needs both limits.
`reasoning`, `supports_temperature`, `kind` and `dimensions` default to
a chat model that takes a temperature:

``` r

hr_register_model("gateway-chat", context_window = 200000, max_output = 8192)
str(hr_model_info("gateway-chat")[c("context_window", "max_output", "reasoning",
                                    "supports_temperature", "source", "certain")])
#> List of 6
#>  $ context_window      : int 200000
#>  $ max_output          : int 8192
#>  $ reasoning           : logi FALSE
#>  $ supports_temperature: logi TRUE
#>  $ source              : chr "registered"
#>  $ certain             : logi TRUE
```

A reasoning model behind the gateway says so, and an embedding model
gives its kind and dimensions:

``` r

hr_register_model("gateway-reasoner", context_window = 128000, max_output = 16000,
                  reasoning = TRUE, supports_temperature = FALSE)
hr_register_model("gateway-embed", context_window = 8192, max_output = 0,
                  kind = "embedding", dimensions = 1024)
```

harnessr refuses a chat model whose output cap is as large as its
window, because then no room would be left for a prompt:

``` r

tryCatch(hr_register_model("too-small", context_window = 4096, max_output = 4096),
         error = conditionMessage)
#> [1] "`max_output` (4096) must be smaller than `context_window` (4096): a model cannot emit its entire context. Set a smaller `max_output` to leave room for a prompt."
```

### A change to one field of a known model

Leave out either limit, and
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
changes the current entry, built in or registered, keeping every value
you leave out. To hold gpt-4o’s replies to 8,000 tokens:

``` r

hr_register_model("gpt-4o", max_output = 8000)
str(hr_model_info("gpt-4o")[c("context_window", "max_output", "source")])
#> List of 3
#>  $ context_window: int 128000
#>  $ max_output    : int 8000
#>  $ source        : chr "registered"
```

The entry is now registered, and it wins over the built-in one until the
session ends. A model with no entry to change is an error that says what
to give:

``` r

tryCatch(hr_register_model("never-seen", max_output = 8000), error = conditionMessage)
#> [1] "Model 'never-seen' is not in the registry, so it has no limits to keep: give both `context_window` and `max_output` to register it."
```

An alias has no entry of its own, so a change to it is refused with its
target named:

``` r

tryCatch(hr_register_model("chatgpt-4o-latest", input_usd = 2.5, output_usd = 10),
         error = conditionMessage)
#> [1] "'chatgpt-4o-latest' is an alias of 'gpt-4o'; set the prices on 'gpt-4o'. The alias uses the target's entry."
```

## Prices

### Why harnessr ships none

Providers change prices more often than harnessr is released. A price
list in the package would be wrong for most of its life, and a wrong
price moves the point where `max_cost_usd` stops a run. A missing price
shows: the cost comes out `NA`. A wrong one gives a figure that looks
right. So harnessr ships limits, which change rarely, and you set the
prices you pay.

### Setting one model’s prices

`input_usd` and `output_usd` are US dollars per million tokens. For a
known model, the prices are all you give:

``` r

# Illustrative figures: use your provider's current prices.
hr_register_model("gpt-4o-mini", input_usd = 0.15, output_usd = 0.60)
str(hr_model_info("gpt-4o-mini")[c("context_window", "max_output", "input_usd",
                                   "output_usd", "as_of", "source")])
#> List of 6
#>  $ context_window: int 128000
#>  $ max_output    : int 16384
#>  $ input_usd     : num 0.15
#>  $ output_usd    : num 0.6
#>  $ as_of         : chr "2026-11"
#>  $ source        : chr "registered"
```

The model keeps its limits, and the entry is stamped with the current
month. Four rules hold for every price:

- A chat model needs both prices, or neither. Half a price is an error,
  because a cost with half its price missing cannot be estimated. An
  embedding model needs only `input_usd`, since it returns no output
  tokens.
- `cached_input_usd` sets a rate for input the provider served from its
  prompt cache. Without it, cached input is priced as other input, which
  never undercounts.
- A local model costs nothing: give it `input_usd = 0` and
  `output_usd = 0`. Its cost is then 0, not `NA`, and the spending limit
  counts it at zero with no warning.
- When you change a priced entry, a price you leave out keeps its value.
  If the change sets only some of the prices, the entry keeps the older
  month, because the prices you left out are as old as before.

``` r

tryCatch(hr_register_model("gpt-4.1-mini", input_usd = 0.40), error = conditionMessage)
#> [1] "Model 'gpt-4.1-mini' has `input_usd` but no `output_usd`. Give both prices (USD per 1M tokens), or neither to register it unpriced, in which case harnessr reports the cost as unknown rather than guessing."
hr_register_model("local-llama", context_window = 32768, max_output = 4096,
                  input_usd = 0, output_usd = 0)
# Illustrative figure.
hr_register_model("gateway-embed", input_usd = 0.05)
```

### Setting many prices from a file: `hr_load_models()`

[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
reads a CSV file with a header row and registers each row as
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
would. `id` is the only column every file needs, and a blank cell, or
`NA`, means the value is not given:

| column | what it holds |
|----|----|
| `id` | the model id, exactly as the API expects it; each id once |
| `input_usd`, `output_usd` | price per million tokens, in USD; both for a chat model, or neither |
| `cached_input_usd` | price per million input tokens served from the provider’s prompt cache |
| `as_of` | the month you checked the prices, as `YYYY-MM`; blank stamps the current month, and a later month is an error |
| `context_window`, `max_output` | limits in tokens; both for a model harnessr does not know |
| `reasoning`, `supports_temperature` | `TRUE` or `FALSE` |
| `kind` | `chat` or `embedding` |
| `dimensions` | how many dimensions an embedding model’s vectors have |

[`?hr_load_models`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
documents the format in full. A row that leaves a limit blank changes
the model’s current entry, as
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
does without one. A row that gives both limits registers the model in
full. This file prices two built-in chat models, with a cached input
rate for one, and adds a gateway model with its limits:

``` r

prices <- file.path(tempdir(), "models-guide-prices.csv")
# Illustrative figures: use your provider's current prices.
writeLines(c(
  "id,input_usd,output_usd,cached_input_usd,context_window,max_output,as_of",
  "gpt-4o,2.50,10.00,1.25,,,",
  "gpt-5.6-terra,2,12,,,,",
  "partner-model,3,15,,200000,8192,2026-10"
), prices)
loaded <- hr_load_models(prices)
loaded
#> [1] "gpt-4o"        "gpt-5.6-terra" "partner-model"
m <- hr_models()
m[m$id %in% loaded, c("id", "context_window", "max_output", "input_usd_per_1m",
                      "output_usd_per_1m", "cached_input_usd_per_1m", "as_of")]
#>               id context_window max_output input_usd_per_1m output_usd_per_1m
#> 9         gpt-4o         128000       8000              2.5                10
#> 19 gpt-5.6-terra        1050000     128000              2.0                12
#> 21 partner-model         200000       8192              3.0                15
#>    cached_input_usd_per_1m   as_of
#> 9                     1.25 2026-11
#> 19                      NA 2026-11
#> 21                      NA 2026-10
```

[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
returns, invisibly, the ids it registered, in file order. gpt-4o kept
the 8,000-token output cap set earlier, because its row left the limits
blank. `subset(hr_models(), !is.na(input_usd_per_1m))` lists every model
with a price. Check the ids against the ones your runs name: a price set
under a misspelt id prices nothing.

harnessr checks the whole file before it registers anything. A file it
cannot use stops with an error of class `hr_bad_models_file` that names
the row and column at fault, with row 1 the first row after the header.
The registry is left as it was:

``` r

bad <- file.path(tempdir(), "models-guide-bad.csv")
writeLines(c("id,input_usd,output_usd", "gpt-4.1,2,8", "gpt-4.1-mini,two,1.6"), bad)
err <- tryCatch(hr_load_models(bad), hr_bad_models_file = function(e) e)
conditionMessage(err)
#> [1] "Models file '/tmp/RtmpcYNwE1/models-guide-bad.csv', row 2, column 'input_usd': 'two' is not a price; give USD per 1M tokens as a number of 0 or more, such as 2.5."
c(row = err$row, column = err$column)
#>         row      column 
#>         "2" "input_usd"
is.na(hr_model_info("gpt-4.1")$input_usd)
#> [1] TRUE
```

gpt-4.1, on the good first row, has no price: nothing in the file was
registered. Loading a file again changes the entries of the models it
names as
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
does, and leaves the others as they are: a value a row leaves blank
keeps its current value. Removing a cached rate from the file therefore
does not remove it from the registry; register the model in full, with
both limits, or start a new session.

### Keeping your prices current

A registration lasts for the R session. One file of prices per project
sets the same prices in every session, keeps every script on the same
figures and puts a date on each:

1.  Keep `prices.csv` beside your scripts, under version control, with
    an `as_of` column holding the month you checked each row.
2.  Load it at the top of each script, or in the project’s `.Rprofile`,
    before anything reports a cost.
3.  When your provider changes a price, or the stale warning (below)
    appears, look up the current prices, change the row and its `as_of`,
    and load the file again.

``` r

harnessr::hr_load_models("prices.csv")
```

The file’s commit history records when each price changed, and the
`as_of` column of a cost report says which month’s prices the cost used.

## What a cost estimate says: `hr_estimate_cost()`

[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
turns token counts into dollars at the model’s prices:

``` r

hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.34
```

That is 120,000 input tokens at \$2.50 per million plus 4,000 output
tokens at \$10. Vectors of counts are summed, so one call prices a whole
run of requests:

``` r

hr_estimate_cost("gpt-4o", input_tokens = c(60000, 60000), output_tokens = c(2000, 2000))
#> [1] 0.34
```

`cached_input_tokens` says how many of the input tokens the provider
served from its prompt cache. gpt-4o has a cached rate here, so 100,000
of the 120,000 are charged at \$1.25:

``` r

hr_estimate_cost("gpt-4o", 120000, 4000, cached_input_tokens = 100000)
#> [1] 0.215
```

A model with no cached rate charges them as other input. The estimate is
`NA`, never 0, when the model has no price, when a token count is `NA`,
or when a chat model has no output price and the call has output tokens.
A local model at zero prices costs 0:

``` r

hr_estimate_cost("gpt-4.1", 120000, 4000)
#> [1] NA
hr_estimate_cost("gpt-4o", NA, 4000)
#> [1] NA
hr_estimate_cost("local-llama", 120000, 4000)
#> [1] 0
hr_estimate_cost("gateway-embed", 1e6)
#> [1] 0.05
```

`detail = TRUE` returns a data frame that also says where the figure’s
prices came from: `priced` (whether the model has a price), `as_of` (the
month of the price) and `certain` (`FALSE` when the entry was guessed
from a pattern or the default):

``` r

hr_estimate_cost("gpt-4o", 120000, 4000, detail = TRUE)
#>    model  usd priced   as_of certain
#> 1 gpt-4o 0.34   TRUE 2026-11    TRUE
hr_estimate_cost("acme-chat-7", 120000, 4000, detail = TRUE)
#> Warning in hr_model_info(model): Model 'acme-chat-7' is not in the registry.
#> Falling back to a conservative 128000-token context with a 4096-token output
#> reserve. Register the real limits with hr_register_model('acme-chat-7',
#> context_window = ..., max_output = ...) so budgets and cost estimates are
#> correct.
#>         model usd priced as_of certain
#> 1 acme-chat-7  NA  FALSE  <NA>   FALSE
```

The second call warned that `acme-chat-7` is not in the registry, and
its row says why the figure is missing: no price, and an entry that is a
guess. Every report of a cost in dollars, such as
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md),
carries the same `priced`, `as_of` and `certain` columns, as “What a run
records” in
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
shows for a document run. The figure is an estimate: it uses the token
counts you give and the prices you set, and it does not know about a
provider’s discounts, minimum charges or taxes.

## A model with no price

A request to a chat model with no price is sent. The first request to
each such model in a session warns with class `hr_unpriced_model`,
because `max_cost_usd` cannot hold a cost it cannot compute. The mock
client is exempt, so this example uses
[`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md),
which wraps an R function as a client that counts as paying:

``` r

hr_register_model("unpriced-model", context_window = 128000, max_output = 4096)
backend <- hr_backend_client(function(messages, params) "Revenue was 45.2 million dollars.")

tr <- hr_trace()
res <- hr_call(backend, "What was revenue?", model = "unpriced-model", trace = tr)
#> Warning: Model 'unpriced-model' has no price set, so the $5 spending limit
#> (max_cost_usd) does not cover its requests: they are sent, and the trace
#> records their cost as NA. Set its prices with hr_register_model(input_usd =,
#> output_usd =) or hr_load_models(). Token and call limits still apply.
#> hr_options(allow_unpriced = FALSE) refuses such requests instead. Shown once
#> per model per session.
res <- hr_call(backend, "What was revenue?", model = "unpriced-model", trace = tr)
hr_trace_cost(tr)[, c("model", "calls", "paid_in", "paid_out", "usd", "priced")]
#>            model calls paid_in paid_out usd priced
#> 1 unpriced-model     2      14       26  NA  FALSE
```

The two requests gave one warning. The trace counts their tokens and
records their cost as `NA`. `max_calls` and `max_tokens_total` still
hold such requests, and then `max_tokens_total` is the limit that bounds
what a run spends.

`allow_unpriced = FALSE` refuses them instead.
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
then sends nothing and returns a failed result whose `refusal` is a
condition of class `hr_unpriced_model`:

``` r

prev <- hr_options(allow_unpriced = FALSE)
res <- hr_call(backend, "What was revenue?", model = "unpriced-model",
               trace = hr_trace())
res$refused
#> [1] TRUE
class(res$refusal)
#> [1] "hr_unpriced_model" "hr_budget_refused" "condition"
hr_options(prev)
```

`hr_governor(allow_unpriced = FALSE)` does the same for one run. Under
either,
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
stops before its first request, with an error of the same class.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
and replays are never refused or warned about for this, and neither is
an embedding model with no price.

An
[`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
is priced as the model its ellmer object was built with, whatever a
recipe names, so set the price of that model. One built on a model with
no price runs outside the spending limit. “Connecting to a model” in
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
registers a hosted model at its prices and a local one at zero.

## When prices go stale

The prices you set go out of date too. A cost computed from prices older
than `price_max_age_days` (120 days by default) warns with class
`hr_stale_price`, once per model per session. The age counts from the
first day of the `as_of` month. A file whose prices were checked in
January 2025 shows it:

``` r

old_prices <- file.path(tempdir(), "models-guide-old.csv")
# Illustrative figures.
writeLines(c("id,input_usd,output_usd,as_of", "gpt-4.1,2,8,2025-01"), old_prices)
hr_load_models(old_prices)
hr_estimate_cost("gpt-4.1", 120000, 4000)
#> Warning: The prices of model 'gpt-4.1' are as of 2025-01, 695 days ago, more
#> than the 120 days of hr_options(price_max_age_days =). Check your provider's
#> current prices and set them with hr_register_model(input_usd =, output_usd =)
#> or hr_load_models(). Shown once per model per session.
#> [1] 0.272
hr_estimate_cost("gpt-4.1", 120000, 4000)
#> [1] 0.272
```

harnessr still returns the figure, and the second estimate does not warn
again. To clear the warning, check your provider’s current prices and
set every price the entry has again, `cached_input_usd` included when it
has one:
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
then stamps the current month, and so does a row of
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
with a blank `as_of`. A change that leaves one of the entry’s prices out
keeps the older month, and the warning stays, even when the row gives a
newer `as_of`. A model with no price is never stale, and its `as_of`,
the month its limits were checked, does not count.

## Counting tokens

harnessr counts tokens in three places: to size a prompt before it is
sent, to cut text to a number of tokens, and to fill in a usage figure
the provider did not report. All three use
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md):

``` r

txt <- c(prose = "The quick brown fox jumps over the lazy dog.",
         table = "| 2024 | 45.2 | 38.1 |",
         japanese = "東京は日本の首都です。",
         long_word = "pneumonoultramicroscopicsilicovolcanoconiosis",
         blank = "")
hr_count_tokens(txt)
#> [1] 13 18 16 17  0
```

It returns one whole number per string, with blank and `NA` strings at
0.

### How exact the default count is

[`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md)
names the counter in use:

``` r

hr_tokenizer()
#> [1] "heuristic"
```

The default, `"heuristic"`, needs nothing installed. It does not
tokenize: it estimates, and it is built to come out high, because a
count that comes out low lets a prompt past the window and the provider
rejects the request after it has been paid for. It charges an ordinary
English word at least one token, a dense string (an id, a number, code)
one token per 1.3 characters, each character outside ASCII, such as
Japanese or Cyrillic, 1.15 tokens, and an emoji 6.5. For tables, digit
lists and short lines it also counts the pieces a byte-pair tokenizer
splits text into first (digit groups, punctuation runs, line breaks) and
keeps the larger figure, line by line. Each string that is not blank
then gets 3 more tokens for the framing a chat message carries.

Measured against OpenAI’s `cl100k_base` and `o200k_base` encodings, it
comes in at or above the real count on tables, digit lists,
tab-separated text and short punctuated lines. Rare long words are where
it can fall short: on a table of medical terms it came in about a tenth
under. The `safety_margin` option, a tenth of the window by default, is
the room
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
leaves for that error.

The two other built-in counters are cruder. `"words"` counts words, and
`"chars"` divides the characters by 4:

``` r

prev_tok <- hr_tokenizer()
counts <- sapply(c("heuristic", "words", "chars"), function(t) {
  hr_set_tokenizer(t)
  hr_count_tokens(txt[1:4])
})
rownames(counts) <- names(txt)[1:4]
counts
#>           heuristic words chars
#> prose            13     9    11
#> table            18     7     6
#> japanese         16     1     3
#> long_word        17     1    12
hr_set_tokenizer(prev_tok)
```

Both count below the heuristic on every row, and `"chars"` counts 11
Japanese characters as 3 tokens. A low count is the direction that
overruns a window, so keep the heuristic unless you have a counter that
matches your model.

### Plugging in a real tokenizer

`hr_set_tokenizer("tiktoken")` switches to OpenAI’s tokenizer, through
the reticulate package and Python’s `tiktoken`:

``` r

hr_set_tokenizer("tiktoken")
hr_count_tokens("The quick brown fox jumps over the lazy dog.", model = "gpt-4o")
```

Given a `model` that `tiktoken` knows, it counts in that model’s
encoding. Without one, which is how harnessr’s own budgets call it, it
counts in both encodings current OpenAI models use (`cl100k_base` and
`o200k_base`) and keeps the larger. For a model from another provider
the count is an estimate with none of the heuristic’s padding. Without
reticulate or `tiktoken`, `hr_set_tokenizer("tiktoken")` stops with an
error and the tokenizer stays as it was: a silent fallback would change
every budget without a word.

For any other model, register a counter of your own: a function that
takes a character vector and returns one count per element. A provider’s
tokenizer wrapped in R goes here. This one stands in for it with a rule
of thumb of 3 characters per token:

``` r

hr_set_tokenizer("three_chars", function(x) ceiling(nchar(x) / 3))
hr_tokenizer()
#> [1] "three_chars"
hr_count_tokens(txt)
#> [1] 15  8  4 15  0
```

[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md)
registers the function under the name and makes it the active counter;
from then on, `hr_set_tokenizer("three_chars")` switches back to it by
name. The counter gets the text alone, not the model. harnessr sets a
negative or `NA` count to 0, and stops if the function returns the wrong
number of counts. A counter you register is copied to the workers of a
parallel run, with the models you registered.

Switch back to the counter in use before, the default heuristic, for the
rest of the guide:

``` r

hr_set_tokenizer(prev_tok)
hr_tokenizer()
#> [1] "heuristic"
```

### Where a count shows up

A result’s `usage` says where its token counts came from. A backend that
returns plain text reports none, so harnessr counted the prompt and the
reply itself:

``` r

res <- hr_call(backend, "What was revenue?", model = "gpt-4o-mini")
str(res$usage)
#> List of 3
#>  $ input     : int 7
#>  $ output    : int 13
#>  $ provenance: chr "estimated"
```

`provenance` is `"reported"` when the provider gave the figures,
`"counted"` when harnessr counted them with `tiktoken`, and
`"estimated"` with any other counter, such as the heuristic that counted
the prompt here as 7 tokens and the reply as 13. A count made with a
crude counter can undercount a request’s cost, so an estimated usage is
worth checking against the provider’s bill on a real run.

## Choosing the settings

Four options decide how the registry and the counter behave. Each
walkthrough says what the option controls, the signs that point to
changing it, where its default came from, and how to test a change.

### Unknown models: `unknown_model_action`

**What it controls.** What a lookup does when the registry does not hold
the id: `"warn"` (the default) guesses from a family pattern or the
default profile and warns with class `gr_unknown_model`; `"error"` stops
with an error of that class, so no request goes out with guessed limits.

**Signs it needs changing.** A `gr_unknown_model` warning in a run you
meant to send to a known model is a typo or a new model. On a scheduled
or unattended run, set `"error"`, since nobody reads the warning before
the run spends.

**Where the default came from.** `"warn"` lets a first run with a new
model work. `gr_settings_table("options")` declares no evidence for it.

**How to test it.** Look up every id a script uses under `"error"`
before the run:

``` r

prev <- hr_options(unknown_model_action = "error")
ids <- c("gpt-4o", "chatgpt-4o-latest", "gpt-5.6-tera")
vapply(ids, function(id) {
  tryCatch(hr_model_info(id)$source, gr_unknown_model = function(e) "unknown")
}, "")
#>            gpt-4o chatgpt-4o-latest      gpt-5.6-tera 
#>      "registered"           "alias"         "unknown"
hr_options(prev)
```

### Models with no price: `allow_unpriced`

**What it controls.** Whether a request to a chat model with no price is
sent while `max_cost_usd` is set. `TRUE`, the default, sends it, records
its cost as `NA` and warns once per model with class
`hr_unpriced_model`. `FALSE` refuses it with a condition of that class.

**Signs it needs changing.** An `hr_unpriced_model` warning, or `NA` in
the `usd` column of
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md),
on a run whose cost has to stay under a limit. Set the model’s prices;
set `allow_unpriced = FALSE` when a run must never spend outside the
limit.

**Where the default came from.** harnessr ships no prices, so `FALSE`
would refuse every request to a built-in model until you set its prices.
`gr_settings_table("options")` lists it as untested.

**How to test it.** Check which models a run names have a price before
you send anything:

``` r

run_models <- c("gpt-4o", "gpt-4o-mini", "unpriced-model")
do.call(rbind, lapply(run_models, hr_estimate_cost, input_tokens = 0, detail = TRUE))
#>            model usd priced   as_of certain
#> 1         gpt-4o   0   TRUE 2026-11    TRUE
#> 2    gpt-4o-mini   0   TRUE 2026-11    TRUE
#> 3 unpriced-model  NA  FALSE    <NA>    TRUE
```

### How old a price may be: `price_max_age_days`

**What it controls.** The age in days, counted from the first day of a
price’s `as_of` month, past which a cost computed from the price warns
with class `hr_stale_price`. `NULL` turns the warning off. The warning
changes no figure and stops nothing.

**Signs it needs changing.** A stale warning on prices you checked
recently means the `as_of` in your file is behind; update it rather than
the option. Raise the limit for a provider whose prices you know have
not moved, such as a contract price.

**Where the default came from.** 120 days, about four months, so prices
set once are checked again a few times a year.
`gr_settings_table("options")` lists it as untested.

**How to test it.**
[`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
shows the month of every price, and the age in days follows from it:

``` r

m <- hr_models()
p <- m[!is.na(m$input_usd_per_1m), c("id", "as_of")]
p$age_days <- as.numeric(Sys.Date() - as.Date(paste0(p$as_of, "-01")))
p
#>               id   as_of age_days
#> 6        gpt-4.1 2025-01      695
#> 9         gpt-4o 2026-11       26
#> 10   gpt-4o-mini 2026-11       26
#> 19 gpt-5.6-terra 2026-11       26
#> 20   local-llama 2026-11       26
#> 21 partner-model 2026-10       57
#> 23 gateway-embed 2026-11       26
```

To see the option at work, load a price checked in January 2025 for a
model no estimate has used yet, and estimate its cost under a higher
limit and then under the default:

``` r

contract <- file.path(tempdir(), "models-guide-contract.csv")
# Illustrative figures.
writeLines(c("id,context_window,max_output,input_usd,output_usd,as_of",
             "contract-model,128000,4096,1,4,2025-01"), contract)
hr_load_models(contract)
prev_age <- hr_options(price_max_age_days = 3650)
hr_estimate_cost("contract-model", 100000, 2000)
#> [1] 0.108
hr_options(prev_age)
hr_estimate_cost("contract-model", 100000, 2000)
#> Warning: The prices of model 'contract-model' are as of 2025-01, 695 days ago,
#> more than the 120 days of hr_options(price_max_age_days =). Check your
#> provider's current prices and set them with hr_register_model(input_usd =,
#> output_usd =) or hr_load_models(). Shown once per model per session.
#> [1] 0.108
```

Under a limit of 3650 days the price is not stale and the first estimate
gives no warning. Back at 120 days, the second warns. The figure is the
same both times. `hr_options(price_max_age_days = NULL)` turns the check
off.

### The token counter: `tokenizer`

**What it controls.** Which counter
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md)
uses, and so every budget, every cut to a number of tokens and every
usage figure the provider did not report. Set it with
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
which checks the name and, for `"tiktoken"`, that Python’s package is
there.

**Signs it needs changing.** A provider error that a prompt was too long
means the counter came in under. Usage marked `"estimated"` that differs
much from the provider’s bill is the other sign. With OpenAI models and
Python at hand, `"tiktoken"` gives exact counts.

**Where the default came from.** The heuristic needs nothing installed
and is built to come out high; its calibration is described above.
`gr_settings_table("options")` declares no evidence for it.

**How to test it.** Count a sample of your own text with each counter
you consider, and compare the counts with the prompt tokens your
provider reports for the same text:

``` r

sample_text <- c("Net revenue rose 12% to $45.2 million in fiscal 2024.",
                 "| segment | 2023 | 2024 |\n| retail | 38.1 | 45.2 |")
sapply(c("heuristic", "words", "chars"), function(t) {
  hr_set_tokenizer(t)
  hr_count_tokens(sample_text)
})
#>      heuristic words chars
#> [1,]        22    10    14
#> [2,]        27    14    13
hr_set_tokenizer(prev_tok)
```

The heuristic counts both texts highest, 22 and 27, since it is built to
come out high; `"words"` and `"chars"` give 10 to 14. The counter whose
figures sit closest above your provider’s reported prompt tokens is the
one to keep.

## Where the document layer builds on this

The segmenters size chunks with
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md),
the readers fit each prompt to the model’s window from
[`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
and every cost the document layer reports comes from these prices.
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
shows the costs a whole document run reports.

## Next

- [`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md):
  the calls these limits and prices apply to, and the trace that records
  their tokens and cost.
- [`vignette("context")`](https://elkronos.github.io/harnessr/articles/context.md):
  the budgets these limits set, and how a prompt is cut to fit them.
- [`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md):
  the reasoning effort sent to the models that reason.
- [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md):
  spending limits, the governor, caching and replay.
- [`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md):
  every setting with its default.
