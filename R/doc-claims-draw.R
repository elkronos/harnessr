# doc-claims-draw.R -- the layer between a table of studies and a write-up.
#
# WHY THIS FILE EXISTS
# `gr_synthesise()`'s unit is the SECTION, and sections come from an outline
# fixed before the reading. Each one is then drafted independently from the whole
# study table. Three things follow, and none of them can be repaired downstream:
#
#   1. The review's structure is the author's hypothesis rather than a finding.
#      Often the strongest sentence a review contains is structural -- "the
#      disagreement about effect size is really a disagreement about
#      measurement" -- and that can only come from the evidence.
#   2. Studies arrive as rows, so the model writes row by row: "Smith (2019)
#      found X. Garcia (2022) found Y." That enumeration is the clearest marker
#      of a weak review and it is a direct consequence of what the prompt holds.
#   3. Nothing computes relations between studies. Synthesis IS the claim about
#      relations, so without this layer "synthesise" concatenates.
#
# A claim here is checkable in exactly the way a citation already is. It names
# the studies it rests on, those numbers are verified against the table rather
# than trusted, and each study's values are backed by a quote that was checked
# against the page it came from. That extends the audit chain by one link --
# claim -> studies -> quotes -> pages -- instead of stepping around it.

#' What a claim is about.
#' @noRd
.gr_claim_kinds <- c("finding", "method", "measurement", "gap")

#' Every property is in `required`, the optional ones written as "string or
#' null" or as an array that may be empty. That is not style: the schema is sent
#' with `strict = TRUE`, and OpenAI refuses a strict schema whose `required`
#' leaves a property out, with a 400 that is not retried. Leaving out
#' `contradicted_by`, `moderator` and `scope` made every claims call on the
#' default client fail, and gr_claims() report that no claims came back.
#' @noRd
.gr_claims_schema <- list(
  type = "object", additionalProperties = FALSE,
  required = list("claims"),
  properties = list(claims = list(
    type = "array",
    items = list(
      type = "object", additionalProperties = FALSE,
      required = list("claim", "kind", "supported_by", "contradicted_by", "moderator", "scope"),
      properties = list(
        claim = list(type = "string",
                     description = paste0("One sentence about the LITERATURE, not about one ",
                                          "study. State it plainly, without citations.")),
        kind = list(type = "string", enum = as.list(.gr_claim_kinds),
                    description = paste0("'finding' for what was found, 'method' for how it was ",
                                         "studied, 'measurement' for how the construct was ",
                                         "defined, 'gap' for what is missing.")),
        supported_by = list(type = "array", items = list(type = "integer"),
                            description = paste0("The [study N] numbers that support it. Use only ",
                                                 "numbers shown. At least one.")),
        contradicted_by = list(type = "array", items = list(type = "integer"),
                               description = paste0("The [study N] numbers that contradict it, ",
                                                    "or an empty array if none do.")),
        moderator = list(type = c("string", "null"),
                         description = paste0("The FIELD NAME from the table that distinguishes ",
                                              "the supporting studies from the contradicting ",
                                              "ones, copied exactly, or null if nothing in the ",
                                              "table explains the split.")),
        scope = list(type = c("string", "null"),
                     description = paste0("How far the claim reaches: the populations, designs ",
                                          "or measures it holds for. Say so if it rests on one ",
                                          "study.")))))))

#' @noRd
.gr_reconcile_schema <- list(
  type = "object", additionalProperties = FALSE,
  required = list("groups"),
  properties = list(groups = list(
    type = "array",
    items = list(type = "array", items = list(type = "integer")),
    description = paste0("One array per distinct claim, holding the numbers of the listed ",
                         "claims that say the same thing. Every number exactly once."))))

