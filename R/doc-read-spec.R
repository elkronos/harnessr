# doc-read-spec.R: the reader registry and the read spec.

#' Register a reading strategy
#'
#' Axis 3 is a registry, so how the model is made to *read* a chunk set is
#' yours to define. A registered reader is a first-class one: it appears in
#' [gr_readers()], can be named in a [gr_recipe()] or an `ensemble`, and is
#' subject to the same call and spending limits as the built-ins.
#'
#' @param name Reader name. Re-registering an existing name replaces it.
#'   `"auto"` is reserved for [answer_document()].
#' @param fn Function of `(chunks, question, client, spec, trace)` returning a
#'   `gr_answer`. See the section below.
#' @param signature Traversal signature, `"select|calls|state"`. Two readers with
#'   the same signature are the same methodology under two names; [gr_compare()]
#'   uses it, together with the ingest and segment specs, to decide whether two
#'   recipes are the same experiment, and `ensemble` refuses members that share
#'   one. A `select` of `"all"` says the reader sends every chunk, so a run
#'   whose chunks alone would cost more than `max_cost_usd` is refused before
#'   its first request.
#' @param description One-line description, shown by [gr_readers()].
#' @param cost_calls Human-readable call count in terms of N chunks (`"N + 1"`,
#'   `"1 + embeddings"`), shown by [gr_readers()]. For people only: the
#'   pre-flight check counts with `cost`.
#' @param calls The stems of the trace labels your reader's calls carry, such
#'   as `c("longest.answer")`. A label is covered by a stem it equals or
#'   starts with followed by a dot. An `effort` map in [gr_read_spec()] may
#'   only name declared stems, or parts of them up to a dot, so declare every
#'   label your reader sends. `NULL` (the default) declares the reader's name,
#'   which covers labels such as `"longest.answer"` for a reader called
#'   `"longest"`.
#' @param cost `NULL`, or a function of `(input_stats, params)` returning
#'   [hr_cost()]: how many requests one run of your reader makes, expected and
#'   at worst. `params` is the [gr_read_spec()]; `input_stats` has `n_chunks`,
#'   `tokens` (of all chunks), `texts`, `question`, `out_cap` (the largest
#'   reply cap a request to `params$model` is sent), `embed_api` (whether
#'   embeddings go to the endpoint at all), and the helpers
#'   `reply_cap(model, cap)`, `room(system, restate)` and
#'   `embed_requests(texts)`. The pre-flight check sums these to refuse a run
#'   that cannot fit the call cap or spending limit before it starts. `NULL`
#'   counts one request per chunk and, for a signature whose `select` is
#'   `"all"`, every chunk sent once.
#' @return Invisibly, `name`.
#'
#' @section Writing a reader:
#' Your function receives:
#' \describe{
#'   \item{`chunks`}{A [gr_chunks]. `chunks$chunks` is the data frame:
#'     `chunk_id`, `text`, `tokens`, `chars`, `page`, `section`, `block_id`.}
#'   \item{`question`}{The question, already validated as non-blank.}
#'   \item{`client`}{Pass it to [gr_call()]; never construct your own.}
#'   \item{`spec`}{A [gr_read_spec()]. Honour at least `model`,
#'     `max_answer_tokens`, `temperature` and `effort`. [gr_read()] has already
#'     filled `model` from the client when the spec named none. Pass
#'     `effort = spec$effort` to every [gr_call()], which resolves a setting
#'     by stage against the call's `label`, so give each call a label of its
#'     own and declare its stem in `calls`; a call without a label is sent no
#'     effort.}
#'   \item{`trace`}{Pass it to every [gr_call()] so your calls are counted,
#'     priced and held to the run's limits: a request that would pass
#'     `max_calls` or `max_cost_usd` is not sent, and comes back with
#'     `refused = TRUE` (see [hr_governor()]). Stop or degrade when one does.
#'     A reader that still checks `harnessr:::trace_can_call(trace)` first, as
#'     earlier versions advised, keeps working.}
#' }
#' Return [new_answer()]. Budget your prompt with [gr_budget()] rather than
#' assuming the document fits.
#'
#' @seealso [new_answer()] to build the return value, [gr_readers()],
#'   [gr_reader_signature()], [gr_read()], [gr_answer], [gr_budget()]
#' @family reading functions
#' @export
#' @examples
#' # A reader that answers from the single longest chunk.
#' gr_register_reader("longest", signature = "one|1|none", cost_calls = "1",
#'   description = "answer from the longest chunk only",
#'   calls = "longest.answer", cost = function(input_stats, params) hr_cost(calls = 1),
#'   fn = function(chunks, question, client, spec, trace) {
#'     d <- chunks$chunks
#'     i <- which.max(d$tokens)
#'     res <- gr_call(client, list(
#'       list(role = "user", content = paste0(d$text[i], "\n\nQuestion: ", question))),
#'       model = spec$model, effort = spec$effort, trace = trace,
#'       label = "longest.answer")
#'     new_answer(res$text, "longest", question, d$chunk_id[i], trace)
#'   })
#'
#' ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 120))
#' gr_read(ch, "What was revenue?", gr_mock_client(function(m, p) "45.2 million"),
#'         "longest")$answer
gr_register_reader <- function(name, fn, signature, description = "", cost_calls = "",
                               calls = NULL, cost = NULL) {
  if (!is.function(fn)) gr_abort("`fn` must be a function of (chunks, question, client, spec, trace).")
  # answer_document(recipe = "auto") would never reach a reader of that name.
  if (identical(as_chr1(name, ""), "auto")) {
    gr_abort(paste0("'auto' is reserved: answer_document() uses it to choose a recipe. ",
                    "Register the reader under another name."), class = "gr_reserved_name")
  }
  if (!grepl("^[^|]+\\|[^|]+\\|[^|]+$", as_chr1(signature))) {
    gr_abort("`signature` must have the form 'select|calls|state', e.g. 'topk|1|none'.")
  }
  if (!is.null(cost) && !is.function(cost)) {
    gr_abort("`cost` must be NULL or a function of (input_stats, params) returning hr_cost().",
             class = "gr_bad_setting")
  }
  calls <- check_calls(calls, as_chr1(name, ""))
  registry_set("readers", name, list(name = name, fn = fn, signature = signature,
                                     description = description, cost_calls = cost_calls,
                                     calls = calls, cost = cost), state = gr_state)
}

#' List registered reading strategies
#'
#' The catalogue for axis 3, and the cheapest way to choose one: the `signature`
#' column tells you how a reader traverses the chunks and `cost_calls` tells you
#' what that costs, both before you spend anything.
#'
#' @return A data frame with one row per registered reader: `name`, `signature`
#'   (see [gr_reader_signature()]), `cost_calls` (a formula in N, the number
#'   of chunks, not a number), `description`, and `calls`, the stems of the
#'   labels its calls carry, joined by commas: the names an `effort` map can
#'   use.
#' @seealso [gr_read()], [gr_reader_signature()], [gr_register_reader()],
#'   [gr_read_spec()], [gr_compare()] to run several and compare
#' @family reading functions
#' @export
#' @examples
#' # Grouped by how they select chunks, which is the real taxonomy:
#' # `all|...` readers see every chunk, `topk|...` readers see a selection.
#' r <- gr_readers()
#' r[order(r$signature), c("name", "signature", "cost_calls")]
gr_readers <- function() {
  with_calls(registry_table("readers", c("signature", "cost_calls", "description"),
                            state = gr_state), gr_state$readers)
}

#' A registry table with each module's declared call stems added, joined by
#' commas.
#' @noRd
with_calls <- function(df, reg) {
  df$calls <- vapply(df$name, function(nm) paste(reg[[nm]]$calls %||% character(0),
                                                 collapse = ", "),
                     character(1), USE.NAMES = FALSE)
  df
}

