# doc-extract-read.R -- the `extract` reader: fill a schema from a document.
#
# Traversal `all|N+conflicts|none`. Every chunk is asked to fill whatever fields
# it can and to leave the rest null; the per-field answers are then reconciled.
#
# The call count is N plus one per DISAGREEMENT, not N + 1. Most fields are
# stated once in a paper, so most reconciliations are arithmetic rather than
# judgement, and paying a model to agree with itself is the kind of cost this
# package exists to avoid. A field that genuinely appears twice with different
# values is the interesting case, and that is where the extra call goes.
#
# Nothing here invents a value. A field no chunk reported comes back NA with the
# status "not reported", which is a FINDING -- the same distinction
# `is_not_found()` draws for answers. A review that cannot tell "the paper does
# not say" from "we failed to look" is not a review.

#' @noRd
read_extract <- function(chunks, question, client, spec, trace) {
  # `[[` not `$`: partial matching on a list is how `.cache_id` silently found
  # `client$.cache` once already. A read spec carries user-supplied `...` fields,
  # so the set of names is open and a prefix collision is a live possibility.
  fields <- spec[["fields"]]
  if (!inherits(fields, "gr_fields")) {
    gr_abort(paste0("The 'extract' reader needs `fields`. Build them with gr_fields(), and pass ",
                    "them through the read spec: gr_read_spec('extract', fields = gr_fields(...)), ",
                    "or use gr_extract(), which does this for you."),
             class = "gr_no_fields")
  }
  d <- chunks$chunks
  schema <- fields_schema(fields)
  listing <- fields_prompt(fields)

  warn_capped_batch(trace, "extract", nrow(d), "segment more coarsely")

  model <- spec[["skim_model"]] %||% spec[["model"]]
  fixed <- list(
    list(role = "system", content = paste0(
      "You fill a data-extraction form from one excerpt of a document. Fill only the fields ",
      "this excerpt actually supports; leave every other field null. Do not infer, do not ",
      "estimate, and do not carry over knowledge from outside the excerpt. For each field you ",
      "fill, copy the exact sentence it came from into the matching __quote field.")),
    list(role = "user", content = paste0("Goal: ", question)),
    list(role = "user", content = paste0("Fields:\n", listing)))
  excerpts <- vapply(seq_len(nrow(d)), function(i)
    paste0("<excerpt>\n", render_chunks(d[i, , drop = FALSE]), "\n</excerpt>"), character(1))
  # The largest request with its reply at the cap: what gr_lapply() holds a
  # parallel batch to, since the workers cannot see what the run spends.
  # Counted from the messages themselves: the field listing goes out with
  # every excerpt, and a long one is most of each prompt. Held only to
  # preflight's flat allowance for the prompt around a chunk, a parallel
  # extraction of 40 fields spent two thirds past max_cost_usd.
  worst <- extract_item_usd(client, model,
                            sum(gr_count_tokens(vapply(fixed, `[[`, character(1), "content"))) +
                              max(c(0L, gr_count_tokens(excerpts))),
                            spec$max_chunk_tokens)

  got <- gr_lapply(seq_len(nrow(d)), function(i, trace) {
    out <- gr_call_json(client, c(fixed, list(list(role = "user", content = excerpts[i]))),
                        schema = schema, schema_name = "extraction", allow_empty = TRUE,
                        # coerce_field() reads each value and reports one it
                        # cannot use, so a wrong-typed value is that field's
                        # problem, not the whole excerpt's.
                        own_scalars = TRUE,
                        model = model, max_output = spec$max_chunk_tokens,
                        temperature = spec$temperature, trace = trace, label = "extract.chunk",
                        effort = spec$effort)
    if (is_refused(out$result)) return(list(ok = FALSE, value = NULL, capped = TRUE))
    if (spec$delay_between_calls > 0) Sys.sleep(spec$delay_between_calls)
    list(ok = isTRUE(out$ok), value = out$value, chunk = i)
  }, parallel = spec$parallel, label = "extract chunk", trace = trace,
     client = client, item_usd = worst)

  # A request a limit stopped was not sent, so it did not fail: gr_read() names
  # the limit.
  capped <- vapply(got, function(g) isTRUE(g$capped), logical(1))
  failed <- sum(!vapply(got, function(g) isTRUE(g$ok), logical(1)) & !capped)
  rec <- reconcile_fields(got, fields, d, client, spec, trace)

  src <- extract_verbatim_source(d)
  ev <- if (length(rec$evidence_chunk)) {
    at <- match(rec$evidence_chunk, d$chunk_id)
    evidence_table(rec$evidence_chunk, rec$evidence_quote, d$page[at], d$section[at],
                   source_text = src[at],
                   kind = "extracted", extra = list(field = rec$evidence_field))
  } else NULL
  # `verified` from evidence_table() says only that the span occurs in the
  # chunk. For an extracted value that is not enough: "We enrolled 120 people."
  # verified n = 5000, and so did the quote "2". The span also has to carry the
  # value it is cited for, or it is not evidence for it. `match` keeps the span
  # score, so verified = FALSE with match = 1 reads as "the sentence is there,
  # and it does not say this".
  if (!is.null(ev) && nrow(ev)) {
    backs <- vapply(seq_len(nrow(ev)), function(i) {
      nm <- as.character(ev$field[i])
      quote_backs_value(rec$record[[nm]], ev$text[i], ev$source_text[i], fields[[nm]])
    }, logical(1))
    ev$verified <- ev$verified & backs
    # A value the adjudicating call judged unsupported -- it chose none of the
    # values the document gave -- is kept, as the first value, and is not
    # verified, whatever its quote says. Left verified, the cell read as
    # settled and fully supported although the one judgement asked of it said
    # the opposite, and the call it cost bought nothing.
    rejected <- names(rec$unresolved)[rec$unresolved == "rejected"]
    ev$verified[as.character(ev$field) %in% rejected] <- FALSE
  }
  # Named once, for the row's `warnings`: what resolve = "model" could not
  # settle, and so kept as with resolve = "first".
  if (length(rec$unresolved)) {
    why <- c(rejected = "the adjudicating request chose none of the values",
             failed = "the adjudicating request failed",
             limit = "a request limit was reached before it could be made")
    gr_warn(sprintf("resolve = \"model\" did not settle %s; the first value is kept.",
                    paste(sprintf("'%s' (%s)", names(rec$unresolved), why[rec$unresolved]),
                          collapse = ", ")),
            class = "gr_extract_unresolved")
  }

  # A value is SUPPORTED when a span was quoted for it, that span really occurs
  # in the chunk it was attributed to, and it carries the value. Two distinct
  # ways to fail: no quote at all, and a quote that is a paraphrase or does not
  # say this. The second is loud already -- `verified = FALSE` sits in the
  # evidence table and new_answer() marks the answer partial. The first was
  # silent, because a field with no quote produced no evidence row at all, so a
  # value nothing supports looked exactly like a value everything supported.
  # That is the failure mode worth naming.
  record <- rec$record
  filled <- names(fields)[!vapply(record, is.null, logical(1))]
  supported <- if (is.null(ev) || !nrow(ev)) character(0)
               else unique(as.character(ev$field[isTRUE_vec(ev$verified)]))
  unsupported <- setdiff(filled, supported)

  # `require_quote` is the strict policy a review protocol needs: no verified
  # quote, no datum. It is off by default because discarding an extracted value is
  # destructive and the caller should choose it, and because the count below
  # makes the same problem visible without discarding anything.
  if (isTRUE(spec[["require_quote"]]) && length(unsupported)) {
    # `record[[nm]] <- NULL` DELETES the key -- the same trap as modifyList().
    # The record has to stay one entry per field, or the JSON stops saying that
    # the field was looked for, and anything downstream that lines the record up
    # against the schema silently shifts.
    for (nm in unsupported) record[nm] <- list(NULL)
    # Evidence for a value that is no longer in the record would cite a cell that
    # does not exist.
    if (!is.null(ev) && nrow(ev)) ev <- ev[!ev$field %in% unsupported, , drop = FALSE]
    filled <- setdiff(filled, unsupported)
  }

  # digits = NA: jsonlite rounds to four decimal places by default, and this
  # text is the answer -- summary$answer, the audit report, as_json() and the
  # store fallback in answer_record() all read it. p = 0.00003 came out as 0.
  new_answer(as.character(as_json(record, pretty = FALSE, digits = NA)), "extract", question,
             unique(if (is.null(ev)) integer(0) else ev$chunk_id), trace,
             chunks_sent = d$chunk_id, evidence = ev,
             # An extraction that filled NOTHING is not a partial answer, it is a
             # complete negative one -- the document was read and does not report
             # these fields. Marking it partial would contradict the distinction
             # this reader exists to preserve, and would flag every off-topic
             # paper in a screening run as a broken read. An UNSUPPORTED value is
             # a different matter: something is in the table that nothing in the
             # document backs, and that is exactly what `partial` is for.
             # A value that could not be read is a field the document may well
             # report, and nothing in the table says what it was.
             partial = failed > 0 || any(capped) || length(unsupported) > 0 ||
               length(rec$unreadable) > 0,
             # With a request failed, an empty field may be in the excerpt that
             # was never read, so it is unknown rather than not reported. So is
             # one a chunk gave a value for that could not be read as its type.
             notes = list(chunks = nrow(d), fields = length(fields),
                          filled = length(filled),
                          not_reported = if (failed > 0) character(0)
                                         else setdiff(names(fields), c(filled, rec$unreadable)),
                          unknown = union(rec$unreadable,
                                          if (failed > 0) setdiff(names(fields), filled)
                                          else character(0)),
                          unsupported = unsupported,
                          dropped_unverified = if (isTRUE(spec[["require_quote"]]))
                            unsupported else character(0),
                          unreadable = rec$unreadable,
                          unresolved = rec$unresolved,
                          conflicts = rec$conflicts, failed_calls = failed,
                          record = record))
}

