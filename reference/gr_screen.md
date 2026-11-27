# Decide which documents a review should read

The stage before
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).
One model call per document, a decision and a reason for every one, and
nothing dropped on the way.

## Usage

``` r
gr_screen(
  sources,
  protocol = NULL,
  question = NULL,
  include = NULL,
  exclude = NULL,
  recipe = "research",
  client = NULL,
  store = NULL,
  screen_tokens = NULL,
  on_error = c("continue", "stop"),
  max_total_usd = NULL,
  max_total_calls = NULL,
  keep_answers = FALSE,
  recursive = FALSE,
  trace = NULL,
  criteria_schema = c("decision", "per_criterion"),
  samples = 1L,
  sample_rule = c("include_if_any", "majority", "k_of_n"),
  sample_k = NULL,
  ...
)
```

## Arguments

- sources:

  As
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md):
  file paths, a directory, or raw text.

- protocol:

  A
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md)
  carrying the criteria and the review question. Give this, or
  `include`/`exclude` directly.

- question, include, exclude:

  The review question and the criteria, if you are not passing a
  protocol. Each criterion is one statement a document either meets or
  does not.

- recipe, client, store, on_error, max_total_usd, recursive,
  keep_answers:

  As
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).

- screen_tokens:

  Cap what the model is shown, in tokens, counted from the start of the
  document. Leaving it unset shows as much as the model's context
  allows. Setting it to a few hundred is title-and-abstract screening,
  done deliberately: cheaper, and closer to what a human screener sees
  at this stage. The opening is whole chunks while they fit; when the
  first chunk is longer than the cap on its own (a structural chunk of
  title, abstract and introduction can be), it is cut to the cap and
  that is what is screened. A cap too small to show any of the document
  at all fails the document, with an `error` naming `screen_tokens`.
  Either way the `truncated` and `seen_tokens` columns say what was
  actually read.

- max_total_calls, trace:

  As
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).
  Pass the same `trace` to
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  and it accumulates the whole review, while each stage keeps its own
  for its own cost and its own ceiling.

- criteria_schema:

  What each screening reply holds. `"decision"` (the default) asks for a
  decision, a reason, the deciding criterion and a quote, as before.
  `"per_criterion"` also asks, for every criterion, whether the excerpt
  shows it `"met"`, `"not_met"` or `"not_reported"`, and adds a
  `criteria_status` column to the table (`"criterion: status"` pairs,
  separated by `"; "`). An exclusion then needs an inclusion criterion
  `"not_met"` or an exclusion criterion `"met"`: a reply that excludes
  with none of either, as when a criterion is not reported and none is
  not met, is recorded as `"unclear"`, for a person to decide, with a
  reason that says so. It changes the request (the schema and the
  criteria message). Untested.

- samples:

  How many times each document's screening request is sent, from 1
  to 20. At 1 (the default) it is sent once, as before. Above 1 it is
  sent that many times, each a separate draw (a cache keeps each), and
  the draws are combined by `sample_rule`; the table gains
  `sample_decisions` (each draw's decision, `"none"` for one not read)
  and `include_share` (the share of draws read that included). It
  multiplies the screening requests by `samples`. In run r of
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  the draws are numbered (r - 1) \* samples + 1 to r \* samples, so each
  run sends its own draws. Untested.

- sample_rule:

  How draws are combined when `samples` is above 1. `"include_if_any"`
  (the default) includes a document any draw included, excludes one only
  when every draw was read and excluded it, and sends the rest to a
  person as `"unclear"`, so a study one draw would keep is not lost to
  the others. `"majority"` takes the decision most draws gave,
  `"unclear"` on a tie. `"k_of_n"` includes a document when at least
  `sample_k` draws included it, excludes one only when every draw was
  read and excluded it, and sends the rest to a person as `"unclear"`.
  The reason, criterion and quote are the first draw's that gave the
  decision kept. Untested.

- sample_k:

  Under `sample_rule = "k_of_n"`, how many draws must include a document
  for it to be included: a whole number from 1 to `samples`. `k_of_n`
  needs it, and the other rules take none. At 1 it decides as
  `"include_if_any"` does; at `samples` a document is included only when
  every draw included it. Untested.

- ...:

  Recipe overrides, as in
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).

## Value

An object of class `gr_screening`:

