# Write a review from an extraction table

The last stage. Takes what
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
found and writes it up section by section, against an outline fixed in
advance, with every section citing the rows it rests on.

## Usage

``` r
gr_synthesise(
  extraction,
  protocol = NULL,
  outline = NULL,
  question = NULL,
  client = NULL,
  model = NULL,
  max_section_tokens = 1200L,
  temperature = NULL,
  include_unclear = FALSE,
  cite_style = c("auto", "marker", "author-year", "numeric"),
  bib = NULL,
  style = NULL,
  coherence = FALSE,
  references = TRUE,
  claims = NULL,
  gaps = NULL,
  trace = NULL,
  effort = NULL,
  coherence_rounds = 1L,
  figure_bands = c(about = 0.1, over = 0.25, under = 0.25),
  prominence = c(top = 1/3, middle = 1/3),
  study_weights = NULL,
  revision_check = c("lexicon", "judge")
)
```

## Arguments

- extraction:

  A `gr_extraction` from
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
  or a data frame shaped like its `$table`.

- protocol:

  A
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md);
  its `outline` and `question` are used unless you give them directly.

- outline:

  The sections, as a named character vector: names are headings, values
  say what that section has to cover. As
  [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md).
  A heading with a blank brief is dropped, unless the claim assignment
  (see `claims`) places claims in it: then its heading is its brief.

- question:

  The review question, for framing.

- client:

  A `gr_client`.

- model, max_section_tokens, temperature:

  Overrides for the writing calls.

- include_unclear:

  Write from rows whose extraction was incomplete. Off by default: a row
  with nothing in it contributes nothing but its own absence, and the
  count of skipped rows is reported either way.

- cite_style:

  How citations appear in the finished prose. `"auto"` (the default)
  names the studies when the table can name all of them and uses markers
  when it cannot. `"author-year"` asks for names and warns if they
  cannot be produced; `"numeric"` gives `(1, 2)`; `"marker"` leaves
  `[study 1]` as written.

  The model always writes `[study N]`, whatever this is set to, and the
  rendering happens afterwards from the table. That is deliberate: a
  marker can be checked exactly against the rows that exist, whereas
  verifying an author-year string would mean matching a name the model
  wrote against a name in the table, and near-misses (Smith for Smyth,
  2019 for 2018) are both the errors that matter and the ones fuzzy
  matching forgives. A rendered citation is therefore a fact about the
  extraction rather than something the model asserted.
  `$sections$text_marked` and `$text_marked` keep the marker form so the
  check can be re-run on the published prose:
  [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  runs it, and renders the citations again, on an edited copy.

- bib:

  Which columns carry bibliographic identity, as a named list of
  `citation`, `authors`, `year`, `title`, `venue`, `doi`. Omitted, the
  conventional names are looked for, which is why
  `gr_protocols("bibliography")` works without configuration: `citation`
  (or `cite`, `citation_key`, `cite_key`), `authors` (or `author`),
  `year`, `title`, `venue` (or `journal`) and `doi`, in any case. Names
  that are as often findings (`date`, `source`, `url`, `published`,
  `publication`) are not taken for bibliographic ones unless named here.
  A column found this way is withheld from the writing prompts and used
  for the citations and references; give a role as `NA` to keep a column
  of that name as a finding (`bib = list(venue = NA)`). The most
  reliable route is a `citation` field asked for during extraction:
  parsing an arbitrary author list is a heuristic, and where it cannot
  be done confidently the run falls back to markers rather than printing
  a name that may be wrong.

  Pass the same `bib` to
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  and
  [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md).
  The claims model is shown every column its own `bib` did not withhold,
  so a claim, and the moderator it names, can carry a column this
  write-up withholds, and the claims reach the writing prompts as they
  are. With `claims` drawn under a `bib` that withheld less than this
  one, the run warns (`gr_claims_bib_mismatch`) and names the columns.

- style:

  A register instruction appended to the writing prompts, such as
  `"formal academic; hedge claims; past tense for findings"`. It governs
  how sections are written, never what they may say: the rules about
  citing every claim and inventing nothing hold whatever voice is asked
  for.

- coherence:

  Revision passes over the finished draft: `TRUE` for all three, `FALSE`
  for none, or any of `"structure"` (reorder and merge), `"cut"` (remove
  repetition) and `"register"` (polish sentences) by name. Each pass is
  forbidden from doing the others' job, and each is discarded (with
  `$draft` kept, and the reason in `$coherence`) if it changed which
  studies are cited, wrote a citation the check cannot read, cited a
  study more often than the draft did, or took the citation marker off a
  claim sentence that stays (each a `gr_coherence_rejected` warning); if
  it arrived truncated (`gr_coherence_truncated`); if it strengthened a
  claim (`gr_revision_escalated`); or if it introduced a figure the
  draft did not have (`gr_revision_new_figure`): one the draft gives in
  no form, so a figure changed or rounded counts, and 0.61 written as
  .61 does not. Off by default: each is a call, and each is a chance for
  a model to touch finished prose.

  The `"cut"` pass is also discarded when the cut pass did not shorten
  the review (`gr_revision_uncut`): its revision must have strictly
  fewer words of prose than the text it was given, headings and citation
  markers left out of the count. Fewer by any amount will do, since how
  much a draft can lose depends on how much it repeats itself. Only the
  cut is held to a length: a polish that keeps every sentence can remove
  half the words of padded prose, so no bound on the other two passes
  would tell their job from cutting. Their counts are in `$coherence`
  all the same.

  The check that refuses a revision which strengthens a claim reads
  English hedges and boosters, so a draft it judges not to be in English
  is not revised at all: a warning (`gr_revision_unguarded`) says so, no
  pass is sent, and every pass is reported with `ran = FALSE` and that
  reason. The judgment counts letters outside the Latin alphabet and
  common function words, so a very short draft can be misjudged: an
  English one naming an accented author left unrevised, or a sentence or
  two of a language that has no accents taken for English.

