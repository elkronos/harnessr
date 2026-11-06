# doc-synth-section.R: one section of a write-up, drafted from its claims.

#' Order claims by how much of the section they have earned.
#'
#' Breadth first -- a claim resting on nine studies says more about a literature
#' than one resting on one -- then the weight of the studies behind it. Contested
#' claims count their contradicting studies too: a disagreement across six
#' studies is more of the story than an agreement across two.
#' @noRd
claim_order <- function(claims, support, weights) {
  if (!nrow(claims)) return(integer(0))
  breadth <- claims$n_support + claims$n_contradict
  # A study with no weight is UNKNOWN, not weightless: it takes the mean of the
  # weights that ARE known across the table -- or 1, the middle of
  # study_weight()'s 0.5-1.5 scale, if none is. Imputing per claim instead gave a
  # claim whose every weight was missing the mean of nothing, NaN, which
  # sum(na.rm = TRUE) then made 0: the unknown-becomes-zero pattern this file
  # documents elsewhere. Unreachable today, because claims_verify() drops claims
  # citing studies outside the table first; kept honest because that is one
  # refactor away from being live.
  known <- weights[!is.na(weights)]
  neutral <- if (length(known)) mean(known) else 1
  mass <- vapply(claims$claim_id, function(id) {
    s <- support$study[support$claim_id == id]
    if (!length(s)) return(0)
    w <- unname(weights[as.character(s)])
    w[is.na(w)] <- neutral
    sum(w)
  }, numeric(1))
  order(-breadth, -mass, claims$claim_id)
}

# --- internals -------------------------------------------------------------

#' The system prompt for a closing section written from the gaps alone: the
#' closing section of a write-up from claims, when no claim was placed in it.
#' It is given no study, so it is told to name none.
#' @noRd
.gr_gaps_section_system <- paste0(
  "You write the '%s' section of a review: what the body of work it reviews does not cover. ",
  "You are given the gaps, computed by counting the studies' records, and no study records. ",
  "State those gaps in prose, grouping the ones that belong together, and say what each leaves ",
  "unanswered. Do not add a gap that is not listed, do not name or cite a study, and do not ",
  "guess at findings. Write prose for the section only -- no heading, no preamble, no closing ",
  "summary of what you just wrote.")

