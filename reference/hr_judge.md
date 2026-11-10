# Judge candidates with a model, in more than one order

Asks a model to choose between candidates (`"select"`), to compare two
(`"pairwise"`) or to grade one against a reference (`"grade"`), once per
presentation order, and combines the verdicts. The candidates are shown
under the letters A, B, ... only; their names, and so their source, are
not sent. With `orders = 2` the order is swapped on the second request
(see
[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md));
when the verdicts, mapped back to the candidates they name, differ
between orders, the result is `"unresolved"` with
`degradation = "judge_inconsistent"`, never a pick. Position bias of
this kind is common in model judges (Zheng et al. 2023; Wang et al.
2024).

## Usage

``` r
hr_judge(
  candidates,
  client,
  mode = c("select", "grade", "pairwise"),
  reference = NULL,
  model = NULL,
  orders = 2,
  rubric,
  schema = NULL,
  trace = NULL,
  governor = NULL,
  draw_index = 0L
)

# S3 method for class 'hr_judgement'
print(x, ...)
```

## Arguments

- candidates:

  The candidates, a character vector (or a list of single strings).
  Names, when every candidate has a distinct one, identify them in
  `value`; otherwise their positions do. `"select"` takes 2 to 26,
  `"pairwise"` exactly 2 and `"grade"` exactly 1.

- client:

  A `gr_client`.

- mode:

  `"select"`, `"grade"` or `"pairwise"`.

- reference:

  Text the judge sees beside the candidates: evidence or a reference
  answer. Required for `"grade"`.

- model:

  The judge's model; the client's model when `NULL`.

- orders:

  Presentation orders. See
  [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md).

- rubric:

  What the judge decides, in words.

- schema:

  `NULL`, or a reply schema with a string `verdict` property.

- trace:

  Optional `gr_trace` of the run being judged.

- governor:

  Optional
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  for the judge's requests.

- draw_index:

  Draw index passed to every request (see
  [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)).

- x:

  An `hr_judgement`.

- ...:

  Ignored.

## Value

An object of class `hr_judgement`, a list with

- `value`:

  The verdict: the chosen candidate's name (or position) for `"select"`,
  that or `"tie"` for `"pairwise"`, the grade for `"grade"`; `NA` unless
  `outcome` is `"answered"`.

- `outcome`:

  `"answered"`, `"unresolved"` or `"failed"`.

- `verdicts`:

  A data frame with one row per order: `order`, `shown` (the candidates
  in the order shown, or `"reference,response"`), `label`, `ok`,
  `verdict` (as the judge gave it), `value` (mapped back to a
  candidate), `reason` and `error`.

- `degradation`:

  `"judge_inconsistent"` when unresolved, else `NA`.

- `swap_checked`:

  `FALSE` when only one order was asked.

- `judge_cost`:

  A list of `usd` (`NA` when the model has no price), `tokens_in`,
  `tokens_out` and `calls`, over the judge's own requests.

- `mode`, `model`, `candidates` (the ids), `config_hash`:

  What was judged and under which configuration.

- `trace`:

  The judge's own `gr_trace`.

## Details

Every request goes through
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)'s
path, so the governor checks it before it is sent, a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
keys it with `draw_index`, and the trace records it, under the label
`judge.<mode>.o<k>` for order k. The requests are recorded in a trace of
the judge's own (`$trace`), never in `trace`, and their cost is reported
in `$judge_cost`, so a run's cost never includes the judging of it. When
`trace` is given, the judge is held to what that run's governor has left
(calls, dollars and tokens) and a local note naming the judge's trace
and cost is added to it. `governor`, if given, is used instead.

A failed request, or a reply with no allowed verdict, makes the result
`"failed"`.

## References

Wang, P., Li, L., Chen, L., Cai, Z., Zhu, D., Lin, B., Cao, Y., Kong,
L., Liu, Q., Liu, T. and Sui, Z. (2024). Large language models are not
fair evaluators. *Proceedings of ACL 2024*, 9440-9450.

Zheng, L., Chiang, W.-L., Sheng, Y., Zhuang, S., Wu, Z., Zhuang, Y.,
Lin, Z., Li, Z., Li, D., Xing, E. P., Zhang, H., Gonzalez, J. E. and
Stoica, I. (2023). Judging LLM-as-a-judge with MT-Bench and Chatbot
Arena. *Advances in Neural Information Processing Systems* 36.

## See also

[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

Other judges:
[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md),
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md),
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md),
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)

## Examples

``` r
# A judge that always picks the candidate naming Paris.
fair <- gr_mock_client(function(messages, params) {
  txt <- messages[[2]]$content
  pick <- if (grepl("Candidate A:\nParis", txt, fixed = TRUE)) "A" else "B"
  sprintf('{"verdict": "%s", "reason": "It names the capital."}', pick)
})
j <- hr_judge(c(first = "Paris", second = "Lyon"), fair, mode = "select",
              rubric = "Which candidate names the capital of France?")
j$value
#> [1] "first"
j$verdicts[, c("order", "shown", "verdict", "value")]
#>   order        shown verdict value
#> 1     1 first,second       A first
#> 2     2 second,first       B first

# A judge that always says "A" follows the position, so it is unresolved.
first <- gr_mock_client(function(messages, params) '{"verdict": "A", "reason": "."}')
hr_judge(c("Paris", "Lyon"), first, mode = "select",
         rubric = "Which candidate names the capital of France?")$outcome
#> [1] "unresolved"
```