#' The claims a table of studies supports
#'
#' Turns an extraction table into statements about the *literature*, each naming
#' the studies it rests on. It is the step that makes a write-up a synthesis
#' rather than an ordered recitation, and the step that lets a section be written
#' from an argument instead of from rows.
#'
#' @section What makes a claim checkable:
#' Every study number a claim names is verified against the table, exactly as a
#' `[study N]` marker in finished prose already is, and against the batch the
#' claim was drawn from: a claim may only name studies its call was shown. A
#' number that fails either is dropped and counted rather than trusted, a claim
#' left with no supporting study is dropped entirely, and a `moderator` naming a
#' column the model was not shown is cleared: it is an invented explanation for
#' a real disagreement. So is a moderator that does not tell the two sides of a
#' contested claim apart by counting: a column the table does not report for
#' the studies on one side, a value reported on both sides, or numbers whose
#' ranges overlap. `$dropped` records all of it, so a claims table that looks
#' thin can be told apart from a literature that is.
#'
#' The study numbers are the same ones [gr_synthesise()] cites, because both
#' derive them from one function. A claim resting on study 3 and a sentence
#' citing `[study 3]` point at the same row by construction.
#'
#' @section Corpora too large for one prompt:
#' The studies are batched, and claims are then reconciled across batches in one
#' further call that sees only the claim TEXTS. Without it a claim holding across
#' the whole corpus comes back once per batch with disjoint support, which reads
#' as several narrow claims instead of one broad one. The reconcile pass may only
#' group claims that already exist: every claim it fails to place stays on its
#' own rather than disappearing. When it cannot run -- a call or cost limit, a
#' failed or cut-off reply, a reply that is not a list of groups, or more claims
#' than fit one prompt -- the claims are kept unmerged, with a warning, and
#' `$unmerged` is `TRUE`.
#'
#' What the reconcile pass cannot check is MEANING. A merged claim keeps one
#' member's wording and the union of every member's studies, so if the model
#' groups two claims that say different things, the studies behind one are
#' listed as supporting the other's wording. Such a merge is not detectable by
#' counting; the merged claim's `note` names every other wording it absorbed so
#' that it can be seen, and a group mixing claims of different `kind` is warned
#' about.
#'
#' A batch is limited by the reply as well as by the context window, because the
#' reply names every study it uses: with the default `max_claim_tokens` a batch
#' holds about 30 studies. A batch whose reply is cut off, or whose call fails,
#' is reported with the number of studies it held rather than passed over.
#'
#' @param extraction A [gr_extract()] result, or a data frame shaped like its
#'   `$table`.
#' @param question The review question. Taken from `protocol` if omitted.
#' @param protocol A [gr_protocol()]; its `question` is used when `question` is
#'   not given.
#' @param client A [gr_client()]. One is built from `model` if omitted.
#' @param model,temperature,max_claim_tokens Passed to the model call.
#'   `max_claim_tokens` is the reply limit for each call, and it also sets how
#'   many studies go into one: about `(max_claim_tokens - 400) / 40`. Raise it
#'   for fewer, larger batches.
#' @param include_unclear Keep rows with nothing extracted. Off by default, the
#'   same as [gr_synthesise()].
#' @param trace A [gr_trace()] to add this stage's calls to, or `NULL`. The
#'   calls are recorded on a trace of the stage's own, returned as `$trace`,
#'   and folded into `trace` when the stage ends, as in [gr_read_many()] and
#'   [gr_synthesise()]. Its requests are held to the governor of `trace`, if
#'   it has one, less what `trace` has already spent (see [hr_governor()]).
#' @param bib Which columns carry bibliographic identity, as in
#'   [gr_synthesise()]: a named list of `citation`, `authors`, `year`, `title`,
#'   `venue`, `doi`. Those columns are withheld from the model, so a claim
#'   cannot attribute a finding to a name, and cannot be moderated by one.
#'   Omitted, only the conventional names are withheld. Pass the same `bib` to
#'   [gr_synthesise()] and [gr_gaps()].
#' @param effort Reasoning effort, or `NULL` (the default) to send none: one
#'   string, or a character vector named by stage, as `effort` in
#'   [gr_read_spec()]. The calls here are labelled `claims.draw` and
#'   `claims.reconcile`, so `c(claims = "high")` covers both. Drawing claims is
#'   judgement, the stage most worth a higher effort. The reasoning counts
#'   against the same reply limit, so a high effort can leave a batch's reply
#'   cut off, which is reported as such (`gr_claims_truncated`).
#' @return An object of class `gr_claims`:
#'   \describe{
#'     \item{`claims`}{One row per claim: `claim_id`, `claim`, `kind`,
#'       `moderator`, `scope`, `n_support`, `n_contradict`, `note`.}
#'     \item{`support`}{Long: `claim_id`, `study`, `role` (`"supports"` or
#'       `"contradicts"`). Join it to `$studies` to reach documents and quotes.}
#'     \item{`studies`}{The rows the claims were drawn from, numbered.}
#'     \item{`dropped`}{What verification removed, and why.}
#'     \item{`partial`}{`TRUE` when some studies contributed nothing because
#'       their batch was cut off at the reply limit, failed, or was not sent
#'       for a call or cost limit.}
#'     \item{`lost`}{The study numbers of those studies.}
#'     \item{`unmerged`}{`TRUE` when claims from several batches could not be
#'       reconciled, so one finding may appear as more than one claim.}
#'     \item{`hidden`}{The columns withheld from the model as bibliographic.}
#'   }
#' @seealso [gr_outline()] to derive sections from these claims,
#'   [gr_synthesise()] to write from them, [gr_gaps()] for what they do not
#'   cover, [gr_protocols()] for the `claims` schema they want as input
#' @export
#' @examples
#' tab <- data.frame(
#'   document = c("a.pdf", "b.pdf"), status = "ok", duplicate_of = NA_character_,
#'   n_filled = 2L, n_unverified = 0L, conflicts = NA_character_,
#'   design = c("randomised trial", "cross-sectional"),
#'   finding = c("supports", "contradicts"), stringsAsFactors = FALSE)
#'
#' cl <- gr_mock_client(function(messages, params) paste0(
#'   '{"claims":[{"claim":"The effect appears in trials but not in surveys.",',
#'   '"kind":"finding","supported_by":[1],"contradicted_by":[2],',
#'   '"moderator":"design","scope":"one trial, one survey"}]}'))
#'
#' cm <- gr_claims(tab, question = "Does it work?", client = cl)
#' cm$claims[, c("claim", "moderator", "n_support", "n_contradict")]
#' cm$support
gr_claims <- function(extraction, question = NULL, protocol = NULL, client = NULL,
                      model = NULL, temperature = NULL, max_claim_tokens = 1600L,
                      include_unclear = FALSE, trace = NULL, bib = NULL, effort = NULL) {
  tab <- if (inherits(extraction, "gr_extraction")) extraction$table else extraction
  if (!is.data.frame(tab) || !nrow(tab)) {
    gr_abort("`extraction` must be a gr_extraction, or a data frame shaped like its $table.",
             class = "gr_no_studies")
  }
  if (!is.null(protocol)) {
    if (!inherits(protocol, "gr_protocol")) {
      gr_abort("`protocol` must come from gr_protocol().", class = "gr_bad_protocol")
    }
    check_protocol_edited(protocol, "draw claims against it")
    if (is.null(question)) question <- protocol$question
  }
  # Labelled UTF-8 here, where it enters. Under a non-UTF-8 locale a question
  # typed in a script is UTF-8 bytes marked "unknown"; it is kept on the
  # result, and gr_outline() and gr_synthesise() paste it to labelled text,
  # which paste() answers by escaping it to "<c3><a9>".
  if (is.character(question)) question <- mark_utf8(question)
  if (!is_nonblank(question)) {
    gr_abort(paste0("`question` must be a non-empty string. A claim is a statement about the ",
                    "literature RELATIVE TO a question, and without one there is nothing for a ",
                    "study to support or contradict."),
             class = "gr_no_question")
  }

  used <- synth_studies(tab, include_unclear)
  client <- client %||% gr_client(model = model %||% gr_options("model"))
  # This function's own default, range check and name, not gr_read_spec()'s;
  # and the budget reserves what the spec settled on. Passed through raw, an NA
  # reached gr_budget() as the output reserve while the spec said 1500.
  max_claim_tokens <- clamp_warn(na_default(max_claim_tokens, 1600L, "max_claim_tokens"),
                                 16, 1e6, "max_claim_tokens")
  spec <- gr_read_spec("stuff", model = model, temperature = temperature,
                       max_answer_tokens = max_claim_tokens, effort = effort)
  # One model for the batch sizing and the requests. Left NULL, gr_budget()
  # sized batches for gr_options("model") while gr_call() asked the client's.
  spec <- resolve_read_model(spec, client)
  # The rule every corpus stage follows (as_parent_trace()): a given trace is
  # the parent this stage's accounting is folded into, and the stage records on
  # a trace of its own. Recording on the given trace charged an earlier stage's
  # calls against this one's call limit, so claims drawn after a large
  # screening came back empty and marked partial, and `$trace` reported the
  # whole review's cost as the claims'.
  parent <- as_parent_trace(trace)
  # Held to the parent's governor, less what the parent has spent, as in
  # gr_read_many() and gr_synthesise(). Without it the stage read the limits
  # from gr_options() and a governor's allowed models, spending limit and
  # token limit did not hold for its requests.
  trace <- gr_trace(meta = list(stage = "claims", question = question,
                                studies = nrow(used)),
                    governor = fork_governor(parent))
  # on.exit, so calls made before an error still reach the parent.
  if (!is.null(parent)) on.exit(trace_absorb(parent, trace), add = TRUE)

  # Same withholding as the write-up: a model that can see who wrote a study
  # will attribute to the name rather than to the number, and a claim attributed
  # to a name is checked by nothing. With the write-up's `bib` too: without it a
  # `first_author` column reached this model, came back inside claim text and as
  # a moderator, and gr_synthesise(bib =) then pasted both into a prompt whose
  # studies block had withheld that column.
  hidden <- unlist(bib_columns(used, bib), use.names = FALSE)
  rendered <- render_studies(used, hide = hidden)
  # "never": claims_batch() sends the question once.
  overhead <- prompt_overhead(question, .gr_prompts$claims_system, "never")
  bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)
  # Sized by what comes BACK as well as by what goes in. The reply names every
  # study it uses and carries a claim, a scope and a moderator per claim, so it
  # grows with the batch while `max_claim_tokens` stays where it is. Sized by the
  # input window alone, a 128k model put 300 studies in one call with a
  # 1600-token reply; the JSON was cut off, did not parse, and every study in
  # the batch contributed nothing.
  groups <- synth_batches(rendered, bud$input, max_n = claims_per_batch(bud$output))
  index <- attr(groups, "index")

  raw <- list()
  not_sent <- 0L
  unsent <- integer(0)
  failed <- integer(0)
  cut_off <- integer(0)
  for (g in seq_along(groups)) {
    if (length(groups) > 1L) gr_msg(sprintf("Claims from batch %d of %d.", g, length(groups)))
    b <- claims_batch(groups[[g]], question, client, spec, trace, shown = used$study[index[[g]]])
    # A batch a limit stopped is not a batch the model found nothing in.
    if (identical(b$status, "not_sent")) {
      not_sent <- not_sent + 1L
      unsent <- c(unsent, g)
      next
    }
    if (identical(b$status, "cut_off")) cut_off <- c(cut_off, g)
    if (identical(b$status, "failed")) failed <- c(failed, g)
    raw[[g]] <- b$rows
  }
  if (not_sent > 0L) {
    gr_warn(sprintf(paste0("%d of %d batch(es) of studies were not sent: the run reached its %s. ",
                           "The studies in them contribute no claims. Raise the limit and run ",
                           "gr_claims() again."),
                    not_sent, length(groups), cap_name(trace)),
            class = "gr_claims_capped")
  }
  # A batch that was sent and came back with nothing usable. With one batch this
  # was only "every call failed"; with several, the survivors' claims hid the
  # loss entirely, and a review was written from the leftover batch.
  lost <- c(cut_off, failed)
  # The studies that contributed nothing, on the result as well as in the
  # warnings: a claims table missing a third of the corpus otherwise looks
  # exactly like a complete one to anything that reads it later.
  lost_studies <- sort(used$study[unlist(index[c(unsent, lost)], use.names = FALSE)])
  lost_msg <- if (!length(lost)) NULL else sprintf(paste0(
    "%d of %d batch(es) of studies, holding %d of %d studies, returned nothing usable (%s), ",
    "so those studies contribute no claims."),
    length(lost), length(groups), length(unlist(index[lost])), nrow(used),
    paste(c(if (length(cut_off)) sprintf(paste0(
              "%d cut off at the %d-token reply limit before the JSON closed; raise ",
              "`max_claim_tokens`"), length(cut_off), spec$max_answer_tokens),
            if (length(failed)) sprintf("%d call(s) failed", length(failed))),
          collapse = "; "))
  got <- do.call(rbind, raw[!vapply(raw, is.null, logical(1))])
  if (is.null(got) || !nrow(got)) {
    gr_warn(paste0("No claims came back. ",
                   if (not_sent == length(groups)) sprintf("No batch was sent: the run had reached its %s. ",
                                                           cap_name(trace))
                   else if (length(lost)) paste0(lost_msg, " ")
                   else "The model returned none. ",
                   "There is nothing for gr_outline() or gr_synthesise(claims = ) to work from."),
            class = "gr_no_claims")
    return(new_claims(empty_claim_rows(), used, question, empty_dropped(), trace, lost_studies,
                      hidden = hidden))
  }
  if (length(lost)) {
    gr_warn(lost_msg, class = if (length(cut_off)) c("gr_claims_truncated", "gr_claims_batch_failed")
                              else "gr_claims_batch_failed")
  }

  # The columns the model was SHOWN, not every column in the table. The moderator
  # check used the reserved-field list, which leaves the bibliographic columns in
  # -- so a claim could name `year` as the moderator of a disagreement, be
  # accepted, and carry an explanation drawn from a column render_studies()
  # withheld precisely so it could not be used. An invented explanation for a
  # real disagreement is the most convincing error this layer can make.
  checked <- claims_verify(got, used, cols = study_fields(used, hide = hidden))
  if (!nrow(checked$claims)) {
    gr_warn(paste0("Every claim was dropped in verification; see `$dropped`. The usual cause is ",
                   "a model citing study numbers that are not in the table."),
            class = "gr_no_claims")
    return(new_claims(empty_claim_rows(), used, question, checked$dropped, trace, lost_studies,
                      hidden = hidden))
  }
  # Claims can repeat only across batches that returned some.
  final <- if (sum(vapply(raw, function(r) NROW(r) > 0L, logical(1))) > 1L) {
    claims_reconcile(checked$claims, question, client, spec, trace)
  } else checked$claims
  # A merge changes which studies sit on each side of a claim, so a moderator
  # that told a member's two sides apart may not tell the merged claim's apart.
  # Checked again on what is actually returned.
  again <- claims_moderators(final, used)
  new_claims(again$claims, used, question, rbind(checked$dropped, again$dropped), trace,
             lost_studies, hidden = hidden, unmerged = isTRUE(attr(final, "unmerged")))
}

