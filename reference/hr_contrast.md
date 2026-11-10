# Non-inferiority contrasts, registered before scoring

`hr_contrast()` states that arm `new` is not worse than arm `reference`
by more than `margin` in accuracy and, with `cost_test = TRUE`, that it
is cheaper. `hr_register_contrasts()` fixes a set of contrasts against
an
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
before any benchmark scores it, with the design MDD from
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
and
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
tests them.

## Usage

``` r
hr_contrast(new, reference, margin, confirmatory = TRUE, cost_test = TRUE)

hr_register_contrasts(plan, contrasts, mdd)

# S3 method for class 'hr_contrast'
print(x, ...)

# S3 method for class 'hr_contrast_registration'
print(x, ...)
```

## Arguments

- new:

  The name of the arm under test.

- reference:

  The name of the arm it is compared with.

- margin:

  The non-inferiority margin Delta, as a proportion (0.08 for 8 points),
  in (0, 1). Pre-register it as min(0.5 x M1, the practical loss
  threshold), with M1 the reference's advantage over a minimal baseline
  from a pilot on the dev split.

- confirmatory:

  `TRUE` for a confirmatory contrast, in the Holm family and held to the
  MDD; `FALSE` for an exploratory one.

- cost_test:

  Whether the verdict also needs `new` to be cheaper than `reference`.

- plan:

  The
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  the benchmark will score, before it is scored.

- contrasts:

  An `hr_contrast` or a list of them.

- mdd:

  An
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  for the planned design.

- x:

  An `hr_contrast` or `hr_contrast_registration`.

- ...:

  Ignored.

## Value

`hr_contrast()` returns an object of class `hr_contrast`, a list of its
arguments. `hr_register_contrasts()` returns an object of class
`hr_contrast_registration`, a list with `contrasts` (a data frame with
`new`, `reference`, `margin`, `confirmatory`, `label`, `cost_test` and
`mdd_design`, the MDD each contrast is held to), `mdd` (the
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
after Holm over the confirmatory contrasts), `mdd_single` (the same
design without the Holm adjustment), `alpha`, `power`, `n_confirmatory`,
`reference_hash`, `registered_at` and `hash`.

## Details

**Registration.** A confirmatory contrast whose margin is below the
design MDD at 80% power after Holm over the confirmatory contrasts is
refused with an error of class `hr_margin_below_mdd`: a non-inferiority
claim at a margin finer than the design can detect says more than the
items hold. Registering it with `confirmatory = FALSE` labels it
exploratory instead; it is then tested at the unadjusted alpha and stays
out of the Holm family. The MDD checked is `mdd` recomputed with
`n_contrasts` raised to the number of confirmatory contrasts when it was
lower, `holm = TRUE`, `power` raised to 0.8 when it was lower, and
`alpha` lowered to 0.025 when it was higher;
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
tests at that alpha. The design may not hold more items or clusters than
the reference has on the test and final splits (an error of class
`gr_bad_setting`).

A reference that a benchmark has begun to score in this session, or one
rebuilt with the same content, is refused, with an error of class
`hr_registration_after_scoring`, since a margin chosen after the results
are seen is not pre-registered. The registration records the reference's
hash, the time and a SHA-256 hash of its own content;
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
refuses a registration whose content no longer matches its hash or that
names another reference.

## See also

[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
ref <- hr_reference(paste0("q", 1:480), labels = rep("yes", 480),
                    cluster = rep(paste0("doc", 1:80), each = 6), split = "test")
design <- hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
design$mdd
#> [1] 0.08188689

# A 10-point margin can be registered; a 5-point one only as exploratory.
reg <- hr_register_contrasts(ref, list(
  hr_contrast("short", "long", margin = 0.10),
  hr_contrast("skim", "long", margin = 0.05, confirmatory = FALSE)), design)
reg
#> <hr_contrast_registration> 2 contrast(s), 1 confirmatory; registered 2026-11-10T01:54:33.257Z
#>  contrast      label        margin mdd cost_test
#>  short vs long confirmatory 10.0   8.2 yes      
#>  skim vs long  exploratory  5.0    8.2 yes      
#>   Margins and MDD in points; reference db69600f91ae; hash 9c90941991d4
try(hr_register_contrasts(ref, hr_contrast("skim", "long", margin = 0.05), design))
#> Error in hr_register_contrasts(ref, hr_contrast("skim", "long", margin = 0.05),  : 
#>   The margin of skim vs long (5.0 points) is below the design MDD of 8.2 points (80% power, one-sided alpha 0.025 after Holm over 1 contrast(s)), so the design cannot support a non-inferiority claim at it. Widen the margin, enlarge the design, or register the contrast with confirmatory = FALSE as exploratory.
```
