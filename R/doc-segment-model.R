# doc-segment-model.R: the contextual and proposition segmenters, and the trace
# marks for a segmenter's model calls.

#' The most one segmentation request can cost: `input_tokens` of prompt and a
#' reply at `max_output`, or the model's own ceiling if lower (for a reasoning
#' model, the larger cap the request is sent with), at the client model's price.
#' NA when the model has no price, which the trace cannot count either.
#' @noRd
seg_call_usd <- function(client, input_tokens, max_output) {
  model <- as_chr1(client$model, "unknown")
  # The segmenter's own call warns about an unknown model; once is enough.
  quiet <- function(expr) tryCatch(suppressWarnings(expr, classes = "gr_unknown_model"),
                                   error = function(e) NULL)
  info <- quiet(gr_model_info(model))
  if (is.null(info)) return(NA_real_)
  # Priced at the cap the request is sent with: a reasoning model is sent
  # room to reason above a short cap (reasoning_output_cap()), and is billed
  # for what it spends there.
  out <- reasoning_output_cap(min(as_num1(max_output, 0), as_num1(info$max_output, Inf)),
                              info, input_tokens)
  as_num1(quiet(gr_estimate_cost(model, input_tokens, out)), NA_real_)
}

#' Where a trace stands before a segmenter's batch of requests, for
#' seg_mark_recovered() to mark what the batch recorded after it.
#' @noRd
seg_trace_mark <- function(trace) {
  if (!inherits(trace, "gr_trace")) return(c(errors = 0L, steps = 0L))
  c(errors = length(trace$errors), steps = length(trace$steps))
}

#' Mark the `label` requests that failed after `mark` as recovered.
#'
#' For a segmenter that loses no text when its request fails: `contextual`
#' keeps the chunk without its header, and `proposition` keeps the batch as
#' written (or, when every batch failed, segments the document by sentence).
#' The shared contract is that such a failure's entry in `trace$errors`
#' carries `recovered = TRUE`, which failed_note() passes over. Left unmarked,
#' one failed context call made gr_read_many() call a document it had read in
#' full "failed ... not read in full", keep it out of the store, and read it
#' again on every run.
#'
#' Matched by label within what the batch added, not by an error's `step`: a
#' parallel batch's errors arrive from each worker's own trace, numbered from
#' that trace's first step, so the number does not locate the step here. Each
#' item makes at most one request, which records one step and, when it fails,
#' one error, so the failed steps with this label are those requests.
#' @noRd
seg_mark_recovered <- function(trace, mark, label) {
  if (!inherits(trace, "gr_trace")) return(invisible(NULL))
  errs <- seq_along(trace$errors)
  for (i in errs[errs > as.integer(mark[["errors"]])]) {
    if (identical(as_chr1(trace$errors[[i]]$label, ""), label)) trace$errors[[i]]$recovered <- TRUE
  }
  steps <- seq_along(trace$steps)
  for (s in steps[steps > as.integer(mark[["steps"]])]) {
    st <- trace$steps[[s]]
    if (identical(as_chr1(st$label, ""), label) && identical(st$ok, FALSE)) {
      trace$steps[[s]]$recovered <- TRUE
    }
  }
  invisible(NULL)
}

