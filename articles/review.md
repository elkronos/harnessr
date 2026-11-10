# Many documents and literature reviews

[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
asks one question of one document. Most real work has a folder of them,
and a literature review has a folder, a search behind it, and a write-up
at the end that somebody else has to be able to check. This guide covers
that work in the order it happens:

1.  Asking one question of every document, with
    [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).
2.  Starting a review from a database search, with
    [`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)
    and
    [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md).
3.  The review itself: one trace for every stage,
    [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md),
    then
    [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
    measuring the screening against a person with
    [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
    and
    [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
    (recall against a target, when ranked screening can stop, several
    reviewers), then
    [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
    and its agreement with a person’s table, and
    [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md).
4.  Writing from claims instead of from rows, with
    [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
    [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
    and
    [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md).
5.  Counting and reporting the whole run, with
    [`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
    and
    [`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md).

[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
introduces the package and its ideas, and how one document is read is in
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md).
Read
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
first if you have not set spending limits or a cache: this guide points
to it for both, and for replay. Comparing whole configurations on a
labelled set of questions, with intervals, is in
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md).

## Setting up

Everything below runs offline.
[`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
stands in for the model: its handler is an ordinary R function.
`embedder = "lexical"` keeps retrieval free and deterministic.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")
cl <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

## Reading many documents

Before reading a folder you have not read before,
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
lists what is in it: which extractor reads each file, which have no text
layer and which would be skipped, with no model calls and no key.
[`vignette("ingest")`](https://elkronos.github.io/harnessr/articles/ingest.md)
shows it on a folder and covers what to do about files with no extractor
or no text layer.

[`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
runs several recipes over one document.
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
runs one recipe over many, and returns one row per document. That is the
shape the work usually has: a folder, one question, and a table at the
end.

``` r

reports <- file.path(tempdir(), "reports")
dir.create(reports, showWarnings = FALSE)
writeLines("Revenue was 45.2 million dollars in fiscal 2024.", file.path(reports, "north.txt"))
writeLines("Revenue was 51.8 million dollars in fiscal 2025.", file.path(reports, "south.txt"))

out <- gr_read_many(reports, "What was revenue?", "fast", client = cl)
out$summary[, c("document", "not_found", "chunks_used", "calls", "status")]
#>    document not_found chunks_used calls status
#> 1 north.txt     FALSE           1     1     ok
#> 2 south.txt     FALSE           1     1     ok
```

A directory is expanded by the extractor registry, so registering an
extractor changes which files get picked up. A document keeps the folder
it came from, so `2019/report.txt` and `2020/report.txt` stay
distinguishable instead of collapsing to one name. The full summary also
carries `answer`, `partial`, `reader`, `chunks`, `cached`, `tokens_in`,
`tokens_out`, `cost_usd`, `seconds` and `error`, and
`write.csv(out$summary, ...)` is a reasonable end to a run.

[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
does five things a [`lapply()`](https://rdrr.io/r/base/lapply.html) does
not.

One bad file costs one row. An unreadable document gets
`status = "failed"` and its error in the `error` column, and the other
hundred and ninety-nine answers survive. Pass `on_error = "stop"` if you
would rather it aborted.

Budgets are per document, and the run has its own. Every document gets
its own trace, so `gr_options(max_calls =)` and
`gr_options(max_cost_usd =)` apply to each one exactly as if you had
read it alone, and one enormous document cannot starve the rest. On its
own that leaves the run unbounded: two hundred documents under a
400-call ceiling is a corpus ceiling of eighty thousand calls. So there
are two run-level ceilings.

``` r

out <- gr_read_many(reports, "What was revenue?", "fast", client = cl,
                    max_total_calls = 2000,   # checked BEFORE each document
                    max_total_usd   = 20)     # checked after each one
```

`max_total_calls` is checked before a document, so the overshoot is
bounded by one document’s own ceiling. `max_total_usd` can only be
checked after one, since what a document costs is not knowable until it
has been read. It also needs a model with a registered price, or cost is
unknown rather than zero and you get a `gr_corpus_cost_unknown` warning
instead of a silent free pass. Documents past either ceiling are marked
`"skipped"` rather than dropped. Set neither and the run says once what
its worst case is.
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
and
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
take the same two arguments.

A run can be resumed. Point `store =` at a directory and each result is
written as it completes and restored on a later run. Combined with a
durable response cache, restarting a four-hour job costs approximately
nothing:

``` r

durable <- gr_cache_client(cl, gr_cache(tools::R_user_dir("harnessr", "cache")))
gr_read_many(reports, "What was revenue?", "thorough",
             client = durable, store = file.path(tempdir(), "run-store"))
```

The store is keyed on the document’s path, size and mtime, the question,
the whole pipeline and the model, so an edited document is a new job,
not a stale hit. A
[`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
needs a stable `id` for a store or a cache to be reused by a later
session;
[`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md)
and
[`gr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/gr_ellmer_client.md)
already know what they are.

The same document is read once. The same paper reaches you from three
databases under three filenames. A source whose cleaned text repeats one
already read is not read again: its row is filled in from the first
copy, `status` is `"duplicate"`, and `duplicate_of` names the row it
repeats. Every source you passed still has a row, so
`subset(out$summary, is.na(duplicate_of))` is the deduplicated set and
`sum(!is.na(out$summary$duplicate_of))` is the number to report as
removed. A response cache already made the second copy’s calls free;
what it could not do was stop the duplicate appearing in the results as
a second, independent document.

`document_id`, beside `document` in the summary, is the hash of that
cleaned text. Cite with it. A filename changes when the file is renamed,
collides between folders, and does not exist at all for a document
passed as text, while the id is the same string for the same document in
every run and on every machine.

You can see what it cost. `out$trace` holds the run’s calls, and
[`gr_trace_cost()`](https://elkronos.github.io/harnessr/reference/gr_trace_cost.md)
prices them at each step’s own model, counting only the calls that were
issued. The mock client has no price, so this bill is zero;
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)
explains the columns and how to register a price.

``` r

gr_trace_cost(out$trace)[, c("model", "calls", "paid_calls", "usd")]
#>        model calls paid_calls usd
#> 1 mock-model     2          2   0
```

## From a search to a review

A folder of PDFs cannot say which databases were searched, with what
query, on what date, or how many records came back, and no care further
down substitutes for that.
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)
records the search, and
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
reads the export your reference manager already produces (RIS here):

``` r

search <- gr_search(
  databases = c(PubMed = "(spaced practice[tiab]) AND (retention[tiab])",
                Scopus = 'TITLE-ABS-KEY("spaced practice" AND retention)'),
  dates = "2026-02-14",
  limits = "English; 2000 onwards; primary studies only",
  registration = "PROSPERO CRD42026000000"
)

# Two exports of the same corpus, as two databases would give them.
exports <- file.path(tempdir(), "exports"); dir.create(exports, showWarnings = FALSE)
writeLines(c("TY  - JOUR", "AU  - Smith, J.", "AU  - Okafor, A.",
             "TI  - Cognitive load and retention", "PY  - 2019",
             "DO  - https://doi.org/10.1037/EDU0000123", "DB  - Scopus", "ER  - ",
             "TY  - JOUR", "AU  - Gone, G.", "TI  - Never obtained", "PY  - 2020",
             "DO  - 10.1000/zzz", "DB  - Scopus", "ER  - "),
           file.path(exports, "scopus.ris"))
writeLines(c("TY  - JOUR", "AU  - Smith J", "TI  - Cognitive Load and Retention.",
             "DP  - 2019 Mar", "DO  - 10.1037/edu0000123", "ER  -"),
           file.path(exports, "pubmed.ris"))

pdfs <- file.path(tempdir(), "pdfs"); dir.create(pdfs, showWarnings = FALSE)
writeLines("A randomised trial of spacing.", file.path(pdfs, "smith2019.txt"))

recs <- gr_records(exports, files = pdfs, search = search)
recs
#> <gr_records> 3 record(s) from 2 export(s)
#>   pubmed.ris 1, Scopus 2
#>   records identified       3
#>   duplicates removed       1
#>   records screened         2
#>   reports sought           2
#>   reports retrieved        1
#>   reports not retrieved    1
#>   ! 1 record(s) have no document. They are part of the review and are
#>     reported as sought-but-not-retrieved, not quietly dropped.
```

Hand `recs` to
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
and
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
wherever you would have passed a folder. Four things follow from it that
a folder cannot give you.

The flow counts start at identification.
[`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
begins at records identified rather than at “sources given”, which is
already past the step that decides whether anyone can reproduce the
search.

Records with no document stay visible. Fourteen reports sought and not
retrieved is a finding about the review, and a folder represents it as
nothing at all.

Duplicates are settled by DOI, not by text. The same paper from three
databases is one record, and `duplicate_of` names the row each one
repeats. Where a DOI is missing (preprints, conference papers),
normalised title and year are the fallback, but two records that both
have DOIs and differ are never merged, because similar titles happen and
merging two studies is the error this whole path exists to avoid.

Authors and years become facts.
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
cites by name, and without an export those names came from asking a
model to read a title page. That is the one part of a citation that must
be exactly right, resting on the loosest guarantee in the pipeline. From
an export they are data, joined onto the extraction table, and the model
is still never shown them.

Matching records to files uses the path the export recorded, then the
DOI in the filename, then the title, then first-author surname and year,
which is how people name downloads. An ambiguous match is no match: two
Smith 2019 papers and one `smith2019.pdf` claim nothing, because a coin
flip presented as a match is how one paper’s findings get attributed to
another.

## The review: protocol, screen, extract, write

The single-document pipeline (ingest, segment, read) answers a question.
A corpus job usually wants a table, and a review wants a table plus the
account of it. Four functions cover that, and they compose in one
direction:

[`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md)
→
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
→
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
→
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)

### One trace for the whole review

Passing the same `trace =` to
[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md),
[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
accumulates the whole review in one place. It is a parent: each stage
still records on a trace of its own, which is what its `$trace` returns
and what `gr_options(max_calls =)` is measured against, and adds its
calls to the shared one when it finishes. So the screening cannot spend
the write-up’s ceiling, the shared trace’s totals are the sum of the
stages’, and each request is counted once.

[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
records its calls on `attr(outline, "trace")`, which
[`gr_outline_pick()`](https://elkronos.github.io/harnessr/reference/gr_outline_pick.md)
keeps and
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
keeps as `$outline_trace`; it does not add them to `claims$trace`. To
total a review’s cost, pass one trace to every stage, or add
`attr(outline, "trace")` to the claims’ own.

### The protocol

A protocol is what you fix before reading anything: which documents
count, what to collect from the ones that do, and what the write-up has
to cover. Fixing it first matters because a criterion invented while
reading is a criterion fitted to what was found.

``` r

protocol <- gr_protocol(
  "revenue-review",
  question = "How did revenue change across the regional reports?",
  include  = "Reports a revenue figure",
  exclude  = "Is a forecast rather than a result",
  fields   = gr_fields(
    region  = "The region the report covers",
    revenue = gr_field("Revenue in millions of dollars", type = "number"),
    year    = gr_field("Fiscal year reported", type = "integer")
  ),
  outline  = c("Findings" = "How revenue compares across regions")
)
protocol
#> <gr_protocol 'revenue-review'>
#>   question : How did revenue change across the regional reports?
#>   include  : Reports a revenue figure
#>   exclude  : Is a forecast rather than a result
#>   fields   : region, revenue, year
#>   outline  : Findings
#>   recipe   : research
```

[`gr_protocols()`](https://elkronos.github.io/harnessr/reference/gr_protocols.md)
lists four templates to start from: `bibliography`, `claims`,
`evidence_table` and `systematic_review`.
[`gr_protocol_save()`](https://elkronos.github.io/harnessr/reference/gr_protocol_save.md)
and
[`gr_protocol_read()`](https://elkronos.github.io/harnessr/reference/gr_protocol_save.md)
round-trip a protocol through a JSON file, so it can be shared, diffed
and cited alongside the results.

### Screening

Screening is one call per document, and nothing is dropped. Every
document gets a decision and a reason. There is no retrieval step that
could quietly remove a source before one is recorded. A file that could
not be read gets `status = "failed"` and no decision rather than a
silent exclusion, and `"unclear"` is an answer rather than a forced
guess, because forcing a binary call on an excerpt that does not settle
it is how automated screening loses studies.

This stand-in screener includes the northern report and cannot decide
about the southern one:

``` r

screener <- gr_mock_client(function(messages, params) {
  seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
                collapse = " ")
  if (grepl("51.8", seen, fixed = TRUE)) {
    return('{"decision":"unclear","reason":"The excerpt does not say whether this is a result.",
             "criterion":null,"quote":null}')
  }
  line <- regmatches(seen, regexpr("Revenue was [0-9.]+ million dollars in fiscal [0-9]+\\.", seen))
  sprintf('{"decision":"include","reason":"Reports a revenue figure.",
            "criterion":"Reports a revenue figure","quote":"%s"}', line)
})

screened <- gr_screen(reports, protocol, client = screener)
screened$table[, c("document", "decision", "criterion", "verified")]
#>    document decision                criterion verified
#> 1 north.txt  include Reports a revenue figure     TRUE
#> 2 south.txt  unclear                     <NA>       NA
```

The reply must fit the schema the request sent. A decision outside
`include`, `exclude` and `unclear` is a failed call, not a guess at what
the model meant, and it is not cached, so running again asks again.

`screened$forward` holds the included and unclear records, the set to
read at full text, and `screened$deferred` holds the unclear ones, for a
person to settle:

``` r

basename(screened$forward)
#> [1] "north.txt" "south.txt"
basename(screened$deferred)
#> [1] "south.txt"
```

[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md)
records that person’s decision. It needs to know who decided, and it
records when (in UTC) and, optionally, why, in the table and as a
`"screen.resolve"` step in the trace. `forward`, `deferred` and
`included` are rebuilt, and the screener’s own decision is kept in
`screener_decision`:

``` r

screened <- gr_resolve(screened, "south.txt", "include", by = "A. Reviewer",
                       reason = "The report covers fiscal 2025 actuals.")
screened$table[, c("document", "decision", "screener_decision", "resolved_by")]
#>    document decision screener_decision resolved_by
#> 1 north.txt  include           include        <NA>
#> 2 south.txt  include           unclear A. Reviewer
```

[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
compares against `screener_decision`, so a person’s correction is not
credited to the screener. Duplicates of a resolved record take the same
decision.

Hand `screened` itself to
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).
In this release that reads the included records only, and warns (class
`gr_unclear_dropped`) when it leaves unclear ones out; from the next
release it reads `$forward`. Pass `screened$forward` to read the unclear
records now. `screened$included` works too, but a character vector of
paths cannot carry the search forward, so the audit’s search section and
the bibliographic columns are lost with it.
`table(screened$table$criterion)` is the breakdown a flow diagram asks
for.

### Knowing how good the screening is

[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
gives every document a decision. Nothing in the run says whether those
decisions were any good, and a screener that discards a fifth of the
eligible studies produces a carefully audited review of the wrong
corpus.

The tempting substitute is running the model twice and reporting the
agreement. It measures the wrong thing: two passes share weights, priors
and blind spots, so they agree most confidently where they are both
wrong. Only a reference standard settles it.
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
draws a sample for a person to screen by hand, and
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
compares the two.

``` r

# A screening run: 340 discarded, 72 kept.
big <- structure(list(table = data.frame(
  document = sprintf("rec%03d.pdf", 1:412),
  decision = c(rep("exclude", 340), rep("include", 60), rep("unclear", 12)),
  stringsAsFactors = FALSE)), class = "gr_screening")

# Sample what it threw away: that is where a permanent loss hides.
check <- gr_reference(big, n = 60, of = "excluded", seed = 1)

# ... a person fills in `human_decision`, blind to what the model said.
check$human_decision <- c(rep("exclude", 57), rep("include", 3))

gr_calibrate(big, check)
#> <gr_calibration> 60 hand-screened row(s), 3 eligible
#>   sampled from: excluded (340 of 412 screened)
#>   eligible among the excluded      5.0%  [1.7%, 13.7%]  n=60
#>   correctly excluded              95.0%  [86.3%, 98.3%]  n=60
#>   screener    eligible  not eligible
#>   include            0             0
#>   unclear            0             0
#>   exclude            3            57
#>   -> across all 340 excluded record(s) that rate implies about 17
#>      eligible studies lost (6 to 47 on the interval above).
#>   eligible records excluded: about 17 of 340; 95% upper bound 39
#>   (sampled from exclusions only: this frame estimates what was lost, not
#>    sensitivity or specificity: it contains no kept records to compute them from)
#>   ! 3 eligible studies were excluded by the screener:
#>       rec329.pdf
#>       rec330.pdf
#>       rec340.pdf
#>   ! the interval on 'eligible among the excluded' is 12.0 points wide
#>     (n=60). A sample of one stratum needs it within 10 points, or the
#>     whole stratum judged. Hand-screen more before quoting a figure.
```

Which rows you sample changes which questions the sample can answer. A
sample of exclusions contains no kept records, so sensitivity would
compute to 0% and specificity to 100%. Both are artifacts of the frame,
alarming or flattering, and neither is a fact about the screener, so
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
reports what the frame supports and refuses the rest. The frame travels
as a column in the CSV, because that file gets emailed, opened in Excel
and read back a fortnight later, and an attribute survives none of that.
In a blind sheet the column is an opaque key, so the person filling it
in cannot tell from it what the model decided, and the CSV is UTF-8 with
a byte-order mark so Excel opens accented names intact.

A sample drawn from everything screened (`of = "all"`) supports the
rest. This one is the eight-record example from
[`?gr_calibrate`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md):

``` r

tab <- data.frame(document = paste0("d", 1:8, ".pdf"),
                  decision = c("include", "include", "unclear", "exclude",
                               "exclude", "exclude", "include", "exclude"),
                  stringsAsFactors = FALSE)
ref <- data.frame(document = paste0("d", 1:8, ".pdf"),
                  human_decision = c("include", "exclude", "include", "exclude",
                                     "exclude", "include", "include", "exclude"),
                  stringsAsFactors = FALSE)
cal <- gr_calibrate(structure(list(table = tab), class = "gr_screening"), ref,
                    of = "all")
cal
#> <gr_calibration> 8 hand-screened row(s), 4 eligible
#>   sampled from: all (NA of 8 screened)
#>   sensitivity (as deployed)       75.0%  [30.1%, 95.4%]  n=4
#>   sensitivity (strict include)    50.0%  [15.0%, 85.0%]  n=4
#>   specificity                     75.0%  [30.1%, 95.4%]  n=4
#>   deferred to a person            12.5%  [2.2%, 47.1%]  n=8
#>   reading avoided                 50.0%  [21.5%, 78.5%]  n=8
#>   screener    eligible  not eligible
#>   include            2             1
#>   unclear            1             0
#>   exclude            1             3
#>   agreement, kept (include + unclear) vs excluded:
#>     kappa     0.50  [--, --]
#>     PABAK     0.50  [-0.18, 0.86]
#>     AC1       0.50  [--, --]
#>     PI 0.00, BI 0.00
#>     (no kappa or AC1 interval: Only 8 record(s); the kappa and AC1 intervals need at least 10.)
#>   agreement, strict include vs the rest:
#>     kappa     0.25  [--, --]
#>     PABAK     0.25  [-0.39, 0.73]
#>     AC1       0.26  [--, --]
#>     PI -0.12, BI -0.12
#>     (no kappa or AC1 interval: Only 8 record(s); the kappa and AC1 intervals need at least 10.)
#>   recall 75.0%  [75.0%, 75.0%]; 95% one-sided lower bound 75.0%
#>   eligible records excluded: about 1 of 4; 95% upper bound 1
#>   recall target 95.0% at 95% confidence: not met
#>   ! 1 eligible study was excluded by the screener:
#>       d6.pdf
#>   ! only 4 eligible studies in the sample. Every rate above rests on
#>     those 4 observations, which is why the intervals are as wide as they are.
#>     Hand-screen more before quoting a figure.
```

`"unclear"` counts as a deferral to a person, not as a miss, because a
record the screener could not settle goes to a person, and counting it
as a failure would punish the one behaviour that makes it safe. Two
sensitivities are reported. Sensitivity as deployed is the share of
eligible studies that were kept, by `"include"` or by `"unclear"`, and
is the one where a shortfall is permanent. Strict sensitivity is the
share actively included. The gap between them is the reading you still
have to do. The rate of `"unclear"` decisions is the “deferred to a
person” line, with its interval, and `cal$decisions` holds the 3x2
counts behind it all.

Accuracy is not reported, and kappa is not reported alone. At a
realistic inclusion rate a screener that excluded everything scores
about 95% accurate and finds nothing. Agreement is taken on the same
decision sensitivity uses, kept (include or unclear) against excluded,
in `cal$agreement$kept`, with strict include against the rest beside it
in `cal$agreement$strict`. Each table gives Cohen’s kappa next to PABAK
and Gwet’s AC1, with intervals, the prevalence and bias indices, and the
class-wise sensitivity, specificity, PPV and NPV, because at a few
eligible records in a hundred kappa moves with prevalence as much as
with agreement:

``` r

cal$agreement$kept$stats
#>             statistic estimate      lower     upper
#> 1  observed agreement     0.75  0.4092754 0.9285208
#> 2               kappa     0.50         NA        NA
#> 3               PABAK     0.50 -0.1814491 0.8570416
#> 4                 AC1     0.50         NA        NA
#> 5    prevalence index     0.00         NA        NA
#> 6          bias index     0.00         NA        NA
#> 7         sensitivity     0.75  0.3006418 0.9544127
#> 8         specificity     0.75  0.3006418 0.9544127
#> 9                 PPV     0.75  0.3006418 0.9544127
#> 10                NPV     0.75  0.3006418 0.9544127
```

`cal$agreement$kept$paradox` is `TRUE` when the prevalence index is
above 0.8 in absolute value, where kappa says more about prevalence than
about agreement. The kappa interval is a percentile bootstrap over
documents, B = 2000, under a fixed seed, so the same sample gives the
same interval and the session’s random stream is untouched;
`cal$agreement$kept$bootstrap` holds B and the seed. AC1 uses Gwet’s
(2008) variance. Where the screener and the person agree on every
record, disagree on every record, or the sample holds fewer than 10
records, as here, the kappa and AC1 intervals are left empty with a
`note` saying why, instead of a zero-width interval such as \[1.00,
1.00\].

Before this release kappa was taken over the screener’s three labels
against the person’s two, so every `"unclear"` counted as a
disagreement. On this example that gave 0.33 where the
kept-against-excluded figure is 0.50. The old figure is
`cal$kappa_legacy` for this release only, and is removed in the next.

A rate from three observations is not a finding. The intervals on the
rates are Wilson score intervals, which stay sensible at zero and one
where the textbook interval collapses to a point, and `$adequate` says
when the sample cannot support a claim. What is enough depends on the
frame: enough eligible studies for sensitivity in a sample of everything
screened (`min_positives`, 10 by default), and for a sample of one
stratum (exclusions, or kept records) an interval no wider than 10
points, or the whole stratum judged. `$missed` is the list of studies
the screener discarded and a person did not, which is usually more use
than any rate.

Pass the result to `gr_audit_report(calibration = )` and it becomes a
section of the report, with the 3x2 counts and every statistic above, so
the figure a reviewer asks for sits next to the run it describes instead
of being copied into a methods section by hand.

### Recall against a target

Sensitivity as deployed is recall: the share of eligible studies the
screener kept. A review usually sets a target for it, such as 95%, and
the claim worth making is that recall is at least the target, at a
stated confidence. A sample of the exclusions alone cannot support that
claim, because it counts none of the eligible records that were kept.
The design that can is the one people use anyway: judge every record the
screener kept, and a sample of what it excluded. `of = "stacked"` draws
both in one sheet.

The target fixes how many exclusions to judge. Recall is K / (K + M),
with K the eligible records kept and M the eligible records excluded, so
a target is a cap on M. If a pilot suggests about 50 of the 72 kept
records are eligible, 95% recall allows floor(50 x 0.05 / 0.95) = 2 of
them to have been lost.
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
gives the number of the 340 exclusions to judge so that, if none of them
turns out eligible, the bound on M is 2:

``` r

gr_screen_sample_size(frame = "stacked", max_lost = 2,
                      frame_n = 340)[, c("frame", "max_lost", "frame_n", "n", "n_binomial")]
#>     frame max_lost frame_n   n n_binomial
#> 1 stacked        2     340 215        508
```

215 is the exact size from the hypergeometric distribution of a frame of
340 records; the binomial rule, which ignores that the frame is finite,
asks for 508. For a sample of everything screened (`frame = "all"`) the
rule is k \>= ln(alpha) / ln(T) eligible records with no miss: 59 for
95% recall at 95% confidence, which at 5% prevalence means drawing 1180
records. A frame of 500 records at that prevalence holds about 25
eligible records, too few for any sample of it to show the target, so
the size is the whole frame; judged whole, recall is known exactly:

``` r

gr_screen_sample_size(0.95, 0.95, prevalence = 0.05,
                      frame_n = 500)[, c("positives", "n", "n_binomial")]
#>   positives   n n_binomial
#> 1        59 500       1180
```

So draw every kept record and 215 of the exclusions:

``` r

stacked <- gr_reference(big, n = 215, of = "stacked", seed = 1)
nrow(stacked)
#> [1] 287

# ... a person judges every row, blind. Here 50 of the 72 kept records are
# eligible, and none of the 215 sampled exclusions.
kept <- big$table$decision[match(stacked$document, big$table$document)] != "exclude"
stacked$human_decision <- "exclude"
stacked$human_decision[which(kept)[1:50]] <- "include"

recall <- gr_calibrate(big, stacked)
unlist(recall$recall[c("estimate", "lower", "upper", "bound")])
#>  estimate     lower     upper     bound 
#> 1.0000000 0.9433962 1.0000000 0.9615385
unlist(recall$lost[c("estimate", "bound", "frame_n")])
#> estimate    bound  frame_n 
#>        0        2      340
recall$verdict$met
#> [1] TRUE
```

Each stratum is weighted by how much of it was judged: all 72 kept
records count once, and each of the 215 sampled exclusions stands for
340 / 215 of them. Recall is the ratio of the weighted
(Horvitz-Thompson) totals, from
[`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md).
M is bounded exactly from the hypergeometric distribution of what the
sample found, and the one-sided lower bound on recall is K / (K + M_U),
here 50 / 52 = 0.962, above the target. No bootstrap is used: with no
eligible record in the sample every resample also finds none, and the
interval would be \[1, 1\].

One eligible record among the sampled exclusions is enough to miss the
target. It stands for 340 / 215 records, and the bound has to allow for
more than that:

``` r

one_miss <- stacked
one_miss$human_decision[which(!kept)[1]] <- "include"
missed <- gr_calibrate(big, one_miss)
round(missed$recall$bound, 3)
#> [1] 0.909
missed$verdict$met
#> [1] FALSE
```

A blind stacked sheet keeps each row’s stratum and inclusion probability
inside its `sampled_from` key, one key per row, and lists the rows in
the run’s order rather than by stratum, so the person filling it in
cannot tell which records the screener kept. A kept sheet and an
excluded sheet drawn separately and joined with
[`rbind()`](https://rdrr.io/r/base/cbind.html) are read the same way
with `gr_calibrate(of = "stacked")`. On a stacked reference the result
also has `lost` (M with its bounds), `false_exclusion`, `work_saved`,
`unclear_rate`, `strata` and `verdict`; agreement statistics are left
out there, since unweighted they would be distorted the same way
unweighted sensitivity is.

### When prioritised screening can stop

[`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
reads every record once, so it has no stopping point to choose.
Screening that reads records in ranked order, most likely relevant
first, does: after enough irrelevant records in a row, the rest are
probably irrelevant too.
[`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
makes that a test. After each screened record it gives the p-value for
recall still being below `target`, given how many records are left, and
the first point where screening may stop at `alpha` (Callaghan and
Muller-Hansen 2020). Here 1,000 records are screened in ranked order:
the first 100 are relevant, the next 400 are not, and 500 are unread:

``` r

seen <- c(rep(1, 100), rep(0, 400), rep(NA, 500))
gr_stop_test(seen)
#> <gr_stop_test> recall target 0.95, alpha 0.05, 500 of 1000 records screened
#>   safe to stop after 453 records (100 relevant found), work saved 0.547
```

The test treats the last records screened as a random draw from those
left, which a ranking is not: when the ranker works it is cautious, and
when it ranks worse than chance it cannot be trusted. Nor is it
corrected for looking after every record. Report the rule and its
settings with the result.
[`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
simulates such an order with a cheap model and no calls, and
[`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
accepts its result;
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
shows it.

### Several reviewers

One person’s decisions are a reference, but not a perfect one, and how
far two people agree is the yardstick for how far a screener agrees with
either. `gr_reference(reviewers = k)` writes one decision column per
reviewer and a `consensus` column for an adjudicator:

``` r

pair <- gr_reference(big, n = 40, of = "all", seed = 2, reviewers = 2)
names(pair)
#> [1] "document"         "human_decision_1" "human_decision_2" "consensus"       
#> [5] "human_note"       "sampled_from"

# ... two people screen the 40 records; the second includes three records the
# first excluded.
eligible <- big$table$decision[match(pair$document, big$table$document)] != "exclude"
pair$human_decision_1 <- ifelse(eligible, "include", "exclude")
pair$human_decision_2 <- pair$human_decision_1
pair$human_decision_2[c(3, 11, 25)] <- "include"
```

[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
compares the screener with the reviewers’ consensus, and it will not
guess one: a disagreement nobody settled stops it, saying how many there
were.

``` r

tryCatch(gr_calibrate(big, pair), error = function(e) cat(conditionMessage(e)))
#> 3 of 40 document(s) were judged differently by the reviewers and have no `consensus` decision, starting with 'rec038.pdf'. Fill `consensus` where they disagree, or form one with gr_reference_consensus(rule = "majority") or rule = "any_include".
```

[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)
forms one decision per document by a rule. `"majority"` takes the
decision of more than half the reviewers, and settles a tie by the
`consensus` column where it is filled and otherwise as include, so a
reference never excludes a record half its reviewers included. With two
reviewers every disagreement is a tie. `"any_include"` carries a record
forward unless every reviewer excluded it, and `"adjudicated"` takes the
`consensus` column and stops where it is empty. `consensus_from` says
how each row’s decision was reached:

``` r

table(gr_reference_consensus(pair, "majority")$consensus_from)
#> 
#>  tie kept unanimous 
#>         3        37
```

Here an adjudicator settles the three instead, and the calibration runs:

``` r

pair$consensus[c(3, 11, 25)] <- "exclude"
both <- gr_calibrate(big, pair)
both$reviewers$agreement[, c("statistic", "estimate", "lower", "upper")]
#>            statistic   estimate     lower     upper
#> 1 observed agreement  0.9250000 0.8013577 0.9741640
#> 2              kappa  0.8181818 0.5833333 1.0000000
#> 3              PABAK  0.8500000 0.6027153 0.9483279
#> 4                AC1  0.8729487 0.7245902 1.0000000
#> 5   prevalence index -0.4250000        NA        NA
#> 6         bias index -0.0750000        NA        NA
#> 7 positive agreement  0.8695652        NA        NA
#> 8 negative agreement  0.9473684        NA        NA
both$reviewers$sensitivity[, c("reviewer", "statistic", "estimate", "lower", "upper", "n")]
#>   reviewer   statistic estimate     lower     upper  n
#> 1        1 sensitivity      1.0 0.7224672 1.0000000 10
#> 2        1 specificity      1.0 0.8864866 1.0000000 30
#> 3        2 sensitivity      1.0 0.7224672 1.0000000 10
#> 4        2 specificity      0.9 0.7437892 0.9654001 30
```

`$reviewers` gives every pair of reviewers the observed agreement,
kappa, PABAK, AC1 and the prevalence and bias indices from
[`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md),
never kappa alone, and Krippendorff’s alpha over all of them with three
reviewers or more. It also gives each reviewer’s sensitivity and
specificity against the consensus, which says what one person screening
alone would have missed. Each reviewer is part of the consensus they are
scored against, so these figures run higher than against an independent
reference, the more so with fewer reviewers. On a stacked reference both
are weighted the way recall is.

### Extraction

Extraction fills the protocol’s fields from every chunk of each included
document, then reconciles them. The result is one typed row per
document, and every filled cell carries the sentence it came from,
checked against the chunk it was attributed to. A paragraph about one
paper cannot be compared with a paragraph about two hundred others; a
table can be sorted, counted, filtered and published.

``` r

extractor <- gr_mock_client(function(messages, params) {
  seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
                collapse = " ")
  n <- if (grepl("45.2", seen, fixed = TRUE)) "45.2" else "51.8"
  yr <- if (grepl("2024", seen, fixed = TRUE)) 2024 else 2025
  rg <- if (grepl("45.2", seen, fixed = TRUE)) "north" else "south"
  line <- sprintf("Revenue was %s million dollars in fiscal %d.", n, yr)
  sprintf('{"region":"%s","revenue":%s,"year":%d,
            "region__quote":"%s","revenue__quote":"%s","year__quote":"%s"}',
          rg, n, yr, line, line, line)
})

table <- gr_extract(screened, protocol, client = extractor, recipe = "fast")
table$table[, c("document", "region", "revenue", "year", "n_unverified")]
#>    document region revenue year n_unverified
#> 1 north.txt  north    45.2 2024            0
#> 2 south.txt  south    51.8 2025            0
```

Reconciling the chunks costs nothing by default. Where the document
contradicts itself, `conflicts` names the field and the earliest chunk’s
value is kept; `resolve = "model"` spends one call per disagreeing field
to have the model choose instead.

`n_unverified` is the column to look at before believing a row: zero
means every value in it can be pointed at in the document.
`table$evidence` is the long form, one row per supported cell, with the
quote, the page it is on, and whether the quote appears there.

``` r

table$evidence[, c("document_id", "field", "quote", "verified")]
#>        document_id   field                                            quote
#> 1 f0651bef6287278d  region Revenue was 45.2 million dollars in fiscal 2024.
#> 2 f0651bef6287278d revenue Revenue was 45.2 million dollars in fiscal 2024.
#> 3 f0651bef6287278d    year Revenue was 45.2 million dollars in fiscal 2024.
#> 4 e472ebfef45d9a3c  region Revenue was 51.8 million dollars in fiscal 2025.
#> 5 e472ebfef45d9a3c revenue Revenue was 51.8 million dollars in fiscal 2025.
#> 6 e472ebfef45d9a3c    year Revenue was 51.8 million dollars in fiscal 2025.
#>   verified
#> 1     TRUE
#> 2     TRUE
#> 3     TRUE
#> 4     TRUE
#> 5     TRUE
#> 6     TRUE
```

Nothing is discarded for failing that check; `require_quote = TRUE`
makes discarding a choice rather than a surprise. A value is read by its
field’s type, so “1,204” in an integer field is 1204, and a value the
field does not allow is reported as one it could not read.

### Agreement on extracted fields

`n_unverified` says whether a value can be found in the document, not
whether it is the value a person would have taken. For that, have a
person fill the same fields for a sample of documents
(`gr_label_sheet("extraction", ...)` writes the sheet;
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
shows how sheets are read back) and compare the tables with
[`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md).
It matches rows on `document` and compares each field on its own, with
Krippendorff’s alpha at the field’s level of measurement: interval for
`integer` and `number` fields and nominal otherwise, unless `levels =`
names another. Here a model and a person extracted two fields from 40
studies:

``` r

fields <- gr_fields(
  design = gr_field("Study design", type = "enum", values = c("rct", "cohort", "case series")),
  n      = gr_field("Number randomised", type = "integer"))

studies_40 <- sprintf("s%02d.pdf", 1:40)
person <- data.frame(document = studies_40,
                     design = rep(c("rct", "cohort", "rct", "case series"), 10),
                     n = 30 + 7 * (1:40))
person$n[c(5, 30)] <- NA
model <- person
model$design[c(4, 17)] <- c("rct", "cohort")
model$n[c(9, 22, 31)] <- c(94, NA, 58)

ag <- gr_extract_agreement(model, person, fields = fields, B = 200)
ag
#> <gr_extract_agreement> 2 field(s), 40 document(s) matched
#> 
#>   field     part    level  n percent_agreement alpha  lower upper
#>  design    value  nominal 40             0.950 0.921  0.807     1
#>       n reported  nominal 40             0.975 0.789 -0.013     1
#>       n    value interval 37             0.946 0.929  0.774     1
#>  not_reported_x not_reported_y unknown
#>               0              0       0
#>               3              2       0
#>               3              2       0
#> 
#> Alpha intervals at 95%; bootstrap over documents, B = 200, seed 1.
subset(ag$pairs, x != y)
#>    document  field            x           y      x_state y_state
#> 4   s04.pdf design          rct case series        value   value
#> 17  s17.pdf design       cohort         rct        value   value
#> 49  s09.pdf      n           94          93        value   value
#> 62  s22.pdf      n not reported         184 not reported   value
#> 71  s31.pdf      n           58         247        value   value
```

A blank, `NA` or “not reported” cell means the document does not report
the field. In a nominal field that is one more category. A numeric field
cannot place it on its scale, so it gets two rows: whether the field is
reported at all, and the value where both tables report it. Alpha at the
interval level gives partial credit for a near miss, so 94 against 93
costs far less than 58 against 247, while percent agreement counts both
as disagreements. Below 30 documents, or for a field that never varies,
alpha is `NA` and a note says why; read percent agreement there. A
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
result can be passed directly. A row that failed is left out of every
field, and an empty cell in a row read only in part is left out rather
than taken as not reported, so a document is never counted as reporting
nothing because it was not read.

### The write-up

[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
makes one call per section of the outline, and every section cites the
rows it rests on:

``` r

writer <- gr_mock_client(function(messages, params) {
  paste("Revenue was higher in the southern region, at 51.8 million dollars [study 2],",
        "than in the northern, at 45.2 million [study 1].")
})

review <- gr_synthesise(table, protocol, client = writer)
review$citations
#>    section study  document      document_id
#> 1 Findings     2 south.txt e472ebfef45d9a3c
#> 2 Findings     1 north.txt f0651bef6287278d
cat(review$text_marked)
#> ## Findings
#> 
#> Revenue was higher in the southern region, at 51.8 million dollars [study 2], than in the northern, at 45.2 million [study 1].
```

`review$text_marked` is the text as the model wrote it, with its
markers; `review$text` is the same with the citations rendered, which
the next section covers. `review$citations` resolves each `[study n]` to
its `document` and `document_id`. The markers are parsed back out and
checked against the rows that exist; one pointing at a row that is not
there is reported and marks the section partial. Duplicates never reach
the write-up, so no study is counted twice.

The citation check says which rows a sentence rests on, not what it says
they found, and the figures are what a reader copies out of a review. So
every number in the write-up is also looked for in the rows its sentence
cites, as the writer was shown them:

``` r

review$sections[, c("section", "n_cited", "n_unbacked")]
#>    section n_cited n_unbacked
#> 1 Findings       2          0
review$figures[, c("number", "studies", "backed", "basis")]
#>   number studies backed     basis
#> 1   51.8    1, 2   TRUE cited row
#> 2   45.2    1, 2   TRUE cited row
```

The check forgives form, such as `.61` for 0.61 or `1204` for 1,204, but
not a changed digit. A figure found nowhere, such as 54.2 written for
45.2, has `backed = FALSE`, is counted in `n_unbacked` and is warned
about. It does not make the section partial, which is about citations. A
figure the cited row carries was copied correctly, and it can still be
the wrong figure for the sentence.

### Citations a reader can use

The model writes and the package checks `[study 2]` markers; extract the
bibliographic fields alongside your own and they render as citations,
with a reference list built from the studies the finished text cites.
`cite_style = "auto"`, the default, names the studies when the table can
name all of them; `"author-year"` asks for names and warns if they
cannot be produced, `"numeric"` gives `(1, 2)`, and `"marker"` leaves
`[study 1]` as written. A protocol for that adds the bibliographic
fields:

``` r

protocol <- gr_protocol(
  "spacing-review",
  question = "Does spaced practice improve retention in adult learners?",
  include  = "A primary study comparing spaced with massed practice",
  fields   = gr_fields(
    authors = "All authors, surname first",
    year    = gr_field("Year of publication", type = "integer"),
    title   = "Article title",
    venue   = "Journal, volume and issue",
    design  = "Study design",
    effect  = "Effect size with its interval"
  ),
  outline  = c("Included studies" = "How many, of what designs",
               "Findings"         = "The effect, and where studies disagree")
)
```

[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
takes the extraction table, so the shape it needs is easy to show
directly:

``` r

studies <- data.frame(
  document = c("smith.pdf", "lee.pdf", "garcia.pdf"),
  status = "ok", duplicate_of = NA_character_, n_filled = 4L,
  authors = c("Smith, J., Okafor, A.", "Lee, M., Petrov, K.", "Garcia, R."),
  year    = c(2019L, 2021L, 2022L),
  title   = c("Cognitive Load and Retention in Adult Learners",
              "Spacing Effects in Online Instruction",
              "No Effect of Spacing on Procedural Skill Acquisition"),
  venue   = c("Journal of Educational Psychology 44(2)",
              "Learning and Instruction 61(4)",
              "Applied Cognitive Psychology 36(1)"),
  effect  = c("d = 0.61", "d = 0.22", "d = 0.04"),
  stringsAsFactors = FALSE
)

cite_writer <- gr_mock_client(function(messages, params)
  "Three studies met the criteria [study 1] [study 2] [study 3].")

cited <- gr_synthesise(
  studies, question = "Does spaced practice improve retention?",
  outline = c("Included studies" = "How many, of what designs"),
  client  = cite_writer,
  style   = "formal academic; hedge claims; past tense for findings"
)
cat(cited$text)
#> ## Included studies
#> 
#> Three studies met the criteria (Garcia, 2022; Lee & Petrov, 2021; Smith & Okafor, 2019).
#> 
#> ## References
#> 
#> - Garcia, R. (2022). No Effect of Spacing on Procedural Skill Acquisition. Applied Cognitive Psychology 36(1).
#> - Lee, M., Petrov, K. (2021). Spacing Effects in Online Instruction. Learning and Instruction 61(4).
#> - Smith, J., Okafor, A. (2019). Cognitive Load and Retention in Adult Learners. Journal of Educational Psychology 44(2).
```

The model still writes `[study 3]`. Rendering happens afterwards, from
the table, so a citation in the finished prose is a fact about the
extraction rather than something the model asserted. Verifying “Smith &
Okafor (2019)” would mean matching a name the model wrote against a name
in the table, and the near-misses (Smith for Smyth, 2019 for 2018) are
the errors that matter and also the ones fuzzy matching forgives.
`cited$text_marked` keeps the marker form, so the check can be re-run on
what you published.

A study it cannot name makes the whole review fall back to markers.
Citing some studies by name and others by number reads as a mistake, and
inventing “n.d.” would assert something the extraction never found. Ask
for a `citation` field directly if your sources are awkward; parsing an
arbitrary author list is a heuristic and is treated as one.

### Revision passes

Sections are written independently, which keeps each one answerable to
its own brief, so nothing joins them: terms drift, a study gets
introduced twice, there are no transitions. `coherence = TRUE` adds
three revision passes over the finished draft: `"structure"` reorders
and merges, `"cut"` removes repetition, and `"register"` polishes
sentences. Each is forbidden from doing the others’ job, and each is a
call, so they are off by default. Name a subset if you want fewer:
`coherence = "cut"`.

A revision pass may reorganise prose. It may not make the review claim
more than the draft did. The passes are the one step that could quietly
undo everything above them, so their output is checked rather than
trusted, and a pass that fails a check is discarded, leaving
`review$draft`, the text from before the passes.

A revision that added or lost a citation is discarded. That check is
necessary and not sufficient, because the most damaging thing an editing
pass does leaves the citations exactly where they were: editing for
impact means deleting hedges, and the hedges are where the uncertainty
lives. “Three small trials suggest a modest benefit” comes back as
“trials show a benefit”, with the same markers and studies and a claim
the evidence does not carry. So a revision is also discarded if it
introduces a universal quantifier that was not there, uses a booster
(“demonstrates”, “establishes”, “confirms”) more often than the draft
did, or carries fewer hedges than the draft’s rate implies.

All three are matched on whole words. As bare substrings, “improved”
counted as an instance of “prove”, so a draft saying “outcomes improved”
licensed a revision saying “proves the drug works”, and a revision that
added the hedge “unproven” was rejected for introducing a booster.
Boosters are counted rather than merely listed, so saying “demonstrates”
three times where the draft said it once is introducing it.

The hedge test scales with how much claim-bearing prose survived, so a
shorter revision may carry fewer hedges, but never none if the draft had
any. It does not promise that every legitimate cut passes: a pass that
removes the most heavily hedged sentence lowers the rate and is refused.
The cost of that is a discarded pass and a warning; the draft stands.

Hedges and universal quantifiers are measured on sentences carrying a
citation, because headings, framing and transitions are exactly what an
editing pass should be free to rewrite, and “the evidence, all of which
is relevant” is not a claim. Boosters are measured on all of the prose
except headings, because there is no register in which an editing pass
should introduce “demonstrates” into a review at all, and the uncited
framing between the claims is where such a sentence gets written.

Two more checks need no model call. A `cut` pass that did not shorten
the review is discarded, since a cut that cut nothing was a polish under
the wrong name. And a revision pass that writes a figure its draft did
not have, or changes which studies are cited, is discarded; the figure
check runs on the draft and again on the revised text.
`review$coherence` has one row per pass: what ran, whether it was kept
and why not, with `words_before` and `words_after`, so a pass that
halved the review can be seen.

## Writing from claims instead of from rows

The write-up above was drafted from the whole table, one section at a
time, and the prose shows it: the model goes row by row. “Smith (2019)
found X. Garcia (2022) found Y.” That enumeration is a common sign of a
weak review, and it follows directly from what the prompt holds. The
structure has the same problem. The outline was fixed before anything
was read, so the shape of the review is your hypothesis, when often the
strongest thing a review has to say is structural: that a literature
splits into three incompatible measures, and that the argument about
effect size is an argument about measurement.

[`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
computes the relations between studies first. Each claim names the
studies that support it, the studies that contradict it, and the field
that distinguishes them. The stand-in below plays all three stages that
follow:

``` r

claim_writer <- gr_mock_client(function(messages, params) {
  sys <- messages[[1]]$content
  if (grepl("turn a table of studies", sys, fixed = TRUE)) {
    return(paste0('{"claims":[{"claim":"Revenue is higher in the south than the north.",',
                  '"kind":"finding","supported_by":[2],"contradicted_by":[1],',
                  '"moderator":"region","scope":"one report per region"},',
                  '{"claim":"The northern region reported for fiscal 2024.",',
                  '"kind":"finding","supported_by":[1],"contradicted_by":[],',
                  '"moderator":null,"scope":"one report"}]}'))
  }
  # Asked for a second outline (see below), it groups the claims another way.
  if (grepl("<earlier_outlines>", messages[[length(messages)]]$content, fixed = TRUE)) {
    return(paste0('{"sections":[{"heading":"The comparison","brief":"south against ',
                  'north","claims":[1],"rationale":"findings"},{"heading":"The reports",',
                  '"brief":"what each covers","claims":[2],"rationale":"coverage"}]}'))
  }
  if (grepl("sections of a review", sys, fixed = TRUE)) {
    return(paste0('{"sections":[{"heading":"Where revenue is higher","brief":"the ',
                  'regional comparison","claims":[1,2],"rationale":"one comparison"}]}'))
  }
  "Revenue was higher in the south [study 2] than in the north [study 1]."
})

cm <- gr_claims(table, question = protocol$question, client = claim_writer)
cm$claims[, c("claim", "moderator", "n_support", "n_contradict")]
#>                                            claim moderator n_support
#> 1 Revenue is higher in the south than the north.    region         1
#> 2  The northern region reported for fiscal 2024.      <NA>         1
#>   n_contradict
#> 1            1
#> 2            0
```

`cm$support` is the long form (`claim_id`, `study`, `role`); join it to
the extraction to reach documents and quotes. Every study number in it
was checked against the table, the same check the `[study n]` markers in
finished prose get, one link earlier. A number that is not in the table
is dropped and counted. A claim left with no supporting study is dropped
entirely, because a claim attached to nothing is an opinion. A
`moderator` naming a column the table does not have is cleared, because
an invented explanation for a real disagreement is the most convincing
error this layer can make. `cm$dropped` records all of it, so a thin
claims table can be told apart from a thin literature.

[`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
then derives the sections from the claims and hands them back as an
ordinary outline you can accept, edit or throw away;
`attr(outline, "claims")` is the assignment of claims to sections.
[`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
computes what the corpus does not contain (a declared category nobody
studied, a dimension with no variation, a claim nobody has replicated, a
disagreement nothing explains) in R, with no model call, so the gap list
is something you can check by counting:

``` r

outline <- gr_outline(cm, client = claim_writer)
names(outline)
#> [1] "Where revenue is higher" "What is missing"
gr_gaps(cm, extraction = table)[, c("kind", "dimension", "detail")]
#>           kind dimension                                        detail
#> 1 unreplicated   claim 2 The northern region reported for fiscal 2024.
```

That outline is one grouping of the claims, and the grouping is the
review’s argument. `alternatives = 2` asks for a second, shown the first
and asked to group the claims by a different principle. How far apart
two outlines are is counted, not asked: `distance` is how far each lies
from the first, the share of pairs of claims that one puts together and
the other apart. One that groups the claims as an earlier one did,
whatever its headings, is dropped. Nothing ranks them, and
[`gr_outline_pick()`](https://elkronos.github.io/harnessr/reference/gr_outline_pick.md)
hands back the one you choose:

``` r

two <- gr_outline(cm, client = claim_writer, alternatives = 2)
attr(two, "comparison")[, c("alternative", "sections", "claims_per_section", "distance")]
#>   alternative sections claims_per_section distance
#> 1           1        2               2, 0        0
#> 2           2        3            1, 1, 0        1
names(gr_outline_pick(two, 2))
#> [1] "The comparison"  "The reports"     "What is missing"
```

Each ends with the closing section for the gaps, which holds no claims
here. The first outline is the same whatever `alternatives` says, and a
review written from a picked one records which it was.

``` r

from_claims <- gr_synthesise(table, outline = outline, question = protocol$question,
                             client = claim_writer, claims = cm,
                             gaps = gr_gaps(cm, extraction = table))
from_claims$sections[, c("section", "n_claims", "claims_missed", "n_unsupplied", "partial")]
#>                   section n_claims claims_missed n_unsupplied partial
#> 1 Where revenue is higher        2             0            0   FALSE
#> 2         What is missing        0             0            2    TRUE
```

The stand-in wrote the same sentence for the gaps section too, citing
two studies that section was not shown, so `n_unsupplied` counts them
and the section is marked partial.

Each section now argues its own claims and is shown only the studies
those claims rest on, ordered so a twelve-person pilot stops getting the
same space as a two-thousand-person trial. `claims_missed` is the
citation check run backwards: a section handed a claim and not writing
it up did not do what the outline promised, is marked partial, and says
which claim it left out. `cite_style = "author-year"` and
`coherence = TRUE` work here as they do above.

The schema this wants as input is the `claims` protocol
(`gr_protocols("claims")`). `design` and `finding` are coded as enums so
studies can be compared mechanically, each paired with the paper’s own
wording so the coding can be checked rather than trusted. `finding` is
coded relative to your question, which is what lets a non-interventional
literature have contradictions at all, and why that template is refused
until you replace the placeholder question in it.

Two things it does not do. It does not rank study designs when deciding
emphasis: that would assert a cohort study beats a qualitative one, and
the Cochrane Handbook discourages totalling per-item scores into one
number. Design is a grouping variable here, describing what
distinguishes the sides of a disagreement, not a score. And nothing asks
a model to judge which of its own inputs are stale or wrong. If two
studies conflict, both are reported and the conflict is named, because
“the model decided this one was wrong” is not something anyone can
check.

## Counting and reporting the run

[`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
returns the numbers a flow diagram is made of, from what the run already
recorded. Every source is accounted for at every stage it reached, so
the arithmetic closes:

``` r

gr_flow(screened, table)[, c("stage", "n")]
#>                      stage n
#> 1            sources given 2
#> 2       duplicates removed 0
#> 3                 screened 2
#> 4                  include 2
#> 5                  exclude 0
#> 6                  unclear 0
#> 7        could not be read 0
#> 8    screening call failed 0
#> 9     resolved by a person 1
#> 10      kept for full text 2
#> 11   deferred to full text 0
#> 12          extracted from 2
#> 13        reported nothing 0
#> 14            read in part 0
#> 15          failed to read 0
#> 16      values unsupported 0
```

The records screened split into include, exclude, unclear, could not be
read (no screening call was made) and screening call failed (a call was
made and its reply failed or was not the form asked for), and those five
rows sum to “screened”. “resolved by a person” counts the decisions a
person made with
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
“kept for full text” is `$forward`, and “deferred to full text” is the
unclear part of it, `$deferred`. Pass `records =` to start the counts at
identification, and `claims =` to add the claim-level counts.

[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
writes the whole chain out as one self-contained HTML file for the
reviewer or co-author whose question is “how do you know?”. It holds the
protocol as fixed in advance, what happened to every document (the
screener’s decision, and who resolved each record, when and why), every
value with its quote and page and whether the quote is there, what was
written and which rows each claim rests on, every claim with the studies
for and against it and where each one ended up, and what it cost. It
takes the objects the run already produced:

``` r

gr_audit_report("audit.html", screening = screened, extraction = table,
                synthesis = from_claims, claims = cm, protocol = protocol,
                calibration = cal)
```

`records =` takes the search when the run had one, and every argument is
optional except the path and at least one stage to report on.

The report puts the failures near the top: unverified quotes, documents
that could not be read, screening calls that failed or came back in the
wrong form, and citations pointing at rows that do not exist are counted
there. It also states what the checking does not establish: that a
quoted sentence occurs in the document is not evidence that it supports
the value taken from it.

## Next

- [`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md):
  spending limits, caching a run so it is paid for once, and replaying
  it offline.
- [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md):
  how each document is read, which `recipe =` chooses for
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  and
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md).
- [`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md):
  label sheets, comparing recipes and models on a labelled set with
  intervals, judges, and baselines that use no model.
- [`?gr_calibrate`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
  [`?gr_screen_sample_size`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
  [`?gr_screen`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  and
  [`?gr_synthesise`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md):
  every argument, with the reasoning behind the defaults.
