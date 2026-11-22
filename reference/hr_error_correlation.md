# Correlated errors between the arms of a benchmark

Says how far the arms of an
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
fail on the same items, and with the same wrong answer, and draws a
sample of the items every arm got wrong for a person to check by hand.
It reads only the benchmark's rows and sends nothing.

## Usage

``` r
hr_error_correlation(
  bench,
  strata = NULL,
  n_strata = 3L,
  n_check = 10L,
  held_out = TRUE,
  seed = 1L
)
```

## Arguments

- bench:

  An `hr_bench` from
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  with at least two arms.

- strata:

  `NULL` to stratify by difficulty, or each item's stratum: a vector
  named by item, or one value per item in the order of
  `unique(bench$item)`.

- n_strata:

  How many difficulty strata, when `strata` is `NULL`: a whole number
  from 1 to 10, default 3. Fewer are made when the items take fewer
  distinct difficulties.

- n_check:

  How many items every arm got wrong to sample for a hand check: a whole
  number, 0 or more, default 10.

- held_out:

  `TRUE` (the default) reads only the rows that count as evidence
  (`reportable`, so not the dev split); `FALSE` reads every row.

- seed:

  The seed of the private random stream the sample is drawn with; the
  caller's random state is left as it was.

## Value

A list of class `hr_error_correlation`:

- `phi`:

  One row per pair of arms and stratum: `arm_a`, `arm_b`, `stratum`,
  `items`, `both_wrong`, `phi` (`NA` where undefined).

- `pairs`:

  One row per pair of arms: `arm_a`, `arm_b`, `items`, `phi_pooled`,
  `both_wrong`, `both_answered` (of those, the items where both gave an
  outcome), `same_wrong` and `same_wrong_rate`.

- `check`:

  The hand-check sample: `item` and one column per arm holding its wrong
  outcome.

- `all_wrong`:

  How many items every arm got wrong.

- `strata`:

  Each item's stratum, named by item.

- `q3`:

  Why Yen's Q3 is not given.

## Details

Each arm is reduced to one result per item: an error when it was wrong
on more than half of its scored runs of the item. Items with no label
(every `correct` `NA`) are left out.

- Phi within difficulty strata:

  For each pair of arms, the phi coefficient (the correlation of two 0/1
  error indicators over the items) within each stratum of item
  difficulty. Two arms both wrong on the hard items are correlated for
  that reason alone; within a stratum of items of like difficulty, what
  is left is the shared blind spot. Difficulty is the share of all the
  arms' scored runs on an item that were wrong, cut into `n_strata`
  groups at its quantiles, unless `strata` gives each item's stratum (as
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)'s
  `strata` do). `phi_pooled` is the mean of the strata's phi weighted by
  their items, over strata where phi is defined (both arms right on some
  items and wrong on others). Because difficulty is read from the same
  runs, the strata are a coarse adjustment, not an independent one.

- Same wrong answer:

  For each pair, of the items both got wrong where both gave an answer
  (`outcome` not `NA`), the share where they gave the same wrong answer
  (each arm's most frequent wrong outcome on the item, compared after
  case and surrounding space are set aside). Kim et al. (2025,
  "Correlated errors in large language models") report this rate for
  models that share a provider or architecture.

- Hand-check sample:

  Up to `n_check` items every arm got wrong, drawn at random with
  `seed`, with each arm's wrong outcome, for a person to read. Unanimous
  errors are where a label can be the thing that is wrong.

Yen's Q3, the residual correlation of a one-parameter item response
model fitted as a mixed model, is not computed: it would need a
mixed-model package (lme4) that harnessr does not depend on. `$q3` says
so.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)

## Examples

``` r
ref <- hr_reference(sprintf("q%02d", 1:12), labels = rep("yes", 12),
                    cluster = sprintf("c%02d", 1:12), split = "test")
says <- function(name, wrong_on) hr_arm(name, function(item, ctx) {
  if (item %in% wrong_on) "no" else "yes"
})
arms <- list(says("arm_a", c("q01", "q02", "q03")),
             says("arm_b", c("q01", "q02", "q04")))
bench <- suppressWarnings(hr_benchmark(arms, ref, runs = 1, client = NULL))
ec <- hr_error_correlation(bench, n_strata = 1)
ec$pairs
#>   arm_a arm_b items phi_pooled both_wrong both_answered same_wrong
#> 1 arm_a arm_b    12  0.5555556          2             2          2
#>   same_wrong_rate
#> 1               1
ec$check
#>   item arm_a arm_b
#> 1  q01    no    no
#> 2  q02    no    no
```
