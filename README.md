# harnessr

[![R-CMD-check](https://github.com/elkronos/harnessr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/elkronos/harnessr/actions/workflows/R-CMD-check.yaml)
[![tests](https://github.com/elkronos/harnessr/actions/workflows/tests.yaml/badge.svg)](https://github.com/elkronos/harnessr/actions/workflows/tests.yaml)

harnessr is a harness for calls to large language models. It composes calls
into steps and chains, checks spending limits before each request, can cache
replies so a repeated request is paid for once, records every call in a trace
you can save and replay offline, and checks what came back. Any client goes
through it: an OpenAI-compatible endpoint, any provider ellmer supports, a
function of your own, or an offline stand-in.

A document layer is built on that core. For one document, `answer_document()`
picks an ingest, a segmentation and a reading strategy, and returns an answer
with the trace of everything it did. For a folder, `gr_screen()` decides which
documents count, `gr_extract()` fills a typed schema across all of them, and
`gr_synthesise()` writes the result up, citing the rows each section rests on
and flagging any sentence that cites none.

![Two stacked layers. The core (hr_ functions for calls and clients, the trace, models and prices, context, effort, limits, cache and replay, composing, evaluating, and the registry and modules) sends every request to a model provider over HTTP or through ellmer, your own function, a mock or a recording. The document layer (gr_ functions for ingest, segment, read, screen, extract, claims, synthesis and review) sits above it and calls the core. Your code calls either layer, and the core never calls the document layer.](man/figures/layers.svg)

Your code can call either layer: the document functions (`gr_`) build on the
core functions (`hr_`), and the core never calls the document layer.

harnessr was called readgpt up to version 0.6.0. If you have code written for
readgpt, `vignette("migrate")` lists the old names and what replaced them.

## Install

Requires R 4.1 or later. The only non-base hard dependencies are `digest`,
`httr` and `jsonlite`. Install the 0.7.0 release, or the development version,
which has the changes in NEWS.md since 0.7.0:

```r
install.packages(c("remotes", "knitr", "rmarkdown"))
# The 0.7.0 release
remotes::install_github("elkronos/harnessr@v0.7.0", build_vignettes = TRUE)
# The development version, which the website documents
remotes::install_github("elkronos/harnessr", build_vignettes = TRUE)
```

`build_vignettes = TRUE` installs the guides, so `vignette("harnessr")` works.
Building them needs `knitr`, `rmarkdown` and Pandoc. Pandoc comes with RStudio;
without RStudio, install it from <https://pandoc.org/installing.html> first, or
leave out `build_vignettes = TRUE`. From a local checkout,
`remotes::install_local("path/to/harnessr")` does the same.

Some features need an optional package: `pdftools` to read PDFs, `ellmer` for
providers other than OpenAI, and a few more. harnessr checks for one when a
feature needs it, and a missing one is an error naming it, unless harnessr can
carry on without it. `vignette("harnessr")` lists each package with the feature
that needs it.

## A first call

One call through the core, with `hr_mock_client()` standing in for a model so
it runs without a key. The trace records the request, its tokens and its cost:

```r
library(harnessr)

cl  <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
tr  <- hr_trace()
res <- hr_call(cl, "What was revenue in fiscal 2024?", trace = tr, label = "ask")
as.data.frame(tr)[, c("stage", "model", "tokens_in", "tokens_out", "usd")]
#>   stage      model tokens_in tokens_out usd
#> 1   ask mock-model        14         13   0
```

`res$text` holds the reply and `res$ok` says whether the call succeeded.
`hr_call()` checked the request against the run's limits before sending it:
by default 400 calls and $5, set with `hr_options()` or `hr_governor()`. `hr_trace_save()` writes the
trace to a file, and `hr_replay_client()` answers the same requests from that
file with no key and no network. `vignette("core")` covers every kind of
client, what a result holds, the trace, structured replies and checks on a
reply.

## The document layer

`answer_document()` runs a whole pipeline over a file in one call: ingest,
segment, read. Here it answers from the bundled example report, with the same
stand-in client:

```r
ans <- answer_document(gr_example(), "What was revenue in fiscal 2024?",
                       recipe = "needle", client = cl)
ans$answer
#> [1] "Revenue was 45.2 million dollars."
```

`ans$trace` records every step of the run, and `ans$evidence` the chunks the
answer rests on. A recipe such as `"needle"` names one choice for each stage.
`vignette("readers")` explains how to choose one, and `gr_compare()` runs
several recipes over one document so you can compare them. For a folder of
documents, `vignette("review")` covers screening, extraction and synthesis.

## Connecting a model

Put your OpenAI key in `.Renviron` as `OPENAI_API_KEY=sk-...`, or set it for
the session:

```r
Sys.setenv(OPENAI_API_KEY = "sk-...")
```

harnessr knows each built-in model's limits but ships no prices, because
providers change them more often than the package is released. Set the price
you pay for the model you use, so the default $5 spending limit counts its
requests. Without a price, a request is still sent, with a warning that the
limit does not cover it.

```r
# Illustrative figures, in USD per million tokens: use your provider's current
# prices.
hr_register_model("gpt-5.6-terra", input_usd = 2, output_usd = 12)
```

Then `answer_document()` runs against the real model when you leave out
`client`, and `hr_call()` does too when you give it `hr_client()` in place of
the stand-in.
`vignette("harnessr")` covers the other ways to give a key, company gateways,
other providers and local models through ellmer, and any other backend.
`vignette("models")` shows how to set many prices from a file and keep them
current.

## Guides

Each guide runs offline, without a key. All are on the website,
<https://elkronos.github.io/harnessr/>, under the same groups as here, with the
reference for every function. Once installed, each is also in R as
`vignette("name")`. The core guides come first because the document guides
build on them.

### Get started

- [Get started](https://elkronos.github.io/harnessr/articles/harnessr.html) (`harnessr`): the ideas, installing, connecting, the core in brief (a call, its trace, prices and limits, context, effort), then a first question about a document checked from start to finish, cost, a glossary.

### Core

- [The core: calls, clients and results](https://elkronos.github.io/harnessr/articles/core.html) (`core`): calls without a document, every kind of client, what a result holds, the trace, structured replies, checks, signals, errors by class.
- [Models, prices and tokens](https://elkronos.github.io/harnessr/articles/models.html) (`models`): what harnessr knows about a model, adding one, setting the prices you pay, cost estimates, models with no price or old prices, and counting tokens.
- [Context: budgets, fitting and cutting](https://elkronos.github.io/harnessr/articles/context.html) (`context`): how much room a prompt has, fitting its pieces into that room, which part of a cut piece is kept, and the cuts the trace records.
- [Effort: how hard the model reasons](https://elkronos.github.io/harnessr/articles/effort.html) (`effort`): which models take a reasoning effort, setting it per call or per stage, what it costs and does to the cache, raising it only when a stage goes wrong, and measuring whether that pays.
- [Limits, caching and replay](https://elkronos.github.io/harnessr/articles/runs.html) (`runs`): what a document run records, spending limits and the governor, parallel batches, paying once with a cache, repeated draws, replaying a run, and what recipes cost.
- [Composing steps into chains](https://elkronos.github.io/harnessr/articles/compose.html) (`compose`): steps of your own and the built-in ones, chains run as one arm, registering a step and checking a module, deriving a chain by dropping or replacing a step, settings and sweeps by path, skills, and a coding sub-agent.
- [Measuring and comparing configurations](https://elkronos.github.io/harnessr/articles/evaluate.html) (`evaluate`): reference sets and label sheets, benchmarks and their intervals, non-inferiority, judges, checks that run a program, baselines, drift, signals.
- [Comparing methods and settings](https://elkronos.github.io/harnessr/articles/compare.html) (`compare`): worked comparisons of readers, segmenters and chunk sizes, one setting over its values, screening settings and a judge against labels, and how to read each report.
- [Settings reference](https://elkronos.github.io/harnessr/articles/settings.html) (`settings`): every setting of every stage with its default and where it came from, and the extractors, cleaners, segmenters, readers, embedders and recipes.

### Documents

- [Getting text out of files](https://elkronos.github.io/harnessr/articles/ingest.html) (`ingest`): PDFs, Word files, web pages and scans, every cleaner, and surveying a folder.
- [Cutting documents into chunks](https://elkronos.github.io/harnessr/articles/segment.html) (`segment`): the segmenters, overlap, minimum size, context, and comparing chunkings.
- [Choosing how the model reads](https://elkronos.github.io/harnessr/articles/readers.html) (`readers`): the reading strategies, recipes, what each costs, and how to choose.
- [Many documents and literature reviews](https://elkronos.github.io/harnessr/articles/review.html) (`review`): search, screening, calibration and recall, several reviewers, extraction, claims, synthesis, the audit report.
- [Extending harnessr](https://elkronos.github.io/harnessr/articles/extending.html) (`extending`): registering your own extractors, cleaners, segmenters, readers and embedders, declaring their calls and cost, and checking them against the contract.

### Upgrade

- [Upgrading from older versions](https://elkronos.github.io/harnessr/articles/migrate.html) (`migrate`): the old names from readgpt and v1, their replacements and the behaviour that changed.

## Getting help

Ask questions and report bugs at
<https://github.com/elkronos/harnessr/issues>.
[CONTRIBUTING.md](https://github.com/elkronos/harnessr/blob/main/CONTRIBUTING.md)
says how to run the tests and what a pull request must keep true.
