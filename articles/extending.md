# Extending harnessr

Every axis of harnessr is a registry: extractors and cleaners for
ingest, segmenters, readers, embedders, and models. You can list each
one, swap one entry for another, and add your own. An addition behaves
exactly like a built-in. It gets the same token caps, provenance and
reporting, it is held to the same call and spending limits, and it can
be named in a recipe, put in an `ensemble`, and compared against a
built-in with
[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md).

This guide shows how to register each kind of module, how a module that
calls the model declares its calls and its cost, how a spec states its
parameters, and how to check a module of your own against the contract
the built-ins follow.
[`vignette("harnessr")`](https://elkronos.github.io/readgpt/articles/harnessr.md)
introduces the package and its ideas.

## Setting up

The examples run offline.
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
is a client whose handler is an ordinary R function; it goes everywhere
a real client goes and records every prompt it was sent, which is how
you check that a module of your own does what you think before you pay
for it. `embedder = "lexical"` keeps embedding free and offline too.

``` r

library(harnessr)
old <- gr_options(verbose = FALSE, embedder = "lexical")
cl <- gr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
```

## Getting text in: extractors and cleaners

An extractor turns a file into text blocks. It is a function of
`(path, opts)` that returns a data frame with a `text` column, and
optionally `page`, `section` and `kind`.
[`gr_register_extractor()`](https://elkronos.github.io/readgpt/reference/gr_register_extractor.md)
names the file extensions it claims.

``` r

gr_register_extractor("tsv", "tsv", description = "TSV, one block per row",
  fn = function(path, opts) {
    d <- utils::read.delim(path, stringsAsFactors = FALSE)
    data.frame(text = apply(d, 1, paste, collapse = " | "), kind = "table")
  })

tsv <- tempfile(fileext = ".tsv")
writeLines(c("region\trevenue", "north\t45.2", "south\t51.8"), tsv)
cat(gr_ingest(tsv)$text)
#> north | 45.2
#> 
#> south | 51.8
```

Pages an extractor could not turn into text can be listed in
`attr(result, "gr_unread_pages")`. An answer drawn from the document is
then marked partial, as it is for a PDF page that needed OCR and did not
get it.

A cleaner is a function of `(text, opts)` that returns cleaned text. Its
`stage` says when it runs: `"early"` steps preserve structure
(boilerplate removal), `"late"` steps normalise destructively (digit
stripping), and early steps always run before late ones whatever order
you list them in.

``` r

gr_register_cleaner("drop_confidential", stage = "early",
  description = "Remove CONFIDENTIAL banner lines",
  fn = function(x, o) gsub("(?mi)^\\s*CONFIDENTIAL.*$", "", x, perl = TRUE))

cleaned <- gr_clean("CONFIDENTIAL - DRAFT\n\nThe real content of the document.",
                    steps = c("drop_confidential", "collapse_whitespace"))
as.character(cleaned)
#> [1] "The real content of the document."
```

A cleaner runs on each text block by default. One that reasons about
position or repetition across the whole document, such as dropping a
trailing bibliography or a running head, needs `scope = "document"`;
applied per block, it would never fire.
[`?gr_register_cleaner`](https://elkronos.github.io/readgpt/reference/gr_register_cleaner.md)
says how its result is matched back to the blocks.
[`vignette("ingest")`](https://elkronos.github.io/readgpt/articles/ingest.md)
covers the built-in extractors and cleaners.

## Cutting text up: segmenters

A segmenter is a function of `(doc, spec, client, trace)` that returns a
`gr_chunks`. Build that object with
[`new_chunks()`](https://elkronos.github.io/readgpt/reference/new_chunks.md):
[`gr_segment()`](https://elkronos.github.io/readgpt/reference/gr_segment.md)
rejects anything else, and the constructor is what gives your segmenter
the same invariants as the built-ins (blank units dropped, `chunk_id`
assigned in order, tokens and characters measured, provenance recycled
to match).

``` r

gr_register_segmenter("by_bullet", description = "one chunk per bullet",
  fn = function(doc, spec, client, trace) {
    units <- unlist(strsplit(doc$text, "\n(?=[-*])", perl = TRUE))
    new_chunks(units, "by_bullet", spec)
  })

subset(gr_segmenters(), name == "by_bullet")
#>        name cost needs_client          description     calls
#> 1 by_bullet free        FALSE one chunk per bullet by_bullet
```

[`new_chunks()`](https://elkronos.github.io/readgpt/reference/new_chunks.md)
does not enforce the token cap.
[`gr_segment()`](https://elkronos.github.io/readgpt/reference/gr_segment.md)
checks it after your function returns and splits anything oversized, so
a segmenter that ignores `spec$max_tokens` still produces chunks that
fit. The conformance check below reports each chunk it had to split.

Three arguments describe what the segmenter spends. `cost` is `"free"`,
`"embedding"` or `"llm"`, so a UI can warn before anything is spent.
`needs_client = TRUE` says it cannot work without a client; without one,
[`gr_segment()`](https://elkronos.github.io/readgpt/reference/gr_segment.md)
warns with class `gr_segment_fallback`, and the segmenter should record
what it fell back to in its `method` (`"mine->paragraph"`) so the
downgrade shows in
[`gr_chunk_stats()`](https://elkronos.github.io/readgpt/reference/gr_chunk_stats.md).
`calls` declares the labels of its model calls, as the next sections
describe for readers; `character(0)` says it makes none.
[`vignette("segment")`](https://elkronos.github.io/readgpt/articles/segment.md)
covers the built-in segmenters.

## Reading: readers

A reader is a function of `(chunks, question, client, spec, trace)` that
returns a `gr_answer`, built with
[`new_answer()`](https://elkronos.github.io/readgpt/reference/new_answer.md).
This one answers from the longest chunk only:

``` r

gr_register_reader("longest", signature = "one|1|none", cost_calls = "1",
  description = "answer from the longest chunk only",
  calls = "longest.answer",
  cost = function(input_stats, params) hr_cost(calls = 1),
  fn = function(chunks, question, client, spec, trace) {
    d <- chunks$chunks
    i <- which.max(d$tokens)
    res <- gr_call(client, list(list(role = "user",
             content = paste0(d$text[i], "\n\nQuestion: ", question))),
           model = spec$model, effort = spec$effort, trace = trace,
           label = "longest.answer")
    new_answer(res$text, "longest", question, d$chunk_id[i], trace,
               partial = !isTRUE(res$ok))
  })

ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 120))
gr_read(ch, "What was revenue?", cl, "longest")$answer
#> [1] "Revenue was 45.2 million dollars."
```

Inside the function, `chunks$chunks` is the data frame of chunks
(`chunk_id`, `text`, `tokens`, `chars`, `page`, `section`, `block_id`).
Send every request through
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md)
with the client you were given, never one you construct, and pass it the
`trace`: that is what counts, prices and limits your calls. A request
that would pass `max_calls` or `max_cost_usd` is not sent and comes back
with `refused = TRUE`, so stop or degrade when one does. Honour at least
`spec$model`, `spec$max_answer_tokens`, `spec$temperature` and
`spec$effort`, and budget the prompt with
[`gr_budget()`](https://elkronos.github.io/readgpt/reference/gr_budget.md)
rather than assuming the document fits.

The `signature`, `"select|calls|state"`, says how the reader traverses
the chunks. Two readers with the same signature are the same method
under two names:
[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md)
uses it to decide whether two recipes are the same experiment, and
`ensemble` refuses members that share one. A `select` of `"all"` says
the reader sends every chunk, so a run whose chunks alone would cost
more than `max_cost_usd` is refused before its first request.
[`gr_reader_signature()`](https://elkronos.github.io/readgpt/reference/gr_reader_signature.md)
reports a reader’s signature, so two readers claiming to differ can be
checked rather than believed. `cost_calls` is a description for people,
shown by
[`gr_readers()`](https://elkronos.github.io/readgpt/reference/gr_readers.md);
the pre-flight check never reads it.

The name `"auto"` is reserved, because
[`answer_document()`](https://elkronos.github.io/readgpt/reference/answer_document.md)
uses it to choose a recipe.
[`vignette("readers")`](https://elkronos.github.io/readgpt/articles/readers.md)
covers the built-in readers.

## Declaring calls

Every
[`gr_call()`](https://elkronos.github.io/readgpt/reference/gr_call.md)
carries a `label`, and the label is the `stage` column of the trace. A
module declares the stems of its labels in `calls`. A label is covered
by a stem it equals, or one it starts with followed by a dot. Leave
`calls` out and the module declares its own name, which covers labels
such as `"longest.answer"` for a reader called `"longest"`.

The declaration is what an `effort` map is checked against. Each name in
`gr_read_spec(effort =)` must be a declared stem, a part of one up to a
dot, or a label under one. Anything else is an error of class
`hr_unknown_effort_key` that lists the stems, rather than a setting that
silently reaches no request:

``` r

spec <- gr_read_spec("longest", effort = c(longest = "low"))
spec$effort
#> longest 
#>   "low"

tryCatch(gr_read_spec("longest", effort = c(longst = "low")),
         hr_unknown_effort_key = function(e) "refused: no call is labelled 'longst'")
#> [1] "refused: no call is labelled 'longst'"
```

An effort map that names the calls of your own module needs the module
registered first, with its labels in `calls`.
[`gr_readers()`](https://elkronos.github.io/readgpt/reference/gr_readers.md)
and
[`gr_segmenters()`](https://elkronos.github.io/readgpt/reference/gr_segmenters.md)
list every module’s stems in their `calls` column.
[`vignette("runs")`](https://elkronos.github.io/readgpt/articles/runs.md)
says what effort does and which models it is sent to.

## Declaring cost

The `cost` argument of
[`gr_register_reader()`](https://elkronos.github.io/readgpt/reference/gr_register_reader.md)
is a function of `(input_stats, params)` that returns
[`hr_cost()`](https://elkronos.github.io/readgpt/reference/hr_cost.md):
how many requests one run makes, expected and at worst. `params` is the
[`gr_read_spec()`](https://elkronos.github.io/readgpt/reference/gr_read_spec.md).
`input_stats` has `n_chunks`, `tokens` (of all chunks), `texts`,
`question`, `out_cap` (the largest reply cap a request to `params$model`
is sent) and `embed_api` (whether embeddings go to the endpoint at all),
with helpers `reply_cap(model, cap)`, `room(system, restate)` and
`embed_requests(texts)`.

This reader asks every chunk and then merges the notes, so it makes one
request per chunk plus one:

``` r

gr_register_reader("each", signature = "all|N+1|none", cost_calls = "N + 1",
  description = "ask every chunk, then merge",
  calls = c("each.chunk", "each.merge"),
  cost = function(input_stats, params) hr_cost(calls = input_stats$n_chunks + 1),
  fn = function(chunks, question, client, spec, trace) {
    d <- chunks$chunks
    notes <- vapply(seq_len(nrow(d)), function(i) {
      gr_call(client, list(list(role = "user",
                content = paste0(d$text[i], "\n\nQuestion: ", question))),
              model = spec$model, effort = spec$effort, trace = trace,
              label = "each.chunk")$text
    }, character(1))
    res <- gr_call(client, list(list(role = "user",
             content = paste(c(notes, question), collapse = "\n\n"))),
           model = spec$model, effort = spec$effort, trace = trace,
           label = "each.merge")
    new_answer(res$text, "each", question, d$chunk_id, trace,
               partial = !isTRUE(res$ok))
  })

a <- gr_read(ch, "What was revenue?", cl, "each")
table(as.data.frame(a$trace)$stage)
#> 
#> each.chunk each.merge 
#>          6          1
```

[`gr_read()`](https://elkronos.github.io/readgpt/reference/gr_read.md)
adds up the cost functions of a run before the first request, and the
governor decides from the sum whether the run fits its limits. Under a
cap of three calls, the six chunks above are refused before anything is
sent:

``` r

capped <- gr_options(max_calls = 3)
tryCatch(gr_read(ch, "What was revenue?", cl, "each"),
         gr_call_cap = function(e) conditionMessage(e))
#> [1] "Reader 'each' over 6 chunks would need about 7 more model calls (0 already made this run), above the 3-call cap. Use a larger `max_tokens` when segmenting (fewer chunks), pick a top-k reader, or raise gr_options(max_calls = ...)."
gr_options(capped)
```

A reader registered without `cost` is counted as one request per chunk
and, for a signature whose `select` is `"all"`, every chunk sent once.
Declare `cost` for any reader that makes a different number of requests.

[`hr_cost()`](https://elkronos.github.io/readgpt/reference/hr_cost.md)
has more fields than `calls`. `calls_max` is the worst case, never taken
as less than `calls`. `tokens_in_max` counts prompt tokens sent beyond
the input itself, such as replies handed on to a merge. `tokens_out_max`
is for a reader whose replies can be billed beyond the reply cap;
otherwise the check prices every request at `input_stats$out_cap`.
`embed_max` counts requests to the embeddings endpoint, and `sends`
lists input every run must send, as `list(tokens =, model =)`, so a run
that cannot finish under the spending limit is refused before it starts.

``` r

hr_cost(calls = 4, calls_max = 6)$calls_max
#> [1] 6
```

[`vignette("runs")`](https://elkronos.github.io/readgpt/articles/runs.md)
covers the governor, its limits and the pre-flight step in the trace.

## Embedders

Embedders are a registry too. They make `retrieve` and the `semantic`
segmenter work offline, for free, and reproducibly:

``` r

gr_embedders()
#>      name deterministic
#> 1     api         FALSE
#> 2 lexical          TRUE
#>                                                    description
#> 1                 Embeddings endpoint on the client's base URL
#> 2 Hashed bag-of-words; free, offline, word overlap not meaning
```

`gr_options(embedder = "lexical")` switches every part of the package
that embeds. An embedder is a function of `(texts, params)` that returns
a numeric matrix with one row per text, rows L2-normalised, since
everything downstream treats the cross-product as cosine similarity.
`params` carries `client`, `model`, `batch_size`, `cache` and `trace`.
Signal failure by raising an error; the caller applies its own fallback.
Register your own (a local model, a company service) and the `semantic`
segmenter and the `retrieve` and `iterative` readers all use it, with no
change to any of them.

``` r

gr_register_embedder("first-letters", description = "Toy: letter counts",
  deterministic = TRUE,
  fn = function(texts, params) {
    t(vapply(texts, function(tx) {
      v <- numeric(26)
      ltr <- utf8ToInt(tolower(substr(tx, 1, 40))) - 96L
      for (i in ltr[ltr >= 1 & ltr <= 26]) v[i] <- v[i] + 1
      n <- sqrt(sum(v^2)); if (n == 0) v else v / n
    }, numeric(26), USE.NAMES = FALSE))
  })

toy <- gr_options(embedder = "first-letters")
attr(gr_embed(cl, c("alpha", "beta")), "embedding_source")
#> [1] "first-letters"
gr_options(toy)
```

Set `deterministic = TRUE` only if the same text always gives the same
vector, in any session on any machine. A trace records model calls, not
vectors, and that flag is what lets
[`gr_replay_client()`](https://elkronos.github.io/readgpt/reference/gr_replay_client.md)
recompute a run’s chunk ranking instead of degrading to lexical vectors.
Claiming it wrongly makes a replay rank chunks from vectors the original
run never saw, while reporting an exact match.

## Models

The model registry holds each model’s context window, output limit and
prices. Register a model the package does not know, or override a
built-in entry whose prices have gone stale:

``` r

gr_register_model("my-local-llama", context_window = 32768, max_output = 4096)
gr_model_info("my-local-llama")[c("context_window", "source", "certain")]
#> $context_window
#> [1] 32768
#> 
#> $source
#> [1] "registered"
#> 
#> $certain
#> [1] TRUE
```

Without prices, a cost cannot be estimated, and harnessr says so rather
than assuming the run is free:

``` r

is.na(gr_estimate_cost("my-local-llama", 1000, 500))
#> [1] TRUE
```

While a spending limit is set, a request to a language model with no
registered price is refused before it is sent (embedding models and
[`gr_mock_client()`](https://elkronos.github.io/readgpt/reference/gr_mock_client.md)
are exempt). Give `input_usd` and `output_usd` in US dollars per million
tokens, or let a local model run unpriced with
`gr_options(allow_unpriced = TRUE)`. `reasoning = TRUE` marks a model
that takes an effort setting. The README’s section on connecting a model
shows both for a model reached through ellmer.

## Using what you registered

A registered module is named like a built-in. A recipe binds one choice
from each axis, and
[`answer_document()`](https://elkronos.github.io/readgpt/reference/answer_document.md)
runs it:

``` r

mine <- gr_recipe("bullets_longest",
                  segment = list(method = "by_bullet", max_tokens = 400),
                  read = list(reader = "longest"))
answer_document(gr_example(), "What was revenue?", recipe = mine,
                client = cl)$answer
#> [1] "Revenue was 45.2 million dollars."
```

[`gr_compare()`](https://elkronos.github.io/readgpt/reference/gr_compare.md)
runs several recipes on one document and question, sharing one trace, so
your addition can be measured against a built-in on calls, tokens and
cost:

``` r

cmp <- gr_compare(gr_example(), "What was revenue?",
                  recipes = list(mine, "fast"), client = cl)
cmp$summary[, c("recipe", "segmenter", "chunks", "reader", "calls")]
#>            recipe segmenter chunks  reader calls
#> 1 bullets_longest by_bullet      2 longest     1
#> 2            fast paragraph      1   stuff     1
```

## Parameter schemas

Each spec constructor states its parameters once, as a schema: type,
default, range and choices.
[`gr_read_spec()`](https://elkronos.github.io/readgpt/reference/gr_read_spec.md),
[`gr_segment_spec()`](https://elkronos.github.io/readgpt/reference/gr_segment_spec.md)
and
[`gr_ingest_spec()`](https://elkronos.github.io/readgpt/reference/gr_ingest_spec.md)
check their arguments this way, and the same three functions are there
for a module of your own.
[`hr_param()`](https://elkronos.github.io/readgpt/reference/hr_param.md)
declares one parameter,
[`hr_schema()`](https://elkronos.github.io/readgpt/reference/hr_schema.md)
collects them, and
[`hr_validate()`](https://elkronos.github.io/readgpt/reference/hr_validate.md)
applies the rules.

``` r

s <- hr_schema(
  hr_param("max_tokens", "integer", default = 1200L, min = 32, max = 1e6,
           help = "Largest chunk, in tokens."),
  hr_param("overlap_tokens", "integer", default = 0L, min = 0,
           max = function(p) p$max_tokens - 1L,
           help = "Tokens repeated between neighbouring chunks."),
  hr_param("order", "enum", choices = c("relevance", "document"),
           help = "How chosen chunks are ordered in the prompt."))
s
#> <hr_schema> 3 parameter(s)
#>   max_tokens                 integer       [32, 1e+06]
#>   overlap_tokens             integer       [0, f()]
#>   order                      enum          relevance|document
```

The parameters resolve in schema order, so a bound that depends on
another parameter, such as `overlap_tokens` above, comes after it. A
number out of range is moved to the nearest bound and warned about with
class `gr_clamped` (and `hr_param_clamped`). An `enum` is matched as
[`match.arg()`](https://rdrr.io/r/base/match.arg.html) matches, so an
unambiguous abbreviation is accepted:

``` r

withCallingHandlers(
  str(hr_validate(s, list(max_tokens = 100, overlap_tokens = 500, order = "doc"))),
  gr_clamped = function(w) {
    message(conditionMessage(w))
    invokeRestart("muffleWarning")
  })
#> `overlap_tokens` 500 is outside [0, 99]; using 99.
#> List of 3
#>  $ max_tokens    : int 100
#>  $ overlap_tokens: int 99
#>  $ order         : chr "document"
```

A name the schema does not have is an error of class `hr_unknown_param`,
and a value outside an `enum`’s choices is an error naming them:

``` r

tryCatch(hr_validate(s, list(top_k = 3)),
         hr_unknown_param = function(e) conditionMessage(e))
#> [1] "'top_k' not a parameter of this schema. Parameters: max_tokens, overlap_tokens, order."
```

The types are `integer`, `number`, `string`, `boolean`, `enum`,
`string_vector`, `named_map`, `module_ref` and `file`;
[`?hr_param`](https://elkronos.github.io/readgpt/reference/hr_param.md)
gives the rule for each. A `resolve` function replaces the type’s rule
for a parameter that needs its own. The other fields describe the
parameter rather than check it: `help` (one plain sentence),
`cost_class` (how it moves the cost of a run: `"none"`, `"local"`,
`"per_call_constant"`, `"per_unit"`, `"per_sample"` or `"per_round"`),
`affects_output` (whether it belongs in cache and store keys), `tier`
(`"basic"` or `"advanced"`, for grouping in a user interface),
`evidence`, `depends_on` and `since`. They are there so a later UI or
command line can be built from the same list.

## Checking a module against the contract

[`gr_check_reader()`](https://elkronos.github.io/readgpt/reference/gr_check_reader.md)
and
[`gr_check_segmenter()`](https://elkronos.github.io/readgpt/reference/gr_check_segmenter.md)
run one registered module on the bundled example document, through an
offline client, and report which rules of its contract it breaks. In
this release they are reports only: registering a module does not run
them, and a module that breaks a rule stays registered and runs as
before. Every built-in reader and segmenter passes.

The `longest` reader above passes all nine reader rules:

``` r

gr_check_reader("longest")
#> <hr_conformance> reader 'longest', contract 0.1
#>   passes all 9 rules
#>   ok    is_function
#>   ok    runs
#>   ok    answer_class
#>   ok    answer_fields
#>   ok    answer_text
#>   ok    evidence: no evidence
#>   ok    chunks_used
#>   ok    calls_declared: 1 call(s), all under declared stems
#>   ok    calls_within_cost: 1 request(s) made, at most 1 expected
```

This one does not. It sends a call under a label it did not declare,
makes two requests where its cost function promised one, and names a
chunk that does not exist:

``` r

gr_register_reader("loose", signature = "one|2|none", calls = "loose.answer",
  cost = function(input_stats, params) hr_cost(calls = 1),
  fn = function(chunks, question, client, spec, trace) {
    gr_call(client, list(list(role = "user", content = question)),
            model = spec$model, trace = trace, label = "other.answer")
    res <- gr_call(client, list(list(role = "user", content = question)),
                   model = spec$model, trace = trace, label = "loose.answer")
    new_answer(res$text, "loose", question, 99L, trace)
  })

gr_check_reader("loose")
#> <hr_conformance> reader 'loose', contract 0.1
#>   fails 3 of 9 rules
#>   FAIL  chunks_used: chunk id(s) 99 are not in the chunks
#>   FAIL  calls_declared: label(s) 'other.answer' not under the declared stems loose.answer
#>   FAIL  calls_within_cost: 2 request(s) made, at most 1 expected
#>   ok    is_function
#>   ok    runs
#>   ok    answer_class
#>   ok    answer_fields
#>   ok    answer_text
#>   ok    evidence: no evidence
```

The broken rules print first, each with what was found. The reader rules
are `is_function` and `runs` (it finishes without an error),
`answer_class` and `answer_fields` (a `gr_answer` with every documented
field), `answer_text` (a single string), `evidence` and `chunks_used`
(they name only chunks of the input), `calls_declared` (every label is
under a declared stem) and `calls_within_cost` (no more requests than
the cost function’s worst case; `NA` for a reader registered without
`cost`).

The `by_bullet` segmenter from earlier fails one rule. The example
document has no bullets, so it comes back as a single chunk over the
150-token cap the check cuts with, and
[`gr_segment()`](https://elkronos.github.io/readgpt/reference/gr_segment.md)
had to split it:

``` r

gr_check_segmenter("by_bullet")
#> <hr_conformance> segmenter 'by_bullet', contract 0.1
#>   fails 1 of 8 rules
#>   FAIL  within_cap: 1 chunk(s) over the 150-token cap
#>   ok    is_function
#>   ok    runs
#>   ok    chunks_class
#>   ok    chunk_columns
#>   ok    chunk_text
#>   ok    chunk_ids
#>   ok    calls_declared: no model calls
```

Splitting on blank lines as well as bullets keeps every chunk under the
cap:

``` r

gr_register_segmenter("by_bullet", description = "one chunk per bullet or paragraph",
  fn = function(doc, spec, client, trace) {
    units <- unlist(strsplit(doc$text, "\n(?=[-*])|\n\\s*\n", perl = TRUE))
    new_chunks(trimws(units), "by_bullet", spec)
  })

gr_check_segmenter("by_bullet")
#> <hr_conformance> segmenter 'by_bullet', contract 0.1
#>   passes all 8 rules
#>   ok    is_function
#>   ok    runs
#>   ok    chunks_class
#>   ok    chunk_columns
#>   ok    chunk_text
#>   ok    chunk_ids
#>   ok    within_cap
#>   ok    calls_declared: no model calls
```

The segmenter rules are `is_function`, `runs`, `chunks_class`,
`chunk_columns` (the documented columns), `chunk_text` (no blank chunk),
`chunk_ids` (unique, not `NA`), `within_cap` and `calls_declared`. A
segmenter that needs a client, or declares calls, is given the offline
one; pass `client =` to check it against another.

Both checks return an `hr_conformance` data frame with `rule`, `ok` and
`detail` columns, so a package of modules can assert on it in its own
tests:

``` r

res <- gr_check_reader("loose")
res$rule[!is.na(res$ok) & !res$ok]
#> [1] "chunks_used"       "calls_declared"    "calls_within_cost"
```

[`hr_check_module()`](https://elkronos.github.io/readgpt/reference/hr_check_module.md)
is the core helper both checks use, and it works for a module of any
kind. Give it the module’s function, a closure of no arguments that runs
the module once, and a named list of rules, each a function of the value
the closure returned. A rule returns `TRUE`, `FALSE`, `NA` (could not be
checked), or a list with `ok` and a `detail` string. The closure runs in
a temporary working directory that is removed afterwards, and an error
it raises is reported by the `runs` rule.

``` r

double_it <- function(x) x * 2
hr_check_module(double_it, function() double_it(2),
  rules = list(numeric = function(v) is.numeric(v),
               above_three = function(v) list(ok = v > 3, detail = sprintf("got %s", v))),
  kind = "function", name = "double_it")
#> <hr_conformance> function 'double_it', contract 0.1
#>   passes all 4 rules
#>   ok    is_function
#>   ok    runs
#>   ok    numeric
#>   ok    above_three: got 4
```

## Next

- [`?gr_register_reader`](https://elkronos.github.io/readgpt/reference/gr_register_reader.md)
  and
  [`?gr_register_segmenter`](https://elkronos.github.io/readgpt/reference/gr_register_segmenter.md):
  the full contract for each, with every argument a module receives.
- [`?new_chunks`](https://elkronos.github.io/readgpt/reference/new_chunks.md)
  and
  [`?new_answer`](https://elkronos.github.io/readgpt/reference/new_answer.md):
  the constructors a segmenter and a reader return.
- [`vignette("runs")`](https://elkronos.github.io/readgpt/articles/runs.md):
  limits, the pre-flight check, effort, and replaying a run.
