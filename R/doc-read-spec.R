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
#'   `"1 + embeddings"`), shown by [gr_readers()].
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
#'     own; a call without it is sent no effort.}
#'   \item{`trace`}{Pass it to every [gr_call()] so your calls are counted and
#'     priced, and check `harnessr:::trace_can_call(trace)` before each one so
#'     the run's call and spending limits are respected.}
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
#' ch <- gr_segment(readgpt_example(), list(method = "sentence", max_tokens = 120))
#' gr_read(ch, "What was revenue?", gr_mock_client(function(m, p) "45.2 million"),
#'         "longest")$answer
gr_register_reader <- function(name, fn, signature, description = "", cost_calls = "") {
  if (!is.function(fn)) gr_abort("`fn` must be a function of (chunks, question, client, spec, trace).")
  # answer_document(recipe = "auto") would never reach a reader of that name.
  if (identical(as_chr1(name, ""), "auto")) {
    gr_abort(paste0("'auto' is reserved: answer_document() uses it to choose a recipe. ",
                    "Register the reader under another name."), class = "gr_reserved_name")
  }
  if (!grepl("^[^|]+\\|[^|]+\\|[^|]+$", as_chr1(signature))) {
    gr_abort("`signature` must have the form 'select|calls|state', e.g. 'topk|1|none'.")
  }
  registry_set("readers", name, list(name = name, fn = fn, signature = signature,
                                     description = description, cost_calls = cost_calls), state = gr_state)
}

