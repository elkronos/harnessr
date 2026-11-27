# Upgrading from older versions

Read this page if you have code written for readgpt, the package’s name
up to version 0.6.0, or for its first version (v1), and want it to run
on harnessr 0.7.0. Each table lists an old name, the name that replaced
it and what to change in your code. None of the old names has an alias:
calling an old function stops with “could not find function”. One
section has no table: from 0.7.0 built-in models carry no prices, so you
set the prices you pay. `NEWS.md` lists every change release by release.

The files listed under “What still loads”, at the end of this page,
still load. A response cache written by readgpt 0.5.1 or earlier is not
read.

## From readgpt 0.6.0: core functions now start with hr\_

The 27 core functions that began with `gr_` now begin with `hr_`, like
the rest of the core layer. Document-layer functions such as
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
and
[`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
keep `gr_`, so replace only the names in this table. A blanket search
and replace of `gr_` breaks them.

| Old | New | What to change |
|----|----|----|
| `gr_api_key()` | [`hr_api_key()`](https://elkronos.github.io/harnessr/reference/hr_api_key.md) | Rename the call. |
| `gr_backend_client()` | [`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md) | Rename the call. |
| `gr_budget()` | [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md) | Rename the call. |
| `gr_cache()` | [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md) | Rename the call. |
| `gr_cache_clear()` | [`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md) | Rename the call. |
| `gr_cache_client()` | [`hr_cache_client()`](https://elkronos.github.io/harnessr/reference/hr_cache_client.md) | Rename the call. |
| `gr_cache_stats()` | [`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md) | Rename the call. |
| `gr_call()` | [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md) | Rename the call. |
| `gr_client()` | [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md) | Rename the call. |
| `gr_count_tokens()` | [`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md) | Rename the call. |
| `gr_ellmer_client()` | [`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md) | Rename the call. |
| `gr_embed()` | [`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md) | Rename the call. |
| `gr_estimate_cost()` | [`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md) | Rename the call. |
| `gr_mock_client()` | [`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md) | Rename the call. |
| `gr_model_info()` | [`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md) | Rename the call. |
| `gr_model_limits()` | [`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md) | Rename the call. |
| `gr_models()` | [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md) | Rename the call. |
| `gr_options()` | [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md) | Rename the call. |
| `gr_register_model()` | [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md) | Rename the call. |
| `gr_replay_client()` | [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md) | Rename the call. |
| `gr_set_tokenizer()` | [`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md) | Rename the call. |
| `gr_tokenizer()` | [`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md) | Rename the call. |
| `gr_trace()` | [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md) | Rename the call. |
| `gr_trace_cost()` | [`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md) | Rename the call. |
| `gr_trace_save()` | [`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md) | Rename the call. |
| `gr_trace_summary()` | [`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md) | Rename the call. |
| `gr_truncate_tokens()` | [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md) | Rename the call. |

The objects these functions return keep their `gr_` classes. Code that
tests `inherits(x, "gr_client")` or handles a `gr_call_cap` condition
works as before.

### Before and after

Most scripts written for 0.6.0 make a client, call it and read the
trace. In 0.6.0 that read:

``` r

library(readgpt)
cl <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
tr <- gr_trace()
res <- gr_call(cl, "What was revenue?", trace = tr)
gr_trace_summary(tr)$calls
```