#' The traversal signature of a reader
#'
#' The signature is how the package tells two reading *methodologies* apart from
#' two names for the same thing. It encodes which chunks reach the model
#' (`select`), the call pattern (`calls`), and whether information flows between
#' calls (`state`).
#'
#' @param reader Reader name, or a `gr_read_spec`.
#' @return A single string `"select|calls|state"`, e.g. `"topk|1|none"`. For
#'   `ensemble` the member list is appended in braces
#'   (`"ensemble|sum+1|none{map_reduce+retrieve}"`), so two ensembles with
#'   different members are correctly seen as different experiments.
#' @seealso [gr_readers()] for every signature at once, [gr_compare()] which
#'   uses this to detect duplicate recipes, [gr_register_reader()]
#' @family reading functions
#' @export
#' @examples
#' # Same document, different traversal: one call over everything, versus one
#' # call per chunk plus merges.
#' gr_reader_signature("stuff")
#' gr_reader_signature("map_reduce")
#'
#' # An ensemble's signature carries its members, so two differently-composed
#' # ensembles are not mistaken for each other.
#' gr_reader_signature(gr_read_spec("ensemble", members = c("retrieve", "refine")))
gr_reader_signature <- function(reader) {
  if (inherits(reader, "gr_read_spec")) {
    base <- registry_get("readers", reader$reader, "readers", state = gr_state)$signature
    if (identical(reader$reader, "ensemble")) {
      base <- paste0(base, "{", paste(sort(reader$members %||% character(0)), collapse = "+"), "}")
    }
    return(base)
  }
  registry_get("readers", as_chr1(reader), "readers", state = gr_state)$signature
}