- references:

  Append a `## References` section built from the studies the finished
  text actually cites. Alphabetical under `"author-year"`, numbered by
  study otherwise: the list is labelled by whatever the prose uses to
  point into it. The alphabetical order follows a fixed rule rather than
  the session's locale, so it is the same on every machine: it ignores
  case, accents and apostrophes, filing an accented name with its base
  letter. Two papers by the same authors in the same year are lettered
  (2019a, 2019b) in title order; a key that does not end in a year is
  lettered after a hyphen ("in press-a"). Under `"author-year"`, an
  entry whose key came from a `citation` field leads with that key, so
  the prose can be followed to it.

- claims:

  A
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  result. With it each section argues that section's claims and sees
  only the studies those claims rest on, rather than being handed every
  study and writing a paragraph per row. Needs an `outline` from
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
  which carries the assignment, and it must be an outline derived from
  these same claims: the run stops (`gr_claims_mismatch`) when the
  outline says it came from other claims, and (`gr_claims_unplaced`)
  when the assignment places a claim in a heading the outline does not
  have, such as a heading renamed after
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md).
  Rename it in `attr(outline, "claims")$section` too. A section given no
  claims is written from the rows, as without `claims`, except the
  closing section, which is written from `gaps` alone and is left out
  when there are none. A section too large for one prompt is written a
  few claims at a time, each batch sent only its claims' studies, and
  merged.

- gaps:

  A
  [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
  result, or lines of text. Given to the closing section
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  named, `attr(outline, "closing")`, with an instruction to state those
  gaps and no others. When the outline has no such section they reach
  none, and a warning (`gr_gaps_unused`) says so. They are cut, at a
  line, to a quarter of the model's input room, with a warning
  (`gr_gaps_truncated`), and the closing section is then partial.

- trace:

  An
  [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  to fold this write-up's accounting into, as in
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).
  It is a parent, not this stage's counter: `$trace` is still the
  write-up's own, so `hr_options(max_calls =)` bounds the write-up
  rather than being spent by the screening that came before it.

- effort:

  Reasoning effort, or `NULL` (the default) to send none: one string, or
  a character vector named by stage, as `effort` in
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).
  The calls here are labelled `synthesise.section`, `synthesise.batch`,
  `synthesise.merge` and, with `coherence`,
  `synthesise.revise.structure`, `.cut` and `.register`;
  `c(synthesise = "medium", "synthesise.section" = "high")` writes the
  sections at high and does the rest at medium. The reasoning counts
  against each call's reply limit (`max_section_tokens` for a section),
  and a section cut off at it is reported as one.

