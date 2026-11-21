# Describe a reading configuration

Describe a reading configuration

## Usage

``` r
gr_read_spec(
  reader = "map_reduce",
  model = NULL,
  temperature = NULL,
  max_answer_tokens = 1500L,
  max_chunk_tokens = 700L,
  max_summary_tokens = 500L,
  top_k = 6L,
  min_score = -Inf,
  mmr = 1,
  context_order = c("relevance", "document", "edges"),
  rerank_candidates = 20L,
  rerank_min_score = 4,
  fan_in = 5L,
  max_levels = 5L,
  max_rounds = 4L,
  preview_tokens = 1200L,
  restate = c("auto", "always", "never"),
  members = NULL,
  cite = FALSE,
  skim_model = NULL,
  summary_model = NULL,
  parallel = NULL,
  delay_between_calls = 0,
  on_overflow = c("warn", "error"),
  effort = NULL,
  premise = FALSE,
  verify = FALSE,
  accept_near_verbatim = FALSE,
  max_merge_levels = 6L,
  restate_tokens = 1200L,
  bm25_k1 = 1.5,
  bm25_b = 0.75,
  lexical_blend = 0.5,
  ...
)
```

## Arguments

- reader:

  Reader name; see
  [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md).

- model:

  Chat model id. `NULL` (the default) means the model of the client the
  spec is read with, so `gr_client(model = "gpt-4o-mini")` is the model
  that answers, is budgeted for and is billed. A model named here, or in
  a recipe, is used whatever the client's.

- temperature:

  Sampling temperature, or `NULL` to omit the field. You do not need to
  null it yourself for reasoning models: it is dropped automatically for
  any model whose registry entry has `supports_temperature = FALSE`,
  which includes the default model. Check with
  `gr_model_info(model)$supports_temperature`.

- max_answer_tokens:

  Output cap for final answers and merges.

- max_chunk_tokens:

  Output cap for per-chunk calls.

- max_summary_tokens:

  Output cap for summarisation calls.

- top_k:

  For `retrieve`, `rerank` and `iterative`: chunks to use.

- min_score:

  For `retrieve`: chunks scoring below this are dropped, but if that
  would leave nothing the single best chunk is used anyway. `-Inf`
  disables the filter. Not a cosine similarity when embeddings fall back
  to lexical vectors: the score is then a blend of cosine and BM25.

- mmr:

  Diversity of selection, for `retrieve` and `iterative`. `1` (the
  default) is plain top-k. Below 1, chunks are picked greedily by
  `mmr * relevance - (1 - mmr) * similarity to what is already picked`,
  so three chunks saying the same thing do not all get in and pay for
  each other. Costs nothing: the vectors are already computed. `0.7` is
  a reasonable place to start; `0` selects for novelty alone and will
  happily pick irrelevant chunks because they are different.

- context_order:

  Where the selected chunks sit in the prompt. `"relevance"` (default)
  is most relevant first; `"document"` restores the order they appear in
  the document, which reads better when chunks are consecutive;
  `"edges"` puts the strongest first and second-strongest last, burying
  the weakest in the middle, because transformers attend measurably
  better to the beginning and end of a long context than to its middle.
  Selection is unaffected. This decides only placement, and it applies
  to `retrieve` and `rerank`, the two readers that put several ranked
  chunks in one prompt.

- rerank_candidates, rerank_min_score:

  For `rerank`: how many chunks to score, and the score below which a
  chunk is discarded. The candidates are the chunks the word-matching
  prefilter ranks highest. When no chunk shares a word with the
  question, it cannot rank them, so they are picked by embedding
  similarity instead, or, when embeddings cannot rank them either,
  spread evenly over the document and the answer marked partial. Either
  way the run warns (`gr_rerank_prefilter`) and `notes$prefilter` says
  which.

- fan_in, max_levels:

  For `hierarchical`: summaries combined per call, and the recursion
  depth cap.

- max_rounds:

  For `iterative`: retrieve-assess cycles.