#' Describe a reading configuration
#'
#' @param reader Reader name; see `gr_readers()`.
#' @param model Chat model id. `NULL` (the default) means the model of the
#'   client the spec is read with, so `gr_client(model = "gpt-4o-mini")` is the
#'   model that answers, is budgeted for and is billed. A model named here, or
#'   in a recipe, is used whatever the client's.
#' @param temperature Sampling temperature, or `NULL` to omit the field. You do
#'   not need to null it yourself for reasoning models: it is dropped
#'   automatically for any model whose registry entry has
#'   `supports_temperature = FALSE`, which includes the default model. Check with
#'   `gr_model_info(model)$supports_temperature`.
#' @param max_answer_tokens Output cap for final answers and merges.
#' @param max_chunk_tokens Output cap for per-chunk calls.
#' @param max_summary_tokens Output cap for summarisation calls.
#' @param top_k For `retrieve`, `rerank` and `iterative`: chunks to use.
#' @param min_score For `retrieve`: chunks scoring below this are dropped, but
#'   if that would leave nothing the single best chunk is used anyway. `-Inf`
#'   disables the filter. Not a cosine similarity when embeddings fall back to
#'   lexical vectors: the score is then a blend of cosine and BM25, and under
#'   `fusion = "rrf"` it is the fused score (see `fusion`). When no chunk
#'   passes, the answer's `notes$below_min_score` is `TRUE`.
#' @param mmr Diversity of selection, for `retrieve` and `iterative`. `1` (the
#'   default) is plain top-k. Below 1, chunks are picked greedily by
#'   `mmr * relevance - (1 - mmr) * similarity to what is already picked`, so
#'   three chunks saying the same thing do not all get in and pay for each other.
#'   Costs nothing: the vectors are already computed. `0.7` is a reasonable
#'   place to start; `0` selects for novelty alone and will happily pick
#'   irrelevant chunks because they are different.
#' @param restate Whether to repeat the question before the excerpts as well as
#'   after them: `"auto"` when the body is long enough to bury the first ask,
#'   `"always"`, or `"never"`. `"window"` repeats it once the excerpts pass the
#'   length the model attends to reliably, its effective window; no model's
#'   effective window is measured yet, so it repeats the question before
#'   excerpts longer than 50,000 tokens and warns (`gr_window_unmeasured`). A setting rather than a rule, because whether it
#'   helps is a question about your corpus and your model. Point [gr_compare()]
#'   at two recipes differing only in this and find out.
#' @param context_order Where the selected chunks sit in the prompt.
#'   `"relevance"` (default) is most relevant first; `"document"` restores the
#'   order they appear in the document, which reads better when chunks are
#'   consecutive; `"edges"` puts the strongest first and second-strongest last,
#'   burying the weakest in the middle, because transformers attend measurably
#'   better to the beginning and end of a long context than to its middle.
#'   Selection is unaffected. This decides only placement, and it applies to
#'   `retrieve`, `rerank` and `iterative`, the readers that put several ranked
#'   chunks in one prompt. Under a `context_policy` with `order_merges = TRUE`
#'   it also places the findings `map_reduce`, `skim` and the write-up merge
#'   combine and the member answers `ensemble` adjudicates. These have no
#'   relevance order, so `"relevance"` and `"document"` keep the order they
#'   come in (document order for findings, member order for an ensemble), and
#'   `"edges"` puts the first first and the second last.
#' @param rerank_candidates,rerank_min_score For `rerank`: how many chunks to
#'   score, and the score below which a chunk is discarded. The candidates are
#'   the chunks the word-matching prefilter ranks highest. When no chunk shares
#'   a word with the question, it cannot rank them, so they are picked by
#'   embedding similarity instead, or, when embeddings cannot rank them either,
#'   spread evenly over the document and the answer marked partial. Either way
#'   the run warns (`gr_rerank_prefilter`) and `notes$prefilter` says which.
#' @param fan_in,max_levels For `hierarchical`: summaries combined per call, and
#'   the recursion depth cap.
#' @param max_rounds For `iterative`: retrieve-assess cycles.
#' @param preview_tokens For `preview`: the cap on the outline the planner sees.
#'   The outline is built from section labels, sizes and short excerpts (never
#'   the full text), and per-section excerpts shrink until the whole thing fits,
#'   so every section stays visible to the planner rather than the outline being
#'   truncated and some sections never being offered to it at all. The planner is
#'   an LLM call about a long document and so prone to exactly the degradation
#'   this package manages; keeping its input small is the mitigation.
#' @param members For `ensemble`: the reader names to combine.
#' @param cite Ask for chunk-level citations (`[chunk 3]`) in the answer. Map
#'   those ids back to pages via `ans$evidence`. Forced off for `hierarchical`,
#'   which answers from summaries: summaries carry no `[chunk N]` ids, so asking
#'   for citations there asks the model to invent them. For `skim`, when its
#'   evidence has to be consolidated to fit and no `[chunk N]` label survives
#'   the consolidation, citations are not asked for either
#'   (`notes$cite_dropped = TRUE`); when some survive, a citation is checked
#'   against those.
#' @param skim_model,summary_model Optional cheaper models for the per-chunk
#'   stages. `skim_model` is used by `skim`'s extraction **and** `rerank`'s
#'   relevance scoring; `summary_model` by `hierarchical`'s summarisation.
#' @param parallel Run per-chunk calls in parallel. Needs the `future` and
#'   `future.apply` packages; without them the run is sequential and says so.
#'
#'   The trace is complete either way: workers keep their own and the parent
#'   absorbs them, in input order, so a parallel run reports the same calls,
#'   tokens and cost as the same run made sequentially. So is what the client
#'   keeps: a mock's or backend's `$calls()` and `$embeds()`, and the hit,
#'   miss and write counts of an attached cache, include the calls made in
#'   workers, added back in input order. A replay client always runs one
#'   request at a time, since it hands out its recording in order.
#'
#'   Two things do not cross the process boundary. The limits in
#'   [gr_options()] are checked before a batch is sent and not inside it,
#'   since a worker cannot see what the others spend. So the pre-flight check,
#'   which runs in the parent, holds a parallel run to its worst case, every
#'   reply at its cap and as many merge or summary levels as replies that size
#'   need, against both `max_calls` and `max_cost_usd`; and each batch goes to
#'   the workers only when it fits what the run has left at its own worst
#'   case, and otherwise runs one request at a time, each checked. And a
#'   handler that records calls in variables of its own (a closure passed to
#'   [gr_backend_client()] or [gr_mock_client()]) records a worker's calls in
#'   that worker's copy, which this process never sees; ask the trace, or the
#'   client's `$calls()`, instead.
#' @param delay_between_calls Seconds to sleep between sequential calls, for
#'   rate-limit shaping. Honoured by `map_reduce`, `refine` and `skim`; the
#'   other readers do not sleep.
#' @param on_overflow For `stuff`: `"warn"` (truncate and say so) or `"error"`.
#' @param effort How much a reasoning model reasons before it answers, or
#'   `NULL` (the default) to send nothing, so every request goes out at the
#'   provider's default exactly as before. One string, such as `"low"`, applies
#'   to every call. A character vector named by stage sets it per stage:
#'   `c(extract = "low", "synthesise.section" = "high")`. A name covers each
#'   call whose trace label is that name or starts with it and a dot; the
#'   longest name that covers a label wins; an unnamed element, or one named
#'   `"default"`, covers the labels no name does, and a label nothing covers is
#'   sent no effort. A name must cover a stem some registered reader,
#'   segmenter or stage declares (the `calls` column of [gr_readers()] and
#'   [gr_segmenters()]), or a label under one, so a misspelt name is an error
#'   of class `hr_unknown_effort_key` that lists the stems, not a setting that
#'   reaches no call. It reaches the segmenters that call a model too, when the
#'   spec is part of a recipe. See the section on reasoning effort.
#' @param premise Check the question's assumptions against the document. A
#'   question can take for granted something the document contradicts ("Why
#'   did revenue fall?" of a report in which it rose). Without this check a
#'   reader answers it on its own terms or reports `NOT_IN_DOCUMENT`, and
#'   either way what the document does say is lost. With `premise = TRUE` the
#'   prompts that answer the question tell the model that, when the excerpts
#'   state the contrary of an assumption in it, it is to say so in one
#'   sentence giving what they state instead, rather than answer. That
#'   sentence becomes `$answer` and `$premise` (see [gr_answer]), and
#'   [is_not_found()] is `FALSE` for it. Excerpts that are merely silent are
#'   still `NOT_IN_DOCUMENT`. See "Checking the premise" below for how each
#'   reader combines what its requests report. The verdict is the model's
#'   reading of the excerpts, not a check harnessr makes, so weigh it as you
#'   would any answer. Off by default because it changes what is sent: the
#'   prompts are longer, so a cache, a recorded replay or a [gr_read_many()]
#'   store made without it does not answer a run with it, and the reverse.
#'   `screen` and `extract`, which answer no question, ignore it.
#' @param verify Check the answer's quotations against the chunks they come
#'   from, and let the check decide what is accepted. `FALSE` (the default)
#'   sends the same requests and accepts answers as before; the `quote_*`
#'   shadow columns are still recorded on checked evidence (see "Verifying
#'   quotations"). With `TRUE`, [gr_read()] runs
#'   [gr_verify_evidence()] on every answer, writes its columns onto
#'   `$evidence`, marks the answer partial when a quotation is not found, and
#'   records a `read.verify` step in the trace. The `iterative` reader also
#'   asks each step that says it can answer for the passages it rests on,
#'   word for word with their chunk numbers, and stops only when every one is
#'   found in the chunk it names; a refused step is told which quotations
#'   were not found, and a run that ends with none accepted answers
#'   `NOT_IN_DOCUMENT`. Its evidence is then the quotations, not every chunk
#'   it was shown. A step that reports the premise false (`premise = TRUE`)
#'   is not asked for quotations and is not refused for lacking them: its
#'   verdict stops the loop as it does without `verify`. See "Verifying
#'   quotations" below.
#' @param accept_near_verbatim Under `verify = TRUE`, whether a quotation the
#'   edit-distance matcher scores `near_verbatim` (see "Verifying quotations")
#'   also lets the `iterative` reader stop. `FALSE` (the default) accepts only
#'   a quotation the decisive check verifies, as before the setting existed.
#'   A near-verbatim quotation that stops the loop is still reported as not
#'   verified in `$evidence`, so the answer is marked partial. `TRUE`
#'   without `verify = TRUE` is refused with a `gr_bad_setting` error. Untested:
#'   nothing has measured whether accepting near-verbatim quotations gives
#'   better answers, and on the package's labelled quotation set 25 of 46
#'   quotations with one content word swapped scored `near_verbatim`.
#' @param max_merge_levels The most merge levels `map_reduce`, `skim` and the
#'   other readers that merge findings run before they give up and return the
#'   findings unmerged and cut, with the answer partial. \[1, 12\], default
#'   6, the cap the code had before it was a setting. Separate from
#'   `max_levels`, which only `hierarchical` reads. Untested.
#' @param restate_tokens Under `restate = "auto"`, the length of the excerpts,
#'   in tokens, above which the question is repeated before them. \[0, 1e6\],
#'   default 1200, the value the code had before it was a setting. Untested:
#'   the code called it "a number, and an arbitrary one".
#' @param bm25_k1,bm25_b The Okapi BM25 parameters of the word-matching scores
#'   that `rerank` prefilters its candidates with and that `retrieve` blends
#'   in when embeddings are lexical. Defaults 1.5 and 0.75, the usual values
#'   given by Robertson and Zaragoza (2009), "The Probabilistic Relevance
#'   Framework: BM25 and Beyond"; not tuned on this package's tasks.
#'   `bm25_k1` \[0, 10\], `bm25_b` \[0, 1\].
#' @param lexical_blend For `retrieve` when the embeddings are lexical (the
#'   offline embedder, or the fallback when the embeddings request fails): the
#'   weight of the cosine score, with `1 - lexical_blend` on the BM25 score.
#'   \[0, 1\], default 0.5, an even blend chosen when the offline path was
#'   written. Untested.
#' @param unskip_k For `preview`: how many of the sections that match the
#'   question's words best (BM25 over each section's text) are read in full
#'   even when the plan skips them. A section that shares no word with the
#'   question is never unskipped. \[0, 100\], default 0, which follows the
#'   plan as before. With `unskip_k = 1`, a plan that skips the only section
#'   holding the question's words is overridden. Whatever its value, each
#'   section the plan skipped is logged in the trace as a `preview.skip` step
#'   with its score and whether it was unskipped, and `notes$unskipped` lists
#'   the sections it overrode. Untested.
#' @param reread_on For `preview`: `"never"` (the default) or `"not_found"`.
#'   Under `"not_found"`, an answer request that came back `NOT_IN_DOCUMENT`
#'   is followed by one more (`preview.reread`) over the sections the plan
#'   did not have read in full (skipped, skimmed, or demoted for lack of
#'   room), fitted whole to one request in document order. The re-read's
#'   answer replaces the not-found when it finds one; `notes$reread` and a
#'   `preview.reread` trace step say what was sent and whether it found an
#'   answer. It costs at most one request. Untested.
#' @param low_score For `rerank`, what happens when every candidate the model
#'   scored is below `rerank_min_score`. `"not_found"` (the default) makes no
#'   answer request and returns `NOT_IN_DOCUMENT`, as before, now with
#'   `notes$retrieval_low_score = TRUE` and a `rerank.low_score` trace step.
#'   `"read_top_k"` sends the 5 best-scored candidates to the answer request
#'   anyway (`notes$read_below_min_score = TRUE`), and marks a
#'   `NOT_IN_DOCUMENT` reply with `notes$retrieval_low_score = TRUE`. It costs
#'   the answer request the default does not make. Untested.
#' @param fusion For `retrieve` and `iterative`: how the embedding ranking and
#'   the BM25 word-matching ranking are combined. Both readers rank through
#'   one function. `"default"` keeps each reader's 0.6.0 ranking: `retrieve`
#'   blends cosine with BM25 by `lexical_blend` when the embeddings are
#'   lexical and uses cosine alone otherwise, and `iterative` uses cosine
#'   alone, so on embeddings that are not lexical the two rank alike.
#'   `"rrf"` is reciprocal rank fusion (Cormack, Clarke and Buettcher 2009,
#'   "Reciprocal Rank Fusion outperforms Condorcet and individual Rank
#'   Learning Methods"): each chunk scores the sum of `1 / (rrf_k + rank)`
#'   over the two rankings, whatever the embeddings, and both readers fuse
#'   alike. It costs no request. Under `"rrf"`, `min_score` applies to the
#'   fused score, which lies between 0 and `2 / (rrf_k + 1)`, about 0.033 at
#'   the default `rrf_k`: a floor chosen for cosine, such as 0.1, passes no
#'   chunk, so `retrieve` reads its best chunk alone and sets
#'   `notes$below_min_score`. With `mmr` below 1, the fused scores are
#'   rescaled to \[0, 1\] over the chunks still eligible before they are
#'   weighed against similarity, which lies between 0 and 1; the order, and
#'   so the plain top-k pick, is unchanged. Untested.
#' @param rrf_k Under `fusion = "rrf"`, the constant `k`. \[1, 1e4\], default
#'   60, the value Cormack, Clarke and Buettcher (2009) use (`cited`); not
#'   tuned here. A larger `k` flattens the difference between top ranks.
#' @param answer_format How the requests that answer the question report
#'   what they found. `"parsed"` (the default) sends the free-text requests
#'   sent before the setting existed and reads `NOT_IN_DOCUMENT` from the
#'   reply. `"schema"` sends them with a JSON schema that asks for `answer`
#'   and `outcome` (`"answered"` or `"not_found"`); a `"not_found"` reply
#'   becomes `NOT_IN_DOCUMENT`, and the model's own words go to
#'   `notes$structured$reply`. A reply that does not parse is read as free
#'   text (`notes$structured$parsed = FALSE`). It covers the answering
#'   request of `stuff`, `retrieve`, `rerank`, `skim`, `hierarchical`,
#'   `preview` and `iterative`'s final answer, and each chunk's request of
#'   `map_reduce`; merges, `refine`'s drafts, `ensemble`'s adjudication and
#'   `iterative`'s steps (already structured) are sent as before. Either way
#'   the answer's `$outcome` is set (see [gr_answer]). Untested: published
#'   comparisons of forced schemas and free text disagree, so the default
#'   stays `"parsed"` until a live comparison settles it.
#' @param premise_verdict Under `premise = TRUE`, how a verdict is reported.
#'   `"sentence"` (the default) is the `FALSE_PREMISE:` sentence in the
#'   reply, as before. `"structured"` sends the answering requests that
#'   `answer_format = "schema"` covers with a JSON schema holding
#'   `premise_status` (`"holds"` or `"contradicted"`) and `quote`, the passage
#'   of the excerpts that states the contrary, word for word. The quote is
#'   checked with the matcher [gr_verify_evidence()] uses, against the
#'   excerpts the request was shown. Where those are passages or summaries a
#'   model wrote (`skim`, `hierarchical` and the skimmed sections of
#'   `preview`), the quote must also be found in the document. The answer
#'   gains `$premise_verdict`
#'   (see [gr_answer]). In `map_reduce` a chunk's flag stands only when its
#'   quote is found in that chunk: a flag with no quote, or one not found, is
#'   dropped with the chunk's reply (`notes$premise_dropped`), and a verified
#'   one goes to the merge and sets `notes$degradation` to
#'   `"premise_flagged"`. `"structured"` without `premise = TRUE` is refused
#'   with a `gr_bad_setting` error. Untested.
#' @param context_policy `NULL` (the default), or an [hr_context_policy()]
#'   (or a named list of its arguments) that decides what a request keeps
#'   when its text does not fit. `NULL` keeps each reader's own cuts, which
#'   keep the start of what they cut. With a policy:
#'   * `refine` fits its state (`draft` or `ledger`) and the new `excerpt`
#'     into the input budget together, cutting the pieces the policy allows
#'     in the order it gives, in place of giving each half the budget;
#'   * the merges of `map_reduce` and `skim` (`findings`), the summaries
#'     `hierarchical` combines (`summaries`), the outline and skimmed
#'     sections of `preview` (`outline`, `excerpts`) and the joined findings
#'     of a merge that gives up are cut with the policy's keep rule for that
#'     piece;
#'   * the readers that pack whole chunks (`stuff`, `retrieve`, `rerank`,
#'     `preview`, `iterative`) write a `"truncate"` step naming the chunks
#'     they left out;
#'   * with `order_merges = TRUE`, the findings a merge combines and the
#'     member answers `ensemble` adjudicates are placed by `context_order`.
#'   The question and the instructions are never cut by any reader. Every
#'   cut is a `"truncate"` step of the trace that names the piece and the
#'   part dropped. Untested.
#' @param refine_state For `refine`: what is carried down the document.
#'   `"draft"` (the default) is the answer, rewritten by each request, as
#'   before. `"ledger"` is a numbered list of findings: each request is shown
#'   it and one excerpt and replies with edits (`ADD: <finding>`,
#'   `REPLACE <n>: <finding>`, `DROP <n>`), which the code applies, so a
#'   finding no edit names is carried forward word for word and a corrected
#'   one is replaced rather than annotated. One more request,
#'   `refine.answer`, answers from the finished list; an empty list is
#'   `NOT_IN_DOCUMENT` with no request. `notes$ledger_items` counts the
#'   findings. Untested; [gr_condensation_check()] builds the test.
#' @param effort_mode `"static"` (the default) sends each request at the
#'   effort `effort` names, as before. `"escalate"` starts every stage at
#'   `effort` (`"low"` when `effort` is unset) and sends the next stage at
#'   `"high"` when a trigger fired in the one before: a cut (a `"truncate"`
#'   step, or a reply stopped at its cap), a reply that is not the JSON asked
#'   for or does not fit its schema, `NOT_IN_DOCUMENT` from every request of
#'   the stage, a quotation `iterative` could not verify, or `ensemble`
#'   members that disagree. Effort changes only at a stage boundary, at most
#'   once a read, and the stage after a raised one goes back to `effort`. The
#'   spec's `effort` is then an [hr_effort_escalate()] policy; each raise is
#'   an `"effort.escalate"` step of the trace, whether it resolved the
#'   trigger an `"effort.resolve"` step, and [hr_effort_log()] lists both.
#'   [hr_effort_check()] compares it with fixed levels. Untested.
#' @param ... Extra fields for custom readers.
#' @return A list of class `gr_read_spec`.
#'
#' @section Checking the premise:
#' With `premise = TRUE`, every request that answers the question carries the
#' rule: the single answering request of `stuff`, `retrieve`, `rerank`,
#' `skim`, `hierarchical` and `preview`; each chunk's request and the merge of
#' `map_reduce`; the draft and every revision of `refine`; each step and the
#' final answer of `iterative`; and the adjudication of `ensemble`. Requests
#' that only pick, score, summarise or copy out passages do not.
#'
#' `map_reduce` treats a chunk that contradicts the premise differently from
#' one that only lacks the answer. The second is dropped, as it always was.
#' The first is passed to the merge as a finding that says the premise is
#' contradicted and what the excerpt states instead, and the merge, told the
#' same rule, weighs it against the chunks that did answer and may itself
#' report the premise false. `notes$premise_chunks` lists the chunks that
#' reported it, whatever the merge decided. `ensemble` does the same with its
#' members (`notes$premise_members`). `refine` carries the verdict in its
#' draft, so a later excerpt can add to the correction or overturn it.
#' `iterative`'s step reports it in a `false_premise` field of its reply,
#' which is in the schema only when the premise is checked, and stops there.
#' A merge or adjudication that failed returns the findings joined, which is
#' no verdict: `$premise` is `NA`, and the notes still name the chunks or
#' members that reported it.
#'
#' The answer records the check: `$premise` is `NA` when nothing contradicted
#' the question, and the correction when something did. [gr_compare()] and
#' [gr_read_many()] add a `premise` column to their summaries, `print()` and
#' [gr_audit_report()] say when the model reported the premise false, and the
#' trace has a `read.premise` step with the outcome.
#'
#' @section Verifying quotations:
#' A reader that puts the chunks it read into `$evidence` has quoted them by
#' construction, so for `stuff`, `retrieve`, `rerank` and the default
#' `iterative` a passing check says only that the chunks were the ones sent.
#' The check means something where a model chose what to quote: `skim`,
#' `extract`, `screen`, and `iterative` under `verify = TRUE`.
#'
#' Two matchers score each quotation. The one that decides `verified` is the
#' check described in [gr_verify_evidence()], unchanged. Beside it the answer
#' carries `quote_status`, `quote_sim`, `quote_coverage`, `quote_edits` and
#' `quote_critical_ok` from an edit-distance matcher that tolerates ligatures,
#' line-break hyphens and OCR letter errors while requiring numbers, units
#' and negations to be identical. It is recorded only, and decides nothing in
#' this release.
#'
#' `verify = TRUE` changes what `iterative` sends (its schema and
#' instructions), so a cache or recording made without it does not answer a
#' run with it. The other readers send exactly what they sent before.
#'
#' @section Out-of-range values:
#' Numeric arguments are clamped into a usable range and the change is warned
#' about, never applied silently: `top_k` \[1, 1e4\], `fan_in` \[2, 32\],
#' `max_levels` \[1, 12\], `max_rounds` \[1, 20\], `rerank_candidates` \[1, 1e4\],
#' `rerank_min_score` \[0, 10\], `preview_tokens` \[100, 1e5\],
#' `delay_between_calls` \[0, 600\],
#' token caps \[16, 1e6\]. The ranges of the settings added later are given
#' with each argument.
#'
#' @section Where the defaults come from:
#' Each setting's default, its tier (`basic` for the few most users change,
#' `advanced` for the rest) and the evidence behind the value. `untested`
#' means no measurement backs the value; `cited` names the published source it
#' comes from. The settings added as declared parameters
#' (`accept_near_verbatim`, `max_merge_levels`, `restate_tokens`, `bm25_k1`,
#' `bm25_b`, `lexical_blend`, and the reading options added after them) are
#' stored in the spec only when they are not their default, so a default spec
#' keeps the store and cache keys it had before they existed.
#'
#' `r schema_sources_md(.gr_read_schema)`
#'
#' @section Reasoning effort:
#' The default models reason before they write a reply, and that reasoning is
#' billed as output and counted against the same output cap as the reply.
#' Nothing sets how much unless `effort` does, so a corpus's hundreds of
#' per-chunk calls reason as long as the one call that drafts its claims.
#'
#' The effort is sent as `reasoning = {"effort": ...}` on the Responses API and
#' as `reasoning_effort` on Chat Completions, and a [gr_mock_client()] or
#' [gr_backend_client()] handler finds it in `params$effort`. It is sent only to
#' a model whose [gr_model_info()] says `reasoning = TRUE`, and left out without
#' a warning for any other, which would refuse the field, as `temperature` is
#' left out for a model that refuses that; register a gateway's reasoning model
#' with [gr_register_model()] to reach it. For the calls it covers it replaces
#' an effort the client's `extra_body` sets. A [gr_ellmer_client()] cannot take
#' it per call, says so once (`gr_effort_unsupported`) and does not record it
#' as sent. A value is passed
#' through as given; one that is not `"none"`, `"minimal"`, `"low"`,
#' `"medium"`, `"high"` or `"xhigh"` is warned about (`gr_effort_unknown`) and
#' sent anyway, since providers add levels.
#'
#' Each request's effort is in its trace step (`params$effort`, and an `effort`
#' column of `as.data.frame(trace)`), and [gr_audit_report()] shows it beside
#' what each stage cost. It is part of the [gr_cache()] key, and, when set, of
#' a recipe's store key in [gr_read_many()], of what [gr_compare()] counts as
#' a different recipe, and of the key a [gr_replay_client()] matches on, so
#' runs at different efforts never share answers. Unset, none of those keys
#' change.
#'
#' The labels are the `stage` column of `as.data.frame(trace)`:
#' `segment.context`, `segment.proposition`; `stuff.answer`; `map.answer`,
#' `reduce`; `refine.draft`, `refine.revise`, `refine.answer`; `skim.extract`,
#' `skim.consolidate`, `skim.answer`; `retrieve.answer`; `rerank.score`,
#' `rerank.answer`; `hier.summarise.L1` (and `L2`, ...), `hier.answer`;
#' `iterative.step`, `iterative.final`; `ensemble.adjudicate`; `preview.plan`,
#' `preview.skim`, `preview.answer`; `screen.decide`; `extract.chunk`,
#' `extract.resolve`; and, for [gr_claims()], [gr_outline()] and
#' [gr_synthesise()], `claims.draw`, `claims.reconcile`, `outline.derive`,
#' `synthesise.section`, `synthesise.batch`, `synthesise.merge` and
#' `synthesise.revise.structure` (`.cut`, `.register`). A merge that takes
#' more than one level labels the levels below its final merge `.level1`,
#' `.level2` and so on, which its own name covers.
#'
#' A starting point, not a default: low for the many mechanical calls and high
#' for the few that judge.
#'
#' ```
#' effort = c("extract.chunk" = "low", "skim.extract" = "low",
#'            "rerank.score" = "low", segment = "low", "map.answer" = "low",
#'            "claims.draw" = "high", "outline.derive" = "high",
#'            "synthesise.section" = "high", "ensemble.adjudicate" = "high")
#' ```
#'
#' Reasoning shares the reply's cap, so a call at `"high"` can spend all of it
#' and come back cut off (`finish_reason = "length"`, warned about where it
#' matters). Give such stages room: `max_answer_tokens` here,
#' `max_section_tokens` in [gr_synthesise()], `max_outline_tokens` in
#' [gr_outline()].
#' Requests to a reasoning model are sent with an output cap of at least 2048
#' tokens whatever the effort, and the cost limits are checked at that cap.
#'
#' @seealso [gr_readers()] for the available readers and their call costs,
#'   [gr_read()], [gr_recipe()]
#' @family reading functions
#' @export
#' @examples
#' gr_read_spec("retrieve", top_k = 8)$top_k
#'
#' # Out-of-range settings are corrected loudly, not quietly.
#' suppressWarnings(gr_read_spec("hierarchical", fan_in = 999)$fan_in)
#'
#' # Reasoning effort by stage: little for the per-chunk calls, more for the
#' # merge. The trace says which request carried which.
#' ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 150))
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' sp <- gr_read_spec("map_reduce", model = "gpt-5.6-luna",
#'                    effort = c(map = "low", reduce = "high"))
#' tr <- gr_trace()
#' invisible(gr_read(ch, "What was revenue?", cl, sp, trace = tr))
#' unique(as.data.frame(tr)[, c("stage", "effort")])
#' # A loaded question, checked against the document. The mock plays a model
#' # that finds the excerpts contradict it.
#' cl <- gr_mock_client(function(m, p)
#'   "FALSE_PREMISE: Revenue rose 12% in 2023, to 45.2 million.")
#' ch <- gr_segment(gr_example(), list(method = "sentence", max_tokens = 400))
#' ans <- gr_read(ch, "Why did revenue fall in 2023?", cl,
#'                gr_read_spec("stuff", premise = TRUE))
#' ans$premise
#' is_not_found(ans$answer)
gr_read_spec <- function(reader = "map_reduce", model = NULL, temperature = NULL,
                         max_answer_tokens = 1500L, max_chunk_tokens = 700L,
                         max_summary_tokens = 500L, top_k = 6L, min_score = -Inf,
                         mmr = 1, context_order = c("relevance", "document", "edges"),
                         rerank_candidates = 20L, rerank_min_score = 4,
                         fan_in = 5L, max_levels = 5L, max_rounds = 4L,
                         preview_tokens = 1200L, restate = c("auto", "always", "never", "window"),
                         members = NULL, cite = FALSE,
                         skim_model = NULL, summary_model = NULL,
                         parallel = NULL, delay_between_calls = 0,
                         on_overflow = c("warn", "error"), effort = NULL, premise = FALSE,
                         verify = FALSE, accept_near_verbatim = FALSE, max_merge_levels = 6L,
                         restate_tokens = 1200L, bm25_k1 = 1.5, bm25_b = 0.75,
                         lexical_blend = 0.5, unskip_k = 0L,
                         reread_on = c("never", "not_found"),
                         low_score = c("not_found", "read_top_k"),
                         fusion = c("default", "rrf"), rrf_k = 60,
                         answer_format = c("parsed", "schema"),
                         premise_verdict = c("sentence", "structured"),
                         context_policy = NULL, refine_state = c("draft", "ledger"),
                         effort_mode = c("static", "escalate"), ...) {
  warn_near_miss(list(...), names(formals(gr_read_spec)), "read")
  # Every argument but `...` is checked and resolved by the schema
  # (.gr_read_schema): ranges clamped with a warning, a missing number taken
  # from its default, the choices matched.
  p <- hr_validate(.gr_read_schema, mget(names(.gr_read_schema), environment()))
  # Without verify the setting does nothing, yet it would still move the
  # spec's hash, its store keys and what gr_compare() reports as changed.
  if (isTRUE(p$accept_near_verbatim) && !isTRUE(p$verify)) {
    gr_abort(paste0("`accept_near_verbatim = TRUE` needs `verify = TRUE`: without `verify` ",
                    "no quotation is checked, so the setting has no effect."),
             class = "gr_bad_setting")
  }
  # Without premise the verdict is never asked for, yet the setting would
  # still move the spec's hash and keys.
  if (identical(p$premise_verdict, "structured") && !isTRUE(p$premise)) {
    gr_abort(paste0("`premise_verdict = \"structured\"` needs `premise = TRUE`: without it no ",
                    "verdict is asked for, so the setting has no effect."),
             class = "gr_bad_setting")
  }
  if (identical(p$restate, "window")) {
    gr_warn(paste0("restate = \"window\" repeats the question once the excerpts pass the ",
                   "model's effective window. No model's effective window is measured yet, so ",
                   "the question is repeated before excerpts longer than 50,000 tokens."),
            class = "gr_window_unmeasured")
  }
  spec <- structure(c(list(
    reader = p$reader,
    model = p$model,
    temperature = p$temperature,
    max_answer_tokens = p$max_answer_tokens,
    max_chunk_tokens = p$max_chunk_tokens,
    max_summary_tokens = p$max_summary_tokens,
    top_k = p$top_k,
    min_score = p$min_score,
    mmr = p$mmr,
    context_order = p$context_order,
    restate = p$restate,
    rerank_candidates = p$rerank_candidates,
    rerank_min_score = p$rerank_min_score,
    fan_in = p$fan_in,
    max_levels = p$max_levels,
    max_rounds = p$max_rounds,
    preview_tokens = p$preview_tokens,
    members = p$members,
    cite = p$cite,
    skim_model = p$skim_model,
    summary_model = p$summary_model,
    parallel = p$parallel,
    delay_between_calls = p$delay_between_calls,
    on_overflow = p$on_overflow
  ),
  # Only when set. A spec is hashed whole into a corpus store's key and into
  # gr_compare()'s check that two recipes differ, and an `effort = NULL` entry
  # would be a new element in every spec, so every store made before the
  # setting existed would have missed and every document been paid for again.
  # Under effort_mode = "escalate" it is the policy that raises it.
  if (identical(p$effort_mode, "escalate")) list(effort = read_escalation(p$effort))
  else if (!is.null(p$effort)) list(effort = p$effort),
  # In the spec only when it is TRUE. The whole spec is hashed into the keys a
  # corpus store files answers under (corpus_key()) and gr_compare() tells
  # recipes apart by, so a field present in every spec, FALSE or not, would
  # have moved every store entry ever written to a key no run asks for.
  if (isTRUE(p$premise)) list(premise = TRUE),
  # Only when TRUE, for the same reason as `premise`.
  if (isTRUE(p$verify)) list(verify = TRUE),
  # Only when not the default, for the same reason.
  nondefault_params(p, .gr_read_schema, .gr_read_late_params),
  list(...)), class = "gr_read_spec")
  registry_get("readers", spec$reader, "readers", state = gr_state)   # fail fast on a typo
  # Asked of a reader that answers no question, the check would silently do
  # nothing; say so once, where the spec is made.
  if (isTRUE(p$premise) && as_chr1(p$reader, "") %in% c("screen", "extract")) {
    gr_warn(sprintf(paste0("premise = TRUE has no effect on '%s', which answers no question. ",
                           "It applies to the readers that do; see gr_readers()."), reader),
            class = "gr_read_premise_ignored")
  }
  spec
}