#' Turn per-chunk partial records into one record.
#'
#' Agreement is free; only disagreement costs a call. `resolve = "first"` (the
#' default) takes the earliest chunk's value and records the conflict, so a run
#' never silently doubles in price because a document repeated itself
#' inconsistently. `resolve = "model"` spends one call per conflicted field.
#' Chunks that agree on a value pool their quotes: the value is cited with the
#' best one any of them gave (best_supported_hit()).
#'
#' Also returns `unreadable`, the fields left empty although some chunk gave a
#' value that could not be read as the field's type (unreadable_value()), and
#' `unresolved`, the conflicted fields `resolve = "model"` did not settle,
#' named by why: "rejected" (the adjudicating call chose none of the values),
#' "failed" (it failed, or its reply chose nothing it could) or "limit" (a
#' request limit was reached first, so it was not made). The first value is
#' kept for each.
#' @noRd
reconcile_fields <- function(got, fields, d, client, spec, trace) {
  record <- empty_record(fields)
  conflicts <- list()
  unreadable <- character(0)
  unresolved <- character(0)
  ev_chunk <- integer(0); ev_quote <- character(0); ev_field <- character(0)
  resolve <- match.arg(as_chr1(spec[["resolve"]] %||% "first"), c("first", "model"))
  src <- extract_verbatim_source(d)
  # Whether a quote is verbatim in a chunk does not depend on the field it is
  # cited for, and a model often quotes one sentence for several fields.
  seen <- new.env(parent = emptyenv())
  verbatim <- function(q, i) {
    key <- paste0(i, "\r", q)
    if (is.null(seen[[key]])) assign(key, isTRUE(span_match(q, src[i])$verified), envir = seen)
    seen[[key]]
  }

  for (nm in names(fields)) {
    hits <- list()
    odd <- FALSE
    for (g in got) {
      if (!isTRUE(g$ok) || is.null(g$value)) next
      raw <- g$value[[nm]]
      v <- coerce_field(raw, fields[[nm]])
      if (is.null(v)) {
        odd <- odd || unreadable_value(raw)
        next
      }
      q <- as_chr1(g$value[[paste0(nm, "__quote")]], "")
      # What the evidence row will say: the span verifies in the chunk and
      # carries the value (see read_extract()).
      # quote_backs_value() first: it is the cheaper test, and when it passes
      # every passage is in the chunk, so span_match() takes its fast path.
      backs <- quote_backs_value(v, q, src[g$chunk], fields[[nm]]) && verbatim(q, g$chunk)
      # "None" or "N/A" in a string field is usually the model saying it found
      # nothing -- often Python's None, spelled out -- and it often fills the
      # quote the same way. It is the answer only when the document itself
      # says it ("Conflicts of interest: None."): kept with a sentence that
      # verifies and spells it, and dropped otherwise, as it always was. Kept
      # on any quote at all, "N/A" quoting "N/A" filled a document that reports
      # nothing and beat a later chunk's verbatim value.
      filler <- identical(fields[[nm]]$type, "string") && is_placeholder_value(v)
      if (filler && !(backs && placeholder_stated(v, q))) next
      hits[[length(hits) + 1L]] <- list(
        value = v, chunk = d$chunk_id[g$chunk], quote = q, supported = backs, filler = filler)
    }
    # A real value anywhere in the document beats a placeholder, rather than
    # contradicting it: that is what the old reading gave, by dropping every
    # placeholder.
    real <- !vapply(hits, function(h) isTRUE(h$filler), logical(1))
    if (any(real)) hits <- hits[real]
    # Empty, although a chunk gave something: "120 (60 per arm)", "unclear" for
    # a boolean, digits nothing here reads. Recorded as not reported, that was
    # a finding the document does not support, with nothing marking it.
    if (!length(hits)) {
      if (odd) unreadable <- c(unreadable, nm)
      next
    }

    # value_key(), not format(). format() keeps seven significant digits, so
    # 0.123456789 and 0.123456781 -- or two counts above 2^31 -- were the same
    # value and a real conflict between two parts of one paper was not reported.
    # By type, so two spellings of one string ("Randomised controlled trial",
    # "randomised controlled trial.") are one value, not a conflict that
    # resolve = "model" pays to adjudicate.
    keys <- vapply(hits, function(h) value_key(h$value, fields[[nm]]$type), character(1))
    # One hit per distinct value, in order of first appearance -- so "first"
    # still means the earliest chunk's VALUE -- but carrying the best quote any
    # chunk gave for it. Taking the first hit's quote made the abstract's
    # unquoted n = 120 hide the methods section's verbatim sentence for the same
    # 120: the value counted as unsupported, and require_quote deleted a datum
    # the document states word for word.
    reps <- lapply(unique(keys), function(k) best_supported_hit(hits[keys == k]))
    chosen <- reps[[1]]

    if (length(reps) > 1L) {
      conflicts[[nm]] <- vapply(reps, function(h) value_key(h$value), character(1))
      if (identical(resolve, "model")) {
        # "limit" when the governor refused the request; see resolve_conflict().
        pick <- resolve_conflict(nm, fields[[nm]], reps, client, spec, trace)
        if (is.character(pick)) unresolved[[nm]] <- pick else chosen <- pick
      }
    }
    record[[nm]] <- chosen$value
    if (nzchar(trimws(chosen$quote))) {
      ev_chunk <- c(ev_chunk, chosen$chunk)
      ev_quote <- c(ev_quote, chosen$quote)
      # Which field this span supports. Without it the evidence table says only
      # that SOMETHING in chunk 7 was quoted, and an extraction table whose
      # provenance cannot be traced back to the cell it justifies is decoration.
      ev_field <- c(ev_field, nm)
    }
  }
  list(record = record, conflicts = conflicts, evidence_chunk = ev_chunk,
       evidence_quote = ev_quote, evidence_field = ev_field,
       unreadable = unreadable, unresolved = unresolved)
}

