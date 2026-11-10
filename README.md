# harnessr

[![R-CMD-check](https://github.com/elkronos/harnessr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/elkronos/harnessr/actions/workflows/R-CMD-check.yaml)
[![tests](https://github.com/elkronos/harnessr/actions/workflows/tests.yaml/badge.svg)](https://github.com/elkronos/harnessr/actions/workflows/tests.yaml)

For one document, `answer_document()` picks an ingest, a segmentation and a
reading strategy, and returns an answer with a trace of everything it did. For
a folder, `gr_screen()` decides which documents count, `gr_extract()` fills a
typed schema across all of them, and `gr_synthesise()` writes the result up
with every claim citing the row it rests on. Every model call is budgeted,
recorded and checked, and can be cached.

harnessr was called readgpt up to version 0.6.0, and so was its GitHub
repository. Requests, cache keys and recordings are unchanged by the rename;
the `readgpt.*` options are still read, with a warning (see `NEWS.md`).

The [guides](#guides) explain each part in depth and all run offline, without a
key. Start with `vignette("harnessr")`. They are also on the website,
<https://elkronos.github.io/harnessr/>, with the reference for every function.

## Install

Requires R 4.1 or later. The only non-base hard dependencies are `digest`,
`httr` and `jsonlite`.

```r
install.packages(c("remotes", "knitr", "rmarkdown"))
remotes::install_github("elkronos/harnessr", build_vignettes = TRUE)
```

`build_vignettes = TRUE` installs the guides, so `vignette("harnessr")` works.
Building them needs `knitr`, `rmarkdown` and Pandoc. Pandoc comes with RStudio;
without RStudio, install it from <https://pandoc.org/installing.html> first, or
leave out `build_vignettes = TRUE`. From a local checkout,
`remotes::install_local("path/to/harnessr")` does the same.

Other packages (pdftools, tesseract and magick, xml2, future, ellmer, shiny)
are checked when a feature needs them; a missing one is an error naming it,
unless harnessr can carry on without it. `vignette("harnessr")` lists them.

## Quick start

```r
library(harnessr)

ans <- answer_document("report.pdf", "What was Q3 revenue?", recipe = "needle")
ans$answer
ans$partial
```

Every console block below is real output from the bundled example document,
with `gr_mock_client()` standing in for the API, so you can reproduce all of it
without a key. `gr_compare()` runs several recipes over one document and
extracts it only once, so you can choose a pipeline before committing to it:

```r
cl  <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
cmp <- gr_compare(gr_example(), "What was revenue in fiscal 2024?",
                  c("fast", "needle", "thorough", "survey"), client = cl)
cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "signature", "settings")]
#>     recipe  segmenter chunks       reader         signature
#> 1     fast  paragraph      1        stuff        all|1|none
#> 2   needle   semantic      2     retrieve       topk|1|none
#> 3 thorough  paragraph      1   map_reduce   all|N+logN|tree
#> 4   survey structural      6 hierarchical all|N+tree+1|tree
#>                                                settings
#> 1                                       max_tokens=4000
#> 2 top_k=8, cite=TRUE, max_tokens=500, overlap_tokens=50
#> 3                                    overlap_tokens=120
#> 4                                       max_tokens=1500
```

`settings` names whatever each recipe changed from the defaults. The bundled
example is small (573 tokens as `gr_ingest()` counts them), so `fast` and
`thorough` fit it in one chunk. On a real report they would not.

Or build a pipeline by hand, one choice per axis:

```r
rec <- gr_recipe("my_pipeline",
  ingest  = list(clean = c("page_numbers", "hyphenation", "headers_footers")),
  segment = list(method = "structural", max_tokens = 800, overlap_tokens = 80),
  read    = list(reader = "skim", cite = TRUE, model = "gpt-5.6-terra"))

ans <- answer_document("thesis.pdf", "How was the sample recruited?", rec)
```

## Connecting a model

```r
Sys.setenv(OPENAI_API_KEY = "sk-...")   # or
options(harnessr.api_key = "sk-...")     # or
cl <- gr_client(api_key = "sk-...")     # per client, for multi-user Shiny
```

An explicit argument wins over the `harnessr.api_key` option, which wins over
`OPENAI_API_KEY`. Keep the key out of the repository: `.Renviron` is the usual
home for it, and both `.Renviron` and `.Rprofile` are gitignored here. Without
a key, `answer_document()`, `gr_read_many()` and `gr_compare()` stop before
reading the document, with a `gr_auth_error` that says how to set one, so a
missing key does not first cost an OCR pass over a long scan.

Behind a company gateway, `gr_client(headers = )` sends the headers it wants,
such as Azure's `api-key`; `vignette("harnessr")` shows how.

The built-in client speaks to OpenAI-compatible `/responses` and
`/chat/completions` endpoints. `gr_ellmer_client()` hands the transport to
[ellmer](https://ellmer.tidyverse.org/), which covers roughly twenty providers,
local models through Ollama among them. The spending limit is on by default and
can hold only for a model with a registered price, so register the model the
ellmer object was built with, at your provider's current prices in US dollars
per million tokens:

```r
library(ellmer)

gr_register_model("claude-sonnet-4-5", context_window = 200000, max_output = 64000,
                  input_usd = 3, output_usd = 15)
cl <- gr_ellmer_client(chat_anthropic(model = "claude-sonnet-4-5"))
answer_document("report.pdf", "What was revenue?", "thorough", client = cl)

# A local model has no price to register, so let it run unpriced:
gr_options(allow_unpriced = TRUE)
gr_ellmer_client(chat_ollama(model = "llama3.1"))
```

Without a registered price, a run under `max_cost_usd` stops before its first
request with an `hr_unpriced_model` error. `vignette("runs")` covers unpriced
models and what changes through ellmer (temperature and embeddings).

Anything else, such as a model behind a queue, goes through
`gr_backend_client()`, which makes any function of `messages` and `params` that
returns a string the transport. Limits, the trace, caching and replay work the
same way on every client. Register the model's real context window with
`gr_register_model()`, since it is what sizes your chunks.

## How it works

How you break a document up and how you make the model read it are separate
decisions worth experimenting with, so the package keeps them separate. There
are three independent axes, each a registry you can extend without editing the
package:

```
  source  ──▶  INGEST  ──▶  SEGMENT  ──▶  READ  ──▶  answer + trace
               │             │             │
               │             │             └─ 12 strategies, each with a
               │             │                distinct traversal signature
               │             └─ 9 segmenters + overlap / min-size / context
               └─ 6 extractors + 14 individually toggleable cleaners
```

Any ingest composes with any segmenter and any reader. `gr_recipe()` binds one
of each into a named pipeline, and a recipe run alongside others gives a
byte-identical `$answer` and `$chunks_used` to running it alone. Which model
answers is a fourth, independent choice.

`gr_ingest()` turns a file into cleaned text blocks that keep their page and
section. The extractors cover plain text and delimited files, Markdown, HTML,
Word, PDF (with OCR for scanned pages) and images, and a web address is
downloaded and read as whatever it serves. Each cleaner can be turned on or off
by name, and `remove_numbers` is off by default, because it would make every
figure, date and percentage unanswerable. See `vignette("ingest")`.

`gr_segment()` cuts the document into chunks: on a ruler, by paragraph,
sentence, heading or page, where embeddings diverge, or by rewriting it into
standalone statements. `max_tokens` is enforced on every segmenter, and
`gr_chunk_stats()` compares chunkings for nothing before you spend anything on
reading. See `vignette("segment")`.

`gr_read()` answers the question with one of the strategies, from `stuff` (one
request carrying the whole document) through `map_reduce` (one per chunk, then a
merge) to `iterative` (multi-hop). Each has a traversal signature,
`select|calls|state`, which is how the package tells two methods apart from two
names for the same thing. Recipes such as `fast`, `needle`, `thorough` and
`survey` bundle a segmenter with a reader. `answer_document()` defaults to
`"auto"`, which reads a document of up to 50,000 tokens (less on a model with a
small context window) with `fast` and a longer one with `thorough`. See
`vignette("readers")`, which also covers what to check when the answer is not
what you expected.

To choose a recipe or a model on more than one document, `hr_benchmark()` runs
each configuration several times over a labelled set of questions under one
spending limit, and `hr_report()` gives accuracy, paired differences and cost
with intervals that treat the questions about one document as a cluster. See
`vignette("evaluate")`.

## What an answer gives back

`print(ans)` sums up the cost, where the evidence came from and, when the answer
is partial, why:

```r
ans$answer
ans$partial                 # TRUE means something degraded; check this first
ans$notes                   # why: dropped_chunks, failed_calls, unread_pages, ...
ans$evidence                # the passages the answer rests on, with page and section
gr_verify_evidence(ans)     # whether each quoted passage is in its chunk
as.data.frame(ans$trace)    # one row per request: stage, tokens, usd, seconds, prompt, reply
```

A quotation that is not in the chunk it is attributed to marks the answer
partial, and a citation of a chunk that was never sent is recorded in
`ans$notes$cited_unknown`. Both checks are local string operations, so they
cost nothing and always run.

`gr_trace_cost()` prices a run by each step's own model and counts only the
calls that were issued; `vignette("runs")` shows a bill.

`gr_audit_report()` puts the question, the answer, whether it is partial and
why, the cost, and the passages in document order on one HTML page:

```r
gr_audit_report("answer.html", answer = ans)
```

## Many documents and reviews

`gr_read_many()` runs one recipe over a folder and returns one row per
document. An unreadable file costs one row rather than the run, each document
gets its own budget, `max_total_calls` and `max_total_usd` bound the run, and
`store =` makes a long run resumable.

A review fixes its protocol before reading anything, then runs `gr_protocol()` →
`gr_screen()` → `gr_extract()` → `gr_synthesise()`. Screening gives every
document a decision and a reason, and sends `"unclear"` ones to a person instead
of guessing. Extraction gives a typed table, and its `n_unverified` column
counts the values in a row that cannot be pointed at in the document. Where a
document contradicts itself, `conflicts` names the field and the earliest
chunk's value is kept; `resolve = "model"` spends one call per disagreeing field
to have the model choose instead. The write-up cites `[study n]` for each row it
rests on, and every marker is checked against the rows that exist. The audit
report writes the whole chain out for the co-author or reviewer who asks "how do
you know?":

```r
gr_audit_report("audit.html", extraction = x, synthesis = review, claims = cm,
                protocol = protocol)
```

`vignette("review")` covers the rest: surveying a folder with
`gr_inventory()`, starting from a reference manager's export with
`gr_records()`, measuring the screener against a hand-screened sample with
`gr_calibrate()`, author-year citations, claims, outlines and gaps, and the
checks on revision passes.

## Limits and records

Two limits are on by default, `max_cost_usd = 5` and `max_calls = 400` per run,
set with `gr_options()` or held together by `hr_governor()`. Every request is
checked before it is sent, against what the run has spent plus the most that
request could cost, and a request that could pass a limit is not sent. The
answer comes back partial, and the trace names the limit in `stop_reason`.

`gr_cache()` stores each successful response, keyed on everything that can
change the reply, and `gr_cache_client()` attaches it to a client, so a repeat
is free and identical. A trace records every prompt and response, so
`gr_trace_save()` and `gr_replay_client()` reproduce a run from the saved trace
and the source document, with no key and no spend.

`vignette("runs")` covers the other limits (tokens, output caps, allowed
models), reasoning effort per stage, what each trace step records, cache keys,
replaying a run that used embeddings, and the classed errors and warnings.

## Shiny app

```r
shiny::runApp(system.file("shiny", package = "harnessr"))
```

Every axis is a control, and a free "Preview chunking" button shows the chunks
before you spend anything. Set `GPTREAD_DOC_ROOTS` before exposing the app to
anyone else: unset, it reads `~/Documents`, or your whole home directory when
there is none. `vignette("segment")` has the details.

## Guides

Each guide is on the website and, once installed, in R as `vignette("name")`.

| guide | what it covers |
|---|---|
| [Get started](https://elkronos.github.io/harnessr/articles/harnessr.html) (`harnessr`) | The ideas, installing, connecting, a first question checked from start to finish, cost, a glossary |
| [Getting text out of files](https://elkronos.github.io/harnessr/articles/ingest.html) (`ingest`) | PDFs, Word files, web pages and scans, every cleaner, and surveying a folder |
| [Cutting documents into chunks](https://elkronos.github.io/harnessr/articles/segment.html) (`segment`) | The segmenters, overlap, minimum size, context, and comparing chunkings |
| [Choosing how the model reads](https://elkronos.github.io/harnessr/articles/readers.html) (`readers`) | The reading strategies, recipes, what each costs, and how to choose |
| [Many documents and literature reviews](https://elkronos.github.io/harnessr/articles/review.html) (`review`) | Search, screening, calibration and recall, several reviewers, extraction, claims, synthesis, the audit report |
| [Measuring and comparing configurations](https://elkronos.github.io/harnessr/articles/evaluate.html) (`evaluate`) | Reference sets and label sheets, benchmarks and their intervals, non-inferiority, judges, baselines, drift, signals |
| [Cost, limits and reproducible runs](https://elkronos.github.io/harnessr/articles/runs.html) (`runs`) | The governor, effort, traces, caching, replay |
| [Extending harnessr](https://elkronos.github.io/harnessr/articles/extending.html) (`extending`) | Registering your own extractors, cleaners, segmenters, readers and embedders, and checking them |

## Development

```bash
bash run-tests.sh   # install deps if needed, install, run the suite; --help lists the options
```

The suite needs `testthat` and `withr`, plus `future` and `future.apply`,
without which the tests of a parallel run's call and cost counts are skipped.
Every test uses an offline mock client, so no key is needed and no requests are
made; `--check` runs a full `R CMD check`.

| workflow | what it does |
|---|---|
| `tests.yaml` | installs, runs the suite, runs the README's code blocks and diffs their documented output against real output, knits every guide with no key and no network, and checks the documented counts against the registries and that no two readers share a traversal signature |
| `R-CMD-check.yaml` | full `R CMD check` on macOS and Ubuntu, current R and the previous release |
| `pkgdown.yaml` | builds the website on pull requests and on pushes to the main branch, and publishes it except from a pull request |
| `pr-checks.yaml` | fails a pull request that drops an `expect_*()` call or adds a `skip()` without the label `tests-reviewed`, or adds a dependency without the label `deps-reviewed` (an added package must be on CRAN either way), and lints the changed files under `R/` |
| `validation.yaml` | runs nightly and by hand, never on pull requests: simulates clustered benchmarks to check the coverage of `hr_report()`'s intervals (`dev/sim-coverage.R`) and `hr_mdd()` against a power simulation (`dev/sim-power.R`), 2000 replicates each, and keeps the tables as an artifact |

`Rscript dev/ci/pr-checks.R tests origin/main HEAD` runs the pull-request checks
locally. No workflow needs a secret: `OPENAI_API_KEY` is empty, or a dummy value
for the README blocks, so a real key can never change a result.

## Migrating from v1

The old entry points still work and map onto the new pipeline, warning once:

| v1 | now |
|---|---|
| `answer_question(f, q, mode = "Chunked")` | `answer_document(f, q, "thorough")` |
| `parse_text(f, chunk_method = "semantic")` | `gr_ingest(f)` → `gr_segment(doc, "semantic")` |
| `gpt_read_chunked()` | `gr_read(ch, q, cl, "map_reduce")` |
| `gpt_read_retrieval()` | `gr_read(ch, q, cl, "skim")` |
| `gpt_read_hierarchical()` | `gr_read(ch, q, cl, "hierarchical")` |
| `gpt_read_multipass()` | `gr_read(ch, q, cl, "ensemble")` |

Three behaviour changes are deliberate and will alter your results:

1. **`mode` no longer defaults to all five modes.** `answer_question(f, q)` in v1
   ran every mode: 41 API calls on an 8-paragraph document, where one was
   expected.
2. **Modes no longer contaminate each other.** In v1, `mode = c("Chunked",
   "Semantic")` changed Chunked's chunking, its cost, and its answer relative to
   `mode = "Chunked"` alone.
3. **Digits are no longer stripped by default.** v1's `remove_numbers = TRUE`
   default was unreachable from `answer_question()`, so every figure, date and
   percentage was deleted before the model saw the document.

v1's `refine = TRUE` is mapped to citations only. Its verification pass is not
reproduced because it could never run: it called a `search_text()` function
that was never defined anywhere in the repository.

The v1 source is kept under `legacy/` for reference and A/B comparison. It is
not loaded by the package. To reproduce its ingestion and chunking under the
current code, use the `legacy` recipe, which reproduces its digit stripping,
3000-token paragraph chunks and lack of overlap. The regression suite in
`tests/testthat/` reproduces each of these defects against the current code.