- preview_tokens:

  For `preview`: the cap on the outline the planner sees. The outline is
  built from section labels, sizes and short excerpts (never the full
  text), and per-section excerpts shrink until the whole thing fits, so
  every section stays visible to the planner rather than the outline
  being truncated and some sections never being offered to it at all.
  The planner is an LLM call about a long document and so prone to
  exactly the degradation this package manages; keeping its input small
  is the mitigation.

- restate:

  Whether to repeat the question before the excerpts as well as after
  them: `"auto"` when the body is long enough to bury the first ask,
  `"always"`, or `"never"`. A setting rather than a rule, because
  whether it helps is a question about your corpus and your model. Point
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  at two recipes differing only in this and find out.

- members:

  For `ensemble`: the reader names to combine.

- cite:

  Ask for chunk-level citations (`[chunk 3]`) in the answer. Map those
  ids back to pages via `ans$evidence`. Forced off for `hierarchical`,
  which answers from summaries: summaries carry no `[chunk N]` ids, so
  asking for citations there asks the model to invent them. For `skim`,
  when its evidence has to be consolidated to fit and no `[chunk N]`
  label survives the consolidation, citations are not asked for either
  (`notes$cite_dropped = TRUE`); when some survive, a citation is
  checked against those.

- skim_model, summary_model:

  Optional cheaper models for the per-chunk stages. `skim_model` is used
  by `skim`'s extraction **and** `rerank`'s relevance scoring;
  `summary_model` by `hierarchical`'s summarisation.

