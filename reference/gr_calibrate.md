# Measure the screener against a hand-screened sample

Compares
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)'s
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
  of = NULL,
  recall_target = 0.95,
  conf = 0.95,
  max_lost = NULL
)
```

## Arguments

- screening:

  A `gr_screening` from
  [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
  or a data frame shaped like its `$table`, for instance read back from
  a CSV. Its `decision` must be `"include"`, `"exclude"`, `"unclear"` or
  empty (never read), in any case; a row whose `status` says it was not
  read counts as never read.

- reference:

  The completed frame from
  [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
  a path to the filled-in CSV, or any data frame with `document` and
  `human_decision` (or one `human_decision_<reviewer>` column per
  reviewer; see "Several reviewers").

- positive:

  Which human decision counts as eligible: `"include"` or `"exclude"`.

- min_positives:

  For an `"all"` sample: below this many eligible studies the
  sensitivity estimate is reported but marked inadequate. A sample of
  one stratum is judged by its interval instead; see "What a small
  sample cannot do".

- of:

  Which part of the screening run the reference was drawn from:
  `"excluded"`, `"kept"`, `"all"` or `"stacked"`; anything else is an
  error. `"stacked"` also reads a kept sheet and an excluded sheet
  stacked with [`rbind()`](https://rdrr.io/r/base/cbind.html) as one
  stratified reference. Normally recovered from the file
  [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
  wrote; give it explicitly for a reference built by hand. Given over a
  file that records a different frame, it wins with a warning, and the
  file's frame size is not used.

- recall_target:

  The recall the screener should reach, strictly between 0 and 1.

- conf:

  Confidence level of the recall and loss bounds.

- max_lost:

  Optional: the most eligible records the screener may have excluded.
  When given, an upper bound on records lost at or below it also meets
  the target.

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

- `recall`:

  Recall: `estimate`, `lower` and `upper` (two-sided at `conf`), `bound`
  (the one-sided lower bound), `method`, `conf`, `n` (eligible records
  in the sample) and `note`. `NA` where the frame cannot estimate it.

- `lost`:

  M, the projected number of eligible records excluded: `estimate`,
  `lower`, `upper`, `bound` (the one-sided upper bound), `frame_n`
  (records excluded) and `conf`.

- `false_exclusion`:

  The share of excluded records that are eligible: `estimate`, `lower`,
  `upper` (exact) and `n`.

- `work_saved`:

  The share of screened records the screener excluded, which nobody
  reads: `estimate`, `excluded`, `screened`.

- `unclear_rate`:

  The share of screened records left unclear: `estimate`, `unclear`,
  `screened`.

- `strata`:

  One row per stratum the frame drew from: `N`, `n`, `eligible`,
  `inclusion_prob`, and the estimated eligible count with its exact
  two-sided bounds.

- `verdict`:

  `met` (`TRUE`, `FALSE`, or `NA` when nothing bounds recall or M),
  `rule`, `recall_target`, `conf`, `max_lost` and `note`.

- `reviewers`:

  Only for a sheet with several reviewers: `reviewers` (their labels),
  `n_reviewers`, `rule` (how the consensus was formed), `conflicts`
  (documents they disagreed on), `consensus` (how each document's
  consensus was reached, counted), `weighted`, `sensitivity` (one row
  per reviewer and statistic: `estimate`, `lower`, `upper`, `n`,
  `method`), `agreement` (one row per pair of reviewers, scope and
  statistic, the scope being the frame, a stratum or `"weighted"`),
  `notes` and `conf`.

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
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md)
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

## Recall against a target

Every calibration also reports recall, the share of eligible records the
screener kept, against `recall_target`, with bounds that stay valid at
the zero or one misses a reference usually finds.

On a stacked reference (every kept record, and a simple random sample of
n of the N excluded ones; `of = "stacked"`) the eligible count is K
among the kept and x in the sample, and recall is estimated with the
design weights, the ratio of Horvitz-Thompson totals from
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md):
K / (K + M), with M = N x / n the projected number of eligible records
excluded. M is bounded exactly from the hypergeometric distribution of
x: its upper bound M_U is the largest M for which drawing x or fewer has
probability above alpha = 1 - `conf`, and the lower bound the smallest M
for which drawing x or more does. Recall falls as M rises, so its
one-sided lower bound is K / (K + M_U). If the kept records were sampled
too, each sampled stratum is bounded the same way with alpha split
equally between them (Bonferroni). The interval in `$recall` is
two-sided at `conf`, with alpha / 2 on each side; `$recall$bound` is the
one-sided bound at `conf`. No bootstrap is used: with x = 0 every
resample also gives M = 0, and the interval would be `[1, 1]`.

On a sample of everything screened (`"all"`) the eligible records in the
sample are a random sample of all of them, and recall is the share kept
with a Clopper-Pearson bound (Lewis, Yang and Frieder 2021). That bound
treats the frame as infinite. When the sample is every screened record
(`gr_reference(n = Inf)`) recall is known exactly, and the estimate is
also both ends of the interval and the bound (`method = "census"`). A
sample of the exclusions alone bounds M and the false-exclusion rate but
not recall, since it does not count the eligible records kept, and a
sample of the kept records alone holds none of the misses.

The verdict in `$verdict` says the target is met when the one-sided
lower bound on recall is at least `recall_target`, or, when `max_lost`
is given, when the upper bound on M is at most `max_lost`. On a stacked
reference this verdict is also `$adequate`.

Weights come from the run: N is the number of records the screening
excluded (or kept), and n the rows of that stratum with a human
decision. On a complete sheet that is the inclusion probability the
sheet records; a sheet whose recorded probabilities disagree is weighted
by the run, with a warning. Agreement statistics are not computed on a
stacked reference, since unweighted they are distorted in the same
direction as unweighted sensitivity.

## One row per document

The reference is matched to the screening by document name, compared as
UTF-8 whatever the session's locale, and by `document_id` for a row
whose name still does not match. A document judged twice (two sheets
stacked with no `reviewer` column, say) is counted once when the copies
agree, with a warning, and is refused when they disagree.

## Several reviewers

A sheet with one `human_decision_<reviewer>` column per reviewer (from
`gr_reference(reviewers = k)`), or a long sheet with a `reviewer`
column, is compared on the reviewers' consensus. Where it has been
formed with
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)
that is used; otherwise records the reviewers agreed on take their
decision, records they disagreed on take the `consensus` column, and the
calibration stops if any disagreement has none, saying how many there
were.

`$reviewers` then reports how far the people agree with each other, the
yardstick for the screener's agreement with them, with
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md):
for every pair of reviewers the observed agreement, Cohen's kappa,
PABAK, Gwet's AC1 and the prevalence and bias indices, never kappa
alone, and with three reviewers or more Krippendorff's alpha over all of
them. It also reports each reviewer's sensitivity and specificity
against the consensus, the share of consensus-eligible records they
included and of consensus-ineligible records they excluded, which says
what one person screening alone would have missed. A reviewer is scored
on the records they judged. Note that a reviewer is part of the
consensus they are scored against, so these figures are higher than
against an independent reference, and more so with fewer reviewers.

On a stacked reference both are weighted the way recall is, each record
by N_h / n_h for its stratum h (the screener's kept or excluded
records), so they describe every record screened rather than the sample.
Sensitivity is sum_h (N_h / n_h) a_h / sum_h (N_h / n_h) (a_h + b_h),
with a_h the consensus-eligible records the reviewer included in stratum
h and b_h those they excluded; its interval bounds each count in a
sampled stratum exactly with the hypergeometric distribution, alpha
split equally over them (Bonferroni), and maps them through the ratio,
which rises with a and falls with b. Specificity is the same with the
consensus-ineligible records. Agreement is computed on the 2x2 table
built with the same weights, with percentile intervals from a bootstrap
within each sampled stratum (B = 2000, seed 1), and
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
is also reported within each stratum. The weighted kappa interval is
approximate and runs narrow when the sampled exclusion stratum holds
fewer than about 100 records (near 80% coverage for a nominal 95% at
30), and `$reviewers$notes` says so; the observed agreement, PABAK and
AC1 intervals hold up better there. On any other frame the sample is one
simple random sample, the figures are unweighted, and sensitivity and
specificity have Wilson intervals, as in `$metrics`.

## References

Lewis, D. D., Yang, E. and Frieder, O. (2021). Certifying one-phase
technology-assisted reviews. *Proceedings of the 30th ACM International
Conference on Information and Knowledge Management*, 893-902.

Horvitz, D. G. and Thompson, D. J. (1952). A generalization of sampling
without replacement from a finite universe. *Journal of the American
Statistical Association* 47(260), 663-685.

Byrt, T., Bishop, J. and Carlin, J. B. (1993). Bias, prevalence and
kappa. *Journal of Clinical Epidemiology* 46(5), 423-429.

Gwet, K. L. (2008). Computing inter-rater reliability and its variance
in the presence of high agreement. *British Journal of Mathematical and
Statistical Psychology* 61(1), 29-48.

## See also

[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)

Other corpus functions:
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)

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
#>   recall 75.0%  [75.0%, 75.0%]; 95% one-sided lower bound 75.0%
#>   eligible records excluded: about 1 of 4; 95% upper bound 1
#>   recall target 95.0% at 95% confidence: not met
#>   ! 1 eligible study was excluded by the screener:
#>       d6.pdf
#>   ! only 4 eligible studies in the sample. Every rate above rests on
#>     those 4 observations, which is why the intervals are as wide as they are.
#>     Hand-screen more before quoting a figure.
```
