# Tf-idf features from texts

Turns texts into an l2-normalised tf-idf matrix, the feature set the
baselines
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
and
[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
use.

## Usage

``` r
hr_tfidf(texts, min_df = 2, max_features = 5000)
```

## Arguments

- texts:

  Character vector of texts. `NA` is read as an empty text.

- min_df:

  Smallest number of texts a term must appear in.

- max_features:

  Largest number of terms kept.

## Value

A numeric matrix with one row per text (named by `names(texts)` when
present) and one column per term, in C-locale order. The idf weights are
attached as the named vector `attr(, "idf")`.

## Details

- Tokens are runs of letters and digits after lower-casing (`"COVID-19"`
  gives `"covid"` and `"19"`). There is no stemming and no stop word
  list.

- A term is kept when it appears in at least `min_df` texts. If more
  than `max_features` terms pass, the most frequent across all texts are
  kept.

- The weight of term j in text i is tf(i, j) \* idf(j), where tf is the
  raw count and idf(j) = log((1 + n) / (1 + df(j))) + 1, with n texts
  and df(j) the number of texts containing j. This is the smoothed idf
  of scikit-learn's `TfidfVectorizer`, which ASReview uses.

- Each row is then divided by its Euclidean norm. A text with no kept
  term is a row of zeros.

The result is an ordinary dense base R matrix. That is fine at the sizes
a benchmark reference or a screening set has (a few thousand texts by at
most `max_features` terms is tens of megabytes); it is not meant for a
corpus of millions.

## References

Salton, G. and Buckley, C. (1988). Term-weighting approaches in
automatic text retrieval. *Information Processing and Management* 24(5),
513-523.

Pedregosa, F. et al. (2011). Scikit-learn: machine learning in Python.
*Journal of Machine Learning Research* 12, 2825-2830.

## See also

Other baselines:
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md),
[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)

## Examples

``` r
m <- hr_tfidf(c("Masks cut infection.", "Masks and handwashing.",
                "Handwashing cut infection."))
round(m, 3)
#>        cut handwashing infection masks
#> [1,] 0.577       0.000     0.577 0.577
#> [2,] 0.000       0.707     0.000 0.707
#> [3,] 0.577       0.577     0.577 0.000
#> attr(,"idf")
#>         cut handwashing   infection       masks 
#>    1.287682    1.287682    1.287682    1.287682 
attr(m, "idf")
#>         cut handwashing   infection       masks 
#>    1.287682    1.287682    1.287682    1.287682 
```
