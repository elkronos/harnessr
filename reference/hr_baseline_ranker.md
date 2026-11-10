# Active-learning screening baseline

Simulates prioritised screening over a set where every record's
relevance is already known, the way ASReview's simulation mode does: the
result shows how much reading a cheap ranker would have saved, which a
model screener has to beat.

## Usage

``` r
hr_baseline_ranker(
  texts,
  labels,
  seed_n = c(1, 1),
  batch = 1,
  model = c("logistic", "naive_bayes"),
  seed = 1,
  lambda = 1,
  min_df = 2,
  max_features = 5000
)

# S3 method for class 'hr_baseline_ranker'
print(x, ...)
```

## Arguments

- texts:

  Character vector, one text per record.

- labels:

  Relevance of each record: logical, or numeric 0 and 1.

- seed_n:

  Number of relevant and irrelevant records known at the start, each at
  least 1.

- batch:

  Records screened between refits.

- model:

  `"logistic"` or `"naive_bayes"`.

- seed:

  Seed for the prior records and tie order, on a private random stream.

- lambda:

  Ridge penalty for `"logistic"`.

- min_df, max_features:

  Passed to
  [`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md).

- x:

  An `hr_baseline_ranker`.

- ...:

  Not used.

## Value

An `hr_baseline_ranker`, a list with `order` (record positions in
screening order), `relevant` (their labels in that order), `curve` (a
data frame of `n_screened`, `item`, `relevant`, `found` and `recall`),
`n_95`, `wss_95`, `random_n_95`, `prior` (the seed records), `n_fits`,
`n_total`, `n_relevant` and `settings`.
[`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
accepts it directly.

## Details

**Procedure.** Under `seed`, `seed_n[1]` relevant and `seed_n[2]`
irrelevant records are drawn as the prior knowledge and screened first,
in a random order. Then, until every record is screened: fit the model
on the records screened so far, score the rest, and screen the `batch`
with the highest predicted probability of relevance (ties broken by a
seeded random order). Features are
[`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)
over all texts, which uses no labels. Once the last relevant record has
been screened, the remaining records are ordered by the last model
without refitting, since their order changes no figure reported here.

**Models.** `"logistic"` is the ridge logistic regression of
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
with penalty `lambda`, warm-started from the previous fit.
`"naive_bayes"` is multinomial naive Bayes on the tf-idf weights with
add-one smoothing (ASReview's default classifier is also multinomial
naive Bayes, with alpha = 3.822).

**Measures.** `recall` is the share of relevant records found after each
screened record. `n_95` is the number screened when recall first reaches
0.95 (the position of the ceiling(0.95 R)-th relevant record, R relevant
in all), and WSS@95 = (N - n_95) / N - 0.05 (Cohen et al. 2006): the
share of records left unread at 95% recall, less the 5% a random order
would leave at that recall. `random_n_95` is the expected n_95 of a
random order, k (N + 1) / (R + 1) with k = ceiling(0.95 R). The seed
records count as screened. WSS depends on prevalence, so compare it only
between methods on the same set.

The simulation fits one model per batch, so its cost grows with N /
`batch` fits; raise `batch` for sets of several thousand.

## References

Cohen, A. M., Hersh, W. R., Peterson, K. and Yen, P.-Y. (2006). Reducing
workload in systematic review preparation using automated citation
classification. *Journal of the American Medical Informatics
Association* 13(2), 206-219.

van de Schoot, R. et al. (2021). An open source machine learning
framework for efficient and transparent systematic reviews. *Nature
Machine Intelligence* 3, 125-133.

## See also

Other baselines:
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md),
[`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)

## Examples

``` r
set.seed(1)
topic <- function(words, n) {
  vapply(seq_len(n), function(i) paste(sample(words, 6, TRUE), collapse = " "), "")
}
texts <- c(topic(c("masks", "infection", "trial", "ward", "virus"), 10),
           topic(c("budget", "policy", "school", "survey", "income"), 50))
labels <- rep(c(TRUE, FALSE), c(10, 50))
r <- hr_baseline_ranker(texts, labels)
r
#> <hr_baseline_ranker> logistic, 60 records, 10 relevant, 9 fits
#>   95% recall after 11 records (random order: 55.5 expected)
#>   WSS@95: 0.767
head(r$curve, 12)
#>    n_screened item relevant found recall
#> 1           1    9        1     1    0.1
#> 2           2   14        0     1    0.1
#> 3           3    1        1     2    0.2
#> 4           4    7        1     3    0.3
#> 5           5    5        1     4    0.4
#> 6           6    6        1     5    0.5
#> 7           7    8        1     6    0.6
#> 8           8    2        1     7    0.7
#> 9           9    4        1     8    0.8
#> 10         10    3        1     9    0.9
#> 11         11   10        1    10    1.0
#> 12         12   48        0    10    1.0
```
