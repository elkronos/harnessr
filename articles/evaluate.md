# Measuring and comparing configurations

Every choice in a pipeline (the recipe, the model, the prompt, the
reasoning effort) changes the answers, and one run on one document
cannot say by how much. A model asked the same question five times can
answer it five ways, and ten questions about one report share that
report’s quirks, so they are closer to one observation than to ten.
[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
shows what each recipe does to one document and is descriptive only. The
functions in this guide answer the question that follows it: on a
labelled set of questions, is configuration A more accurate than B, by
how much, at what cost, and how sure can you be?

The guide follows the order of the work: a reference set and its splits,
the arms to compare and the rule that scores them, a benchmark held to
one spending limit, the report and how to read it, planning the size of
a comparison before running it, judges, baselines that use no model,
drift, and the signals the package records about its own work. The
statistics functions underneath come last. Measuring a screener against
people, several reviewers and agreement between extraction tables are
part of a review and are in
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md).

## Setting up

Everything below runs offline.
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
stands in for the model, and `embedder = "lexical"` keeps retrieval free
and deterministic. Two mock model ids get prices, so the benchmarks
below have a cost to compare: `mock-small` at \$0.20 and \$0.80 per
million input and output tokens, and `mock-large` at ten times that.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")

gr_register_model("mock-small", context_window = 128000, max_output = 4096,
                  input_usd = 0.2, output_usd = 0.8)
gr_register_model("mock-large", context_window = 128000, max_output = 4096,
                  input_usd = 2, output_usd = 8)
