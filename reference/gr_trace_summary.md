# Summarise a trace

Summarise a trace

## Usage

``` r
gr_trace_summary(trace)
```

## Arguments

- trace:

  A `gr_trace`.

## Value

A one-row data frame: `run_id`, `calls`, `cached`, `steps`, `tokens_in`,
`tokens_out`, `errors`, `elapsed_s`, `embed_calls`, `embed_tokens`,
`tokens_reasoning`, `tokens_cached_in`, `usage_estimated`.

`calls` counts every request, including the `embed_calls` of them made
to an embeddings endpoint. `tokens_in` and `tokens_out` are the size of
the model calls' prompts and replies; the text sent to be embedded is
counted in `embed_tokens` instead, because an embedding model is priced
at a small fraction of a chat model's rate. There is no cost column:
[`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md)
prices every request at its own model, embeddings included, and is what
the run cost. Combining `tokens_in`/`tokens_out` with
[`gr_estimate_cost()`](https://elkronos.github.io/readgpt/reference/gr_estimate_cost.md)
estimates the model calls alone at one model's prices.

`cached` is how many of those calls were answered from a
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
or a
[`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md).
Their tokens are still counted in `tokens_in` and `tokens_out`, because
that is how large the prompts and replies were; they were simply not
paid for again. A run with `cached == calls` cost nothing, so feeding
its token counts to
[`gr_estimate_cost()`](https://elkronos.github.io/readgpt/reference/gr_estimate_cost.md)
gives you what the run *would* have cost, not what it did.

`errors` counts every failed request, including any the run recovered
from (see `errors` in
[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md)).

`tokens_reasoning` and `tokens_cached_in` are the reasoning tokens and
cached input tokens the provider reported for the model calls, 0 where
it reported none. They are parts of `tokens_out` and `tokens_in`, not
additions to them. `usage_estimated` is the share of requests whose
token counts were estimated locally because the provider reported none
(see `tokens` under "Steps" in
[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md)),
from 0 to 1, or `NA` when no request says.

## See also

[`gr_trace()`](https://elkronos.github.io/readgpt/reference/gr_trace.md),
[`as_json()`](https://elkronos.github.io/readgpt/reference/as_json.md),
[`gr_trace_cost()`](https://elkronos.github.io/readgpt/reference/gr_trace_cost.md),
[`gr_estimate_cost()`](https://elkronos.github.io/readgpt/reference/gr_estimate_cost.md),
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "45.2 million dollars")
ans <- answer_document(gr_example(), "What was revenue?", "thorough", client = cl)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'map_reduce' (all|N+logN|tree) over 1 chunk(s).
gr_trace_summary(ans$trace)
#>                          run_id calls cached steps tokens_in tokens_out errors
#> 1 run_20261106091722.517_c2f4cc     1      0     4       607         10      0
#>   elapsed_s embed_calls embed_tokens tokens_reasoning tokens_cached_in
#> 1      0.02           0            0                0                0
#>   usage_estimated
#> 1               1

# What the run cost, each request priced at its own model (nothing, for a
# mock), and what its model calls would cost at another model's prices.
gr_trace_cost(ans$trace)
#>        model calls paid_calls paid_in paid_out usd paid_reasoning
#> 1 mock-model     1          1     607       10   0              0
#>   paid_cached_in
#> 1              0
gr_estimate_cost("gpt-4o", ans$trace$tokens_in, ans$trace$tokens_out)
#> [1] 0.0016175
```
