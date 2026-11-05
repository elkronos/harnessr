# doc-read-preview.R: the preview reader.


# ---------------------------------------------------------------------------
# preview: planned | 1 + skims + 1 | none
#
# The only reader that decides how to read before reading. Every other reader
# treats all chunks alike: `stuff` sends them all, `map_reduce` answers from
# each in turn, `retrieve` ranks them by similarity. None of them plans.
#
# A skilled analyst handed a 200-page report does not read it uniformly, and
# does not rank its paragraphs by similarity either. They look at the structure,
# work out which parts can bear on the question, read those properly, scan a few
# more, and ignore the rest. That is a different traversal from anything above,
# which is why it gets its own signature rather than a flag on an existing
# reader: selection is `planned`, and the plan is an artifact you can read back.
#
# The obvious objection is that the planner is itself an LLM call about a long
# document, and so prone to exactly the degradation this package exists to
# manage. Three things keep it honest. The outline it sees is built from section
# metadata and short excerpts, never the full text, and is capped at
# `preview_tokens`. Its output is a fixed schema, not prose. And when it fails or
# returns something unparseable, the reader reads everything and says so, rather
# than quietly skipping the document.
# ---------------------------------------------------------------------------

#' Group chunks into the units a plan is made of.
#'
#' Sections when the segmenter recorded them, contiguous runs of chunks when it
#' did not -- `fixed` and `recursive` leave `section` NA on every row, and a
#' planner needs something to point at either way.
#' @noRd
preview_units <- function(d, target = 8L) {
  sec <- as.character(d$section)
  # A placeholder is not a heading. `seg_structural()` writes the literal
  # "[no section]" where a chunk has none, so a document without headings
  # arrived here with a section column that was entirely placeholder rather
  # than NA. `!all(is.na(sec))` was therefore TRUE, the run-length grouping
  # produced ONE unit spanning the document, and a plan that marked that single
  # unit "skim" sent one truncated excerpt and reported the answer complete --
  # 16% of an 18,000-token document read, `partial = FALSE`.
  sec[!is.na(sec) & (!nzchar(trimws(sec)) | sec %in% .gr_no_section)] <- NA_character_
  if (!all(is.na(sec))) {
    # `rle` on the raw column would merge two same-named sections separated by a
    # third. Keying on a run id keeps them apart.
    key <- sec
    key[is.na(key)] <- "none"
    run <- cumsum(c(TRUE, key[-1] != key[-length(key)]))
    units <- unname(split(seq_len(nrow(d)), run))
    # One unit covering everything is not a plan -- there is nothing to decide
    # between, and every treatment it can be given applies to the whole
    # document. Fall through to blocks, which is what a document with no
    # structure gets anyway.
    if (length(units) > 1L) return(units)
  }
  # No structure to work with: contiguous blocks, sized so a long document does
  # not produce an outline with one line per chunk.
  n <- nrow(d)
  size <- max(1L, ceiling(n / max(1L, target)))
  unname(split(seq_len(n), ceiling(seq_len(n) / size)))
}

#' The label a unit is known by, in the plan and in the outline.
#' @noRd
preview_label <- function(d, rows) {
  nm <- unique(as.character(d$section[rows]))
  nm <- nm[!is.na(nm) & nzchar(nm)]
  if (length(nm)) nm[1] else sprintf("chunks %d-%d", min(rows), max(rows))
}