#' What a claims reply costs, for sizing batches by it.
#'
#' A base for the JSON around the claims plus a share per study: each study is
#' named at least once, and every few studies carry a claim sentence, a scope
#' and a moderator. Deliberately generous. A batch too large for its reply is
#' lost whole, while a batch smaller than it needed to be costs one more call.
#' @noRd
.gr_claims_reply_tokens <- c(base = 400L, per_study = 40L)

#' How many studies one claims call can take and still answer in `reply` tokens.
#' @noRd
claims_per_batch <- function(reply) {
  max(1L, as.integer(floor((reply - .gr_claims_reply_tokens[["base"]]) /
                             .gr_claims_reply_tokens[["per_study"]])))
}

#' What a reconcile reply for `n` claims can take: every claim number once, with
#' its comma and the brackets of its group. About two tokens a claim; six, to be
#' generous, since a reply cut off here leaves every claim unmerged.
#' @noRd
reconcile_reply_tokens <- function(n) {
  as.integer(200L + 6L * n)
}

#' What went wrong with a call that returned nothing usable, as a phrase
#' following "the ... call".
#'
#' Three causes that need three different remedies. gr_call() shrinks the reply
#' to whatever the context window leaves after the prompt, so a long prompt is
#' cut off BELOW the limit it asked for, and "raise the limit" was advice that
#' could not help. `knob` names the argument that raises `cap`. `problem` is
#' gr_call_json()'s reason for refusing a reply that did arrive, which says
#' what to look at where "failed" alone does not.
#' @noRd
call_failure <- function(result, messages, model, cap, knob, problem = NULL) {
  if (reply_cut_off(result)) {
    info <- gr_model_info(model)
    prompt <- sum(gr_count_tokens(vapply(messages, function(m) as_chr1(m$content), character(1))))
    room <- as.integer(info$context_window - prompt - 32L)
    if (room < min(cap, info$max_output)) {
      return(sprintf(paste0("stopped short: its %d-token prompt left about %d tokens for the ",
                            "reply in '%s''s %d-token context window"),
                     prompt, max(room, 0L), as_chr1(model), as.integer(info$context_window)))
    }
    return(sprintf("stopped at the %d-token reply limit (raise %s)",
                   as.integer(min(cap, info$max_output)), knob))
  }
  # After the cut-off test: a reply stopped at the cap is also not JSON, and
  # the remedy for it is the limit, not the schema.
  if (isTRUE(result$ok) && length(problem)) {
    problem <- as_chr1(problem)
    return(if (problem %in% c("not JSON", "not an object")) "returned a reply that was not a JSON object"
           else sprintf("returned a reply that does not fit its schema (%s)",
                        substr(problem, 1L, 200L)))
  }
  err <- as_chr1(result$error, "")
  if (nzchar(err)) sprintf("failed (%s)", substr(err, 1L, 200L)) else "failed"
}