Now it reads as below. The package name and the four core calls change;
the arguments, the reply and the class stay the same:

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
cl <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
tr <- hr_trace()
res <- hr_call(cl, "What was revenue?", trace = tr)
res$text
#> [1] "Revenue was 45.2 million dollars."
hr_trace_summary(tr)$calls
#> [1] 1
inherits(cl, "gr_mock_client")
#> [1] TRUE
```

## From readgpt 0.6.0: the package, options and other removed names

harnessr was called readgpt up to version 0.6.0, and so was its GitHub
repository. The rename itself changes no request or key. harnessr 0.7.0
does move the response cache to the key `harnessr-cache-v3` and replay
to `harnessr-replay-v2`; “What still loads” says how old entries are
found.

| Old | New | What to change |
|----|----|----|
| `readgpt` | `harnessr` | Load it with [`library(harnessr)`](https://github.com/elkronos/harnessr) and install it with `remotes::install_github("elkronos/harnessr")`. GitHub sends the old repository address to the new one. |
| `readgpt_example()` | [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md) | Rename the call. It returns the same path to the bundled example document. |
| `options(readgpt.api_key =)` | `options(harnessr.api_key =)` | Rename the option. harnessr ignores the old one, so a key set only there is not found. |
| `options(readgpt.allow_local_urls =)` | `options(harnessr.allow_local_urls =)` | Rename the option. harnessr ignores the old one. |
| the `gr_deprecated` warning class | none | Drop handlers for it. Nothing warns about an old name now. |

## From readgpt 0.6.0: models carry no prices

readgpt 0.6.0 shipped a price for each built-in model. harnessr 0.7.0
ships their limits and no prices, because providers change prices more
often than the package is released. Three things change for code written
for 0.6.0:

- A cost for a built-in model is `NA` until you set its prices. That
  holds for
  [`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md),
  [`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md)
  and every other report of a cost in dollars.
- Under `max_cost_usd`, a request to a chat model with no price is sent,
  as in 0.6.0. 0.6.0 warned with class `gr_cost_uncheckable` on every
  read; now the first such request to each model in a session warns with
  class `hr_unpriced_model`, and later ones do not. The spending limit
  does not count the request; `max_calls` and `max_tokens_total` do.
- A cost computed from prices older than `price_max_age_days` (120 by
  default) warns with class `hr_stale_price`, once per model per
  session.

Set the prices you pay with
[`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
for one model, or with
[`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
for a file of them. A built-in model keeps its limits when you give only
its prices:

``` r

old <- hr_options(verbose = FALSE)
# Illustrative figures: use your provider's current prices.
hr_register_model("gpt-4o", input_usd = 2.50, output_usd = 10)
hr_estimate_cost("gpt-4o", input_tokens = 120000, output_tokens = 4000)
#> [1] 0.34
```

To refuse unpriced requests instead, set the new option
`hr_options(allow_unpriced = FALSE)`. “Prices” in
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)
walks through setting prices from a file, checking them and keeping them
current.

## From v1

v1, the package’s first version, had six entry points that 0.2.0
replaced and later versions removed. Each has a replacement:

| Old | New | What to change |
|----|----|----|
| `answer_question()` | [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md) | `answer_question(f, q, mode = "Chunked")` becomes `answer_document(f, q, "thorough")`. To run several recipes on one document, use [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md). |
| `parse_text()` | [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md), then [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md) | `parse_text(f, chunk_method = "semantic")` becomes `gr_segment(gr_ingest(f), "semantic", client = cl)`. Semantic chunking embeds, so it needs a client; without one it warns and cuts paragraphs. |
| `gpt_read_chunked()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) | Segment first, then call `gr_read(chunks, q, cl, "map_reduce")`. |
| `gpt_read_retrieval()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) | Segment first, then call `gr_read(chunks, q, cl, "skim")`. |
| `gpt_read_hierarchical()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) | Segment first, then call `gr_read(chunks, q, cl, "hierarchical")`. |
| `gpt_read_multipass()` | [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md) | Segment first, then call `gr_read(chunks, q, cl, "ensemble")`. |

Three behaviour changes from v1 are deliberate and will alter your
results:

1.  **`mode` no longer defaults to all five modes.**
    `answer_question(f, q)` in v1 ran every mode: 41 API calls on an
    8-paragraph document, where one was expected.
2.  **Modes no longer contaminate each other.** In v1,
    `mode = c("Chunked", "Semantic")` changed Chunked’s chunking, its
    cost, and its answer relative to `mode = "Chunked"` alone.
