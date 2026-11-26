# Measuring and comparing configurations

Every choice in a pipeline (the recipe, the model, the prompt, the
reasoning effort) changes the answers, and one run on one document
cannot tell you by how much. A model asked the same question five times
can answer it five ways. Ten questions about one report share that
report’s quirks, so they are closer to one observation than to ten.

[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
shows what each recipe does to one document, and its output is
descriptive only. With the functions in this guide you answer the next
question: on a labelled set of questions, is configuration A more
accurate than B, by how much, at what cost, and how sure can you be?

The sections follow the order of the work: a reference set and its
splits, the arms to compare and the rule that scores them, a benchmark
held to one spending limit, the report and how to read it, planning the
size of a comparison before you run it, judges, baselines that use no
model, drift, and the signals the package records about its own work.
The statistics functions underneath come last. Measuring a screener
against people, several reviewers and agreement between extraction
tables belong to a review, so
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
covers them.
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
puts these functions to work on worked comparisons of readers,
segmenters, settings, screening and judges.

## Setting up

Every example runs offline.
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
stands in for the model, and `embedder = "lexical"` keeps retrieval free
and deterministic. The setup gives two mock model ids prices, so the
benchmarks below have a cost to compare: `mock-small` at \$0.20 and
\$0.80 per million input and output tokens, and `mock-large` at ten
times that.

``` r

library(harnessr)
old <- hr_options(verbose = FALSE, embedder = "lexical")

hr_register_model("mock-small", context_window = 128000, max_output = 4096,
                  input_usd = 0.2, output_usd = 0.8)
hr_register_model("mock-large", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)
```

## References and splits

A reference is the labelled set you score every configuration on. Each
item has a payload (what the configuration is given), a label (what
counts as right), a cluster and a split. The cluster is the unit whose
items share errors, usually the document. Eight questions about one
report are not eight independent observations, and every interval in
this guide is computed with that in mind.
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
builds a reference from any items.
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
builds one from questions about documents, with each question’s
acceptable answers:

``` r

reports <- c(
  north = "The northern region. Revenue was 45.2 million dollars in fiscal 2024. The plant in Leeds made 12,400 units.",
  south = "The southern region. Revenue was 51.8 million dollars in fiscal 2025. Staff numbered 310 at year end.",
  east  = "The eastern region. Revenue was 38.9 million dollars in fiscal 2024. The chair is Ana Ruiz.",
  west  = "The western region. Revenue was 29.4 million dollars in fiscal 2023. Exports rose 7 percent.")

qa <- gr_qa_reference(
  questions = c(n_rev = "What was revenue?", n_units = "How many units did Leeds make?",
                s_rev = "What was revenue?", s_staff = "How many staff were there?",
                e_rev = "What was revenue?", e_ceo = "Who is the chief executive?",
                w_rev = "What was revenue?", w_exp = "By how much did exports rise?"),
  documents = rep(unname(reports), each = 2),
  answers = list("45.2 million", c("12,400", "12400"), "51.8 million", "310",
                 "38.9 million", NA, "29.4 million", "7 percent"),
  unanswerable = "e_ceo",
  cluster = rep(names(reports), each = 2),
  split = "test")
qa
#> <hr_reference> 8 item(s) in 4 cluster(s)
#>   splits: test 8 
#>   hash: d64da50d3779
```

The eastern report names a chair and no chief executive, so `e_ceo` is
marked unanswerable. Its label is the not-found answer, and a reader is
right on it only when it says the document does not hold the answer. The
flag goes into the label alone. The payload holds the question and the
document, so a configuration cannot tell which questions have no answer.
Without such items, a reference never tests whether a reader can tell
that an answer is missing.

An item with neither an answer nor the unanswerable flag has no label.
Every run on it is scored `NA`, so it never counts for or against an
arm.

A benchmark locks a reference once it starts scoring it. From then on
[`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
refuses to add items to the reference, or to any copy of it, with an
error of class `hr_reference_locked`, so no one can add an item after
seeing the results. The reference also carries a SHA-256 hash of its
content, and the benchmark checks that hash.

Splits keep tuning apart from evidence:

- `dev` is for tuning prompts, settings and margins, and its scores are
  never reported.
- `exploratory` holds early experiments.
- `calibration` is for fitting signal thresholds (below).
- `test` holds the items reported comparisons are scored on.
- `final`, if used, is held back and run once per release.

[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
assigns whole clusters, so no document has questions on both sides of a
tuning and a scoring split:

``` r

questions <- data.frame(
  item_id  = sprintf("q%03d", 1:120),
  document = rep(sprintf("report%02d.pdf", 1:30), each = 4),
  question = rep(c("What was revenue?", "Who audited the accounts?",
                   "How many staff were there?", "When did the year end?"), 30))
sp <- hr_assign_splits(questions, seed = 2026)
sp
#> <hr_splits> 120 item(s) in 30 cluster(s), method stable, seed 2026
#> 
#>        split target clusters items cluster_share item_share
#>          dev    0.1        4    16         0.133      0.133
#>  exploratory    0.1        3    12         0.100      0.100
#>  calibration    0.3       10    40         0.333      0.333
#>         test    0.5       13    52         0.433      0.433
```

The default shares are 10% dev, 10% exploratory, 30% calibration and 50%
test. The SHA-256 digest of the seed and a cluster’s id sets that
cluster’s split, so row order and the session’s random state do not
change it. With the default `method = "stable"`, adding or dropping a
document never moves another. In exchange, the shares hold only on
average: 13 of these 30 documents went to test, not 15.

`method = "balanced"` gives each split its share of whole clusters. A
document added later can then shift others across a boundary, so draw
the splits once and store them:

``` r

hr_assign_splits(questions, seed = 2026, method = "balanced")$counts[, c("split", "clusters", "items")]
#>         split clusters items
#> 1         dev        3    12
#> 2 exploratory        3    12
#> 3 calibration        9    36
#> 4        test       15    60
```

With very few documents, a split given a share can receive no cluster,
and
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
then warns with class `hr_empty_split`.

### Label sheets

Labels come from people.
[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
writes a CSV with one row per item, the columns a person needs to judge
it and empty columns for their decisions, plus an instructions file
beside it. It writes six kinds: `"qa"`, `"screening"`, `"extraction"`,
`"calibration"`, `"judge"` and `"pairwise"` (two texts in a blinded
order, for a pairwise judge;
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md)
has one). Sheets are blind by default: a blind sheet copies only those
columns, so a model’s answer in `items` stays out of it:

``` r

to_label <- head(sp$items, 3)
to_label$model_answer <- c("45.2 million", "Not stated", "310")

path <- file.path(tempdir(), "qa-labels.csv")
sheet <- gr_label_sheet("qa", to_label, path = path)
names(sheet)
#> [1] "item_id"    "document"   "question"   "answerable" "answer"    
#> [6] "quote"      "note"
```

The person fills `answerable`, `answer` and `quote`.
[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
reads the sheet back, checks every value and id, and joins the items’
other columns by `item_id`. It renames a column that clashes with a
decision column, so a model’s `answer` here would come back as
`model_answer`:

``` r

filled <- read.csv(path, fileEncoding = "UTF-8-BOM")
filled$answerable <- c("yes", "no", "yes")
filled$answer <- c("45.2 million dollars", NA, "310")
write.csv(filled, path, row.names = FALSE, na = "")

gr_read_labels(path, "qa", items = to_label)[, c("item_id", "answerable", "answer",
                                                  "split", "model_answer")]
#>   item_id answerable               answer split model_answer
#> 1    q001       TRUE 45.2 million dollars   dev 45.2 million
#> 2    q002      FALSE                 <NA>   dev   Not stated
#> 3    q003       TRUE                  310   dev          310
```

A value it cannot read stops it with an error of class `gr_bad_labels`.
The error lists every bad value at once, each with the sheet, the row
number as a spreadsheet counts it, and the item:

``` r

filled$answer[2] <- "Smith & Co"
write.csv(filled, path, row.names = FALSE, na = "")
tryCatch(gr_read_labels(path, "qa", items = to_label),
         gr_bad_labels = function(e) cat(conditionMessage(e)))
#> 1 value(s) in the qa sheet cannot be read:
#> qa-labels.csv row 3 (item 'q002'): `answerable` is no but `answer` is filled; clear one of them.
```

With `reviewers = k`, each person gets a sheet of their own and sees no
one else’s decisions.
[`?gr_label_sheet`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
gives the number of items each kind of set needs for the package’s own
evaluation: about 480 questions over 88 documents for question
answering.

## Arms and scorers

An arm is one configuration to compare: a function of an item and a
context that returns the arm’s output for that item. `ctx` carries the
benchmark’s client, a trace of this run alone, the governor the run is
held to and the run’s `draw_index`. `ctx$call()` is
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
with the client, the trace and the draw index filled in. Send every
request an arm makes through that trace: the benchmark counts the run’s
tokens and dollars there and holds the run to the limit through it:

``` r

ask <- function(name, model) {
  hr_arm(name, function(item, ctx) {
    ctx$call(paste("Item", item), model = ctx$params$model)$text
  }, params = list(model = model))
}
ask("large", "mock-large")
#> <hr_arm large> version 0.0.1
#>   params: model = mock-large 
#>   hash: 4a659e23a5b4
```

The arm records a SHA-256 hash of its name, code, settings and
`version`. The hash covers the code as text plus the values it names
from the environment it was made in, the workspace included. An arm
written at top level that reads a global prompt therefore gets a new
hash when the prompt changes. The same arm has the same hash in every
session and after [`saveRDS()`](https://rdrr.io/r/base/readRDS.html).
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
refuses an arm edited after it was built instead of running it under its
old name. Change `version` when the arm’s behaviour changes.

[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
wraps a reading recipe as an arm, and
[`gr_arms()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
builds one per recipe. Each run reads the item’s document with
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
or with
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
when the document is already chunked, and returns the `gr_answer`.
`settings` takes what
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
takes in `...`. Here the settings make one recipe into two arms on two
models:

``` r

arms <- list(gr_arm("fast", settings = list(model = "mock-small"), name = "small"),
             gr_arm("fast", settings = list(model = "mock-large"), name = "large"))
```

A [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
takes the package version as its version, since readers and prompts
change between releases. Every request of a run carries the run’s draw
index, segmenter and reader requests included. If the run’s limits leave
a reader too little room to start, the reader returns a partial
not-found answer that notes the limit, and that answer is scored as a
budget stop, not an error.

A scorer turns an output and a label into `correct`, an `outcome` (what
it compared) and a `failure_kind` saying why a wrong output was wrong:
`"parse_failure"`, `"refusal"`, `"not_in_document"`, `"wrong"`,
`"budget_stop"` or `"error"`.
[`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
the default, compares text after folding case and white space. For
reading recipes, use
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md).
It counts an answer right when the answer contains any acceptable
answer, after folding case, white space and thousands separators.
Numbers are matched whole: `"12"` is not found in `".12"` or `"-12"`,
but is found in `"12-15"`, and `"45.2"` in `"45.2m"`:

``` r

s <- gr_scorer_answer()
item <- list(question = "How many units?", document = gr_example())
s$fn(item, "Leeds made 12,400 units.", "12400")$correct
#> [1] TRUE
s$fn(item, "Leeds made 112,400 units.", "12400")$correct
#> [1] FALSE
s$fn(item, "Revenue was 45.2 million dollars.", "12400")$failure_kind
#> [1] "wrong"
```

On an unanswerable item it counts an answer right when
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
is `TRUE` and no limit or refusal stopped the run, since a reader that
ran out of budget did not look. To write your own scorer, pass a
function of `(item, output, label)` to
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md);
its help has one that accepts a number within 1% of the label.

## Running a benchmark

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
runs every arm on every item of the chosen splits `runs` times, scores
each output, and returns one row per cluster, item, arm and run. The
stand-in model below knows each report’s facts. Asked as `mock-small`,
it replies that the report is unclear on 30% of requests; asked as
`mock-large`, it never does:

``` r

facts <- list(
  northern = c(revenue = "Revenue was 45.2 million dollars.", units = "Leeds made 12,400 units."),
  southern = c(revenue = "Revenue was 51.8 million dollars.", staff = "There were 310 staff."),
  eastern  = c(revenue = "Revenue was 38.9 million dollars."),
  western  = c(revenue = "Revenue was 29.4 million dollars.", exports = "Exports rose 7 percent."))

cl <- hr_mock_client(function(messages, params) {
  seen <- paste(vapply(messages, function(m) as.character(m$content), ""), collapse = " ")
  region <- regmatches(seen, regexpr("(northern|southern|eastern|western)", seen))
  asked <- sub(".*Question", "", seen)
  topic <- c("revenue", "units", "staff", "exports")
  hit <- topic[vapply(topic, grepl, logical(1), x = asked, ignore.case = TRUE)][1]
  reply <- facts[[region]][hit]
  if (is.na(reply)) return("NOT_IN_DOCUMENT")
  if (identical(params$model, "mock-small") && runif(1) < 0.3) return("The report is unclear.")
  reply
})

bench <- hr_benchmark(arms, qa, runs = 5, client = cl, scorer = gr_scorer_answer())
bench
#> <hr_bench> 2 arm(s) x 8 item(s) in 4 cluster(s) x 5 run(s); split test; scorer answer_contains
#>  arm   accuracy runs wrong failed budget_stop usd   
#>  small 0.750    40   10    0      0           0.0013
#>  large 1.000    40    0    0      0           0.0132
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
head(bench[, c("item", "arm", "run", "correct", "failure_kind", "usd", "draw_index")])
#>    item   arm run correct failure_kind      usd draw_index
#> 1 n_rev small   1   FALSE        wrong 3.10e-05          1
#> 2 n_rev small   2    TRUE         <NA> 3.42e-05          2
#> 3 n_rev small   3    TRUE         <NA> 3.42e-05          3
#> 4 n_rev small   4    TRUE         <NA> 3.42e-05          4
#> 5 n_rev small   5   FALSE        wrong 3.10e-05          5
#> 6 n_rev large   1    TRUE         <NA> 3.42e-04          1
```

The printed accuracy is the mean over runs within each item, then over
items. It is descriptive and has no interval. The arms run under a
private random stream started from `seed` (1 by default), so the mock’s
[`runif()`](https://rdrr.io/r/stats/Uniform.html) gives the same draws
every time this guide is built, and the caller’s random state is left as
it was. Rows on the dev split are marked `reportable = FALSE` and
printed apart.

Five runs is the default and the expected minimum. Fewer warns with
class `hr_few_runs`, because with fewer runs you cannot tell the spread
from run to run apart from the difference between arms.

### One limit for the whole benchmark

The whole benchmark is one run under one
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md).
Each run’s trace is held to the governor’s limits less what the runs
before it used, so the limit you set is the most the whole comparison
can spend. With `governor = NULL` the limits come from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md),
and its default of 400 calls is easy to exceed: two arms on 300 items
for 5 runs make 3000 calls. A run stopped by a refused request is
recorded as a `"budget_stop"` and counted wrong. The runs after it still
start, so every row exists and you can see the refusals:

``` r

capitals <- hr_reference(items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
                         labels = c("Paris", "Lima", "N'Djamena", "Suva"),
                         cluster = c("a", "a", "b", "b"), split = "test")
atlas <- c(France = "Paris", Peru = "Lima", Chad = "N'Djamena", Fiji = "Suva")
geo <- hr_mock_client(function(messages, params) atlas[[sub("Capital of ", "", messages[[1]]$content)]])
capital <- hr_arm("capital", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)

short <- hr_benchmark(capital, capitals, runs = 5, client = geo,
                      governor = hr_governor(max_calls = 6))
#> Warning in warn_budget_stops(out, stop_limit, governor, from_options): 14 of 20
#> runs were stopped by the benchmark's limits (calls: 14). All of them are
#> counted wrong in the accuracy, intervals and comparisons. The first was item
#> 'q2', arm 'capital', run 2.
table(short$failure_kind, useNA = "ifany")
#> 
#> budget_stop        <NA> 
#>          14           6
```

The first six runs got answers. The governor refused the other fourteen
before anything was sent. Whenever a limit stops a run,
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
warns with class `hr_budget_stopped` and gives the number stopped, the
limit that stopped them, how many of them count against an arm and the
first run stopped. When the limits came from
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md),
the warning gives the values of the options that stopped runs and says
to pass a governor sized for the benchmark.

### Repeated runs must be repeated draws

Run `r` gets `ctx$draw_index = r`, and its `ctx$trace` carries `r`, so
`ctx$call()` and every stage called with `trace = ctx$trace` send their
requests at the run’s draw. Under an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
each run is its own cache entry, and under an
[`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
its own recorded draw. The recorded draw also names the arm, so a replay
answers each arm with its own replies, whether it replays every arm or a
few, in any order.

Five runs answered from one stored reply would agree perfectly and
measure nothing.
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
therefore refuses an arm whose runs come back as copies, with an error
of class `hr_duplicate_draw`. An arm that sends every run’s request at
one fixed draw index is such an arm:

``` r

cache <- hr_cache()
cached <- hr_cache_client(geo, cache)
invisible(hr_benchmark(capital, capitals, runs = 5, client = cached))

fixed_draw <- hr_arm("fixed_draw", function(item, ctx) {
  hr_call(ctx$client, paste0("Capital of ", item), trace = ctx$trace,
          draw_index = 1)$text
})
tryCatch(hr_benchmark(fixed_draw, capitals, runs = 5, client = cached),
         hr_duplicate_draw = function(e) class(e)[1])
#> [1] "hr_duplicate_draw"
```

A cache still saves requests. Run the `capital` benchmark again under
the same cache and it sends no request and costs nothing, since each run
is answered from its own entry. An
[`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
keeps no cache, so under it the `fixed_draw` arm is not refused; under a
cache it is.

## Reading the report

[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
turns the reportable rows into accuracy per arm with intervals that keep
clusters together, paired differences, stability, reliability, cost and
failures. `B` sets the number of cluster bootstrap resamples, 2000 by
default. This guide uses fewer so it builds quickly.

``` r

rpt <- hr_report(bench, B = 200)
rpt
#> <hr_bench_report> 2 arm(s), 8 item(s) in 4 cluster(s), 5 run(s)
#> Intervals: cluster-robust t on the logit scale, C - 1 df at 95% (8 items in 4 clusters fall short of 300 items and 30 clusters).
#> 
#> Accuracy (arms in benchmark order, not ranked):
#>  arm   accuracy interval       rank_interval
#>  small 0.750    [0.648, 0.830] 2-2          
#>  large 1.000    [0.561, 1.000] 1-1          
#> 
#> Paired differences (first minus second):
#>  contrast      difference interval         simultaneous    
#>  small - large -0.250     [-0.342, -0.158] [-0.342, -0.158]
#> 
#> Stability across runs:
#>  arm   flip_rate TARa  run_sd
#>  small 0.750     0.250 0.153 
#>  large 0.000     1.000 0.000 
#> 
#> Reliability:
#>  arm   pass^1 pass^3 pass^5
#>  small 0.750  0.425  0.250 
#>  large 1.000  1.000  1.000 
#> 
#> Cost:
#>  arm   usd_per_item usd_per_correct interval               tokens_per_item
#>  small 3.24e-05     4.32e-05        [3.946e-05, 4.733e-05] 127.9          
#>  large 0.000331     0.000331        [0.0003192, 0.0003405] 128.8          
#>  estimated       on_frontier frontier_share
#>  100.000% (flag) yes         1.000         
#>  100.000% (flag) yes         1.000         
#> 
#> Failures (all counted wrong):
#>  arm   wrong without_parse_refusal
#>  small 10    0.750                
#>  large  0    1.000                
#> 
#> Variance on the probability scale: within-item runs 0.075, between items 0.019, within share 0.800.
#> Note: More than 5% of the cost of small, large rests on estimated token counts; read its cost as approximate. 
#> Note: Run-to-run variance is 80% of the total, above 10%: use runs = 10. 
#> Note: Cost, pass^k, frontier share and rank intervals come from the cluster bootstrap, which can undercover below 300 items or 30 clusters; read them as rough. 
#> Note: Accuracy of large is 0, 1 or the same in every cluster, where the t interval is not defined; its interval is Korn and Graubard's, one-sided from 0 or 1 at those bounds. 
#> Note: The frontier share (how often an arm is on the cost-accuracy frontier over resamples) is an extension, not a published standard.
```

With `method = "auto"`,
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
picks the interval from the size of the benchmark, and the second line
of the print names it and says why. With at least 300 items and at least
30 clusters, `method = "auto"` uses a studentised cluster bootstrap:
each resample draws whole clusters with all their items, runs and arms.
Below either threshold, as here, it uses a cluster-robust t interval on
the logit scale, with t quantiles on C - 1 degrees of freedom for C
clusters.

Neither interval is defined when accuracy is 0 or 1 or the same in every
cluster. The arm then gets Korn and Graubard’s interval, one-sided from
that bound, and a note says so. That is why `large` reads \[0.561,
1.000\] with four clusters behind it. No interval treats items or runs
as independent trials. `method = "exact"` (Clopper-Pearson on the
effective number of items) and `method = "bayes"` (a beta-binomial model
with a cluster random effect) are there on request.

These defaults come from simulation. In `dev/sim-coverage.R` (2000
replicates) the studentised bootstrap covered 95.5% and 95.0% with 386
items in 40 clusters, where the BCa bootstrap it replaced covered 93.5%.
The cluster-robust t interval covered 95.7% and 95.8% with 50 items in
10 clusters. The workflow `validation.yaml` reruns that simulation, and
the one behind
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
every night.

Paired differences are taken item by item, so each one compares the arms
on the same question. Each difference gets a cluster-robust t interval
at every size, with simultaneous intervals over all pairs beside it. The
report lists arms in benchmark order and does not rank them. The rank
interval shows how much the order could change over resamples: `small`
and `large` here rank 2 and 1 in every one.

The stability rows compare each arm with itself:

- the flip rate is the share of items whose correctness changed between
  runs;
- TARa is the share whose scored output was the same on every run;
- `run_sd` is the spread of whole-run accuracy.

`small` flips on 75% of its items, and an accuracy of 0.750 alone would
hide that. Reliability is pass^k, the chance that k runs drawn from an
item’s runs are all right, estimated without bias. Here an arm right 75%
of the time is right on all five runs of an item only 25% of the time.

Cost comes in dollars and tokens per item and per correct item, since a
cheap arm that is often wrong can cost more per right answer than it
looks. The report flags an arm when more than 5% of its spend rests on
estimated token counts. The mock reports no token counts, so both arms
are flagged here. The frontier is the set of arms no other arm beats on
both dollars per item and accuracy, with each arm’s share of resamples
on it.

Failures are counted by kind, and every one counts as wrong. Beside
them, the report gives accuracy recomputed without parse failures and
refusals. The variance line splits the spread into within-item (run to
run) and between-item parts. When runs account for more than 10% of it,
as here at 80%, the report says to use 10 runs.

With fewer than 5 runs the report is descriptive only: point estimates
and no intervals. The report refuses an item scored on some runs and not
others. The returned list holds every part (`rpt$accuracy`,
`rpt$contrasts`, `rpt$pass_k`, `rpt$cost`, `rpt$frontier`,
`rpt$failures`, `rpt$variance`, `rpt$notes`), and
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
writes it out.

### Errors the arms share

**What it controls.**
[`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md)
measures how far the arms’ errors go together. It gives the phi
coefficient between each pair’s errors within strata of item difficulty
(`n_strata`, or your own `strata`), the share of items both got wrong
where they gave the same wrong answer, and a sample of `n_check` items
every arm got wrong, for a person to read. Two arms with good accuracy
that fail on the same items gain little from being combined, or from
checking each other. The function reads the benchmark’s rows (with
`held_out = TRUE`, only those that count as evidence) and sends nothing.
It does not compute Yen’s Q3, the residual correlation of an item
response model, since that needs a mixed-model package harnessr does not
depend on.

**Signs it needs reading.** A plan to vote across arms, to use one arm
to check another, or to call two arms’ agreement a sign of being right;
or a benchmark where most errors fall on a few items.

**Where the defaults came from.** Three difficulty strata, a sample of
ten and reading only held-out rows were set when the metric was added
and have not been compared. `strata = NULL` reads difficulty from the
same runs, and `seed` only makes the hand-check sample repeatable. All
five are `untested`.

**How to test it.** Here three arms share a blind spot on the first
three items and each also fails items of its own, built with
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md):

``` r

truth <- hr_reference(sprintf("q%02d", 1:12), labels = rep("yes", 12),
                      cluster = sprintf("c%02d", 1:12), split = "test")
blind <- function(every) {
  hr_arm(paste0("every-", every), function(item, ctx) {
    n <- as.integer(sub("q", "", item))
    if (n <= 3 || n %% every == 0) "no" else "yes"
  }, params = list(every = every))
}
eb <- hr_benchmark(hr_sweep(blind, list(every = c(4, 5, 6))), truth, runs = 5,
                   client = NULL)
ec <- hr_error_correlation(eb, n_strata = 1)
ec$pairs[, c("arm_a", "arm_b", "phi_pooled", "both_wrong", "same_wrong_rate")]
#>             arm_a           arm_b phi_pooled both_wrong same_wrong_rate
#> 1 every-4:every=4 every-5:every=5  0.1690309          3               1
#> 2 every-4:every=4 every-6:every=6  0.5070926          4               1
#> 3 every-5:every=5 every-6:every=6  0.3142857          3               1
ec$check
#>   item every-4:every=4 every-5:every=5 every-6:every=6
#> 1  q01              no              no              no
#> 2  q02              no              no              no
#> 3  q03              no              no              no
```

Every pair is positively correlated, and every pair that is wrong
together gives the same wrong answer, “no”. Most of that comes from the
three items every arm gets wrong. With difficulty strata
(`n_strata = 3`, the default), the function cuts the items by the share
of runs that got them wrong:

``` r

ec3 <- hr_error_correlation(eb)
table(ec3$strata)
#> 
#> 1 3 
#> 8 4
ec3$phi[, c("arm_a", "arm_b", "stratum", "items", "both_wrong", "phi")]
#>             arm_a           arm_b stratum items both_wrong        phi
#> 1 every-4:every=4 every-5:every=5       1     8          0 -0.3333333
#> 2 every-4:every=4 every-5:every=5       3     4          3         NA
#> 3 every-4:every=4 every-6:every=6       1     8          0 -0.2182179
#> 4 every-4:every=4 every-6:every=6       3     4          4         NA
#> 5 every-5:every=5 every-6:every=6       1     8          0 -0.2182179
#> 6 every-5:every=5 every-6:every=6       3     4          3         NA
```

Tied shares leave two strata, not three. Stratum “3” holds q01 to q03
and q12, which every-4 and every-6 get wrong as well. In it, one arm of
each pair is wrong on all four items (every-5 is right on q12, but its
partner is not), so phi there is undefined. The pooled phi then reads
only the eight items of stratum “1”, where each arm’s errors fall on
items of its own, and it comes out negative.

### What a reader keeps: `gr_condensation_check()`

A reader that carries a running draft through a document, as `refine`
does, condenses as it goes. It can lose an early fact, take a value from
a near-namesake, or keep a figure the document later corrected.
[`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
builds a benchmark that measures each of these without a model judge. In
a document (synthetic filler, or a text of your own) it:

- plants facts, each with a question whose answer is the planted value;
- plants lures, the same measure for a near-namesake with another value;
- states one fact wrongly near the start and corrects it near the end.

Each document is given forwards and reversed by paragraph
([`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md)),
so the reverse reader meets first the fact the forward reader meets
last.

``` r

chk <- gr_condensation_check(n_facts = 4, n_lures = 1, paragraphs = 8)
chk
#> <gr_condensation_check> 1 document(s), forward and reversed, 8 item(s)
#>   per order: 2 fact, 1 lure, 1 correction
chk$items[chk$items$order == "forward", c("kind", "question", "answer", "lure", "superseded")]
#>         kind                                              question answer  lure
#> 1       lure      What was the floor area of the Northgate clinic?  3,565 4,120
#> 2       fact How many yearly visits did the Riverside school have? 10,237  <NA>
#> 3       fact        What was the budget of the Elm Street library?   42.5  <NA>
#> 4 correction       What was the staff count of the Westfield mill?    321  <NA>
#>   superseded
#> 1       <NA>
#> 2       <NA>
#> 3       <NA>
#> 4        264
```

The two arms below differ in how they carry the document: a running
draft or a ledger of findings. Here a stand-in model plays a reader
whose draft takes the lure’s value and keeps the superseded figure,
while a ledger of findings does neither. On a real model the same code
measures what each one does.

``` r

facts <- chk$items
condenser <- hr_mock_client(function(messages, params) {
  text <- vapply(messages, function(m) m$content, "")
  if (grepl("Reply with the edits", text[length(text)], fixed = TRUE)) return("ADD: noted.")
  asks <- text[startsWith(text, "Question: ")]
  row <- facts[facts$question == sub("^Question: ", "", asks[length(asks)]), ][1, ]
  ledger <- any(grepl("<findings>", text, fixed = TRUE))
  if (!ledger && row$kind == "lure") return(paste("It was", row$lure))
  if (!ledger && row$kind == "correction") return(paste("It was", row$superseded))
  paste("It was", row$answer)
})
arms <- hr_sweep(gr_arm("thorough", list(reader = "refine", method = "paragraph")),
                 list(refine_state = c("draft", "ledger")))
cb <- hr_benchmark(arms, chk$reference, runs = 5, client = condenser, scorer = chk$scorer)
gr_condensation_summary(chk, cb)
#>                            arm    order fact_recall lure_rate correction_won
#> 1  thorough:refine_state=draft  forward         0.5         1              0
#> 2  thorough:refine_state=draft reversed         0.5         1              0
#> 3 thorough:refine_state=ledger  forward         1.0         0              1
#> 4 thorough:refine_state=ledger reversed         1.0         0              1
#>   late_recall runs
#> 1         0.5   20
#> 2         0.5   20
#> 3         1.0   20
#> 4         1.0   20
```

In the summary:

- `fact_recall` is the share of runs whose answer holds the planted
  value;
- `lure_rate` is the share of runs on lure items whose answer holds the
  lure’s;
- `correction_won` is the share of runs on the corrected fact that give
  the new figure and not the old;
- `late_recall` is fact recall over the facts in the last third of the
  document as it was read.

The check’s `reference` and `scorer` are ordinary ones, so
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
reads the same benchmark with intervals.

## Planning the size, and non-inferiority

Often you want to know whether a cheaper arm is worse than the one in
use by more than a margin you can live with. That is a non-inferiority
test. Whether a benchmark can answer that depends on its size, so check
the size before anyone labels 500 questions.

[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
gives the smallest paired difference a clustered design can detect. It
needs the number of items and clusters, the intra-cluster correlation of
the paired item difference (ICC_D, taken from a pilot on the dev split)
and the share of items on which the arms disagree (`p_disc`). For 480
questions over 80 documents:

``` r

hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2)
#> <hr_mdd> 8.2 points at 80% power, one-sided alpha 0.025
#>   480 items in 80 clusters (m = 6, 6 after cv 0), ICC_D 0.2: DE 2, n_eff 240
#>   p_disc 0.2
hr_mdd(480, n_clusters = 80, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#> <hr_mdd> 10.7 points at 80% power, one-sided alpha 0.002778 (0.025 / 9 contrasts, Holm worst case)
#>   480 items in 80 clusters (m = 6, 6 after cv 0), ICC_D 0.2: DE 2, n_eff 240
#>   p_disc 0.2
```

Questions in one document count for less than independent ones: the
design effect DE = 1 + (m - 1) x ICC_D is 2 here, so 480 questions carry
the information of 240. With nine confirmatory contrasts, Holm’s first
step tests at 0.025 / 9, and the detectable difference grows from 8.2 to
10.7 points.
[`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
works the other way and gives the items needed for a margin:

``` r

hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#> <hr_n_needed> 8.0 points at 80% power, one-sided alpha 0.002778 (0.025 / 9 contrasts, Holm worst case)
#>   n_eff 419 effective items; DE 2, so 840 items in 140 clusters of 6
```

Both use t quantiles on C - 1 degrees of freedom, the ones the report
tests with. In the power simulation `dev/sim-power.R` the formula’s MDD
came within 0.25 points of the simulated one. With normal quantiles it
fell up to 0.41 points below it at 80 clusters, so both functions use t
quantiles.

[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
states a contrast: the new arm, the reference arm, the margin and
whether the new arm must also be cheaper.
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
fixes the contrasts against the reference before anything scores it.
[`?hr_contrast`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
suggests a margin of min(0.5 x M1, the loss you would accept in
practice), with M1 the reference arm’s advantage over a minimal baseline
in a pilot.

[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
refuses a confirmatory margin below the design’s MDD after Holm, with
class `hr_margin_below_mdd`, since such a margin claims more than the
items can show. `confirmatory = FALSE` registers it as exploratory
instead. It also refuses a reference a benchmark has already begun to
score, with class `hr_registration_after_scoring`.

``` r

n <- 300
ids <- sprintf("q%03d", 1:n)
docs <- rep(sprintf("doc%02d", 1:50), each = 6)
plan <- hr_reference(ids, labels = rep("yes", n), cluster = docs, split = "test")

design <- hr_mdd(n, n_clusters = 50, icc = 0.1, p_disc = 0.15)
reg <- hr_register_contrasts(plan, hr_contrast("small", "large", margin = 0.10), design)
reg
#> <hr_contrast_registration> 1 contrast(s), 1 confirmatory; registered 2026-11-26T06:50:57.469Z
#>  contrast       label        margin mdd cost_test
#>  small vs large confirmatory 10.0   7.8 yes      
#>   Margins and MDD in points; reference d453122a93af; hash 6b788533dba2
```

Here the stand-in model finds each item easier or harder by document and
by item, and `mock-small` is a little worse on every one. The governor
allows the 3000 calls the benchmark needs:

``` r

set.seed(11)
ease <- setNames(rnorm(50, 2, 1)[as.integer(factor(docs))] + rnorm(n, 0, 1.5), ids)
grader <- hr_mock_client(function(messages, params) {
  shift <- if (identical(params$model, "mock-small")) -0.3 else 0
  item <- sub("Item ", "", messages[[1]]$content)
  if (runif(1) < plogis(ease[[item]] + shift)) "yes" else "no"
})

trial <- hr_benchmark(list(ask("large", "mock-large"), ask("small", "mock-small")),
                      plan, runs = 5, client = grader,
                      governor = hr_governor(max_calls = 4000, max_cost_usd = 1))
ni <- hr_report(trial, B = 500, registration = reg)
ni$method_reason
#> [1] "300 items in 50 clusters reach 300 items and 30 clusters"
ni$ni[, c("new", "reference", "margin", "estimate", "lower", "cost_upper",
          "verdict", "mdd_design", "mdd_achieved")]
#>     new reference margin    estimate       lower cost_upper verdict mdd_design
#> 1 small     large    0.1 -0.05266667 -0.08118863  -4.32e-05    TRUE 0.07828581
#>   mdd_achieved
#> 1   0.04057211
```

With 300 items in 50 clusters the report switches to the studentised
bootstrap. A contrast holds only if the one-sided lower bound of the
accuracy difference is above -margin and, with the cost test, the upper
bound of the paired cost difference is below 0.

Here `small` is 5.3 points less accurate than `large`. Its lower bound
is -8.1 points, inside the margin of 10, and its cost bound is below 0,
so the verdict is `TRUE`. The accuracy bound is the cluster-robust t
bound of the paired differences, so at one-sided 0.025 it is the lower
end of the printed 95% contrast interval. Confirmatory contrasts are
tested with Holm’s step-down procedure. The report prints the design and
achieved MDD beside the verdict, with Tango’s paired score interval as a
cross-check that does not enter the verdict.

A report with a registration, or with `confirmatory = TRUE`, is
evidence.
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
then refuses any row from the dev, exploratory or calibration split with
class `hr_dev_not_evidence`. It refuses a registration edited after it
was made too, with class `hr_registration_changed`.

## Judges

Matching text cannot score some answers: a summary, an explanation, an
answer that is right in other words.
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
asks a model to choose between candidates (`"select"`), compare two
(`"pairwise"`) or grade one against a reference (`"grade"`). The model
sees the candidates under the letters A, B and so on, never their names,
and gets each item in two orders. A verdict that changes with the order,
once mapped back to the candidate it names, is `"unresolved"`, never a
pick. This stand-in always picks whatever is shown first:

``` r

first <- hr_mock_client(function(messages, params) '{"verdict": "A", "reason": "It is first."}')
j <- hr_judge(c(short = "Revenue was 45.2 million.", long = "Revenue was 51.8 million."),
              first, mode = "select", rubric = "Which candidate gives fiscal 2024 revenue?")
j$outcome
#> [1] "unresolved"
j$verdicts[, c("order", "shown", "verdict", "value")]
#>   order      shown verdict value
#> 1     1 short,long       A short
#> 2     2 long,short       A  long
```

The judge’s requests pass the same check as
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md),
under the labels `judge.<mode>.o<k>`, and go into a trace of the judge’s
own. Their cost is in `j$judge_cost` and never in the trace of the run
being judged.

[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md)
holds everything that decides a judge’s answers (model, mode, rubric,
the package’s instructions, reply schema, orders, how verdicts are
combined, the positive grade) with a hash of it.
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
compares the judge’s decisions with blind human labels for one
configuration. It refuses fewer than 50 human-positive or 50
human-negative items, with class `hr_judge_too_few_labels`, and you
cannot lower those minimums. At 10% prevalence, 100 labels hold 10
positives, and sensitivity then has an interval of about plus or minus
0.3. Here the judge’s simulated decisions are right 90% of the time:

``` r

hr_register_model("mock-judge", context_window = 128000, max_output = 4096,
                  input_usd = 1, output_usd = 4)
cfg <- hr_judge_config("mock-judge", "Does the response give the reference's answer?",
                       mode = "grade")

set.seed(3)
human <- rep(c(TRUE, FALSE), c(60, 60))
judged <- ifelse(runif(120) < 0.9, human, !human)
judged[c(5, 70)] <- NA       # unresolved by the judge
v <- hr_judge_validate(cfg, data.frame(judge = judged, human = human), B = 200)
v
#> <hr_judge_validation> config e9b61470aa4b (grade, mock-judge)
#>   items: 120 labelled (60 positive, 60 negative), 2 unresolved, 0 dropped
#>   kappa:       0.850 [0.750, 0.950]
#>   sensitivity: 0.933 [0.841, 0.974], n = 60, half-width 0.067
#>   specificity: 0.917 [0.819, 0.964], n = 60
#>   swap inconsistency: 0.017 [0.005, 0.059], 2 of 120
```

Items the judge left unresolved count as not called positive, as the
scorer will count them, so the figures describe the judge as you will
use it. Decide before labelling what figures are good enough for your
purpose: the function measures the judge and does not approve it. The
record is keyed by the configuration’s hash, and
[`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
tells you when it no longer holds:

``` r

hr_judge_valid(v, cfg)
#> [1] TRUE
hr_judge_valid(v, hr_judge_config("mock-judge", "Is the response right?", mode = "grade"))
#> [1] FALSE
#> attr(,"reason")
#> [1] "the judge configuration changed since validation (rubric)"
```

[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
is a benchmark scorer that grades each output against its label with a
grade-mode judge. Without a valid record it refuses to build (class
`hr_judge_unvalidated`). An unresolved judgement counts as wrong and a
failed one as an error, so an arm’s accuracy cannot rise on the items
the judge could not settle. The judge’s requests stay in the scorer’s
own trace, out of the benchmark’s cost columns:

``` r

grader_judge <- hr_mock_client(function(messages, params) {
  shown <- sub(".*Response to grade:", "", messages[[2]]$content)
  ok <- grepl("45.2 million", shown, fixed = TRUE)
  sprintf('{"verdict": "%s", "reason": "Compared."}', if (ok) "pass" else "fail")
})
judge_scorer <- hr_scorer_judge(cfg, v, grader_judge)
judge_scorer$fn("What was revenue?", "It came to 45.2 million dollars.", "45.2 million")$correct
#> [1] TRUE
```

Accuracy scored by a judge carries the judge’s own errors.
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md)
corrects judge-scored accuracy with human labels on a sample, by
prediction-powered inference (PPI++ by default). Here a lenient judge
passes 30% of wrong answers on 1000 items, and people label 150 of them:

``` r

set.seed(7)
truth <- rbinom(1000, 1, 0.6)
lenient <- ifelse(truth == 1, rbinom(1000, 1, 0.95), rbinom(1000, 1, 0.3))
labelled <- rep(NA, 1000)
picked <- sample(1000, 150)
labelled[picked] <- truth[picked]
hr_judge_ppi(lenient, labelled)[, c("estimate", "lower", "upper", "judge_mean")]
#>    estimate     lower     upper judge_mean
#> 1 0.5668593 0.5053991 0.6283196      0.698
mean(truth)
#> [1] 0.594
```

The judge alone gives 0.698. Corrected with the 150 labels, the estimate
is 0.567, and its interval, 0.505 to 0.628, holds the true share of
0.594. If the labelled items were drawn with unequal probabilities, pass
`inclusion_prob` and the correction is inverse probability weighted. The
interval is a normal approximation and runs narrow with few labels at
small inclusion probabilities.

## Checks that run a program

Besides a label or a judge, a benchmark can score what a program says
about an output.
[`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
builds a step that runs one program you name, such as `Rscript` on a
test file, and reads its result as `"passed"` or `"failed"`. Put it in a
chain (see
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md))
after the step that writes what it checks.

The step runs the program with your own privileges, through
[`system2()`](https://rdrr.io/r/base/system2.html). Each element of
`argv` is one argument, never split on spaces. There is no default
command, and the step never takes a command from a model’s reply. The
API key is unset for the call, and the program inherits the rest of the
environment. A command step sends no request, so it adds no cost.

The examples below run the R that builds this guide, so they work
offline. The draft step writes a small R file for each item in place of
a model’s draft, and the check runs it:

``` r

rscript <- file.path(R.home("bin"), "Rscript")
tasks <- hr_reference(list(t1 = "1 + 1 == 2", t2 = "1 + 1 == 3"),
                      labels = c("passed", "failed"), cluster = c("a", "b"),
                      split = "test")
draft <- hr_step("draft", function(input, ctx) {
  f <- tempfile(fileext = ".R")
  writeLines(sprintf("stopifnot(%s)", input), f)
  list(file = f)
})
run_file <- function(input, ctx) c(rscript, input$file)
status_is <- hr_scorer(function(item, output, label) {
  held <- attr(output, "hr_held")$check
  s <- if (is.null(held)) output$check$status else held$status
  list(correct = identical(s, label), outcome = s, failure_kind = NA)
}, name = "status")
```

The scorer reads a held result from `attr(output, "hr_held")` and a
visible one from `output$check`, so it scores a chain either way.

### How long a command may run

**What it controls.** `timeout` is the number of seconds the program may
run before it is stopped. A program stopped at the limit gets the status
`"timeout"` and the degradation `"command_timeout"`, and counts as
neither passed nor failed. The step ends the program, but processes it
started in the background (or that ignore the signal) can keep running
on any platform. On Windows, any process it started can keep running.

**Signs it needs changing.** Runs whose status is `"timeout"` on items
that pass when run by hand (the limit is too short for the machine), or
a benchmark that takes far longer than its checks should (a stuck
program is waiting out a long limit).

**Where the default came from.** Sixty seconds, enough for a small test
file, set when the step was written and not tuned. It is `untested`.

**How to test it.** Sweep it by path. Each value changes the
configuration, so each value is its own arm. Here both values are long
enough, and the outcomes agree:

``` r

chain <- hr_chain(draft = draft,
                  check = hr_step_command("check", run_file, held = TRUE),
                  name = "checked")
arms <- hr_sweep(chain, data.frame(check.timeout = c(5, 60)))
tb <- hr_benchmark(arms, tasks, runs = 5, client = NULL, scorer = status_is)
table(tb$arm, tb$outcome)
#>                           
#>                            failed passed
#>   checked:check.timeout=5       5      5
#>   checked:check.timeout=60      5      5
```

### How the result is read

**What it controls.** `parse = "exit"` reads the exit code: 0 is
`"passed"`, anything else `"failed"`. `parse = "testthat"` reads the
last `[ FAIL n | WARN n | SKIP n | PASS n ]` line the program printed:
`"failed"` when `FAIL` is above 0, and `"error"` when there is no such
line. For testthat the exit code alone falls short, because
[`testthat::test_file()`](https://testthat.r-lib.org/reference/test_file.html)
exits with 0 when a test fails unless you give it
`stop_on_failure = TRUE`.

**Signs it needs changing.** A check that runs a test file and reports
`"passed"` for drafts that fail their tests: it is reading the exit code
of a run that does not stop on failure. With `"testthat"`, a status of
`"error"` on every run means the program prints no summary line, so the
command is not running the tests.

**Where the default came from.** `"exit"` reads what every program
reports. It was chosen, never tuned, and is `untested`.

**How to test it.** Run the same test file both ways. Without
`stop_on_failure = TRUE` the exit code is 0, so `"exit"` passes what
`"testthat"` fails:

``` r

tf <- tempfile(fileext = ".R")
writeLines("testthat::test_that('sum', testthat::expect_equal(1 + 1, 3))", tf)
quiet <- function(input, ctx) {
  c(rscript, "-e", sprintf("testthat::test_file('%s')", gsub("\\\\", "/", tf)))
}
one <- hr_reference(list(t1 = "sum"), labels = "failed", cluster = "a", split = "test")
tests <- hr_chain(draft = hr_step("draft", function(input, ctx) list()),
                  check = hr_step_command("check", quiet, held = TRUE),
                  name = "tests")
pb <- hr_benchmark(hr_sweep(tests, data.frame(check.parse = c("exit", "testthat"))),
                   one, runs = 5, client = NULL, scorer = status_is)
table(pb$arm, pb$outcome)
#>                             
#>                              error passed
#>   tests:check.parse=exit         0      5
#>   tests:check.parse=testthat     5      0
```

### Whether later steps see the result

**What it controls.** With `held = FALSE` the step returns its input
with the result in `$check`, so a later step (a revise step, say) can
read it. With `held = TRUE` the step passes its input on unchanged,
records the status as the signal `"command.<step>"`, and attaches the
result as `attr(output, "hr_held")` for the scorer. A held step must
come last in its chain:
[`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
refuses a step that is not held after one that is.

**Signs it needs changing.** A chain whose revise step sees the check
that scores it. The check then becomes a target for the revise step, and
its pass rate says little about drafts the check never saw. Hold that
check back, and use a separate visible check for the revise step.

**Where the default came from.** Off, so the steps after it see the
result. It was chosen for the chain, never tuned, and is `untested`.

**How to test it.** Sweep it on the last step. The outcomes agree, since
nothing after the check reads it, but only the held arm records the
signal:

``` r

hs <- hr_benchmark(hr_sweep(chain, data.frame(check.held = c(FALSE, TRUE))), tasks,
                   runs = 5, client = NULL, scorer = status_is)
table(hs$arm, hs$outcome)
#>                           
#>                            failed passed
#>   checked:check.held=FALSE      5      5
#>   checked:check.held=TRUE       5      5
table(hr_signals(hs)$arm)
#> 
#> checked:check.held=TRUE 
#>                      10
```

The difference shows when a step comes after the check. Here a visible
check feeds a revise step that fixes any draft that failed, and a held
check scores the result:

``` r

revise <- hr_step("revise", function(input, ctx) {
  if (identical(input$check$status, "failed")) writeLines("stopifnot(TRUE)", input$file)
  input
})
both <- hr_chain(draft = draft,
                 look = hr_step_command("look", run_file),
                 revise = revise,
                 check = hr_step_command("check", run_file, held = TRUE),
                 name = "revised")
hb <- hr_benchmark(list(chain, both), tasks, runs = 5, client = NULL,
                   scorer = status_is)
table(hb$arm, hb$outcome)
#>          
#>           failed passed
#>   checked      5      5
#>   revised      0     10
hr_signals(hb)[1:3, c("arm", "item", "signal", "value")]
#>       arm item        signal  value
#> 1 checked   t1 command.check passed
#> 2 checked   t1 command.check passed
#> 3 checked   t1 command.check passed
unlink(tf)
```

The revised chain passes every draft, so it is scored wrong on `t2`,
whose label says the draft should fail. A command step checks only what
its command checks, and the package never chooses the command.

## Baselines without a model

A configuration that calls a model should beat one that does not.
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
fits a ridge logistic regression on tf-idf features
([`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md))
and cross-fits it, so a model that never saw an item predicts it, with
the vocabulary fitted on each training fold only. Folds are stratified
by label, or keep each `cluster` whole:

``` r

set.seed(1)
words <- function(pool, n) vapply(seq_len(n), function(i) paste(sample(pool, 6, TRUE), collapse = " "), "")
abstracts <- c(words(c("masks", "infection", "trial", "ward", "virus"), 10),
               words(c("budget", "policy", "school", "survey", "income"), 50))
relevant <- rep(c(TRUE, FALSE), c(10, 50))

hr_baseline_classifier(abstracts, relevant, folds = 5)
#> <hr_baseline_classifier> ridge logistic, 2 labels, 5 folds
#>   accuracy: 1.000 [0.940, 1.000], 60 of 60 out of fold
#>   training size per fold: 48, 48, 48, 48, 48
```

Real abstracts do not separate this cleanly. Run the baseline on the
same labelled set as the model screener: a screener no more accurate
than it costs calls and buys nothing.

[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
simulates prioritised screening over a set whose relevance is known, as
ASReview’s simulation mode does: it starts from one relevant and one
irrelevant record, refits after each batch, and screens the record with
the highest predicted relevance next. It reports the records screened to
reach 95% recall and <WSS@95>, the share left unread at that recall less
the 5% a random order would leave:

``` r

ranked <- hr_baseline_ranker(abstracts, relevant)
ranked
#> <hr_baseline_ranker> logistic, 60 records, 10 relevant, 9 fits
#>   95% recall after 11 records (random order: 55.5 expected)
#>   WSS@95: 0.767
```

[`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
takes this result, or any screening order, and says when prioritised
screening may stop;
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md)
covers it.

## Drift

A provider can change a model behind the same name.
[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md)
reruns an arm live on the items of a frozen benchmark and compares the
two item by item. You fix `alpha` and an optional `alert` in the call,
before anything is rerun. Here the model now gets two capitals wrong:

``` r

six <- hr_reference(
  items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji", q5 = "Chile", q6 = "Laos"),
  labels = c("Paris", "Lima", "N'Djamena", "Suva", "Santiago", "Vientiane"),
  cluster = c("a", "a", "b", "b", "c", "c"), split = "test")
then <- c(France = "Paris", Peru = "Lima", Chad = "N'Djamena", Fiji = "Suva",
          Chile = "Santiago", Laos = "Vientiane")
now <- then
now[c("Chad", "Laos")] <- c("Ndjamena", "Luang Prabang")
answers <- function(table) {
  hr_mock_client(function(messages, params) table[[sub("Capital of ", "", messages[[1]]$content)]])
}

frozen <- hr_benchmark(capital, six, runs = 5, client = answers(then))
drift <- hr_drift_check(frozen, capital, client = answers(now), reference = six,
                        alert = 0.1, B = 500)
drift
#> <hr_drift_check> arm 'capital': 5 frozen run(s) vs 5 live, 6 item(s) in 3 cluster(s); alpha 0.05
#> (a) Accuracy: frozen 1.000, live 0.667, change -0.333 [-0.500, -0.167], p 0.0122; changed: yes
#>     Clustered McNemar (Obuchowski): X^2 4.000, p 0.0455; agrees: yes
#> (b) Flips: between frozen runs 0.000, between live runs 0.000, frozen vs live 0.333, excess 0.333 (one-sided lower 0.000), p 0.333; in excess: no
#>     Frozen pairs flip 0.000 to 0.000; frozen-live pairs 0.333 to 0.333
#> Drift: yes; alert at 0.100: crossed
#> Items: lost 2, gained 0, worse 0, better 0, same 4 
#>  item cluster change frozen live  frozen_outcome live_outcome 
#>  q3   b       lost   1.000  0.000 n'djamena      ndjamena     
#>  q6   c       lost   1.000  0.000 vientiane      luang prabang
#> Note: 6 items in 3 clusters fall short of 300 items and 30 clusters, where the cluster bootstrap can undercover; read the tests as approximate.
```

Test (a) is the change in accuracy, live minus frozen, by a cluster
bootstrap over documents, with the clustered McNemar test beside it.
Test (b) checks whether frozen and live runs disagree more than
replicate runs disagree among themselves. Per item it estimates the
squared change, so it also catches losses and gains that cancel in
accuracy.

Here (a) finds the two lost items: a change of -0.333 with an interval
that lies wholly beyond the alert of 0.1. Test (b) does not reject,
since with three clusters its one-sided bound reaches 0. The live rerun
is in `drift$live`, an `hr_bench` you can report or keep as the next
frozen sample.

[`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md)
refuses fewer than 5 frozen runs, a changed arm, another reference or
scorer, and a live rerun answered from a cache or a recording. That last
one would return the frozen reply again instead of the model’s answer
today.

## Signals, calibration and gate thresholds

Some readers report on their own work: the `iterative` reader says at
each step whether it can answer, `preview` says which sections its plan
would skip, and `ensemble` says how it settled its members.
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
records such a value as a local step in the trace. That step sends no
request and changes no cache key.
[`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
reads the values back:

``` r

reader <- hr_mock_client(function(m, p) {
  '{"can_answer": true, "answer": "45.2 million dollars", "next_query": ""}'
})
ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
read <- gr_read(ch, "What was revenue?", reader, "iterative")
hr_signals(read)[, c("signal", "value", "score", "refs")]
#>                    signal value score        refs
#> 1 gr.iterative.can_answer  TRUE     1 {"round":1}
```

A signal is advisory. Nothing in the package acts on one, and a signal
may gate an action only after you measure it against items whose right
answer is known.
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
takes that measure on a graded set, which must include unanswerable
items. A signal measured only on answerable questions has never been
tested on the case where “I can answer” is most often wrong.

[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
fits a map from the signal to a probability on half of each cluster’s
items and measures it on the other half. It reports the Brier score,
type-2 AUROC, the area under the risk-coverage curve and a debiased
calibration error, each with a cluster bootstrap interval. The record is
keyed by the served model, its version, the task, format, prompt hash,
effort, module and contract version. The graded set here is simulated,
1200 items in 120 documents:

``` r

set.seed(2)
n <- 1200
answerable <- runif(n) < 0.8
score <- runif(n) * ifelse(answerable, 1, 0.6)
graded <- data.frame(cluster = rep(sprintf("doc%03d", 1:120), each = 10),
                     score = score, answerable = answerable,
                     correct = runif(n) < plogis(-6 + 12 * score) / ifelse(answerable, 1, 3))
key <- list(served_model = "mock-large-2026-01", version = "2026-01", task = "qa",
            format = "txt", prompt_hash = "a1b2c3", effort = NA, module = "iterative")

cal <- hr_calibrate_signal("gr.iterative.can_answer", graded, key, seed = 3, B = 200)
cal
#> <hr_calibration> gr.iterative.can_answer: advisory
#>   1200 items (715 wrong, 266 unanswerable) in 120 clusters; map: platt
#>   key: served_model=mock-large-2026-01, version=2026-01, task=qa, format=txt, prompt_hash=a1b2c3, effort=NA, module=iterative, contract_version=0.1
#>   calibration half: 600 items, accuracy 0.400
#>   brier   0.0914  [0.0761, 0.1075]
#>   auroc2  0.9454  [0.9282, 0.9619]
#>   aurc    0.2677  [0.2358, 0.3110]
#>   ece     0.0695  [0.0264, 0.1021]
#>   advisory: no gate threshold has been set
```

A new record is always advisory.
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
uses Learn-then-Test to find the loosest threshold at which acting on
the items at or above it keeps a risk below `alpha` with confidence 1 -
`delta`. It tests thresholds from strict to loose with a one-sided
Clopper-Pearson bound and stops at the first that fails. Errors from one
document go together, so the bound is taken on an effective number of
items, `n / deff`, where the design effect `deff` is measured over the
calibration half’s clusters at each threshold. `alpha` has no default,
since you set it for the task:

``` r

cal <- hr_gate_threshold(cal, "stop", alpha = 0.1)
as.data.frame(cal$gate[c("threshold", "n", "k", "deff", "ucb", "coverage", "status")])
#>   threshold   n k     deff        ucb coverage status
#> 1 0.8510243 147 7 1.258159 0.09408169    0.245 passed
cal$status
#> [1] "gating"
```

At the threshold kept, 147 items of the calibration half are acted on, 7
of them wrongly. The design effect is 1.26, so the bound counts them as
about 117 independent items, and the upper bound on the error among them
is 0.094 (0.088 if the items were independent).

A record becomes `"gating"` only when it has all four of these:

- a passing threshold;
- at least 100 wrong items in the graded set;
- a map that rises with the signal;
- a calibration error over at least 5 bins.

Items with the same `p` share a bin, so a signal with fewer than 5
values, such as a logical one, stays advisory. A graded set with a
`split` column, as
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
gives, is calibrated on its `calibration` rows alone. Even with a gating
record, the signal gates only through a policy, and only for a run whose
key matches the record:

``` r

policy <- hr_signal_policy("gr.iterative.can_answer", "stop")
hr_apply_signal(c(0.95, 0.4), policy, cal, key)[, c("value", "p", "gated", "act", "route")]
#>   value         p gated   act       route
#> 1  0.95 0.9938152  TRUE  TRUE         act
#> 2   0.4 0.1982915  TRUE FALSE route_check

later <- utils::modifyList(key, list(served_model = "mock-large-2026-06"))
hr_calibration_valid(cal, later)
#> [1] FALSE
#> attr(,"differs")
#> [1] "served_model"
hr_apply_signal(0.95, policy, cal, later)$reason
#> [1] "the record does not hold for this run (served_model differs)"
```

If the signal cannot gate, `on_fail` routes the item: to a check (the
default), to a person, or nowhere. No reader calls
[`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
yet, so in this release nothing gates on a signal.

## The statistics underneath

The functions above rest on five that you can also use on their own.

[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)
gives Wilson, Clopper-Pearson or Jeffreys intervals for a proportion.
Use Wilson for a descriptive rate and Clopper-Pearson for an “at least”
or “at most” claim, read as a one-sided bound:

``` r

hr_prop_ci(46, 50)[, c("est", "lower", "upper", "method")]
#>    est     lower     upper method
#> 1 0.92 0.8116175 0.9684505 wilson
hr_prop_ci(46, 50, method = "clopper_pearson", side = "lower")[, c("lower", "method", "side")]
#>       lower          method  side
#> 1 0.8262088 clopper_pearson lower
```

[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
reports agreement between two raters as the count table with observed
agreement, Cohen’s kappa with a bootstrap interval, the prevalence and
bias indices, PABAK, Gwet’s AC1, and sensitivity, specificity, PPV and
NPV when `positive` is given. Kappa is never reported alone, since it
moves with prevalence as much as with agreement. For a matrix of coders,
or an ordinal, interval or ratio level, it reports Krippendorff’s alpha
instead. Below 30 items that can be paired, alpha is `NA` and only
percent agreement is reported.

``` r

screener <- rep(c("keep", "drop", "keep", "drop"), c(40, 9, 6, 45))
person   <- rep(c("keep", "keep", "drop", "drop"), c(40, 9, 6, 45))
hr_agreement(screener, person, positive = "keep", B = 200)$stats[1:4, ]
#>            statistic  estimate        se     lower     upper
#> 1 observed agreement 0.8500000        NA 0.7671644 0.9069401
#> 2              kappa 0.6995192 0.0713936 0.5620888 0.8377657
#> 3              PABAK 0.7000000        NA 0.5343288 0.8138803
#> 4                AC1 0.7007481 0.0713518 0.5591707 0.8423256
```

[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md)
estimates a total, a mean or a ratio from a sample drawn with known
inclusion probabilities, optionally by stratum. Screening recall on a
stacked reference is weighted with it.
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md) is
the prediction-powered estimate behind
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md).
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md)
runs the alternative annotator test of Calderon, Reichart and Dror
(2025), which tests whether a model’s labels can stand in for those of
three or more people, with the margin set by the people’s declared
expertise (`expertise` has no default):

``` r

set.seed(3)
gold <- sample(c("a", "b", "c"), 80, replace = TRUE)
noisy <- function(p) ifelse(runif(80) < p, gold, sample(c("a", "b", "c"), 80, TRUE))
people <- sapply(1:4, function(j) noisy(0.75))
alt <- hr_alt_test(noisy(0.95), people, expertise = "skilled")
alt$omega
#> [1] 1
alt$passed
#> [1] TRUE
```

The model here wins against each of the four annotators, so the winning
rate omega is 1 and the test passes. The test needs at least 30 items
with two or more human labels, and
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md)
warns below 50.

## Next

- [`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md):
  these steps applied to five comparisons (readers, segmenters and chunk
  sizes, a setting over its values, screening settings, a judge against
  labels), each with its report and how to read it.
- [`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md):
  screening recall against a target, several reviewers, and agreement
  between extraction tables.
- [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md):
  the governor, caching and replay that a benchmark relies on.
- [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md):
  the recipes
  [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  turns into arms.
- [`?hr_report`](https://elkronos.github.io/harnessr/reference/hr_report.md),
  [`?hr_mdd`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  and
  [`?hr_calibrate_signal`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md):
  every formula, with its references and the simulation results behind
  the defaults.