#' One line per unit: what it is, how big, and enough text to judge it by.
#' @noRd
preview_outline <- function(d, units, budget) {
  first_words <- function(x, n) {
    w <- strsplit(trimws(as_chr1(x)), "[[:space:]]+")[[1]]
    paste(utils::head(w, n), collapse = " ")
  }
  body <- ""
  # Shrink the per-unit excerpt until the whole outline fits, rather than
  # truncating the outline and hiding whole sections from the planner. A section
  # the planner never saw is a section it cannot choose to read.
  for (w in c(40L, 25L, 15L, 8L)) {
    lines <- vapply(seq_along(units), function(i) {
      rows <- units[[i]]
      pg <- d$page[rows]; pg <- pg[!is.na(pg)]
      # page_text(), not "%d": a segmenter may record page labels ("iv") or a
      # fractional page, and "%d" failed on both. Labels have no order to take
      # the least and greatest of, so the first and the last stand for them.
      pages <- if (!length(pg)) "" else if (is.numeric(pg))
        sprintf("pp. %s-%s | ", page_text(min(pg)), page_text(max(pg)))
      else sprintf("pp. %s-%s | ", page_text(pg[1]), page_text(pg[length(pg)]))
      sprintf("[%d] %s | chunks %d-%d | %stokens %d\n    opens: %s\n    ends: %s",
              i, preview_label(d, rows), min(rows), max(rows), pages,
              sum(d$tokens[rows]),
              first_words(d$text[rows[1]], w),
              first_words(d$text[rows[length(rows)]], w))
    }, character(1))
    body <- paste(lines, collapse = "\n")
    if (gr_count_tokens(body) <= budget) return(body)
  }
  gr_truncate_tokens(body, budget)
}