#' The pieces of a quotation, in the order they are quoted.
#'
#' quote_passages() gives passages, each split into the pieces an elision
#' separates; the checks here take them one after another.
#' @noRd
quote_pieces <- function(quote) unlist(quote_passages(quote)$raw, use.names = FALSE)

#' Does a quotation state a placeholder value itself?
#'
#' "Conflicts of interest: None." does; "None" alone is the model echoing its
#' own filler, and "No country data were given." is the document not
#' reporting the field, which NA already says.
#' @noRd
placeholder_stated <- function(value, quote) {
  pieces <- quote_pieces(quote)
  if (!length(pieces) || all(vapply(pieces, is_placeholder_value, logical(1)))) return(FALSE)
  v <- normalise_for_match(as_chr1(value, ""))
  any(vapply(pieces, function(p) found_whole(v, p), logical(1)))
}

#' Of several hits giving the same value, the one whose quote best backs it.
#'
#' A quote that verifies and carries the value first, then any quote at all (so
#' a paraphrase is still shown and flagged rather than replaced by nothing),
#' then the first hit.
#' @noRd
best_supported_hit <- function(hits) {
  for (h in hits) if (isTRUE(h$supported)) return(h)
  for (h in hits) if (nzchar(trimws(h$quote))) return(h)
  hits[[1]]
}