#' List registered reading strategies
#'
#' The catalogue for axis 3, and the cheapest way to choose one: the `signature`
#' column tells you how a reader traverses the chunks and `cost_calls` tells you
#' what that costs, both before you spend anything.
#'
#' @return A data frame with one row per registered reader: `name`, `signature`
#'   (see [gr_reader_signature()]), `cost_calls` (a formula in N, the number
#'   of chunks, not a number) and `description`.
#' @seealso [gr_read()], [gr_reader_signature()], [gr_register_reader()],
#'   [gr_read_spec()], [gr_compare()] to run several and compare
#' @family reading functions
#' @export
#' @examples
#' # Grouped by how they select chunks, which is the real taxonomy:
#' # `all|...` readers see every chunk, `topk|...` readers see a selection.
#' r <- gr_readers()
#' r[order(r$signature), c("name", "signature", "cost_calls")]
gr_readers <- function() registry_table("readers", c("signature", "cost_calls", "description"), state = gr_state)

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
#'   lexical vectors: the score is then a blend of cosine and BM25.
#' @param mmr Diversity of selection, for `retrieve` and `iterative`. `1` (the
#'   default) is plain top-k. Below 1, chunks are picked greedily by
#'   `mmr * relevance - (1 - mmr) * similarity to what is already picked`, so
#'   three chunks saying the same thing do not all get in and pay for each other.
#'   Costs nothing: the vectors are already computed. `0.7` is a reasonable
#'   place to start; `0` selects for novelty alone and will happily pick
#'   irrelevant chunks because they are different.
#' @param restate Whether to repeat the question before the excerpts as well as
#'   after them: `"auto"` when the body is long enough to bury the first ask,
#'   `"always"`, or `"never"`. A setting rather than a rule, because whether it
#'   helps is a question about your corpus and your model. Point [gr_compare()]
#'   at two recipes differing only in this and find out.
#' @param context_order Where the selected chunks sit in the prompt.
#'   `"relevance"` (default) is most relevant first; `"document"` restores the
#'   order they appear in the document, which reads better when chunks are
#'   consecutive; `"edges"` puts the strongest first and second-strongest last,
#'   burying the weakest in the middle, because transformers attend measurably
#'   better to the beginning and end of a long context than to its middle.
#'   Selection is unaffected. This decides only placement, and it applies to
#'   `retrieve` and `rerank`, the two readers that put several ranked chunks in
#'   one prompt.
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
#'   sent no effort. It reaches the segmenters that call a model too, when the
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
#' @section Out-of-range values:
#' Numeric arguments are clamped into a usable range and the change is warned
#' about, never applied silently: `top_k` \[1, 1e4\], `fan_in` \[2, 32\],
#' `max_levels` \[1, 12\], `max_rounds` \[1, 20\], `rerank_candidates` \[1, 1e4\],
#' `rerank_min_score` \[0, 10\], `preview_tokens` \[100, 1e5\],
#' `delay_between_calls` \[0, 600\],
#' token caps \[16, 1e6\].
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
#' `reduce`; `refine.draft`, `refine.revise`; `skim.extract`,
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
#' ch <- gr_segment(readgpt_example(), list(method = "paragraph", max_tokens = 150))
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
#' ch <- gr_segment(readgpt_example(), list(method = "sentence", max_tokens = 400))
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
                         preview_tokens = 1200L, restate = c("auto", "always", "never"),
                         members = NULL, cite = FALSE,
                         skim_model = NULL, summary_model = NULL,
                         parallel = NULL, delay_between_calls = 0,
                         on_overflow = c("warn", "error"), effort = NULL, premise = FALSE,
                         ...) {
  on_overflow <- match.arg(on_overflow)
  context_order <- match.arg(context_order)
  restate <- match.arg(restate)
  # Refused rather than read with isTRUE(): premise = "yes" or NA would turn a
  # check the caller asked for into none, and nothing in the answer would say.
  if (!is.logical(premise) || length(premise) != 1L || is.na(premise)) {
    gr_abort("`premise` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  warn_near_miss(list(...), names(formals(gr_read_spec)), "read")
  effort <- check_effort(effort)
  spec <- structure(c(list(
    reader = reader,
    # NULL is kept, not filled from gr_options("model"): filled here, every
    # reader passed a model to gr_call(), which only falls back to the client's
    # when given none, so a client built for another model was never the one
    # asked, budgeted for or billed. gr_read() fills it from the client.
    model = if (is.null(model)) NULL else as_chr1(model),
    temperature = temperature %||% gr_options("temperature"),
    max_answer_tokens = clamp_warn(na_default(max_answer_tokens, 1500L, "max_answer_tokens"), 16, 1e6, "max_answer_tokens"),
    max_chunk_tokens = clamp_warn(na_default(max_chunk_tokens, 700L, "max_chunk_tokens"), 16, 1e6, "max_chunk_tokens"),
    max_summary_tokens = clamp_warn(na_default(max_summary_tokens, 500L, "max_summary_tokens"), 16, 1e6, "max_summary_tokens"),
    top_k = clamp_warn(na_default(top_k, 6L, "top_k"), 1, 1e4, "top_k"),
    # -Inf is the documented "no floor", so a value that cannot be compared has
    # to be refused rather than silently becoming one: a relevance floor that is
    # not applied is the same failure as a cost ceiling that is not enforced.
    min_score = if (identical(min_score, -Inf)) -Inf else
      na_default(min_score, -Inf, "min_score"),
    # NA falls back to the DEFAULT, not to the bottom of the range. clamp_warn()
    # maps NA to `lo`, which for this setting is 0 -- pure diversity, documented
    # as "will happily pick irrelevant chunks because they are different". A
    # missing value must not select the most destructive end of a scale.
    mmr = clamp_warn(na_default(mmr, 1, "mmr"), 0, 1, "mmr", integer = FALSE),
    context_order = context_order,
    restate = restate,
    rerank_candidates = clamp_warn(na_default(rerank_candidates, 20L, "rerank_candidates"), 1, 1e4, "rerank_candidates"),
    rerank_min_score = clamp_warn(na_default(rerank_min_score, 4, "rerank_min_score"), 0, 10, "rerank_min_score", integer = FALSE),
    fan_in = clamp_warn(na_default(fan_in, 5L, "fan_in"), 2, 32, "fan_in"),
    max_levels = clamp_warn(na_default(max_levels, 5L, "max_levels"), 1, 12, "max_levels"),
    max_rounds = clamp_warn(na_default(max_rounds, 4L, "max_rounds"), 1, 20, "max_rounds"),
    preview_tokens = clamp_warn(na_default(preview_tokens, 1200L, "preview_tokens"), 100, 1e5,
                               "preview_tokens"),
    members = members,
    cite = isTRUE(cite),
    skim_model = skim_model,
    summary_model = summary_model,
    parallel = parallel %||% gr_options("parallel"),
    delay_between_calls = clamp_warn(na_default(delay_between_calls, 0, "delay_between_calls"),
                                     0, 600, "delay_between_calls", integer = FALSE),
    on_overflow = on_overflow
  ),
  # Only when set. A spec is hashed whole into a corpus store's key and into
  # gr_compare()'s check that two recipes differ, and an `effort = NULL` entry
  # would be a new element in every spec, so every store made before the
  # setting existed would have missed and every document been paid for again.
  if (!is.null(effort)) list(effort = effort),
  # In the spec only when it is TRUE. The whole spec is hashed into the keys a
  # corpus store files answers under (corpus_key()) and gr_compare() tells
  # recipes apart by, so a field present in every spec, FALSE or not, would
  # have moved every store entry ever written to a key no run asks for.
  if (isTRUE(premise)) list(premise = TRUE),
  list(...)), class = "gr_read_spec")
  registry_get("readers", spec$reader, "readers", state = gr_state)   # fail fast on a typo
  # Asked of a reader that answers no question, the check would silently do
  # nothing; say so once, where the spec is made.
  if (isTRUE(premise) && as_chr1(reader, "") %in% c("screen", "extract")) {
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
