# doc-modules.R: the built-in segmenters and readers, registered when the
# package loads.

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
  gr_register_reader("stuff", read_stuff, signature = "all|1|none", cost_calls = "1",
    description = "Whole document in one prompt. The baseline; errors or truncates if it does not fit.")
  gr_register_reader("map_reduce", read_map_reduce, signature = "all|N+logN|tree", cost_calls = "N + merges",
    description = "Answer each chunk independently, then tree-reduce. Parallel, order-independent.")
  gr_register_reader("refine", read_refine, signature = "all|N|forward", cost_calls = "N",
    description = "Sequential draft-and-revise down the document. Order matters; not parallelisable.")
  gr_register_reader("skim", read_skim, signature = "all|N+1|none", cost_calls = "N + 1",
    description = "Extract verbatim evidence per chunk, then answer once from the evidence.")
  gr_register_reader("retrieve", read_retrieve, signature = "topk|1|none", cost_calls = "1 + embeddings",
    description = "Embed, rank by cosine similarity, answer from the top k. Cost independent of length.")
  gr_register_reader("rerank", read_rerank, signature = "topk|m+1|none", cost_calls = "m + 1",
    description = "BM25 prefilter, then the model scores candidates, then answer from the winners.")
  gr_register_reader("hierarchical", read_hierarchical, signature = "all|N+tree+1|tree",
    cost_calls = "N + fan-in levels + 1",
    description = "Recursively summarise until the summaries fit, then answer. Truly recursive.")
  gr_register_reader("iterative", read_iterative, signature = "topk|rounds*2|forward",
    cost_calls = "up to 2 x max_rounds",
    description = "Agentic loop: the model names what it still needs and that drives the next retrieval.")
  gr_register_reader("extract", read_extract, signature = "all|N+conflicts|none",
    cost_calls = "N (+1 per conflict with resolve = 'model')",
    description = "Fill a typed schema from every chunk, then reconcile. Needs `fields`.")
  gr_register_reader("screen", read_screen, signature = "head|1|none", cost_calls = "1",
    description = paste0("Decide whether one document meets a review's criteria, from its ",
                         "opening. Needs `include`/`exclude`."))
  gr_register_reader("preview", read_preview, signature = "planned|1+s+1|none",
    cost_calls = "1 + skimmed sections + 1",
    description = paste0("Plan from an outline first, then read only what the plan says to. ",
                         "Sections it skips are named."))
  gr_register_reader("ensemble", read_ensemble, signature = "ensemble|sum+1|none",
    cost_calls = "sum of members + 1",
    description = "Run several distinct readers and adjudicate. Members must have different signatures.")
  invisible(NULL)
}

#' @noRd
register_builtin_segmenters <- function() {
  gr_register_segmenter("fixed", seg_fixed, cost = "free",
    description = "Uniform token windows, ignoring structure. The control condition.")
  gr_register_segmenter("paragraph", seg_paragraph, cost = "free",
    description = "Greedy packing of the author's paragraphs up to the cap.")
  gr_register_segmenter("sentence", seg_sentence, cost = "free",
    description = "Sentence-boundary packing; tighter, more chunks, cleaner edges.")
  gr_register_segmenter("recursive", seg_recursive, cost = "free",
    description = "Cascade through separators, using the strongest one that fits.")
  gr_register_segmenter("structural", seg_structural, cost = "free",
    description = "Never merge across headings; each chunk keeps its section title.")
  gr_register_segmenter("page", seg_page, cost = "free",
    description = "One chunk per page. For forms, invoices and scanned records.")
  # needs_client = TRUE because seg_semantic falls back to `paragraph` without
  # one. Declaring FALSE made `gr_segmenters()` disagree with the behaviour, so
  # the one column a UI would check before offering the strategy was wrong.
  gr_register_segmenter("semantic", seg_semantic, cost = "embedding", needs_client = TRUE,
    description = "Cut where consecutive embeddings diverge most. One embedding pass.")
  gr_register_segmenter("contextual", seg_contextual, cost = "free", needs_client = FALSE,
    description = "Paragraph chunks prefixed with where they sit; context_source='llm' writes it per chunk.")
  gr_register_segmenter("proposition", seg_proposition, cost = "llm", needs_client = TRUE,
    description = "Rewrite into standalone factual statements. Expensive; best for dense factual recall.")
  invisible(NULL)
}