- coherence_rounds:

  How many rounds each `coherence` pass may run: each round revises the
  text the round before it kept, and the pass stops at the first round
  that is discarded or changes nothing. Every round is checked as a
  single pass is, and is a request. A whole number in \[1, 10\]; default
  1, one round per pass, as before the setting existed. Untested:
  paper-orchestra runs up to 3 refinement rounds, with no recorded
  evidence for that number, and nothing has measured more than one round
  here.

- figure_bands:

  How near a value a qualified figure must be to count as found in the
  check of figures (see "Figures"): a named numeric vector of `about`
  (the share either way that "about 1,200" covers), `over` (the share
  above that "more than 1,000" covers) and `under` (the share below that
  "fewer than 1,000" covers). Names left out keep their defaults,
  `c(about = 0.10, over = 0.25, under = 0.25)`, set when the check was
  written and untested. Each is in \[0, 1\]. The check sends nothing, so
  this changes what `$figures` reports, never a request.

- prominence:

  How much of the writing prompt's sentence budget the claims of a
  section get, by rank: `c(top = , middle = )`, the shares of a
  section's claims (ranked by the sign test of their direction tally,
  lowest p first, with a claim more of whose studies contradict it than
  support it last, then by the weight of the studies behind them; see
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  "Direction of effect") asked for "two or three sentences" and "one or
  two sentences"; the rest get "one sentence", and a section of three
  claims or fewer gives each "two or three". Default
  `c(top = 1/3, middle = 1/3)`, thirds, set when claims were added and
  untested. Each share is in \[0, 1\] and the two add up to at most 1.
  At least one claim is always in the top tier. Used only with `claims`.

- study_weights:

  How much each study counts when claims are ranked, among claims whose
  sign tests tie (and so which tier each claim gets, see `prominence`):
  `NULL` (the default) for the package's weight,
  `0.5 + 0.5 * size + 0.5 * filled`, where `size` is `log1p(n)` over its
  largest value (the mean of the known ones when `n` is missing) and
  `filled` the share of a row's filled cells whose quotations verified
  (0.5 when unknown). That formula is untested, and is not a quality
  score. Or a function of the studies table (the extraction's included
  rows, with a `study` column of ids) returning one non-negative number
  per row. Used only with `claims`.

- revision_check:

  What checks a kept revision pass beyond the citation, figure and
  length checks. `"lexicon"` (the default) is the word-counting guard
  against a stronger claim, as before. `"judge"` adds, behind it, a
  model judge
  ([`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
  on `model`, its requests held to the run's limits) that grades each
  sentence the revision changed against the draft sentences it came from
  (those citing the same study, else the two sharing most of its words):
  `"holds"`, `"stronger"` (it claims more, as "is associated with"
  become "reduces") or `"not_entailed"`. It costs one request per
  changed sentence. The judge is advisory: a flagged sentence is warned
  about (`gr_revision_flagged`), counted in the `flagged` column of
  `$coherence` and listed in `$revision_flags`, and the revision is kept
  as it was. The judge is not validated against people's labels (see
  [`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)),
  so its flags are for a person to read. Untested.

## Value

An object of class `gr_synthesis`:

- `text`:

  The whole write-up, as markdown, citations rendered and the reference
  list appended.

- `text_marked`:

  The same document with `[study N]` markers intact: what the citation
  check ran on.

- `draft`:

  The write-up before the coherence pass, for comparison.

- `references`:

  The reference list, or `NULL`.

- `cite_style`:

  The style actually used, which is not always the one asked for.

- `coherence`:

  One row per round of each revision pass, or `NULL` if none ran: `pass`
  (which of `"structure"`, `"cut"`, `"register"`), `round` (1 unless
  `coherence_rounds` is more), `ran`, `kept`, `lost` and `added`
  (citations, if the revision changed them), `reason` for anything
  discarded, and `words_before` and `words_after` (integer: words of
  prose, headings and citation markers left out, in the text the pass
  was given and in its revision; `NA` for a pass that was not sent, or
  was refused by a check made before the length check, which comes
  last).