#' @noRd
as_read_spec <- function(spec) {
  if (inherits(spec, "gr_read_spec")) return(spec)
  if (is.null(spec)) return(gr_read_spec())
  if (is.character(spec) && length(spec) == 1L) return(gr_read_spec(reader = spec))
  if (is.list(spec)) return(do.call(gr_read_spec, spec))
  gr_abort("`read` must be a gr_read_spec, a reader name, or a named list.")
}

#' The schema of gr_read_spec(): every argument but `...`, in the order the
#' constructor resolved them before the schema existed, so a run of warnings
#' comes out in the same order. Ranges and defaults are the ones documented
#' under "Out-of-range values"; the defaults must match the formals, which a
#' test checks.
#' @noRd
.gr_read_schema <- hr_schema(
  hr_param("on_overflow", "enum", choices = c("warn", "error"),
           help = "For stuff: truncate with a warning, or stop, when the document does not fit.",
           tier = "advanced",
           evidence = ev_untested(paste0("Chosen so that a document too long for one request ",
                                         "still gets an answer that says what was cut."))),
  hr_param("context_order", "enum", choices = c("relevance", "document", "edges"),
           help = "Where the selected chunks sit in the prompt.", tier = "advanced",
           evidence = ev_untested(paste0("The order the readers used before the setting ",
                                         "existed; the alternatives were added to be compared, ",
                                         "and no comparison is recorded."))),
  hr_param("restate", "enum", choices = c("auto", "always", "never", "window"),
           help = "Whether to repeat the question before the excerpts as well as after.",
           tier = "advanced",
           evidence = ev_untested(paste0("A setting so that gr_compare() can measure it on a ",
                                         "corpus; no measurement is recorded."))),
  # Refused rather than read with isTRUE(): premise = "yes" or NA would turn a
  # check the caller asked for into none, and nothing in the answer would say.
  hr_param("premise", "boolean", default = FALSE, strict = TRUE, tier = "advanced",
           help = "Check the question's assumptions against the document.",
           evidence = ev_untested(paste0("Off, so a run sends the requests it sent before ",
                                         "the check existed."))),
  hr_param("verify", "boolean", default = FALSE, strict = TRUE,
           help = "Check the answer's quotations against the chunks they cite.",
           evidence = ev_untested(paste0("Off, so a run sends the requests and accepts the ",
                                         "answers it did before the check existed."))),
  hr_param("effort", "named_map", default = NULL, cost_class = "per_call_constant",
           help = "Reasoning effort, one level or a map named by call stem.",
           tier = "advanced",
           evidence = ev_untested(paste0("Unset: no effort is sent, and the provider's own ",
                                         "default applies.")),
           resolve = function(x, p, params) check_effort_stems(check_effort(x),
                                                               declared_call_stems())),
  hr_param("reader", "module_ref", default = "map_reduce", kind = "reader",
           help = "The reading strategy.", cost_class = "per_unit", resolve = param_as_given,
           evidence = ev_untested(paste0("The reader that sends every chunk, chosen because it ",
                                         "reads the whole document at any length; no ",
                                         "comparison of readers is recorded."))),
  # NULL is kept, not filled from gr_options("model"): filled here, every
  # reader passed a model to gr_call(), which only falls back to the client's
  # when given none, so a client built for another model was never the one
  # asked, budgeted for or billed. gr_read() fills it from the client.
  hr_param("model", "string", default = NULL, help = "Chat model id; NULL means the client's.",
           evidence = ev_untested("Not a tuned value: NULL takes the client's model."),
           resolve = function(x, p, params) if (is.null(x)) NULL else as_chr1(x)),
  hr_param("temperature", "number", default = NULL, help = "Sampling temperature.",
           tier = "advanced",
           evidence = ev_untested(paste0("Not a tuned value: NULL takes ",
                                         "gr_options(\"temperature\"), which sends none.")),
           resolve = function(x, p, params) x %||% gr_options("temperature")),
  hr_param("max_answer_tokens", "integer", default = 1500L, min = 16, max = 1e6,
           help = "Output cap for final answers and merges.", tier = "advanced",
           evidence = ev_untested("Set as a generous cap for an answer; not measured.")),
  hr_param("max_chunk_tokens", "integer", default = 700L, min = 16, max = 1e6,
           help = "Output cap for per-chunk calls.", tier = "advanced",
           evidence = ev_untested("Set as a cap for one chunk's finding; not measured.")),
  hr_param("max_summary_tokens", "integer", default = 500L, min = 16, max = 1e6,
           help = "Output cap for summarisation calls.", tier = "advanced",
           evidence = ev_untested("Set as a cap for one summary; not measured.")),
  hr_param("top_k", "integer", default = 6L, min = 1, max = 1e4,
           help = "Chunks to use, for retrieve, rerank and iterative.",
           evidence = ev_untested("A common starting value for retrieval; not tuned here.")),
  # -Inf is the documented "no floor", so a value that cannot be compared has
  # to be refused rather than silently becoming one: a relevance floor that is
  # not applied is the same failure as a cost ceiling that is not enforced.
  hr_param("min_score", "number", default = -Inf,
           help = "For retrieve: chunks scoring below this are dropped.", tier = "advanced",
           evidence = ev_untested("Not a tuned value: -Inf applies no floor.")),
  # NA falls back to the default, not to the bottom of the range, which for
  # this setting is pure diversity and picks irrelevant chunks.
  hr_param("mmr", "number", default = 1, min = 0, max = 1, tier = "advanced",
           help = "Relevance against diversity when selecting chunks; 1 is plain top-k.",
           evidence = ev_untested(paste0("1 is plain top-k, the selection used before the ",
                                         "setting existed."))),
  hr_param("rerank_candidates", "integer", default = 20L, min = 1, max = 1e4,
           help = "For rerank: how many chunks to score.", cost_class = "per_unit",
           tier = "advanced", evidence = ev_untested("Set when rerank was written; not tuned.")),
  hr_param("rerank_min_score", "number", default = 4, min = 0, max = 10,
           help = "For rerank: the score below which a chunk is discarded.", tier = "advanced",
           evidence = ev_untested("Set when rerank was written; not tuned.")),
  hr_param("fan_in", "integer", default = 5L, min = 2, max = 32,
           help = "For hierarchical: summaries combined per call.", tier = "advanced",
           evidence = ev_untested("Set when hierarchical was written; not tuned.")),
  hr_param("max_levels", "integer", default = 5L, min = 1, max = 12,
           help = "For hierarchical: the recursion depth cap.", tier = "advanced",
           evidence = ev_untested("Set when hierarchical was written; not tuned.")),
  hr_param("max_rounds", "integer", default = 4L, min = 1, max = 20,
           help = "For iterative: retrieve-assess cycles.", cost_class = "per_round",
           tier = "advanced", evidence = ev_untested("Set when iterative was written; not tuned.")),
  hr_param("preview_tokens", "integer", default = 1200L, min = 100, max = 1e5,
           help = "For preview: the cap on the outline the planner sees.", tier = "advanced",
           evidence = ev_untested("Set when preview was written; not tuned.")),
  hr_param("members", "string_vector", default = NULL, cost_class = "per_unit",
           help = "For ensemble: the reader names to combine.", resolve = param_as_given,
           tier = "advanced",
           evidence = ev_untested(paste0("NULL takes ensemble's own pair, retrieve and ",
                                         "map_reduce; not compared with other pairs."))),
  hr_param("cite", "boolean", default = FALSE, strict = FALSE,
           help = "Ask for chunk-level citations in the answer.",
           evidence = ev_untested(paste0("Off, so the answer prompt is the one used before ",
                                         "the setting existed."))),
  hr_param("skim_model", "string", default = NULL, tier = "advanced",
           help = "A cheaper model for skim's extraction and rerank's scoring.",
           evidence = ev_untested("Not a tuned value: NULL uses `model`."),
           resolve = param_as_given),
  hr_param("summary_model", "string", default = NULL, tier = "advanced",
           help = "A cheaper model for hierarchical's summaries.", resolve = param_as_given,
           evidence = ev_untested("Not a tuned value: NULL uses `model`.")),
  hr_param("parallel", "boolean", default = NULL, affects_output = FALSE, tier = "advanced",
           help = "Run per-chunk calls in parallel.",
           evidence = ev_untested(paste0("Not a tuned value: NULL follows ",
                                         "gr_options(\"parallel\"). It does not change output.")),
           resolve = function(x, p, params) x %||% gr_options("parallel")),
  hr_param("delay_between_calls", "number", default = 0, min = 0, max = 600,
           affects_output = FALSE, tier = "advanced",
           help = "Seconds to sleep between sequential calls.",
           evidence = ev_untested("No pause. It does not change output.")),
  # The settings below were constants in the code until they were declared
  # here. Each keeps the constant's value as its default, and gr_read_spec()
  # stores it only when it is not the default (nondefault_params()).
  hr_param("accept_near_verbatim", "boolean", default = FALSE, strict = TRUE,
           tier = "advanced", depends_on = "verify = TRUE",
           help = "Under verify, let a near-verbatim quotation stop the iterative reader.",
           evidence = ev_untested(paste0("Off, as the code behaved before the setting existed. ",
                                         "Not measured as a stopping rule; on the labelled ",
                                         "quotation set, 25 of 46 quotations with one content ",
                                         "word swapped score near_verbatim (NEWS, 0.6.0.9000)."))),
  hr_param("max_merge_levels", "integer", default = 6L, min = 1, max = 12, tier = "advanced",
           cost_class = "per_round",
           help = "Most merge levels a reader runs before it returns its findings unmerged.",
           evidence = ev_untested("The cap the merge code had as a constant; not tuned.")),
  hr_param("restate_tokens", "integer", default = 1200L, min = 0, max = 1e6,
           tier = "advanced", depends_on = "restate = \"auto\"",
           help = "Under restate = 'auto', the body length above which the question is repeated.",
           evidence = ev_untested(paste0("An arbitrary number, as its comment said when it was ",
                                         "a constant; not measured."))),
  hr_param("bm25_k1", "number", default = 1.5, min = 0, max = 10, tier = "advanced",
           help = "BM25 term-frequency saturation, for rerank's prefilter and lexical retrieve.",
           evidence = ev_cited(paste0("Robertson and Zaragoza (2009), \"The Probabilistic ",
                                      "Relevance Framework: BM25 and Beyond\", give k1 between ",
                                      "1.2 and 2.0 as usual; not tuned here."))),
  hr_param("bm25_b", "number", default = 0.75, min = 0, max = 1, tier = "advanced",
           help = "BM25 length normalisation, for rerank's prefilter and lexical retrieve.",
           evidence = ev_cited(paste0("Robertson and Zaragoza (2009), \"The Probabilistic ",
                                      "Relevance Framework: BM25 and Beyond\", give b = 0.75 ",
                                      "as usual; not tuned here."))),
  hr_param("lexical_blend", "number", default = 0.5, min = 0, max = 1, tier = "advanced",
           help = "For retrieve on lexical embeddings: the weight of cosine against BM25.",
           evidence = ev_untested("An even blend, set when the offline path was written.")),
  hr_param("unskip_k", "integer", default = 0L, min = 0, max = 100, tier = "advanced",
           help = paste0("For preview: the sections that best match the question's words, ",
                         "read even when the plan skips them."),
           evidence = ev_untested(paste0("Off (0), so the plan is followed as it was before ",
                                         "the setting existed. Not measured."))),
  hr_param("reread_on", "enum", choices = c("never", "not_found"), tier = "advanced",
           cost_class = "per_call_constant",
           help = paste0("For preview: under \"not_found\", an answer that found nothing reads ",
                         "the sections not read in full in one more request."),
           evidence = ev_untested(paste0("\"never\", so a run makes the requests it made ",
                                         "before the setting existed. Not measured."))),
  hr_param("low_score", "enum", choices = c("not_found", "read_top_k"), tier = "advanced",
           depends_on = "reader = \"rerank\"",
           help = paste0("For rerank: when every candidate scores below rerank_min_score, ",
                         "answer not found, or send the 5 best to the answer request."),
           evidence = ev_untested(paste0("\"not_found\", the behaviour before the setting ",
                                         "existed: no answer request. Not measured."))),
  hr_param("fusion", "enum", choices = c("default", "rrf"), tier = "advanced",
           help = paste0("For retrieve and iterative: how embedding similarity and BM25 ",
                         "are combined into one ranking."),
           evidence = ev_untested(paste0("\"default\" keeps the 0.6.0 ranking of each reader. ",
                                         "Reciprocal rank fusion is not compared with it ",
                                         "here."))),
  hr_param("rrf_k", "number", default = 60, min = 1, max = 1e4, tier = "advanced",
           depends_on = "fusion = \"rrf\"",
           help = "Under fusion = 'rrf': the constant k in 1 / (k + rank).",
           evidence = ev_cited(paste0("Cormack, Clarke and Buettcher (2009), \"Reciprocal ",
                                      "Rank Fusion outperforms Condorcet and individual Rank ",
                                      "Learning Methods\", SIGIR, use k = 60; not tuned here."))),
  hr_param("answer_format", "enum", choices = c("parsed", "schema"), tier = "advanced",
           help = paste0("How answering requests report their outcome: parsed from free text, ",
                         "or in a JSON schema the request forces."),
           evidence = ev_untested(paste0("\"parsed\", the requests sent before the setting ",
                                         "existed. Published comparisons of forced schemas and ",
                                         "free text disagree; owner decision DEC-05 keeps the ",
                                         "question open until a live comparison."))),
  hr_param("premise_verdict", "enum", choices = c("sentence", "structured"), tier = "advanced",
           depends_on = "premise = TRUE",
           help = paste0("Under premise = TRUE: the verdict as a sentence in the reply, or as ",
                         "schema fields with a quote that is checked against the excerpts."),
           evidence = ev_untested(paste0("\"sentence\", the requests premise = TRUE sent ",
                                         "before the setting existed. Not measured."))),
  hr_param("context_policy", "named_map", default = NULL, tier = "advanced",
           help = paste0("Which pieces of a request are never cut, which are cut first, and ",
                         "which part of a cut piece is kept."),
           evidence = ev_untested(paste0("NULL: each reader cuts as it did before the setting ",
                                         "existed, keeping the start of what it cuts. No ",
                                         "policy has been compared with it.")),
           resolve = function(x, p, params) check_context_policy(x)),
  hr_param("refine_state", "enum", choices = c("draft", "ledger"), tier = "advanced",
           cost_class = "per_call_constant", depends_on = "reader = \"refine\"",
           help = paste0("For refine: carry a rewritten draft down the document, or a numbered ",
                         "list of findings that each request adds to, replaces or drops from."),
           evidence = ev_untested(paste0("\"draft\", the state refine carried before the ",
                                         "setting existed. Not compared with \"ledger\"; ",
                                         "gr_condensation_check() builds the test."))),
  hr_param("effort_mode", "enum", choices = c("static", "escalate"), tier = "advanced",
           cost_class = "per_call_constant",
           help = paste0("Under \"escalate\", every stage starts at `effort` (\"low\" when ",
                         "unset), and the next stage is sent at \"high\" when a trigger fires."),
           evidence = ev_untested(paste0("\"static\": the effort `effort` names, as before the ",
                                         "setting existed. Not compared with \"escalate\"; ",
                                         "hr_effort_check() makes the comparison.")))
)