- `table`:

  One row per document: `document`, `document_id`, `decision`, `reason`,
  `criterion`, `criterion_valid`, `quote`, `verified`, `seen_tokens`,
  `document_tokens`, `truncated`, `status`, `duplicate_of`, `error`.

- `included`:

  The distinct sources whose decision was `"include"` (the paths, not
  the display labels). Duplicates are left out; they are the same study,
  and `table` still has their rows.
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  takes this, but prefer handing it the whole screening object: a
  character vector of paths cannot carry the search, so
  `gr_extract(screened)` keeps it and `gr_extract(screened$included)`
  does not.

- `forward`:

  The distinct sources kept for full text: `"include"` and `"unclear"`.
  An unclear record is a deferral, not an exclusion, so this is the set
  a review should read next. In this release `gr_extract(screened)`
  still reads `included`, and warns (class `gr_unclear_dropped`) when
  that leaves unclear records out; from 0.9.0 it reads `forward`.

- `deferred`:

  The distinct sources whose decision was `"unclear"`: the ones a person
  still has to decide, with
  [`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md).

- `sources`:

  Every source, one per row of `table`, so that
  [`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md)
  can rebuild the sets above.

- `records`:

  The
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  the run was made over, or `NULL`.

- `sampling`:

  Only when `samples` is above 1: a list of `samples`, `sample_rule`
  and, under `"k_of_n"`, `sample_k`, the rule that turned the draws in
  `sample_decisions` into `decision`.

- `summary`,`answers`,`trace`,`store`:

  As
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).

## Three decisions, not two

`decision` is `"include"`, `"exclude"` or `"unclear"`. The third is not
a failure mode; it is the answer when the excerpt does not settle the
question, and it is what stops an uncertain call from being recorded as
a confident one. Those documents are for a person to look at. Every
published evaluation of automated screening reaches the same conclusion:
reliable on the easy calls, not yet trustworthy alone on the hard ones.

A document that could not be read at all gets `status = "failed"` and no
decision. It is not excluded, and it is not silently absent: it is an
outstanding job. A review whose denominator is unknown is not a review.
The same goes for a document whose screening request failed, or whose
reply was not the JSON asked for: no model judged it, so it is not
"unclear" either. `error` says what happened, and with a `store` the
next run screens it again.

## The criterion is checked

`criterion` is the criterion the model said decided it, in the
protocol's own words when it matches one of `include` or `exclude`
(case, spacing, a leading list marker, surrounding quotes and closing
punctuation aside); `criterion_valid` says whether it did, and is `NA`
when the model named none. An exclusion has to name one of the
protocol's criteria: an exclusion criterion it meets, or an inclusion
criterion it fails. One that names another criterion, or none, is
recorded as `"unclear"` so that a person decides, with
`criterion_valid = FALSE` (or `NA`) and a `reason` saying so. The match
is on the wording, so a paraphrased criterion is held back too; that
costs a person a look, where accepting an invented one would cost a
study.

The quote is checked against the excerpt the model was shown and
attributed to the chunk that contains it; a quote spanning two chunks,
or one that does not verify, has no chunk.

## Reporting it

`table(x$table$decision)` is the screening result and
`table(x$table$criterion[x$table$decision %in% "exclude"])` is the
breakdown of exclusions by criterion, which is what a flow diagram asks
for; every one names a criterion of the protocol. Duplicates were
removed before screening, so `sum(!is.na(x$table$duplicate_of))` is the
"duplicates removed" count and every one of them still has a row; see
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).

## See also

[`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md),
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)

## Examples

``` r
cl <- hr_mock_client(function(messages, params) {
  '{"decision":"include","reason":"Reports a randomised comparison.",
    "criterion":"Reports a randomised comparison",
    "quote":"We randomly assigned participants to two groups."}'
})

f <- tempfile(fileext = ".txt")
writeLines("We randomly assigned participants to two groups.", f)

s <- gr_screen(f, question = "Does the treatment work?",
               include = "Reports a randomised comparison", client = cl)
#> [1/1] file1b662bdc0cde.txt
#> Extracting 'file1b662bdc0cde.txt' with the 'txt' extractor.
#> Ingested 1 block(s), ~15 tokens (0 chars removed by cleaning).
#> Segmenting with 'structural' (cap 900 tokens, overlap 90).
#> Reading with 'screen' (head|1|none) over 1 chunk(s).
s$table[, c("document", "decision", "reason")]
#>               document decision                           reason
#> 1 file1b662bdc0cde.txt  include Reports a randomised comparison.
```
