# Changelog

## harnessr 0.6.0.9000

### Renamed core functions

The 27 core functions that still began with `gr_` now begin with `hr_`,
like the rest of the core layer. Document-layer functions such as
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
and
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
keep `gr_`.

| Old name | New name |
|----|----|
| `gr_api_key()` | [`hr_api_key()`](https://elkronos.github.io/harnessr/reference/hr_api_key.md) |
| `gr_backend_client()` | [`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md) |
| `gr_budget()` | [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md) |
| `gr_cache()` | [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md) |
| `gr_cache_clear()` | [`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md) |
| `gr_cache_client()` | [`hr_cache_client()`](https://elkronos.github.io/harnessr/reference/hr_cache_client.md) |
| `gr_cache_stats()` | [`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md) |
| `gr_call()` | [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md) |
| `gr_client()` | [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md) |
| `gr_count_tokens()` | [`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md) |
| `gr_ellmer_client()` | [`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md) |
| `gr_embed()` | [`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md) |
| `gr_estimate_cost()` | [`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md) |
| `gr_mock_client()` | [`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md) |
| `gr_model_info()` | [`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md) |
| `gr_model_limits()` | [`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md) |
| `gr_models()` | [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md) |
| `gr_options()` | [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md) |
| `gr_register_model()` | [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md) |
| `gr_replay_client()` | [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md) |
| `gr_set_tokenizer()` | [`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md) |
| `gr_tokenizer()` | [`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md) |
| `gr_trace()` | [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md) |
| `gr_trace_cost()` | [`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md) |
| `gr_trace_save()` | [`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md) |
| `gr_trace_summary()` | [`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md) |
| `gr_truncate_tokens()` | [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md) |

- The old names are gone, with no alias, so a script that calls
  `gr_call()` stops with “could not find function”.
- Class names and condition classes keep `gr_`:
  `inherits(hr_mock_client(f), "gr_mock_client")` is `TRUE`, and a
  handler for `gr_call_cap` catches the same condition as before.
- Caches, traces saved with
  [`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md),
  replay cassettes and signal calibrations written by earlier versions
  still load.

### Context, effort and revision checks

Each option below is off by default, so a default spec sends the
requests it sent before and keeps its store, cache and replay keys. Each
new setting is declared with its evidence (`untested`), is listed by
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md),
and has a walkthrough that says how to test it with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md).

