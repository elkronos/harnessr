# Get or set package options

`hr_options()` with no arguments returns the full option list. Called
with a single string it returns that option. Called with `name = value`
pairs it sets them and invisibly returns the previous values, so it
composes with [`on.exit()`](https://rdrr.io/r/base/on.exit.html).

## Usage

``` r
hr_options(...)
```

## Arguments

- ...:

  Nothing, a single option name, `name = value` pairs, or a named list
  (the form `hr_options()` itself returns, so a saved value can be
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
  [`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md).

- `api` ("responses"):

  `"responses"` or `"chat"` request shape.

- `api_base` ("https://api.openai.com/v1"):

  API root; point this at a proxy or a compatible endpoint.

- `api_headers` (none):

  Named character vector of extra HTTP headers sent with every request,
  for gateways that do not authenticate with a bearer token. Inherited
  by every
  [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
  that does not name its own; see that function's `headers` argument for
  the rules.

- `temperature` (NULL):

  Default sampling temperature. `NULL` omits the field. Dropped
  automatically for models that reject it. Untested: `NULL` sends no
  temperature, so the model decides.

- `max_retries` (4):

  Retries for transient failures. HTTP 400 is never retried: a malformed
  request stays malformed. Untested: set when retries were written, with
  no measurement behind the number.

- `retry_pause_base` (2):

  Seconds; exponential backoff base. Untested: set when retries were
  written.

- `request_timeout` (120):

  Per-request timeout, seconds. Untested: set when the HTTP client was
  written.

- `safety_margin` (0.10):

  Fraction of the context window left unused to absorb tokenizer error.
  Not a spending cap (see `max_cost_usd`). Untested: set to absorb the
  error of counting tokens locally, and not measured against it.

- `min_output_tokens` (256):

  Floor on the completion room
  [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
  reserves *when `reserve_output` is not given explicitly*. An explicit
  `reserve_output` is used between 1 token and the model's `max_output`,
  unless it leaves no input room; then it drops to this floor, as the
  default reserve does. Untested: set as a floor for a short reply.

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
  recording a run with a *deterministic* embedder is what lets an
  [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
  reproduce its chunk ranking.

- `cache_dir` (NULL):

  Directory
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
  stores model responses in. `NULL` means a per-session directory under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html), which costs
  nothing and disappears with the session. Set it to a real path, such
  as `tools::R_user_dir("harnessr", "cache")`, to keep responses across
  sessions and make a long run resumable.

- `parallel` (FALSE):

  Run per-chunk calls concurrently. Needs the future and future.apply
  packages; without them it warns and runs sequentially.

- `workers` (4):

  Worker processes when `parallel` is TRUE. Untested: set when parallel
  runs were added. It does not change output.

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
  [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md))
  is not held by the limit: its requests are sent with a warning, unless
  `allow_unpriced` is `FALSE`. Under a limit of 0 a model registered at
  no cost runs and one with a price is refused. `NULL` removes the
  limit.

- `max_calls` (400):

  Hard cap on model calls per run, checked before every request. A
  request to an embeddings endpoint (the built-in `"api"` embedder)
  counts as one, and is checked and priced against `max_cost_usd` the
  same way; an embedding served from the session cache is free. A
  request an
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
  answers counts. `NULL` removes the cap.

- `max_tokens_total` (NULL):

  Most tokens one run may use: the prompt and reply tokens of every
  call, cache hits included, and the text sent to be embedded. A request
  is refused when what the run has used plus its prompt and its reply at
  the cap would pass it. The limit that still bounds a run on a model
  with no price. `NULL` for no limit.

- `max_output_tokens` (NULL):

  The largest output cap one request may be sent with. A request with a
  larger cap (for a reasoning model, the raised cap
  [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
  sends) is refused rather than cut down. `NULL` for no ceiling.

- `allowed_models` (NULL):

  Character vector of the model ids a run may call, chat and embedding
  models alike. A request to any other is refused. `NULL` for any model.

- `allow_unpriced` (TRUE):

  Whether a chat model with no registered price may be called while
  `max_cost_usd` is set. On, such a request is sent, its cost is
  recorded as unknown (`NA`), and the first request to each such model
  in a session warns with class `hr_unpriced_model`. Off, it is refused
  with a condition of that class. Untested: harnessr ships no prices, so
  off would refuse every built-in model until you set its prices with
  [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
  or
  [`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md).

- `price_max_age_days` (120):

  How old a price may be, in days, before a cost computed from it warns
  with class `hr_stale_price`. A price's age is counted from the first
  day of its `as_of` month (see
  [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)),
  and the warning is given once per model per session. Built-in models
  have no prices, so it applies to prices you set. `NULL` turns the
  warning off. Untested: about four months, so prices set once are
  checked again a few times a year.

- `unknown_model_action` ("warn"):

  `"warn"` or `"error"` when a model id is not in the registry.

- `actor` (none):

  A named list (or character vector) of the actor fields every
  [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  records: `system`, `owner`, `run_by`, `purpose` and `approved_by`,
  each one string. A field named here is recorded on each new trace
  unless
  [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  is given its own; one named nowhere is `NA`. Other names are refused
  with an error of class `gr_bad_option`.

- `auto_max_tokens` (50000):

  The largest document, in tokens, that
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  with `recipe = "auto"` reads with `"fast"` (one request); a larger one
  is read with `"thorough"`. Untested: the value is about 70 pages of
  prose and under a twentieth of the default model's window, and nothing
  has measured where the two recipes' answers diverge.

- `auto_room_share` (0.5):

  The second condition of that choice: the document must fill at most
  this share of the input room
  [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
  leaves on every model of the run. Untested: the other half was left
  for the error of counting tokens locally.

- `reasoning_floor` (2048):

  The smallest output cap a request to a reasoning model is sent with. A
  smaller cap is raised to it, within the model's limit and the room the
  context window leaves, so a short structured call is not used up by
  reasoning; `0` turns the raise off. The trace's `params_sent` records
  the cap sent. Untested: a reasoning model can spend a few hundred to a
  couple of thousand tokens before it replies, and the value was not
  measured. A value other than the default joins the response-cache key
  and the store key of
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).

- `output_reserve_share` (0.25):

  The share of the usable window
  [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
  reserves for the reply when no `reserve_output` is given, between
  `min_output_tokens` and the model's output limit. It sets the input
  room of such a budget. The readers give `max_answer_tokens` as the
  reserve, so it does not change how much of a document they fit in one
  request. Untested.

- `near_verbatim_sim` (0.90), `near_verbatim_sim_short` (0.95),
  `near_verbatim_short_chars` (40):

  The least similarity a quotation of at least
  `near_verbatim_short_chars` characters (after normalising), and one
  shorter than that, needs for the edit-distance matcher to score it
  `near_verbatim` (see
  [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)).
  The values come from practitioner sources and were not tuned; the
  matcher's error rates at them were measured on a labelled set of 343
  true and 162 false quotations (see NEWS). The status is recorded only,
  unless `accept_near_verbatim = TRUE` (see
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)).
  A value other than the default joins the store key of
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).

## Where the defaults come from

The settings listed last above were constants in the code until they
were options; each keeps the constant's value. A trace records them, and
`price_max_age_days`, (in its options snapshot) only when one is not its
default, so a trace made at the defaults reads as it did before they
existed. Each tuning setting's entry above (`temperature`,
`max_retries`, `retry_pause_base`, `request_timeout`, `safety_margin`,
`min_output_tokens`, `workers`, `price_max_age_days` and the settings
listed last) says where its default came from, as does
`allow_unpriced`'s; "untested" means no measurement backs the value. The
other entries are switches, limits and names, which are choices rather
than tuned values.

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
`request_timeout` \[1, 3600\], `workers` \[1, 32\], `temperature` \[0,
2\], `auto_max_tokens` \[0, 1e7\], `auto_room_share` \[0, 1\],
`reasoning_floor` \[0, 1e6\], `output_reserve_share` \[0, 0.9\],
`near_verbatim_sim` and `near_verbatim_sim_short` \[0, 1\],
`near_verbatim_short_chars` \[0, 1e4\] and `price_max_age_days` \[0,
3650\]) read a number written as text as that number. A value they
cannot read, such as `NA` or `"x"`, warns (`gr_bad_option`) and leaves
the current setting unchanged; a value outside the range is clamped into
it, with the same warning. Whole-number settings are rounded down.
`temperature` also takes `NULL`, its default, and `price_max_age_days`
takes `NULL` to turn its warning off.

## See also

[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
to correct a model's limits,
[`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md),
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md),
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)

## Examples

``` r
old <- hr_options(verbose = FALSE)
hr_options("verbose")
#> [1] FALSE
hr_options(old)
```
