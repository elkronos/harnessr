# Summarise a trace

Summarise a trace

## Usage

``` r
hr_trace_summary(trace)
```

## Arguments

- trace:

  A `gr_trace`.

## Value

A one-row data frame: `run_id`, `calls`, `cached`, `steps`, `tokens_in`,
`tokens_out`, `errors`, `elapsed_s`, `embed_calls`, `embed_tokens`,
`tokens_reasoning`, `tokens_cached_in`, `usage_estimated`, `request_s`,
`local_s`, `overhead_s`, `request_share`, `local_share`,
`overhead_share`.

`calls` counts every request, including the `embed_calls` of them made
to an embeddings endpoint. `tokens_in` and `tokens_out` are the size of
the model calls' prompts and replies; the text sent to be embedded is
counted in `embed_tokens` instead, because an embedding model is priced
at a small fraction of a chat model's rate. There is no cost column:
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md)
prices every request at its own model, embeddings included, and is what
the run cost. Combining `tokens_in`/`tokens_out` with
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
estimates the model calls alone at one model's prices.

`cached` is how many of those calls were answered from an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
or a
[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md).
Their tokens are still counted in `tokens_in` and `tokens_out`, because
that is how large the prompts and replies were; they were simply not
paid for again. A run with `cached == calls` cost nothing, so feeding
its token counts to
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
gives you what the run *would* have cost, not what it did.

`errors` counts every failed request, including any the run recovered
from (see `errors` in
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)).

`tokens_reasoning` and `tokens_cached_in` are the reasoning tokens and
cached input tokens the provider reported for the model calls, 0 where
it reported none. They are parts of `tokens_out` and `tokens_in`, not
additions to them. `usage_estimated` is the share of requests whose
token counts were estimated locally because the provider reported none
(see `tokens` under "Steps" in
[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)),
from 0 to 1, or `NA` when no request says. The share of input tokens the
provider served from its cache is `tokens_cached_in / tokens_in`; the
trace's print shows it when it is above 0.

`elapsed_s` is the time from the run's start (`trace$started`) to the
end of its last step: a request's `ended_utc`, or the `at` time of a
local step. `at` is local time with no offset, so it is placed using the
offset the trace's requests show (their `at` beside their `ended_utc`),
or the `utc_offset` the trace recorded when it holds no request. It is
read from the steps, so a summary taken an hour after the run, or of a
trace saved with [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) and
read back in another time zone, gives the same figure. A trace with
local steps, no request and no `utc_offset` (one made by harnessr 0.7.0)
cannot place them: its `elapsed_s` is then `request_s + local_s`. A
trace with no steps gives 0.

The last six columns split that time. `request_s` is the seconds the
requests took (model calls and embeddings requests, retries included),
`local_s` the seconds local steps recorded (a command step from
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
records its run time; segmentation, truncation and other local steps
record none, so their time falls into the overhead), and `overhead_s`
the rest of `elapsed_s`. Requests sent in parallel overlap, so
`request_s` can pass `elapsed_s`, and `overhead_s` is then 0. The three
shares are each part over the three together, so they add to 1, or `NA`
when no time was measured.

## See also

[`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md),
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md),
[`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md),
[`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)

## Examples

``` r
cl <- hr_mock_client(function(m, p) "45.2 million dollars")
ans <- answer_document(gr_example(), "What was revenue?", "thorough", client = cl)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
hr_trace_summary(ans$trace)
#>                          run_id calls cached steps tokens_in tokens_out errors
#> 1 run_20261127174242.533_7f0259     1      0     4       607         10      0
#>   elapsed_s embed_calls embed_tokens tokens_reasoning tokens_cached_in
#> 1      0.01           0            0                0                0
#>   usage_estimated request_s local_s overhead_s request_share local_share
#> 1               1         0       0       0.01             0           0
#>   overhead_share
#> 1              1

# What the run cost, each request priced at its own model (nothing, for a
# mock), and what its model calls would cost at another model's prices.
# harnessr ships no prices, so set that model's first. The figures are
# illustrative: use your provider's current prices.
hr_trace_cost(ans$trace)
#>        model calls paid_calls paid_in paid_out usd paid_reasoning
#> 1 mock-model     1          1     607       10   0              0
#>   paid_cached_in priced   as_of certain
#> 1              0   TRUE 2026-11    TRUE
hr_register_model("gpt-4o", input_usd = 2.50, output_usd = 10)
hr_estimate_cost("gpt-4o", ans$trace$tokens_in, ans$trace$tokens_out)
#> [1] 0.0016175
```