#' The most one extraction request can cost: `input_tokens` of prompt and a
#' reply at `max_output` (at most the model's ceiling; for a reasoning model,
#' the larger cap the request is sent with), priced at the model that is billed
#' for it.
#'
#' That is the model the request names, except through a client that bills
#' every call as its own model whatever the request names (an ellmer chat;
#' see client_billed_model()). NA when that model has no price, which a
#' spending limit cannot count in this process either.
#' @noRd
extract_item_usd <- function(client, model, input_tokens, max_output) {
  billed <- client_billed_model(client) %||% model %||%
    as_chr1(client[["model", exact = TRUE]], gr_options("model"))
  # The request itself warns about an unknown model; once is enough.
  quiet <- function(expr) tryCatch(suppressWarnings(expr, classes = "gr_unknown_model"),
                                   error = function(e) NULL)
  info <- quiet(gr_model_info(billed))
  if (is.null(info)) return(NA_real_)
  # Priced at the cap the request is sent with: a reasoning model is sent
  # room to reason above a short cap (reasoning_output_cap()), and is billed
  # for what it spends there.
  out <- reasoning_output_cap(min(as_num1(max_output, 0), as_num1(info$max_output, Inf)),
                              info, input_tokens)
  as_num1(quiet(gr_estimate_cost(billed, input_tokens, out)), NA_real_)
}