#' One claims call over one batch of studies.
#'
#' Returns the rows and how the call went: "ok" (which may be no claims at
#' all), "cut_off" (the reply stopped at the limit and the JSON never closed) or
#' "failed". The caller has to tell those apart, because a batch the model
#' found nothing in and a batch whose answer was lost look identical as rows.
#' `shown` is the study numbers in the batch, which is what its claims may cite.
#' @noRd
claims_batch <- function(block, question, client, spec, trace, shown = NULL) {
  res <- gr_call_json(client, list(
    list(role = "system", content = .gr_prompts$claims_system),
    list(role = "user", content = paste0("Review question: ", question)),
    list(role = "user", content = paste0("<studies>\n", paste(block, collapse = "\n\n"),
                                         "\n</studies>"))
  ), schema = .gr_claims_schema, schema_name = "claims", model = spec$model,
     max_output = spec$max_answer_tokens, temperature = spec$temperature,
     trace = trace, label = "claims.draw", effort = spec$effort)
  if (is_refused(res$result)) return(list(rows = NULL, status = "not_sent"))
  if (!isTRUE(res$ok)) {
    return(list(rows = NULL, status = if (reply_cut_off(res$result)) "cut_off" else "failed"))
  }
  rows <- claim_rows(json_field(res$value, "claims", scalar = FALSE))
  if (!is.null(rows) && !is.null(shown)) rows$.shown <- rep(list(as.integer(shown)), nrow(rows))
  list(rows = rows, status = "ok")
}