- parallel:

  Run per-chunk calls in parallel. Needs the `future` and `future.apply`
  packages; without them the run is sequential and says so.

  The trace is complete either way: workers keep their own and the
  parent absorbs them, in input order, so a parallel run reports the
  same calls, tokens and cost as the same run made sequentially. So is
  what the client keeps: a mock's or backend's `$calls()` and
  `$embeds()`, and the hit, miss and write counts of an attached cache,
  include the calls made in workers, added back in input order. A replay
  client always runs one request at a time, since it hands out its
  recording in order.

  Two things do not cross the process boundary. The limits in
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
  are checked before a batch is sent and not inside it, since a worker
  cannot see what the others spend. So the pre-flight check, which runs
  in the parent, holds a parallel run to its worst case, every reply at
  its cap and as many merge or summary levels as replies that size need,
  against both `max_calls` and `max_cost_usd`; and each batch goes to
  the workers only when it fits what the run has left at its own worst
  case, and otherwise runs one request at a time, each checked. And a
  handler that records calls in variables of its own (a closure passed
  to
  [`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
  or
  [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md))
  records a worker's calls in that worker's copy, which this process
  never sees; ask the trace, or the client's `$calls()`, instead.

- delay_between_calls:

  Seconds to sleep between sequential calls, for rate-limit shaping.
  Honoured by `map_reduce`, `refine` and `skim`; the other readers do
  not sleep.

- on_overflow:

  For `stuff`: `"warn"` (truncate and say so) or `"error"`.

- effort:

  How much a reasoning model reasons before it answers, or `NULL` (the
  default) to send nothing, so every request goes out at the provider's
  default exactly as before. One string, such as `"low"`, applies to
  every call. A character vector named by stage sets it per stage:
  `c(extract = "low", "synthesise.section" = "high")`. A name covers
  each call whose trace label is that name or starts with it and a dot;
  the longest name that covers a label wins; an unnamed element, or one
  named `"default"`, covers the labels no name does, and a label nothing
  covers is sent no effort. A name must cover a stem some registered
  reader, segmenter or stage declares (the `calls` column of
  [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
  and
  [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md)),
  or a label under one, so a misspelt name is an error of class
  `hr_unknown_effort_key` that lists the stems, not a setting that
  reaches no call. It reaches the segmenters that call a model too, when
  the spec is part of a recipe. See the section on reasoning effort.

- premise:

  Check the question's assumptions against the document. A question can
  take for granted something the document contradicts ("Why did revenue
  fall?" of a report in which it rose). Without this check a reader
  answers it on its own terms or reports `NOT_IN_DOCUMENT`, and either
  way what the document does say is lost. With `premise = TRUE` the
  prompts that answer the question tell the model that, when the
  excerpts state the contrary of an assumption in it, it is to say so in
  one sentence giving what they state instead, rather than answer. That
  sentence becomes `$answer` and `$premise` (see
  [gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md)),
  and
  [`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
  is `FALSE` for it. Excerpts that are merely silent are still
  `NOT_IN_DOCUMENT`. See "Checking the premise" below for how each
  reader combines what its requests report. The verdict is the model's
  reading of the excerpts, not a check harnessr makes, so weigh it as
  you would any answer. Off by default because it changes what is sent:
  the prompts are longer, so a cache, a recorded replay or a
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  store made without it does not answer a run with it, and the reverse.
  `screen` and `extract`, which answer no question, ignore it.

- verify:

  Check the answer's quotations against the chunks they come from, and
  let the check decide what is accepted. `FALSE` (the default) sends the
  same requests and accepts answers as before; the `quote_*` shadow
  columns are still recorded on checked evidence (see "Verifying
  quotations"). With `TRUE`,
  [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  runs
  [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  on every answer, writes its columns onto `$evidence`, marks the answer
  partial when a quotation is not found, and records a `read.verify`
  step in the trace. The `iterative` reader also asks each step that
  says it can answer for the passages it rests on, word for word with
  their chunk numbers, and stops only when every one is found in the
  chunk it names; a refused step is told which quotations were not
  found, and a run that ends with none accepted answers
  `NOT_IN_DOCUMENT`. Its evidence is then the quotations, not every
  chunk it was shown. A step that reports the premise false
  (`premise = TRUE`) is not asked for quotations and is not refused for
  lacking them: its verdict stops the loop as it does without `verify`.
  See "Verifying quotations" below.

- accept_near_verbatim:

  Under `verify = TRUE`, whether a quotation the edit-distance matcher
  scores `near_verbatim` (see "Verifying quotations") also lets the
  `iterative` reader stop. `FALSE` (the default) accepts only a
  quotation the decisive check verifies, as before the setting existed.
  A near-verbatim quotation that stops the loop is still reported as not
  verified in `$evidence`, so the answer is marked partial. `TRUE`
  without `verify = TRUE` is refused with a `gr_bad_setting` error.
  Untested: nothing has measured whether accepting near-verbatim
  quotations gives better answers, and on the package's labelled
  quotation set 25 of 46 quotations with one content word swapped scored
  `near_verbatim`.

- max_merge_levels:

  The most merge levels `map_reduce`, `skim` and the other readers that
  merge findings run before they give up and return the findings
  unmerged and cut, with the answer partial. \[1, 12\], default 6, the
  cap the code had before it was a setting. Separate from `max_levels`,
  which only `hierarchical` reads. Untested.

- restate_tokens:

  Under `restate = "auto"`, the length of the excerpts, in tokens, above
  which the question is repeated before them. \[0, 1e6\], default 1200,
  the value the code had before it was a setting. Untested: the code
  called it "a number, and an arbitrary one".

- bm25_k1, bm25_b:

  The Okapi BM25 parameters of the word-matching scores that `rerank`
  prefilters its candidates with and that `retrieve` blends in when
  embeddings are lexical. Defaults 1.5 and 0.75, the usual values given
  by Robertson and Zaragoza (2009), "The Probabilistic Relevance
  Framework: BM25 and Beyond"; not tuned on this package's tasks.
  `bm25_k1` \[0, 10\], `bm25_b` \[0, 1\].

- lexical_blend:

  For `retrieve` when the embeddings are lexical (the offline embedder,
  or the fallback when the embeddings request fails): the weight of the
  cosine score, with `1 - lexical_blend` on the BM25 score. \[0, 1\],
  default 0.5, an even blend chosen when the offline path was written.
  Untested.

- ...:

  Extra fields for custom readers.

## Value

A list of class `gr_read_spec`.

## Checking the premise

With `premise = TRUE`, every request that answers the question carries
the rule: the single answering request of `stuff`, `retrieve`, `rerank`,
`skim`, `hierarchical` and `preview`; each chunk's request and the merge
of `map_reduce`; the draft and every revision of `refine`; each step and
the final answer of `iterative`; and the adjudication of `ensemble`.
Requests that only pick, score, summarise or copy out passages do not.

`map_reduce` treats a chunk that contradicts the premise differently
from one that only lacks the answer. The second is dropped, as it always
was. The first is passed to the merge as a finding that says the premise
is contradicted and what the excerpt states instead, and the merge, told
the same rule, weighs it against the chunks that did answer and may
itself report the premise false. `notes$premise_chunks` lists the chunks
that reported it, whatever the merge decided. `ensemble` does the same
with its members (`notes$premise_members`). `refine` carries the verdict
in its draft, so a later excerpt can add to the correction or overturn
it. `iterative`'s step reports it in a `false_premise` field of its
reply, which is in the schema only when the premise is checked, and
stops there. A merge or adjudication that failed returns the findings
joined, which is no verdict: `$premise` is `NA`, and the notes still
name the chunks or members that reported it.

The answer records the check: `$premise` is `NA` when nothing
contradicted the question, and the correction when something did.
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
and
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
add a `premise` column to their summaries,
[`print()`](https://rdrr.io/r/base/print.html) and
[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
say when the model reported the premise false, and the trace has a
`read.premise` step with the outcome.

## Verifying quotations

A reader that puts the chunks it read into `$evidence` has quoted them
by construction, so for `stuff`, `retrieve`, `rerank` and the default
`iterative` a passing check says only that the chunks were the ones
sent. The check means something where a model chose what to quote:
`skim`, `extract`, `screen`, and `iterative` under `verify = TRUE`.

Two matchers score each quotation. The one that decides `verified` is
the check described in
[`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md),
unchanged. Beside it the answer carries `quote_status`, `quote_sim`,
`quote_coverage`, `quote_edits` and `quote_critical_ok` from an
edit-distance matcher that tolerates ligatures, line-break hyphens and
OCR letter errors while requiring numbers, units and negations to be
identical. It is recorded only, and decides nothing in this release.

`verify = TRUE` changes what `iterative` sends (its schema and
instructions), so a cache or recording made without it does not answer a
run with it. The other readers send exactly what they sent before.

## Out-of-range values

Numeric arguments are clamped into a usable range and the change is
warned about, never applied silently: `top_k` \[1, 1e4\], `fan_in` \[2,
32\], `max_levels` \[1, 12\], `max_rounds` \[1, 20\],
`rerank_candidates` \[1, 1e4\], `rerank_min_score` \[0, 10\],
`preview_tokens` \[100, 1e5\], `delay_between_calls` \[0, 600\], token
caps \[16, 1e6\]. The ranges of the settings added later are given with
each argument.

## Where the defaults come from

Each setting's default, its tier (`basic` for the few most users change,
`advanced` for the rest) and the evidence behind the value. `untested`
means no measurement backs the value; `cited` names the published source
it comes from. The settings added as declared parameters
(`accept_near_verbatim`, `max_merge_levels`, `restate_tokens`,
`bm25_k1`, `bm25_b`, `lexical_blend`) are stored in the spec only when
they are not their default, so a default spec keeps the store and cache
keys it had before they existed.

- `on_overflow` (default `"warn"`, advanced): untested. Chosen so that a
  document too long for one request still gets an answer that says what
  was cut.

- `context_order` (default `"relevance"`, advanced): untested. The order
  the readers used before the setting existed; the alternatives were
  added to be compared, and no comparison is recorded.

- `restate` (default `"auto"`, advanced): untested. A setting so that
  gr_compare() can measure it on a corpus; no measurement is recorded.

- `premise` (default `FALSE`, advanced): untested. Off, so a run sends
  the requests it sent before the check existed.

- `verify` (default `FALSE`, basic): untested. Off, so a run sends the
  requests and accepts the answers it did before the check existed.

- `effort` (default `NULL`, advanced): untested. Unset: no effort is
  sent, and the provider's own default applies.

- `reader` (default `"map_reduce"`, basic): untested. The reader that
  sends every chunk, chosen because it reads the whole document at any
  length; no comparison of readers is recorded.

- `model` (default `NULL`, basic): untested. Not a tuned value: NULL
  takes the client's model.

- `temperature` (default `NULL`, advanced): untested. Not a tuned value:
  NULL takes gr_options("temperature"), which sends none.

- `max_answer_tokens` (default `1500`, advanced): untested. Set as a
  generous cap for an answer; not measured.

- `max_chunk_tokens` (default `700`, advanced): untested. Set as a cap
  for one chunk's finding; not measured.

- `max_summary_tokens` (default `500`, advanced): untested. Set as a cap
  for one summary; not measured.

- `top_k` (default `6`, basic): untested. A common starting value for
  retrieval; not tuned here.

- `min_score` (default `-Inf`, advanced): untested. Not a tuned value:
  -Inf applies no floor.

- `mmr` (default `1`, advanced): untested. 1 is plain top-k, the
  selection used before the setting existed.

- `rerank_candidates` (default `20`, advanced): untested. Set when
  rerank was written; not tuned.

- `rerank_min_score` (default `4`, advanced): untested. Set when rerank
  was written; not tuned.

- `fan_in` (default `5`, advanced): untested. Set when hierarchical was
  written; not tuned.

- `max_levels` (default `5`, advanced): untested. Set when hierarchical
  was written; not tuned.

- `max_rounds` (default `4`, advanced): untested. Set when iterative was
  written; not tuned.

- `preview_tokens` (default `1200`, advanced): untested. Set when
  preview was written; not tuned.

- `members` (default `NULL`, advanced): untested. NULL takes ensemble's
  own pair, retrieve and map_reduce; not compared with other pairs.

- `cite` (default `FALSE`, basic): untested. Off, so the answer prompt
  is the one used before the setting existed.

- `skim_model` (default `NULL`, advanced): untested. Not a tuned value:
  NULL uses `model`.

- `summary_model` (default `NULL`, advanced): untested. Not a tuned
  value: NULL uses `model`.

- `parallel` (default `NULL`, advanced): untested. Not a tuned value:
  NULL follows gr_options("parallel"). It does not change output.

- `delay_between_calls` (default `0`, advanced): untested. No pause. It
  does not change output.

- `accept_near_verbatim` (default `FALSE`, advanced): untested. Off, as
  the code behaved before the setting existed. Not measured as a
  stopping rule; on the labelled quotation set, 25 of 46 quotations with
  one content word swapped score near_verbatim (NEWS, 0.6.0.9000).

- `max_merge_levels` (default `6`, advanced): untested. The cap the
  merge code had as a constant; not tuned.

- `restate_tokens` (default `1200`, advanced): untested. An arbitrary
  number, as its comment said when it was a constant; not measured.

- `bm25_k1` (default `1.5`, advanced): cited. Robertson and Zaragoza
  (2009), "The Probabilistic Relevance Framework: BM25 and Beyond", give
  k1 between 1.2 and 2.0 as usual; not tuned here.

- `bm25_b` (default `0.75`, advanced): cited. Robertson and Zaragoza
  (2009), "The Probabilistic Relevance Framework: BM25 and Beyond", give
  b = 0.75 as usual; not tuned here.

- `lexical_blend` (default `0.5`, advanced): untested. An even blend,
  set when the offline path was written.

## Reasoning effort

The default models reason before they write a reply, and that reasoning
is billed as output and counted against the same output cap as the
reply. Nothing sets how much unless `effort` does, so a corpus's
hundreds of per-chunk calls reason as long as the one call that drafts
its claims.

The effort is sent as `reasoning = {"effort": ...}` on the Responses API
and as `reasoning_effort` on Chat Completions, and a
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
or
[`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
handler finds it in `params$effort`. It is sent only to a model whose
[`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md)
says `reasoning = TRUE`, and left out without a warning for any other,
which would refuse the field, as `temperature` is left out for a model
that refuses that; register a gateway's reasoning model with
[`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md)
to reach it. For the calls it covers it replaces an effort the client's
`extra_body` sets. A
[`gr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/gr_ellmer_client.md)
cannot take it per call, says so once (`gr_effort_unsupported`) and does
not record it as sent. A value is passed through as given; one that is
not `"none"`, `"minimal"`, `"low"`, `"medium"`, `"high"` or `"xhigh"` is
warned about (`gr_effort_unknown`) and sent anyway, since providers add
levels.

Each request's effort is in its trace step (`params$effort`, and an
`effort` column of `as.data.frame(trace)`), and
[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
shows it beside what each stage cost. It is part of the
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
key, and, when set, of a recipe's store key in
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md),
of what
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
counts as a different recipe, and of the key a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
matches on, so runs at different efforts never share answers. Unset,
none of those keys change.

The labels are the `stage` column of `as.data.frame(trace)`:
`segment.context`, `segment.proposition`; `stuff.answer`; `map.answer`,
`reduce`; `refine.draft`, `refine.revise`; `skim.extract`,
`skim.consolidate`, `skim.answer`; `retrieve.answer`; `rerank.score`,
`rerank.answer`; `hier.summarise.L1` (and `L2`, ...), `hier.answer`;
`iterative.step`, `iterative.final`; `ensemble.adjudicate`;
`preview.plan`, `preview.skim`, `preview.answer`; `screen.decide`;
`extract.chunk`, `extract.resolve`; and, for
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md),
`claims.draw`, `claims.reconcile`, `outline.derive`,
`synthesise.section`, `synthesise.batch`, `synthesise.merge` and
`synthesise.revise.structure` (`.cut`, `.register`). A merge that takes
more than one level labels the levels below its final merge `.level1`,
`.level2` and so on, which its own name covers.

A starting point, not a default: low for the many mechanical calls and
high for the few that judge.

    effort = c("extract.chunk" = "low", "skim.extract" = "low",
               "rerank.score" = "low", segment = "low", "map.answer" = "low",
               "claims.draw" = "high", "outline.derive" = "high",
               "synthesise.section" = "high", "ensemble.adjudicate" = "high")

Reasoning shares the reply's cap, so a call at `"high"` can spend all of
it and come back cut off (`finish_reason = "length"`, warned about where
it matters). Give such stages room: `max_answer_tokens` here,
`max_section_tokens` in
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md),
`max_outline_tokens` in
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md).
Requests to a reasoning model are sent with an output cap of at least
2048 tokens whatever the effort, and the cost limits are checked at that
cap.

## See also

[`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
for the available readers and their call costs,
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`gr_recipe()`](https://elkronos.github.io/harnessr/reference/gr_recipe.md)

Other reading functions:
[`gr_answer`](https://elkronos.github.io/harnessr/reference/gr_answer.md),
[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md),
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`gr_reader_signature()`](https://elkronos.github.io/harnessr/reference/gr_reader_signature.md),
[`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md),
[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md),
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md),
[`new_answer()`](https://elkronos.github.io/harnessr/reference/new_answer.md)

## Examples

``` r
gr_read_spec("retrieve", top_k = 8)$top_k
#> [1] 8

# Out-of-range settings are corrected loudly, not quietly.
suppressWarnings(gr_read_spec("hierarchical", fan_in = 999)$fan_in)
#> [1] 32

# Reasoning effort by stage: little for the per-chunk calls, more for the
# merge. The trace says which request carried which.
ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 150))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 150 tokens, overlap 0).
cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
sp <- gr_read_spec("map_reduce", model = "gpt-5.6-luna",
                   effort = c(map = "low", reduce = "high"))
tr <- gr_trace()
invisible(gr_read(ch, "What was revenue?", cl, sp, trace = tr))
#> Reading with 'map_reduce' (all|N+logN|tree) over 5 chunk(s).
unique(as.data.frame(tr)[, c("stage", "effort")])
#>        stage effort
#> 1 map.answer    low
#> 6     reduce   high
# A loaded question, checked against the document. The mock plays a model
# that finds the excerpts contradict it.
cl <- gr_mock_client(function(m, p)
  "FALSE_PREMISE: Revenue rose 12% in 2023, to 45.2 million.")
ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 400))
#> Using cached ingestion for this document + settings.
#> Segmenting with 'sentence' (cap 400 tokens, overlap 0).
ans <- gr_read(ch, "Why did revenue fall in 2023?", cl,
               gr_read_spec("stuff", premise = TRUE))
#> Reading with 'stuff' (all|1|none) over 2 chunk(s).
ans$premise
#> [1] "Revenue rose 12% in 2023, to 45.2 million."
is_not_found(ans$answer)
#> [1] FALSE
```