#' @noRd
seg_contextual <- function(doc, spec, client, trace) {
  # Contextual retrieval: each chunk keeps a short pointer to
  # where it sits, so a chunk retrieved alone is still interpretable. Free
  # variant uses document + section metadata; `context_source = "llm"` spends
  # one call per chunk to write the blurb.
  title <- basename(doc$source)
  src <- as_chr1(spec$context_source %||% "metadata")
  if (identical(src, "llm") && is.null(client)) {
    gr_warn(paste0("context_source = 'llm' needs a client; using the free metadata blurb ",
                   "instead. The chunk set records context_source = 'metadata'."),
            class = "gr_segment_fallback")
    src <- "metadata"
  }
  cap <- spec$max_tokens
  frame <- function(h, body) ifelse(nzchar(h), paste0("[", h, "]\n\n", body), body)
  # Room for the header is held back from the body BEFORE packing. Packed to
  # the full cap and then prefixed, a chunk near the cap went over it, and
  # gr_segment() cut it in two: the second piece had no header -- the
  # out-of-context excerpt this segmenter exists to prevent -- and every
  # "Part i of n" counted n before the cut. At least half the cap stays text.
  pack <- function(reserve) {
    sp <- spec
    sp$max_tokens <- max(cap - as.integer(reserve), (cap + 1L) %/% 2L)
    seg_paragraph(doc, sp, client, trace)$chunks
  }
  meta_headers <- function(d) {
    vapply(seq_len(nrow(d)), function(i) {
      bits <- c(sprintf("Source: %s", title),
                if (!is.na(d$section[i])) sprintf("Section: %s", d$section[i]),
                if (!is.na(d$page[i])) sprintf("Page: %d", d$page[i]),
                sprintf("Part %d of %d", i, nrow(d)))
      paste(bits, collapse = " | ")
    }, character(1))
  }
  # Whatever still does not fit -- a header longer than half the cap, a reply
  # counted as longer than it was asked to be -- is shortened, never the body:
  # the body is the document, the header only points into it.
  fit_headers <- function(h, body) {
    for (k in which(nzchar(h) & gr_count_tokens(frame(h, body)) > cap)) {
      was <- h[k]
      repeat {
        excess <- gr_count_tokens(frame(h[k], body[k])) - cap
        if (excess <= 0L || !nzchar(h[k])) break
        h[k] <- trimws(gr_truncate_tokens(h[k], gr_count_tokens(h[k]) - excess, marker = ""))
      }
      # One record per header, for the whole of what it lost. The limit is the
      # room the header was cut to, not the cap on header and body together.
      trace_truncation(trace, "segment.contextual.header", was, h[k],
                       limit = as.integer(gr_count_tokens(h[k])), chunk = k)
    }
    h
  }

  # The room a header needs. A reply is held to 90 tokens. A metadata header
  # is bounded by the longest one it could be: the longest section label, the
  # highest page, and a part number no larger than the document has
  # characters (a chunk holds at least one). One packing, no second pass.
  reserve <- if (identical(src, "llm")) 90L else {
    b <- doc$blocks
    top_page <- suppressWarnings(max(b$page, na.rm = TRUE))
    n_hi <- max(1L, nchar(doc$text))
    worst <- vapply(unique(c(NA_character_, b$section)), function(s) {
      paste(c(sprintf("Source: %s", title),
              if (!is.na(s)) sprintf("Section: %s", s),
              if (is.finite(top_page)) sprintf("Page: %d", as.integer(top_page)),
              sprintf("Part %d of %d", n_hi, n_hi)), collapse = " | ")
    }, character(1), USE.NAMES = FALSE)
    max(gr_count_tokens(frame(worst, "x"))) - gr_count_tokens("x")
  }
  d <- pack(reserve)
  if (!nrow(d)) return(new_chunks(character(0), "contextual", spec))
  extra <- list(context_source = src)
  headers <- if (identical(src, "llm")) {
    doc_summary <- truncate_logged(doc$text, 1500, "segment.contextual.document", trace,
                                   marker = "")$text
    sys_prompt <- "You situate an excerpt within its source document. Reply with one sentence, no preamble."
    ask <- function(excerpt) paste0(
      "<document>\n", doc_summary, "\n</document>\n\n<excerpt>\n", excerpt,
      "\n</excerpt>\n\nIn one sentence, say what this excerpt is about and where it fits in the document.")
    # The longest excerpt with its reply at the cap: what gr_lapply() holds a
    # parallel batch to, since the workers cannot see what the run spends.
    worst <- seg_call_usd(client, sum(gr_count_tokens(c(sys_prompt, ask("")))) + max(d$tokens), 90L)
    mark <- seg_trace_mark(trace)
    res <- gr_lapply(seq_len(nrow(d)), function(i, trace) {
      r <- gr_call(client, list(
        list(role = "system", content = sys_prompt),
        list(role = "user", content = ask(d$text[i]))
      ), max_output = 90L, trace = trace, label = "segment.context",
         effort = spec$effort)
      if (is_refused(r)) return(list(text = "", why = "limit"))
      if (!isTRUE(r$ok)) return(list(text = "", why = "failed"))
      txt <- trimws(as_chr1(r$text, ""))
      list(text = txt, why = if (nzchar(txt)) "" else "empty")
    }, parallel = spec$parallel, label = "context blurb", trace = trace,
       client = client, item_usd = worst)
    # A chunk whose context call failed is kept, whole, without its header: the
    # failure cost the chunk a pointer, not any of the document. Marked after
    # the batch, which may have run in workers whose traces are absorbed here.
    seg_mark_recovered(trace, mark, "segment.context")
    why <- vapply(res, function(r) if (is.list(r)) as_chr1(r$why, "failed") else "failed",
                  character(1))
    # But it is said. A chunk skipped at the run's limit, or whose call failed,
    # silently got no header while the chunk set still claimed
    # context_source = "llm": under gr_compare() a contextual recipe run after
    # the others was capped by their spending, and its answer said nothing.
    # The warning reaches the answer through the chunk set's warnings.
    missing <- nzchar(why)
    if (any(missing)) {
      reason <- c(limit = "skipped at the run's call or cost limit",
                  failed = "whose request failed", empty = "with an empty reply")
      n_why <- vapply(names(reason), function(r) sum(why == r), integer(1))
      gr_warn(sprintf(paste0("%d of %d contextual chunk(s) have no context line (%s). They are ",
                             "kept whole without one, so no text is lost, but each reads as an ",
                             "excerpt with nothing to say where it sits."),
                      sum(missing), length(missing),
                      paste(sprintf("%d %s", n_why[n_why > 0L], reason[n_why > 0L]),
                            collapse = ", ")),
              class = "gr_segment_fallback")
    }
    extra$blurbs_missing <- sum(missing)
    extra$blurbs_at_limit <- sum(why == "limit")
    vapply(res, function(r) if (is.list(r)) as_chr1(r$text, "") else "", character(1))
  } else {
    meta_headers(d)
  }
  headers <- fit_headers(headers, d$text)
  # The header is not the document's text, and under context_source = "llm" a
  # model wrote it. Kept as the chunk's text it became part of what quotes were
  # checked against, so a quote of a figure the context-writing call invented
  # ("revenue rose to 52 million" of a document that says 45.2) verified as a
  # verbatim quotation. `source_text` is the body alone; see new_chunks().
  body <- d$text
  out <- new_chunks(frame(headers, body), "contextual", spec, page = d$page,
                    section = d$section, block_id = d$block_id,
                    source_text = ifelse(nzchar(headers), body, NA_character_))
  out$extra <- extra
  out
}

