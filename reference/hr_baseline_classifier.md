# Cross-fitted text classifier baseline

A ridge-penalised logistic regression on tf-idf features, fitted fold by
fold so that every prediction comes from a model that never saw the
item. Its accuracy is the floor a model configuration has to beat: a
classifier trained on the same labels costs no model calls.

## Usage

``` r
hr_baseline_classifier(
  texts,
  labels,
  folds = 5,
  cluster = NULL,
  seed = 1,
  lambda = 1,
  min_df = 2,
  max_features = 5000
)

# S3 method for class 'hr_baseline_classifier'
print(x, ...)
```

## Arguments

- texts:

  Character vector, one text per item.

- labels:

  The label of each item: a factor, character, logical or numeric vector
  with at least two distinct values and no `NA`.

- folds:

  Number of folds, at least 2.

- cluster:

  Optional cluster of each item; folds then keep clusters whole.

- seed:

  Seed for the fold deal, run on a private random stream so the
  session's stream does not move.

- lambda:

  Ridge penalty, a positive number.

- min_df, max_features:

  Passed to the tf-idf fit of each fold.

- x:

  An `hr_baseline_classifier`.

- ...:

  Not used.

## Value

An `hr_baseline_classifier`, a list with:

- `predictions`: one row per item with `item` (position), `id`
  (`names(texts)`, or the position), `fold`, `label`, `predicted` and
  `correct`.

- `prob`: the out-of-fold probability matrix, one column per label.

- `folds`: one row per fold with `fold`, `n_train`, `n_test` and
  `n_terms`.

- `train_items`: the training item positions of each fold.

- `accuracy`: the
  [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)
  row for the out-of-fold accuracy.

- `classes`, `settings` and `note`.

## Details

**Folds.** Items are dealt to `folds` folds under `seed`. Without
`cluster`, the deal is stratified by label. With `cluster` (a document
id, a source), whole clusters are dealt, so items that share a cluster
are never split between training and test; with fewer clusters than
`folds`, there is one fold per cluster. For each fold, the vocabulary
and idf weights are fitted on the training texts only
([`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)
with `min_df` and `max_features`) and applied to the held-out texts, so
no word statistics from a test text reach its model.

**Model.** For two labels, one logistic regression of the second level
against the first. Its coefficients maximise sum_i log L_i - (lambda /
2) \* sum_j beta_j^2, with the intercept not penalised, fitted by
iteratively reweighted least squares (each step a weighted ridge solve
on the working response; Hastie, Tibshirani and Friedman 2009, section
4.4) with step halving. `lambda = 1` is the same penalty as
scikit-learn's `LogisticRegression` default (`C = 1`). For more than two
labels, one model per label against the rest, with the probabilities
divided by their sum; a label missing from a training fold gets
probability 0 there. The predicted label is the most probable one, the
first in level order on a tie.

**Accuracy.** The share of items whose predicted label equals the given
one, with a Wilson interval from
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md).
The interval treats items as independent; with `cluster`, read it as too
narrow when clusters are large, and use the out-of-fold predictions in a
benchmark report for a clustered interval.

## References

Hastie, T., Tibshirani, R. and Friedman, J. (2009). *The Elements of
Statistical Learning*, 2nd edition. Springer.

le Cessie, S. and van Houwelingen, J. C. (1992). Ridge estimators in
logistic regression. *Applied Statistics* 41(1), 191-201.

## See also

Other baselines:
[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md),
[`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)

## Examples

``` r
texts <- c(paste("trial randomised placebo", c("adults", "children", "elderly")),
           paste("survey interview opinion", c("adults", "children", "elderly")),
           paste("randomised placebo trial", c("women", "men")),
           paste("opinion survey interview", c("women", "men")))
labels <- rep(c("trial", "survey", "trial", "survey"), c(3, 3, 2, 2))
fit <- hr_baseline_classifier(texts, labels, folds = 2)
fit
#> <hr_baseline_classifier> ridge logistic, 2 labels, 2 folds
#>   accuracy: 1.000 [0.722, 1.000], 10 of 10 out of fold
#>   training size per fold: 5, 5
fit$predictions
#>    item id fold  label predicted correct
#> 1     1  1    2  trial     trial    TRUE
#> 2     2  2    1  trial     trial    TRUE
#> 3     3  3    1  trial     trial    TRUE
#> 4     4  4    1 survey    survey    TRUE
#> 5     5  5    1 survey    survey    TRUE
#> 6     6  6    1 survey    survey    TRUE
#> 7     7  7    2  trial     trial    TRUE
#> 8     8  8    2  trial     trial    TRUE
#> 9     9  9    2 survey    survey    TRUE
#> 10   10 10    2 survey    survey    TRUE
```
