# doc-claims-outline.R: an outline of a write-up, built from the claims.

#' `rationale` is required and nullable rather than optional, for the reason
#' given at .gr_claims_schema: strict mode refuses anything else.
#' @noRd
.gr_outline_schema <- list(
  type = "object", additionalProperties = FALSE,
  required = list("sections"),
  properties = list(sections = list(
    type = "array",
    items = list(
      type = "object", additionalProperties = FALSE,
      required = list("heading", "brief", "claims", "rationale"),
      properties = list(
        heading = list(type = "string",
                       description = "The section heading, as it will be printed."),
        brief = list(type = "string",
                     description = "One line saying what this section must cover."),
        claims = list(type = "array", items = list(type = "integer"),
                      description = paste0("The claim numbers this section covers. Every claim ",
                                           "goes in exactly one section.")),
        rationale = list(type = c("string", "null"),
                         description = "One line on why these claims belong together."))))))

#' Derive a review's sections from its claims
#'
#' [gr_synthesise()] takes an `outline` fixed before the reading, which makes the
#' review's structure the author's hypothesis rather than a finding. It is often
#' the strongest thing a review has to say: that a literature splits into three
#' incompatible operationalisations, say, and that the argument about effect size
#' is really an argument about measurement. This derives the structure from the
#' claims instead, and hands it back for you to accept or replace.
#'
#' @section What is verified:
#' Every claim is assigned to exactly one section. A claim number that does not
#' exist is dropped; a claim assigned twice keeps its first section; a claim the
#' reply never placed is put in the closing section rather than lost, with a
#' message saying so. A section left with no claims is removed, except the
#' closing one, which is allowed to be empty because it is where [gr_gaps()]
#' writes and gaps are not claims.
#'
#' @section More than one outline:
#' The grouping is the review's argument, and one proposal gives nothing to
#' weigh it against. With `alternatives` above 1, each further outline is a
#' request of its own, shown the groupings proposed before it and asked to
#' group the claims by a different organising principle. Asking the same
#' question again would not do: the default model takes no temperature, and
#' the response cache answers an identical request with the reply it stored.
#' The first request is the one `alternatives = 1` sends, so the first outline
#' is the same whatever `alternatives` says, and a run recorded without
#' alternatives still replays. The others are labelled `outline.derive.alt2`
#' onwards in the trace, which also records which were kept
#' (`outline.compare`).
#'
#' Each alternative is verified exactly as the first is. How far apart two
#' outlines are is then counted, not asked: the fraction of pairs of claims
#' that one puts in the same section and the other does not, 0 for the same
#' grouping under other headings and 1 for groupings that agree about no pair.
#' An alternative at 0 from an earlier one is dropped. So is one whose call
#' failed or was cut off, or none of whose sections held a claim once
#' verified, rather than replaced by a single section the way a failed first
#' outline is. None is requested when the first outline is such a single
#' section, or once the run reaches its call or cost limit. A warning
#' (`gr_outline_alternatives_short`) says when fewer outlines came back
#' distinct than were asked for, and why.
#'
#' Nothing ranks them, and no model is asked which is best. The first proposal
#' is returned as it would be alone, carrying `attr(, "comparison")`, one row
#' per outline asked for: `alternative`, `sections`, `claims_per_section` and
#' `contested_per_section` (claims with a contradicting study, per section, in
#' heading order), `distance` from the first, `nearest` (the distance to the
#' closest earlier outline kept), `kept`, a `note` saying why one was not kept,
#' and the `headings`. The kept alternatives are in `attr(, "alternatives")`.
#' Choose one with [gr_outline_pick()], which keeps its headings and its claim
#' assignment together.
#'
#' @param claims A [gr_claims()] result.
#' @param question The review question. Taken from `claims` if omitted.
#' @param client A [gr_client()]. One is built from `model` if omitted.
#' @param model,temperature Passed to the model call.
#' @param max_sections Upper bound on sections, before the closing one.
#' @param closing The heading of the closing section, which receives gap claims
#'   and anything unplaced. `NULL` for no closing section.
#' @param trace A [gr_trace()] to add this stage's calls to, or `NULL`. The
#'   calls are recorded on a trace of the stage's own, attached as
#'   `attr(, "trace")`, and folded into `trace` when the stage ends. The trace
#'   of `claims` is left as it was.
#' @param max_outline_tokens The reply limit for the outline call. The reply
#'   names every claim and writes a heading, brief and rationale per section,
#'   so by default it grows with both: `400 + 8` per claim `+ 60` per section,
#'   never below 1200, plus 4000 on a model registered as a reasoning model,
#'   which spends part of the same limit before it writes. Clamped to what the
#'   model can emit. A reply cut off at it puts every claim in one section,
#'   with a warning.
#' @param effort Reasoning effort, or `NULL` (the default) to send none: one
#'   string, or a character vector named by stage, as `effort` in
#'   [gr_read_spec()]. The call here is labelled `outline.derive`, and each
#'   further alternative `outline.derive.alt2`, `outline.derive.alt3` and so
#'   on, which a name of `outline.derive` covers. A higher effort spends more
#'   of `max_outline_tokens` before the reply starts.
#' @param alternatives How many outlines to ask for, from 1 to 10. Each one
#'   past the first is one more call, made one after another. See "More than
#'   one outline".
#' @return A named character vector shaped exactly like the `outline` argument of
#'   [gr_synthesise()] (headings as names, briefs as values), carrying
#'   `attr(, "claims")` (a `section`/`claim_id` frame), `attr(, "rationale")`,
#'   `attr(, "closing")`, `attr(, "trace")` (the calls made here) and
#'   `attr(, "claims_fingerprint")`, a hash of the
#'   claims' numbers and texts. A claim number means something only within one
#'   [gr_claims()] result, so [gr_synthesise()] refuses the outline
#'   (`gr_claims_mismatch`) when the `claims` it is given are not the ones the
#'   outline was derived from: a re-run, or claims edited or reordered since.
#'
#'   With `alternatives` above 1 it also carries `attr(, "comparison")`,
#'   `attr(, "alternatives")` (the other kept outlines, each shaped like this
#'   one) and `attr(, "alternative")`, which says which outline of the
#'   comparison it is.
#' @seealso [gr_claims()], [gr_synthesise()], [gr_gaps()], [gr_outline_pick()]
#' @export
#' @examples
#' tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok",
#'                   duplicate_of = NA_character_, n_filled = 1L, n_unverified = 0L,
#'                   conflicts = NA_character_, finding = c("supports", "contradicts"),
#'                   stringsAsFactors = FALSE)
#' cl <- gr_mock_client(function(messages, params) {
#'   if (grepl("<claims>", paste(unlist(messages), collapse = " "), fixed = TRUE)) {
#'     return(paste0('{"sections":[{"heading":"What it finds","brief":"the claims",',
#'                   '"claims":[1],"rationale":"one topic"}]}'))
#'   }
#'   paste0('{"claims":[{"claim":"It works in trials.","kind":"finding",',
#'          '"supported_by":[1],"contradicted_by":[2],"moderator":null,"scope":null}]}')
#' })
#' cm <- gr_claims(tab, question = "Does it work?", client = cl)
#' o <- gr_outline(cm, client = cl)
#' o
#' attr(o, "claims")
gr_outline <- function(claims, question = NULL, client = NULL, model = NULL,
                       temperature = NULL, max_sections = 6L,
                       closing = "What is missing", trace = NULL,
                       max_outline_tokens = NULL, effort = NULL, alternatives = 1L) {
  if (!inherits(claims, "gr_claims")) {
    gr_abort("`claims` must come from gr_claims().", class = "gr_bad_claims")
  }
  if (!nrow(claims$claims)) {
    gr_abort("That gr_claims has no claims, so there is no structure to derive from it.",
             class = "gr_no_claims")
  }
  # Labelled UTF-8, as in gr_claims(). The closing heading most of all: it
  # sits among headings read from the model, which are labelled, and
  # gr_synthesise() pastes it to the claims and trims it with them -- which,
  # typed with an accent under a C locale, stopped the write-up.
  question <- mark_utf8(as_chr1(question %||% claims$question))
  if (is.character(closing)) closing <- mark_utf8(closing)
  if (!is_nonblank(question)) gr_abort("`question` must be a non-empty string.")
  # Settled before any call, so a bad value warns before the first outline is
  # paid for rather than after it.
  alternatives <- clamp_warn(na_default(alternatives, 1L, "alternatives"), 1,
                             .gr_outline_max_alternatives, "alternatives")
  client <- client %||% gr_client(model = model %||% gr_options("model"))
  # The model first, because the default reply limit depends on it.
  spec <- resolve_read_model(gr_read_spec("stuff", model = model, temperature = temperature,
                                          effort = effort),
                             client)
  cw <- claims$claims
  # A fixed 1200 tokens, with no way to raise it, cut off the outline from about
  # 300 claims on an ordinary model and from 20 on a reasoning one, which spends
  # the same limit thinking first. Every claim then went to one section, and the
  # warning's advice could not help: the same claims ask for the same reply.
  info <- gr_model_info(spec$model)
  auto <- outline_reply_tokens(nrow(cw), max_sections, info)
  max_outline_tokens <- if (is.null(max_outline_tokens)) auto else
    clamp_warn(na_default(max_outline_tokens, auto, "max_outline_tokens"), 16, 1e6,
               "max_outline_tokens")
  # Clamped to what the model can emit, as gr_call() would, so that the limit a
  # warning names is the limit the request carried.
  spec$max_answer_tokens <- min(as.integer(max_outline_tokens), as.integer(info$max_output))
  # Its own trace, folded into a given one, as every corpus stage does (see
  # as_parent_trace()). It used to record on `claims$trace` when no trace was
  # given, which changed a finished gr_claims result, and on a given trace
  # directly, which counted every earlier stage's calls against this one's
  # limit.
  parent <- as_parent_trace(trace)
  trace <- gr_trace(meta = list(stage = "outline", question = question,
                                claims = nrow(cw)))
  if (!is.null(parent)) on.exit(trace_absorb(parent, trace), add = TRUE)

  # Labelled, so that a claim edited by hand, unlabelled under a non-UTF-8
  # locale, is not escaped by paste() for sitting beside the model's claims.
  listed <- paste(sprintf("%d. [%s] %s%s", cw$claim_id, mark_utf8(cw$kind), mark_utf8(cw$claim),
                          ifelse(is.na(cw$moderator), "",
                                 sprintf(" (contested; distinguished by %s)",
                                         mark_utf8(cw$moderator)))),
                  collapse = "\n")
  msgs <- list(
    list(role = "system", content = .gr_prompts$outline_system),
    list(role = "user", content = paste0("Review question: ", question)),
    list(role = "user", content = paste0("<claims>\n", listed, "\n</claims>")),
    list(role = "user", content = sprintf("Use at most %d sections.", as.integer(max_sections))))
  capped <- !trace_can_call(trace)
  res <- if (!capped) {
    gr_call_json(client, msgs, schema = .gr_outline_schema, schema_name = "outline",
                 model = spec$model, max_output = spec$max_answer_tokens,
                 temperature = spec$temperature, trace = trace, label = "outline.derive",
                 effort = spec$effort)
  } else list(ok = FALSE, value = NULL)

  secs <- if (isTRUE(res$ok)) outline_rows(json_field(res$value, "sections", scalar = FALSE)) else NULL
  derived <- !is.null(secs) && nrow(secs) > 0L
  if (!derived) {
    # A reply cut off at the limit never closes its JSON, so it arrives here
    # like any failed call. Said apart, because "try again" cannot help: the
    # same claims ask for the same reply, and it stops in the same place.
    cut <- !capped && reply_cut_off(res$result)
    gr_warn(if (capped) sprintf(paste0("The outline was not requested: the run had reached its %s. ",
                                       "Every claim was put in one section. Raise the limit, or ",
                                       "pass an `outline` to gr_synthesise() yourself."),
                                cap_name(trace))
            else if (cut) sprintf(paste0("The outline reply %s before it finished, so every claim was ",
                                         "put in one section. Lower `max_sections`, or pass an ",
                                         "`outline` to gr_synthesise() yourself."),
                                  call_failure(res$result, msgs, spec$model, spec$max_answer_tokens,
                                               "`max_outline_tokens`"))
            else paste0("The outline call did not return usable sections, so every claim was put ",
                        "in one section. Pass an `outline` to gr_synthesise() yourself, or try again."),
            class = if (cut) c("gr_outline_truncated", "gr_outline_failed") else "gr_outline_failed")
    secs <- data.frame(heading = "Findings", brief = "What the evidence supports",
                       rationale = NA_character_, stringsAsFactors = FALSE)
    secs$.claims <- list(cw$claim_id)
  }
  out <- finish_outline(secs, cw, closing, max_sections)
  if (alternatives >= 2L) {
    out <- outline_alternatives(out, alternatives, if (derived) secs, msgs, cw, closing,
                                max_sections, client, spec, trace)
  }
  outline_with_trace(out, trace)
}

