# A test of what a reader keeps as it condenses a document

Builds a benchmark for
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md):
documents with planted facts, lures and a later correction, read
forwards and reversed, with one question per fact and a scorer that
needs no model. Arms that differ in how they carry a document (a
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
`refine_state`, a `context_policy`, a reader) are run on its `reference`
and scored with its `scorer`; `gr_condensation_summary()` reads the
result.

## Usage

``` r
gr_condensation_check(
  text = NULL,
  n_facts = 6L,
  n_lures = 2L,
  correction = TRUE,
  n_documents = 1L,
  paragraphs = 12L,
  orders = c("forward", "reversed"),
  seed = 1L,
  split = "test"
)

# S3 method for class 'gr_condensation_check'
print(x, ...)

gr_condensation_summary(check, bench)
```

## Arguments

- text:

  `NULL` for synthetic documents, or a document of your own as one
  string, whose paragraphs (split at blank lines) the facts are planted
  between. Its own text must not mention the planted places.

- n_facts:

  Facts per document, 2 to 10.

- n_lures:

  How many of the facts get a lure, 0 to `n_facts - 1`.

- correction:

  Whether the last fact is stated wrongly early and corrected late.

- n_documents:

  Synthetic documents to build, each its own cluster; 1 when `text` is
  given. A document's forward and reversed copies carry the same facts,
  so they share its cluster.

- paragraphs:

  Filler paragraphs per synthetic document, at least `n_facts`.

- orders:

  `"forward"`, `"reversed"` or both.

- seed:

  A whole number that fixes the places and values.

- split:

  The split of every item; see
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).

- x:

  A `gr_condensation_check`.

- ...:

  Ignored.

- check:

  A `gr_condensation_check`.

- bench:

  An
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  result on `check$reference`.

## Value

`gr_condensation_check()` returns an object of class
`gr_condensation_check`, a list of `reference` (an
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
whose payloads are `question` and `document`, as
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
builds them), `scorer` (an
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
named `"condensation"`), `items` (a data frame of `item`, `document`,
`order`, `kind` (`"fact"`, `"lure"` or `"correction"`), `position`
(where the fact sits in the forward document, from 0 at the start to 1
at the end), `question`, `answer`, `lure` and `superseded`) and
`documents` (the texts, named by document and order).

`gr_condensation_summary()` returns a data frame with one row per arm
and order: `fact_recall` (the share of runs whose answer holds the
fact's value, over every item), `lure_rate` (the share of runs on lure
items whose answer holds the lure's value), `correction_won` (the share
of runs on correction items that are right), `late_recall` (fact recall
over the facts in the last third of the document as it was read) and
`runs`.

## Details

Each document is a run of plain paragraphs, from `text` or from neutral
filler sentences, with `n_facts` facts planted at evenly spread
positions from the first paragraph to the last: "The budget of the
Harbour depot was 41.3 million dollars." Each fact gets a question whose
answer is its value. For the first `n_lures` facts a lure is planted as
well, the same measure for a near-namesake ("the Harbour depot annexe")
with another value. With `correction = TRUE`, the last fact is first
stated with a wrong value in the opening paragraphs and corrected near
the end ("Correction: ... was 248. The figure of 212 given earlier was
wrong."). Every document is then given forwards and reversed by
paragraph
([`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md)),
so a fact near the end for one order is near the start for the other.

The values are fixed by `seed` with arithmetic, not by the random number
generator, so the same call builds the same benchmark in any session.

The scorer finds the values in the answer as
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
finds an answer: folded, and as a whole number. A fact item is right
when the answer holds its value. A lure item is right when it holds the
value and not the lure's. A correction item is right when it holds the
corrected value and not the superseded one. The `outcome` names what was
found: `"answer"`, `"lure"`, `"superseded"`, `"answer+lure"`,
`"answer+superseded"`, `"not_found"` or `"other"`.

## See also

[`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
for `refine_state` and `context_policy`

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md),
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
[`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md),
[`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
[`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md),
[`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md),
[`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md),
[`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md),
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md),
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md),
[`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)

## Examples

``` r
chk <- gr_condensation_check(n_facts = 4, n_lures = 1)
chk
#> <gr_condensation_check> 1 document(s), forward and reversed, 8 item(s)
#>   per order: 2 fact, 1 lure, 1 correction
head(chk$items[, c("item", "kind", "question", "answer", "lure")])
#>                     item       kind
#> 1       d1.lure1.forward       lure
#> 2       d1.fact2.forward       fact
#> 3       d1.fact3.forward       fact
#> 4 d1.correction4.forward correction
#> 5      d1.lure1.reversed       lure
#> 6      d1.fact2.reversed       fact
#>                                                question answer  lure
#> 1      What was the floor area of the Northgate clinic?  3,565 4,120
#> 2 How many yearly visits did the Riverside school have? 10,237  <NA>
#> 3        What was the budget of the Elm Street library?   42.5  <NA>
#> 4       What was the staff count of the Westfield mill?    321  <NA>
#> 5      What was the floor area of the Northgate clinic?  3,565 4,120
#> 6 How many yearly visits did the Riverside school have? 10,237  <NA>

# Two arms that differ only in what refine carries, on a stand-in model
# that answers every question with the planted budget.
cl <- hr_mock_client(function(m, p) {
  if (grepl("Reply with the edits", m[[length(m)]]$content, fixed = TRUE)) return("NONE")
  "The budget was 41.3 million dollars."
})
arms <- hr_sweep(gr_arm("thorough", list(reader = "refine", method = "paragraph")),
                 list(refine_state = c("draft", "ledger")))
bench <- suppressWarnings(hr_benchmark(arms, chk$reference, runs = 1, client = cl,
                                       scorer = chk$scorer))
#> Ingested 12 block(s), ~503 tokens (0 chars removed by cleaning).
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Ingested 12 block(s), ~503 tokens (0 chars removed by cleaning).
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
#> Using cached ingestion for this document + settings.
#> Segmenting with 'paragraph' (cap 1200 tokens, overlap 120).
#> Reading with 'refine' (all|N|forward) over 1 chunk(s).
gr_condensation_summary(chk, bench)
#>                            arm    order fact_recall lure_rate correction_won
#> 1  thorough:refine_state=draft  forward           0         0              0
#> 2  thorough:refine_state=draft reversed           0         0              0
#> 3 thorough:refine_state=ledger  forward           0         0              0
#> 4 thorough:refine_state=ledger reversed           0         0              0
#>   late_recall runs
#> 1           0    4
#> 2           0    4
#> 3           0    4
#> 4           0    4
```