#' Normalise whatever jsonlite made of the reply into a flat frame.
#'
#' `simplifyVector = TRUE` is not type-stable for an array of arrays: with equal
#' lengths it produces a MATRIX, with unequal lengths a list, and with a single
#' element a bare vector. A caller that assumes any one of those is broken by the
#' other two, and the failure is silent -- the ids come out transposed or
#' recycled rather than absent.
#' @noRd
as_id_list <- function(x, n) {
  out <- rep(list(integer(0)), n)
  if (is.null(x) || !n) return(out)
  pick <- function(v) {
    v <- suppressWarnings(as.integer(unlist(v, use.names = FALSE)))
    v <- v[!is.na(v)]
    unique(v)
  }
  if (is.matrix(x)) {
    for (i in seq_len(min(n, nrow(x)))) out[[i]] <- pick(x[i, ])
    return(out)
  }
  if (is.list(x)) {
    for (i in seq_len(min(n, length(x)))) out[[i]] <- pick(x[[i]])
    return(out)
  }
  # One id per claim, arriving as a plain vector.
  v <- suppressWarnings(as.integer(x))
  for (i in seq_len(min(n, length(v)))) out[[i]] <- if (is.na(v[i])) integer(0) else v[i]
  out
}

#' @noRd
claim_rows <- function(x) {
  # Exact reads throughout: this is a model's reply, and `$` let `claim_draft`
  # answer for `claim` and `headings` answer for `heading` -- a key the schema
  # never defined producing a real row.
  fx <- function(o, nm) o[[nm, exact = TRUE]]
  if (is.null(x)) return(NULL)
  # A single claim can arrive as a bare named list rather than a one-row frame.
  if (!is.data.frame(x) && is.list(x) && !is.null(names(x))) x <- list(x)
  # Anything else the reply might be. A JSON array of strings parses to a list
  # of CHARACTERS, and `e$claim` on a character vector is an error, not a miss:
  # `$ operator is invalid for atomic vectors` came out of gr_claims() as a crash
  # rather than as "no claims came back". A bare vector reached the frame branch
  # and died in rep(NA, nrow(x)) on a NULL nrow.
  if (!is.data.frame(x) && !is.list(x)) return(NULL)
  if (is.list(x) && !is.data.frame(x)) {
    x <- x[vapply(x, function(e) is.list(e) && !is.null(names(e)), logical(1))]
    if (!length(x)) return(NULL)
    flat <- lapply(x, function(e) list(
      claim = as_chr1(fx(e, "claim")), kind = as_chr1(fx(e, "kind"), "finding"),
      moderator = as_chr1(fx(e, "moderator"), NA_character_), scope = as_chr1(fx(e, "scope"), NA_character_),
      supported_by = list(as_id_list(list(fx(e, "supported_by")), 1L)[[1]]),
      contradicted_by = list(as_id_list(list(fx(e, "contradicted_by")), 1L)[[1]])))
    x <- do.call(rbind, lapply(flat, function(e) data.frame(
      claim = fx(e, "claim"), kind = fx(e, "kind"), moderator = fx(e, "moderator"), scope = fx(e, "scope"),
      stringsAsFactors = FALSE)))
    sup <- lapply(flat, function(e) fx(e, "supported_by")[[1]])
    con <- lapply(flat, function(e) fx(e, "contradicted_by")[[1]])
  } else {
    n <- nrow(x)
    sup <- as_id_list(fx(x, "supported_by"), n)
    con <- as_id_list(fx(x, "contradicted_by"), n)
    # `%||%` on `claim` as well as the rest: a reply in which NO object carries
    # it gave vapply() a NULL, which is character(0), and data.frame() then died
    # with "arguments imply differing number of rows: 0, 2" instead of warning
    # that no claims came back.
    x <- data.frame(claim = vapply(fx(x, "claim") %||% rep(NA, n), as_chr1, character(1),
                                   USE.NAMES = FALSE),
                    kind = vapply(fx(x, "kind") %||% rep("finding", n), as_chr1, character(1),
                                  USE.NAMES = FALSE),
                    moderator = vapply(fx(x, "moderator") %||% rep(NA, n), as_chr1, character(1),
                                       USE.NAMES = FALSE),
                    scope = vapply(fx(x, "scope") %||% rep(NA, n), as_chr1, character(1),
                                   USE.NAMES = FALSE),
                    stringsAsFactors = FALSE)
  }
  if (is.null(x) || !nrow(x)) return(NULL)
  x$moderator[!nzchar(x$moderator)] <- NA_character_
  x$scope[!nzchar(x$scope)] <- NA_character_
  x$.support <- sup
  x$.contradict <- con
  # A claim with no text is not a claim. It used to survive to claims_verify(),
  # which drops it only if it also has no supporting study -- so an entry that
  # was all ids and no sentence became a row in `$claims` with an empty claim,
  # and gr_outline() then wrote a section arguing it. outline_rows() has always
  # dropped blank headings; this is the same rule one file over.
  x <- x[nzchar(trimws(fx(x, "claim"))), , drop = FALSE]
  if (!nrow(x)) return(NULL)
  x
}