#' Attach the trace that recorded an outline's calls, to the outline and to
#' each alternative it carries, so the one gr_outline_pick() hands back still
#' says what it cost. gr_synthesise() keeps it as `$outline_trace`.
#' @noRd
outline_with_trace <- function(out, trace) {
  alts <- attr(out, "alternatives")
  if (length(alts)) {
    attr(out, "alternatives") <- lapply(alts, function(a) {
      attr(a, "trace") <- trace
      a
    })
  }
  attr(out, "trace") <- trace
  out
}

#' The default reply limit for an outline of `n` claims, on the model `info`
#' describes.
#'
#' The reply lists every claim number and writes a heading, a brief and a
#' rationale per section. Never below the 1200 it used to be fixed at. A
#' reasoning model spends part of the same limit before it writes a word, and
#' how much is not known in advance; a limit is a ceiling rather than a charge,
#' so the allowance is generous, while a reply cut off costs the whole outline.
#' @noRd
outline_reply_tokens <- function(n, max_sections, info) {
  sections <- suppressWarnings(as.numeric(max_sections))
  if (length(sections) != 1L || !is.finite(sections)) sections <- 6
  base <- max(1200, 400 + 8 * n + 60 * sections)
  as.integer(min(1e6, base + if (isTRUE(info$reasoning)) 4000 else 0))
}

