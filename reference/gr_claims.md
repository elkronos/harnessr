# The claims a table of studies supports

Turns an extraction table into statements about the *literature*, each
naming the studies it rests on. It is the step that makes a write-up a
synthesis rather than an ordered recitation, and the step that lets a
section be written from an argument instead of from rows.

## Usage

``` r
gr_claims(
  extraction,
  question = NULL,
  protocol = NULL,
  client = NULL,
  model = NULL,
  temperature = NULL,
  max_claim_tokens = 1600L,
  include_unclear = FALSE,
  trace = NULL,
  bib = NULL,
  effort = NULL,
  unverified = c("exclude", "include"),
  moderators = NULL
)
```

## Arguments

- extraction:

  A
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result, or a data frame shaped like its `$table`.

- question:

  The review question. Taken from `protocol` if omitted.

- protocol:

  A
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md);
  its `question` is used when `question` is not given.

- client:

  An
  [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md).
  One is built from `model` if omitted.

- model, temperature, max_claim_tokens:

  Passed to the model call. `max_claim_tokens` is the reply limit for
  each call, and it also sets how many studies go into one: about
  `(max_claim_tokens - 400) / 40`. Raise it for fewer, larger batches.

- include_unclear:

  Keep rows with nothing extracted. Off by default, the same as
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md).

- trace:

  An
  [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  to add this stage's calls to, or `NULL`. The calls are recorded on a
  trace of the stage's own, returned as `$trace`, and folded into
  `trace` when the stage ends, as in
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md).
  Its requests are held to the governor of `trace`, if it has one, less
  what `trace` has already spent (see
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)).

- bib:

  Which columns carry bibliographic identity, as in
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md):
  a named list of `citation`, `authors`, `year`, `title`, `venue`,
  `doi`. Those columns are withheld from the model, so a claim cannot
  attribute a finding to a name, and cannot be moderated by one.
  Omitted, only the conventional names are withheld. Pass the same `bib`
  to
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  and
  [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md).

- effort:

  Reasoning effort, or `NULL` (the default) to send none: one string, or
  a character vector named by stage, as `effort` in
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).
  The calls here are labelled `claims.draw` and `claims.reconcile`, so
  `c(claims = "high")` covers both. Drawing claims is judgement, the
  stage most worth a higher effort. The reasoning counts against the
  same reply limit, so a high effort can leave a batch's reply cut off,
  which is reported as such (`gr_claims_truncated`).

- unverified:

  What the claims prompt does with an extracted value whose quote did
  not verify, or that came with no quote (see
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  "Verifying it"). `"exclude"` (the default) leaves it out of the
  prompt, so no claim rests on it, and lists it in `$unverified`;
  `"include"` shows it, marked unverified with the quote that was given.
  Either way each value shown carries its check and its quote. Only a
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  result carries the quotes: a bare table's values are shown as they
  are, with no check, and nothing is left out. The default is untested:
  it follows the rule that a claim should rest on what the documents
  were found to say, and no benchmark has compared the two.

- moderators:

  The columns you expected, before reading, to explain a disagreement
  between studies: a character vector of column names, or `NULL` (the
  default) for none. A claim's moderator is "declared" when it is one of
  these, and is then tested with the others for multiplicity (Holm). Any
  other moderator the model names is "exploratory", and so is any split
  of one study against one. See "Moderators" below. Naming a column
  changes nothing that is sent.

## Value

An object of class `gr_claims`:

- `claims`:

  One row per claim: `claim_id`, `claim`, `kind`, `moderator`,
  `moderator_status` (`"declared"`, `"exploratory"` or NA), `scope`,
  `n_support`, `n_contradict`, `sign_p`, `low_power`, `note`. `sign_p`
  is the exact two-sided sign test of the claim's direction tally,
  `n_support` of `n_support + n_contradict` studies: 5 of 5 gives
  0.0625. `low_power` is `TRUE` when the tally is 5 studies or fewer, so
  that no split of it can reach p \< 0.05. See "Direction of effect"
  below.

- `support`:

  Long: `claim_id`, `study`, `role` (`"supports"` or `"contradicts"`).
  Join it to `$studies` to reach documents and quotes.