- `revision_flags`:

  Under `revision_check = "judge"` only: one row per sentence a kept
  revision changed, with `pass`, `round`, `sentence`, `verdict` and the
  judge's `reason`.

- `unrendered`:

  Studies a section cited honestly that `text` still shows as
  `[study N]` somewhere, because a kept revision moved or reworded a
  citation of the same study that another section made without being
  given it, and the two could no longer be told apart. Leaving both is
  the safe side of that doubt; `$draft` renders each section's own
  citations. Empty when nothing was in doubt.

- `sections`:

  One row per section: `section`, `brief`, `text`, `n_cited`,
  `n_unknown` (citations to a row that does not exist), `n_unsupplied`
  (citations to a study that exists but was not given to the call that
  wrote them: with `claims`, a study not behind that section's claims;
  for a section written in batches, a study outside that batch, or one
  the merge of the batch drafts cited that no draft did. They are left
  as markers and kept out of the reference list, with one exception:
  once batch drafts are merged, a study that another batch of the same
  section was given and cited cannot be told apart, so it is rendered,
  and still counted), `n_unparsed` (brackets that open like a citation,
  such as `[studies 1 to 7]`, but cannot be read as one, so the studies
  they name were not checked), `n_truncated` (replies, including batch
  drafts and merges, that stopped at the reply limit), `n_claims` and
  `claims_missed` (the claims it was given, and those it did not write
  up), `lost_batches` (batches of studies whose call failed),
  `capped_batches` (batches not sent because the run reached its call or
  cost ceiling), `merge_failed` (its batch drafts could not be merged,
  so it is those drafts joined end to end), and `partial`. A section is
  partial when any of those counts is non-zero (`n_cited` and `n_claims`
  aside), when it came back empty, when a batch of studies was lost or
  not read, when its batch drafts could not be merged or one had to be
  cut to fit the merge, when (without `claims`) none of the studies of a
  batch it was drafted from is cited in it, when it could not be sent at
  all (its brief and gaps leave no room in the window), when the gaps
  given to it were cut, or, with `claims`, when it did not write up a
  claim it was given. Last, `n_unbacked`: the figures in the section
  that are not in the rows their sentence cites (see "Figures" below).
  It does not make a section partial, which says that a citation cannot
  be trusted, and a figure's citation may be sound.

- `citations`:

  Every citation, resolved to the row it points at, in long form:
  `section`, `study`, `document`, `document_id`.

- `figures`:

  Every figure in a sentence of the write-up, checked against the rows
  it cites: `stage` (`"draft"` for the sections as written, `"final"`
  for the revised text when a kept revision pass changed it), `section`
  (the heading it stands under), `sentence`, `number` (as written),
  `studies` (the studies the sentence cites, comma-joined, or NA),
  `backed`, `basis`, what it was found in (NA when it was not), `field`,
  the extracted field it reports, as `"n (study 2)"`, when a row's own
  value of that field is the figure, `pool`, how many distinct values
  the rows it was checked against hold, and `chance`, the chance of a
  match among that many by coincidence. See "Figures" below.

- `sentences`:

  Every sentence of the text as published, linked to the records it
  rests on: `section`, `sentence`, `studies` (the studies it cites,
  comma-joined, or NA), `verified` (those of them that are verified
  records: studies with at least one value whose quote verified),
  `linked` (`TRUE` when it cites at least one verified record; `NA` when
  the table cannot say) and `flag`: `"cites no study"`,
  `"cites no verified record"`, or NA. A flag marks nothing partial; it
  says where to look. With a bare table, a study is a verified record
  when `n_filled` is above `n_unverified`.

- `uncited`:

  The studies the text as published cites nowhere, from the final cited
  set (the one the reference list follows): `study`, `document`,
  `document_id` and `shown`, whether any section's prompt held the
  study. A study shown and left uncited is one the writer passed over;
  one not shown was never in front of it. A count, not a quota: nothing
  asks that every study be cited.

