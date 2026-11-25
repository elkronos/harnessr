# Comparing methods and settings

Should this corpus be read with `retrieve` or `map_reduce`? Do smaller
chunks help? Is `top_k = 1` enough? Does the screener need to see more
of each record? Each of these is a comparison between configurations,
and each can be answered the same way: build one arm per configuration,
run them all on the same labelled questions several times, and read the
report with its intervals.

[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
explains the machinery: references and splits, arms, scorers,
benchmarks, reports, judges. This guide puts it to work on five
comparisons: readers, segmenters and chunk sizes, one setting swept over
its values, screening settings, and a judge against people’s labels.
Each runs offline here on a stand-in model, and each ends in a report
and what it does and does not show. The last section repeats the steps
on your own documents.

## Setting up

``` r

library(harnessr)
old <- hr_options(verbose = FALSE, embedder = "lexical")
op <- options(digits = 3)
hr_register_model("mock-model", context_window = 128000, max_output = 16384,
                  input_usd = 1, output_usd = 4)
```

The stand-in model’s id is `mock-model`; the price gives the benchmarks
a cost to compare. The corpus is twelve short annual reports. Each has
six paragraphs, one topic each, and four questions are asked of each
report. Some sentences share a question’s words without answering it
(“Export revenue rose with prices”), as real reports do, so ranking
chunks by the question’s words can pick the wrong one:

``` r

co <- data.frame(
  place   = c("Ashford", "Bexley", "Carlow", "Dunmore", "Elstow", "Fenwick",
              "Garston", "Hollins", "Irvine", "Jarrow", "Kelso", "Larne"),
  revenue = c(45.2, 51.8, 38.9, 29.4, 61.3, 33.7, 48.5, 27.1, 55.6, 40.2, 36.4, 52.9),
  units   = c(12400, 9800, 15100, 7600, 11200, 8300, 13900, 6900, 10500, 14700, 9100, 12800),
  staff   = c(310, 275, 402, 198, 356, 221, 389, 167, 298, 344, 251, 377),
  exports = c(7, 12, 4, 9, 15, 6, 11, 3, 8, 14, 5, 10))

report <- function(r) paste(c(
  sprintf("%s annual report", r$place),
  sprintf(paste("Results. Revenue was %.1f million dollars in fiscal 2024. Analysts expect",
                "revenue to reach %.1f million dollars by 2026 if prices hold. Export",
                "revenue rose with prices."), r$revenue, round(r$revenue * 1.2, 1)),
  sprintf(paste("Operations. The plant in %s made %s units. Output was limited by a two week",
                "shutdown for repairs. A second line is planned for next year."),
          r$place, format(r$units, big.mark = ",")),
  sprintf(paste("People. Staff numbered %d at year end. Training hours per person doubled.",
                "Turnover fell for the third year."), r$staff),
  sprintf(paste("Trade. Exports rose %d percent. Most shipments went by sea. Units shipped",
                "abroad by the plant are counted separately."), r$exports),
  paste("Governance. The audit committee met four times. Staff representatives joined",
        "the board at year end.")),
  collapse = "\n\n")
docs <- setNames(vapply(seq_len(nrow(co)), function(i) report(co[i, ]), ""), co$place)

qs <- c(revenue = "What was revenue in fiscal 2024?",
        units   = "How many units did the plant make?",
        staff   = "How many staff were there at year end?",
        exports = "By how much did exports rise?")
grid_q <- expand.grid(topic = names(qs), place = co$place, stringsAsFactors = FALSE)
answer_of <- function(place, topic) {
  r <- co[co$place == place, ]
  switch(topic, revenue = sprintf("%.1f million", r$revenue),
         units = format(r$units, big.mark = ","), staff = as.character(r$staff),
         exports = sprintf("%d percent", r$exports))
}
qa <- gr_qa_reference(
  questions = setNames(unname(qs[grid_q$topic]), paste(grid_q$place, grid_q$topic, sep = "_")),
  documents = unname(docs[grid_q$place]),
  answers   = unname(Map(answer_of, grid_q$place, grid_q$topic)),
  cluster   = grid_q$place,
  split     = ifelse(grid_q$place %in% co$place[1:4], "dev", "test"))
qa
#> <hr_reference> 48 item(s) in 12 cluster(s)
#>   splits: dev 16, test 32 
#>   hash: c3a742404b80
```

The first four reports are the dev split, kept for tuning; the other
eight are the test split, which every reported comparison is scored on.
Each report is one cluster, since four questions about one report share
its quirks.
[`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
draws the split for a set of your own.

The stand-in reader answers from what it is shown. It finds the sentence
that answers the question in its prompt and returns it, or
`NOT_IN_DOCUMENT` when the prompt does not hold it. Like a real model it
gets worse as its prompt grows: it misses a sentence it was shown with
probability equal to the prompt’s length in characters over 6000.

``` r

pattern <- c(revenue = "Revenue was [0-9.]+ million dollars in fiscal 2024",
             units = "made [0-9,]+ units", staff = "Staff numbered [0-9]+",
             exports = "Exports rose [0-9]+ percent")
reader <- hr_mock_client(function(messages, params) {
  seen <- paste(vapply(messages, function(m) as.character(m$content), ""), collapse = " ")
  asked <- sub(".*Question", "", seen)
  topic <- names(pattern)[vapply(c("revenue", "units", "staff", "exports"), grepl,
                                 logical(1), x = asked, ignore.case = TRUE)][1]
  hit <- regmatches(seen, regexpr(pattern[[topic]], seen))
  if (!length(hit)) return("NOT_IN_DOCUMENT")
  if (runif(1) < nchar(seen) / 6000) return("The report does not say clearly.")
  paste0(hit, ".")
})
```

## Which settings there are

Every setting a reader, segmenter or ingest step takes is declared in a
schema, with its type, default, range, tier and the evidence behind its
default.
[`gr_settings()`](https://elkronos.github.io/harnessr/reference/gr_settings.md)
returns the schema; printed, it shows each setting’s tier and evidence
status:

``` r

gr_settings("segment")
#> <hr_schema> 20 parameter(s)
#>   context_source             enum          advanced  untested  metadata|llm
#>   max_tokens                 integer       basic     untested  [32, 1e+06]
#>   overlap_tokens             integer       basic     untested  [0, f()]
#>   min_tokens                 integer       advanced  untested  [0, f()]
#>   method                     module_ref    basic     untested  
#>   separators                 string_vector advanced  untested  
#>   prefix_section             boolean       advanced  untested  
#>   semantic_window            integer       advanced  untested  [1, 10]
#>   semantic_percentile        number        advanced  untested  [50, 99.5]
#>   proposition_batch_tokens   integer       advanced  untested  [200, 4000]
#>   parallel                   boolean       advanced  untested  
#>   context_reply_tokens       integer       advanced  untested  [16, 4000]
#>   context_document_tokens    integer       advanced  untested  [100, 1e+06]
#>   proposition_reply_tokens   integer       advanced  untested  [100, 1e+06]
#>   semantic_threshold         enum          advanced  untested  percentile|texttiling
#>   table_packing              enum          advanced  untested  rows|grouped
#>   proposition_check          enum          advanced  untested  count|drop
#>   proposition_context_tokens integer       advanced  untested  [0, 2000]
#>   packing                    enum          advanced  untested  greedy|balanced
#>   runt_merge                 enum          advanced  untested  backward|both
```

`basic` marks the few settings most comparisons vary; the read schema’s
are `reader`, `model`, `top_k`, `cite` and `verify`.
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) adds the
default and where it came from:

``` r

rs <- as.data.frame(gr_settings("read"))
rs[rs$name %in% c("top_k", "lexical_blend", "bm25_k1"), c("name", "default", "status", "source")]
#>             name default   status
#> 13         top_k       6 untested
#> 31       bm25_k1     1.5    cited
#> 33 lexical_blend     0.5 untested
#>                                                                                                                                            source
#> 13                                                                                         A common starting value for retrieval; not tuned here.
#> 31 Robertson and Zaragoza (2009), "The Probabilistic Relevance Framework: BM25 and Beyond", give k1 between 1.2 and 2.0 as usual; not tuned here.
#> 33                                                                                          An even blend, set when the offline path was written.
```

Most defaults are `untested`: they were chosen, not measured. That is
what makes them worth comparing. Any setting in these schemas can be
given to
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md) in
`settings`, which takes what
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
takes in `...`.

## The rules every comparison here follows

- **Tune on dev, report on test.** Settings are chosen by looking at dev
  results, which are never reported. A setting chosen on the test split
  and then reported on it is fitted to those questions, and its
  advantage is partly luck.
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  leaves dev rows out.
- **At least five runs, and ten when the report asks.** A model asked
  the same question twice can answer differently. With fewer than five
  runs,
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  warns and
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  gives no intervals. When run-to-run variance is above 10% of the
  total, the report’s notes say “use runs = 10”.
- **One governor for the whole benchmark.** The default limits are for
  one read (400 calls). Size
  [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  for arms x items x runs x calls per run, and check afterwards how much
  of it was used.
- **Intervals, not point estimates.** An arm ahead by 5 points with an
  interval from -3 to 13 has not been shown to be better.
- **Know the smallest difference the design can see.**
  [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  gives it before anything is run.

The test split here is 32 questions in 8 reports. If the two arms
disagree on about 15% of questions and questions in one report are
correlated at 0.1:

``` r

hr_mdd(32, n_clusters = 8, icc = 0.1, p_disc = 0.15)
#> <hr_mdd> 25.5 points at 80% power, one-sided alpha 0.025
#>   32 items in 8 clusters (m = 4, 4 after cv 0), ICC_D 0.1: DE 1.3, n_eff 24.6
#>   p_disc 0.15
hr_n_needed(0.05, m = 4, icc = 0.1, p_disc = 0.15)
#> <hr_n_needed> 5.0 points at 80% power, one-sided alpha 0.025
#>   n_eff 477 effective items; DE 1.3, so 624 items in 156 clusters of 4
```

So no comparison below is designed to detect a difference smaller than
about 25.5 points, and a 5 point difference would need about 624
questions in 156 reports. A difference the report calls uncertain at
this size is not evidence that the arms are the same.

## Readers on the same questions

Three readers, each with the segmentation it is usually paired with:
`stuff` sends the whole report in one request, `map_reduce` reads
60-token chunks one by one and merges the answers, and `retrieve` sends
the two 60-token chunks of sentences that rank highest:

``` r

readers <- list(
  gr_arm("fast", name = "stuff"),
  gr_arm("thorough", settings = list(max_tokens = 60, overlap_tokens = 0), name = "map_reduce"),
  gr_arm("fast", settings = list(reader = "retrieve", top_k = 2, method = "sentence",
                                 max_tokens = 60), name = "retrieve"))
gov <- hr_governor(max_calls = 3 * 32 * 10 * 8, max_cost_usd = 1)
b_read <- hr_benchmark(readers, qa, runs = 10, client = reader,
                       scorer = gr_scorer_answer(), governor = gov)
b_read
#> <hr_bench> 3 arm(s) x 32 item(s) in 8 cluster(s) x 10 run(s); split test; scorer answer_contains
#>  arm        accuracy runs wrong failed budget_stop usd   
#>  stuff      0.847    320  49    0      0           0.0972
#>  map_reduce 0.906    320  30    0      0           0.2430
#>  retrieve   0.894    320  34    0      0           0.0686
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
hr_trace_summary(attr(b_read, "trace"))[, c("calls", "tokens_in", "tokens_out")]
#>   calls tokens_in tokens_out
#> 1  1920    304730      26029
```

Each arm runs 10 times, not 5. With `runs = 5` the report’s notes said
“Run-to-run variance is 81% of the total, above 10%: use runs = 10.”,
and the rule below is to do what that line says. The governor allows 8
calls per run for each of 3 arms, 32 questions and 10 runs, 7,680 in
all, which is more than `map_reduce` needs on reports this short; the
trace shows 1,920 used.

``` r

r_read <- hr_report(b_read, B = 200)
r_read$accuracy[, c("arm", "estimate", "lower", "upper")]
#>          arm estimate lower upper
#> 1      stuff    0.847 0.783 0.894
#> 2 map_reduce    0.906 0.870 0.933
#> 3   retrieve    0.894 0.780 0.952
r_read$contrasts[, c("arm1", "arm2", "estimate", "lower", "upper")]
#>         arm1       arm2 estimate   lower    upper
#> 1      stuff map_reduce  -0.0594 -0.1140 -0.00472
#> 2      stuff   retrieve  -0.0469 -0.1293  0.03555
#> 3 map_reduce   retrieve   0.0125 -0.0711  0.09610
r_read$simultaneous[, c("arm1", "arm2", "estimate", "lower", "upper", "critical")]
#>         arm1       arm2 estimate   lower   upper critical
#> 1      stuff map_reduce  -0.0594 -0.1269 0.00816     2.92
#> 2      stuff   retrieve  -0.0469 -0.1487 0.05497     2.92
#> 3 map_reduce   retrieve   0.0125 -0.0908 0.11580     2.92
r_read$cost[, c("arm", "usd_per_item", "tokens_per_item")]
#>          arm usd_per_item tokens_per_item
#> 1      stuff     0.000304             268
#> 2 map_reduce     0.000759             588
#> 3   retrieve     0.000214             178
```

`map_reduce` has the highest estimate, 0.906 against 0.894 for
`retrieve` and 0.847 for `stuff`. The intervals below do not show that
it is more accurate than either. `contrasts` gives each pair its own 95%
interval. For `stuff` against `map_reduce` that interval, -0.114 to
-0.005, just excludes 0, but three pairs were compared, and with three
intervals at 95% each the chance that at least one excludes 0 by luck is
higher than 5%. `simultaneous` gives intervals that hold for all three
pairs at once (max-t). Its `critical` column is the multiplier of the
standard error, 2.92 here, larger than the one a single pair’s interval
uses, so each interval is wider. There the same difference runs from
-0.127 to 0.008, which includes 0. So this design has not shown that
`stuff` is worse. When more than two arms are compared and no one pair
was named before the run, read `simultaneous`.

`map_reduce` against `retrieve` is 0.013, from -0.091 to 0.116 at once:
no difference is shown. The minimum detectable difference is 25.5
points: a true difference that size would be shown 80% of the time. A
true difference of 1 point would be shown much less often, though not
never, so this result does not say the two readers are equally accurate.
The cost difference is large: `map_reduce` sends 588 tokens per question
against 178 for `retrieve`, and costs 3.5 times as much. Whether an
unproven point is worth that is a decision the report informs and does
not make. The stand-in is built to miss more in long prompts, so these
figures say nothing about any real model; they show how to read the
report.

## Segmenters and chunk sizes

A segmenter is tested first for nothing, then with a model. Two free
measures come before any benchmark.

### Boundaries against the topics

Each report’s six paragraphs are its topics, so the paragraphs are a
reference segmentation.
[`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md)
maps a segmentation to sentence boundaries, and
[`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
and
[`gr_seg_windowdiff()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
measure how far a chunking’s boundaries fall from the reference’s: 0
means the same boundaries, and lower is better. The settings form a grid
of three segmenters at two sizes:

``` r

seg_grid <- expand.grid(method = c("fixed", "sentence", "paragraph"),
                        max_tokens = c(40, 80), stringsAsFactors = FALSE)
seg_grid$name <- paste(seg_grid$method, seg_grid$max_tokens, sep = "_")
dev_docs <- docs[co$place[1:4]]

boundary_error <- function(method, max_tokens) {
  per_doc <- vapply(dev_docs, function(d) {
    ref <- gr_seg_boundaries(strsplit(d, "\n\n")[[1]], d)
    hyp <- gr_seg_boundaries(gr_segment(d, list(method = method, max_tokens = max_tokens)), d)
    c(pk = gr_seg_pk(ref, hyp), windowdiff = gr_seg_windowdiff(ref, hyp))
  }, numeric(2))
  round(rowMeans(per_doc), 3)
}
cbind(seg_grid["name"], t(mapply(boundary_error, seg_grid$method, seg_grid$max_tokens)))
#>                     name    pk windowdiff
#> fixed           fixed_40 0.444      0.444
#> sentence     sentence_40 0.722      0.722
#> paragraph   paragraph_40 0.194      0.222
#> fixed.1         fixed_80 0.500      0.500
#> sentence.1   sentence_80 0.556      0.556
#> paragraph.1 paragraph_80 0.278      0.278
```

A paragraph here is about 30 tokens, so at 40 tokens the paragraph
segmenter makes most chunks one paragraph and has the lowest error, Pk
0.194. At 80 tokens it packs two paragraphs into a chunk and misses the
boundary between them (0.278). The sentence segmenter packs sentences
across paragraph ends and does worst, 0.722 at 40 tokens, worse than
fixed windows (0.444), which ignore the text. The two measures differ
only for `paragraph_40` (0.194 and 0.222): WindowDiff also counts a
window in which both have a boundary but not the same number. Both say
where chunk edges fall, not whether a reader will find the answer.

### Whether the answer is in the chunks retrieved

[`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)
ranks each segmentation’s chunks for each question as the `retrieve`
reader does and counts the questions whose answer is in the first `k`
chunks. It calls no model with the lexical embedder:

``` r

seg_specs <- setNames(lapply(seq_len(nrow(seg_grid)), function(i) {
  list(method = seg_grid$method[i], max_tokens = seg_grid$max_tokens[i])
}), seg_grid$name)
rec <- gr_seg_recall(qa, seg_specs, k = c(1, 2), split = "dev")
rec[rec$k == 1, c("segmenter", "hits", "questions", "recall", "no_chunk", "chunks")]
#>       segmenter hits questions recall no_chunk chunks
#> 1      fixed_40    8        16   0.50        0    5.0
#> 3   sentence_40   12        16   0.75        0    7.0
#> 5  paragraph_40   12        16   0.75        0    6.5
#> 7      fixed_80   12        16   0.75        0    3.0
#> 9   sentence_80    8        16   0.50        0    4.0
#> 11 paragraph_80   12        16   0.75        0    3.0
```

With one chunk retrieved, four settings put the answer first for 12 of
the 16 dev questions, and `fixed_40` and `sentence_80` for 8. `no_chunk`
is 0 throughout, so no chunk edge cut an answer in two: the misses are
in the ranking, where a chunk that shares the question’s words (such as
“Export revenue rose with prices”) can outrank the one that answers it.
`attr(rec, "ranks")` gives the rank of the answering chunk for every
question. Neither measure called a model.

### A grid of arms on dev, then one comparison on test

The same grid becomes arms, one per row, each the `retrieve` reader with
`top_k = 1`, and runs on the dev split:

``` r

seg_arms <- lapply(seq_len(nrow(seg_grid)), function(i) {
  gr_arm("fast", settings = list(reader = "retrieve", top_k = 1,
                                 method = seg_grid$method[i],
                                 max_tokens = seg_grid$max_tokens[i]),
         name = seg_grid$name[i])
})
b_seg_dev <- hr_benchmark(seg_arms, qa, runs = 5, client = reader, split = "dev",
                          scorer = gr_scorer_answer(),
                          governor = hr_governor(max_calls = 6 * 16 * 5, max_cost_usd = 1))
b_seg_dev
#> <hr_bench> 6 arm(s) x 16 item(s) in 4 cluster(s) x 5 run(s); split dev; scorer answer_contains
#>  arm          accuracy dev   runs wrong failed budget_stop usd   
#>  fixed_40     -        0.475 80   2     40     0           0.0146
#>  sentence_40  -        0.713 80   3     20     0           0.0133
#>  paragraph_40 -        0.725 80   2     20     0           0.0136
#>  fixed_80     -        0.688 80   5     20     0           0.0178
#>  sentence_80  -        0.500 80   0     40     0           0.0151
#>  paragraph_80 -        0.688 80   5     20     0           0.0158
#>   480 row(s) on the dev split are not reportable; their accuracy is the dev column alone.
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
```

The dev column is the only accuracy printed, and
[`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
would refuse these rows. On dev `paragraph_40` scores highest, 0.725,
just above `sentence_40` at 0.713, and the two arms whose recall at 1
was 0.50 score lowest (0.475 and 0.500). The best of six close dev
scores is partly luck, which is why it is confirmed on test. The
comparison there is with the paragraph segmenter at 80 tokens, the other
size of the same segmenter:

``` r

b_seg <- hr_benchmark(seg_arms[match(c("paragraph_40", "paragraph_80"), seg_grid$name)], qa,
                      runs = 10, client = reader, scorer = gr_scorer_answer(),
                      governor = hr_governor(max_calls = 2 * 32 * 10, max_cost_usd = 1))
r_seg <- hr_report(b_seg, B = 200)
r_seg$accuracy[, c("arm", "estimate", "lower", "upper")]
#>            arm estimate lower upper
#> 1 paragraph_40    0.834 0.695 0.917
#> 2 paragraph_80    0.703 0.666 0.738
r_seg$contrasts[, c("arm1", "arm2", "estimate", "lower", "upper")]
#>           arm1         arm2 estimate  lower upper
#> 1 paragraph_40 paragraph_80    0.131 0.0132 0.249
```

This benchmark also runs 10 times: at 5 runs its notes said run-to-run
variance was 15% of the total. On test, `paragraph_40` scores 0.834 and
`paragraph_80` 0.703, and the difference of 0.131 has an interval from
0.013 to 0.249, which excludes 0. It can be reported because it is one
contrast, and both arms were chosen on dev before their test results
were seen. It still carries the width of 8 reports: the gain could be
anything from 1 to 25 points.

## One setting swept over its values

`top_k` is how many chunks `retrieve` sends. More chunks make it
likelier the answer is among them and the prompt longer. The sweep runs
on dev:

``` r

top_k_arms <- lapply(c(1, 2, 4), function(k) {
  gr_arm("fast", settings = list(reader = "retrieve", top_k = k, method = "sentence",
                                 max_tokens = 40), name = paste0("top_k_", k))
})
b_k_dev <- hr_benchmark(top_k_arms, qa, runs = 5, client = reader, split = "dev",
                        scorer = gr_scorer_answer(),
                        governor = hr_governor(max_calls = 3 * 16 * 5, max_cost_usd = 1))
b_k_dev
#> <hr_bench> 3 arm(s) x 16 item(s) in 4 cluster(s) x 5 run(s); split dev; scorer answer_contains
#>  arm     accuracy dev   runs wrong failed budget_stop usd   
#>  top_k_1 -        0.738 80   1     20     0           0.0133
#>  top_k_2 -        0.950 80   4      0     0           0.0153
#>  top_k_4 -        0.912 80   7      0     0           0.0199
#>   240 row(s) on the dev split are not reportable; their accuracy is the dev column alone.
#>   Descriptive only: accuracy is the mean over runs within each item, then over labelled items, with no interval.
```

`top_k = 2` is highest on dev, 0.950. `top_k = 1` misses the questions
whose answer ranks second, and `top_k = 4` gives the stand-in a longer
prompt, which it reads worse. On test the choice is compared with
`top_k = 4`, the value nearer the default of 6:

``` r

b_k <- hr_benchmark(top_k_arms[2:3], qa, runs = 10, client = reader,
                    scorer = gr_scorer_answer(),
                    governor = hr_governor(max_calls = 2 * 32 * 10, max_cost_usd = 1))
r_k <- hr_report(b_k, B = 200)
r_k$contrasts[, c("arm1", "arm2", "estimate", "lower", "upper")]
#>      arm1    arm2 estimate  lower upper
#> 1 top_k_2 top_k_4   0.0687 0.0179  0.12
r_k$cost[, c("arm", "usd_per_item", "tokens_per_item")]
#>       arm usd_per_item tokens_per_item
#> 1 top_k_2     0.000192             155
#> 2 top_k_4     0.000250             213
```

With 10 runs (at 5, the notes put run-to-run variance at 79% of the
total), `top_k = 2` is 6.9 points more accurate than `top_k = 4` on
test, with an interval from 1.8 to 12.0 points, and sends 155 tokens per
question instead of 213. The difference is far below the 25.5-point
minimum detectable difference above, and the interval still excludes 0.
That is not a contradiction. The 25.5 points is the true difference this
design would detect 80% of the time, on an assumed disagreement of 15%
and a correlation of 0.1; it is not the width of an interval and not a
floor under what can be shown. A smaller true difference is detected
less often, not never. The interval rests on what these two arms did.
Plan with values measured in a pilot on dev, and read the result from
the report.

## Screening settings

An arm can be any function, so a screening setting is compared the same
way. Here 16 records of hand-hygiene studies are screened for randomised
comparisons. Every record opens with the same background, and the
sentence that settles it comes in the second, third or fourth sentence,
so a screener shown too little of a record cannot decide:

``` r

rec_dir <- file.path(tempdir(), "compare-records")
dir.create(rec_dir, showWarnings = FALSE)
set.seed(4)
n <- 16
design <- rep(c("randomly assigned", "followed an existing cohort of"), length.out = n)
lead <- c("Hand hygiene in hospital wards has been studied for decades.",
          "Compliance varies between units and shifts.",
          "Audits rarely capture night work.")
where <- rep(1:3, length.out = n)
records <- vapply(seq_len(n), function(i) {
  method <- sprintf("We %s %d nurses across %d wards.", design[i], sample(80:300, 1),
                    sample(4:12, 1))
  body <- append(lead, method, after = where[i])
  paste(c(sprintf("Study %02d.", i), body, "Infections were recorded for six months."),
        collapse = " ")
}, "")
paths <- file.path(rec_dir, sprintf("study%02d.txt", seq_len(n)))
for (i in seq_len(n)) writeLines(records[i], paths[i])

protocol <- gr_protocol("hygiene", question = "Does hand hygiene training reduce infections?",
                        include = "Reports a randomised comparison",
                        exclude = "Is an observational study")
screens <- hr_reference(setNames(as.list(paths), sprintf("s%02d", seq_len(n))),
                        labels = ifelse(grepl("randomly", design), "include", "exclude"),
                        cluster = sprintf("batch%d", rep(1:4, each = 4)), split = "test")
```

The stand-in screener decides from the allocation sentence when it is in
the excerpt it was shown, and says `unclear` otherwise. One arm per
value of `screen_tokens`, the cap on what the screener is shown; each
run screens one record through
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
on the run’s trace and at its draw index:

``` r

screener <- hr_mock_client(function(messages, params) {
  shown <- paste(vapply(messages, function(m) as.character(m$content), ""), collapse = " ")
  reply <- function(d, why, crit) {
    sprintf('{"decision":"%s","reason":"%s","criterion":%s,"quote":null}', d, why, crit)
  }
  if (grepl("randomly assigned", shown)) {
    return(reply("include", "Randomised.", '"Reports a randomised comparison"'))
  }
  if (grepl("existing cohort", shown)) {
    return(reply("exclude", "Observational.", '"Is an observational study"'))
  }
  reply("unclear", "The excerpt does not say how nurses were allocated.", "null")
})
screen_arm <- function(tokens) {
  hr_arm(paste0("tokens_", tokens), function(item, ctx) {
    gr_screen(item, protocol, client = ctx$client, screen_tokens = ctx$params$tokens,
              trace = ctx$trace)$table$decision
  }, params = list(tokens = tokens))
}
b_scr <- hr_benchmark(list(screen_arm(40), screen_arm(80)), screens, runs = 5,
                      client = screener,
                      governor = hr_governor(max_calls = 2 * 16 * 5, max_cost_usd = 1))
table(b_scr$arm, b_scr$outcome)
#>            
#>             exclude include unclear
#>   tokens_40       0      15      65
#>   tokens_80      40      40       0
r_scr <- hr_report(b_scr, B = 200)
r_scr$accuracy[, c("arm", "estimate", "lower", "upper")]
#>         arm estimate  lower upper
#> 1 tokens_40    0.188 0.0589  0.46
#> 2 tokens_80    1.000 0.7136  1.00
r_scr$cost[, c("arm", "usd_per_item", "tokens_per_item")]
#>         arm usd_per_item tokens_per_item
#> 1 tokens_40     0.000568             352
#> 2 tokens_80     0.000585             363
```

At 40 tokens the allocation sentence fits in the excerpt for 3 of the 16
records, and the screener says `unclear` about the other 13: accuracy
0.188, with an interval from 0.059 to 0.460, against 1.000 at 80 tokens.
That interval, 0.714 to 1.000, is Korn and Graubard’s, one-sided because
every run was right. The cap saves little, 352 tokens per record against
363, since the instructions and criteria are most of each request. An
`unclear` decision is counted wrong here. It is not an exclusion, since
a person settles it, but it costs that person a look; a scorer that
counts it another way is a few lines with
[`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md).

## A judge against people’s labels

Some outputs need a judge, and a judge is a model whose decisions have
to be checked against people before its scores mean anything. A pairwise
judge says which of two texts answers better. Its labels come from a
pairwise sheet: two texts per row, in an order drawn for that row, with
the order kept in an opaque key so that the person cannot tell which
text is which candidate.

Here 180 pairs set the right sentence against a wrong one (the 2026
forecast in place of the 2024 figure), or two right sentences against
each other:

``` r

right <- sprintf("Revenue was %.1f million dollars in fiscal 2024.", co$revenue)
wrong <- sprintf("Revenue will reach %.1f million dollars by 2026.", round(co$revenue * 1.2, 1))
pick <- rep(seq_len(nrow(co)), length.out = 180)
kind <- rep(c("A", "B", "tie"), each = 60)
pairs <- data.frame(
  item_id = sprintf("p%03d", 1:180),
  question = "What was revenue in fiscal 2024?",
  candidate_a = ifelse(kind == "B", wrong[pick], right[pick]),
  candidate_b = ifelse(kind == "A", wrong[pick], right[pick]))
sheet_path <- file.path(tempdir(), "pairs.csv")
sheet <- gr_label_sheet("pairwise", pairs, path = sheet_path)
head(sheet[, c("item_id", "text_1", "text_2", "order_key")], 3)
#>   item_id                                           text_1
#> 1    p001 Revenue will reach 54.2 million dollars by 2026.
#> 2    p002 Revenue was 51.8 million dollars in fiscal 2024.
#> 3    p003 Revenue was 38.9 million dollars in fiscal 2024.
#>                                             text_2
#> 1 Revenue was 45.2 million dollars in fiscal 2024.
#> 2 Revenue will reach 62.2 million dollars by 2026.
#> 3 Revenue will reach 46.7 million dollars by 2026.
#>                                            order_key
#> 1 pk74fe8ffc5d402f4cab21b935c58cde250f4d0f04721af381
#> 2 pkca3ed8308d8da28a3560dd6164f3362c8c59210c37c6614e
#> 3 pk861aaaba18ad688ed514afc499ed67224d091e42cf6b22f9
```

A person fills `preferred` with 1, 2 or tie for each row as shown. Here
the filling is simulated: the text with the 2024 figure is preferred,
and two right texts are a tie.

``` r

filled <- read.csv(sheet_path, fileEncoding = "UTF-8-BOM")
has_2024 <- function(x) grepl("fiscal 2024", x)
filled$preferred <- ifelse(has_2024(filled$text_1) & has_2024(filled$text_2), "tie",
                           ifelse(has_2024(filled$text_1), "1", "2"))
write.csv(filled, sheet_path, row.names = FALSE, na = "")
labels <- gr_read_labels(sheet_path, "pairwise")
table(shown_first = labels$shown_first, preferred = labels$preferred)
#>            preferred
#> shown_first  A  B tie
#>           A 28 25  29
#>           B 32 35  31
```

[`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
turns each answer back into candidate order with the key: `preferred` is
`A`, `B` or `tie` whichever text was shown first. A key that was edited,
lost or pasted onto another row is an error of class `gr_bad_labels`.

The judge sees each pair in both orders. This stand-in judge prefers the
text with the 2024 figure but, a quarter of the time, simply picks
whichever text it was shown first:

``` r

judge_cl <- hr_mock_client(function(messages, params) {
  txt <- messages[[2]]$content
  a <- grepl("Candidate A:\n[^\n]*fiscal 2024", txt)
  b <- grepl("Candidate B:\n[^\n]*fiscal 2024", txt)
  v <- if (runif(1) < 0.25) "A" else if (a && b) "tie" else if (a) "A" else "B"
  sprintf('{"verdict": "%s", "reason": "Compared."}', v)
})
rubric <- "Which candidate gives fiscal 2024 revenue?"
hr_register_model("mock-judge", context_window = 128000, max_output = 4096,
                  input_usd = 1, output_usd = 4)
set.seed(5)
verdicts <- vapply(seq_len(nrow(pairs)), function(i) {
  j <- hr_judge(c(A = pairs$candidate_a[i], B = pairs$candidate_b[i]), judge_cl,
                mode = "pairwise", model = "mock-judge", rubric = rubric)
  if (identical(j$outcome, "answered")) j$value else NA_character_
}, "")
table(verdicts, useNA = "ifany")
#> verdicts
#>    A    B  tie <NA> 
#>   46   47   29   58
```

A verdict that changes with the order is `unresolved`, recorded as `NA`.
With `positive = "A"`,
[`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
measures how well the judge finds the pairs where candidate A is better;
a tie and a B both count as negative:

``` r

cfg_pair <- hr_judge_config("mock-judge", rubric, mode = "pairwise")
v_pair <- hr_judge_validate(cfg_pair, data.frame(judge = verdicts, human = labels$preferred),
                            positive = "A", B = 200)
v_pair
#> <hr_judge_validation> config 9c12c6f5550d (pairwise, mock-judge)
#>   items: 180 labelled (60 positive, 120 negative), 58 unresolved, 0 dropped
#>   kappa:       0.814 [0.719, 0.897]
#>   sensitivity: 0.767 [0.646, 0.856], n = 60, half-width 0.105
#>   specificity: 1.000 [0.969, 1.000], n = 120
#>   swap inconsistency: 0.322 [0.258, 0.394], 58 of 180
```

The judge finds 0.767 of the 60 pairs where people preferred A, with an
interval from 0.646 to 0.856, and never prefers A where they did not
(specificity 1.000). Its swap inconsistency is 0.322: on 58 of 180 pairs
the verdict changed with the order. Those count as not preferring A,
which is how a scorer would count them, and they are why sensitivity is
low; a judge that changes its mind on a third of pairs needs a better
rubric or model before its scores are used. With `positive = "A"` a tie
is negative, so a judge that calls a tie where people preferred A has
missed it.

### When the judge is the model it grades

A model grading its own answers can favour them.
[`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
takes the judge’s model in `judge_model` (the configuration’s by
default), and
[`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
marks each run whose requests went to that same model in `self_judged`.
Nothing is refused, and the report says so. Here the grade judge runs on
`mock-model`, the model the arm reads with; its validation record is
simulated, as in
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):

``` r

cfg_grade <- hr_judge_config("mock-model", "Does the response give the reference's answer?",
                             mode = "grade")
set.seed(3)
human <- rep(c(TRUE, FALSE), c(60, 60))
v_grade <- hr_judge_validate(cfg_grade, data.frame(judge = ifelse(runif(120) < 0.9, human, !human),
                                                   human = human), B = 200)
grader <- hr_mock_client(function(messages, params) {
  txt <- messages[[2]]$content
  block <- function(head) regmatches(txt, regexec(paste0(head, ":\n([^\n]*)"), txt))[[1]][2]
  ok <- grepl(block("Reference answer"), block("Response to grade"), fixed = TRUE)
  sprintf('{"verdict": "%s", "reason": "Compared."}', if (ok) "pass" else "fail")
})
judged <- hr_benchmark(readers[3], qa, runs = 10, client = reader,
                       scorer = hr_scorer_judge(cfg_grade, v_grade, grader),
                       governor = hr_governor(max_calls = 32 * 10, max_cost_usd = 1))
table(judged$self_judged, useNA = "ifany")
#> 
#> TRUE 
#>  320
cat(hr_report(judged, B = 200)$notes, sep = "\n")
#> 320 of 320 runs were graded by a judge on the arm's own model (retrieve: 320). A model grading its own output can favour it; compare with a judge on another model, or with human labels (hr_judge_ppi()).
#> More than 5% of the cost of retrieve rests on estimated token counts; read its cost as approximate.
#> Cost, pass^k, frontier share and rank intervals come from the cluster bootstrap, which can undercover below 300 items or 30 clusters; read them as rough.
#> The frontier share (how often an arm is on the cost-accuracy frontier over resamples) is an extension, not a published standard.
```

All 320 runs, 32 questions times 10, are marked `self_judged`, and the
first note says so. At 5 runs the notes put run-to-run variance at 82%
of the total and asked for 10, so this benchmark runs 10 times; at 10
the notes no longer ask for more.

`judge_model = "mock-judge"` would mark the same runs `FALSE`, and a run
with no model request is `NA`. The match is exact, so give the served
model id when the provider names its model differently from the one
asked for.

## Reading a comparison honestly

The five comparisons above end in reports, and each has the same limits.

- **Read the interval of the difference, not the two accuracies.** A
  contrast whose interval covers 0 has not shown a difference. With more
  than two arms, read `simultaneous` unless one pair was named before
  the run.
- **Hold the result against the minimum detectable difference.** At 32
  questions in 8 reports, a real gain of 5 points would usually be
  missed.
  [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  says how many questions would show it.
- **Report only test results.** The grids and sweeps above were read on
  dev, one setting was chosen there, and only that setting and one
  comparator were run on test: `paragraph_40` against `paragraph_80`,
  and `top_k = 2` against `top_k = 4`. Reporting the best of six dev
  arms as if it were one planned comparison overstates it.
- **Five runs is the minimum.** When the report’s notes say run-to-run
  variance is more than 10% of the total, use 10. The reader, segmenter,
  `top_k` and judge benchmarks on test all said so at 5 runs (81%, 15%,
  79% and 82%), so they run 10 times.
- **Size the governor for the whole benchmark** and compare its limit
  with the calls the trace records. A run stopped by a limit is counted
  wrong.
- **The free measures are not the outcome.** Pk, WindowDiff and recall
  at k say why an arm may do well; only the benchmark says whether it
  does.
- **A judge’s scores are as good as its validation.** Validate it
  against blind labels, say when it graded its own model, and correct
  judge-scored accuracy with
  [`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md).

## On your own documents

The same steps on real documents and a real model. Nothing here runs
when the guide is built. Results go to a directory you name; this uses
the per-user data directory, never the package’s own folder:

``` r

out <- file.path(tools::R_user_dir("harnessr", "data"), "compare")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# 1. Questions about your documents, one row each, labelled by a person.
questions <- read.csv("my-questions.csv")   # columns: document, question
gr_label_sheet("qa", questions, path = file.path(out, "qa-labels.csv"))
# ... a person fills the sheet ...
lab <- gr_read_labels(file.path(out, "qa-labels.csv"), "qa", items = questions)
# Whole documents to dev or test; the shares are yours to choose.
lab <- hr_assign_splits(lab, props = c(dev = 0.3, test = 0.7), seed = 2026)$items
qa_own <- gr_qa_reference(
  questions = setNames(lab$question, lab$item_id), documents = lab$document,
  answers = as.list(ifelse(lab$answerable, lab$answer, NA)),
  unanswerable = lab$item_id[!lab$answerable], split = lab$split)

# 2. Free measures on dev: which segmentations put answers in the top chunks.
gr_seg_recall(qa_own, seg_specs, k = c(1, 3, 5), split = "dev")

# 3. The arms, tuned on dev.
cl <- hr_client()
dev <- hr_benchmark(top_k_arms, qa_own, runs = 5, client = cl, split = "dev",
                    scorer = gr_scorer_answer(),
                    governor = hr_governor(max_calls = 5000, max_cost_usd = 20))
dev

# 4. The arm chosen on dev against the current default on test, then the
#    report. Set `chosen` to the arm with the best dev accuracy in step 3.
chosen <- top_k_arms[[2]]
current <- gr_arm("fast", settings = list(reader = "retrieve", method = "sentence",
                                          max_tokens = 40), name = "top_k_default")
n_test <- sum(qa_own$split == "test")
hr_mdd(n_test, n_clusters = length(unique(qa_own$cluster[qa_own$split == "test"])),
       icc = 0.1, p_disc = 0.15)
# Use runs = 10 if the report's notes say run-to-run variance is above 10%.
test <- hr_benchmark(list(chosen, current), qa_own, runs = 5, client = cl,
                     scorer = gr_scorer_answer(),
                     governor = hr_governor(max_calls = 2 * n_test * 5 * 2, max_cost_usd = 20))
rpt <- hr_report(test)
rpt

# 5. Keep the results with the run, outside the package.
saveRDS(test, file.path(out, "test-bench.rds"))
writeLines(as_json(rpt), file.path(out, "test-report.json"))
```

`max_calls` and `max_cost_usd` above are examples: set them from the
number of arms, test questions, runs and calls per run
([`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
lists each reader’s calls), with room to spare.

## Next

- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  references, scorers, intervals, non-inferiority, judges and the
  statistics underneath.
- [`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md):
  the segmenters and their settings.
- [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md):
  the readers and recipes the arms are built from.
- [`?gr_seg_pk`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md),
  [`?gr_seg_recall`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)
  and
  [`?hr_scorer_judge`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md):
  the measures and the self-judging rule in full.
