# doc-modules.R: the document layer's state, the kinds of module it brings,
# and the built-in segmenters and readers, registered when the package loads.

# The document layer's registries and its document cache. The core keeps its
# own state in hr_state and never reads this one; what it needs from here it
# gets through the hooks registered by register_doc_layer().
gr_state <- new.env(parent = emptyenv())

gr_state$extractors     <- list()

gr_state$cleaners       <- list()

gr_state$segmenters     <- list()

gr_state$readers        <- list()

gr_state$embedders      <- list()

gr_state$protocols      <- list()

gr_state$doc_cache      <- new.env(parent = emptyenv())

#' The registries a parallel worker needs to see the same modules as the
#' process that sent it the batch. Not the document cache, which holds whole
#' documents and would cost more to send than the work.
#' @noRd
.gr_module_slots <- c("extractors", "cleaners", "segmenters", "readers", "embedders",
                      "protocols")

#' Tell the core what the document layer brings: its five kinds of module, and
#' how a parallel worker gets this layer's registries. Run by .onLoad() before
#' the built-in modules are registered.
#' @noRd
register_doc_layer <- function() {
  hr_register_kind("extractor", registry = "extractors")
  hr_register_kind("cleaner", registry = "cleaners")
  hr_register_kind("segmenter", registry = "segmenters")
  hr_register_kind("reader", registry = "readers")
  hr_register_kind("embedder", registry = "embedders")
  hr_register_worker_state("doc", doc_worker_snapshot, doc_worker_restore)
  invisible(NULL)
}

#' This layer's registries, as a worker needs them.
#' @noRd
doc_worker_snapshot <- function() {
  mget(.gr_module_slots, envir = gr_state, ifnotfound = list(NULL))
}

#' Put registries taken by doc_worker_snapshot() in place, in a worker. A
#' registry that was not there is left as the worker's own load made it.
#' @noRd
doc_worker_restore <- function(values) {
  for (nm in names(values)) if (!is.null(values[[nm]])) assign(nm, values[[nm]], envir = gr_state)
  invisible(NULL)
}

# Readers: AXIS 3, the reading strategies.
#
# Each reader below has a distinct TRAVERSAL SIGNATURE, declared in its
# registration. The signature is `select|calls|state`; the values in use are
# exactly those in `gr_readers()$signature`, and nothing else is accepted:
#
#   select : all | topk | ensemble          -- which chunks reach the model
#   calls  : 1 | N | N+1 | N+logN | m+1 | N+tree+1 | rounds*2 | sum+1
#   state  : none | forward | tree          -- how information flows between calls
#
# Run `gr_readers()` for the authoritative table; the enumeration above is a
# summary of it and the registry is what is checked.
#
# Two readers that would resolve to the same signature on the same inputs are
# the same methodology wearing two names -- exactly the "Chunked" vs "Semantic"
# situation in the previous release. `gr_compare()` checks this and refuses to
# bill you twice for it.

# Segmenters: AXIS 2, the segmentation strategies themselves.
#
# Each segmenter is a genuinely different *hypothesis about where meaning
# breaks*:
#
# PROVENANCE: `paragraph`, `sentence`, `structural`, `page`, `semantic` and
# `contextual` carry each chunk's page/section/block through to `gr_chunks`, so
# citations can point back at the source. `fixed`, `recursive` and `proposition`
# do not: the first two work on the concatenated document text by design, and
# `proposition` REWRITES the text, so no chunk corresponds to any source block.
# That is the cost of ignoring (or rewriting) structure, and it is reported as
# NA rather than guessed at. What `proposition` and `contextual` do keep is the
# document text behind each chunk, in `source_text`, because their chunk text
# holds words that are not the document's -- a model's rewrite, a context line
# -- and a quote has to be checked against the document.
#
#   fixed       -- meaning is uniform; cut on a ruler. The control condition.
#   paragraph   -- the author's paragraph breaks are the real boundaries.
#   sentence    -- sentences are atomic; pack them tightly.
#   recursive   -- respect the strongest separator that still fits (the
#                  LangChain-style cascade).
#   structural  -- headings are the boundaries; never merge across sections.
#   page        -- the page is the unit (forms, invoices, scanned records).
#   semantic    -- boundaries are where the embedding of the text *shifts*.
#   contextual  -- like paragraph, but each chunk is prefixed with where it sits,
#                  so a chunk read in isolation still knows what it is about.
#   proposition -- an LLM rewrites the text into standalone factual statements.
#                  Because the text is rewritten, these chunks carry no
#                  provenance back to a source block.
#
# They differ in cost too, which is stated in `cost` so the UI can warn:
# `fixed`/`paragraph`/`sentence`/`recursive`/`structural`/`page`/`contextual`
# are free; `semantic` costs one embedding pass; `proposition` costs one model
# call per `proposition_batch_tokens`-sized batch of blocks (default 900), not
# one per block.