3.  **Digits are no longer stripped by default.** v1’s
    `remove_numbers = TRUE` default was unreachable from
    `answer_question()`, so every figure, date and percentage was
    deleted before the model saw the document.

For v1’s `refine = TRUE`, ask for citations with `cite = TRUE` in
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md).
Its verification pass has no replacement because it could not run: it
called a `search_text()` function that the repository never defined.

The v1 source is kept under `legacy/` in the repository for reference
and A/B comparison. The package does not load it. To reproduce its
ingestion and chunking under the current code, use the `legacy` recipe.
It strips digits, as v1 did, and cuts 3000-token paragraph chunks with
no overlap:

``` r

old <- hr_options(verbose = FALSE)
legacy <- gr_recipes("legacy")
gr_ingest("Revenue was 45.2 million dollars in fiscal 2024.", legacy$ingest)$text
#> [1] "Revenue was . million dollars in fiscal ."
unlist(legacy$segment[c("method", "max_tokens", "overlap_tokens")])
#>         method     max_tokens overlap_tokens 
#>    "paragraph"         "3000"            "0"
```

Two tests in `tests/testthat/` fail if the current code undoes the
second or third change above: “a recipe’s answer does not depend on what
it is compared against”, in `test-distinctness.R`, and “digits survive
ingestion by default”, in `test-regressions-v1.R`. `answer_question()`
is removed, and `test-removed-names.R` fails if it is exported or
defined again.

## What still loads

harnessr writes new cache entries under the key `harnessr-cache-v3` and
records replay steps under `harnessr-replay-v2`. When a call finds
nothing under the new key, harnessr looks it up under the old one, and a
reply found that way raises an `hr_legacy_key` warning. Each item below
names the test in `tests/testthat/` that loads such a file.

- **Response caches.** A cache written by readgpt 0.6.0, or by an
  earlier build of harnessr, answers every call it holds through the old
  key `readgpt-cache-v2`, and nothing is sent. The warning comes once
  per cache in a session. A call with a draw index does not read the old
  keys. readgpt 0.5.1 and earlier wrote the key `readgpt-cache-v1`,
  which harnessr does not read, so the calls in such a cache are sent
  again. Tests: “an old cache answers every call through the old key,
  each hit warning” and “an old cache is not read for a draw”, in
  `test-compat-legacy-keys.R`.
- **readgpt’s cache directory.** When your cache directory is
  `tools::R_user_dir("harnessr", "cache")`, entries readgpt kept in
  `tools::R_user_dir("readgpt", "cache")` answer too, after it. harnessr
  never writes to or clears the old directory. Test: “entries readgpt
  kept in its documented cache directory still answer”, in
  `test-compat-legacy-keys.R`.
- **Traces and replay recordings (cassettes).** A trace saved by
  `gr_trace_save()` in 0.6.0 replays with
  [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md),
  strict mode included. Test: “an old recording replays strictly through
  the old key, each hit warning”, in `test-compat-legacy-keys.R`. A
  trace’s `meta` still records the version under `readgpt`, so traces
  from before and after the rename read the same way. Test: “a trace
  records the configuration that produced it, not just the recipe’s
  name”, in `test-hardening.R`.
- **Signal calibrations.** Calibrations keep their own contract version,
  0.1, so a record saved under 0.1 stays valid. Test: “a calibration key
  keeps contract version 0.1, so a saved record stays valid”, in
  `test-contract-02.R`.
- **Stores.** A
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  store written by an older version resumes. Tests: “a store written by
  an older version still resumes”, in `test-corpus.R`, and “a store
  entry written by 0.5.0 is read again once, then restored”, in
  `test-review3-corpus.R`.
- **Class names.** Objects keep their `gr_` classes, so an object saved
  before the rename still dispatches. Tests: “the renamed constructors
  still make gr\_ classes” and “a gr_result saved before the rename
  prints with its method”, in `test-core-names.R`.
