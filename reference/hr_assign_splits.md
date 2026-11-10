# Assign reference items to splits by cluster

Puts every item of a cluster (a document, usually) in the same split, so
that no document has items on both sides of a tuning and a scoring
split. The assignment is worked out from the seed and the cluster ids
alone: the order of the rows, the session's random state and the other
clusters in the set do not change it (with `method = "stable"`).

## Usage

``` r
hr_assign_splits(
  items,
  cluster = NULL,
  props = c(dev = 0.1, exploratory = 0.1, calibration = 0.3, test = 0.5),
  seed,
  method = c("stable", "balanced")
)
```

## Arguments

- items:

  The items: a vector of item ids, or a data frame with one row per
  item. A data frame's ids come from its `item_id` column, else its `id`
  column, else the row number. Column names are matched exactly, so a
  column such as `ideal_answer` is never taken for `id`.

- cluster:

  The cluster of each item: a vector as long as `items`, or for a data
  frame the name of a column. With a data frame one string is always
  read as a column name; for a one-row frame and a literal cluster
  value, wrap it in [`I()`](https://rdrr.io/r/base/AsIs.html). `NULL`
  takes a data frame's `cluster` column, else its `document` column; for
  a vector of ids, or a data frame with neither column, each item is its
  own cluster.

- props:

  Named shares, from `"dev"`, `"exploratory"`, `"calibration"`, `"test"`
  and `"final"`, each at least 0, adding up to 1.

- seed:

  One number or one string. Required: the assignment is a function of
  the seed and the ids, so the seed has to be recorded with it.

- method:

  `"stable"` or `"balanced"`; see "How clusters are assigned".

## Value

An object of class `hr_splits`, a list with:

- `items`:

  The items with a `split` column: the data frame given, or a data frame
  of `item_id`, `cluster` and `split`.

- `clusters`:

  One row per cluster: `cluster`, `n_items`, `u` and `split`.

- `counts`:

  One row per split in `props`: `split`, `target` (the share asked for),
  `clusters`, `items`, `cluster_share` and `item_share`.

- `props`, `seed`, `method`:

  As given.

- `notes`:

  Remarks, such as a split that was given a share and received no
  cluster.

It has a [`print()`](https://rdrr.io/r/base/print.html) method.

## The splits

- `dev` tunes prompts, settings and margins. Its scores are not
  evidence.

- `exploratory` is kept out of the test set for exploratory comparisons.

- `calibration` is for calibrating signals and choosing gate thresholds
  ([`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
  [`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)),
  kept apart from both tuning and testing.

- `test` is what reported comparisons are scored on.

- `final` is an optional held-back set, run once per release.

`props` names any of these. A split given a share of 0 receives nothing.

## How clusters are assigned

Each cluster gets a number `u` in \[0, 1) from the first 13 hex digits
of the SHA-256 digest of `"harnessr-split"`, the seed and the cluster id
(as UTF-8, joined by a separator), divided by 16^13. A number that is a
whole number is written out in full before it is hashed, so a document
id of 100000 gets the same split whether it is stored as a double or as
an integer (`as.character(100000)` would give `"1e+05"`).

- `method = "stable"` (the default) cuts \[0, 1) into consecutive
  intervals whose widths are `props`, in the order `props` is given, and
  a cluster goes to the interval `u` falls in. A cluster's split depends
  only on the seed and its own id, so adding documents to the set later,
  or dropping some, never moves another document between splits. The
  shares are those of `props` on average over clusters; with few
  clusters they can be some way off, and `counts` shows how far.

- `method = "balanced"` sorts the clusters by `u` and gives each split
  its share of the clusters, rounded by largest remainders (Hamilton's
  method), in the order `props` is given. The number of clusters per
  split is then as close to `props` as whole clusters allow, but a
  cluster added later can shift others across a boundary, so the
  assignment should be drawn once and stored.

Shares are shares of clusters. Item counts follow from cluster sizes and
are reported beside them.

## See also

[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
to write sheets for people to label the items,
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md).

Other reference sets:
[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md),
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)

## Examples

``` r
qa <- data.frame(item_id = sprintf("q%02d", 1:40),
                 document = rep(sprintf("doc%02d.pdf", 1:10), each = 4))
sp <- hr_assign_splits(qa, seed = 2026)
sp
#> <hr_splits> 40 item(s) in 10 cluster(s), method stable, seed 2026
#> 
#>        split target clusters items cluster_share item_share
#>          dev    0.1        1     4           0.1        0.1
#>  exploratory    0.1        2     8           0.2        0.2
#>  calibration    0.3        1     4           0.1        0.1
#>         test    0.5        6    24           0.6        0.6
table(sp$items$split)
#> 
#> calibration         dev exploratory        test 
#>           4           4           8          24 

# Whole clusters, split as close to the shares as ten documents allow.
hr_assign_splits(qa, seed = 2026, method = "balanced")$counts
#>         split target clusters items cluster_share item_share
#> 1         dev    0.1        1     4           0.1        0.1
#> 2 exploratory    0.1        1     4           0.1        0.1
#> 3 calibration    0.3        3    12           0.3        0.3
#> 4        test    0.5        5    20           0.5        0.5
```