#' quote_backs_value() for one reading of the quotation: `passages`, as
#' quote_passages() gives them (each the pieces an elision splits it into,
#' normalised), and `src`, a match_source() of the chunk.
#' @noRd
pieces_back_value <- function(value, passages, src, field) {
  pieces <- unlist(passages, use.names = FALSE)
  if (!length(pieces)) return(FALSE)
  if (!all(vapply(pieces, found_whole, logical(1), src = src))) return(FALSE)
  if (!passage_gaps_ok(passages, src)) return(FALSE)
  passage <- any(vapply(pieces, function(p) {
    length(regmatches(p, gregexpr("[\\p{L}\\p{N}]+", p, perl = TRUE))[[1]]) >= 2L ||
      nchar(p) >= 12L
  }, logical(1)))
  if (field$type %in% c("integer", "number")) {
    lang <- quote_language(paste(pieces, collapse = " "))
    got <- unlist(lapply(pieces, quote_numbers, lang = lang), use.names = FALSE)
    if (value_among(abs(as.numeric(value)), got)) return(TRUE)
    # A passage in a script whose number words nothing here reads (Cyrillic,
    # Greek, Arabic, Hangul), which states no number that can be read, is
    # checked as it was before: by span. Never one in the Latin script: its
    # languages are read, or it is English, and an English sentence with
    # "de novo", "SE" or an accented name in it states no number.
    return(!length(got) && passage && identical(lang, "script"))
  }
  if (passage) return(TRUE)
  v <- normalise_for_match(as_chr1(value, ""))
  nzchar(v) && any(vapply(pieces, function(p) found_whole(v, p), logical(1)))
}