#' @noRd
register_builtin_readers <- function() {
  gr_register_reader("stuff", read_stuff,
    calls = "stuff.answer", cost = cost_stuff,
    signature = "all|1|none", cost_calls = "1",
    description = "Whole document in one prompt. The baseline; errors or truncates if it does not fit.")
  gr_register_reader("map_reduce", read_map_reduce,
    calls = c("map.answer", "reduce"), cost = cost_map_reduce,
    signature = "all|N+logN|tree", cost_calls = "N + merges",
    description = "Answer each chunk independently, then tree-reduce. Parallel, order-independent.")
  gr_register_reader("refine", read_refine,
    calls = c("refine.draft", "refine.revise"), cost = cost_refine,
    signature = "all|N|forward", cost_calls = "N",
    description = "Sequential draft-and-revise down the document. Order matters; not parallelisable.")
  gr_register_reader("skim", read_skim,
    calls = c("skim.extract", "skim.consolidate", "skim.answer"), cost = cost_skim,
    signature = "all|N+1|none", cost_calls = "N + 1",
    description = "Extract verbatim evidence per chunk, then answer once from the evidence.")
  gr_register_reader("retrieve", read_retrieve,
    calls = "retrieve.answer", cost = cost_retrieve,
    signature = "topk|1|none", cost_calls = "1 + embeddings",
    description = "Embed, rank by cosine similarity, answer from the top k. Cost independent of length.")
  gr_register_reader("rerank", read_rerank,
    calls = c("rerank.score", "rerank.answer"), cost = cost_rerank,
    signature = "topk|m+1|none", cost_calls = "m + 1",
    description = "BM25 prefilter, then the model scores candidates, then answer from the winners.")
  gr_register_reader("hierarchical", read_hierarchical,
    calls = c("hier.summarise", "hier.answer"), cost = cost_hierarchical,
    signature = "all|N+tree+1|tree",
    cost_calls = "N + fan-in levels + 1",
    description = "Recursively summarise until the summaries fit, then answer. Truly recursive.")
  gr_register_reader("iterative", read_iterative,
    calls = c("iterative.step", "iterative.final"), cost = cost_iterative,
    signature = "topk|rounds*2|forward",
    cost_calls = "up to 2 x max_rounds",
    description = "Agentic loop: the model names what it still needs and that drives the next retrieval.")
  gr_register_reader("extract", read_extract,
    calls = c("extract.chunk", "extract.resolve"), cost = cost_extract,
    signature = "all|N+conflicts|none",
    cost_calls = "N (+1 per conflict with resolve = 'model')",
    description = "Fill a typed schema from every chunk, then reconcile. Needs `fields`.")
  gr_register_reader("screen", read_screen,
    calls = "screen.decide", cost = cost_screen,
    signature = "head|1|none", cost_calls = "1",
    description = paste0("Decide whether one document meets a review's criteria, from its ",
                         "opening. Needs `include`/`exclude`."))
  gr_register_reader("preview", read_preview,
    calls = c("preview.plan", "preview.skim", "preview.answer"), cost = cost_preview,
    signature = "planned|1+s+1|none",
    cost_calls = "1 + skimmed sections + 1",
    description = paste0("Plan from an outline first, then read only what the plan says to. ",
                         "Sections it skips are named."))
  gr_register_reader("ensemble", read_ensemble,
    calls = "ensemble.adjudicate", cost = cost_ensemble,
    signature = "ensemble|sum+1|none",
    cost_calls = "sum of members + 1",
    description = "Run several distinct readers and adjudicate. Members must have different signatures.")
  invisible(NULL)
}

