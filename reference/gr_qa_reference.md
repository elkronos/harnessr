# A reference of questions about documents

Builds an
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
whose items are questions about documents, for benchmarking reading
recipes with
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
and scoring them with
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md).

## Usage

``` r
gr_qa_reference(
  questions,
  documents,
  answers,
  split,
  cluster = documents,
  unanswerable = NULL
)
```

## Arguments

- questions:

  The questions, a character vector. Its names, when every question has
  one, are the item ids; otherwise the ids are `q1`, `q2`, and so on,
  zero-padded to a common width so they sort in order (`q01` to `q10`
  for ten questions).

- documents:

  The document each question is about: a character vector of file paths,
  web addresses or text (one per question, or one for all), or a list
  whose elements may also be chunks from
  [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md).

- answers:

  The acceptable answers, one element per question: a character vector
  with one answer each, or a list whose elements are character vectors
  of alternatives. `NA` or an empty element for a question with no
  answer (an unanswerable one, or one not yet labelled). Numbers are
  taken as text.

- split:

  The split of each item, one per item or one for all; see
  [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).
  When `split` is not given, every item goes in `"dev"`.

- cluster:

  The cluster of each item, one per item or one for all. By default, the
  document.

- unanswerable:

  Which questions the document does not answer: `NULL` for none, a
  logical vector (one per question, or one for all), item ids, or
  positions.

## Value

An
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md).

## Details

Each item's payload, what an arm is given, is a list of `question` and
`document`. Its label is the list of acceptable answers, any one of
which an answer must contain to be right. An unanswerable item, one the
document does not answer, is labelled `"NOT_IN_DOCUMENT"`: the reader is
right when it says the document does not hold the answer. That an item
is unanswerable is held in its label alone, so an arm cannot read it
from the payload. An answer given as `"NOT_IN_DOCUMENT"` marks its item
unanswerable too. An item that is neither unanswerable nor given an
answer has no label, and every run on it is scored `NA`.

Items are clustered by document by default, since questions about one
document share its errors: a document given as a path or address is its
own cluster name, and text or chunks are named by a hash of their
content.

## See also

[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)

Other harness:
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md),
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md),
[`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md),
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md),
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md),
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md),
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)

## Examples

``` r
ref <- gr_qa_reference(
  questions = c(revenue = "What was revenue in 2024?",
                units = "How many units did Sheffield produce?",
                ceo = "Who is the chief executive?"),
  documents = gr_example(),
  answers = list(c("45.2 million", "45,200,000"), "12,400", NA),
  unanswerable = "ceo", split = "test")
ref
#> <hr_reference> 3 item(s) in 1 cluster(s)
#>   splits: test 3 
#>   hash: 5a83551bcb88
ref$labels$ceo
#> [1] "NOT_IN_DOCUMENT"
```