#' @noRd
synth_section <- function(heading, brief, question, rendered, used, client, spec, trace,
                          style = NULL, claims = NULL, claim_ids = integer(0),
                          weights = NULL, gaps = NULL, capped = NULL, gaps_cut = FALSE) {
  # With claims, the section argues a list of claims and sees only the studies
  # those claims rest on. Without, it sees every study and writes from rows --
  # which is what produces "Smith (2019) found X. Garcia (2022) found Y."
  by_claims <- !is.null(claims) && length(claim_ids)
  # The closing section of a write-up from claims, holding no claim, states the
  # gaps and reads no study. Written from rows, it was handed every study under
  # the row-by-row prompt: prose about each study under a heading meant for
  # what the studies leave out, and at scale nearly half the write-up's prompt
  # tokens. gr_synthesise() gives gaps to that section alone, and leaves it out
  # when there are none.
  gaps_only <- !is.null(claims) && !length(claim_ids) && is_nonblank(gaps)
  # Every study, rendered: a section written a few claims at a time sends each
  # batch its own rows from here.
  all_rows <- rendered
  if (by_claims) {
    cw <- claims$claims[claims$claims$claim_id %in% claim_ids, , drop = FALSE]
    want <- unique(claims$support$study[claims$support$claim_id %in% claim_ids])
    # Indexing the ALREADY-rendered blocks rather than re-rendering, so the
    # bibliographic columns stay hidden by exactly the same rule.
    rendered <- rendered[used$study %in% want]
    blocks <- render_claims(cw, claims$support, weights, collapse = FALSE)
    claim_block <- paste(blocks, collapse = "\n\n")
  } else if (gaps_only) {
    rendered <- character(0)
  }
  system_prompt <- if (by_claims) .gr_prompts$claims_section_system else
    if (gaps_only) sprintf(.gr_gaps_section_system, heading) else
      sprintf(.gr_prompts$synthesise_system, heading)
  # Appended rather than replacing: the register is how it is written, not what
  # it may say, and the rules above about citing and not inventing hold whatever
  # voice is asked for.
  if (is_nonblank(style)) system_prompt <- paste0(system_prompt, " Register: ", as_chr1(style))
  base <- paste0("Review question: ", question,
                 "\n\nSection: ", heading, "\nThis section must cover: ", brief)
  # The gaps are COMPUTED from the table, so the section may state these and
  # nothing else as a gap. That is the whole reason they are computed.
  gap_block <- if (!is_nonblank(gaps)) "" else
    paste0("\n\n<gaps>\n", as_chr1(gaps), "\n</gaps>\n",
           "State only the gaps listed above. Do not add others.")
  with_claims <- function(block) paste0(base, "\n\n<claims>\n", block, "\n</claims>", gap_block)
  ask <- if (by_claims) with_claims(claim_block) else paste0(base, gap_block)
  # The brief is repeated after the studies (see below), and a restatement that
  # is not in the overhead is a prompt that overruns the window by exactly its
  # length. `ask` itself is sent once, hence "never" there; the tail is counted
  # on its own because it restates the section brief, not the whole of `ask`.
  again <- paste0("write the '", heading, "' section, which must cover: ", brief)
  overhead <- prompt_overhead(ask, system_prompt, "never") +
    if (identical(as_chr1(spec$restate, "auto"), "never")) 0L else
      gr_count_tokens(paste0("\n\nAgain, the question: ", again))
  # No room for the section's own text is this section's problem, not the
  # run's. gr_budget() raised and nothing caught it, so a claims block larger
  # than the window aborted the write-up with every section before it already
  # written, and paid for, thrown away. NULL here is a section that cannot be
  # sent whole; with claims it is written a few claims at a time instead.
  bud <- tryCatch(gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead),
                  gr_budget_error = function(e) NULL)

  body <- paste(rendered, collapse = "\n\n")
  lost_batches <- 0L
  # A latch of this function's own, not `trace$budget_stop`. A refused merge
  # request in tree_merge() sets budget_stop while still returning usable text
  # -- so a run whose merge tripped the ceiling suppressed the warning for every
  # section after it, and those sections came back empty in silence.
  capped <- capped %||% new.env(parent = emptyenv())
  first_stop <- !isTRUE(capped$warned)
  capped_batches <- 0L
  # Replies that stopped at the reply limit. gr_call() keeps them ok = TRUE --
  # the text is what the model wrote -- so usable_text() accepts them, and a
  # section ending "However, the trial" came back complete.
  cut_off <- 0L
  merge_failed <- FALSE
  # Batch drafts the merge had to cut to fit before merging them.
  merge_cut <- 0L
  # The section's own text leaves no room for a study, and claims whose own
  # block of studies does not fit a prompt: neither can be written.
  too_large <- FALSE
  unwritable <- integer(0)
  # Studies a batch draft cited without being in its batch (or the merge cited
  # without any draft citing them), and studies a batch cited that it was
  # given. Only written in the batch path.
  batch_stray <- integer(0)
  batch_honest <- integer(0)
  # The studies each batch was sent, and whether its draft came back: what the
  # merged section is checked against below.
  batch_rows <- list()
  batch_read <- logical(0)
  # A section a limit stopped before any of it was written. Synthesis once
  # kept writing sections, one call each, after a run had hit `max_calls`; the
  # governor now refuses those requests, and an empty section is marked partial
  # below, which is the right outcome: the ceiling was the user's instruction.
  not_written <- function() {
    if (first_stop) {
      capped$warned <- TRUE
      gr_warn(sprintf(paste0("Section '%s' was not written: the run reached its call or cost ",
                             "ceiling first. It is marked partial, as is any later section the ",
                             "ceiling stops."), heading),
              class = "gr_synth_capped")
    }
    ""
  }
  text <- if (!is.null(bud) && gr_count_tokens(body) <= bud$input) {
    msgs <- list(
      list(role = "system", content = system_prompt),
      list(role = "user", content = ask))
    # The section's job again after the studies, for the same reason
    # answer_messages() asks last: over several thousand tokens of table, an
    # instruction given once at the top is a long way from where the writing
    # happens. A section written from the gaps alone has no studies to send.
    if (!gaps_only) {
      msgs[[3L]] <- list(role = "user", content = paste0("<studies>\n", body, "\n</studies>",
                                                         restate_tail(body, again, spec$restate)))
    }
    res <- gr_call(client, msgs, model = spec$model, max_output = spec$max_answer_tokens,
                   temperature = spec$temperature, trace = trace, label = "synthesise.section",
                   effort = spec$effort)
    if (is_refused(res)) not_written() else {
      if (usable_text(res) && reply_cut_off(res)) cut_off <- cut_off + 1L
      if (usable_text(res)) res$text else ""
    }
  } else {
    # Too many studies for one prompt: draft the section from batches and merge.
    # Cheaper alternatives -- take the first N rows, or summarise the table first
    # -- both drop studies without saying which, which is the one thing a review
    # may not do.
    #
    # With claims, a batch is some of the section's claims and the studies
    # behind them, not some of its studies under the whole claims block. The
    # block went into every batch as fixed overhead: batches shrank to a few
    # studies that each resent every claim, and past the window the section
    # could not be written at all.
    jobs <- if (by_claims) {
      room <- tryCatch(gr_budget(spec$model, reserve_output = spec$max_answer_tokens,
                                 overhead = prompt_overhead(with_claims(""), system_prompt,
                                                            "never"))$input,
                       gr_budget_error = function(e) NULL)
      if (is.null(room)) NULL else {
        cb <- claim_batches(blocks, claims$support, all_rows, room)
        unwritable <- attr(cb, "unwritable")
        lapply(cb, function(j) list(ask = with_claims(j$block), rows = j$rows))
      }
    } else if (!is.null(bud)) {
      groups <- synth_batches(rendered, bud$input)
      # Without claims `rendered` is every study in order, so a position in it
      # is a row of `used`.
      lapply(attr(groups, "index"), function(ix) list(ask = ask, rows = ix))
    }
    too_large <- is.null(jobs) || (!length(jobs) && !length(unwritable))
    parts <- vapply(jobs, function(j) {
      # Counted apart from a batch whose CALL failed. Both leave an empty part,
      # but "2 batches of studies failed" points at the model or the network,
      # and the cause here is the ceiling the caller set. `<<-` is right in this
      # nested function: it targets synth_section()'s frame, not the global one.
      res <- gr_call(client, list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = j$ask),
        list(role = "user", content = paste0("<studies>\n", paste(all_rows[j$rows], collapse = "\n\n"),
                                             "\n</studies>"))
      ), model = spec$model, max_output = spec$max_answer_tokens,
         temperature = spec$temperature, trace = trace, label = "synthesise.batch",
         effort = spec$effort)
      if (is_refused(res)) { capped_batches <<- capped_batches + 1L; return("") }
      # Kept for the merge, as the one-call section keeps its text: part of a
      # batch's draft beats none of it. Counted, so the section says it.
      if (usable_text(res) && reply_cut_off(res)) cut_off <<- cut_off + 1L
      if (usable_text(res)) res$text else ""
    }, character(1), USE.NAMES = FALSE)
    # tree_merge() strips empty pieces, so a merge over the survivors reads
    # exactly like a merge over everything -- and with one survivor it returns
    # that piece unchanged, ok = TRUE, without making a call. The studies in the
    # failed batch were then simply absent from the write-up, with nothing on
    # the section, on `partial` or in print() to say so.
    # `<-`, not `<<-`: an if/else block shares the enclosing frame, so `<<-`
    # here would have written to the global environment and left this one at 0.
    lost_batches <- sum(!nzchar(parts)) - capped_batches
    batch_rows <- lapply(jobs, function(j) used$study[j$rows])
    batch_read <- nzchar(parts)
    # Each batch draft checked against what IT was given -- its rows, and any
    # study its prompt names (the brief, the gaps, its claims' own block) --
    # before the merge makes one text of them. Checked against the whole
    # section, a draft citing a study it never saw passed as known, was
    # rendered and went into the reference list.
    for (b in seq_along(parts)) {
      ids <- cited_ids(parts[[b]], "study")
      given <- union(batch_rows[[b]], cited_ids(jobs[[b]]$ask, "study"))
      batch_stray <- c(batch_stray, setdiff(intersect(ids, used$study), given))
      batch_honest <- c(batch_honest, intersect(ids, given))
    }
    # The merge is shown the section's brief and the drafts. With claims, not
    # the claims block: that is what did not fit.
    merge_ask <- if (by_claims) paste0(base, gap_block) else ask
    from <- length(trace$steps) + 1L
    m <- if (!length(parts)) list(text = "", ok = FALSE) else
      tryCatch(tree_merge(client, merge_ask, parts, spec, trace, label = "synthesise.merge",
                          system_prompt = system_prompt, kind = "draft"),
               # The merge sizes its prompt as the section did. No room is a
               # merge that did not happen, not a write-up that stops.
               gr_budget_error = function(e) list(text = merge_giveup(parts[nzchar(parts)], spec),
                                                  ok = FALSE, error = conditionMessage(e)))
    # tree_merge() accepts a merge reply cut off at the limit as it accepts any
    # other, and returns only the text, so the steps it recorded are the one
    # place that says whether a merge -- the last one, or one at a level below
    # it that the last one merged from -- stopped short.
    cut_off <- cut_off + trace_cut_off(trace, from, "synthesise.merge")
    # A merge that failed hands back the batch drafts joined and capped. The
    # section is not the merged draft it stands in for, whether or not every
    # batch was read; when none was, the lost batches already say so.
    merge_failed <- length(parts) > 0L && !isTRUE(m$ok) &&
      lost_batches + capped_batches < length(parts)
    # A draft too long for the merge's prompt, or a merge group that failed and
    # was passed up whole, is cut to fit before the next merge, and what it said
    # past the cut is gone from a merge that otherwise succeeded.
    merge_cut <- if (isTRUE(m$ok)) as_int1(m$truncated, 0L) else 0L
    # m$text on failure carries tree_merge()'s own "[merge failed; findings
    # above are truncated]" marker. Throwing it away for a raw paste() of the
    # parts discarded the one thing that said the section was incomplete.
    merged <- if (isTRUE(m$ok)) m$text else
      as_chr1(m$text, paste(parts[nzchar(parts)], collapse = "\n\n"))
    # The merge is a call too, and it is shown the brief and the drafts and no
    # row of the table. A study it cites that no draft cited and the brief does
    # not name is one it never saw, by the same rule as a batch draft's.
    # Unchecked, "Also seen in [study 7]" added by the merge passed as known,
    # was rendered and went into the reference list, with the section complete.
    in_drafts <- unique(unlist(lapply(parts, cited_ids, word = "study"), use.names = FALSE))
    batch_stray <- c(batch_stray, setdiff(intersect(cited_ids(merged, "study"), used$study),
                                          union(in_drafts, cited_ids(merge_ask, "study"))))
    merged
  }

  cited <- cited_ids(text, "study")
  # A bracket that opens like a citation and does not parse as one --
  # "[studies 1 to 7]", "[study one]" -- names ids nothing here can check.
  # Counting it as citing nothing is how a fabricated study passed as clean.
  unparsed <- unparsed_citations(text, "study")
  # Checked against what this section was SHOWN. With claims it sees only the
  # studies behind its claims, and a number it could not have seen is, by this
  # file's own definition, a citation to something never supplied. Checked
  # against the whole table it passed: it counted as known, was rendered as an
  # author-year citation and went into the reference list. `unsupplied` is kept
  # apart from `unknown` because the row does exist, and "a row that does not
  # exist" would misdescribe it. A section written from the gaps is shown no
  # study but one the gaps name.
  shown <- if (by_claims) want else if (gaps_only) cited_ids(ask, "study") else used$study
  unknown <- setdiff(cited, used$study)
  unsupplied <- setdiff(intersect(cited, used$study), shown)
  # The same check per batch, for a section drafted in batches (see above),
  # counting only what survived the merge into the section's text. A study
  # another batch of this section cited honestly cannot be told apart once the
  # drafts are merged, so it is rendered, but counted and marked partial; one
  # no batch was given, or one the merge cited and no draft did, stays a
  # marker, as `unsupplied` does.
  stray <- intersect(unique(batch_stray), cited)
  leave <- union(unsupplied, setdiff(stray, batch_honest))
  unsupplied <- union(unsupplied, stray)
  known <- cited[cited %in% shown & !cited %in% leave]
  hits <- match(known, used$study)
  # The check in the other direction, which the citation check cannot make: a
  # section handed four claims and citing none of the studies behind one of them
  # did not write that claim up. The outline promised it would. A claim that
  # could not be sent at all is not written up whatever else cites its studies.
  missed <- if (!by_claims) integer(0) else {
    claim_ids[claim_ids %in% unwritable | !vapply(claim_ids, function(id) {
      any(claims$support$study[claims$support$claim_id == id] %in% known)
    }, logical(1))]
  }
  # And for a section drafted in batches without claims: a batch whose draft
  # came back and not one of whose studies the section cites. The merge folds
  # several drafts into one reply of the same length, and a merge that
  # finished normally but kept only the first draft's studies -- 69 of 1000 --
  # read as a complete section. Not with claims, where a claim is what must be
  # covered, and `missed` checks that.
  dropped <- if (by_claims || !length(batch_rows)) 0L else
    sum(batch_read & !vapply(batch_rows, function(r) any(r %in% cited), logical(1)))
  if (too_large) {
    gr_warn(sprintf(paste0("Section '%s' was not written: its brief%s alone leave%s no room in ",
                           "the model's window for a single study. It is marked partial; shorten ",
                           "the brief, or use a model with a larger window."),
                    heading, if (nzchar(gap_block)) " and gaps" else "",
                    if (nzchar(gap_block)) "" else "s"),
            class = "gr_synth_too_large")
  }
  if (length(unwritable)) {
    gr_warn(sprintf(paste0("Section '%s': claim %s could not be sent, because the list of studies ",
                           "behind %s alone does not fit the model's window. %s marked missed and ",
                           "the section partial."),
                    heading, paste(unwritable, collapse = ", "),
                    if (length(unwritable) == 1L) "it" else "each",
                    if (length(unwritable) == 1L) "It is" else "They are"),
            class = "gr_synth_too_large")
  }
  if (length(missed)) {
    gr_warn(sprintf(paste0("Section '%s' was given %d claim(s) and did not write up %d of them ",
                           "(claim %s). The section is marked partial."),
                    heading, length(claim_ids), length(missed),
                    paste(missed, collapse = ", ")),
            class = "gr_claims_missed")
  }
  if (lost_batches > 0L) {
    gr_warn(sprintf(paste0("Section '%s': %d batch(es) of studies failed, so the studies in ",
                           "them are missing from it. The section is marked partial."),
                    heading, lost_batches), class = "gr_synth_batch_failed")
  }
  if (capped_batches > 0L && first_stop) {
    capped$warned <- TRUE
    gr_warn(sprintf(paste0("Section '%s': %d batch(es) of studies were not read: the run ",
                           "reached its call or cost ceiling. The section is marked partial, as ",
                           "is any later section the ceiling stops."),
                    heading, capped_batches), class = "gr_synth_capped")
  }
  if (cut_off > 0L) {
    gr_warn(sprintf(paste0("Section '%s': %d repl%s stopped at the %d-token reply limit before ",
                           "finishing, so the section is incomplete. It is marked partial; raise ",
                           "`max_section_tokens`."),
                    heading, cut_off, if (cut_off == 1L) "y" else "ies", spec$max_answer_tokens),
            class = "gr_synth_truncated")
  }
  if (merge_failed) {
    gr_warn(sprintf(paste0("Section '%s': the batches of studies were drafted but not merged (%s), ",
                           "so the section is those drafts joined end to end, capped in length, ",
                           "rather than one account. It is marked partial."),
                    heading, as_chr1(m$error, "the merge failed")),
            class = "gr_synth_merge_failed")
  }
  if (merge_cut > 0L) {
    gr_warn(sprintf(paste0("Section '%s': %d batch draft(s) were too long for the merge and were ",
                           "cut to fit, so what they said past the cut is missing. It is marked ",
                           "partial."), heading, merge_cut),
            class = "gr_synth_merge_truncated")
  }
  if (dropped > 0L) {
    gr_warn(sprintf(paste0("Section '%s' was drafted in %d batches of studies and cites none of the ",
                           "studies in %d of them: merging the drafts into one reply of at most %d ",
                           "tokens left them out. It is marked partial; raise ",
                           "`max_section_tokens`, or narrow what the section covers."),
                    heading, length(batch_rows), dropped, spec$max_answer_tokens),
            class = "gr_synth_batch_dropped")
  }
  if (length(unparsed)) {
    gr_warn(sprintf(paste0("Section '%s' has %d citation(s) the check cannot read (%s), so the ",
                           "studies they name were not checked. The section is marked partial."),
                    heading, length(unparsed), paste(unparsed, collapse = ", ")),
            class = "gr_synth_unparsed")
  }
  list(
    row = data.frame(section = heading, brief = as_chr1(brief), text = as_chr1(text),
                     n_cited = length(known), n_unknown = length(unknown),
                     n_unsupplied = length(unsupplied),
                     n_unparsed = length(unparsed), n_truncated = cut_off,
                     # A section citing a row that is not in the table, or citing
                     # nothing at all, is not a section anyone should paste into a
                     # manuscript unread.
                     n_claims = length(claim_ids), claims_missed = length(missed),
                     # The causes the warnings above name, kept on the row so
                     # the audit report can name them too: without them it
                     # could say only that the section was marked partial.
                     lost_batches = as.integer(lost_batches),
                     capped_batches = as.integer(capped_batches),
                     merge_failed = isTRUE(merge_failed),
                     # `capped_batches` counts here as well as `lost_batches`.
                     # Separating the two for the MESSAGE removed the only thing
                     # that marked the section partial, so a section that
                     # silently dropped a quarter of the corpus read as complete
                     # while the warning said it had been marked partial.
                     partial = length(unknown) > 0L || length(unsupplied) > 0L ||
                       !nzchar(trimws(text)) || lost_batches > 0L || capped_batches > 0L ||
                       length(missed) > 0L || length(unparsed) > 0L || cut_off > 0L ||
                       merge_failed || merge_cut > 0L || dropped > 0L || too_large ||
                       isTRUE(gaps_cut),
                     stringsAsFactors = FALSE),
    # Which markers in THIS section must stay markers when the prose is rendered.
    unsupplied = leave,
    citations = if (!length(known)) NULL else
      data.frame(section = heading, study = known,
                 # A table with no `document` column is one gr_synthesise()
                 # accepts; indexing NULL gave a zero-length column, and the
                 # frame, and the run, failed.
                 document = if (is.null(used$document)) NA_character_ else
                   as.character(used$document[hits]),
                 # NOT as_chr1(): it collapses a vector to ONE string with
                 # newlines between the elements, so every citation row got the
                 # same value -- all the ids, glued together. It is for scalars.
                 document_id = if (is.null(used$document_id)) NA_character_ else
                   as.character(used$document_id[hits]),
                 stringsAsFactors = FALSE))
}