#' A list of propositions as a flat character vector, whatever shape it arrived in.
#'
#' An array of strings simplifies to a character vector; an array of ARRAYS to a
#' matrix, which `as.character()` flattens column-major and so transposes; an
#' array of objects to a data frame, which `as.character()` deparses, putting
#' the literal text `c("A.", "B.")` into the document. [text_leaves()] reads
#' each shape in the order it was written. An object is read through its text
#' key when it has one -- `{"statement": ..., "confidence": "high"}` is one
#' proposition, not two -- and through every string when it has none, so a
#' proposition under a key nobody anticipated is kept. A number beside the text
#' is a label, not a proposition.
#' @noRd
prop_strings <- function(x) {
  text_leaves(x, prefer = c("text", "proposition", "statement", "sentence", "claim",
                            "assertion", "content"),
              object_numbers = FALSE)
}

#' @noRd
seg_proposition <- function(doc, spec, client, trace) {
  # Dense X-retrieval style: rewrite the text into standalone assertions, each
  # of which is self-contained (no dangling pronouns). Expensive, but it is the
  # segmentation that most changes what retrieval can find.
  if (is.null(client)) {
    gr_warn("Proposition segmentation needs a client; falling back to 'sentence'.",
            class = "gr_segment_fallback")
    out <- seg_sentence(doc, spec, client, trace); out$method <- "proposition->sentence"
    return(out)
  }
  batch_tokens <- as.integer(spec$proposition_batch_tokens %||% 900)
  batches <- pack_units(doc$blocks$text, batch_tokens, 0L, 0L,
                        meta = doc$blocks[, c("page", "section", "block_id")])
  schema <- list(type = "object", additionalProperties = FALSE,
                 required = list("propositions"),
                 properties = list(propositions = list(
                   type = "array", items = list(type = "string"))))
  # A batch that cannot be decomposed -- the call failed, the run hit its
  # ceiling, or the reply held nothing usable -- is KEPT AS WRITTEN rather than
  # dropped. It used to return character(0), so one bad batch in ten silently
  # removed a tenth of the document from everything downstream; only a run in
  # which EVERY batch failed noticed, by falling back to sentences. A segmenter
  # must never lose text.
  keep <- function(i) list(p = batches$text[i], kept = TRUE)
  sys_prompt <- paste0(
    "Decompose text into standalone propositions. Each proposition must be a single ",
    "self-contained factual statement: resolve every pronoun and abbreviation to the ",
    "entity it refers to, keep all numbers, dates and units verbatim, and add nothing ",
    "that is not stated in the text.")
  # The largest batch with its reply at the cap: what gr_lapply() holds a
  # parallel batch to, since the workers cannot see what the run spends.
  worst <- seg_call_usd(client, gr_count_tokens(sys_prompt) +
                          max(c(0L, gr_count_tokens(batches$text))), 2000L)
  mark <- seg_trace_mark(trace)
  res <- gr_lapply(seq_along(batches$text), function(i, trace) {
    # A request a limit refused keeps its batch as written, as a failed one does.
    out <- gr_call_json(client, list(
      list(role = "system", content = sys_prompt),
      list(role = "user", content = batches$text[i])
    ), schema = schema, schema_name = "propositions", trace = trace,
       label = "segment.proposition", max_output = 2000L, effort = spec$effort)
    if (!out$ok) return(keep(i))
    # as.character() on whatever simplifyVector made of it flattened a matrix
    # column-major (transposing the propositions) and deparsed a data frame
    # (putting the literal R expression c("A.", "B.") into the document text).
    p <- prop_strings(json_field(out$value, "propositions", scalar = FALSE))
    p <- p[has_content(p)]
    if (!length(p)) keep(i) else list(p = p, kept = FALSE)
  }, parallel = spec$parallel, label = "proposition batch", trace = trace,
     client = client, item_usd = worst)
  # Every batch whose request failed is kept as written, or, when all of them
  # failed, the document is segmented by sentence below: either way no text is
  # lost, so the failures are recovered ones. The warnings below still say
  # which chunks are not propositions.
  seg_mark_recovered(trace, mark, "segment.proposition")
  kept <- vapply(res, function(r) isTRUE(r$kept), logical(1))
  if (all(kept)) {
    gr_warn("Proposition extraction returned nothing; falling back to 'sentence'.",
            class = "gr_segment_fallback")
    out <- seg_sentence(doc, spec, client, trace); out$method <- "proposition->sentence"
    return(out)
  }
  if (any(kept)) {
    gr_warn(sprintf(paste0("%d of %d proposition batch(es) could not be decomposed and are kept ",
                           "as written, so no text is lost; those chunks are paragraphs, not ",
                           "propositions."), sum(kept), length(kept)),
            class = "gr_segment_fallback")
  }
  props <- unlist(lapply(res, function(r) r$p), use.names = FALSE)
  # Which batch each proposition came from, so each chunk can name the
  # document text it was written from.
  from <- rep(seq_along(res), vapply(res, function(r) length(r$p), integer(1)))
  real <- has_content(props)
  props <- props[real]
  from <- from[real]
  packed <- pack_units(props, spec$max_tokens, 0L, spec$min_tokens, joiner = "\n")
  # The propositions are the model's words, not the document's: a fact the
  # decomposing call added was checked against itself and verified, match 1.
  # `source_text` holds the batches each chunk's propositions came from, which
  # is what a quote from it has to be found in. A batch kept as written is its
  # own source.
  source <- vapply(seq_len(nrow(packed$span)), function(k) {
    b <- seq(from[packed$span$first[k]], from[packed$span$last[k]])
    paste(batches$text[b], collapse = "\n\n")
  }, character(1))
  out <- new_chunks(packed$text, "proposition", spec, source_text = source)
  # `propositions` counts propositions: a batch kept as written is a paragraph,
  # and counting it here reported a partly decomposed document as fully done.
  n_props <- sum(vapply(res[!kept], function(r) length(r$p), integer(1)))
  out$extra <- list(propositions = n_props, batches = length(batches$text),
                    batches_kept_as_written = sum(kept))
  out
}
