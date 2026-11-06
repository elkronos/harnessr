# Measure the screener against a hand-screened sample

Compares
[`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md)'s
decisions with a person's on the same documents, and reports what that
sample supports: how much of the eligible literature the screener kept,
how much of the irrelevant literature it removed, and how much reading
it saved. Each comes with an interval, and each is refused when the
sample is too small to say.

## Usage

``` r
gr_calibrate(
  screening,
  reference,
  positive = "include",
  min_positives = 10L,
  of = NULL
)
```

## Arguments

- screening:

  A `gr_screening` from
  [`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md),
  or a data frame shaped like its `$table`, for instance read back from
  a CSV. Its `decision` must be `"include"`, `"exclude"`, `"unclear"` or
  empty (never read), in any case; a row whose `status` says it was not
  read counts as never read.

- reference:

  The completed frame from
  [`gr_reference()`](https://elkronos.github.io/readgpt/reference/gr_reference.md),
  a path to the filled-in CSV, or any data frame with `document` and
  `human_decision`.

- positive:

  Which human decision counts as eligible: `"include"` or `"exclude"`.

- min_positives:

  For an `"all"` sample: below this many eligible studies the
  sensitivity estimate is reported but marked inadequate. A sample of
  one stratum is judged by its interval instead; see "What a small
  sample cannot do".

- of:

  Which part of the screening run the reference was drawn from:
  `"excluded"`, `"kept"` or `"all"`; anything else is an error. Normally
  recovered from the file
  [`gr_reference()`](https://elkronos.github.io/readgpt/reference/gr_reference.md)
  wrote; give it explicitly for a reference built by hand. Given over a
  file that records a different frame, it wins with a warning, and the
  file's frame size is not used.

## Value

An object of class `gr_calibration`:

- `counts`:

  The confusion matrix, as kept/excluded by eligible/not.

- `metrics`:

  One row per statistic: `estimate`, `lower`, `upper`, `n`.

- `kappa`:

  Cohen's kappa on kept against excluded; `NA` for a sample of one
  stratum.

- `agreement`:

  `kept` (the primary table) and `strict` (include against the rest),
  each a list of `table`, `n`, `stats` (one row per statistic:
  `statistic`, `estimate`, `lower`, `upper`) and `paradox`. `NULL` for a
  sample of one stratum.

- `kappa_legacy`:

  Deprecated: the 0.6.0 kappa on the screener's three labels against the
  person's two. Removed in the next release.

- `decisions`:

  The 3x2 counts: the screener's include, unclear and exclude by the
  person's eligible and not.

- `missed`:

  The eligible studies the screener excluded: the rows themselves,
  because a list of the misses says more than a rate.

- `disagreements`:

  Every row where the two differ, in either direction.

- `adequate`:

  Whether the sample supports a claim from its frame's headline rate:
  sensitivity in an `"all"` sample, the frame's own rate in an
  `"excluded"` or `"kept"` one.

- `adequacy`:

  How that was judged: `rule` (`"positives"`, `"interval"` or
  `"whole frame"`), `bar`, `width`, and `note`, a sentence saying why
  the sample fell short (`NA` when it did not).

- `frame`:

  Which rows the sample was drawn from, and how many.

## Two sensitivities, and the gap between them

`"unclear"` is a deferral, not a miss. A record the screener could not
settle goes to a person, so it is not lost, and counting it as a failure
would punish the screener for the one behaviour that makes it safe.

So two figures are reported. **Sensitivity as deployed** asks what
fraction of the eligible studies survived: kept, whether by `"include"`
or by `"unclear"`. That is the number that matters, because it is the
one where a shortfall is permanent. **Strict sensitivity** asks what
fraction were actively included. The gap between them is the reading a
person still has to do, and reporting only the first would flatter a
screener that defers everything.

## Why accuracy is not reported

Inclusion rates run at a few per cent, so a screener that excluded every
record would score around 95% accurate and find nothing.
Chance-corrected agreement is reported instead, and never as one number.

## Agreement, on the decision that matters

The primary agreement table is the one sensitivity uses: kept
(`"include"` or `"unclear"`) against excluded, by the person's eligible
against not. An `"unclear"` on an eligible record is agreement there,
since the record was kept. The secondary table is strict: `"include"`
against everything else.

Each table reports Cohen's kappa beside the statistics that say whether
it can be read: the prevalence index (PI) and bias index (BI) of Byrt et
al. (1993), the prevalence- and bias-adjusted kappa (PABAK, 2 po - 1)
and Gwet's AC1, with intervals, and the class-wise sensitivity,
specificity, PPV and NPV. At a few eligible records in a hundred, kappa
moves with the marginals as much as with agreement, and can sit near
zero where the two raters agree on almost every record;
`$agreement$kept$paradox` is `TRUE` when abs(PI) is above 0.8, a
heuristic threshold that marks such a table. AC1 has the opposite
weakness, a value near 1 from records both raters left out, so it is not
read alone either.

The kappa interval is a percentile bootstrap that resamples documents, B
= 2000, under a fixed seed so the same sample gives the same interval
(`$agreement$kept$bootstrap` holds B and the seed; the session's random
stream is left as it was). The AC1 interval uses the variance of Gwet
(2008), as the irrCAC package does, with a t quantile on n - 1 degrees
of freedom. The PABAK interval is the Wilson interval on the observed
agreement, mapped onto the same scale. Where the two raters agree on
every record, disagree on every record, or the sample has fewer than 10
records, the kappa and AC1 intervals would be a point or close to one,
so they are left empty and `$agreement$kept$note` says why.

0.6.0 computed kappa on the screener's three labels against the person's
two, so every `"unclear"` counted as a disagreement. That figure is kept
as `$kappa_legacy` for this release only, so a number already quoted can
be traced; it is not the screener's agreement with a person.

The rate of `"unclear"` decisions is the metric
`"deferred to a person"`, with its interval, and the 3x2 counts behind
both tables are in `$decisions`.

A decision a person settled with
[`gr_resolve()`](https://elkronos.github.io/readgpt/reference/gr_resolve.md)
is not the screener's, so the comparison uses the screener's own
decision, from `screener_decision`, wherever the table has one.

## What a small sample cannot do

Sensitivity is estimated from the eligible studies in the sample and
from nothing else. Twelve hand-screened records containing two eligible
studies estimate it from two observations, and "1.00" from two
observations is not a finding. The intervals are Wilson score intervals,
which stay sensible at zero and one where the textbook interval
collapses to a point, and `$adequate` says whether there was enough to
support a claim at all.

What "enough" means depends on the frame, because what the headline rate
rests on does. In an `"all"` sample it is sensitivity, estimated from
the eligible studies alone, so the sample needs `min_positives` of them.
In an `"excluded"` or `"kept"` sample the headline rate ("eligible among
the excluded", "eligible among those kept") is taken over every row
sampled, so a sample of 500 clean exclusions is a good one, not one
resting on no observations. There the sample is adequate when that
rate's interval is at most 10 percentage points wide, or when every
record in the stratum was judged (nothing is left to sample, and the
rate is a count for this run). The bar is a floor, not a verdict: 10
points is wide for an omission rate near zero across a large pile of
exclusions, and the projected count of lost studies, printed with its
interval, is the figure to judge that by. `$adequacy$note` says in a
sentence why a sample fell short.

## One row per document

The reference is matched to the screening by document name, compared as
UTF-8 whatever the session's locale, and by `document_id` for a row
whose name still does not match. A document judged twice (two reviewers'
sheets stacked, say) is counted once when the copies agree, with a
warning, and is refused when they disagree: reconcile dual screening
into one consensus decision per document first.

## See also

[`gr_reference()`](https://elkronos.github.io/readgpt/reference/gr_reference.md),
[`gr_screen()`](https://elkronos.github.io/readgpt/reference/gr_screen.md),
[`gr_audit_report()`](https://elkronos.github.io/readgpt/reference/gr_audit_report.md)

Other corpus functions:
[`gr_inventory()`](https://elkronos.github.io/readgpt/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/readgpt/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/readgpt/reference/gr_reference.md),
[`gr_resolve()`](https://elkronos.github.io/readgpt/reference/gr_resolve.md),
[`gr_search()`](https://elkronos.github.io/readgpt/reference/gr_search.md)

## Examples

``` r
tab <- data.frame(document = paste0("d", 1:8, ".pdf"),
                  decision = c("include", "include", "unclear", "exclude",
                               "exclude", "exclude", "include", "exclude"),
                  stringsAsFactors = FALSE)
ref <- data.frame(document = paste0("d", 1:8, ".pdf"),
                  human_decision = c("include", "exclude", "include", "exclude",
                                     "exclude", "include", "include", "exclude"),
                  stringsAsFactors = FALSE)
gr_calibrate(structure(list(table = tab), class = "gr_screening"), ref)
#> Warning: This reference does not say which part of the screening run it came from, so the figures below assume a sample of EVERYTHING screened. If it is a sample of one stratum (the exclusions, say), sensitivity and specificity are artifacts of that frame rather than facts about the screener. Pass `of = "excluded"`, `"kept"` or `"all"` to say which.
#> <gr_calibration> 8 hand-screened row(s), 4 eligible
#>   sampled from: unknown (NA of 8 screened)
#>   sensitivity (as deployed)       75.0%  [30.1%, 95.4%]  n=4
#>   sensitivity (strict include)    50.0%  [15.0%, 85.0%]  n=4
#>   specificity                     75.0%  [30.1%, 95.4%]  n=4
#>   deferred to a person            12.5%  [2.2%, 47.1%]  n=8
#>   reading avoided                 50.0%  [21.5%, 78.5%]  n=8
#>   screener    eligible  not eligible
#>   include            2             1
#>   unclear            1             0
#>   exclude            1             3
#>   agreement, kept (include + unclear) vs excluded:
#>     kappa     0.50  [--, --]
#>     PABAK     0.50  [-0.18, 0.86]
#>     AC1       0.50  [--, --]
#>     PI 0.00, BI 0.00
#>     (no kappa or AC1 interval: Only 8 record(s); the kappa and AC1 intervals need at least 10.)
#>   agreement, strict include vs the rest:
#>     kappa     0.25  [--, --]
#>     PABAK     0.25  [-0.39, 0.73]
#>     AC1       0.26  [--, --]
#>     PI -0.12, BI -0.12
#>     (no kappa or AC1 interval: Only 8 record(s); the kappa and AC1 intervals need at least 10.)
#>   ! 1 eligible study was excluded by the screener:
#>       d6.pdf
#>   ! only 4 eligible studies in the sample. Every rate above rests on
#>     those 4 observations, which is why the intervals are as wide as they are.
#>     Hand-screen more before quoting a figure.
```