#' @noRd
outline_rows <- function(x) {
  # Exact reads throughout: this is a model's reply, and `$` let `claim_draft`
  # answer for `claim` and `headings` answer for `heading` -- a key the schema
  # never defined producing a real row.
  fx <- function(o, nm) o[[nm, exact = TRUE]]
  if (is.null(x)) return(NULL)
  if (!is.data.frame(x) && is.list(x) && !is.null(names(x))) x <- list(x)
  # Same two shapes claim_rows() guards against: a JSON array of strings, and a
  # bare vector. Both crashed rather than returning "no outline came back".
  if (!is.data.frame(x) && !is.list(x)) return(NULL)
  if (is.list(x) && !is.data.frame(x)) {
    x <- x[vapply(x, function(e) is.list(e) && !is.null(names(e)), logical(1))]
    if (!length(x)) return(NULL)
    ids <- lapply(x, function(e) as_id_list(list(fx(e, "claims")), 1L)[[1]])
    out <- do.call(rbind, lapply(x, function(e) data.frame(
      heading = as_chr1(fx(e, "heading")), brief = as_chr1(fx(e, "brief")),
      rationale = as_chr1(fx(e, "rationale"), NA_character_), stringsAsFactors = FALSE)))
  } else {
    n <- nrow(x)
    ids <- as_id_list(fx(x, "claims"), n)
    out <- data.frame(heading = vapply(fx(x, "heading") %||% rep(NA, n), as_chr1, character(1),
                                       USE.NAMES = FALSE),
                      brief = vapply(fx(x, "brief") %||% rep(NA, n), as_chr1, character(1),
                                     USE.NAMES = FALSE),
                      rationale = vapply(fx(x, "rationale") %||% rep(NA, n), as_chr1, character(1),
                                         USE.NAMES = FALSE),
                      stringsAsFactors = FALSE)
  }
  if (is.null(out) || !nrow(out)) return(NULL)
  out$rationale[!nzchar(out$rationale)] <- NA_character_
  out$.claims <- ids
  out[nzchar(trimws(out$heading)), , drop = FALSE]
}