#' @noRd
register_builtin_segmenters <- function() {
  gr_register_segmenter("fixed", seg_fixed, calls = character(0), cost = "free",
    description = "Uniform token windows, ignoring structure. The control condition.")
  gr_register_segmenter("paragraph", seg_paragraph, calls = character(0), cost = "free",
    description = "Greedy packing of the author's paragraphs up to the cap.")
  gr_register_segmenter("sentence", seg_sentence, calls = character(0), cost = "free",
    description = "Sentence-boundary packing; tighter, more chunks, cleaner edges.")
  gr_register_segmenter("recursive", seg_recursive, calls = character(0), cost = "free",
    description = "Cascade through separators, using the strongest one that fits.")
  gr_register_segmenter("structural", seg_structural, calls = character(0), cost = "free",
    description = "Never merge across headings; each chunk keeps its section title.")
  gr_register_segmenter("page", seg_page, calls = character(0), cost = "free",
    description = "One chunk per page. For forms, invoices and scanned records.")
  # needs_client = TRUE because seg_semantic falls back to `paragraph` without
  # one. Declaring FALSE made `gr_segmenters()` disagree with the behaviour, so
  # the one column a UI would check before offering the strategy was wrong.
  gr_register_segmenter("semantic", seg_semantic, calls = character(0), cost = "embedding",
    needs_client = TRUE,
    description = "Cut where consecutive embeddings diverge most. One embedding pass.")
  gr_register_segmenter("contextual", seg_contextual, calls = "segment.context", cost = "free",
    needs_client = FALSE,
    description = "Paragraph chunks prefixed with where they sit; context_source='llm' writes it per chunk.")
  gr_register_segmenter("proposition", seg_proposition, calls = "segment.proposition",
    cost = "llm", needs_client = TRUE,
    description = "Rewrite into standalone factual statements. Expensive; best for dense factual recall.")
  invisible(NULL)
}

# The call stems of the document layer's stages that are not registered as
# modules yet: gr_claims(), gr_outline() and gr_synthesise() make their own
# calls under these labels. "outline.derive.alt2", "synthesise.merge.level1"
# and "synthesise.revise.cut" are labels under them.
.gr_stage_calls <- list(
  claims = c("claims.draw", "claims.reconcile"),
  outline = "outline.derive",
  synthesise = c("synthesise.section", "synthesise.batch", "synthesise.merge",
                 "synthesise.revise"))

#' Every call stem declared by a registered reader or segmenter, or by one of
#' the stages above: the names an effort map may use (check_effort_stems()).
#' Read from the registries when asked, so a reader registered in this session
#' adds its stems, and a parallel worker, which is sent the registries, sees
#' the same ones.
#' @noRd
declared_call_stems <- function() {
  of <- function(reg) unlist(lapply(reg, function(e) e$calls), use.names = FALSE)
  unique(c(of(gr_state$readers), of(gr_state$segmenters),
           unlist(.gr_stage_calls, use.names = FALSE)))
}

#' Check the call stems a module declares: a character vector of labels, none
#' blank. NULL means the module declared none, and its name stands in, since
#' a reader or segmenter registered before stems were declared labels its
#' calls after itself as the built-ins do ("longest.answer" for "longest").
#' @noRd
check_calls <- function(calls, name) {
  if (is.null(calls)) return(name)
  if (!is.character(calls) || anyNA(calls) || !all(has_visible(calls)) ||
      any(grepl("\\s", calls))) {
    gr_abort(paste0("`calls` must be a character vector of call label stems, such as ",
                    "c(\"mine.score\", \"mine.answer\"), with no blanks or spaces."),
             class = "gr_bad_setting")
  }
  unique(calls)
}