#' @noRd
read_preview <- function(chunks, question, client, spec, trace) {
  d <- chunks$chunks
  units <- preview_units(d)
  n_units <- length(units)

  outline <- preview_outline(d, units, as.integer(clamp(spec$preview_tokens %||% 1200L, 100, 1e5)))
  schema <- list(type = "object", additionalProperties = FALSE,
                 required = list("sections"),
                 properties = list(sections = list(
                   type = "array",
                   items = list(type = "object", additionalProperties = FALSE,
                                required = list("id", "treatment", "reason"),
                                properties = list(
                                  id = list(type = "integer"),
                                  treatment = list(type = "string",
                                                   enum = list("read", "skim", "skip")),
                                  reason = list(type = "string"))))))

  plan <- if (trace_can_call(trace)) {
    gr_call_json(client, list(
      list(role = "system", content = .gr_prompts$preview_system),
      list(role = "user", content = paste0("Question: ", question)),
      list(role = "user", content = paste0("<outline>\n", outline, "\n</outline>")),
      list(role = "user", content = sprintf(
        "Return one entry for each of the %d sections, using the ids shown.", n_units))
    ), schema = schema, schema_name = "reading_plan", model = spec$model,
       max_output = spec$max_answer_tokens, temperature = spec$temperature,
       trace = trace, label = "preview.plan", effort = spec$effort)
  } else list(ok = FALSE, value = NULL)

  # The default is READ, not skip. An unplanned section is one the planner did
  # not speak about, and the safe reading of silence is "look at it", not "throw
  # it away": a skipped section is never revisited, and this reader must not be
  # able to lose a document's contents to a malformed reply.
  treat <- rep("read", n_units)
  reasons <- rep(NA_character_, n_units)
  degraded <- TRUE
  if (isTRUE(plan$ok)) {
    tab <- json_field(plan$value, "sections", scalar = FALSE)
    # is.atomic() on both columns: an `id` that arrived as an array becomes a
    # LIST column, and as.integer() on a list is an error, not a warning, so
    # suppressWarnings() did not catch it and the reader crashed instead of
    # taking the degraded path three lines below.
    if (is.data.frame(tab) && nrow(tab) && all(c("id", "treatment") %in% names(tab)) &&
        is.atomic(tab$id) && is.atomic(tab$treatment)) {
      ids <- suppressWarnings(as.integer(tab$id))
      tr <- lower_text(trimws(as.character(tab$treatment)))
      # Lengths are equal by construction (columns of one frame), so no
      # recycling here; `ok` is as long as the plan.
      ok <- !is.na(ids) & ids >= 1L & ids <= n_units & tr %in% c("read", "skim", "skip")
      if (any(ok)) {
        # Last entry wins for a duplicated id, matching the registries' rule.
        treat[ids[ok]] <- tr[ok]
        if (!is.null(tab$reason)) reasons[ids[ok]] <- as.character(tab$reason)[ok]
        degraded <- FALSE
      }
    }
  }
  if (degraded) {
    gr_warn(paste0("The preview step returned no usable reading plan, so every section is being ",
                   "read in full (does this endpoint support JSON schema output?). This run is ",
                   "effectively 'stuff', not 'preview'."), class = "gr_preview_degraded")
  }

  # Budget the sections marked `read`, in document order. What does not fit is
  # DEMOTED to skim rather than dropped: the section still gets looked at, for
  # one call, instead of vanishing because the plan was more ambitious than the
  # context window. The planner and the skims judge where the answer is, not
  # whether the question holds, so the premise rule goes only to the answer.
  overhead <- prompt_overhead(question, answer_system(spec$cite, spec$premise), spec$restate)
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  # as.integer(), because `unlist()` on an empty list returns NULL, not
  # integer(0) -- and `fit_chunks()` reads `order %||% seq_len(nrow(df))`, so a
  # plan that marked every section skip handed it NULL and it read the WHOLE
  # document. The reader silently did the opposite of what the plan said, and
  # charged for it. as.integer(NULL) is integer(0), which `%||%` leaves alone.
  read_rows <- sort(as.integer(unlist(units[treat == "read"], use.names = FALSE)))
  fit <- fit_chunks(d, bud$input, order = read_rows)
  demoted <- integer(0)
  if (length(fit$dropped)) {
    demoted <- which(vapply(units, function(rows) any(rows %in% fit$dropped), logical(1)) &
                     treat == "read")
    treat[demoted] <- "skim"
  }
  # A demoted section is skimmed, whole, and not read as well. The part of it
  # that fitted used to stay in the prompt verbatim while the section was
  # skimmed too, so its chunks went in twice, in a prompt with room for
  # neither.
  keep_rows <- as.integer(setdiff(fit$idx, unlist(units[demoted], use.names = FALSE)))

  # One extraction call per skimmed SECTION, not per chunk. That is what makes
  # this cheaper than `skim`: the plan has already judged these sections
  # unlikely to hold the answer, so they get one look each.
  skim_units <- which(treat == "skim")
  ev_skim <- NULL
  ev_rows <- list()
  skim_sent <- integer(0)
  failed <- 0L
  not_sent <- 0L
  truncated <- 0L
  cut <- 0L
  if (length(skim_units)) {
    cap <- max(64L, bud$input %/% 2L)
    skim_model <- spec$skim_model %||% spec$model
    # The largest section as it is sent, rendered and cut to `cap`, with its
    # reply at the cap; see map_reduce.
    sent <- vapply(units[skim_units], function(rows)
      as.numeric(gr_count_tokens(render_chunks(d[rows, , drop = FALSE]))), numeric(1))
    worst <- batch_item_usd(client, skim_model, min(cap, max_tokens_of(sent)) +
                              prompt_overhead(question, .gr_prompts$extract_system, "never"),
                            spec$max_chunk_tokens)
    res <- gr_lapply(skim_units, function(i, trace) {
      rows <- units[[i]]
      if (!trace_can_call(trace)) return(list(ok = FALSE, text = "", rows = rows, capped = TRUE))
      body <- render_chunks(d[rows, , drop = FALSE])
      # What the truncation costs is reported, not swallowed. A skimmed unit
      # too big for one call used to lose its tail silently, so the run said it
      # had looked at a section it had seen half of.
      had <- gr_count_tokens(body)
      lost <- 0L
      if (had > cap) { body <- gr_truncate_tokens(body, cap); lost <- as.integer(had - cap) }
      r <- gr_call(client, list(
        list(role = "system", content = .gr_prompts$extract_system),
        list(role = "user", content = paste0("Question: ", question)),
        list(role = "user", content = paste0("<excerpt>\n", body, "\n</excerpt>"))
      ), model = skim_model, max_output = spec$max_chunk_tokens,
         temperature = spec$temperature, trace = trace, label = "preview.skim",
         effort = spec$effort)
      list(ok = usable_text(r), text = r$text, rows = rows, lost = lost, cut = reply_cut_off(r))
    }, parallel = spec$parallel, label = "preview section", trace = trace,
       client = client, item_usd = worst)

    truncated <- sum(vapply(res, function(r) as.integer(r$lost %||% 0L), integer(1)))
    ok <- vapply(res, function(r) isTRUE(r$ok), logical(1))
    txt <- vapply(res, function(r) as_chr1(r$text), character(1))
    # Not sent is not failed; see map_reduce.
    capped <- vapply(res, function(r) isTRUE(r$capped), logical(1))
    failed <- sum(!ok & !capped)
    not_sent <- sum(capped)
    skim_sent <- as.integer(unlist(lapply(res[!capped], function(r) r$rows), use.names = FALSE))
    # NONE in any script's decoration; see skim.
    keep <- ok & !is_none_reply(txt) & has_content(txt)
    # Evidence cut off at the output cap; see skim.
    cut <- sum(keep & vapply(res, function(r) isTRUE(r$cut), logical(1)))
    if (any(keep)) {
      rows1 <- vapply(res[keep], function(r) as.integer(r$rows[1]), integer(1))
      # Model-written, so it carries its source and is verified -- the rule
      # `skim` follows. The source is the whole section the span was drawn from,
      # which is what the model actually saw, less anything a segmenter wrote.
      src <- vapply(res[keep], function(r) paste(reader_source_text(d)[r$rows], collapse = "\n\n"),
                    character(1))
      ev_skim <- evidence_table(d$chunk_id[rows1], txt[keep], d$page[rows1], d$section[rows1],
                                source_text = src, kind = "extracted")
      ev_rows <- lapply(res[keep], function(r) r$rows)
    }
  }

  # The answer prompt is budgeted as a whole. The read rows were fitted to all
  # of it and the skim evidence went in on top, which is exactly when the read
  # rows had filled it -- demotion only happens then -- so gr_call() cut the
  # reply's room (partial = FALSE, over an answer that could stop mid-sentence)
  # or refused the call. The evidence goes into the room the read rows leave,
  # whole, in document order; what does not fit is left out and counted.
  ev_dropped <- 0L
  if (!is.null(ev_skim) && nrow(ev_skim)) {
    room <- bud$input -
      if (length(keep_rows)) gr_count_tokens(render_chunks(d[keep_rows, , drop = FALSE])) else 0L
    need <- gr_count_tokens(sprintf("[chunk %d]\n%s", ev_skim$chunk_id, ev_skim$text))
    fits <- logical(length(need))
    for (i in seq_along(need)) {
      if (need[i] <= room) { fits[i] <- TRUE; room <- room - need[i] }
    }
    ev_dropped <- length(unlist(ev_rows[!fits], use.names = FALSE))
    ev_skim <- ev_skim[fits, , drop = FALSE]
  }

  ev_read <- if (length(keep_rows)) {
    evidence_table(d$chunk_id[keep_rows], reader_source_text(d)[keep_rows], d$page[keep_rows],
                   d$section[keep_rows], kind = "verbatim")
  } else NULL
  ev <- rbind_evidence(list(ev_read, ev_skim))

  # The plan is a first-class artifact, not a log line: what each section was
  # judged to be, and why. "Sections 3 and 5 were not read" is a finding about
  # the answer, and the audit report has to be able to show it.
  plan_tab <- data.frame(
    section = seq_len(n_units),
    label = vapply(units, function(rows) preview_label(d, rows), character(1)),
    chunks = vapply(units, length, integer(1)),
    tokens = vapply(units, function(rows) sum(d$tokens[rows]), integer(1)),
    treatment = treat, reason = reasons, stringsAsFactors = FALSE)
  rownames(plan_tab) <- NULL
  skipped_rows <- as.integer(unlist(units[treat == "skip"], use.names = FALSE))
  trace_note(trace, "preview.plan", list(
    sections = n_units, read = sum(treat == "read"), skimmed = sum(treat == "skim"),
    skipped = sum(treat == "skip"), demoted = length(demoted), degraded = degraded,
    tokens_read = sum(d$tokens[keep_rows]),
    tokens_skipped = sum(d$tokens[skipped_rows])))

  body <- paste(c(
    if (length(keep_rows)) render_chunks(d[keep_rows, , drop = FALSE]),
    if (!is.null(ev_skim) && nrow(ev_skim))
      paste(sprintf("[chunk %d]\n%s", ev_skim$chunk_id, ev_skim$text), collapse = "\n\n")
  ), collapse = "\n\n")

  # What some request was shown: the rows read and the sections a skim was sent
  # for. Every chunk, as it was, took in the sections the plan skipped, which no
  # model saw, so a citation of one could never be caught.
  sent <- unique(d$chunk_id[c(keep_rows, skim_sent)])

  if (!nzchar(trimws(body))) {
    # The same counts the ordinary return carries. Omitting them left
    # `notes$skipped` NULL on exactly the run where everything was skipped,
    # which is the run somebody inspecting that field is looking at.
    return(new_answer(.NOT_FOUND, "preview", question, integer(0), trace, partial = TRUE,
                      chunks_sent = sent,
                      notes = list(sections = n_units, plan = plan_tab,
                                   read = sum(treat == "read"), skimmed = sum(treat == "skim"),
                                   skipped = sum(treat == "skip"),
                                   demoted_to_skim = length(demoted), failed_calls = failed,
                                   degraded = degraded,
                                   tokens_skipped = sum(d$tokens[skipped_rows]),
                                   tokens_truncated = truncated, dropped_chunks = ev_dropped,
                                   reason = "the plan skipped every section, or every skim failed")))
  }

  res2 <- if (trace_can_call(trace)) {
    gr_call(client, answer_messages(question, body, cite = spec$cite, restate = spec$restate,
                                    premise = spec$premise),
            model = spec$model, max_output = spec$max_answer_tokens,
            temperature = spec$temperature, trace = trace, label = "preview.answer",
            effort = spec$effort)
  } else gr_result(FALSE, error = paste(cap_name(trace), "reached before the answer step"))
  if (usable_text(res2) && reply_cut_off(res2)) cut <- cut + 1L

  used <- unique(c(d$chunk_id[keep_rows], if (!is.null(ev_skim)) ev_skim$chunk_id))
  out <- premise_reply(if (usable_text(res2)) res2$text else .NOT_FOUND, spec$premise)
  # No answer, no evidence; see stuff.
  new_answer(out$text, "preview", question, used, trace, premise = out$premise,
             chunks_sent = sent, evidence = if (usable_text(res2)) ev,
             # A run that deliberately did not read part of the document is
             # partial in the sense the word carries everywhere else here: the
             # answer does not rest on everything that was available.
             # A truncated skim is the same kind of gap as a skipped section:
             # part of the document did not reach any model. It counts here for
             # the same reason `skip` does.
             partial = !res2$ok || failed > 0L || not_sent > 0L || any(treat == "skip") ||
               degraded || truncated > 0L || cut > 0L || ev_dropped > 0L,
             notes = list(sections = n_units, plan = plan_tab,
                          read = sum(treat == "read"), skimmed = sum(treat == "skim"),
                          skipped = sum(treat == "skip"), demoted_to_skim = length(demoted),
                          failed_calls = failed, truncated_calls = cut, degraded = degraded,
                          tokens_skipped = sum(d$tokens[skipped_rows]),
                          tokens_truncated = truncated, dropped_chunks = ev_dropped))
}