- `contradictions`:

  With `claims`, sentences that state a claim and cite a study on its
  contradicting side with no hedge ("may", "suggest") and no word of
  contrast ("however", "mixed"): `section`, `sentence`, `claim_id`,
  `study`. A sentence states a claim when it stands in a section the
  claim was given (any claim, under a heading the write-up did not
  have), points in the claim's direction in one of its clauses and
  shares at least two content words with it. Found by counting words,
  with no model; a flag says where to look, and marks nothing partial.

- `section_studies`:

  The studies each section was shown: `section`, `study`.
  [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  reads it.

- `closing`,`style`,`figure_bands`,`bib_columns`:

  The closing section, the `style` and `figure_bands` given, and the
  bibliographic columns the run used, which
  [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  reads.

- `values`:

  Each extracted value of the studies with its check and quote, as
  `$values` of
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md).
  The writing prompts show each value with these, the unverified ones
  marked as such.

- `studies`:

  The rows that were written from, with the `study` number each was
  cited by.

- `claims`:

  The
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  result written from, or `NULL`. When its `$lost` names studies whose
  claims batch contributed nothing, the run warns (`gr_claims_partial`),
  and print() and the audit report say the review was written without
  them.

- `claim_sections`:

  With `claims`, which section each claim was given to: a data frame of
  `section` and `claim_id`, the outline's assignment. `NULL` without
  `claims`.

- `outline_alternative`:

  Present only when the outline is one of several
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  compared (`alternatives` above 1): which one it was, as `alternative`,
  `of` (how many were asked for), `distinct` (how many came back
  distinct) and `distance` from the first proposal. The trace's meta
  records `outline_alternative` and `outline_of` too.

- `outline_trace`:

  Present only when `outline` came from
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md):
  the trace of the calls that derived it, which this stage's `trace`
  does not include.

- `trace`:

  As
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).

## Which rows are used