#' Assign every claim exactly once, and keep the ones nobody placed.
#' @noRd
finish_outline <- function(secs, cw, closing, max_sections) {
  ids <- cw$claim_id
  if (nrow(secs) > max_sections) secs <- secs[seq_len(max_sections), , drop = FALSE]
  seen <- integer(0)
  for (i in seq_len(nrow(secs))) {
    v <- intersect(secs$.claims[[i]], ids)
    # First assignment wins. A claim in two sections is written up twice, and
    # the reader has no way to know it is one claim.
    v <- setdiff(v, seen)
    seen <- c(seen, v)
    secs$.claims[[i]] <- sort(v)
  }
  unplaced <- setdiff(ids, seen)
  gaps_kind <- cw$claim_id[cw$kind == "gap"]

  keep <- vapply(secs$.claims, length, integer(1)) > 0L
  secs <- secs[keep, , drop = FALSE]
  if (!nrow(secs) && !is_nonblank(closing)) {
    # Every section the reply proposed lost all its claims to verification, and
    # there is no closing section to put them in. One section beats none: an
    # empty outline aborts gr_synthesise(), which loses the claims entirely.
    secs <- data.frame(heading = "Findings", brief = "What the evidence supports",
                       rationale = NA_character_, stringsAsFactors = FALSE)
    secs$.claims <- list(sort(ids))
    unplaced <- integer(0)
  }
  if (is_nonblank(closing)) {
    # Gap claims belong here whatever the reply said: a gap is what the
    # literature does not cover, and reading it under "What it finds" inverts it.
    move <- unique(c(unplaced, gaps_kind))
    for (i in seq_len(nrow(secs))) secs$.claims[[i]] <- setdiff(secs$.claims[[i]], gaps_kind)
    tail_row <- data.frame(heading = as_chr1(closing),
                           brief = "The questions this body of work cannot answer, and why",
                           rationale = "Gaps, and anything the structure could not place",
                           stringsAsFactors = FALSE)
    tail_row$.claims <- list(sort(move))
    secs <- secs[vapply(secs$.claims, length, integer(1)) > 0L, , drop = FALSE]
    secs <- rbind(secs, tail_row)
  } else if (length(unplaced)) {
    secs$.claims[[nrow(secs)]] <- sort(c(secs$.claims[[nrow(secs)]], unplaced))
  }
  if (length(unplaced)) {
    gr_msg(sprintf("%d claim(s) were not placed by the outline and went to the closing section.",
                   length(unplaced)))
  }

  # Everything downstream keys the outline by HEADING -- gr_synthesise() writes
  # one section per name and looks its claims up by that name -- so two sections
  # called the same thing wrote the same heading twice and each copy took the
  # union of both claim sets. Three claims came out as five section slots. Merge
  # rather than rename: a reply that proposed "Findings" twice meant one section.
  if (anyDuplicated(secs$heading)) {
    dup <- duplicated(secs$heading)
    for (h in unique(secs$heading[dup])) {
      j <- which(secs$heading == h)
      secs$.claims[[j[1]]] <- sort(unique(unlist(secs$.claims[j], use.names = FALSE)))
    }
    gr_msg(sprintf("%d duplicate section heading(s) in the outline were merged into one.",
                   sum(dup)))
    secs <- secs[!dup, , drop = FALSE]
  }

  map <- do.call(rbind, lapply(seq_len(nrow(secs)), function(i) {
    v <- secs$.claims[[i]]
    if (!length(v)) return(NULL)
    data.frame(section = secs$heading[i], claim_id = v, stringsAsFactors = FALSE)
  }))
  if (is.null(map)) {
    map <- data.frame(section = character(0), claim_id = integer(0), stringsAsFactors = FALSE)
  }
  out <- stats::setNames(secs$brief, secs$heading)
  attr(out, "claims") <- map
  attr(out, "rationale") <- stats::setNames(secs$rationale, secs$heading)
  attr(out, "closing") <- if (is_nonblank(closing)) as_chr1(closing) else NA_character_
  # Which claims the numbers in `map` are. A claim number is a position in one
  # gr_claims() result, so an outline made from a re-run, or from claims
  # reordered since, names the same numbers for other claims; gr_synthesise()
  # compares this with the claims it is given and stops on a difference.
  attr(out, "claims_fingerprint") <- claims_fingerprint(cw)
  out
}
