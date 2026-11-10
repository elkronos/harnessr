# The alternative annotator test

Tests whether a model's labels can be used in place of human annotators,
with the leave-one-out procedure of Calderon, Reichart and Dror (2025)
as implemented in their reference code (github.com/nitaytech/alttest).

## Usage

``` r
hr_alt_test(
  model_labels,
  human_labels,
  expertise,
  epsilon = NULL,
  q = 0.05,
  metric = c("accuracy", "neg_rmse")
)
```

## Arguments

- model_labels:

  The model's label for each item: a vector with one value per row of
  `human_labels`, `NA` where it gave none.

- human_labels:

  A matrix or data frame, items in rows and human annotators in columns,
  `NA` where an annotator did not label an item. Column names, when
  given, must be unique and non-empty; they name the rows of
  `per_annotator`.

- expertise:

  The annotators' expertise: `"expert"`, `"skilled"` or `"crowd"`.
  Required.

- epsilon:

  The cost-benefit margin. `NULL` takes it from `expertise`.

- q:

  False discovery rate for the Benjamini-Yekutieli correction.

- metric:

  `"accuracy"` for categorical labels, `"neg_rmse"` for numeric ones.

## Value

An object of class `hr_alt_test`, a list with `passed`, `omega`, `rho`,
`epsilon`, `expertise`, `q`, `metric`, `n_items`, `per_annotator` (a
data frame: `annotator`, `n`, `rho_model`, `rho_human`, `p_value`,
`p_adjusted`, `rejected`), `sweep` (a data frame of `epsilon`, `omega`
and `passed`), `skipped` and `notes`.

## Details

For each human annotator j in turn, on every item j labelled:

1.  score the model's label against the labels of the other annotators
    of that item, and score j's label the same way (`metric`: the share
    of them it matches for `"accuracy"`, minus the root mean squared
    difference for `"neg_rmse"`);

2.  W_model = 1 where the model's score is at least j's, W_human = 1
    where j's is at least the model's (a tie counts for both);

3.  test H0: mean(W_human - W_model) \>= epsilon against the one-sided
    alternative that it is below epsilon, with a one-sample t test.
    Rejecting says the model is not worse than j by more than epsilon.

The p-values of all annotators are corrected with Benjamini-Yekutieli at
level `q`. The winning rate omega is the share of annotators for whom
the test rejects, and the model passes when omega \>= 0.5. The advantage
probability rho is the mean of W_model over items, averaged over
annotators: how often the model represents the others at least as well
as the person it replaces.

epsilon is the penalty paid by the human annotators for being slower and
dearer. The authors' rule of thumb sets it by their expertise: 0.2 for
experts, 0.15 for skilled annotators such as trained students, 0.1 for
crowd workers, and lower than that when the people agree poorly with
each other. `expertise` has no default so the choice is always made on
purpose. Because the verdict depends on epsilon, omega is also reported
for each epsilon from 0.05 to 0.20 in steps of 0.05.

Requirements: at least 3 human annotators (the authors accept 2 but
advise 3, since with two the test only asks which of them the model
resembles), and at least 30 items with a model label and two or more
human labels, where the t test's normal approximation starts to hold;
fewer is an error. Below 50 items there is a warning, as the authors
recommend 50 to 100. An annotator with fewer than 30 such items is left
out of the test, as in the reference code, and the result names them.

A t statistic is undefined when W_human - W_model is constant. Then the
p-value is 0 when that constant is below epsilon and 1 otherwise, the
limit of the test as the spread goes to zero.

## References

Calderon, N., Reichart, R. and Dror, R. (2025). The alternative
annotator test for LLM-as-a-judge: how to statistically justify
replacing human annotators with LLMs. *Proceedings of the 63rd Annual
Meeting of the Association for Computational Linguistics*, 16051-16081.

Benjamini, Y. and Yekutieli, D. (2001). The control of the false
discovery rate in multiple testing under dependency. *Annals of
Statistics* 29(4), 1165-1188.

## See also

Other statistics:
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md),
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md),
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md),
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)

## Examples

``` r
set.seed(3)
gold <- sample(c("a", "b", "c"), 80, replace = TRUE)
noisy <- function(p) ifelse(runif(80) < p, gold, sample(c("a", "b", "c"), 80, TRUE))
people <- sapply(1:4, function(j) noisy(0.75))
hr_alt_test(noisy(0.95), people, expertise = "skilled")
#> <hr_alt_test> passed: omega = 1 with epsilon = 0.15 (skilled annotators), q = 0.05
#> 80 items, metric accuracy, advantage probability rho = 0.991
#> 
#>    annotator  n rho_model rho_human  p_value p_adjusted rejected
#>  annotator_1 80     0.988     0.850 1.15e-09   2.40e-09     TRUE
#>  annotator_2 80     0.988     0.800 2.17e-10   6.03e-10     TRUE
#>  annotator_3 80     0.988     0.788 1.34e-10   5.57e-10     TRUE
#>  annotator_4 80     1.000     0.825 2.58e-11   2.15e-10     TRUE
#> 
#> omega by epsilon:
#>  epsilon omega passed
#>     0.05     1   TRUE
#>     0.10     1   TRUE
#>     0.15     1   TRUE
#>     0.20     1   TRUE
```