Rows that were never read (`status` `"failed"` or `"skipped"`) are left
out, and so are duplicates: a study counted twice is the error this
whole pipeline exists to avoid, and
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
has already marked them. The number left out is reported by
[`print()`](https://rdrr.io/r/base/print.html) and is in `$skipped`.

## What it costs

One call per section when the table fits one prompt, which is the usual
case: a hundred rows of a ten-field schema is a few thousand tokens. A
table too large for one prompt is written in batches and merged, so a
section costs batches + merges instead. Either way the cost is per
*section*, not per document: the expensive reading has already happened.

The merge folds every batch draft into one reply of at most
`max_section_tokens`, the same limit each draft had, so a section
drafted from a very large table covers only what that one reply can
hold. Nothing checks that it cites every study (a section need not), but
without `claims` a batch none of whose studies the merged section cites
is reported (`gr_synth_batch_dropped`) and marks it partial. Raise
`max_section_tokens`, or divide the table between narrower sections.

## Figures

The citation check says which rows a sentence rests on, not what it says
they found, and the numbers are what a reader copies out of a review. So
every number in every sentence is looked for in what the writer was
shown for that sentence: the rows it cites, as the writing prompt showed
them; the question, the section's heading and brief, `style`, and the
gaps a closing section was given; and with `claims`, the claims given to
the section that rest on a cited study. This runs on the draft, and
again on the revised text when a kept revision pass changed it; it sends
nothing, so it is always on, and it changes no request.

Each figure found in a row is linked to the field it reports where it
can: `field` names the field, and the study, whose own value is the
figure. Each figure also carries `pool`, how many distinct values the
rows it was checked against hold, and `chance`, the chance that one of
them matches it by coincidence: `1 - (1 - m / N)^pool`, with `N` the
count of numbers with as many significant digits as the figure (90 for
"63") and `m` the forms it is compared in (2 for "63%"). That takes the
values to be spread evenly, so it is a yardstick, not a measured
probability. A sentence that cites nothing is checked against every row
its section was shown, where matches by chance are common, so a figure
found there counts only when its `chance` is below 0.05 or the sentence
names, for that figure, the field it matched ("n = 236" for a field `n`
of 236; a one-letter field just before the figure, a longer name in the
same clause, so "(n = 410), 57 dropped out" names `n` for 410 and not
for 57). An uncited "63%" among 40 numbers, with a chance of about 0.59,
is unbacked; and a figure qualified by "about" or "more than" counts as
near a row's value only in a sentence that cites the row.

The check is diagnostic only. `backed` marks no section partial, stops
nothing, and is not a measure of accuracy: no benchmark has validated it
against a person checking the figures.

A figure counts as found in any form a faithful copy may give it: `.61`
for 0.61, `45.20` for 45.2, `1204` for 1,204, `12 450` for 12,450
(grouped by a space, where that is the row's figure), a minus sign or
none, either side of a dash in a range, `45.2 million` for 45,200,000,
`4 x 10^-4` for 0.0004, `100,000` for a numeric field shown as `1e+05`,
`45%` for 0.45, `12` for "twelve", and rounded to the places it is
written to (0.61 or 0.6 for 0.613, never 0.62). A row's percentage read
as a proportion, or its scaled figure at full value, must match exactly:
rounded as well, a pooled estimate no study reported matched a row's
unrelated percentage. A figure is also allowed when it is the total of a
numeric field over the rows the sentence cites; worked out from two
other figures of the same sentence ("120 of 1,020 (11.8%)"), or from a
ratio in it read as a change from 1 ("HR 0.78, a 22% lower hazard"); a
difference in points between two figures of one field of a cited row, or
two percentages of one cited row; a year a cited row carries in any
column; the number of studies the sentence cites, its section was shown
or the review was written from, or how many of those rows share a
field's value ("10 were randomised trials"); or, after "about", "more
than", "fewer than" and their like, within a tenth (about) or a quarter
(a bound) of a value it could have come from (`figure_bands` changes
these shares). Not read as figures: a citation's ids, written bare as
well ("studies 12 to 15"), a whole number below ten that is not a
percentage or scaled (a review writes "2 of the trials" as it likes), a
number joined to a name ("COVID-19", "IL-6"), an ordinal, a decade
("1990s", "in their 60s"), an interval's level (`95% CI`), a
significance threshold (`p < .001`, "p value below 0.05") and a
significance level ("at the 5% level"). Numbers written in words are not
checked.

A figure found nowhere is reported in `$figures` and counted in
`$sections$n_unbacked`, and the run warns (`gr_synth_unbacked_figures`)
about the text as published. It is arithmetic the sentence does not
show, a pooled estimate no study reported, or a number the writer made
up, and nothing here can tell which. Found means copied, not right: a
figure the cited row carries can still be the wrong one for the
sentence. The section is not marked partial, because `partial` is about
whether its citations can be trusted, and those are checked apart.

## See also

[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
[`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md),
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
[`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
to check and render an edited `text_marked` again

## Examples

``` r
fields <- gr_fields(design = "The study design",
                    n = gr_field("Participants", type = "integer"))
cl <- hr_mock_client(function(messages, params) {
  seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
                collapse = " ")
  if (grepl("<studies>", seen, fixed = TRUE)) "One randomised trial of 120 people [study 1]."
  else '{"design":"randomised trial","n":120,
         "design__quote":"We ran a randomised trial.",
         "n__quote":"We enrolled 120 people."}'
})

f <- tempfile(fileext = ".txt")
writeLines("We ran a randomised trial. We enrolled 120 people.", f)
x <- gr_extract(f, fields, client = cl)
#> [1/1] file1bef2a93bf34.txt
#> Extracting 'file1bef2a93bf34.txt' with the 'txt' extractor.
#> Ingested 1 block(s), ~18 tokens (0 chars removed by cleaning).
#> Segmenting with 'structural' (cap 900 tokens, overlap 90).
#> Reading with 'extract' (all|N+conflicts|none) over 1 chunk(s).

s <- gr_synthesise(x, question = "Does it work?",
                   outline = c("Included studies" = "How many, of what design"),
                   client = cl)
#> [1/1] Included studies
s$sections[, c("section", "n_cited", "n_unknown", "n_unbacked")]
#>            section n_cited n_unknown n_unbacked
#> 1 Included studies       1         0          0
# The 120 in the section, found in the row it cites.
s$figures[, c("number", "studies", "backed", "basis")]
#>   number studies backed     basis
#> 1    120       1   TRUE cited row
```