#' The escalation policy of effort_mode = "escalate": every stage at `effort`
#' ("low" when unset), the next stage at "high" when a trigger fires, once a
#' read, and NOT_IN_DOCUMENT from every request of a stage counted as a
#' trigger.
#' @noRd
read_escalation <- function(effort) {
  if (inherits(effort, "hr_effort_escalate")) return(effort)
  hr_effort_escalate(base = effort %||% "low", to = "high",
                     replies = c(not_in_document = .NOT_FOUND))
}

#' A read spec's context policy: NULL, an hr_context_policy(), or a list of
#' its arguments.
#' @noRd
check_context_policy <- function(x) {
  if (is.null(x) || inherits(x, "hr_context_policy")) return(x)
  if (is.list(x) && (!length(x) || all(nzchar(names(x) %||% "")))) {
    return(do.call(hr_context_policy, x))
  }
  gr_abort(paste0("`context_policy` must be NULL, an hr_context_policy(), or a named list of ",
                  "its arguments."), class = "gr_bad_setting")
}

#' The read settings that were constants in the code until they were declared
#' in the schema. gr_read_spec() stores each only when it is not its default.
#' @noRd
.gr_read_late_params <- c("accept_near_verbatim", "max_merge_levels", "restate_tokens",
                          "bm25_k1", "bm25_b", "lexical_blend", "unskip_k", "reread_on",
                          "low_score", "fusion", "rrf_k", "answer_format",
                          "premise_verdict", "context_policy", "refine_state", "effort_mode")

#' The settings among `names` whose resolved value is not the schema's default,
#' as a list to add to a spec. A spec is hashed whole into the corpus store and
#' document cache keys, so a field present in every spec, at its default or
#' not, would move every key ever written; one present only when changed
#' keeps the keys of a default spec.
#' @noRd
nondefault_params <- function(p, schema, names) {
  out <- list()
  for (nm in names) {
    v <- p[[nm]]
    # An enum's default is its first choice, as hr_validate() resolves it.
    d <- if (identical(schema[[nm]]$type, "enum")) schema[[nm]]$choices[1]
         else schema[[nm]]$default
    if (is.null(v) || isTRUE(all.equal(v, d, check.attributes = FALSE))) next
    out[[nm]] <- v
  }
  out
}

#' The settings of a read spec that differ from its defaults, for the trace
#' and gr_compare(). Defaults come from gr_read_spec() itself, so a model or
#' `parallel` that merely follows gr_options() is not reported as a setting.
#' @noRd
read_settings <- function(spec) {
  spec_settings(spec, suppressWarnings(gr_read_spec(reader = spec$reader)), drop = "reader")
}
