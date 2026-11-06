# Get or set package options

`gr_options()` with no arguments returns the full option list. Called
with a single string it returns that option. Called with `name = value`
pairs it sets them and invisibly returns the previous values, so it
composes with [`on.exit()`](https://rdrr.io/r/base/on.exit.html).

## Usage

``` r
gr_options(...)
```

## Arguments

- ...:

  Nothing, a single option name, `name = value` pairs, or a named list
  (the form `gr_options()` itself returns, so a saved value can be
  restored directly).

## Value

The option list, a single option value, or (when setting) the old values
invisibly.

## Details

Options are read at *call* time, never captured at load time, so
changing an option mid-session affects subsequent runs.

## Options

- `verbose` (TRUE):

  Print a line for each ingest, segment and read stage. In an
  interactive session, also keep one line up to date with how many
  chunks a long read has done and what the run has spent.

- `model` ("gpt-5.6-terra"):

  Default chat model. Note the default is a reasoning model, which does
  not accept `temperature`.

- `embedding_model` ("text-embedding-3-small"):

  Default embedding model.

- `tokenizer` ("heuristic"):

  Token counter: `"heuristic"` (conservative, no dependencies),
  `"words"`, `"chars"`, `"tiktoken"` (needs reticulate), or a name
  registered via
  [`gr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_set_tokenizer.md).

- `api` ("responses"):

  `"responses"` or `"chat"` request shape.

- `api_base` ("https://api.openai.com/v1"):

  API root; point this at a proxy or a compatible endpoint.

- `api_headers` (none):

  Named character vector of extra HTTP headers sent with every request,
  for gateways that do not authenticate with a bearer token. Inherited
  by every
  [`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md)
  that does not name its own; see that function's `headers` argument for
  the rules.

- `temperature` (NULL):

  Default sampling temperature. `NULL` omits the field. Dropped
  automatically for models that reject it.

- `max_retries` (4):

  Retries for transient failures. HTTP 400 is never retried: a malformed
  request stays malformed.

- `retry_pause_base` (2):

  Seconds; exponential backoff base.

- `request_timeout` (120):

  Per-request timeout, seconds.

- `safety_margin` (0.10):

  Fraction of the context window left unused to absorb tokenizer error.
  Not a spending cap (see `max_cost_usd`).

- `min_output_tokens` (256):

  Floor on the completion room
  [`gr_budget()`](https://elkronos.github.io/harnessr/reference/gr_budget.md)
  reserves *when `reserve_output` is not given explicitly*. An explicit
  `reserve_output` is honoured down to 1.

- `cache_documents` (TRUE):

  Cache ingestion per file + settings. The key covers file size, mtime
  and every option that changes the output.

- `cache_embeddings` (TRUE):

  Cache embeddings per text + model.

- `embedder` (NULL):

  Which registered embedder to use. `NULL` means the one the client
  carries, if any, and otherwise `"api"`. Naming one here overrides
  both. See
  [`gr_embedders()`](https://elkronos.github.io/harnessr/reference/gr_embedders.md);
  recording a run with a *deterministic* embedder is what lets a
  [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  reproduce its chunk ranking.

- `cache_dir` (NULL):

  Directory
  [`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
  stores model responses in. `NULL` means a per-session directory under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html), which costs
  nothing and disappears with the session. Set it to a real path, such
  as `tools::R_user_dir("harnessr", "cache")`, to keep responses across
  sessions and make a long run resumable.

- `parallel` (FALSE):

  Run per-chunk calls concurrently. Needs the future and future.apply
  packages; without them it warns and runs sequentially.

- `workers` (4):

  Worker processes when `parallel` is TRUE.

- `max_cost_usd` (5):

  Spending limit per run, in USD. A run whose reader sends every chunk
  is refused before it starts when sending them would cost more than
  this. Every request is then checked before it is sent, against what
  the run has spent plus the most the request could cost (its prompt,
  and its reply at the output cap), and one that could pass the limit is
  not sent (see
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)),
  so a run ends at or under the limit with a `partial` answer. With
  `parallel = TRUE` a reader that sends batches is also refused before
  it starts when its worst case, every reply at its token cap and the
  price of the dearest model it uses, would pass the limit, and each
  worker is held to its share of what is left. A chat model with no
  registered price (see
  [`gr_models()`](https://elkronos.github.io/harnessr/reference/gr_models.md))
  is refused under a limit unless `allow_unpriced` is `TRUE`. Under a
  limit of 0 a model registered at no cost runs and one with a price is
  refused. `NULL` removes the limit.

- `max_calls` (400):

  Hard cap on model calls per run, checked before every request. A
  request to an embeddings endpoint (the built-in `"api"` embedder)
  counts as one, and is checked and priced against `max_cost_usd` the
  same way; an embedding served from the session cache is free. A
  request a
  [`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
  answers counts. `NULL` removes the cap.

- `max_tokens_total` (NULL):

  Most tokens one run may use: the prompt and reply tokens of every
  call, cache hits included, and the text sent to be embedded. A request
  is refused when what the run has used plus its prompt and its reply at
  the cap would pass it. The limit that still bounds a run on a model
  with no price under `allow_unpriced = TRUE`. `NULL` for no limit.

- `max_output_tokens` (NULL):

  The largest output cap one request may be sent with. A request with a
  larger cap (for a reasoning model, the raised cap
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  sends) is refused rather than cut down. `NULL` for no ceiling.

- `allowed_models` (NULL):

  Character vector of the model ids a run may call, chat and embedding
  models alike. A request to any other is refused. `NULL` for any model.

- `allow_unpriced` (FALSE):

  Whether a chat model with no registered price may be called while
  `max_cost_usd` is set. Off, such a request is refused with a condition
  of class `hr_unpriced_model`; on, it is sent and its cost is recorded
  as unknown (`NA`).

- `unknown_model_action` ("warn"):

  `"warn"` or `"error"` when a model id is not in the registry.

- `actor` (none):

  A named list (or character vector) of the actor fields every
  [`gr_trace()`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  records: `system`, `owner`, `run_by`, `purpose` and `approved_by`,
  each one string. A field named here is recorded on each new trace
  unless
  [`gr_trace()`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  is given its own; one named nowhere is `NA`. Other names are refused
  with an error of class `gr_bad_option`.

## Checked values

Numeric options are checked when they are set, and the two kinds are
treated differently because a wrong value costs different things.

The ceilings, `max_cost_usd`, `max_calls`, `max_tokens_total` and
`max_output_tokens`, refuse anything that is not a single number of zero
or more (one or more for `max_output_tokens`), with an error of class
`gr_bad_option`: a limit that cannot be compared is not a limit, and
ignoring it spends money. `NULL` and `Inf` both mean "no limit".
`allowed_models` must be `NULL` or a character vector of ids, and
`allow_unpriced` `TRUE` or `FALSE`.

The tuning settings (`safety_margin` \[0, 0.5\], `min_output_tokens`
\[0, 1e6\], `max_retries` \[0, 10\], `retry_pause_base` \[0, 60\],
`request_timeout` \[1, 3600\], `workers` \[1, 32\] and `temperature`
\[0, 2\]) read a number written as text as that number. A value they
cannot read, such as `NA` or `"x"`, warns (`gr_bad_option`) and leaves
the current setting unchanged; a value outside the range is clamped into
it, with the same warning. Whole-number settings are rounded down.
`temperature` also takes `NULL`, its default.

## See also

[`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md)
to correct a model's limits,
[`gr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_set_tokenizer.md),
[`gr_budget()`](https://elkronos.github.io/harnessr/reference/gr_budget.md),
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)

## Examples

``` r
old <- gr_options(verbose = FALSE)
gr_options("verbose")
#> [1] FALSE
gr_options(old)
```