#' How many replies recorded from step `from` on, under a label starting with
#' `prefix`, stopped at the reply limit.
#'
#' For calls made inside a helper that returns only text, such as tree_merge():
#' the trace records every reply's finish reason, normalised by gr_result(), and
#' worker traces are folded in, so this counts the same with or without
#' parallel merge levels.
#' @noRd
trace_cut_off <- function(trace, from, prefix) {
  if (!inherits(trace, "gr_trace") || from > length(trace$steps)) return(0L)
  steps <- trace$steps[seq.int(from, length(trace$steps))]
  sum(vapply(steps, function(st) {
    startsWith(as_chr1(st$label), prefix) && identical(as_chr1(st$finish_reason, ""), "length")
  }, logical(1)))
}

#' The claims a section must argue, in the order they earned.
#'
#' The tier is a sentence budget, and it is the whole of step "emphasis": a claim
#' resting on nine studies and one resting on a single pilot were getting the
#' same space, which is a claim about the literature that the literature does not
#' support.
#'
#' `collapse = FALSE` gives one block per claim, in that order, with the ids in
#' `attr(, "claim_id")`: the tiers are set across the whole section first, so a
#' section written a few claims at a time gives each claim the room it earned
#' among all of them.
#' @noRd
render_claims <- function(cw, support, weights, collapse = TRUE) {
  ord <- claim_order(cw, support, weights)
  cw <- cw[ord, , drop = FALSE]
  # Labelled, as the brief they are pasted to is: a claim edited by hand under
  # a non-UTF-8 locale is unlabelled bytes, which paste() would escape.
  for (col in intersect(c("claim", "moderator", "scope"), names(cw))) {
    if (is.character(cw[[col]])) cw[[col]] <- mark_utf8(cw[[col]])
  }
  n <- nrow(cw)
  third <- max(1L, n %/% 3L)
  tier <- rep("one sentence", n)
  if (n <= 3L) {
    tier[] <- "two or three sentences"
  } else {
    tier[seq_len(third)] <- "two or three sentences"
    tier[seq(third + 1L, min(n, 2L * third))] <- "one or two sentences"
  }
  ids <- function(id, role) {
    v <- sort(support$study[support$claim_id == id & support$role == role])
    if (!length(v)) return(NULL)
    paste(sprintf("[study %d]", v), collapse = " ")
  }
  vapply(seq_len(n), function(i) {
    id <- cw$claim_id[i]
    paste(c(sprintf("[claim %d] (%s)", id, tier[i]),
            cw$claim[i],
            sprintf("supported by: %s", ids(id, "supports")),
            if (cw$n_contradict[i]) sprintf("contradicted by: %s", ids(id, "contradicts")),
            if (!is.na(cw$moderator[i])) sprintf("distinguished by: %s", cw$moderator[i]),
            if (cw$n_contradict[i] && is.na(cw$moderator[i]))
              "the disagreement is not explained by anything in the table",
            if (!is.na(cw$scope[i])) sprintf("scope: %s", cw$scope[i])),
          collapse = "\n")
  }, character(1), USE.NAMES = FALSE) -> blocks
  if (!collapse) return(structure(blocks, claim_id = cw$claim_id))
  paste(blocks, collapse = "\n\n")
}

