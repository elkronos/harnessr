# A reference set to score arms against

A reference holds the items a benchmark runs every arm on, the label
each item is scored against, the cluster it belongs to (the unit whose
items share errors, such as a document or a task), and the split it is
in.

## Usage

``` r
hr_reference(
  items,
  labels,
  cluster,
  split = c("dev", "exploratory", "calibration", "test", "final"),
  inclusion_prob = 1,
  strata = NULL,
  coders = NULL
)

hr_reference_add(
  reference,
  items,
  labels,
  cluster,
  split = c("dev", "exploratory", "calibration", "test", "final"),
  inclusion_prob = 1,
  strata = NULL,
  coders = NULL
)
```

## Arguments

- items:

  The items, one per element: a named list whose names are the item ids
  and whose elements are the payloads the arms are given (any R object:
  a question, a question with a file path, a record), a named character
  vector (names are ids, values payloads), or an unnamed character
  vector of ids, which are then their own payloads.

- labels:

  The label of each item, one per item: an atomic vector, or a list
  whose elements may hold several accepted answers. `NA` for an item
  with no label, which is scored `NA`. Unnamed, the labels go to the
  items in order; named, they go to the items by name, and the names
  must be the item ids. The same holds for `cluster`, `split`,
  `inclusion_prob` and `strata` when they give one value per item.

- cluster:

  The cluster of each item, one per item, or one value for all. Taken as
  text.

- split:

  The split of each item, one per item, or one value for all: `"dev"`,
  `"exploratory"`, `"calibration"`, `"test"` or `"final"`. When `split`
  is not given, every item goes in `"dev"`.

- inclusion_prob:

  The probability each item was drawn into the reference, in (0, 1\]:
  one per item or one for all.

- strata:

  The sampling stratum of each item, or `NULL`.

- coders:

  The labels individual coders gave, one row per item and one column per
  coder (a matrix or data frame), or `NULL`.

- reference:

  An `hr_reference`.

## Value

An object of class `hr_reference`: a list of `ids`, `items` (the
payloads, named by id), `labels`, `cluster`, `split`, `inclusion_prob`,
`strata`, `coders` and `hash`. `hr_reference_add()` returns a new
reference holding the old items and the new ones, sharing the old one's
lock.

## Details

The splits keep tuning apart from evidence. `"dev"` is for tuning
prompts and thresholds, and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
marks its rows as not reportable. `"exploratory"` is for early
experiments kept out of the test set, `"calibration"` for setting signal
thresholds, `"test"` for the reported comparison, and `"final"` for a
held-out set run once per release.

`inclusion_prob` is the probability with which each item was drawn into
the reference, for estimates that weight items by it (see
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md));
1 means every item of the population is in the reference.

A reference is locked when a benchmark starts scoring it. After that
`hr_reference_add()` refuses to add items to it or to any reference
built from it, with an error of class `hr_reference_locked`, so gold
items cannot be chosen after the results are seen. The lock is shared by
every copy of the reference. The `hash` is a SHA-256 hash of the ids,
payloads, labels, clusters, splits, inclusion probabilities, strata and
coders;
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
refuses a reference whose content no longer matches it.

## See also

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
ref <- hr_reference(
  items = list(q1 = "Capital of France?", q2 = "Capital of Peru?",
               q3 = "Capital of Chad?"),
  labels = c("Paris", "Lima", "N'Djamena"),
  cluster = c("europe", "americas", "africa"),
  split = "test")
ref
#> <hr_reference> 3 item(s) in 3 cluster(s)
#>   splits: test 3 
#>   hash: 14e0a94eaaec

# Items can be added until a benchmark has scored the reference.
ref <- hr_reference_add(ref, list(q4 = "Capital of Fiji?"), "Suva", "oceania",
                        split = "test")
length(ref$ids)
#> [1] 4
```