- `studies`:

  The rows the claims were drawn from, numbered.

- `dropped`:

  What verification removed, and why.

- `partial`:

  `TRUE` when some studies contributed nothing because their batch was
  cut off at the reply limit, failed, or was not sent for a call or cost
  limit.

- `lost`:

  The study numbers of those studies.

- `unmerged`:

  `TRUE` when claims from several batches could not be reconciled, so
  one finding may appear as more than one claim.

- `hidden`:

  The columns withheld from the model as bibliographic.

- `values`:

  Each extracted value of the studies, one row per study and field:
  `study`, `document`, `field`, `value`, `status` (`"verified"`,
  `"unverified"` or `"not reported"`) and `quote` (the verified quote,
  else the closest one given, else `NA`). Empty for a bare table, which
  carries no quotes.

- `moderators`:

  One row per claim that names a moderator: `claim_id`, `moderator`,
  `declared`, `exploratory`, `n_support` and `n_contradict` (the studies
  on each side that report it), `fisher_p`, `min_p` and `holm_p`. See
  "Moderators" below.

- `declared`:

  The `moderators` named in advance that the model was shown.

- `unverified`:

  The unverified values, listed apart: `study`, `document`, `field`,
  `value`, `quote` and `shown`, whether the prompt showed them
  (`unverified = "include"`).

## What makes a claim checkable

Every study number a claim names is verified against the table, exactly
as a `[study N]` marker in finished prose already is, and against the
batch the claim was drawn from: a claim may only name studies its call
was shown. A number that fails either is dropped and counted rather than
trusted, a claim left with no supporting study is dropped entirely, and
a `moderator` naming a column the model was not shown is cleared: it is
an invented explanation for a real disagreement. So is a moderator that
does not tell the two sides of a contested claim apart by counting: a
column the table does not report for the studies on one side, a value
reported on both sides, or numbers whose ranges overlap. `$dropped`
records all of it, so a claims table that looks thin can be told apart
from a literature that is.

The study numbers are the same ones
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
cites, because both derive them from one function. A claim resting on
study 3 and a sentence citing `[study 3]` point at the same row by
construction.

## Corpora too large for one prompt

The studies are batched, and claims are then reconciled across batches
in one further call that sees only the claim TEXTS. Without it a claim
holding across the whole corpus comes back once per batch with disjoint
support, which reads as several narrow claims instead of one broad one.
The reconcile pass may only group claims that already exist: every claim
it fails to place stays on its own rather than disappearing. When it
cannot run (a call or cost limit, a failed or cut-off reply, a reply
that is not a list of groups, or more claims than fit one prompt), the
claims are kept unmerged, with a warning, and `$unmerged` is `TRUE`.

What the reconcile pass cannot check is MEANING. A merged claim keeps
one member's wording and the union of every member's studies, so if the
model groups two claims that say different things, the studies behind
one are listed as supporting the other's wording. Two such errors are
refused by reading words: findings that point different ways, and claims
naming different populations (adults, children, adolescents, infants,
older people, women, men, students), read from the claim and its scope,
are kept apart whatever the reply grouped, with a warning
(`gr_claims_kept_apart`) and a `note`. A finding is read on three axes:
whether it states no effect ("has no effect on Y", "did not improve Y",
"ineffective"), whether it names a benefit or a harm ("improves",
"harms"), and whether it names a rise or a fall ("raises", "reduces").
Two findings are kept apart when one states no effect and the other one,
or when both speak to the same axis and differ. "Improves depressive
symptoms" and "reduces depressive symptoms" stay together, since a fall
can be a benefit; for the same reason "improves Y" and "reduces Y" are
not told apart. The words are English and the lists short, and a
population outside the list is not recognised, so a merge they do not
catch is still possible. The merged claim takes the wording of the
member most studies support, then the one fewest contradict, then the
first in a fixed order, not the longest, so the result does not depend
on the order of the table. Its `note` names every other wording it
absorbed so that it can be seen, and a group mixing claims of different
`kind` is warned about.

A batch is limited by the reply as well as by the context window,
because the reply names every study it uses: with the default
`max_claim_tokens` a batch holds about 30 studies. A batch whose reply
is cut off, or whose call fails, is reported with the number of studies
it held rather than passed over.