- `hr_truncate(text, n, keep)` cuts text to `n` tokens and keeps the
  part asked for: the start (`"head"`, the default, which is
  `gr_truncate_tokens()` itself), the end (`"tail"`), both ends
  (`"both"`) or the units with the highest `scores` (`"scored"`). With a
  trace, a cut writes a `"truncate"` step naming the piece, the part
  dropped (`dropped_part`) and the tokens it held.
  [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)
  states which pieces of a request are never cut (`pin`), which are cut
  first (`cut_order`) and which part of each is kept (`keep`), and
  [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
  applies one to a set of named pieces.

- [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  gains `context_policy`. With a policy, `refine` fits its state and the
  new excerpt into the input budget together instead of halving it; the
  merges of `map_reduce` and `skim`, `hierarchical`’s summaries and
  `preview`’s outline and skims are cut under the policy’s keep rule for
  their piece; and the readers that pack whole chunks (`stuff`,
  `retrieve`, `rerank`, `iterative`, `preview`’s re-read) write a
  `"truncate"` step naming the chunks they left out. Under
  `order_merges = TRUE`, the findings a merge combines and the answers
  `ensemble` adjudicates are placed by `context_order`. `NULL`, the
  default, keeps each reader’s cuts as they were.

- [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  gains `refine_state`. `"ledger"` makes `refine` carry a numbered list
  of findings: each request replies with edits (`ADD`, `REPLACE n`,
  `DROP n`) that the code applies, so a finding no edit names is kept
  word for word and a corrected one is replaced, and one more request,
  `refine.answer`, answers from the list. `"draft"`, the default,
  rewrites the draft as before.

- `restate` gains `"window"`, which repeats the question once the
  excerpts pass the model’s effective window. No model’s window is
  measured yet, so it uses 50,000 tokens and warns
  (`gr_window_unmeasured`).

- [`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
  builds a benchmark of what a reader keeps as it condenses a document:
  facts planted in a synthetic document or a text of your own, lures
  (the same measure for a near-namesake, with another value) and a fact
  stated wrongly early and corrected late, each document given forwards
  and reversed by paragraph
  ([`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md)).
  It returns an
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  and a scorer that finds the values in the answer with no model judge,
  for
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  to run arms that differ in `refine_state`, `context_policy` or the
  reader; and
  [`gr_condensation_summary()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
  gives each arm’s fact recall, lure rate, whether the correction won
  and recall of the facts read last. The live comparison on real
  documents is not part of this release.

- [`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
  is an effort policy that starts every stage low and sends the next
  stage raised when a trigger fired in the one before: a cut, a reply
  stopped at its cap, a reply that is not the JSON asked for or does not
  fit its schema, a reply the caller names (such as `NOT_IN_DOCUMENT`
  from every request of a stage), or an event the caller reports with
  [`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md).
  Effort changes only at stage boundaries, at most `max_escalations`
  times a run. The stage after a raised one goes back to the base effort
  unless it fired a trigger too and a raise is left. A cut counts for
  the stage whose request it was made for. Each raise is an
  `"effort.escalate"` step of the trace and its outcome an
  `"effort.resolve"` step;
  [`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)
  lists them. `gr_call()` takes the policy as its `effort`.

- [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  gains `effort_mode`. `"escalate"` makes the read’s `effort` such a
  policy, starting at `effort` (`"low"` when unset) and raising to
  `"high"`; `iterative` reports a quotation it could not verify,
  `ensemble` members that disagree, and screening an unclear decision or
  draws that disagree. `"static"`, the default, sends `effort` as
  before.

- [`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
  compares an effort policy’s arm with fixed-effort arms on a benchmark,
  with
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)’s
  non-inferiority test at a stated `margin` and Holm’s procedure over
  the comparisons, and reports each arm’s accuracy, cost, requests per
  run, raises and the requests sent raised. Without a registration from
  [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  the contrasts are marked post hoc. It plans nothing: there is no
  effort planner.

- [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  gains `revision_check`. `"judge"` puts an advisory check behind the
  word-counting guard of the `coherence` passes: each sentence a kept
  revision changed is graded by
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
  its requests held to the run’s limits, against the draft sentences it
  came from, as `"holds"`, `"stronger"` or `"not_entailed"`. A flagged
  sentence is warned about (`gr_revision_flagged`), counted in a
  `flagged` column of `$coherence` and listed in `$revision_flags`; the
  revision is kept as it was. “Is associated with” made “reduces” passes
  the word lists and is flagged by the judge; a hedge moved into another
  sentence is not. `"lexicon"`, the default, sends no judge request.

- Left out: a look-up step for `hierarchical` (reading the chunks behind
  the summary an answer rests on) and showing `iterative` its earlier
  queries. Each changes the requests of a reader in a way that needs its
  own benchmark arm, and neither was needed for the policy itself.

The read stage now has 50 settings and the synthesise stage 29, 224 in
all.

### Reading options

Each option below is off by default, so a default spec sends the
requests it sent before and keeps its store, cache and replay keys. Each
is declared with its evidence (`untested` unless a source is named), is
listed by
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md),
and has a walkthrough in
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
that says what it trades off and how to test it with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md).

- `preview` logs each section its plan skips as a `preview.skip` step in
  the trace, with the section’s BM25 score against the question. Two
  settings guard against a plan that skips the answer: `unskip_k` reads
  the `k` sections that match the question’s words best even when the
  plan skips them (`notes$unskipped`), and `reread_on = "not_found"`
  follows a `NOT_IN_DOCUMENT` answer with one request (`preview.reread`)
  over the sections not read in full (`notes$reread`).

- `rerank` records `notes$retrieval_low_score = TRUE`, and a
  `rerank.low_score` trace step, when every candidate the model scored
  is below `rerank_min_score`; before, only the reason string said so.
  The new setting `low_score = "read_top_k"` sends the 5 best-scored
  candidates to the answer request in that case instead of answering
  `NOT_IN_DOCUMENT` unasked, and marks a `NOT_IN_DOCUMENT` reply with
  `retrieval_low_score`.

- `retrieve` and `iterative` rank chunks through one fusion function. At
  `fusion = "default"` each keeps its 0.6.0 ranking (`retrieve` blends
  cosine with BM25 on lexical embeddings, `iterative` uses cosine), so
  the two give the same order on the same inputs whenever the embeddings
  are not lexical. `fusion = "rrf"` is reciprocal rank fusion of the
  cosine and BM25 rankings for both, with `rrf_k = 60`, the constant
  Cormack, Clarke and Buettcher (2009) use.

- Every answer from
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  carries `$outcome`: `"answered"`, `"partial"`, `"not_found"`,
  `"refused"` (a limit stopped the run) or `"failed"` (every model
  request it made failed, or the reader reports an error), for every
  reader.
  [`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
  given an answer reads it, so a refused or failed run no longer counts
  as the document lacking the answer; given a string, or an answer
  without the field, it tests the sentinel as before.
  [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  writes the field.

- `answer_format = "schema"` sends the answering requests with a JSON
  schema holding `answer` and `outcome`, so the model reports a
  not-found in a field rather than with the sentinel; `"parsed"`, the
  default, sends the free-text requests as before. Owner decision DEC-05
  keeps the default until a live comparison of the two on the default
  model.

- `premise_verdict = "structured"`, with `premise = TRUE`, asks the
  answering requests for a `premise_status` field and the `quote` from
  the excerpts that contradicts the question, in a JSON schema, and
  checks the quote with the span matcher
  [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  uses against what the request was shown (and the document, where that
  was text a model wrote, as in `skim` and `hierarchical`). The answer
  gains `$premise_verdict`. In `map_reduce`, a chunk’s flag whose quote
  is absent or not found in the chunk is dropped
  (`notes$premise_dropped`), and a verified one goes to the merge and
  sets `notes$degradation` to `"premise_flagged"`. The default,
  `"sentence"`, sends what `premise = TRUE` sent before.

- New
  [`gr_methods_text()`](https://elkronos.github.io/harnessr/reference/gr_methods_text.md)
  writes a plain paragraph for a methods section from a result, a trace
  or a benchmark: the harnessr version, the models asked for and the
  models the provider said answered, request and run counts, the tokens
  sent (a request a cache or a recording answered sent none, and its
  recorded tokens are given apart), the settings changed from their
  defaults, and a hash of each system prompt by stage. It reads only the
  record and makes no claim beyond it.

- New
  [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  builds one stage of a run (`"ingest"`, `"segment"` or `"read"`) as a
  step, a function of `(input, ctx)`, with its settings checked when the
  step is built, and
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  returns the chunks `retrieve` would send, ranked and scored, without
  the answer request. Inside an
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
  run function they use the run’s `ctx$client` and `ctx$trace`, so a
  benchmark counts and limits their requests; they are composed by hand
  for now, and carry the attributes a later
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
  will read.

### Pipeline options

Each option below is off by default, so a default run sends the requests
it sent before, keeps its store, cache and replay keys, and returns the
tables it returned. Each is declared with its evidence (`untested`
unless a source is named), is listed by
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md),
and has a walkthrough that says how to test it with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md).
The settings come to 219 in all.

- [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  gains `resolve = "vote"`, which keeps the value most of a document’s
  chunks gave, for no extra request; a tie goes to the earliest of the
  tied values, as `"first"` chooses. `agreement_columns = TRUE` adds
  `<field>_agreement` (how many of the chunks that reported a field give
  its most common value, as `"2/3"`) and `<field>_conflict` to the
  table. An abstract that says 240 and two results paragraphs that say
  236 give 240 under `"first"`, 236 under `"vote"`, and `"2/3"` with a
  conflict under both. Each answer’s `notes$agreement` holds the same
  counts.

- [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  gains `criteria_schema`. At `"per_criterion"` each reply also gives
  every criterion’s status, `"met"`, `"not_met"` or `"not_reported"`,
  which the table holds in `criteria_status`, and an exclusion needs an
  inclusion criterion `"not_met"` or an exclusion criterion `"met"`: a
  reply that excludes with a criterion not reported and none not met is
  recorded as `"unclear"`, for a person. The default, `"decision"`,
  sends the request and schema it sent before.

- [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  gains `samples` and `sample_rule`. Above 1 sample, each document’s
  screening request is sent that many times as separate draws (each with
  its own `draw_index`, so a cache keeps them apart), and
  `"include_if_any"` includes a document any draw included, excludes one
  only when every draw excluded it, and leaves the rest `"unclear"`;
  `"majority"` takes the decision most draws gave. The table gains
  `sample_decisions` and `include_share`. At the default, 1, one request
  is sent as before.

- [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  gains `packing` and `runt_merge`. `packing = "balanced"` keeps the
  number of chunks greedy packing makes and evens their sizes
  (`paragraph`, `sentence`, `recursive`, `structural`, `semantic`).
  `runt_merge = "both"` merges a first chunk under `min_tokens` forward
  into the second, which the backward merge could not reach. The
  defaults, `"greedy"` and `"backward"`, pack as before.

- [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  gains `semantic_threshold`. At `"texttiling"`, the `semantic`
  segmenter cuts by TextTiling’s depth score (Hearst 1997): the
  similarity between the windows before and after each gap, read from
  the same embeddings, cut at valleys deeper than Hearst’s cutoff and
  than the spread of the similarities, so a text on one topic gets at
  most about one cut instead of one gap in ten. The default,
  `"percentile"`, cuts as before.

- Every block of a document says which table it is a row of, if any:
  [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
  adds `table_id` and `table_rows` to `$blocks` (each unbroken run of
  `"table"` blocks is one table; `table_rows` is `"3"` for a row from
  Word or HTML, `"1-12"` for a Markdown table read as one block), and
  `paragraph` chunks of a document with a table carry `table_id` and
  `table_rows` for the rows they hold. This is provenance only: no text
  and no request changes, and a document with no table gets no new chunk
  columns.

- [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  gains `table_packing`. At `"grouped"`, `paragraph` packs each table on
  its own and opens every chunk of it with the table’s header row, so a
  60-row table cut into three chunks gives three chunks that each start
  with the header. The default, `"rows"`, packs rows as before.

- [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
  gains `ocr_trigger`. At `"after_running_lines"`, under `ocr = "auto"`,
  a PDF page is counted against `ocr_min_chars` once the running heads,
  feet and stamps the layout pass drops are taken out, so a scanned page
  whose text layer holds only a 60-character fax header or Bates stamp
  is OCR-ed. The default, `"raw_text"`, counts the whole text layer as
  before.

- The blocks of a PDF page OCR read now have `kind = "ocr"` (headings
  keep `"heading"`), as the blocks OCR reads from a Word file’s images
  and from image files always had. This changes the blocks of a document
  at the default settings when tesseract and magick are installed and a
  page is OCR-ed: it is a fix, since the blocks did not say their text
  came from OCR, and no text and no request changes. Without tesseract
  nothing changes.

- [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
  gains `ocr_confidence`. At `TRUE`, the blocks of a PDF page OCR read
  carry `ocr_confidence`, Tesseract’s mean word confidence for the page,
  from a second Tesseract pass over each OCR-ed page. The default,
  `FALSE`, runs one pass, as before, and adds no column.

- An embedded image in a Word file whose OCR fails now raises a
  `gr_ocr_failed` warning naming the image, as a PDF page does; before,
  its text was lost with nothing said.

- `contextual` with `context_source = "llm"` now sends each chunk’s
  section path from the document’s headings (`"Methods > Participants"`)
  with its request, and declares its cost, one request per chunk and no
  more, in `$extra$cost` and a `segment.cost` trace step. `proposition`
  keeps the page and section of each batch on its chunks, and counts
  propositions with no support in their batch (a number it does not give
  in any form, “1,200” for “1200” or “twelve” for “12”, or most words
  absent) in `$extra$propositions_unsupported`. The new setting
  `proposition_check = "drop"` drops them, counting them in
  `$extra$propositions_dropped` with a `gr_proposition_dropped` warning;
  the default, `"count"`, keeps every proposition as before. The new
  setting `proposition_context_tokens` sends each batch that many tokens
  from the end of the batch before it, as context; at its default, 0,
  each batch is sent alone as before. The section path changes what
  `contextual` sends under `"llm"`, an opt-in setting of an opt-in
  segmenter, so its cache and replay keys change; no default segmenter
  sends anything new, and the golden runs, which use neither segmenter,
  are unchanged.

- `semantic` run on lexical vectors now reports its method as
  `"semantic->lexical"`, as it reports `"semantic->paragraph"` when it
  falls back. This is a label fix: the chunks and the requests are
  unchanged.

- New
  [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md)
  says how far a benchmark’s arms fail on the same items: the phi
  coefficient between each pair’s errors within strata of item
  difficulty (or strata you give), pooled over the strata; the share of
  items both got wrong where they gave the same wrong answer (Kim et
  al. 2025); and a sample of items every arm got wrong, for a person to
  check. It reads the benchmark’s rows and sends nothing. Yen’s Q3 from
  a one-parameter mixed model is not computed, since it would need lme4,
  which harnessr does not depend on.

### Claims and the write-up: what each rests on

- The claims and writing prompts now show each extracted value with its
  check and its quote, as
  `n: 120 (verified quote: "We enrolled 120 people.")`, when they are
  given a
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result. This changes what is sent at the default settings: every
  claims and section request made from an extraction carries the quotes,
  so its cache and replay keys change and earlier cached replies for
  these requests are not reused. A bare table carries no quotes and is
  sent as before.

- [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  gains `unverified`, last. At its default, `"exclude"`, a value whose
  quote did not verify, or that came with no quote, is left out of the
  claims prompt, so no claim rests on it, and a study with no value left
  is not sent. `"include"` shows them, marked unverified with the quote
  that was given. The result gains `$values`, every value with its
  status (`"verified"`, `"unverified"` or `"not reported"`) and quote,
  and `$unverified`, the unverified values listed apart;
  [`print()`](https://rdrr.io/r/base/print.html) counts them. The
  default is untested.

- [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  shows the unverified values to the writer, marked, and gains `$values`
  and `$sentences`: every sentence of the text as published, linked to
  the studies it cites that are verified records (with at least one
  value whose quote verified), or flagged as citing no study or no
  verified record. [`print()`](https://rdrr.io/r/base/print.html) counts
  the flagged sentences, and the audit report lists them and the values
  the claims prompt left out. Nothing is marked partial for a flag.

- Claims are ranked by the certainty of their direction tally, not by
  how many studies vote. Each claim in `gr_claims()$claims` gains
  `sign_p`, the exact two-sided sign test of `n_support` of
  `n_support + n_contradict` studies, and `low_power`, `TRUE` for a
  tally of 5 studies or fewer, where no split can reach p \< 0.05.
  Sections rank their claims by `sign_p`, lowest first, then by study
  weight, so a 5-of-5 claim now ranks above a contested 3-to-3 one. A
  claim that more of its studies contradict than support ranks after
  every other, the least contradicted first: `sign_p` is two-sided, and
  alone it ranked 1 supporting and 8 contradicting (p = 0.039) above 5
  of 5. [`print()`](https://rdrr.io/r/base/print.html) gives each
  claim’s tally and p (5 of 5 prints p = 0.0625) and warns of low power,
  citing Campbell et al. 2020 (SWiM) and Boon and Thomson 2021; the
  audit report adds `sign_p`. This changes what is sent at the default
  settings for a section given claims in a different order: the claims
  block lists them, and assigns their sentence budgets, by the new rank.

- [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  gains `moderators`, last: the columns you expected, before reading, to
  explain a disagreement. Each moderator a claim names is now tested, in
  `$moderators`: `declared` (named in `moderators`) or `exploratory`
  (not declared, or one study against one), Fisher’s exact `fisher_p` of
  the split, `min_p`, the smallest p a split with those numbers of
  studies can give, and `holm_p`, Holm’s adjustment over the declared
  moderators. `$claims` gains `moderator_status`.
  [`print()`](https://rdrr.io/r/base/print.html) and the audit report
  give the tests and list the ICEMAN items (Schandelmaier et al.

  2020. to assess each moderator against; harnessr scores none of them.
        The writing prompt marks an exploratory moderator,
        `distinguished by: design (exploratory)`, which changes what is
        sent at the default settings for a section whose claims name a
        moderator, since with no `moderators` declared every moderator
        is exploratory.

- Claims reconciled across batches are no longer merged when they differ
  in direction, between findings, or in the population they name
  (adults, children, adolescents, infants, older people, women, men,
  students, from the claim and its scope), whatever the reconcile reply
  grouped; such a group is split, with a `gr_claims_kept_apart` warning
  and a `note` on each part. Direction is read from words on three axes:
  a null finding (“has no effect”, “did not improve”, “ineffective”,
  “unchanged”) against an effect, a benefit against a harm (“benefits”,
  “harms”), and a rise against a fall (“raises”, “reduces”). “Improves
  depressive symptoms” and “reduces depressive symptoms” stay together,
  and so “improves Y” and “reduces Y” are not told apart; a population
  outside the list is not recognised. A merged claim takes the wording
  of the member most studies support, then the one fewest contradict,
  then the first in a fixed order, instead of the longest, so the claims
  no longer depend on the order of the table. This changes what is sent
  at the default settings when claims come from more than one batch and
  the reconcile reply merges or groups them: the merged claim’s wording,
  and the number of claims where a group is split, feed the
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  prompts, so those requests, and their cache and replay keys, differ
  from before. A new test shuffles a 24-study table five times and
  requires at least 90% of claims to keep the same studies, direction
  and population. Two tests that expected a merge of opposite claims now
  expect them kept apart.

- The figures check of
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  links each figure found in a row to the field it reports, in a new
  `field` column of `$figures` (`"n (study 2)"`), and gives `pool`, how
  many distinct values the rows it was checked against hold, and
  `chance`, the chance of a match among them by coincidence, from the
  digits the figure was written with. A sentence that cites nothing is
  still checked against every row its section was shown, but a figure
  found there now counts only when its `chance` is below 0.05 or the
  sentence names the field it matched for that figure (a one-letter
  field just before it, a longer name in the same clause): an uncited
  “63%” among 40 numbers is unbacked, “n = 236” matching a field `n` of
  236 is backed, and in “(n = 410), 57 dropped out” the 57 is not backed
  by `n`. A qualified figure (“about 50”) counts as near a row’s value
  only in a sentence that cites the row. The check stays diagnostic
  only: it marks nothing partial and sends nothing. The audit report
  adds `pool` and `chance` to its unbacked figures.

- [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  gains `$uncited`, the studies the text as published cites nowhere,
  from the final cited set the reference list follows, with `shown`,
  whether any section’s prompt held the study.
  [`print()`](https://rdrr.io/r/base/print.html) gives one line and the
  audit report a table. It is a count, not a quota: nothing asks that
  every study be cited. The result also keeps `$section_studies` (the
  studies each section was shown), `$closing`, `$style`, `$figure_bands`
  and `$bib_columns`.

- New `gr_recheck(synthesis, text_marked)` checks and renders an edited
  write-up again. Edit `$text_marked`, the marker form, and pass it
  back: a marker naming a row that does not exist, or a study the
  section under whose heading it stands was not shown, is left as a
  marker, counted in `$recheck` and warned about
  (`gr_recheck_citations`); the citations and reference list are
  rendered from the edit; and `$figures` (stage `"edited"`),
  `$sentences`, `$uncited` and `$contradictions` are worked out again,
  the figures with the `style` and `figure_bands` the write-up was made
  with. A study one heading cites without being shown it keeps its
  reference when another heading cites it honestly. On a synthesis saved
  before `$section_studies` was kept, `shown` in `$uncited` is `NA`.
  Nothing is sent.

- [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  gains `$contradictions`: with `claims`, sentences that state a claim
  and cite a study on its contradicting side with no hedge (“may”,
  “suggest”) and no word of contrast (“however”, “mixed”). A sentence
  states a claim when it stands in a section the claim was given, points
  in the claim’s direction in one of its clauses (so “improved mood,
  with no adverse events” still states that mood improved) and shares at
  least two content words with it. It is found by counting words, with
  no model; [`print()`](https://rdrr.io/r/base/print.html) counts them
  and the audit report lists them. Nothing is marked partial.

### Checking the search, the files and the screening

- New `gr_search_recall(records, known, tier, held_out)` measures a
  search against a seed set of papers already known to be relevant: the
  share it found, with a Clopper-Pearson interval from
  [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md),
  overall and for each `tier`. Seeds are matched to records by the rules
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  uses to find duplicates. A seed those rules refuse (a title under 12
  letters or digits, a title and year shared by records with different
  DOIs, or authors or venues that disagree) counts as not found and is
  listed in `$refused` with the reason. Seeds used to build the search,
  marked by a `used_to_build` column or left out of `held_out`, are left
  out of the figure and listed in `$excluded`. When `known` is a
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  that holds two exports of one paper, the copy its `duplicate_of` marks
  is counted once with the seed it copies and listed in `$copies`. An
  empty seed set, a tier with no seed or none left, and a `tier` string
  that names no column of `known` (with one seed too) are refused. The
  help cites relative recall (Sampson et al. 2006) and PRISMA-S.

- [`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
  gains `recall`, its last argument, which adds the search’s recall
  against the seed set and the seeds it missed. Calls that pass
  arguments by position keep their meaning.

- [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
  and so
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  and
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  check that each file is the paper its record names when the sources
  come from a
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md):
  the first 6,000 characters of its text are searched for the record’s
  DOI, as a whole DOI, and title, with any HTML markup such as `<i>`
  taken out of the record’s title. When the recipe’s cleaning removes
  digits (`remove_numbers`, in the `"legacy"` preset), the DOI is not
  looked for and the title is compared without its digits. A last
  `identity` column of `$summary` holds `TRUE`, `FALSE` or `NA` (nothing
  to check), and `FALSE` warns with class `gr_identity_mismatch` and is
  added to `warnings`. Nothing is dropped and
  [`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
  is unchanged. [`print()`](https://rdrr.io/r/base/print.html) counts
  the mismatches, and the audit report lists them. A row restored from
  `store` keeps its check only when the run that stored it checked the
  file against the same record; otherwise `identity` is `NA`, the stored
  warning is dropped, and a note in `warnings` says the check needs the
  document read again. A run without records has no new column, even for
  rows it restores from a store a run over records wrote, and those rows
  lose the stored warning.

- The `references` cleaner no longer cuts a Markdown file at a line
  indented four or more spaces (” \# References”), which in Markdown is
  code, not a heading. PDF and plain text still allow any indent.
  [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
  tells the cleaners what read the file in `.source_type`.

- Screening recall now says what it is relative to.
  [`print()`](https://rdrr.io/r/base/print.html) on a
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  result and the audit report state that recall is the share of the
  records the person judged eligible that the screener kept, wherever
  they report recall or sensitivity. The audit report now gives recall
  with its interval and one-sided bound as well.

- [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  gains `$worst_case`, a sensitivity analysis that counts every record
  the reviewers split on as eligible and works out recall, records lost
  and the verdict again. With several reviewers,
  [`print()`](https://rdrr.io/r/base/print.html) and the audit report
  show it beside the main estimate. With one decision per document it
  repeats the main figures.

- The audit report’s header gives, for each stage, when it ran and the
  harnessr version that ran it, from the stage’s own trace, beside the
  time and version that wrote the report. A stage run on another version
  is flagged. “What this report does not establish” now says what each
  check looks at: the quote check, the value check behind
  `n_unverified`, and for a write-up the citation and figures checks.

### Comparing methods and settings

- A new guide,
  [`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md),
  works through five comparisons offline, each ending in an
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md):
  three readers on 32 test questions in 8 reports, a grid of three
  segmenters at two chunk sizes, `top_k` swept over 1, 2 and 4, two
  values of `screen_tokens`, and a pairwise judge validated against 180
  labelled pairs. Settings are tuned on the dev split and one chosen
  contrast is run on test, with 10 runs where the report’s notes ask for
  them and simultaneous intervals where three arms are compared. A last
  section shows the same steps on your own documents, writing results to
  a directory you name.
- **A settings reference.**
  [`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
  prints every setting of every stage from
  [`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
  when it is built, each important one linked to its walkthrough, and
  the extractors, cleaners and presets, segmenters, readers, embedders
  and recipes from their registries. The README and
  [`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
  gain a “What you can change” section: one row per stage with its count
  of settings, the most used, and links to the walkthroughs; Get started
  also gives the basic settings of each stage with when to change each.
- **Settings walkthroughs.** Five guides end with a “Choosing the
  settings” section, one walkthrough per important setting or group:
  what it controls and trades off, the signs in your results that point
  to changing it, where its default came from (measured, cited or
  untested), and how to test it with
  [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md).
  [`vignette("ingest")`](https://elkronos.github.io/harnessr/articles/ingest.md)
  covers cleaning presets with `references_after`, and OCR;
  [`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md)
  the segmenter, `max_tokens`, `overlap_tokens`, and `contextual` and
  `proposition`;
  [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
  the reader, `top_k`, `mmr`, word matching (`lexical_blend` and BM25),
  `context_order` with `restate`, `verify` with `cite`, `effort` and
  `max_merge_levels`;
  [`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
  screening calibration, extraction’s `resolve` and `require_quote`, and
  synthesis’s `coherence_rounds`, `figure_bands` and `prominence`;
  [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
  the global limits and the governor. The offline examples run on the
  stand-in models and report what each value sent: on the example
  report, `"scan"` cleaning sent the same requests as `"standard"`, a
  merge cap of 6 the same as a cap of 1, and `mmr = 0.7` at `top_k = 3`
  and `verify` the same as the value before them.
- **[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)**
  builds one arm per row of a grid of settings. The base is an arm from
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
  whose settings each row overrides by name, or a function of the grid’s
  columns that returns an arm. A column that is not a setting is an
  error (class `hr_unknown_setting`) listing the settings that are, and
  rows that build the same configuration are dropped with a message
  (class `hr_sweep_collapsed`).
- **[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)**
  adds a `param.<name>` column for each setting the arms record (arms
  from
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  or
  [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)),
  after `reportable`, so a sweep is summarised with
  `aggregate(correct ~ param.top_k, bench, mean)`. It warns (class
  `hr_same_config`) when two arms resolve to the same configuration: two
  recipe arms whose settings resolve to the same recipe, or two other
  arms that differ only in name.
- **[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)**
  lists the arms of a benchmark that sent byte-identical requests to an
  earlier arm on every item and run, and the recorded settings that
  differ between them. Those settings changed nothing that was sent:
  `top_k` under the `fast` recipe, which sends the whole document, is
  one.
- **[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)**
  returns every setting of every stage in one table of 195 rows: the
  ingest, segment and read schemas (with the entries of `cleaner_opts`
  and `layout_opts` the built-in code reads), the arguments of the
  screening, extraction, synthesis and evaluation functions, and every
  `gr_options()` option. Each row has its stage, the function that takes
  it, its default, tier, evidence status and source, the first sentence
  of its help, and the guide section that explains how to choose it. It
  is built from the schemas, the option rules, the functions’ arguments
  and the installed help when it is called, and a test fails when a
  declared setting is missing from it.
- **[`gr_settings()`](https://elkronos.github.io/harnessr/reference/gr_settings.md)**
  returns the schema of the read, segment or ingest settings, and
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) of a
  schema gives each setting’s default, range, tier, evidence status and
  source.
- **[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)**
  and
  **[`gr_seg_windowdiff()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)**
  measure how far a segmentation’s boundaries fall from a reference’s
  (Beeferman, Berger and Lafferty 1999; Pevzner and Hearst 2002), with
  NLTK’s windows and default `k`, so values match NLTK’s on the same
  strings.
  **[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md)**
  turns chunks, or a reference segmentation given as text, into the
  sentence-by-sentence boundaries they compare. It locates segments and
  sentences in the document, so a sentence the document repeats, such as
  “See note 3.” at the start of two sections, stays in the section it
  occurs in.
  **[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)**
  ranks each segmentation’s chunks for each question as the `retrieve`
  reader does and reports recall at k per segmenter, with no model call
  under the lexical embedder.
- **`gr_label_sheet("pairwise")`** writes two texts per row as `text_1`
  and `text_2`, in an order drawn for each row from a SHA-256 digest of
  its id and texts, with the order kept in an opaque `order_key` tied to
  the row.
  [`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
  gives the person’s choice back in candidate order as `"A"`, `"B"` or
  `"tie"`, ready for `hr_judge_validate(positive = "A")`, where a tie
  counts as negative. A key edited or moved to another row is an error
  of class `gr_bad_labels`.
- **Self-judging is recorded.**
  [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
  takes `judge_model`, the configuration’s model by default, and
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  adds a `self_judged` column: `TRUE` when the judge’s model equals the
  model or served model of one of the run’s requests, `FALSE` when the
  run asked a known model and none equals it, `NA` otherwise. The match
  is exact and nothing is refused;
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  adds a note counting the self-judged runs per arm. `hr_bench` has the
  new column before `reportable`.

### Settings that were constants

Values that were fixed in the code are now settings, each with the value
it had as its default, so a run at the defaults sends the same requests
and keeps the same cache, store and replay keys. A new read, segment or
ingest setting is stored in the spec only when it is not its default,
and a new option is recorded in a trace’s options, and joins a key, only
then. Each setting’s help says where its default came from; almost none
has a measurement behind it.

- **`gr_options()`**: `auto_max_tokens` (50000) and `auto_room_share`
  (0.5) set when `answer_document(recipe = "auto")` reads with `"fast"`;
  `reasoning_floor` (2048) is the least output cap sent to a reasoning
  model, and `0` turns the raise off; `output_reserve_share` (0.25) is
  the share of the window `gr_budget()` reserves for the reply;
  `near_verbatim_sim` (0.90), `near_verbatim_sim_short` (0.95) and
  `near_verbatim_short_chars` (40) set when the edit-distance matcher
  scores a quotation `near_verbatim`. A non-default `reasoning_floor`
  joins the response-cache key, and it, `output_reserve_share` and the
  near-verbatim settings join the store key of
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).
- **[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)**:
  `accept_near_verbatim` (FALSE) lets a near-verbatim quotation stop the
  `iterative` reader under `verify = TRUE`, and is refused without it;
  `max_merge_levels` (6) caps the merge tree of `map_reduce` and the
  other merging readers, and the worst case counted before a run counts
  that many levels; `restate_tokens` (1200) is the length above which
  `restate = "auto"` repeats the question; `bm25_k1` (1.5) and `bm25_b`
  (0.75) are the BM25 parameters of rerank’s prefilter and lexical
  retrieve, the usual values in Robertson and Zaragoza (2009);
  `lexical_blend` (0.5) weighs cosine against BM25 in an offline
  `retrieve`.
- **[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)**:
  `context_reply_tokens` (90) and `context_document_tokens` (1500) for
  `contextual` under `context_source = "llm"`, and
  `proposition_reply_tokens` (2000) for `proposition`.
- **[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)**:
  `layout_opts` changes the PDF running-head pass (`depth`, `share`,
  `min_pages`, `max_chars`, `max_words`). Under `cleaner_opts`,
  `references_after` (0.4) sets where the `references` cleaner may find
  a bibliography heading; it keeps the code’s behaviour, a heading at or
  after 40% of the text, which a comment had described as “the last
  40%”. `header_max_chars` and `header_min_repeats`, which
  `headers_footers` already read, are now documented. The settings
  column of
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  names each entry of `layout_opts` and `cleaner_opts`, as
  `layout_opts.depth=3`, and the ingest step of a run’s trace records
  them under `settings` when any is set.
- **[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)**:
  `coherence_rounds` (1) lets each revision pass run more than once,
  each round checked as a pass is and the pass stopping at a round that
  is discarded or changes nothing (paper-orchestra runs up to 3, with no
  recorded evidence for that number); `figure_bands` (about 0.10, over
  and under 0.25) sets how near a qualified figure must be; `prominence`
  (thirds) sets how many claims get each sentence budget; and
  `study_weights` takes a function that weighs the studies claims are
  ranked by. `$coherence` has a `round` column.
- **`gr_calibrate(max_width = 0.10)`**,
  **`hr_report(auto_bootstrap_at = c(items = 300, clusters = 30), min_runs = 5)`**
  and
  **`hr_calibrate_signal(min_errors = 100, isotonic_min_items = 1000, min_clusters = 20)`**.
  None of these numbers was measured. The coverage simulation
  (`dev/sim-coverage.R`) measured the two interval methods at two
  designs only, 386 items in 40 clusters and 50 items in 10; the switch
  to the bootstrap at 300 items and 30 clusters lies between them and is
  itself untested. A calibration record held to a bar other than the
  default says so in its `notes`.
- **`hr_param(evidence =)`** must be a list of `status` (`"measured"`,
  `"cited"` or `"untested"`) and a non-empty `source`. Every parameter
  of the read, segment and ingest schemas declares one, their help pages
  list them under “Where the defaults come from”, and
  [`print()`](https://rdrr.io/r/base/print.html) of a schema shows each
  parameter’s tier and evidence status. Each schema keeps at most five
  `basic` parameters: the read spec’s are `reader`, `model`, `top_k`,
  `cite` and `verify`, and the rest are `advanced`. No default changed.

### Benchmarks

Nothing here changes a default: an arm that uses neither shortcut sends
the requests it sent before, with the same cache keys, and no setting is
added.

- [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)’s
  `ctx` gains `judge(candidates, ...)`, which calls
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  with the benchmark’s client and `trace = ctx$trace`, so the judge’s
  requests go out at the run’s draw and its cost is in the run’s `usd`
  once. Pass `rubric` as
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  needs. It also gains `note(name, value, refs = NULL)`, which records a
  signal about the run’s item with
  [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md).
- [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  accepts an `hr_bench`. It reads each run’s own trace and adds `arm`,
  `run` and `item` columns; the benchmark’s folded trace is not read, so
  each signal is listed once.

### Steps and chains

Nothing here changes a default or adds a setting:
[`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
and
[`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
take the arguments they took, and a step built with them sends the
requests it sent before, with the same cache keys.
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
shows the new functions at work.

- `hr_step(name, fn)` builds a step: a function of `(input, ctx)` with
  the settings it was built with recorded beside it. With a `schema`,
  its settings are checked and resolved by
  [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md);
  with `build`, the function is built from the settings when the step
  is, so a bad setting fails there. `input` and `output` declare what
  the step takes and returns.
- `hr_chain(..., name)` runs steps in order as one
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
  which
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  takes as it takes any arm, and
  [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
  sweeps by path (see
  [`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
  below). Inside a chain each step gets `ctx$step` and
  `ctx$step_params`, and `ctx$params` is the arm’s.
  `hr_chain(old, judge = NULL, name = "nojudge")` derives a chain
  without one step; `x = step` replaces a step and a new name adds one.
  The arm records each step’s settings as `"step.setting"`, and its
  configuration is a hash of the steps’ code, the values it reads and
  their resolved settings. A step that takes chunks no earlier step
  returns warns (`hr_chain_gap`), and a step that cannot follow an
  answer is an error (`hr_bad_chain`). A step that takes a document no
  earlier step returns does not warn, since most chains start at the
  segment step, which ingests at the default settings.
- `hr_settings(x)` lists every setting of a step or a chain: one row per
  setting of each step’s schema, with the step, the setting, its
  resolved value, whether it was given, and the schema’s default, range,
  type, tier and evidence. A chain’s settings are named by path,
  `"step.setting"`. An arm from
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  or
  [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
  is an error (`hr_bad_arm`) that points to
  [`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md).
- `hr_set(x, ...)` builds a step or a chain again with some settings
  changed: `hr_set(chain, retrieve.top_k = 8)`, or
  `hr_set(step, top_k = 8)` for a single step. A path that is not a
  setting of a step’s schema, including a fixed extra setting, is an
  error (`hr_unknown_setting`). The values are checked as when the step
  was built, so an out-of-range number is clamped with a warning, each
  changed step keeps its class, and the chain’s configuration is that of
  the new settings: a setting set to its default gives the configuration
  of leaving it out.
  [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
  uses it to sweep a chain by path, as in
  `hr_sweep(chain, data.frame(retrieve.top_k = c(2, 8)))`, which gives
  `param.retrieve.top_k` columns in the benchmark.
- [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  and
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  now return `hr_step` objects (class
  `c("gr_step", "hr_step", "function")`) checked against the ingest,
  segment or read schema, with their input and output declared.

### Command steps

[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
is opt-in: no command runs unless you build a step with one, so every
default run sends the requests it sent before, with the same cache keys.
Its three settings are declared with their evidence (`untested`), are
listed by
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
under the evaluate stage (227 settings in all), and have walkthroughs in
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
that test each with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md).

- `hr_step_command(name, argv, parse, timeout, held, wd)` builds a chain
  step that runs a program you name, through
  [`system2()`](https://rdrr.io/r/base/system2.html), and reads its
  result as `"passed"`, `"failed"`, `"error"` or `"timeout"`. Each
  element of `argv` is one argument, quoted for the shell and never
  split; there is no default command, and `argv` is never taken from a
  model’s reply. `argv` may be a function of `(input, ctx)`, for a
  command that names a file an earlier step wrote. `OPENAI_API_KEY` is
  unset for the call and put back after it; the rest of the environment
  is inherited. `parse = "testthat"` reads the last testthat summary
  line, and gives `"error"` when there is none. A program stopped at
  `timeout` seconds carries the degradation `"command_timeout"`. The run
  is noted in the trace as `"step.command"`, with hashes of the command
  and the output, never the output.
- With `held = FALSE` the step adds its result to its input as `$check`.
  With `held = TRUE` it passes its input on, records the signal
  `"command.<step>"` and attaches the result as
  `attr(output, "hr_held")`, for a scorer.
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
  refuses a step that is not held after one that is, with class
  `hr_held_not_last`.
- [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  reads its `"judge_inconsistent"` degradation from the same list of
  codes as the command step. Nothing it returns changes.
- [`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
  builds a coding sub-agent: a draft step, a visible check, a revise
  step that reads it, and a held check last that only the scorer sees,
  compared with the first draft alone. It also runs the two goals the
  steps were written for, a recipe swept over a grid next to an arm of
  your own and a chain with a judge step derived and swept, and says why
  a stand-in model’s handler must be stateless. A test builds the same
  loop from exported names only, on four small tasks, and checks it with
  [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md).

### Skills

Skills are opt-in: a step has one only when you give it
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
so every default run sends the requests it sent before, with the same
cache keys. A skill adds no setting to
[`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md):
its limits are fixed, and whether a skill helps is tested by comparing a
chain with and without it, as the “Skills” section of
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
does with
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
and an
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
over a function.

- `hr_skill(path)` reads a skill folder you choose: `SKILL.md`, whose
  header (`name`, `description`, `version`, between two `---` lines) is
  read without a YAML parser, and whose body is the instructions; text
  files under `references/`; and scripts under `scripts/`, which are
  listed and never run. A nested or multi-line header value, a missing
  name or closing line, a nul byte, a file linked from outside the
  folder, more than 50 files in either subfolder or more than 200,000
  bytes in all is an error of class `hr_bad_skill`; an unknown header
  key warns (`hr_skill_unknown_key`). Its `hash` covers the header, the
  instructions, the references and every byte of the scripts. The
  package never looks for skills and never lets a model choose one, and
  a skill’s text goes into the prompt as it is, so it can carry prompt
  injection.
- `hr_step(skill = )` now takes a skill. Inside
  [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
  the step’s `ctx$call()` and `ctx$call_json()` send the instructions
  and references as a system message before the step’s messages, and
  `ctx$skill` holds the skill. The hash is a fixed setting of the step
  and part of its fingerprint, so a chain with a skill has its own
  configuration and records the setting `"<step>.skill"` (a
  `param.<step>.skill` column in a benchmark). The skill’s version, when
  it has one, is the step’s version.
  [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  and
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  refuse a skill with class `hr_bad_skill`, since their requests are not
  sent through `ctx$call()`.

### Registering modules

Nothing here changes a default or adds a setting: each `gr_register_*()`
function keeps its arguments and checks, each `gr_*()` listing keeps its
existing columns (contract 0.2 appends `version` and `contract`; see
“Module contract 0.2” below), and the built-in cleaners and extractors
keep their registration stamps, so ingest cache keys do not change. The
“Registering any kind with hr_register()” section of
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
shows both functions.

- `hr_register(kind, name, fn, ..., description = "", calls = NULL, version = NULL)`
  registers a module of any kind through that kind’s own function, so it
  runs the same checks: `hr_register("reader", ...)` refuses what
  [`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
  refuses. The kinds are `"extractor"`, `"cleaner"`, `"segmenter"`,
  `"reader"`, `"embedder"`, `"protocol"` and `"step"` (see “Module
  contract 0.2” for the last two); any other is an error of class
  `hr_unknown_kind`, and `calls` for a kind that declares no calls is an
  error of class `gr_bad_setting`.
- `hr_modules(kind = NULL)` lists the modules of every kind in one
  table: `kind`, `name`, `description` and `calls`, a list column of the
  call stems each module declares. With `kind`, it adds that kind’s own
  columns, such as a reader’s `signature` or an extractor’s
  `extensions`.
- `hr_register("segmenter", ...)` also takes `effort_label`, a function
  of the segment spec that returns the label the segmenter’s requests
  carry. The built-in segmenters register this way, so a run’s `effort`
  map reaches each one as the effort for its own label, as before. A
  function you register under a built-in’s name with
  [`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
  still gets the whole map.
- Reads that look up a module by name, such as running a reader,
  choosing a segmenter’s effort or picking an embedder, go through the
  kind’s accessor, and `gr_embed()` looks embedders up the same way. The
  listings and the worker snapshot still read the document layer’s
  slots. The core calls no document layer function.
- When an embeddings request fails, `gr_embed()` falls back on the
  embedder registered as `"lexical"`, so if you replace `"lexical"` with
  [`gr_register_embedder()`](https://elkronos.github.io/harnessr/reference/gr_register_embedder.md)
  your function also serves as the fallback. If your function fails
  there, `gr_embed()` warns with its error and uses the built-in hashed
  lexical vectors.

### Conformance for every kind, and mock failure modes

Nothing here changes a default or adds a setting. `gr_mock_client()`
without `mode` keeps the fields and replies it had, and no request or
cache key changes. “Checking a module against the contract” in
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md)
shows a mode in use.

- `gr_mock_client()` gains `mode`, which breaks each chat reply the way
  a provider can: `"bad_json"` sends a JSON object cut off part way,
  `"refuse"` sends an empty reply that `gr_call()` reports as failed,
  `"at_cap"` marks the handler’s reply as cut off at the output cap and
  bills the cap (a failed result from the handler comes back as it is),
  and a vector of HTTP status codes such as `c(429, 500, 200)` gives
  call `i` the `i`-th status, marked retryable for the statuses the HTTP
  transport retries. Embeddings are left as they are. Pass such a client
  to
  [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md)
  or
  [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)
  to check a module against replies that fail.
- The package’s tests now check every registered module that
  [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
  lists, and every protocol, against the rules for its kind. An
  extractor is checked where its packages are installed and the tests
  have a sample file in its format. Extractors are checked for blocks
  with text and typed columns, cleaners for one string per block, some
  text left and the same result twice, embedders for finite unit-length
  rows under their own name, and protocols for a question, criteria, an
  outline and a save and read that gives the same protocol back. Every
  built-in reader and segmenter passes its rules under each mock mode,
  and every reader keeps to a call cap of 0, 1 and 3. These checks are
  internal.

### Module contract 0.2

Nothing here changes a default or adds a setting, and no request or
cache key changes. The new columns come last in each listing, so code
that picks a column by name, or by its position counted from the first
column, reads what it read before. CONTRACT.md lists every field that
changed.

- The module contract moves to 0.2. A conformance report’s `contract`
  attribute now says 0.2.
- `"protocol"` and `"step"` are kinds.
  `hr_register("protocol", name, fn = protocol)` registers a protocol
  from
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md)
  through
  [`gr_register_protocol()`](https://elkronos.github.io/harnessr/reference/gr_register_protocol.md).
  `hr_register("step", name, fn)` registers a step from
  [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
  or builds one from a function of `(input, ctx)` and the arguments you
  pass. The package registers no step at load.
  [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
  lists both kinds.
- [`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
  gains `version`. A module you register with
  [`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
  records the version you give and contract 0.2 in its entry. An entry
  registered with a `gr_register_*()` function has neither field, and
  each listing shows `NA` for it.
- `hr_register("step", ...)` refuses call stems that are blank or
  contain whitespace, with class `gr_bad_setting`, and keeps each stem
  once, as the reader and segmenter kinds do. Parallel workers receive
  the steps you registered, so `hr_modules("step")` on a worker lists
  them.
- [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md),
  [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md),
  [`gr_cleaners()`](https://elkronos.github.io/harnessr/reference/gr_cleaners.md),
  [`gr_extractors()`](https://elkronos.github.io/harnessr/reference/gr_extractors.md),
  [`gr_embedders()`](https://elkronos.github.io/harnessr/reference/gr_embedders.md),
  [`gr_protocols()`](https://elkronos.github.io/harnessr/reference/gr_protocols.md)
  and
  [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
  end with the columns `version` and `contract`. The built-in segmenters
  register through
  [`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
  so they show contract 0.2.
- Signal calibrations keep their own contract version at 0.1. A key
  without `contract_version` is still filled with “0.1”, so a
  calibration record you saved stays valid under
  [`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md).

### Fixed

- A worker in a parallel batch sets `OPENAI_API_KEY` for each item and
  puts back the value it had when the item ends. A key passed as `key`
  or through the `harnessr.api_key` option no longer stays in the worker
  process after its item. A worker started from a session with
  `OPENAI_API_KEY` set has that key from the start and keeps it. A
  backend handler or `gr_ellmer_client()` that reads the key from the
  environment still gets it. A batch through `gr_mock_client()` sets no
  key. Requests and cache keys do not change.

- A `gr_claims`, `gr_synthesis` or `gr_calibration` you saved with an
  earlier version gets the fields added since filled with their defaults
  when
  [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md),
  [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  or
  [`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
  reads it, or [`print()`](https://rdrr.io/r/base/print.html) reads a
  `gr_claims` or `gr_synthesis`. Each one gives the output it gave for
  that object before.
  [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  returns the filled object, and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  stores the filled claims table in `$claims`. A hand-built object such
  as `structure(list(table = tab), class = "gr_screening")` passes
  through unchanged. Requests and cache keys do not change.

- The `references` cleaner, in the `"academic"` and `"legacy"` presets,
  now cuts at a Markdown heading such as `## References` or
  `### 7. References`, with or without closing `#` marks, and not at a
  line inside a fenced code block, such as a `# references` comment. It
  matched only a line that held the word alone, so a Markdown document
  kept its reference list under both presets. The example report ends
  with `## References`, so under `"academic"` it now sends 62 fewer
  prompt tokens than under `"standard"`, not 26. The `research` and
  `legacy` recipes send shorter requests for such a document, and so do
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  and
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  whose default recipe is `research`: at their defaults their requests
  and cache keys change for a Markdown document with a references
  heading in its last 60%, so a `gr_cache()` built before this misses
  for those documents. The golden records of the two recipes and the two
  stages were recorded again. Requests under the `"standard"` preset,
  the default of
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
  do not change.

- [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  and
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  now send their requests at the draw index and draw scope of the trace
  they are given. Each records on a trace of its own, which did not
  carry them, so its requests went out at draw index 0 whatever run of a
  benchmark the trace was: under a `gr_cache()` runs 2 onwards were
  answered with run 1’s reply, and an
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  arm that called `gr_claims(trace = ctx$trace)` was refused for
  repeating a draw. The items of a parallel `gr_lapply()` batch carry
  the run’s draw index and scope the same way. Requests made without a
  draw index are unchanged, and so are their cache keys. A recording
  made before this change holds a stage’s requests only at draw 0, so a
  replay asking for a later draw is answered with those replies in
  recorded order, served as replies without their own draw key, as for
  any recording made without per-draw keys.

- A stage that keeps a trace of its own
  ([`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md))
  is now held to the calls its given trace’s
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  has left, as it already was to the dollars and tokens left.
  `max_calls` was left whole, so a stage given a trace that had made its
  2 calls under `hr_governor(max_calls = 2)` made a third. The calls
  taken off are the ones the governor counts: every recorded request,
  cache hits and embeddings requests included. Without a governor,
  `gr_options(max_calls =)` is still a limit per document for
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  and per stage for the others.

- [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  given a `trace` is now a step of the run that trace records. It
  recorded its requests on a trace of its own with a copy of the run’s
  governor and never folded it in, so its calls and dollars were missing
  from the run’s cost, from `usd` in
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  and from the count the benchmark’s governor checks, and its requests
  went out at draw index 0: under a `gr_cache()` every run was handed
  run 1’s verdict. Its requests now count against the trace’s governor,
  are folded into the trace when the judgement ends, and are sent at the
  trace’s draw index and draw scope unless `draw_index` names another. A
  `governor` given with a `trace` no longer replaces the trace’s: the
  judge is held to both, the lower of each limit, so a judge inside a
  benchmark run cannot take the run past the benchmark’s `max_calls`.
  Each request folded in names the judge in its `judge` field, and
  `self_judged` in
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  leaves those requests out: an arm that answers on one model and judges
  on another inside its run is not marked as judged on its own model by
  an
  [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
  on the judge’s model. The note it adds to the trace records no tokens,
  so cost summaries count the judge once. Its own result is unchanged:
  `$trace` and `$judge_cost` still hold the judge’s requests alone, and
  the order swap works as before. A judge called without a trace, and
  [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md),
  still keep their calls apart. A recording made before this change
  holds no judge requests in a benchmark’s trace, so a replay of an arm
  that judged inside its runs stops at the judge, as it did before.

- [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  records a run as `"budget_stop"`, not `"error"`, when a reader’s
  pre-flight check in the arm stops it with `gr_call_cap` or
  `gr_cost_cap` because the benchmark’s limits leave too little.
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  caught that error, but a hand-written arm that calls
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  with `trace = ctx$trace` let it through, so the run was scored as an
  error and left out of the `hr_budget_stopped` warning. The run’s trace
  gets a `budget.preflight` note naming the limit.

- [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  now sets each run’s draw index on `ctx$trace`, not only on
  `ctx$call()`. A
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md),
  [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  or other stage called with `trace = ctx$trace` sent its requests at
  draw 0, so under a `gr_cache()` the arm was refused with
  `hr_duplicate_draw` unless it set `ctx$trace$draw_index` itself. Arms
  no longer need that line, and
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  no longer sets it. A request given a fixed `draw_index` still sends
  that one, and such an arm is still refused.

- [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)’s
  `ctx` gains `call_json(messages, schema, ...)`, a structured call sent
  through the same client, trace, governor and draw as `ctx$call()`. It
  returns the parsed reply, or a failed `gr_result` when the request
  failed or the reply does not meet the schema, which the scorers count
  as an error.

### Removed

The deprecated names are removed. Each one warned and pointed to its
replacement; calling a removed function is now an error, and a removed
option is ignored. Caches, recordings and stores written before the
rename still read: the `readgpt-cache-v2` and `readgpt-replay-v1` keys
and the cache directory `tools::R_user_dir("readgpt", "cache")` are
still looked up, and the corpus store key is computed as before.

| Removed | Use instead |
|----|----|
| `answer_question()` | [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md), or [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md) for several recipes |
| `parse_text()` | [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md), then [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md) |
| `gpt_read_chunked()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) with `reader = "map_reduce"` |
| `gpt_read_retrieval()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) with `reader = "skim"` |
| `gpt_read_hierarchical()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) with `reader = "hierarchical"` |
| `gpt_read_multipass()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) with `reader = "ensemble"` |
| `readgpt_example()` | [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md) |
| `options(readgpt.api_key =)` | `options(harnessr.api_key =)` |
| `options(readgpt.allow_local_urls =)` | `options(harnessr.allow_local_urls =)` |
| [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)’s `$kappa_legacy` | `$kappa`; `$decisions` holds the 3x2 counts the old figure came from |
| the `gr_deprecated` warning class | none: nothing warns about an old name now |

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
  `readgpt_example()`, below.

- **`readgpt_example()` is now
  [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md)**,
  which returns the same path to the bundled example document. The old
  name is removed (see “Removed”).

- **Requests, cache keys and recordings are unchanged by the rename.**
  Every request is sent as 0.6.0 sent it, and the corpus store key is
  the one 0.6.0 computed. The response-cache and replay keys change
  later in this release (see “Cache and replay keys” below), and the
  keys 0.6.0 computed are still looked up, so a warm cache, a recording
  made for `gr_replay_client()` and a
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  store all keep answering.

- **Two options are renamed**: `readgpt.api_key` is now
  `harnessr.api_key`, and `readgpt.allow_local_urls` is now
  `harnessr.allow_local_urls`. The old names are no longer read (see
  “Removed”).

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
  body fields. For a `gr_client()` it is read from the request body
  itself. `params` keeps what the caller asked for, as before. Requests,
  response-cache keys and replay keys are unchanged.

- **Steps record `served_model`, `response_id` and `fingerprint`** where
  the provider returns them, beside `model`, which stays the model asked
  for and is what a step is priced and replayed by. None of them enters
  a cache or replay key. `gr_call()` results carry the same three
  fields.

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
  `input` rather than additions. `gr_trace_summary()` gains
  `tokens_reasoning`, `tokens_cached_in` and `usage_estimated`, the
  share of requests whose counts were estimated, and
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
  columns when some request has them, and `gr_trace_cost()` gains
  `paid_reasoning` and `paid_cached_in`.

- **Cached input can be priced at its own rate.** `gr_register_model()`
  takes `cached_input_usd`, `gr_estimate_cost()` takes
  `cached_input_tokens`, and `gr_models()` shows
  `cached_input_usd_per_1m`. A model with no cached rate prices cached
  input as other input, so every built-in model costs what it did.

- **Runs record who they are for.** `gr_trace()` takes `system`,
  `owner`, `run_by`, `purpose` and `approved_by`, and the new option
  `gr_options(actor = list(...))` sets them for every trace; a field
  named nowhere is `NA`. They are written to a saved trace under `actor`
  and shown by [`print()`](https://rdrr.io/r/base/print.html) when set.

- **Runs record the options in force** when the trace was made, under
  `config`, with the R version. The values of `api_headers` are left
  out, since they can hold credentials.

- `gr_options()` given one named argument whose value is a list now sets
  that option. It used to read the list as a set of options to restore,
  which only an unnamed list should be.

### Cache and replay keys

- **`gr_call()` takes a `draw_index`** for the draws of a sampled
  request: 0, the default, for an ordinary call, and 1, 2, … for
  repeated draws. Above 0 it is part of the response-cache key, so N
  identical calls with draw indexes 1 to N are N cached replies; before,
  a cache returned the first reply N times and anything that compared
  them saw perfect agreement. A handler finds it in `params$draw_index`
  and the trace records it in the step’s `params`; at 0 neither carries
  it, so an ordinary call is unchanged.

- **The response-cache key is now `harnessr-cache-v3`**, a SHA-256 hash
  (64 hex digits) in place of xxhash64. Entries written under the old
  key (`readgpt-cache-v2`, by readgpt 0.6.0 and earlier builds of
  harnessr) are still read for calls with no draw index: a call that
  finds nothing under its new key is looked up under the old one. The
  first reply found that way in a session warns once for the cache, with
  class `hr_legacy_key`, and `gr_cache_stats()` has a new column,
  `legacy_hits`, that counts them. Old entries are never rewritten, new
  ones are written under the new key only, and `gr_cache_clear()`
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
  `gr_call()` sends) at the output price. The prompt is counted with the
  JSON schema and extra body fields the request carries and a few tokens
  of framing per message, then raised by `safety_margin`, since the
  provider bills for all of that. A request that could take the run past
  a limit is not sent. Runs used to stop only once what they had spent
  reached the limit, so they ended up to one request over it; they now
  end at or under it, as long as the provider stops each reply at its
  cap and counts the prompt within that margin of the local tokenizer. A
  run that leaves its output caps at the model’s limit stops while it
  still has headroom a smaller cap would have used.

- **A refused request is not a call.** It comes back from `gr_call()` as
  a failed result with `refused = TRUE` and an error naming the limit,
  after a condition of class `hr_budget_refused` is signalled (catch it
  to stop instead). It adds nothing to the trace’s calls, steps or
  spend; the trace lists it in a new `refusals` field, sets
  `budget_stop` and names the limit in `stop_reason`. Readers and review
  stages treat it as they treated reaching a limit before: the answer or
  section is marked partial, and the request is not counted as failed.

- **Every request is checked, not only the ones a reader asked about.**
  Judges, the ensemble’s adjudication, conflict resolution in `extract`,
  context and proposition segmentation, claims, outlines, screening,
  synthesis and embeddings requests all go through the same check, as
  does any request a custom reader or a script makes with `gr_call()`.
  The readers no longer check `trace_can_call()` themselves. It is kept
  for custom readers written to the 0.6.0 help page, which still work.

- **A chat model with no registered price is refused while a spending
  limit is set**, with a condition of class `hr_unpriced_model`. Such a
  model added nothing to the spend, so the limit never stopped it.
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  stops before its first request with an `hr_unpriced_model` error.
  Register the model’s prices with `gr_register_model()`, or set
  `gr_options(allow_unpriced = TRUE)`; then its requests are sent, still
  count against `max_calls` and `max_tokens_total`, and are priced `NA`
  in the trace. `gr_mock_client()` and replays are never refused for
  this, and neither are embedding models with no price. An ellmer chat
  is priced as the model it was built with, whatever a spec names, so a
  chat on a model with no registered price is refused too; the README
  and the `gr_ellmer_client()` example now register its price, and allow
  a local model to run unpriced.

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
  argument; a trace without one reads the limits from `gr_options()`, as
  before. The new limits are also options, `max_tokens_total`,
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
  kappa moves from 0.33 to 0.50. The old figure is no longer reported
  (see “Removed”).

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
  for `gr_call()` that fills in all three. `run` is required. The arm
  records its settings, a version and a hash of its code and settings,
  which is the same in every session and after
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
  recorded under the arm’s name, and `gr_replay_client()` answers an arm
  only with its own replies, so replaying some of the arms, or the arms
  in another order, gives each arm what it got even when two arms sent
  the same request. The whole benchmark is held to one governor; a run
  with a refused request is recorded as a budget stop and counted wrong,
  and the benchmark warns (class `hr_budget_stopped`) with the number of
  runs stopped, the limits that stopped them, how many count against an
  arm, and the first run stopped. With no governor the limits are
  `gr_options()`’s, set for one run of a reader (400 calls), and the
  warning gives the values of the options that stopped runs and, for a
  call, spending or token limit, says to pass a governor sized for the
  benchmark. A reader stopped by its own check before its first request
  now leaves a `budget.preflight` note on the run’s trace naming the
  limit, and the errors that check raises carry the limit in `$limit`.
  Every run on an item with no label has `correct = NA`, failures
  included, so such an item never counts against an arm. Rows on the dev
  split are marked not reportable.
  [`print()`](https://rdrr.io/r/base/print.html) shows accuracy per arm
  over the reportable rows and labelled items, with the dev split’s
  accuracy in its own column, descriptive only.

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
  `gr_call()`, so the governor, a cache keyed with `draw_index` and the
  trace all apply, under the labels `judge.<mode>.o<k>`. They are
  recorded in the judge’s own trace and their cost in `$judge_cost`,
  never in the trace of the run being judged, which gets a local note
  pointing at the judge’s trace; the judge is held to what that run’s
  governor has left.

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