#' Group claims that say the same thing, across batches.
#'
#' The model is shown the claim TEXTS only -- no studies, no numbers to cite --
#' so it cannot invent a claim here, and every study a merged claim names was
#' verified before this ran. What it CAN do is group badly: a group's support
#' is the union of its members', under one member's wording, so two claims
#' that say different things grouped together list each other's studies as
#' support. Nothing here can check meaning, so the merged claim's `note` names
#' every other wording it absorbed, and a group mixing kinds is warned about.
#' A claim the reply fails to place keeps its own group, because dropping one
#' silently is the failure this whole file is built to avoid.
#'
#' Whenever the claims come back unmerged for a reason other than "nothing to
#' merge", the result carries `attr(, "unmerged") = TRUE`, which gr_claims()
#' records on the object.
#' @noRd
claims_reconcile <- function(claims, question, client, spec, trace) {
  n <- nrow(claims)
  if (n < 2L) return(reindex_claims(claims))
  unmerged <- function(why, class = "gr_claims_unmerged") {
    gr_warn(sprintf(paste0("Claims from different batches were not merged: %s, so one finding can ",
                           "appear as more than one claim."), why),
            class = class)
    out <- reindex_claims(claims)
    attr(out, "unmerged") <- TRUE
    out
  }
  listed <- paste(sprintf("%d. %s", seq_len(n), claims$claim), collapse = "\n")
  # Sized by the claims, as the draw is sized by its studies: the reply names
  # every claim once, so a fixed limit cut off the reply for a large corpus and
  # every claim came back unmerged. gr_call() clamps it to what the model can emit.
  cap <- max(as.integer(spec$max_answer_tokens), reconcile_reply_tokens(n))
  msgs <- list(
    list(role = "system", content = .gr_prompts$reconcile_system),
    list(role = "user", content = paste0("Review question: ", question)),
    list(role = "user", content = paste0("<claims>\n", listed, "\n</claims>")))
  res <- gr_call_json(client, msgs, schema = .gr_reconcile_schema, schema_name = "claim_groups",
                      model = spec$model, max_output = cap, temperature = spec$temperature,
                      trace = trace, label = "claims.reconcile", effort = spec$effort)
  if (is_refused(res$result)) {
    return(unmerged(sprintf("the run reached its %s", cap_name(trace)), class = "gr_claims_capped"))
  }
  if (!isTRUE(res$ok)) {
    # Said, as the capped case above is. Batches sized by their reply make this
    # pass the normal route for a large corpus, and its reply names every claim.
    return(unmerged(sprintf("the reconcile call %s", call_failure(res$result, msgs, spec$model, cap,
                                                                  "`max_claim_tokens`",
                                                                  res$problem))))
  }

  raw <- json_field(res$value, "groups", scalar = FALSE)
  # A flat array, `{"groups":[1,2,3]}`, is not one group of three: it is a reply
  # that ignored the schema. gr_call_json() now refuses such a reply, so this
  # guards only against the schema and this reader drifting apart. Read as one
  # group it merged every claim into the longest one's wording and handed it
  # every study, opposite findings included. Equal-length groups arrive as a
  # matrix and ragged ones as a list, so a bare vector is only ever this.
  if (!is.null(raw) && !is.list(raw) && !is.matrix(raw)) {
    return(unmerged("the reconcile reply was a flat list of numbers, not a list of groups"))
  }
  g <- as_id_list(raw, if (is.matrix(raw)) nrow(raw) else length(raw))
  # Defence in depth, not load-bearing: `claims[c(1, 99), ]` yields a row of NAs
  # rather than an error, and the merge below happens to absorb it -- nchar(NA)
  # loses to any real claim text and NULL support unions to nothing. Mutating
  # this line away changes no output today. It stays because the next change to
  # the merge would not be so lucky, and because a reply naming a claim that was
  # never listed should not reach that code at all.
  g <- lapply(g, function(v) v[v >= 1L & v <= n])
  g <- g[vapply(g, length, integer(1)) > 0L]
  # A claim in two groups would be merged twice and counted twice.
  seen <- integer(0)
  clean <- list()
  for (v in g) {
    v <- setdiff(v, seen)
    if (!length(v)) next
    seen <- c(seen, v)
    clean[[length(clean) + 1L]] <- v
  }
  missed <- setdiff(seq_len(n), seen)
  if (length(missed)) {
    for (i in missed) clean[[length(clean) + 1L]] <- i
    gr_msg(sprintf("%d claim(s) were not placed by the reconcile pass and kept their own group.",
                   length(missed)))
  }
  # A finding, a method and a gap cannot "say the same thing"; a group mixing
  # them is the model grouping by topic, and the merged claim keeps one kind.
  mixed <- vapply(clean, function(v) length(unique(claims$kind[v])) > 1L, logical(1))
  if (any(mixed)) {
    gr_warn(sprintf(paste0("The reconcile pass merged claims of different kinds into %d claim(s); ",
                           "a merged claim keeps one wording and every member's studies. Their ",
                           "`note` names the wordings merged in."), sum(mixed)),
            class = "gr_claims_merged")
  }
  merged <- lapply(clean, function(v) {
    first <- claims[v[1], , drop = FALSE]
    # The longest text, because a claim stated over more studies is usually
    # stated more fully, and the support is the union either way.
    keep <- which.max(nchar(claims$claim[v]))
    first$claim <- claims$claim[v][keep]
    # Every other wording, so a merge can be read back. Without it one claim
    # absorbing an opposite one ("did not improve symptoms" taking in "improved
    # symptoms") left the first claim's studies supporting the second's words,
    # with nothing anywhere to show that a merge had happened.
    norm <- function(s) lower_text(gsub("[[:space:]]+", " ", trimws(s)))
    others <- unique(claims$claim[v][-keep])
    others <- others[norm(others) != norm(first$claim)]
    absorbed <- if (length(others)) sprintf("merged with: %s", paste(sprintf(
      "'%s'", others), collapse = "; ")) else NULL
    mods <- stats::na.omit(claims$moderator[v])
    first$moderator <- if (length(mods)) mods[1] else NA_character_
    sc <- stats::na.omit(claims$scope[v])
    first$scope <- if (length(sc)) sc[which.max(nchar(sc))] else NA_character_
    sup <- sort(unique(unlist(claims$.support[v], use.names = FALSE)))
    con <- sort(unique(unlist(claims$.contradict[v], use.names = FALSE)))
    # A study that supported one member of this group and contradicted another
    # is a DISAGREEMENT, and the setdiff below files it on the supporting side.
    # Silently: `n_contradict` went 1 -> 0 with nothing in `note`, so a merge
    # manufactured consensus that no study agreed to. The study still belongs on
    # the supporting side -- it does support the merged wording -- but the reader
    # has to be told, because this is exactly the kind of loss the claims layer
    # exists to make visible.
    flipped <- intersect(con, sup)
    nts <- c(stats::na.omit(claims$note[v]), absorbed)
    if (length(flipped)) {
      nts <- c(nts, sprintf(paste0("study %s contradicted a claim merged into this one; ",
                                   "kept as supporting"), paste(flipped, collapse = ", ")))
    }
    first$note <- if (length(nts)) paste(unique(nts), collapse = "; ") else NA_character_
    first$.support <- list(sup)
    first$.contradict <- list(setdiff(con, sup))
    first
  })
  reindex_claims(do.call(rbind, merged))
}

#' @noRd
reindex_claims <- function(claims) {
  claims$claim_id <- seq_len(nrow(claims))
  rownames(claims) <- NULL
  claims
}

#' @noRd
empty_claim_rows <- function() {
  out <- data.frame(claim = character(0), kind = character(0), moderator = character(0),
                    scope = character(0), note = character(0), claim_id = integer(0),
                    stringsAsFactors = FALSE)
  out$.support <- list(); out$.contradict <- list()
  out
}
