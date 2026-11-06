# Changelog

## harnessr 0.6.0.9000

### Renamed

- **The package is now called harnessr.** readgpt grew a general core
  for model calls (clients, spending limits, a response cache,
  recordings that replay offline, traces) under its document-reading
  layer, and the new name says so. Load it with
  [`library(harnessr)`](https://github.com/elkronos/harnessr). The
  GitHub repository is renamed to `elkronos/harnessr` too, and GitHub
  sends the old address there, so
  `remotes::install_github("elkronos/harnessr")` installs it and the old
  `elkronos/readgpt` still works. The website moves to
  <https://elkronos.github.io/harnessr/>. No exported function, class,
  argument or prompt changes name in this release except
  [`readgpt_example()`](https://elkronos.github.io/harnessr/reference/readgpt_example.md),
  below.

- **[`readgpt_example()`](https://elkronos.github.io/harnessr/reference/readgpt_example.md)
  is now
  [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md)**,
  which returns the same path to the bundled example document.
  [`readgpt_example()`](https://elkronos.github.io/harnessr/reference/readgpt_example.md)
  still works, with one `gr_deprecated` warning per session naming the
  new function.

- **Requests, cache keys and recordings are unchanged by the rename.**
  Every request is sent as 0.6.0 sent it, and the corpus store key is
  the one 0.6.0 computed. The response-cache and replay keys change
  later in this release (see “Cache and replay keys” below), and the
  keys 0.6.0 computed are still looked up, so a warm cache, a recording
  made for
  [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  and a
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  store all keep answering.

- **Two options are renamed**: `readgpt.api_key` is now
  `harnessr.api_key`, and `readgpt.allow_local_urls` is now
  `harnessr.allow_local_urls`. The old names are still read when the new
  ones are not set, with one `gr_deprecated` warning per session naming
  the new option.

- The help pages now suggest `tools::R_user_dir("harnessr", "cache")`
  for a cache that lasts. With that directory set, entries readgpt kept
  in `tools::R_user_dir("readgpt", "cache")` are read too, after it; new
  entries are written only to the new directory, and the old one is
  never cleared. The per-session default is now
  `file.path(tempdir(), "harnessr-cache")`.

- Text that named the package now says harnessr: the URL fetcher’s user
  agent (`harnessr/<version>`), the audit report’s title and footer,
  messages, and the Shiny app’s title. A trace’s `meta` still records
  the version under `readgpt`, so traces written before and after the
  rename read the same way.

### Traces record what was sent and what came back

- **Each request step records `params_sent`**, the request as it went
  out with every default resolved: the model, `api`, `base_url`, the
  output cap actually sent (a reasoning model’s small cap goes out
  raised to 2048), the temperature (filled from
  `gr_options("temperature")`, or `NA` when none was sent), the effort,
  the schema name, and SHA-256 hashes of the schema and of the extra
  body fields. For a
  [`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md)
  it is read from the request body itself. `params` keeps what the
  caller asked for, as before. Requests, response-cache keys and replay
  keys are unchanged.

- **Steps record `served_model`, `response_id` and `fingerprint`** where
  the provider returns them, beside `model`, which stays the model asked
  for and is what a step is priced and replayed by. None of them enters
  a cache or replay key.
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  results carry the same three fields.

- **Steps record `attempts`**, the number of requests sent, retries
  included (0 for a reply from a cache or a recording), and
  `started_utc` and `ended_utc` as ISO 8601 in UTC with a trailing `Z`.
  A saved trace’s `started` is now written in UTC with a `Z` too; it was
  local time with no offset.

- **Token records say where they came from.** A step’s `tokens` gains
  `provenance`: `"reported"` by the provider, `"counted"` here with the
  `"tiktoken"` tokenizer, or `"estimated"` with another one. Reasoning
  and cached input tokens the provider reports are kept as
  `tokens$reasoning` and `tokens$cached_input`, parts of `output` and
  `input` rather than additions.
  [`gr_trace_summary()`](https://elkronos.github.io/harnessr/reference/gr_trace_summary.md)
  gains `tokens_reasoning`, `tokens_cached_in` and `usage_estimated`,
  the share of requests whose counts were estimated, and
  [`print()`](https://rdrr.io/r/base/print.html) on a trace says that
  share when it is above zero. A request that failed before the provider
  sent any usage records a `"counted"` zero, and a handler’s
  [`gr_result()`](https://elkronos.github.io/harnessr/reference/gr_result.md)
  built with no usage is counted here rather than taken as a reported 0
  in and 0 out.

- **Embeddings requests record `attempts`, `served_model` and a
  provenance** like any other request; `attempts` was always `NA`
  although they are retried, and a failed one had no provenance.
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) on a
  trace gains `tokens_reasoning`, `tokens_cached_in` and `served_model`
  columns when some request has them, and
  [`gr_trace_cost()`](https://elkronos.github.io/harnessr/reference/gr_trace_cost.md)
  gains `paid_reasoning` and `paid_cached_in`.

- **Cached input can be priced at its own rate.**
  [`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md)
  takes `cached_input_usd`,
  [`gr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/gr_estimate_cost.md)
  takes `cached_input_tokens`, and
  [`gr_models()`](https://elkronos.github.io/harnessr/reference/gr_models.md)
  shows `cached_input_usd_per_1m`. A model with no cached rate prices
  cached input as other input, so every built-in model costs what it
  did.

- **Runs record who they are for.**
  [`gr_trace()`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  takes `system`, `owner`, `run_by`, `purpose` and `approved_by`, and
  the new option `gr_options(actor = list(...))` sets them for every
  trace; a field named nowhere is `NA`. They are written to a saved
  trace under `actor` and shown by
  [`print()`](https://rdrr.io/r/base/print.html) when set.

- **Runs record the options in force** when the trace was made, under
  `config`, with the R version. The values of `api_headers` are left
  out, since they can hold credentials.

- [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
  given one named argument whose value is a list now sets that option.
  It used to read the list as a set of options to restore, which only an
  unnamed list should be.

### Cache and replay keys

- **[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  takes a `draw_index`** for the draws of a sampled request: 0, the
  default, for an ordinary call, and 1, 2, … for repeated draws. Above 0
  it is part of the response-cache key, so N identical calls with draw
  indexes 1 to N are N cached replies; before, a cache returned the
  first reply N times and anything that compared them saw perfect
  agreement. A handler finds it in `params$draw_index` and the trace
  records it in the step’s `params`; at 0 neither carries it, so an
  ordinary call is unchanged.

- **The response-cache key is now `harnessr-cache-v3`**, a SHA-256 hash
  (64 hex digits) in place of xxhash64. Entries written under the old
  key (`readgpt-cache-v2`, by readgpt 0.6.0 and earlier builds of
  harnessr) are still read for calls with no draw index: a call that
  finds nothing under its new key is looked up under the old one. The
  first reply found that way in a session warns once for the cache, with
  class `hr_legacy_key`, and
  [`gr_cache_stats()`](https://elkronos.github.io/harnessr/reference/gr_cache_stats.md)
  has a new column, `legacy_hits`, that counts them. Old entries are
  never rewritten, new ones are written under the new key only, and
  [`gr_cache_clear()`](https://elkronos.github.io/harnessr/reference/gr_cache_clear.md)
  removes both.

- **The replay key is now `harnessr-replay-v2`**, and covers the
  temperature (once the session default is filled in), the output cap
  asked for and the JSON schema as well as the messages, model and
  effort. A replay under another temperature, cap or schema now misses
  instead of being answered with the recorded replies. Each model step
  of a trace records its key as `replay_key`. A step recorded before
  that is looked up by the old key (`readgpt-replay-v1`: messages, model
  and effort), with one `hr_legacy_key` warning per recording in a
  session and a count in `$stats()$legacy_hits`. A replay’s own trace
  records a reply found that way, or one repeated under
  `on_exhausted = "flag"`, without a `replay_key`, so a replay of that
  trace still goes through the old key, or still runs out of replies. A
  miss on a prompt recorded for the model at the effort asked for says
  the temperature, output cap or schema differ, names the recorded
  settings next to the ones this call asks for, and says which of them
  differ. Where the schema differs, the recorded cap is given as the cap
  that was sent, which may be the model’s limit rather than the cap
  asked for.

- **A replay that runs out of recorded replies is an error.** A call
  past the last reply recorded for its request, or for a draw that was
  never recorded, raises `hr_replay_exhausted`. It used to repeat the
  last reply, so a replay making more calls than the recorded run looked
  like an exact reproduction. `gr_replay_client(on_exhausted = "flag")`
  keeps the old behaviour, counted in `$stats()$repeats`. A call with a
  `draw_index` above 0 is answered with the reply recorded for that
  draw, or the k-th reply to the request in a recording made without
  draw indexes.

### Limits checked before every request

- **`max_calls` and `max_cost_usd` now hold exactly.** Every request is
  checked before it is sent, by the call path itself, against what the
  run has spent plus the most the request could cost: its prompt at the
  input price and its output cap (for a reasoning model, the raised cap
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  sends) at the output price. The prompt is counted with the JSON schema
  and extra body fields the request carries and a few tokens of framing
  per message, then raised by `safety_margin`, since the provider bills
  for all of that. A request that could take the run past a limit is not
  sent. Runs used to stop only once what they had spent reached the
  limit, so they ended up to one request over it; they now end at or
  under it, as long as the provider stops each reply at its cap and
  counts the prompt within that margin of the local tokenizer. A run
  that leaves its output caps at the model’s limit stops while it still
  has headroom a smaller cap would have used.

- **A refused request is not a call.** It comes back from
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  as a failed result with `refused = TRUE` and an error naming the
  limit, after a condition of class `hr_budget_refused` is signalled
  (catch it to stop instead). It adds nothing to the trace’s calls,
  steps or spend; the trace lists it in a new `refusals` field, sets
  `budget_stop` and names the limit in `stop_reason`. Readers and review
  stages treat it as they treated reaching a limit before: the answer or
  section is marked partial, and the request is not counted as failed.

- **Every request is checked, not only the ones a reader asked about.**
  Judges, the ensemble’s adjudication, conflict resolution in `extract`,
  context and proposition segmentation, claims, outlines, screening,
  synthesis and embeddings requests all go through the same check, as
  does any request a custom reader or a script makes with
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md).
  The readers no longer check `trace_can_call()` themselves. It is kept
  for custom readers written to the 0.6.0 help page, which still work.

- **A chat model with no registered price is refused while a spending
  limit is set**, with a condition of class `hr_unpriced_model`. Such a
  model added nothing to the spend, so the limit never stopped it.
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  stops before its first request with an `hr_unpriced_model` error.
  Register the model’s prices with
  [`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md),
  or set `gr_options(allow_unpriced = TRUE)`; then its requests are
  sent, still count against `max_calls` and `max_tokens_total`, and are
  priced `NA` in the trace.
  [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
  and replays are never refused for this, and neither are embedding
  models with no price. An ellmer chat is priced as the model it was
  built with, whatever a spec names, so a chat on a model with no
  registered price is refused too; the README and the
  [`gr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/gr_ellmer_client.md)
  example now register its price, and allow a local model to run
  unpriced.

- **New option `max_tokens_total`** (`NULL`, off) limits the tokens a
  run may use: prompts and replies of every call, and text sent to be
  embedded. A request whose prompt and reply at its cap would pass it is
  refused with `stop_reason` `"tokens"`. It is the limit that still
  bounds a run on an unpriced model under `allow_unpriced = TRUE`.
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  holds the whole comparison to it, as it does to `max_cost_usd`.

- **New
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)**
  holds a run’s limits: `max_calls`, `max_cost_usd`, `max_tokens_total`,
  `max_output_tokens` (the largest output cap one request may carry; a
  request with a larger one is refused, not cut down), `allowed_models`
  and `allow_unpriced`. Attach one with the new `gr_trace(governor = )`
  argument; a trace without one reads the limits from
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md),
  as before. The new limits are also options, `max_tokens_total`,
  `max_output_tokens`, `allowed_models` (all `NULL`, off) and
  `allow_unpriced` (`FALSE`), so every trace’s config snapshot now lists
  them.
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  writes a trace’s `refusals` and `governor` when it has any, with
  `allowed_models` always as an array.
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md),
  which keep a trace of their own and fold it into the one they are
  given, hold their requests to that trace’s governor, less what it has
  already spent and used in tokens; `max_calls` stays a limit per
  document and per stage.

- **A parallel batch cannot pass a limit.** Each worker’s items are held
  to an equal share of the calls and dollars the run has left, and an
  item its share refused before it sent anything runs again in the
  calling process, against the run. A batch that the run’s limits cannot
  cover still runs in the calling process, as before. Batch items make
  one request each; an item that made more and had a later one refused
  by its share warns (`gr_parallel_share`) and does not mark the run as
  stopped.

### JSON replies checked against their schema

- **A JSON reply must fit the schema the request sent.** Every call that
  asks for JSON (screening, claims, outlines, preview plans, rerank,
  iterative reading, model segmentation, extraction) now checks the
  reply’s types, `enum` values and `required` fields, through nested
  objects and arrays, before using it. A reply that fails is treated as
  a reply that did not parse: the reader takes its failure path, and the
  reply is not cached, so running again asks again. A cached reply that
  fails is asked again too. It used to be enough for a reply to be a
  named object, so `{"decision": "probably"}` was a screening reply and
  was stored as one. Some replies that used to be read leniently are now
  failed calls: a screening decision outside `include`, `exclude` and
  `unclear` (it was read as “unclear”), a text field sent as an array or
  object in `iterative`, `rerank` and
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  (it was joined into one string), and a proposition list sent as an
  array of arrays (the batch is kept as written). Where a reader reports
  why a call failed, it now says where the reply broke the schema, as in
  `$.groups[0]: expected array, got 1`.
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  still reads each field’s value itself, so “1,204” in an integer field
  is still 1204 and an undeclared value is still reported as one it
  could not read; only the shape of its replies is checked.

### Embedding scores

- **Comparing vectors of different lengths is an error.** Cosine
  similarity cut both vectors to the shorter length, so a lexical
  fallback vector scored against an API embedding gave a plausible
  number from two unrelated spaces. It now stops with an error of class
  `hr_dim_mismatch`. The readers already kept the query and the chunks
  in one space; `iterative` now also falls back to word overlap for a
  round whose query came back with no vector.

- **BM25 scoring is faster on many chunks.** Document frequency is
  counted once per query term instead of once per term for every chunk,
  so the `rerank` prefilter and the offline `retrieve` path no longer
  slow down with the square of the number of chunks. Scores are
  unchanged.

### Parameter schemas, declared calls and reader costs

- **New
  [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md),
  [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  and
  [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)**
  state a spec’s parameters once: type, default, range and choices.
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
  [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  and
  [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
  now check their arguments through schemas instead of code of their
  own. They accept the same values and return the same specs, with the
  same clamps, defaults and warnings; a clamp warning now also has class
  `hr_param_clamped` beside `gr_clamped`.

- A value outside the choices of `context_order`, `restate`,
  `on_overflow`, `context_source`, `ocr` or `layout` is still an error,
  which now names the setting and has class `gr_bad_setting`, where it
  used to be a plain
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html) error that said
  `'arg'`.

- **Readers and segmenters declare the labels their calls carry.**
  [`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
  and
  [`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
  take a new `calls` argument, the stems of their calls’ trace labels
  (`"stuff.answer"`, `c("map.answer", "reduce")`).
  [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
  and
  [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md)
  list them in a new `calls` column. A reader or segmenter registered
  without `calls` declares its own name, which covers labels such as
  `"longest.answer"` for a reader called `"longest"`.

- **An `effort` map that names no declared call is an error.** A name in
  `gr_read_spec(effort =)` (and the `effort` of
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md))
  must be a declared stem, a part of one up to a dot (`"synthesise"`,
  `"segment"`), or a label under one (`"reduce.level1"`). Anything else
  stops with an error of class `hr_unknown_effort_key` that lists the
  stems. Such a name used to be accepted and matched no call, so a
  misspelt `c(extrac = "low")` sent every extraction call at the
  provider’s default with nothing said. An effort map that names the
  calls of a reader or segmenter of your own needs that module
  registered first, with its labels in `calls`.

- **A reader states its cost as a function.**
  [`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
  takes a new `cost` argument, a function of `(input_stats, params)`
  returning the new
  [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md):
  requests expected and at worst, embedding requests, and what the
  reader must send. The pre-flight check of
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  adds up these functions instead of repeating each built-in reader’s
  call pattern, and the governor decides from the sum whether the run
  fits its limits before the first request. The built-in readers’
  estimates, the trace’s `preflight` step and the refusals are
  unchanged. A registered reader without `cost` is counted as before,
  one request per chunk. `cost_calls` is kept for display only, as the
  description
  [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
  shows; the pre-flight check never reads it, and it will be retired in
  a later phase. A cost function may also return a plain list with
  `calls_max` and no `calls`, which is read as both.
  [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md)
  has a `tokens_out_max` for a reader whose replies can be billed beyond
  the reply cap; the check prices every request at
  `input_stats$out_cap`, the largest cap the run’s model is sent, and
  uses `tokens_out_max` when it is larger.

- [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  with a `type` or `tier` it does not know is an error of class
  `gr_bad_setting` that names the parameter. A `named_map` parameter
  takes a character vector or a list whose elements are all named.

### Screening

- **[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  computes kappa on kept against excluded.** 0.6.0 took kappa over the
  screener’s three labels (include, unclear, exclude) against the
  person’s two, so every `"unclear"` counted as a disagreement, while
  sensitivity in the same object counted an unclear record as kept. The
  primary table is now kept (include or unclear) against excluded, the
  definition sensitivity uses, and `$agreement$strict` holds strict
  include against the rest as a secondary table. On the eight-record
  example in
  [`?gr_calibrate`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  kappa moves from 0.33 to 0.50. The old figure is `$kappa_legacy` for
  this release only, and is removed in the next.

- **Kappa is no longer reported alone.** Each agreement table carries
  Cohen’s kappa, PABAK and Gwet’s AC1 with intervals, the prevalence and
  bias indices, and the class-wise sensitivity, specificity, PPV and
  NPV; `$agreement$kept$paradox` flags a table whose prevalence index is
  above 0.8 in absolute value, where kappa says more about prevalence
  than agreement. `$decisions` holds the 3x2 counts, and
  [`print()`](https://rdrr.io/r/base/print.html) and the audit report
  show them with the agreement set. The rate of `"unclear"` decisions is
  the existing `"deferred to a person"` metric, with its interval.

- **The kappa interval is a bootstrap over documents.** It is a
  percentile bootstrap with B = 2000 under a fixed seed, so the same
  sample gives the same interval and the session’s random stream is
  untouched; B and the seed are in `$agreement$kept$bootstrap`. AC1
  keeps Gwet’s (2008) variance. Where the screener and the person agree
  on every record, disagree on every record, or the sample holds fewer
  than 10 records, the kappa and AC1 intervals are left empty (NA) with
  a `$note` saying why, instead of a zero-width interval such as \[1.00,
  1.00\].

- [`print()`](https://rdrr.io/r/base/print.html) on a calibration now
  shows the 3x2 counts on every sample, including one drawn from a
  single stratum. The audit report’s calibration section shows the same
  counts, and sensitivity, specificity, PPV and NPV with intervals
  beside kappa, PABAK and AC1.

- **Unclear records no longer leave a review without a word.** A
  `gr_screening` gains `$forward` (the included and unclear records, the
  set a review reads at full text) and `$deferred` (the unclear ones).
  `gr_extract(screening)` still reads only `$included` in this release
  and now warns (class `gr_unclear_dropped`) when that leaves unclear
  records out; from the next release it reads `$forward`. Pass
  `screening$forward` to read them now. Passing the vector
  `screening$included` gives no such warning: `$included` stays a plain
  character vector in this release, and a warning on that path is left
  to a later release.

- **New
  [`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md)**
  records a person’s decision on a deferred or failed record: who
  decided, when (in UTC) and why, in the table and as a
  `"screen.resolve"` step in the trace. `forward`, `deferred` and
  `included` are rebuilt, the screener’s own decision is kept in
  `screener_decision`, and
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  compares against that one, so a person’s correction is not credited to
  the screener. Duplicates of a resolved record take the same decision.
  The audit report’s screening table shows the screener’s decision and
  who resolved each record, when and why.

- **[`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
  accounts for every screened record.** A record with no decision is now
  counted as “could not be read” only when no screening call was made;
  one whose call failed, or whose reply was not the form asked for, has
  a row of its own, “screening call failed”. New rows count the records
  resolved by a person, the records kept for full text (`$forward`) and,
  of those, the ones deferred (`$deferred`).

### Claims and outline

- **[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  and
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  record their calls the way the other review stages do.** Each records
  on a trace of its own and, given `trace =`, adds its calls to that
  trace when it finishes, as
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  already did. Before, both recorded straight onto the trace they were
  given, so a review trace that an earlier stage had taken past
  `gr_options(max_calls =)` or `max_cost_usd =` stopped them before they
  sent a request, and
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  returned no claims, marked partial. Pass one trace to every stage and
  its totals are the sum of the stages’, with each request counted once.

- **[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  no longer adds to `claims$trace`.** Given no `trace`, it recorded its
  calls on the trace of the claims it was handed, which changed a
  finished
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  result and made `claims$trace` report the outline’s cost as the
  claims’. Its calls are now on `attr(outline, "trace")`, which
  [`gr_outline_pick()`](https://elkronos.github.io/harnessr/reference/gr_outline_pick.md)
  keeps and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  keeps as `$outline_trace`. Scripts that totalled a review’s cost from
  `claims$trace` after
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  should pass one `trace` to both, or add `attr(outline, "trace")`. The
  audit report’s claims row still includes the outline’s calls, read
  from the synthesis, and counts them once when a script passes
  `trace = claims$trace` to
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md).

### Comparing recipes

- **[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  says what each recipe cost.** `summary` gains `calls`, `tokens_in`,
  `tokens_out` and `usd`, priced from the requests on the trace at each
  model’s registered price, and `usd_estimated`, the share of those
  dollars spent on requests whose token counts were estimated locally
  because the provider reported none (`NA` for a trace whose requests do
  not record how their counts were obtained, such as one saved by an
  earlier version). A recipe is charged for a segmentation it shares
  with an earlier recipe, as it would be run alone, so the column can
  add up to more than `gr_trace_cost(cmp$trace)`. `usd` is `NA` when a
  model has no registered price. The columns come after `error` and
  before `premise`.

- **`gr_compare(correct =)`** takes strings that a right answer contains
  (ignoring case and white space) or a function of each `gr_answer`
  returning `TRUE`, `FALSE` or `NA`, and adds `correct` and
  `usd_per_correct`, the cost of a right answer: `usd` when the answer
  is right, `Inf` when it is wrong and cost something. Without it the
  summary has no such columns. A recipe a limit stopped before it found
  anything is `NA`, not wrong: the spending, token or call limit, the
  model allow-list, the output ceiling, or a spending limit refusing a
  model with no price. A `correct` function that fails or returns
  something other than one logical gives a `gr_bad_correct` warning and
  `NA` for that recipe, so the paid results still come back; an invalid
  `correct` argument is an error of the same class.

### Checking quotations

- **`gr_read_spec(verify = TRUE)`** checks an answer’s quotations
  against the chunks they come from and lets the check decide what is
  accepted.
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  runs
  [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  on the answer, writes its columns onto `$evidence`, marks the answer
  partial when a quotation is not found (`notes$unverified_evidence`),
  notes how many it checked (`notes$quotes_checked`) and records a
  `read.verify` step in the trace. The `iterative` reader’s step must
  then list the passages its answer rests on, word for word with their
  chunk numbers, and the loop stops only when every one is found in the
  chunk it names, among those the step was shown. A refused step is told
  which quotations were not found; a run that ends with none accepted
  answers `NOT_IN_DOCUMENT`, keeps the refused answer in
  `notes$unverified_answer` and makes no final answer request. Its
  evidence is the quoted passages, not every chunk it was shown. A
  refusal is sent back even when retrieval has no unseen chunks left, so
  the next step can quote what it already has. With `premise = TRUE`, a
  step that reports the premise false is not held to quotations in this
  release and stops the loop as it does without `verify`.
  `verify = FALSE`, the default, sends every request as before, and the
  field is in the spec only when `TRUE`, so cache, replay and corpus
  store keys are unchanged.

- **A second quote matcher is recorded beside `verified`.** Evidence
  tables that are checked (`skim`, `extract`, `screen`, `iterative` with
  `verify = TRUE`) and
  [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  gain `quote_status`, `quote_sim`, `quote_coverage`, `quote_edits` and
  `quote_critical_ok`, from a matcher that expands ligatures, joins
  words broken across a line with a hyphen, undoes JSON escapes and
  scores the closest window of the source by character edits, with
  numbers (in digits or in words, with any comparison sign before them
  and the unit after), and negations required to be identical. A passage
  too long to score (its length times the source’s over 5e7 characters)
  is `not_checked`. Its statuses are `verbatim`, `near_verbatim`
  (similarity at least 0.90, or 0.95 under 40 characters, five words or
  more), `unverified` and `not_checked`. It decides nothing in this
  release: `verified` and `match` are the existing check’s, as before.
  On a labelled set of 343 true and 162 false quotations it rejects 1.2%
  of true ones (95% CI 0.3% to 3.0%) against 36.4% (31.3% to 41.8%) for
  the existing check, and accepts none of the 52 with a changed digit, 8
  with a changed number word, 3 with a changed comparison sign, 37 with
  a flipped negation or 16 invented sentences; it does accept 25 of 46
  quotations with one content word swapped as `near_verbatim`, which is
  why that status is not `verified`. `Rscript dev/quote-matcher-rates.R`
  prints the full table.

### Trace records of state and cuts

- **`refine` and `hierarchical` write the length of the state they
  carry.** Each `refine.draft` and `refine.revise` step in the trace
  gains `state$tokens_in` (the draft the request carried) and
  `state$tokens_out` (the draft carried on from it, which is the old one
  when the reply was unusable). Each `hier.summarise.L<k>` step gains
  the length of the text it summarised and of the summary it returned,
  the `hier.answer` step the length of the summaries it was sent, and
  each level adds a local `hier.state.L<k>` step with the number of
  summaries handed on and their combined length. A draft that shrinks
  sharply in one revision can now be seen in the trace.

- **Every cut writes a `truncate` step to the trace** with where it was
  made (`detail$where`: `refine.excerpt`, `refine.draft`,
  `hier.summaries`, `preview.skim`, `preview.outline`, `<label>.input`
  for a finding cut to fit a merge, `<label>.giveup` for the capped
  findings a failed merge returns, `segment.contextual.header`,
  `segment.contextual.document`, `screen.opening`, `synthesise.gaps`,
  `embed.input`), the token limit, and the tokens before, kept and
  dropped (the truncation marker is not counted as kept). For
  `screen.opening` the limit is the screening cap on the opening with
  its heading; for `segment.contextual.header` it is the room the header
  was cut to. A `preview.skim` cut lists the cut section’s `chunk_ids`,
  always as a JSON array. `refine` and `hierarchical` answers also gain
  `notes$tokens_truncated`, and their printed answer now says how many
  tokens were cut (“N token(s) cut to fit”) when a cut happened. The
  `preview` reader’s `notes$tokens_truncated` is now the tokens a cut
  dropped rather than the overshoot over the cap, a correction to a
  count that measured the wrong thing. Requests, cache keys and replay
  keys are unchanged; the trace of a run that cut nothing gains only the
  state lengths above.

### Conformance checks

- **New
  [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md)
  and
  [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)**
  run one registered reader or segmenter on
  [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md)
  through an offline mock client and report which rules of its contract
  it breaks. A reader is checked for finishing without an error,
  returning a `gr_answer` with the fields
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  documents and a single string as its answer, evidence and
  `chunks_used` that name only chunks of the input, call labels covered
  by the stems it declared in `calls`, and no more requests than its
  `cost` function’s worst case for that input. A segmenter is checked
  for finishing without an error, returning a `gr_chunks` with the
  documented columns, text in every chunk, unique chunk ids, no chunk
  over `max_tokens` that
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
  had to split, and call labels covered by its declared stems. Every
  built-in reader and segmenter passes them.

- **New
  [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md)**
  is the core helper both use: it runs a closure that calls a module in
  a temporary working directory, catches its error and warnings, asks a
  named list of rule functions about what came back, and returns an
  `hr_conformance` data frame with a `rule`, `ok` and `detail` for each.
  `ok` is `NA` for a rule that could not be checked.
  [`print()`](https://rdrr.io/r/base/print.html) lists the broken rules
  first, says “passes all N rules” when every rule passes, and says
  “passes all N rules checked; M not checked” when some rules could not
  be checked.

- The checks are reports only.
  [`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
  and
  [`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
  still check only that `fn` is a function, and register a module that
  breaks a rule as before.