#' Do the passages of a quotation leave out only what a faithful quotation
#' may?
#'
#' Each passage verifies on its own, and two ways of putting them together
#' can still change what the document says.
#'
#' Within a passage, the pieces an elision ("...") separates must occur in
#' order, and what the elision leaves out must be something one may: no
#' negation within a sentence ("the drug did ... reduce mortality" from "the
#' drug did not reduce mortality"), and across a sentence end, the next piece
#' must start a sentence ("Revenue ... rose 30%" from "Revenue fell 12%. Costs
#' rose 30%."). That is span_match()'s own test (found_in_order(), which
#' reads each gap with elision_gap_ok()).
#'
#' Separate passages -- lines, bullets, paragraphs, each in its own quote
#' marks -- are separate quotations, and each may start anywhere in a
#' sentence: "- The trial enrolled adults.\n- 240 patients were randomised."
#' quotes "... adults. In total, 240 patients were randomised." faithfully.
#' But two that follow each other within one sentence of the document are an
#' elision with no marker, and are held to elision_gap_ok() the same way:
#' "- the drug did\n- reduce mortality" does not verify against "the drug did
#' not reduce mortality". `src` is a match_source().
#' @noRd
passage_gaps_ok <- function(passages, src) {
  for (p in passages) if (length(p) > 1L && !found_in_order(p, src)) return(FALSE)
  if (length(passages) < 2L) return(TRUE)
  for (i in seq_len(length(passages) - 1L)) {
    a <- passages[[i]][length(passages[[i]])]
    b <- passages[[i + 1L]][1L]
    if (!unmarked_join_ok(a, b, src)) return(FALSE)
  }
  TRUE
}

#' Two consecutive passages, the last piece `a` of one and the first `b` of
#' the next: can `b` be read as a quotation of its own, or, where it follows
#' `a` within one sentence, as an elision that leaves out nothing it may not?
#' Every place `b` occurs is tried, against the nearest `a` before it.
#' @noRd
unmarked_join_ok <- function(a, b, src) {
  a_end <- found_every(a, src) + nchar(a) - 1L
  for (at in found_every(b, src)) {
    prev <- a_end[a_end < at]
    if (!length(prev)) return(TRUE)
    prev <- max(prev)
    gap <- substr(src$text, prev + 1L, at - 1L)
    if (grepl(.gr_sentence_end, gap, perl = TRUE) || elision_gap_ok(src, prev, at)) return(TRUE)
  }
  FALSE
}

#' Where a sentence ends, as elision_gap_ok() finds one: a full stop,
#' question or exclamation mark, colon or semicolon (past any closing quote
#' mark or bracket) before a space or the end, or a full-width mark of
#' Chinese or Japanese.
#' @noRd
.gr_sentence_end <- "[.!?;:][\"')\\]]*(?:\\s|$)|[\u3002\uff01\uff1f\uff1b\uff1a]"

#' Words that negate what follows them, for elision_gap_ok().
#' @noRd
.gr_negation_words <- c("not", "no", "never", "neither", "nor", "none", "nobody", "nothing",
                        "without", "cannot", "non", "failed", "fail", "fails", "unable",
                        "lack", "lacked", "lacking", "absent", "absence")

#' A value as a string that distinguishes every distinct value.
#'
#' Full precision for numbers, because the point is to tell two values apart:
#' `format()` rounds to seven significant digits and made different values
#' identical. `%.15g` keeps every digit a value written in a paper can have, so
#' two such values differ here exactly when they differ on the page; it also
#' prints a whole number without a decimal point or an exponent.
#'
#' With `type = "string"`, the value as a quotation is matched
#' (normalise_for_match(): case, quote marks, dashes and spaces folded), less
#' the quote marks around it and the punctuation after it, so two chunks that
#' write one value two ways do not count as contradicting each other. Nothing
#' else is folded: "-0.3" and "0.3", or "54%" and "54", stay two values. An
#' enum value is one of the declared values exactly, so it is compared as it
#' is.
#' @noRd
value_key <- function(v, type = NULL) {
  if (is.numeric(v)) return(sprintf("%.15g", v[1]))
  s <- as_chr1(v, "")
  if (!identical(type, "string")) return(s)
  s <- sub("[\\s\"'.,;:!?]+$", "", normalise_for_match(s), perl = TRUE)
  sub("^[\\s\"']+", "", s, perl = TRUE)
}