## Direction of effect

A claim's tally is a direction-of-effect count: how many of the studies
it names point its way. Each claim carries the exact sign test of that
count, the binomial probability of a split at least as uneven if each
study were as likely to point either way (`sign_p`, two-sided), and
claims are ranked by it, lowest p first, wherever they are ranked
([`print()`](https://rdrr.io/r/base/print.html), and the sentence budget
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
gives each claim). A two-sided test is as small for a tally against the
claim as for one in its favour (1 of 9 gives 0.039, below 5 of 5 at
0.0625), so a claim that more of its studies contradict than support
ranks after every other claim, the least contradicted of those first.
The number of studies voting was the rank before, which put a contested
3-to-3 claim above an agreed 5-of-5 one. A sign test is weak: with 5
studies or fewer no split, however even or uneven, can reach p \< 0.05,
and [`print()`](https://rdrr.io/r/base/print.html) warns of low power.
Read such a tally as a count of directions, not as evidence of an effect
or of none. This follows SWiM's guidance on vote counting by direction
of effect (Campbell et al. 2020, BMJ 368:l6890) and Boon and Thomson
(2021, Research Synthesis Methods 12:29-33) on direction tallies and
their sign test.

## Moderators

A moderator is kept only when it separates a claim's supporting studies
from its contradicting ones (see "What makes a claim checkable"). Kept,
it is tested. `fisher_p` is Fisher's exact test, two-sided, of the 2 x 2
table of side (supports, contradicts) against which side's values a
study has; `min_p` is the smallest p a table with those margins can
give. Since a kept moderator splits the studies perfectly, the two are
equal: the test says how much a split that clean can show with that few
studies. One study on each side gives p = 1, which is why a 1-vs-1 split
is always "exploratory": it is a coincidence as often as an explanation.
For the moderators named in `moderators`, `holm_p` adjusts `fisher_p`
for their number by Holm's method; an exploratory moderator has none,
since the number of columns the model looked through is not known. The
writing prompt marks an exploratory moderator as such.

These are between-study comparisons of direction, not tests of an
interaction on effect sizes. Assess each moderator you rely on against
the ICEMAN items for effect modification (Schandelmaier et al. 2020,
CMAJ 192:E901-E906); harnessr scores none of them, and lists them, with
what it reports on each, in the audit report:

- Is the effect modification based on comparison within studies rather
  than between them? (Here it is between studies.)

- Was the moderator specified before the analysis? (`declared`.)

- Was the direction of the effect modification hypothesised in advance,
  and correctly?

- Does a test for interaction suggest that chance is an unlikely
  explanation? (`fisher_p` tests directions only.)

- Was only a small number of moderators tested, or was the number
  allowed for? (`holm_p`, over the declared ones.)

- For a continuous moderator, were arbitrary cut points avoided?

- Is the effect modification consistent across related outcomes?

## See also

[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
to derive sections from these claims,
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
to write from them,
[`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
for what they do not cover,
[`gr_protocols()`](https://elkronos.github.io/harnessr/reference/gr_protocols.md)
for the `claims` schema they want as input

## Examples

``` r
tab <- data.frame(
  document = c("a.pdf", "b.pdf"), status = "ok", duplicate_of = NA_character_,
  n_filled = 2L, n_unverified = 0L, conflicts = NA_character_,
  design = c("randomised trial", "cross-sectional"),
  finding = c("supports", "contradicts"), stringsAsFactors = FALSE)

cl <- hr_mock_client(function(messages, params) paste0(
  '{"claims":[{"claim":"The effect appears in trials but not in surveys.",',
  '"kind":"finding","supported_by":[1],"contradicted_by":[2],',
  '"moderator":"design","scope":"one trial, one survey"}]}'))

cm <- gr_claims(tab, question = "Does it work?", client = cl)
cm$claims[, c("claim", "moderator", "n_support", "n_contradict")]
#>                                              claim moderator n_support
#> 1 The effect appears in trials but not in surveys.    design         1
#>   n_contradict
#> 1            1
cm$support
#>   claim_id study        role
#> 1        1     1    supports
#> 2        1     2 contradicts
```
