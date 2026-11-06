# What a run actually cost

Costs a trace using each step's own model and counting only the calls
that were issued: a call served from a
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)
or a
[`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md)
spent nothing, however many tokens its prompt contained.

## Usage

``` r
gr_trace_cost(trace)
```

## Arguments

- trace:

  A `gr_trace`.

## Value

A data frame with one row per model: `model`, `calls`, `paid_calls`,
`paid_in`, `paid_out`, `usd`, `paid_reasoning`, `paid_cached_in`.
`sum(x$usd)` is the run's cost. `paid_reasoning` and `paid_cached_in`
are the reasoning and cached input tokens the provider reported among
`paid_out` and `paid_in`; cached input is priced at the model's cached
input rate where
[`gr_register_model()`](https://elkronos.github.io/readgpt/reference/gr_register_model.md)
gave it one. A model with no registered price contributes `NA`, so a
total that silently omitted an unpriced model is impossible. The
exception is a model whose every request failed without sending a token
(an embeddings request to an endpoint that has none, say): that cost
nothing, priced or not, so it contributes 0.

## Details

This is why the token totals on
[`gr_trace_summary()`](https://elkronos.github.io/readgpt/reference/gr_trace_summary.md)
are not a bill. They report how large the prompts and replies were,
which is the right measure of a run's *shape*; a fully cached re-run has
the same shape as the original and cost nothing at all.

## See also

[`gr_trace_summary()`](https://elkronos.github.io/readgpt/reference/gr_trace_summary.md),
[`gr_estimate_cost()`](https://elkronos.github.io/readgpt/reference/gr_estimate_cost.md),
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md),
[`gr_read_many()`](https://elkronos.github.io/readgpt/reference/gr_read_many.md)

## Examples

``` r
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
ans <- answer_document(gr_example(), "What was revenue?", "fast", client = cl)
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
gr_trace_cost(ans$trace)
#>        model calls paid_calls paid_in paid_out usd paid_reasoning
#> 1 mock-model     1          1     607       13   0              0
#>   paid_cached_in
#> 1              0

# Priced by the model each step records: a mock's own model, at no cost.
# A cached re-run costs nothing for a different reason: paid_calls falls
# to zero while calls does not.
cache <- gr_cache(file.path(tempdir(), "harnessr-cost-example"))
again <- answer_document(gr_example(), "What was revenue?", "fast",
                         client = gr_cache_client(cl, cache))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
twice <- answer_document(gr_example(), "What was revenue?", "fast",
                         client = gr_cache_client(cl, cache))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 4000 tokens, overlap 0).
#> Reading with 'stuff' (all|1|none) over 1 chunk(s).
gr_trace_cost(twice$trace)[c("calls", "paid_calls", "usd")]
#>   calls paid_calls usd
#> 1     1          0   0
```