```

## References and splits

A reference is the labelled set every configuration is scored on. Each
item has a payload (what the configuration is given), a label (what
counts as right), a cluster and a split. The cluster is the unit whose
items share errors, usually the document: eight questions about one
report are not eight independent observations, and every interval in
this guide is computed with that in mind.
[`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
builds one from any items;
[`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
builds one of questions about documents, with each question’s acceptable
answers:

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
marked unanswerable: its label is the not-found answer, and a reader is
right on it only when it says the document does not hold the answer. The
flag goes into the label alone; the payload a configuration is given
holds the question and the document, so it cannot tell which questions
have no answer. A reference without such items never tests whether a
reader can tell that an answer is missing. An item with neither an
answer nor the unanswerable flag has no label, and every run on it is
scored `NA`, so it never counts for or against an arm.

Once a benchmark starts scoring a reference, the reference is locked:
[`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
then refuses to add items to it, or to any copy of it, with an error of
class `hr_reference_locked`, so no item can be added after the results
are seen. The reference also carries a SHA-256 hash of its content,
which the benchmark checks.

Splits keep tuning apart from evidence. `dev` is for tuning prompts,
settings and margins, and its scores are never reported. `exploratory`
holds early experiments, `calibration` is for fitting signal thresholds
(below), `test` is what reported comparisons are scored on, and `final`,
if used, is held back and run once per release.
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
test. Each cluster’s place comes from the SHA-256 digest of the seed and
its id, so row order and the session’s random state do not change it,
and with the default `method = "stable"` adding or dropping a document
never moves another. The price is that the shares are met only on
average: 13 of these 30 documents went to test, not 15.
`method = "balanced"` gives each split its share of whole clusters, at
the cost that a document added later can shift others across a boundary,
so draw it once and store it:

``` r

hr_assign_splits(questions, seed = 2026, method = "balanced")$counts[, c("split", "clusters", "items")]
#>         split clusters items
#> 1         dev        3    12
#> 2 exploratory        3    12
#> 3 calibration        9    36
#> 4        test       15    60
```

A split given a share that receives no cluster warns with class
`hr_empty_split`, which happens with very few documents.

### Label sheets

Labels come from people.
[`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
writes a CSV with one row per item, the columns a person needs to judge
it and empty columns for their decisions, with an instructions file
beside it. It writes five kinds: `"qa"`, `"screening"`, `"extraction"`,
`"calibration"` and `"judge"`. A blind sheet, the default, copies only
those columns, so a model’s answer in `items` stays out of it:

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
other columns back by `item_id`, renaming one that clashes with a
decision column (the model’s `answer` here would come back as
`model_answer`):

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

A value it cannot read stops it with an error of class `gr_bad_labels`
that names the sheet, the row as a spreadsheet counts it and the item,
for every bad value at once:

``` r

filled$answer[2] <- "Smith & Co"
write.csv(filled, path, row.names = FALSE, na = "")
tryCatch(gr_read_labels(path, "qa", items = to_label),
         gr_bad_labels = function(e) cat(conditionMessage(e)))
#> 1 value(s) in the qa sheet cannot be read:
#> qa-labels.csv row 3 (item 'q002'): `answerable` is no but `answer` is filled; clear one of them.
```

With `reviewers = k` each person gets a sheet of their own, so no one
sees another’s decisions.
[`?gr_label_sheet`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
gives the number of items each kind of set needs for the package’s own
evaluation: for question answering, about 480 questions over 88
documents.

## Arms and scorers

An arm is one configuration to compare: a function of an item and a
context that returns the arm’s output for that item. `ctx` carries the
benchmark’s client, a trace of this run alone, the governor the run is
held to and the run’s `draw_index`; `ctx$call()` is
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
with the client, the trace and the draw index filled in. Every request
an arm makes has to go through that trace, since it is how the benchmark
counts the run’s tokens and dollars and holds it to the limit:

``` r

ask <- function(name, model) {
  hr_arm(name, function(item, ctx) {
    ctx$call(paste("Item", item), model = ctx$params$model)$text
  }, params = list(model = model))
}
ask("large", "mock-large")
#> <hr_arm large> version 0.0.1
#>   params: model = mock-large 
#>   hash: dc2928258ae6
```

The arm records a SHA-256 hash of its name, code, settings and
`version`. The code is hashed as text with the values it names from the
environment it was made in, the workspace included: an arm written at
top level that reads a global prompt gets a new hash when the prompt
changes. The same arm has the same hash in every session and after
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html), and an arm edited
after it was built is refused rather than run under its old name. Change
`version` when the arm’s behaviour changes.

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
takes in `...`; here they make the same recipe two arms on two models:

``` r

arms <- list(gr_arm("fast", settings = list(model = "mock-small"), name = "small"),
             gr_arm("fast", settings = list(model = "mock-large"), name = "large"))
```

A
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)’s
version is the package version, since readers and prompts change between
releases. Every request of a run, segmenter and reader requests
included, carries the run’s draw index. A reader that finds the run’s
limits leave it too little room to start returns a partial not-found
answer noting the limit, which is scored as a budget stop rather than an
error.

A scorer turns an output and a label into `correct`, an `outcome` (what
it compared) and a `failure_kind` saying why a wrong output was wrong:
`"parse_failure"`, `"refusal"`, `"not_in_document"`, `"wrong"`,
`"budget_stop"` or `"error"`.
[`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md),
the default, compares text after folding case and white space.
[`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
is the one for reading recipes: an answer is right when it contains any
acceptable answer, after folding case, white space and thousands
separators, with numbers matched whole (`"12"` is not found in `".12"`
or `"-12"`, but is found in `"12-15"`, and `"45.2"` in `"45.2m"`):

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

On an unanswerable item it is right when
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
is `TRUE` and no limit or refusal stopped the run, since a reader that
ran out of budget did not look.
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
makes a scorer of your own from a function of `(item, output, label)`;
its help has one that accepts a number within 1% of the label.

## Running a benchmark

[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
runs every arm on every item of the chosen splits `runs` times, scores
each output, and returns one row per cluster, item, arm and run. The
stand-in model below knows each report’s facts. Asked as `mock-small` it
loses its way on 30% of requests; as `mock-large` it does not:

``` r

facts <- list(
  northern = c(revenue = "Revenue was 45.2 million dollars.", units = "Leeds made 12,400 units."),
  southern = c(revenue = "Revenue was 51.8 million dollars.", staff = "There were 310 staff."),
  eastern  = c(revenue = "Revenue was 38.9 million dollars."),
  western  = c(revenue = "Revenue was 29.4 million dollars.", exports = "Exports rose 7 percent."))

cl <- gr_mock_client(function(messages, params) {
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
items, and is descriptive: no interval. The arms run under a private
random stream started from `seed` (1 by default), which is why the
mock’s [`runif()`](https://rdrr.io/r/stats/Uniform.html) gives the same
draws every time this guide is built, and the caller’s random state is
left as it was. Rows on the dev split are marked `reportable = FALSE`
and printed apart. Five runs is the default and the expected minimum;
fewer warns with class `hr_few_runs`, because with fewer the spread from
run to run cannot be told from the difference between arms.

### One limit for the whole benchmark

The benchmark is one run under one
[`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md).
Each run’s trace is held to the governor’s limits less what the runs
before it used, so the limit you set is the most the whole comparison
can spend. With `governor = NULL` the limits come from
[`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md),
whose default of 400 calls is easy to exceed: two arms on 300 items for
5 runs is 3000 calls. A run stopped by a refused request is recorded as
a `"budget_stop"`, counted wrong, and the runs after it are still
started, so every row exists and the refusals are visible:

``` r

capitals <- hr_reference(items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
                         labels = c("Paris", "Lima", "N'Djamena", "Suva"),
                         cluster = c("a", "a", "b", "b"), split = "test")
atlas <- c(France = "Paris", Peru = "Lima", Chad = "N'Djamena", Fiji = "Suva")
geo <- gr_mock_client(function(messages, params) atlas[[sub("Capital of ", "", messages[[1]]$content)]])
capital <- hr_arm("capital", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)

short <- hr_benchmark(capital, capitals, runs = 5, client = geo,
                      governor = hr_governor(max_calls = 6))
table(short$failure_kind, useNA = "ifany")
#> 
#> budget_stop        <NA> 
#>          14           6
```

The first six runs were answered, and the other fourteen were refused
before anything was sent.

### Repeated runs must be repeated draws

Run `r` is given `ctx$draw_index = r`, and `ctx$call()` passes it on, so
under a
[`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
each run is its own cache entry and under a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
its own recorded draw. The recorded draw also names the arm, so a replay
answers each arm with its own replies, whether it replays every arm or a
few, in any order. Five runs answered from one stored reply would agree
perfectly and measure nothing, so an arm whose runs come back as copies
is refused with an error of class `hr_duplicate_draw`. An arm that calls
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
without the draw index is one:

``` r

cache <- gr_cache()
cached <- gr_cache_client(geo, cache)
invisible(hr_benchmark(capital, capitals, runs = 5, client = cached))

no_draw <- hr_arm("no_draw", function(item, ctx) {
  gr_call(ctx$client, paste0("Capital of ", item), trace = ctx$trace)$text
})
tryCatch(hr_benchmark(no_draw, capitals, runs = 5, client = cached),
         hr_duplicate_draw = function(e) class(e)[1])
#> [1] "hr_duplicate_draw"
```

A cache is still worth having: running the `capital` benchmark again
under the same cache sends no request and costs nothing, each run
answered from its own entry. A
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
keeps no cache, so under it the `no_draw` arm is not refused; under a
cache it is.

## Reading the report

[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
turns the reportable rows into accuracy per arm with intervals that keep
clusters together, paired differences, stability, reliability, cost and
failures. `B` is the number of cluster bootstrap resamples, 2000 by
default; this guide uses fewer so it builds quickly.

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

Which interval is used depends on the size of the benchmark, and the
second line of the print says which and why. With at least 300 items and
at least 30 clusters, `method = "auto"` uses a studentised cluster
bootstrap: each resample draws whole clusters with all their items, runs
and arms. Below either threshold, as here, it uses a cluster-robust t
interval on the logit scale, with t quantiles on C - 1 degrees of
freedom for C clusters. Where neither is defined, because accuracy is 0
or 1 or the same in every cluster, the arm gets Korn and Graubard’s
interval, one-sided from that bound; that is why `large` reads \[0.561,
1.000\] with four clusters behind it, and a note says so. No interval
treats items or runs as independent trials. `method = "exact"`
(Clopper-Pearson on the effective number of items) and
`method = "bayes"` (a beta-binomial model with a cluster random effect)
are there on request.

These defaults were chosen by simulation. In `dev/sim-coverage.R` (2000
replicates) the studentised bootstrap covered 95.5% and 95.0% with 386
items in 40 clusters, where the BCa bootstrap it replaced covered 93.5%,
and the cluster-robust t interval covered 95.7% and 95.8% with 50 items
in 10 clusters. The workflow `validation.yaml` reruns that simulation,
and the one behind
[`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md),
every night.

Paired differences are taken item by item, so each one compares the arms
on the same question, with a cluster-robust t interval at every size and
simultaneous intervals over all pairs beside it. Arms are listed in
benchmark order, not ranked; the rank interval is how much the order
could change over resamples, and `small` and `large` here are ranked 2
and 1 in every one.

The stability rows describe each arm against itself. The flip rate is
the share of items whose correctness changed between runs, TARa the
share whose scored output was the same on every run, and `run_sd` the
spread of whole-run accuracy. `small` flips on 75% of its items, which
an accuracy of 0.750 alone would hide. Reliability is pass^k, the chance
that k runs drawn from an item’s runs are all right, estimated without
bias: an arm right 75% of the time is right on all five runs of an item
only 25% of the time here.

Cost is in dollars and tokens per item and per correct item, since a
cheap arm that is often wrong can cost more per right answer than it
looks. An arm whose dollars rest on estimated token counts for more than
5% of its spend is flagged; the mock reports no token counts, so both
are flagged here. The frontier is the set of arms no other arm beats on
both dollars per item and accuracy, with each arm’s share of resamples
on it. Failures are counted by kind, every one counted wrong, with
accuracy recomputed without parse failures and refusals beside it. The
variance line splits the spread into within-item (run to run) and
between-item parts; when runs account for more than 10% of it, as here
at 80%, the report says to use 10 runs.

Below 5 runs the report is descriptive only, with point estimates and no
intervals. An item scored on some runs and not others is refused.
Everything is in the returned list (`rpt$accuracy`, `rpt$contrasts`,
`rpt$pass_k`, `rpt$cost`, `rpt$frontier`, `rpt$failures`,
`rpt$variance`, `rpt$notes`), and
[`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
writes it out.

## Planning the size, and non-inferiority

Often the question is whether a cheaper arm is worse than the one in use
by more than a margin you can live with. That is a non-inferiority test.
Whether a benchmark can answer it depends on its size, which is worth
knowing before anyone labels 500 questions.

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
turns it round, giving the items needed for a margin:

``` r

hr_n_needed(0.08, m = 6, icc = 0.2, p_disc = 0.2, n_contrasts = 9)
#> <hr_n_needed> 8.0 points at 80% power, one-sided alpha 0.002778 (0.025 / 9 contrasts, Holm worst case)
#>   n_eff 419 effective items; DE 2, so 840 items in 140 clusters of 6
```

Both use t quantiles on C - 1 degrees of freedom, the ones the report
tests with. In the power simulation `dev/sim-power.R` the formula’s MDD
was within 0.25 points of the simulated one; with normal quantiles it
was up to 0.41 points below it at 80 clusters, which is why t quantiles
are used.

[`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
states a contrast (the new arm, the reference arm, the margin and
whether the new arm must also be cheaper) and
[`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
fixes the contrasts against the reference before anything scores it. The
help suggests a margin of min(0.5 x M1, the loss you would accept in
practice), with M1 the reference arm’s advantage over a minimal baseline
in a pilot. A confirmatory margin below the design’s MDD after Holm is
refused with class `hr_margin_below_mdd`, since it claims more than the
items can show; `confirmatory = FALSE` registers it as exploratory
instead. A reference a benchmark has already begun to score is refused
with class `hr_registration_after_scoring`.

``` r

n <- 300
ids <- sprintf("q%03d", 1:n)
docs <- rep(sprintf("doc%02d", 1:50), each = 6)
plan <- hr_reference(ids, labels = rep("yes", n), cluster = docs, split = "test")

design <- hr_mdd(n, n_clusters = 50, icc = 0.1, p_disc = 0.15)
reg <- hr_register_contrasts(plan, hr_contrast("small", "large", margin = 0.10), design)
reg
#> <hr_contrast_registration> 1 contrast(s), 1 confirmatory; registered 2026-11-10T01:54:42.320Z
#>  contrast       label        margin mdd cost_test
#>  small vs large confirmatory 10.0   7.8 yes      
#>   Margins and MDD in points; reference d453122a93af; hash 79bccfe26832
```

Here the stand-in model finds each item easier or harder by document and
by item, and `mock-small` is a little worse on every one. The governor
allows the 3000 calls the benchmark needs:

``` r

set.seed(11)
ease <- setNames(rnorm(50, 2, 1)[as.integer(factor(docs))] + rnorm(n, 0, 1.5), ids)
grader <- gr_mock_client(function(messages, params) {
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
bound of the paired cost difference is below 0. Here `small` is 5.3
points less accurate than `large`, its lower bound is -8.1 points,
inside the margin of 10, and its cost bound is below 0, so the verdict
is `TRUE`. The accuracy bound is the cluster-robust t bound of the
paired differences, so at one-sided 0.025 it is the lower end of the
printed 95% contrast interval. Confirmatory contrasts are tested with
Holm’s step-down procedure. The design and achieved MDD are printed
beside the verdict, and Tango’s paired score interval sits beside it as
a cross-check that does not enter the verdict.

A report with a registration, or with `confirmatory = TRUE`, is
evidence, so any row from the dev, exploratory or calibration split is
refused with class `hr_dev_not_evidence`, and so is a registration
edited after it was made.

## Judges

Some answers cannot be scored by matching text: a summary, an
explanation, an answer that is right in other words.
[`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
asks a model to choose between candidates (`"select"`), compare two
(`"pairwise"`) or grade one against a reference (`"grade"`). Candidates
are shown under the letters A, B and so on, never their names, and each
item is asked in two orders. A verdict that changes with the order,
mapped back to the candidate it names, is `"unresolved"`, never a pick.
This stand-in always picks whatever is shown first:

``` r

first <- gr_mock_client(function(messages, params) '{"verdict": "A", "reason": "It is first."}')
j <- hr_judge(c(short = "Revenue was 45.2 million.", long = "Revenue was 51.8 million."),
              first, mode = "select", rubric = "Which candidate gives fiscal 2024 revenue?")
j$outcome
#> [1] "unresolved"
j$verdicts[, c("order", "shown", "verdict", "value")]
#>   order      shown verdict value
#> 1     1 short,long       A short
#> 2     2 long,short       A  long
```

The judge’s requests go through the same check as
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md),
under the labels `judge.<mode>.o<k>`, into a trace of the judge’s own.
Their cost is in `j$judge_cost` and never in the trace of the run being
judged.

[`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md)
holds everything that decides a judge’s answers (model, mode, rubric,
the package’s instructions, reply schema, orders, how verdicts are
combined, the positive grade) with a hash of it.
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
compares the judge’s decisions with blind human labels for one
configuration. It refuses fewer than 50 human-positive or 50
human-negative items, with class `hr_judge_too_few_labels`, and the
minimums cannot be lowered: at 10% prevalence, 100 labels hold 10
positives and a sensitivity interval of about plus or minus 0.3. The
judge’s decisions here are simulated as right 90% of the time:

``` r

gr_register_model("mock-judge", context_window = 128000, max_output = 4096,
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

Items the judge left unresolved count as not called positive, which is
how the scorer will count them, so the figures describe the judge as it
will be used. Whether they are good enough for your purpose is a
decision to make before labelling; the function measures and does not
admit. The record is keyed by the configuration’s hash, and
[`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
says when it no longer holds:

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
grade-mode judge. It refuses to be built without a valid record (class
`hr_judge_unvalidated`). An unresolved judgement counts as wrong and a
failed one as an error, so an arm’s accuracy cannot rise on the items
the judge could not settle, and the judge’s requests stay in the
scorer’s own trace, out of the benchmark’s cost columns:

``` r

grader_judge <- gr_mock_client(function(messages, params) {
  shown <- sub(".*Response to grade:", "", messages[[2]]$content)
  ok <- grepl("45.2 million", shown, fixed = TRUE)
  sprintf('{"verdict": "%s", "reason": "Compared."}', if (ok) "pass" else "fail")
})
judge_scorer <- hr_scorer_judge(cfg, v, grader_judge)
judge_scorer$fn("What was revenue?", "It came to 45.2 million dollars.", "45.2 million")$correct
#> [1] TRUE
```

A judge’s accuracy figures carry its own errors.
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

The judge alone says 0.698. Corrected with the 150 labels the estimate
is 0.567, and its interval, 0.505 to 0.628, holds the true share of
0.594. When the labelled items were drawn with unequal probabilities,
pass `inclusion_prob` and the correction is inverse probability
weighted. The interval is a normal approximation and runs narrow with
few labels at small inclusion probabilities.

## Baselines without a model

A configuration that calls a model should beat one that does not.
[`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
fits a ridge logistic regression on tf-idf features
([`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md))
and cross-fits it, so every item is predicted by a model that never saw
it, with the vocabulary fitted on each training fold only. Folds are
stratified by label, or keep each `cluster` whole:

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
two item by item, with `alpha` and an optional `alert` fixed in the call
before anything is rerun. Here the model has since learned two capitals
wrong:

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
  gr_mock_client(function(messages, params) table[[sub("Capital of ", "", messages[[1]]$content)]])
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
Test (b) asks whether frozen and live runs disagree more than replicate
runs disagree among themselves; per item it estimates the squared
change, so it also sees losses and gains that cancel in accuracy. Here
(a) finds the two lost items, a change of -0.333 with an interval that
lies wholly beyond the alert of 0.1. Test (b) does not reject: with
three clusters its one-sided bound reaches 0. The live rerun is in
`drift$live`, an `hr_bench` you can report or keep as the next frozen
sample. Fewer than 5 frozen runs, a changed arm, another reference or
scorer, and a live rerun answered from a cache or a recording are
refused: that last one would be the frozen reply again, not the model
today.

## Signals, calibration and gate thresholds

Some readers report on their own work: the `iterative` reader says at
each step whether it can answer, `preview` says which sections its plan
would skip, and `ensemble` says how it settled its members.
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
records such a value as a local step in the trace, which sends no
request and changes no cache key, and
[`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
reads them back:

``` r

reader <- gr_mock_client(function(m, p) {
  '{"can_answer": true, "answer": "45.2 million dollars", "next_query": ""}'
})
ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 150))
read <- gr_read(ch, "What was revenue?", reader, "iterative")
hr_signals(read)[, c("signal", "value", "score", "refs")]
#>                    signal value score        refs
#> 1 gr.iterative.can_answer  TRUE     1 {"round":1}
```

A signal is advisory. Nothing in the package acts on one, and a signal
may gate an action only after it has been measured against items whose
right answer is known.
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
does that on a graded set, which must include unanswerable items: a
signal measured only on answerable questions has never been asked about
the case where “I can answer” is most often wrong. It fits a map from
the signal to a probability on half of each cluster’s items and measures
it on the other half, with the Brier score, type-2 AUROC, the area under
the risk-coverage curve and a debiased calibration error, each with a
cluster bootstrap interval. The record is keyed by the served model, its
version, the task, format, prompt hash, effort, module and contract
version. The graded set here is simulated, 1200 items in 120 documents:

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
looks for the loosest threshold at which acting on the items at or above
it keeps a risk below `alpha` with confidence 1 - `delta`, by
Learn-then-Test: thresholds are tested from strict to loose with a
one-sided Clopper-Pearson bound, and the sequence stops at the first
that fails. Errors from one document go together, so the bound is taken
on an effective number of items, `n / deff`, where the design effect
`deff` is measured over the calibration half’s clusters at each
threshold. `alpha` has no default, since it is a decision about the
task:

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
is 0.094 (0.088 if the items were independent). A record becomes
`"gating"` only with a passing threshold, at least 100 wrong items in
the graded set, a map that rises with the signal and a calibration error
over at least 5 bins. Items with the same `p` share a bin, so a signal
with fewer than 5 values, such as a logical one, stays advisory. A
graded set with a `split` column, as
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
gives, is calibrated on its `calibration` rows alone. Even then the
signal gates only through a policy, and only for a run whose key matches
the record:

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

When the signal cannot gate, the item is routed by `on_fail`: to a check
(the default), to a person, or nowhere. No reader calls
[`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
yet, so in this release nothing gates on a signal.

## The statistics underneath

The functions above rest on five that can be used on their own.

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
instead, and only percent agreement below 30 items.

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
inclusion probabilities, optionally by stratum; it is how screening
recall is weighted on a stacked reference.
[`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md) is
the prediction-powered estimate behind
[`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md).
[`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md)
runs the alternative annotator test of Calderon, Reichart and Dror
(2025), which asks whether a model’s labels can stand in for those of
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
rate omega is 1 and the test passes; it needs at least 30 items with two
or more human labels, and warns below 50.

## Next

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