#' Pack rendered studies into batches that fit `budget` input tokens.
#'
#' `max_n` caps the studies per batch, for a caller whose REPLY grows with the
#' batch (gr_claims()). `attr(, "index")` gives each batch's positions in
#' `rendered`, so a caller can say which studies a batch held -- which is what a
#' claim drawn from it may cite.
#' @noRd
synth_batches <- function(rendered, budget, max_n = Inf) {
  groups <- list(); index <- list(); buf <- character(0); at <- integer(0); tks <- 0L
  for (i in seq_along(rendered)) {
    p <- rendered[[i]]
    pt <- gr_count_tokens(p)
    if (length(buf) && (tks + pt > budget || length(buf) >= max_n)) {
      groups[[length(groups) + 1L]] <- buf; index[[length(index) + 1L]] <- at
      buf <- character(0); at <- integer(0); tks <- 0L
    }
    buf <- c(buf, p); at <- c(at, i); tks <- tks + pt
  }
  if (length(buf)) {
    groups[[length(groups) + 1L]] <- buf; index[[length(index) + 1L]] <- at
  }
  attr(groups, "index") <- index
  groups
}

#' Pack a section's claims into batches that each fit `budget` input tokens
#' together with the studies behind them.
#'
#' `blocks` is render_claims(collapse = FALSE): one block per claim, ranked.
#' In that order a claim joins the current batch while its block and the rows
#' it adds still fit, so a study behind several claims of one batch is sent
#' once, and each batch resends only its own claims. A claim too large for a
#' batch of its own goes out with its studies split over several batches,
#' each carrying its block; one whose block alone leaves no room comes back in
#' `attr(, "unwritable")`. Each batch is `block`, the text of its claims, and
#' `rows`, its study numbers, which are positions in `rendered`.
#' @noRd
claim_batches <- function(blocks, support, rendered, budget) {
  ids <- attr(blocks, "claim_id")
  # The blank line between blocks, and between rows.
  tb <- gr_count_tokens(blocks) + 2L
  tr <- gr_count_tokens(rendered) + 2L
  behind <- lapply(ids, function(id) sort(unique(support$study[support$claim_id == id])))
  out <- list()
  unwritable <- integer(0)
  cur <- integer(0); rows <- integer(0); cost <- 0
  flush <- function() {
    if (!length(cur)) return(invisible(NULL))
    block <- paste(blocks[cur], collapse = "\n\n")
    if (cost <= budget) {
      out[[length(out) + 1L]] <<- list(block = block, rows = rows)
    } else {
      # Only ever one claim: a second joins a batch only when it fits.
      room <- budget - tb[cur]
      if (room <= 0) {
        unwritable <<- c(unwritable, ids[cur])
      } else {
        g <- synth_batches(rendered[rows], room)
        for (ix in attr(g, "index")) out[[length(out) + 1L]] <<- list(block = block, rows = rows[ix])
      }
    }
    cur <<- integer(0); rows <<- integer(0); cost <<- 0
  }
  for (k in seq_along(ids)) {
    add <- function() tb[k] + sum(tr[setdiff(behind[[k]], rows)])
    if (length(cur) && cost + add() > budget) flush()
    cost <- cost + add()
    cur <- c(cur, k)
    rows <- sort(union(rows, behind[[k]]))
  }
  flush()
  attr(out, "unwritable") <- unwritable
  out
}
