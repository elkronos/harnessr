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

### Fixed

- A download refused for size no longer breaks the downloads after it.
  httr shares one curl handle per host, and a stream stopped at the size
  limit could leave that handle attached to its connection, so every
  later download from the same host in the session failed with “Handle
  is already in use elsewhere”. Each request now gets its own handle.

### Phase 2

- New guide,
  [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
  (“Measuring and comparing configurations”), covers reference sets and
  label sheets, benchmarks and their reports, non-inferiority, judges,
  baselines, drift and signals;
  [`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
  gains recall against a target, the stopping test, several reviewers
  and agreement on extracted fields.

#### Agreement and estimation statistics

- **New
  [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)**
  gives Wilson, Clopper-Pearson or Jeffreys intervals for proportions,
  vectorised over `x` and `n`, two-sided or as a one-sided bound. Wilson
  matches `prop.test(correct = FALSE)`, including a lower bound of
  exactly 0 at `x = 0` and an upper bound of exactly 1 at `x = n` (the
  formula alone left a rounding error there for 38 and 60 of the values
  of `n` from 1 to 200, such as a lower bound of 2.8e-17 at 0 of 10),
  and Clopper-Pearson matches
  [`binom.test()`](https://rdrr.io/r/stats/binom.test.html). The help
  says which to use: Wilson for descriptive rates, Clopper-Pearson for
  any “at least” or “at most” guarantee.

- **New
  [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)**
  reports agreement between two raters as the count table with observed
  agreement, Cohen’s kappa (standard error and a bootstrap interval over
  items), the prevalence and bias indices, PABAK, Gwet’s AC1 with its
  variance interval, positive and negative specific agreement, and, when
  `positive` is given, sensitivity, specificity, PPV and NPV against the
  second rater. `paradox_flag` marks tables where kappa should not be
  compared across samples. For a matrix of coders, or a level other than
  nominal, it reports Krippendorff’s alpha at the nominal, ordinal,
  interval or ratio level with a bootstrap interval, and reports only
  percent agreement, with a note, below 30 items or for a constant
  field. It has [`print()`](https://rdrr.io/r/base/print.html) and
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  methods, and its bootstrap leaves the caller’s random state as it was.
  Factor levels that neither rater used are left out of the two-rater
  table with a note, and a `positive` label that is not among the labels
  is an error. When coders’ factors carry different level sets, ordinal
  alpha merges them keeping each coder’s order (low, high and low, mid,
  high give low, mid, high), and levels that conflict or leave two
  levels unordered are an error.

- **New
  [`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md)**
  estimates a total (Horvitz-Thompson), a mean (Hajek) or a ratio of
  totals from a sample drawn with known inclusion probabilities,
  optionally stratified, with the difference estimator when predictions
  for the whole population are given, and a bootstrap interval that
  resamples within strata with the finite population correction (the
  Rao-Wu rescaling bootstrap). A stratum judged in full (pi = 1) adds no
  variance: a census of 20 records gives se 0 and the interval \[12,
  12\] for a total of 12, and a simple random sample of 100 from 200
  with 30 eligible gives se 6.5, the design value.

- **New
  [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md)**
  gives a prediction-powered estimate of a mean from many model-labelled
  units and a few labelled by people, with the power-tuned PPI++ weight
  by default and inverse-probability weighting when the labelled units
  were drawn with unequal probabilities.

- **New
  [`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md)**
  runs the alternative annotator test of Calderon, Reichart and Dror
  (2025): whether a model’s labels can be used in place of three or more
  human annotators, with the margin set by their declared expertise, a
  Benjamini-Yekutieli correction, the winning rate, and the winning rate
  over margins from 0.05 to 0.20. Annotator column names must be unique
  and non-empty.

- [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  and its output are unchanged.

#### Benchmarks: arms, references, scorers and `hr_benchmark()`

- **New
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)**
  describes one configuration to compare: a function of an item and a
  context that carries the client, a trace of the run alone, the
  governor and the run’s `draw_index`, with `ctx$call()` as a shortcut
  for
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  that fills in all three. `run` is required. The arm records its
  settings, a version and a hash of its code and settings, which is the
  same in every session and after
  [`saveRDS()`](https://rdrr.io/r/base/readRDS.html), also for an arm
  built inside a function of yours. The hash covers the values the code
  reads from where it was written, the workspace included, so an arm at
  top level that reads a global prompt gets a new hash when the prompt
  changes.

- **New
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)**
  holds the items to score, their labels, clusters, splits (`"dev"`,
  `"exploratory"`, `"calibration"`, `"test"`, `"final"`), inclusion
  probabilities, strata and coder labels, with a content hash. Labels,
  clusters, splits, inclusion probabilities and strata given with names
  are matched to the items by name (`c(q2 = "Lima", q1 = "Paris")` gives
  q1 Paris), and names that are not the item ids are an error of class
  `hr_bad_reference`. Items can be added with
  [`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  until a benchmark starts scoring the reference; after that every copy
  of it, and every reference grown from it, refuses new items with an
  error of class `hr_reference_locked`.

- **New
  [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)**
  states the scoring contract (correct, outcome and failure kind for
  each run), and
  **[`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)**,
  the default, compares text after folding case and white space, and
  sorts parse failures, errors, `NOT_IN_DOCUMENT` and failures an arm
  reports itself apart from wrong answers. A number in a label is
  compared in plain digits, so the label `100000` accepts `"100000"`.

- **New
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)**
  runs every arm on every item of the chosen splits `runs` times (5 by
  default; fewer warns) and returns one row per cluster x item x arm x
  run with correctness, failure kind, tokens by kind, cost and its
  provenance, seconds, the draw index and the id of the run’s trace. Run
  `r` is draw `r`, so repeated runs are separate cache entries and
  recorded draws, and an arm whose runs come back as one stored reply
  (the same cache entry, a repeated replay, a repeated response id) is
  refused with an error of class `hr_duplicate_draw`. Each draw is also
  recorded under the arm’s name, and
  [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  answers an arm only with its own replies, so replaying some of the
  arms, or the arms in another order, gives each arm what it got even
  when two arms sent the same request. The whole benchmark is held to
  one governor; a run with a refused request is recorded as a budget
  stop and counted wrong, and the benchmark warns (class
  `hr_budget_stopped`) with the number of runs stopped, the limits that
  stopped them, how many count against an arm, and the first run
  stopped. With no governor the limits are
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)’s,
  set for one run of a reader (400 calls), and the warning gives the
  values of the options that stopped runs and, for a call, spending or
  token limit, says to pass a governor sized for the benchmark. A reader
  stopped by its own check before its first request now leaves a
  `budget.preflight` note on the run’s trace naming the limit, and the
  errors that check raises carry the limit in `$limit`. Every run on an
  item with no label has `correct = NA`, failures included, so such an
  item never counts against an arm. Rows on the dev split are marked not
  reportable. [`print()`](https://rdrr.io/r/base/print.html) shows
  accuracy per arm over the reportable rows and labelled items, with the
  dev split’s accuracy in its own column, descriptive only.

#### Benchmark reports: `hr_report()`

- **New
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)**
  turns the reportable rows of an
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  into accuracy per arm (mean over runs within each item, then over
  items) with intervals that keep clusters together. With the default
  `method = "auto"` and at least 300 items and 30 clusters it uses
  `method = "bootstrap"`, which is now a studentised (bootstrap-t)
  cluster bootstrap rather than BCa: it resamples whole clusters with
  all their items, runs and arms (B = 2000, or 5000 with
  `confirmatory = TRUE`), each resample studentised by its own
  linearised standard error. Below either threshold it uses the new
  `method = "cluster_t"`, a cluster-robust t interval on the logit
  scale: the linearised variance of the ratio estimator with the C /
  (C - 1) factor and t quantiles on C - 1 degrees of freedom (Cameron
  and Miller 2015). Both can be asked for at any size. Where neither is
  defined (accuracy 0 or 1, or the same in every cluster) the arm gets
  Korn and Graubard’s interval, one-sided from the bound at 0 or 1, with
  a note. `method = "exact"` gives Clopper-Pearson on the effective
  number of items from cluster totals (Korn and Graubard) instead, with
  items rather than runs as trials, and `method = "bayes"` a Bayesian
  beta-binomial model with a cluster random effect and flat priors, with
  a note on its calibration. No interval treats items or runs as
  independent trials.

  These methods replace the BCa cluster bootstrap and the Bayesian model
  as defaults after the coverage simulation (`dev/sim-coverage.R`, 2000
  replicates) failed them: BCa covered 93.5% for accuracy at 0.75 and
  92.9% for the paired difference with 40 clusters, and 89.2% for the
  difference with 10 clusters; the Bayesian model covered 96.5% to 96.6%
  with 10 clusters, its misses 2.9% to 3.2% below the truth and 0.2% to
  0.5% above. With the new methods the same simulation passes: accuracy
  95.5% and 95.0%, difference 94.7% with 40 clusters; accuracy 95.8% and
  95.7%, difference 95.7% with 10 clusters.

- The report also gives paired differences between arms (every pair, or
  the ones in `contrasts`) with cluster-robust t intervals on C - 1
  degrees of freedom at every size, cut to \[-1, 1\] (when every cluster
  gives the same mean difference, so the cluster variance is 0, Tango’s
  score interval with the items as pairs and the item count scaled for
  C - 1 degrees of freedom, with a note), single-step max-t simultaneous
  intervals over all pairs from the multivariate t with the same
  correlation (Hothorn, Bretz and Westfall 2008), and bootstrap rank
  intervals in place of a ranking by point estimate. A pair whose
  cluster variance is 0 takes Tango’s interval at the Bonferroni share
  (1 - conf) / number of pairs, and the max-t critical value over the
  rest is then taken at 1 - (1 - conf) x (pairs with variance above 0) /
  (number of pairs), so the family stays at conf: with 3 pairs, one at
  variance 0, and 12 clusters it is 2.43, where the full-level 2.20 left
  the family at up to 6.7% error. The `critical` column is `NA` on the
  Tango rows. [`print()`](https://rdrr.io/r/base/print.html) shows the
  simultaneous interval of a contrast written against benchmark order
  (b - a) as the negated interval of its pair, \[-upper, -lower\], where
  it printed “-”; flip rate, TARa and run-level SD; pass^k with the
  unbiased estimator; dollars and tokens per item and per correct item
  with intervals, flagging arms whose cost rests on estimated token
  counts for more than 5%; the cost-accuracy frontier with each arm’s
  share of resamples on it; failure counts with accuracy recomputed
  without parse failures and refusals; and within-item and between-item
  variance on the probability scale, with a note to use 10 runs when
  runs account for more than 10%. Below 5 runs the report is descriptive
  only, without intervals. An item scored on some runs but not all is
  refused. It has [`print()`](https://rdrr.io/r/base/print.html) and
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  methods and leaves the caller’s random state as it was. The help
  writes its intervals with their brackets, such as \[r - q_hi se, r -
  q_lo se\] and “cut to \[0, 1\]”; they had been turned into 5 broken
  links, which R CMD check reported as a warning and the rendered help
  showed without brackets. The BCa intervals still used for cost and
  pass^k count a resample as below t0 only when it is more than 1e-12 x
  max(1, \|t0\|) below it, so a resample that ties with t0 up to a
  rounding error is not counted. This is the count in exact arithmetic;
  boot.ci() counts sum(t \< t0) and can differ when there are such ties
  (484 against 495 of 999 resamples in one test, moving the limits by
  less than 0.001).

#### Non-inferiority contrasts and the minimum detectable difference

- **New
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  and
  [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)**
  give the smallest paired accuracy difference a clustered design can
  detect, and the items needed for a given one, from n_eff = (t\_(C - 1,
  1 - alpha’) + t\_(C - 1, power))^2 x p_disc / Delta^2 with t quantiles
  on C - 1 degrees of freedom for C clusters, the degrees of freedom of
  the report’s non-inferiority bound, and the design effect DE = 1 +
  (m - 1) x ICC_D, where ICC_D is the intra-cluster correlation of the
  paired item difference and m becomes (cv^2 + 1) x m for unequal
  clusters. With `n_contrasts` above 1, alpha’ is alpha / n_contrasts,
  the first step of Holm. For 480 questions in 80 documents at ICC_D 0.2
  and p_disc 0.2 this gives DE 2, 240 effective items and an MDD of 8.2
  points, or 10.7 points after Holm over nine contrasts (8.1 and 10.4
  with normal quantiles).
  [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  finds the number of items by root finding, since the degrees of
  freedom depend on it, and both refuse a design of one cluster.
  [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  also takes a true difference below 0. Its
  [`print()`](https://rdrr.io/r/base/print.html) rounds the clusters up
  first and gives the items as that many clusters of m: 840 items in 140
  clusters of 6 for n_items 837.8, where it printed 838 items, not a
  multiple of 6.

- **New
  [`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  and
  [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)**
  fix non-inferiority contrasts (arm, reference arm, margin, whether it
  must also be cheaper) against an
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  before a benchmark scores it. A confirmatory margin below the design
  MDD at 80% power after Holm is refused with an error of class
  `hr_margin_below_mdd`; with `confirmatory = FALSE` it is registered as
  exploratory. The check is at one-sided alpha 0.025 or less whatever
  level the design was given at, and a design with more items or
  clusters than the reference holds on the test and final splits is
  refused. A reference already being scored, or one rebuilt with the
  same content, is refused (`hr_registration_after_scoring`), and the
  registration is hashed.
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  takes whole numbers of items and clusters only.

- **[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  gains `registration`.** Each registered contrast is non-inferior only
  if the one-sided lower bound of the accuracy difference is above
  -margin and, when it tests cost, the upper bound of the paired cost
  difference (BCa cluster bootstrap) is below 0. The accuracy bound is
  the cluster-robust t bound of the report’s paired differences, taken
  one-sided on C - 1 degrees of freedom (the Tango bound with items as
  pairs when every cluster gives the same mean difference), so at
  one-sided 0.025 it is the lower end of the printed 95% contrast
  interval. It replaces the BCa cluster bootstrap bound, which
  undercovered the paired difference in the coverage simulation (92.9%
  with 40 clusters, 89.2% with 10). Confirmatory contrasts are tested
  with Holm’s step-down procedure, exploratory ones at alpha. The design
  and achieved MDD are printed beside every verdict (the achieved one on
  the linearised standard error and the same t quantiles as
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
  and `NA` when the cluster variance is 0), and a contrast that passed
  its registered test is reported as passed even when the achieved MDD
  exceeds its margin. Tango’s (1998) paired score interval on effective
  counts, at most one pair per item, is given as a cross-check. A
  changed registration, or one for another reference, is refused. Each
  contrast’s `p_value` is the smallest one-sided level at which it
  passes, found by bisection down to 1e-6. With a cost test the search
  stops at 1 / (B + 1) (1 / 2001, about 5.0e-4, at B = 2000): below that
  level the BCa cost bound is the most extreme resample and stops
  moving, and a contrast whose resamples were all cheaper was reported
  at 1e-6 where a cluster t on the paired cost means gave 2.3e-4.

- **Dev-split rows are refused as evidence.** A report with a
  registration or `confirmatory = TRUE` errors with class
  `hr_dev_not_evidence` when the benchmark holds rows on the dev,
  exploratory or calibration split or rows marked not reportable.

#### Benchmarking reading recipes

- **New
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  and
  [`gr_arms()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)**
  wrap reading recipes as benchmark arms. Each run reads the item’s
  document with
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
  or with
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  when the document is already chunked, and returns the `gr_answer`,
  with every request on the run’s own trace. That trace gives every
  request of the run, segmenter and reader requests included, the run’s
  draw index, so repeated runs under a cache or a recording are separate
  draws. A reader that refuses to start because the run’s call or
  spending limit leaves too little returns a partial `NOT_IN_DOCUMENT`
  answer noting the limit, which is scored as a budget stop rather than
  an error. The arm records the recipe and its settings, and its version
  is the package version.

- **New
  [`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)**
  builds an
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  of questions about documents from questions, documents and acceptable
  answers (one string or a list of alternatives per question).
  Unanswerable questions, given as flags, ids, positions or the answer
  `NOT_IN_DOCUMENT`, are labelled `NOT_IN_DOCUMENT`. The payload an arm
  is given holds the question and the document only: whether an item is
  unanswerable is in its label. Items are clustered by document by
  default.

- **New
  [`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)**
  marks an answer right when it contains an accepted answer after
  folding case, white space and thousands separators (`"1,204"` matches
  `"1204"`), with numbers matched whole (`"12"` is not in `".12"` or
  `"-12"`, but is in `"12-15"`, and `"45.2"` is in `"45.2m"`), a numeric
  label written in plain digits, and an unanswerable item right when
  [`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
  is true and no limit or refusal stopped the run. Wrong answers are
  sorted into parse failures, budget stops, refusals, `not_in_document`
  and wrong.

- [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)’s
  help now says it is descriptive, and points to
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  and
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  for a comparison with intervals.

#### Judges and their validation record

- **New
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)**
  asks a model to choose between candidates (`"select"`), compare two
  (`"pairwise"`) or grade one against a reference (`"grade"`).
  Candidates are shown under the letters A, B, … only, and each item is
  asked in two presentation orders: reversed for candidates, reference
  first and then response first for grading. A verdict that differs
  between the orders, mapped back to the candidate it names, is returned
  as `"unresolved"` with `degradation = "judge_inconsistent"`; a failed
  request or a reply with no allowed verdict is `"failed"`. One order is
  allowed for grading only. With more than two candidates, `orders`
  above 2 shows cyclic rotations. Requests go through the same path as
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md),
  so the governor, a cache keyed with `draw_index` and the trace all
  apply, under the labels `judge.<mode>.o<k>`. They are recorded in the
  judge’s own trace and their cost in `$judge_cost`, never in the trace
  of the run being judged, which gets a local note pointing at the
  judge’s trace; the judge is held to what that run’s governor has left.

- **New
  [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md)**
  holds what decides a judge’s answers (model, mode, rubric, the
  package’s instructions for the mode, reply schema, orders, how
  verdicts are combined, the positive grade) with a SHA-256 hash of
  them.

- **New
  [`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  and
  [`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md).**
  From blind human labels on a judge’s decisions, the record gives
  Cohen’s kappa with a bootstrap interval and the full
  [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
  set, sensitivity and specificity with Wilson intervals (and the
  sensitivity half-width), and the swap-inconsistency rate. Items the
  judge left unresolved or failed on count as not called positive, the
  rule
  [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
  applies, so the figures describe the judge as the scorer uses it.
  Fewer than 50 human-positive or 50 human-negative items are refused
  with `hr_judge_too_few_labels`, and the minimums cannot be lowered.
  Text labels such as `"pass"` and `"fail"` default to the
  configuration’s positive grade. A `judge` column that shares no value
  with `human` (logical calls beside `"pass"`/`"fail"` labels) is
  refused with `gr_bad_setting` rather than counted as all negative. The
  optional columns `consistent`, `outcome` and `config_hash` are read by
  exact name, so an extra column such as `consistently_long` is ignored.
  The record is keyed by the configuration hash;
  [`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  is `FALSE`, naming what changed, when the model, rubric, prompt,
  schema, orders, aggregation or positive grade differ, or when the
  record was edited.

- **New
  [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)**,
  a benchmark scorer that grades each output against its label with a
  grade-mode judge. It refuses to be built without a valid record
  (`hr_judge_unvalidated`). Unresolved judgements count as wrong and
  failed ones as errors, and the judge’s requests stay in the scorer’s
  own trace, out of the benchmark’s cost columns. A `draw_index`
  argument sets the cache draw for the judge’s requests.

- **New
  [`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md)**
  corrects judge-scored accuracy with human labels on a sample through
  [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md):
  prediction-powered inference, and the inverse-probability weighted DSL
  form when the labelling probabilities vary. It also reports the
  uncorrected judge mean. Its normal interval needs enough labelled
  items in every inclusion stratum; with few labels at small inclusion
  probabilities it is too narrow.

#### Baselines without a model

- **New
  [`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)**
  turns texts into an l2-normalised tf-idf matrix: lower-cased runs of
  letters and digits, terms in at least `min_df` texts (at most
  `max_features`, the most frequent), raw counts times the smoothed idf
  log((1 + n) / (1 + df)) + 1. It is a dense base R matrix, which suits
  a reference or screening set of a few thousand texts.

- **New
  [`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)**,
  a ridge-penalised logistic regression on tf-idf features fitted by
  iteratively reweighted least squares and cross-fitted by fold, so each
  item is predicted by a model that never saw it. Folds are stratified
  by label, or keep each `cluster` whole. The vocabulary and idf are
  fitted on each training fold only. More than two labels are fitted one
  against the rest. It returns the out-of-fold probabilities and labels,
  the training size of each fold, and accuracy with a Wilson interval
  from
  [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md).

- **New
  [`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)**
  simulates prioritised screening over a fully labelled set, as ASReview
  does: it starts from `seed_n` relevant and irrelevant records, refits
  after each `batch`, and screens the record with the highest predicted
  relevance next. The model is the same ridge logistic regression or
  multinomial naive Bayes. It returns the screening order, the recall
  curve, the records screened to reach 95% recall, <WSS@95> and the
  number a random order would need on average.

- **New
  [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)**,
  the hypergeometric stopping test of Callaghan and Muller-Hansen (2020)
  for prioritised screening. After each screened record it gives the
  p-value for recall still being below `target` given the records left
  unscreened, and the first point where screening may stop at `alpha`.
  It takes a vector of relevance in screening order, with unscreened
  records as trailing `NA`, or an
  [`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
  result.

#### Drift checks

- **New
  [`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md)**
  reruns an arm live on the items of a frozen
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  and reports, item by item, which items were lost, gained or moved,
  with their most common output before and after. Two tests are fixed in
  the call, with `alpha` and an optional `alert` threshold. (a) The
  accuracy change, live minus frozen, by a BCa cluster bootstrap over
  documents on paired item accuracy, with the clustered McNemar test of
  Obuchowski (1998) beside it as a cross-check. (b) Excess instability:
  the flips between frozen and live runs against the flips among
  replicate runs, frozen and live, one-sided, on the same cluster
  resamples. Per item it estimates the squared change in accuracy, so it
  sees losses and gains that cancel in accuracy and noisy items that
  turn deterministic; it needs at least 2 live runs. The alert is
  crossed when the whole accuracy interval lies beyond the threshold,
  and `alert_not_ruled_out` reports the weaker reading, an interval that
  reaches beyond it. Moved items whose runs disagreed are counted apart
  in the printout, since their moves can be run-to-run variation. Fewer
  than 5 frozen runs is refused (`hr_drift_few_runs`), as are a changed
  arm, another reference or scorer (`hr_drift_mismatch`) and a live
  rerun answered from a cache or a recording (`hr_drift_not_live`). The
  live rerun is returned as an `hr_bench`.

#### Validation of the intervals and the MDD

- **A nightly validation job checks the report’s statistics on simulated
  benchmarks.** `dev/sim-coverage.R` simulates clustered corpora with a
  known effect, document ICC and run variance, reports each with
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
  and gives the coverage of the accuracy and paired difference intervals
  over 2000 replicates with its Wilson 95% interval, in a large design
  (386 items in 40 clusters, studentised cluster bootstrap) and a small
  one (50 items in 10 clusters, cluster-robust t on the logit scale,
  with the Korn-Graubard interval beside it). An interval passes when
  that Monte Carlo interval contains 95% and its lower end is at least
  93%. `dev/sim-power.R` sets
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  against a power simulation of the report’s cluster-robust t
  non-inferiority bound and passes when the simulated MDD is within 1
  point. Both exit with status 1 on a failure. The workflow
  `.github/workflows/validation.yaml` runs them every night and by hand,
  never on pull requests, and keeps the printed tables as an artifact.
  The power table’s `power_check` column also marks a design whose
  simulated power at the formula’s MDD lies below or above the target
  beyond Monte Carlo error (“below target” or “above target”), without
  failing the run.

- The
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  help gives the power simulation’s result (2000 replicates, seed 1):
  the MDD was 0.16 and 0.17 points below the simulated one at 80 equal
  clusters (simulated power at the formula’s MDD 78.55% and 78.30%) and
  0.25 points above it at 40 unequal clusters (81.60%). With normal
  quantiles it was 0.26 and 0.41 points below at 80 clusters (power
  77.20% and 76.05%, short of 80% beyond Monte Carlo error), which is
  why the formula takes t quantiles.

#### Screening recall against a target

- **`gr_reference(of = "stacked")`** draws the reference the screening
  help recommends in one sheet: every record the screener kept, and `n`
  of those it excluded. Each row records its stratum and its inclusion
  probability (1 for a kept record, `n` / N for an excluded one). A
  blind sheet keeps both inside a key per row of one length, so they do
  not reveal what the model decided. `frame =` is accepted as another
  name for `of`. The other frames draw exactly as before.

- **[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  estimates recall on a stacked reference** instead of refusing it: the
  ratio of Horvitz-Thompson totals, K / (K + M), with M the projected
  number of eligible records excluded and exact hypergeometric bounds on
  M mapped into a one-sided lower bound on recall. A kept sheet and an
  excluded sheet stacked with
  [`rbind()`](https://rdrr.io/r/base/cbind.html) are read the same way
  with `of = "stacked"`; without it they are still refused.

- **[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  gains `recall_target` (0.95), `conf` (0.95) and `max_lost`**, and its
  result gains `recall`, `lost`, `false_exclusion`, `work_saved`,
  `unclear_rate`, `strata` and `verdict`, which says whether the
  one-sided lower bound on recall reaches the target (or the bound on M
  is within `max_lost`). A sample of everything screened bounds recall
  with Clopper-Pearson, except that when it is every screened record
  recall is known exactly and is its own bound (`method = "census"`: 25
  of 25 eligible kept gives a bound of 1, not the 0.887 Clopper-Pearson
  gives); a sample of the exclusions alone bounds M but not recall.
  Every field it returned before is unchanged.

- **New
  [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)**
  gives the reference size a recall target needs: n \>= ln(alpha) /
  ln(T) eligible records with no miss (59 for 95% at 95% confidence),
  divided by `prevalence` for the records to draw, and for a sample of
  the exclusions the exact hypergeometric size for a frame of `frame_n`
  records with at most `max_lost` lost, beside the binomial one. For a
  sample of everything screened, giving `frame_n` with `prevalence` caps
  the draw at the frame: a frame of 500 records at 5% prevalence holds
  about 25 eligible records, fewer than the 59 needed, so `n` is 500
  (judge every record) rather than 1180. A smaller draw cannot pass
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
  which bounds such a sample with Clopper-Pearson: 388 records with 22
  eligible and none missed give a bound of 0.873.

#### References from several reviewers

- **`gr_reference(reviewers = k)`** writes one decision column per
  reviewer, `human_decision_1` to `human_decision_<k>`, and a
  `consensus` column for an adjudicator, one row per document. With one
  reviewer the sheet is as before.

- **New
  [`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)**
  forms one decision per document from several reviewers, by
  `rule = "majority"` (a tie is settled by `consensus` where filled, and
  otherwise settled as include), `"any_include"` or `"adjudicated"` (the
  `consensus` column, an error where reviewers disagree and it is
  empty). It also reads a long sheet with a `reviewer` column. Each row
  says in `consensus_from` how its decision was reached. Columns named
  `human_decision_<x>` are reviewers, except those ending in `_note`,
  `_notes`, `_comment`, `_comments` or `_date`.

- **[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  compares the screener with the reviewers’ consensus** on a
  multi-reviewer sheet, and stops only on a disagreement nobody settled,
  saying how many there were. Its result gains `reviewers`: agreement
  between each pair of reviewers from
  [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
  (kappa beside PABAK, AC1 and the prevalence and bias indices, never
  alone), Krippendorff’s alpha with three reviewers or more, and each
  reviewer’s sensitivity and specificity against the consensus. On a
  stacked reference both are weighted by the stratum weights recall
  uses, with exact hypergeometric bounds for the rates and a bootstrap
  within the sampled stratum for agreement; the notes flag the weighted
  kappa interval as approximate when fewer than 100 excluded records
  were sampled. A one-reviewer calibration is unchanged.

#### Agreement on extracted fields

- **New
  [`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md)**
  compares two extraction tables for the same documents, a model’s
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result against a person’s or two people’s, matched on `document`. Each
  field gets Krippendorff’s alpha at a declared level (`levels =`; by
  default interval for `integer` and `number` fields and nominal
  otherwise) with a bootstrap interval over documents, percent agreement
  and the number of documents compared. “Not reported” is a category of
  its own in a nominal field; an ordinal, interval or ratio field gets a
  separate row for agreement on whether it is reported, and its value
  row covers the documents both tables report. Below 30 documents or for
  a constant field alpha is `NA` and a note says why. Rows of a
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result that failed or were read only in part are not taken as
  reporting nothing, duplicates are left out (a blank `duplicate_of`, as
  a table saved with `write.csv(na = "")` reads back, is not a
  duplicate), and `$pairs` lists every cell side by side for reading the
  disagreements.

#### Signals, calibration records and gate thresholds

- **New
  [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  and
  [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md).**
  [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  records a value the package produced about its own work (a
  self-signal) into a trace, as a local step labelled `"signal"`; it
  sends no request, so requests and cache keys are unchanged.
  [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  reads every recorded signal back from a trace, an answer or a list of
  them as one table, a row per value, with the value as text and as a
  number. A trace object reached twice in the list is read once; two
  separate traces are both read even when they share a `run_id` (two
  traces made with `gr_trace(run_id = "pilot")` give 2 rows, not 1).

- **Three readers record a signal.** `iterative` records
  `gr.iterative.can_answer` for each step whose reply parsed, `preview`
  records `gr.preview.skip` for each section of a usable plan (the
  plan’s own decision, before any section is demoted to skim), and
  `ensemble` records `gr.ensemble.adjudicate` as `"model"`,
  `"concatenated"` or `"single member"`. No reader behaves differently:
  each answer, each request and each cache key is as before, and a trace
  from these readers has one more local step per signal.

- **New
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)**
  measures a signal against a graded set that must include unanswerable
  items, on the half of each cluster’s items not used to fit the map:
  the Brier score with its reliability, resolution and uncertainty
  decomposition (and the two within-bin terms that make it exact over
  binned forecasts), type-2 AUROC, the area under the risk-coverage
  curve with the selective risk at 50, 80 and 90 percent coverage, and
  the debiased equal-mass calibration error over 5 to 10 bins, each with
  a cluster bootstrap interval (`NA` when the calibration half has one
  cluster, with a note below 20 clusters). AUROC and the risk-coverage
  curve are taken on the signal itself, so a signal that is higher when
  the item is wrong shows an AUROC below 0.5 even after the map turns it
  round. The map is Platt scaling, isotonic regression (only from 1000
  graded items, counted before the split) or none. A map that does not
  increase with the signal keeps the record advisory. The record is
  keyed by served model, model version, task, format, prompt hash,
  effort, module and contract version, starts `advisory`, says why, and
  has [`print()`](https://rdrr.io/r/base/print.html) and
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  methods.

  The ECE and the Brier decomposition use the same bins, and items with
  the same `p` always share one, so the ECE does not depend on row
  order. A signal with two values on 200 documents of 10 items,
  calibrated within each value, had an ECE of 0.044 that fell to 0 when
  its rows were shuffled; it is now 0 either way. `bins` is the number
  of bins formed: 2 for a logical signal, which therefore stays advisory
  under the 5-bin rule (it reported 10). A graded set with a `split`
  column is calibrated on its `calibration` rows alone, with the rows
  left out counted in `notes` and a message (before, dev, exploratory
  and test rows were fitted and scored too), and one with no calibration
  row stops with `hr_bad_calibration`. Columns are read by exact name,
  so a `cluster_size` column is no longer taken for `cluster` (40
  documents of 10 items collapsed to 1 cluster).

- **New
  [`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md)**
  is `FALSE` when any key field of a record differs from the run’s, and
  names the fields.

- **New
  [`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)**
  picks a threshold by Learn-then-Test: the thresholds are tested from
  strict to loose with a one-sided Clopper-Pearson bound on the error
  among accepted items, or on the miss rate for exclusions, and the
  loosest one before the first failure is kept. The bound is taken on an
  effective sample, `n / deff` items with `k / deff` errors, where the
  design effect `deff` is the cluster variance of the error rate over
  the variance with each item its own cluster, never below 1. Taken at
  face value, items from one document are not independent: with 30
  documents of 20 items, a true error rate of 0.12 and an intraclass
  correlation of 0.3, a gate at `alpha = 0.10` and `delta = 0.05` passed
  in 8.7 percent of draws; it now passes in 2.4 percent. Unclustered
  items give `deff = 1` and the exact Clopper-Pearson bound. `$gate`
  reports `deff` and `n_eff`, and `$gate$path` the `deff` of every
  threshold. It starts where enough items are acted on for the bound to
  reach `alpha`, and reports `"none passed"` or `"too few items"` when
  nothing qualifies. A record becomes `"gating"` only with a passing
  threshold, at least 100 wrong items in the graded set, a map that
  increases with the signal and an ECE over at least 5 bins.

- **New
  [`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
  and
  [`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md).**
  A signal gates its action only with a gating record for the same
  signal and action whose key matches the run; otherwise it stays
  advisory (`gated = FALSE`), the item is routed to a check, a person or
  nowhere, and `reason` says why. Nothing in the package calls
  [`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
  yet, so nothing gates by default.

#### Splits and label sheets

- **New
  [`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)**
  assigns reference items to the `dev`, `exploratory`, `calibration`,
  `test` and `final` splits by cluster, so every item of a document
  lands in the same split. The default shares are 10% dev, 10%
  exploratory, 30% calibration and 50% test. Each cluster’s place comes
  from the SHA-256 digest of the seed and its id, so the assignment does
  not depend on row order or the session’s random state. With
  `method = "stable"` (the default) adding or dropping documents never
  moves another one; `method = "balanced"` gives each split its share of
  clusters by largest remainders. The result reports clusters and items
  per split beside the target shares, and warns with `hr_empty_split`
  when a split given a share receives nothing. A whole-number cluster id
  is hashed written in full, so document 300000 gets the same split
  stored as a double or as an integer (as a double it was hashed as
  `"3e+05"` and went to test instead of calibration with seed 7).
  Columns are matched by exact name: a frame with no `item_id`, `id` or
  `cluster` column no longer takes `ideal_answer` for its ids or
  `cluster_size` for its clusters.

- **New
  [`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)**
  writes a CSV for people to label, with an instructions file beside it,
  for five kinds of set: QA answers, a screening reference, extraction
  fields, a calibration graded set and judge validation verdicts. Each
  row has an `item_id` and empty decision columns. A blind sheet (the
  default) copies only the columns a person needs to judge the item, so
  no model output or sampling detail reaches it. With several reviewers
  each gets a sheet of their own. The help page gives the number of
  items each set needs for the package’s own evaluation. Ids come from a
  column named exactly `item_id` or `id`: a frame whose only such column
  was `ideal_answer` used to put the reference answers in the `item_id`
  column of a blind sheet; it now gets `qa-0001`, `qa-0002`, and so on.

- **New
  [`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)**
  reads filled sheets back, checks every value and id, and stops with
  `gr_bad_labels` naming the sheet, row and item of each value it cannot
  read. It returns a screening reference that
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  and
  [`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)
  take, an extraction table for
  [`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md),
  and calibration labels with clusters, with the items’ own columns
  joined back by id (an item column named like a decision, such as the
  model’s `answer` or a judge’s `verdict`, comes back as
  `model_<name>`). Only a calibration sheet written with `blind = FALSE`
  has the `correct` column
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
  needs; a blind one gives reference answers, and the model’s answers
  are scored against them to make `correct`. A `blind = FALSE`
  calibration sheet read back without `items` turns its `model_score`
  column back into the number `score`, so it is a graded set either way
  (before, only the read with `items` was). A blind screening sheet
  carries the reference’s frame as an opaque key, so it reads back as a
  usable reference without `items`.