#' Mark the errors a trace recorded after the first `before` as recovered.
#'
#' The shared contract for a request whose failure the pipeline recovers from
#' without losing input: its entry in `trace$errors` carries `recovered =
#' TRUE`, and failed_note() does not count it as a failed read.
#' @noRd
extract_mark_recovered <- function(trace, before) {
  if (!inherits(trace, "gr_trace")) return(invisible(NULL))
  n <- length(trace$errors)
  if (n > before) {
    for (i in seq.int(before + 1L, n)) trace$errors[[i]]$recovered <- TRUE
  }
  invisible(NULL)
}

#' Ask a model which of a conflicted field's values the document supports.
#'
#' Returns the hit it chose, or why there is none: "rejected" when it chose
#' none of them (0), "failed" when the request failed or its reply named no
#' option.
#' @noRd
resolve_conflict <- function(nm, field, hits, client, spec, trace) {
  # value_key(), for the reason reconcile_fields() uses it: format() showed
  # 3000000001 and 3000000002 both as "3e+09", and the model was asked to choose
  # between two options it could not tell apart.
  opts <- vapply(seq_along(hits), function(i)
    sprintf("%d. %s   (from chunk %s: \"%s\")", i, value_key(hits[[i]]$value),
            hits[[i]]$chunk, substr(hits[[i]]$quote, 1, 200)),
    character(1))
  before <- if (inherits(trace, "gr_trace")) length(trace$errors) else 0L
  was <- if (inherits(trace, "gr_trace")) list(stop = trace$budget_stop, why = trace$stop_reason)
  out <- gr_call_json(client, list(
    list(role = "system", content = paste0(
      "Two or more parts of one document give different values for the same field. Choose the ",
      "one the document actually supports for the field as described, by its number. If none is ",
      "supportable, choose 0.")),
    list(role = "user", content = paste0("Field: ", nm, " -- ", field$description)),
    list(role = "user", content = paste(opts, collapse = "\n"))
  ), schema = list(type = "object", additionalProperties = FALSE,
                   required = list("choice"),
                   properties = list(choice = list(type = "integer", minimum = 0,
                                                   maximum = length(hits)))),
     schema_name = "conflict", model = spec$model, max_output = 100L,
     temperature = spec$temperature, trace = trace, label = "extract.resolve",
     effort = spec$effort)
  if (is_refused(out$result)) {
    # An adjudication a limit refused cuts nothing short: every excerpt has
    # been read by then. Left marked, the trace's budget_stop made
    # gr_read_many() call a document whose every chunk had been read "failed
    # ... before the document was read in full", keep it out of the store and
    # re-read it on every run. The refusal itself stays in `refusals`.
    if (!is.null(was)) {
      trace$budget_stop <- was$stop
      trace$stop_reason <- was$why
    }
    return("limit")
  }
  if (!isTRUE(out$ok)) {
    # The field falls back to the first value, as with resolve = "first", and
    # every excerpt was still read: the failure is recovered. Counted as a
    # failed read, it made a fully extracted document "failed", unstored and
    # left out of synthesis, and re-read on every run while the call kept
    # failing. The conflict itself stays in `conflicts`, and the field in the
    # answer's `unresolved` note.
    extract_mark_recovered(trace, before)
    return("failed")
  }
  # json_field(): `$` let a reply keyed `choices` answer a read of `choice`.
  # A reply that names no option is no verdict; 0 is one -- that none of the
  # values is supportable -- and the caller marks the value it keeps
  # unverified rather than presenting it as settled.
  i <- as_int1(json_field(out$value, "choice"), NA_integer_)
  if (is.na(i) || i < 0L || i > length(hits)) return("failed")
  if (i == 0L) return("rejected")
  hits[[i]]
}
