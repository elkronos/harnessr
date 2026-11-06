# doc-synth-batch.R -- the write-up, one section at a time, from the table.
#
# WHY THIS FILE EXISTS
# An extraction table is the finding; a review is the account of it. Asking a
# model for that account in one call over two hundred studies is the version that
# does not work: it overflows, and long before it overflows it starts writing
# fluently about studies it has stopped attending to.
#
# So the unit is the SECTION, and it comes from the protocol's outline rather
# than from the model's sense of how a review is structured. Each section is one
# call, over the table, against a brief the author wrote in advance. That makes
# the write-up reproducible section by section, revisable a section at a time,
# and -- because the outline is fixed before the reading -- not shaped by what
# happened to be found.
#
# EVERY CLAIM CITES A ROW. Sections are written with `[study 3]` markers, the
# markers are parsed back out, and any pointing at a row that does not exist --
# or at a row the call that wrote it was not shown (with claims, or a section
# drafted in batches) -- is reported and marks the section partial. This is the
# same check `new_answer()`
# runs on `[chunk 3]`, for the same reason: a citation to something that was
# never supplied is a fabrication, and the most convincing kind there is.
#
# The chain it completes: a sentence cites a study, the study's row cites a
# quote, the quote was checked against the page it is attributed to. Nothing here
# proves the SENTENCE is true. It makes every step of the way back to the
# document short enough to walk.

#' Write a review from an extraction table
#'
#' The last stage. Takes what [gr_extract()] found and writes it up section by
#' section, against an outline fixed in advance, with every section citing the
#' rows it rests on.
#'
#' @param extraction A `gr_extraction` from [gr_extract()], or a data frame
#'   shaped like its `$table`.
#' @param protocol A [gr_protocol()]; its `outline` and `question` are used
#'   unless you give them directly.
#' @param outline The sections, as a named character vector: names are headings,
#'   values say what that section has to cover. As [gr_protocol()]. A heading
#'   with a blank brief is dropped, unless the claim assignment (see `claims`)
#'   places claims in it: then its heading is its brief.
#' @param question The review question, for framing.
#' @param client A `gr_client`.
#' @param model,max_section_tokens,temperature Overrides for the writing calls.
#' @param include_unclear Write from rows whose extraction was incomplete. Off by
#'   default: a row with nothing in it contributes nothing but its own absence,
#'   and the count of skipped rows is reported either way.
#' @param cite_style How citations appear in the finished prose. `"auto"` (the
#'   default) names the studies when the table can name all of them and uses
#'   markers when it cannot. `"author-year"` asks for names and warns if they
#'   cannot be produced; `"numeric"` gives `(1, 2)`; `"marker"` leaves
#'   `[study 1]` as written.
#'
#'   The model always writes `[study N]`, whatever this is set to, and the
#'   rendering happens afterwards from the table. That is deliberate: a marker
#'   can be checked exactly against the rows that exist, whereas verifying an
#'   author-year string would mean matching a name the model wrote against a
#'   name in the table, and near-misses (Smith for Smyth, 2019 for 2018) are
#'   both the errors that matter and the ones fuzzy matching forgives. A
#'   rendered citation is therefore a fact about the extraction rather than
#'   something the model asserted. `$sections$text_marked` and `$text_marked`
#'   keep the marker form so the check can be re-run on the published prose.
#' @param bib Which columns carry bibliographic identity, as a named list of
#'   `citation`, `authors`, `year`, `title`, `venue`, `doi`. Omitted, the
#'   conventional names are looked for, which is why
#'   `gr_protocols("bibliography")` works without configuration: `citation`
#'   (or `cite`, `citation_key`, `cite_key`), `authors` (or `author`), `year`,
#'   `title`, `venue` (or `journal`) and `doi`, in any case. Names that are as
#'   often findings -- `date`, `source`, `url`, `published`, `publication` --
#'   are not taken for bibliographic ones unless named here. A column found
#'   this way is withheld from the writing prompts and used for the citations
#'   and references; give a role as `NA` to keep a column of that name as a
#'   finding (`bib = list(venue = NA)`). The most
#'   reliable route is a `citation` field asked for during extraction: parsing
#'   an arbitrary author list is a heuristic, and where it cannot be done
#'   confidently the run falls back to markers rather than printing a name that
#'   may be wrong.
#'
#'   Pass the same `bib` to [gr_claims()] and [gr_gaps()]. The claims model is
#'   shown every column its own `bib` did not withhold, so a claim, and the
#'   moderator it names, can carry a column this write-up withholds, and the
#'   claims reach the writing prompts as they are. With `claims` drawn under
#'   a `bib` that withheld less than this one, the run warns
#'   (`gr_claims_bib_mismatch`) and names the columns.
#' @param style A register instruction appended to the writing prompts, such as
#'   `"formal academic; hedge claims; past tense for findings"`. It governs how
#'   sections are written, never what they may say: the rules about citing every
#'   claim and inventing nothing hold whatever voice is asked for.
#' @param coherence Revision passes over the finished draft: `TRUE` for all
#'   three, `FALSE` for none, or any of `"structure"` (reorder and merge),
#'   `"cut"` (remove repetition) and `"register"` (polish sentences) by name.
#'   Each pass is forbidden from doing the others' job, and each is discarded
#'   (with `$draft` kept, and the reason in `$coherence`) if it changed which
#'   studies are cited, wrote a citation the check cannot read, cited a study
#'   more often than the draft did, or took the citation marker off a claim
#'   sentence that stays (each a `gr_coherence_rejected` warning); if it
#'   arrived truncated (`gr_coherence_truncated`); if it strengthened a
#'   claim (`gr_revision_escalated`); or if it introduced a figure the draft
#'   did not have (`gr_revision_new_figure`): one the draft gives in no form,
#'   so a figure changed or rounded counts, and 0.61 written as .61 does not.
#'   Off by default: each is a call, and each is a chance for a model to
#'   touch finished prose.
#'
#'   The `"cut"` pass is also discarded when the cut pass did not shorten the
#'   review (`gr_revision_uncut`): its revision must have strictly fewer words
#'   of prose than the text it was given, headings and citation markers left
#'   out of the count. Fewer by any amount will do, since how much a draft can
#'   lose depends on how much it repeats itself. Only the cut is held to a
#'   length: a polish that keeps every sentence can remove half the words of
#'   padded prose, so no bound on the other two passes would tell their job
#'   from cutting. Their counts are in `$coherence` all the same.
#'
#'   The check that refuses a revision which strengthens a claim reads English
#'   hedges and boosters, so a draft it judges not to be in English is not
#'   revised at all: a warning (`gr_revision_unguarded`) says so, no pass is
#'   sent, and every pass is reported with `ran = FALSE` and that reason. The
#'   judgment counts letters outside the Latin alphabet and common function
#'   words, so a very short draft can be misjudged: an English one naming an
#'   accented author left unrevised, or a sentence or two of a language that
#'   has no accents taken for English.
#' @param claims A [gr_claims()] result. With it each section argues that
#'   section's claims and sees only the studies those claims rest on, rather
#'   than being handed every study and writing a paragraph per row. Needs an
#'   `outline` from [gr_outline()], which carries the assignment, and it must be
#'   an outline derived from these same claims: the run stops
#'   (`gr_claims_mismatch`) when the outline says it came from other claims,
#'   and (`gr_claims_unplaced`) when the assignment places a claim in a heading
#'   the outline does not have -- a heading renamed after [gr_outline()], say;
#'   rename it in `attr(outline, "claims")$section` too. A section given no
#'   claims is written from the rows, as without `claims`, except the closing
#'   section, which is written from `gaps` alone and is left out when there
#'   are none. A section too large for one prompt is written a few claims at a
#'   time, each batch sent only its claims' studies, and merged.
#' @param gaps A [gr_gaps()] result, or lines of text. Given to the closing
#'   section [gr_outline()] named, `attr(outline, "closing")`, with an
#'   instruction to state those gaps and no others. When the outline has no
#'   such section they reach none, and a warning (`gr_gaps_unused`) says so.
#'   They are cut, at a line, to a quarter of the model's input room, with a
#'   warning (`gr_gaps_truncated`), and the closing section is then partial.
#' @param trace A [gr_trace()] to fold this write-up's accounting into, as in
#'   [gr_read_many()]. It is a parent, not this stage's counter: `$trace` is
#'   still the write-up's own, so `gr_options(max_calls =)` bounds the write-up
#'   rather than being spent by the screening that came before it.
#' @param references Append a `## References` section built from the studies the
#'   finished text actually cites. Alphabetical under `"author-year"`, numbered
#'   by study otherwise: the list is labelled by whatever the prose uses to
#'   point into it. The alphabetical order follows a fixed rule rather than the
#'   session's locale, so it is the same on every machine: it ignores case,
#'   accents and apostrophes, filing an accented name with its base letter.
#'   Two papers by the same authors in the same year are lettered (2019a,
#'   2019b) in title order; a key that does not end in a year is lettered
#'   after a hyphen ("in press-a"). Under `"author-year"`, an entry whose key
#'   came from a `citation` field leads with that key, so the prose can be
#'   followed to it.
#' @param effort Reasoning effort, or `NULL` (the default) to send none: one
#'   string, or a character vector named by stage, as `effort` in
#'   [gr_read_spec()]. The calls here are labelled `synthesise.section`,
#'   `synthesise.batch`, `synthesise.merge` and, with `coherence`,
#'   `synthesise.revise.structure`, `.cut` and `.register`; `c(synthesise =
#'   "medium", "synthesise.section" = "high")` writes the sections at high and
#'   does the rest at medium. The reasoning counts against each call's reply
#'   limit (`max_section_tokens` for a section), and a section cut off at it is
#'   reported as one.
#'
#' @return An object of class `gr_synthesis`:
#'   \describe{
#'     \item{`text`}{The whole write-up, as markdown, citations rendered and the
#'       reference list appended.}
#'     \item{`text_marked`}{The same document with `[study N]` markers intact:
#'       what the citation check ran on.}
#'     \item{`draft`}{The write-up before the coherence pass, for comparison.}
#'     \item{`references`}{The reference list, or `NULL`.}
#'     \item{`cite_style`}{The style actually used, which is not always the one
#'       asked for.}
#'     \item{`coherence`}{One row per revision pass, or `NULL` if none ran:
#'       `pass` (which of `"structure"`, `"cut"`, `"register"`), `ran`, `kept`,
#'       `lost` and `added` (citations, if the revision changed them),
#'       `reason` for anything discarded, and `words_before` and `words_after`
#'       (integer: words of prose, headings and citation markers left out, in
#'       the text the pass was given and in its revision; `NA` for a pass
#'       that was not sent, or was refused by a check made before the length
#'       check, which comes last).}
#'     \item{`unrendered`}{Studies a section cited honestly that `text` still
#'       shows as `[study N]` somewhere, because a kept revision moved or
#'       reworded a citation of the same study that another section made
#'       without being given it, and the two could no longer be told apart.
#'       Leaving both is the safe side of that doubt; `$draft` renders each
#'       section's own citations. Empty when nothing was in doubt.}
#'     \item{`sections`}{One row per section: `section`, `brief`, `text`,
#'       `n_cited`, `n_unknown` (citations to a row that does not exist),
#'       `n_unsupplied` (citations to a study that exists but was not given to
#'       the call that wrote them: with `claims`, a study not behind that
#'       section's claims; for a section written in batches, a study outside
#'       that batch, or one the merge of the batch drafts cited that no draft
#'       did. They are left as markers and kept out of the reference
#'       list, with one exception: once batch drafts are merged, a study that
#'       another batch of the same section was given and cited cannot be told
#'       apart, so it is rendered, and still counted), `n_unparsed` (brackets
#'       that open like a citation, such as `[studies 1 to 7]`, but cannot be
#'       read as one, so the studies they name were not checked), `n_truncated` (replies,
#'       including batch drafts and merges, that stopped at the reply limit),
#'       `n_claims` and `claims_missed` (the claims it was given, and those it
#'       did not write up), `lost_batches` (batches of studies whose call
#'       failed), `capped_batches` (batches not sent because the run reached
#'       its call or cost ceiling), `merge_failed` (its batch drafts could not
#'       be merged, so it is those drafts joined end to end), and
#'       `partial`. A section is partial when any of those counts is non-zero
#'       (`n_cited` and `n_claims` aside), when it came back empty, when a batch of studies
#'       was lost or not read, when its batch drafts could not be merged or
#'       one had to be cut to fit the merge, when (without `claims`) none of
#'       the studies of a batch it was drafted from is cited in it, when it
#'       could not be sent at all (its brief and gaps leave no room in the
#'       window), when the gaps given to it were cut, or, with `claims`, when
#'       it did not write up a claim it was given. Last, `n_unbacked`: the
#'       figures in the section that are not in the rows their sentence cites
#'       (see "Figures" below). It does not make a section partial, which
#'       says that a citation cannot be trusted, and a figure's citation may
#'       be sound.}
#'     \item{`citations`}{Every citation, resolved to the row it points at, in
#'       long form: `section`, `study`, `document`, `document_id`.}
#'     \item{`figures`}{Every figure in a sentence of the write-up, checked
#'       against the rows it cites: `stage` (`"draft"` for the sections as
#'       written, `"final"` for the revised text when a kept revision pass
#'       changed it), `section` (the heading it stands under), `sentence`, `number`
#'       (as written), `studies` (the studies the sentence cites, comma-joined,
#'       or NA), `backed`, and `basis`, what it was found in (NA when it was
#'       not). See "Figures" below.}
#'     \item{`studies`}{The rows that were written from, with the `study` number
#'       each was cited by.}
#'     \item{`claims`}{The [gr_claims()] result written from, or `NULL`. When
#'       its `$lost` names studies whose claims batch contributed nothing, the
#'       run warns (`gr_claims_partial`), and print() and the audit report say
#'       the review was written without them.}
#'     \item{`claim_sections`}{With `claims`, which section each claim was
#'       given to: a data frame of `section` and `claim_id`, the outline's
#'       assignment. `NULL` without `claims`.}
#'     \item{`outline_alternative`}{Present only when the outline is one of
#'       several [gr_outline()] compared (`alternatives` above 1): which one
#'       it was, as `alternative`, `of` (how many were asked for), `distinct`
#'       (how many came back distinct) and `distance` from the first proposal.
#'       The trace's meta records `outline_alternative` and `outline_of` too.}
#'     \item{`outline_trace`}{Present only when `outline` came from
#'       [gr_outline()]: the trace of the calls that derived it, which this
#'       stage's `trace` does not include.}
#'     \item{`trace`}{As [gr_extract()].}
#'   }
#'
#' @section Which rows are used:
#' Rows that were never read (`status` `"failed"` or `"skipped"`) are left out,
#' and so are duplicates: a study counted twice is the error this whole
#' pipeline exists to avoid, and `gr_read_many()` has already marked them. The
#' number left out is reported by `print()` and is in `$skipped`.
#'
#' @section What it costs:
#' One call per section when the table fits one prompt, which is the usual case:
#' a hundred rows of a ten-field schema is a few thousand tokens. A table too
#' large for one prompt is written in batches and merged, so a section costs
#' batches + merges instead. Either way the cost is per *section*, not per
#' document: the expensive reading has already happened.
#'
#' The merge folds every batch draft into one reply of at most
#' `max_section_tokens`, the same limit each draft had, so a section drafted
#' from a very large table covers only what that one reply can hold. Nothing
#' checks that it cites every study -- a section need not -- but without
#' `claims` a batch none of whose studies the merged section cites is
#' reported (`gr_synth_batch_dropped`) and marks it partial. Raise
#' `max_section_tokens`, or divide the table between narrower sections.
#'
#' @section Figures:
#' The citation check says which rows a sentence rests on, not what it says
#' they found, and the numbers are what a reader copies out of a review. So
#' every number in every sentence is looked for in what the writer was shown
#' for that sentence: the rows it cites, as the writing prompt showed them; the
#' question, the section's heading and brief, `style`, and the gaps a closing
#' section was given; and with `claims`, the claims given to the section that
#' rest on a cited study. A sentence that cites nothing is checked against
#' every row its section was shown. This runs on the draft, and again on the
#' revised text when a kept revision pass changed it; it sends nothing, so it
#' is always on, and it changes no request.
#'
#' A figure counts as found in any form a faithful copy may give it: `.61` for
#' 0.61, `45.20` for 45.2, `1204` for 1,204, `12 450` for 12,450 (grouped by
#' a space, where that is the row's figure), a minus sign or none, either side
#' of a dash in a range, `45.2 million` for 45,200,000, `4 x 10^-4` for
#' 0.0004, `100,000` for a numeric field shown as `1e+05`, `45%` for 0.45,
#' `12` for "twelve", and rounded to the places it is written to (0.61 or 0.6
#' for 0.613, never 0.62). A row's percentage read as a proportion, or its
#' scaled figure at full value, must match exactly: rounded as well, a pooled
#' estimate no study reported matched a row's unrelated percentage. A figure
#' is also allowed when it is the total of a numeric field over the rows the
#' sentence cites; worked out from two other figures of the same sentence
#' ("120 of 1,020 (11.8%)"), or from a ratio in it read as a change from 1
#' ("HR 0.78, a 22% lower hazard"); a difference in points between two figures
#' of one field of a cited row, or two percentages of one cited row; a year a
#' cited row carries in any column; the number of studies the sentence cites,
#' its section was shown or the review was written from, or how many of those
#' rows share a field's value ("10 were randomised trials"); or, after
#' "about", "more than", "fewer than" and their like, within a tenth (about)
#' or a quarter (a bound) of a value it could have come from. Not read as
#' figures: a citation's ids, written bare as well ("studies 12 to 15"), a
#' whole number below ten that is not a percentage or scaled (a review writes
#' "2 of the trials" as it likes), a number joined to a name ("COVID-19",
#' "IL-6"), an ordinal, a decade ("1990s", "in their 60s"), an interval's
#' level (`95% CI`), a significance threshold (`p < .001`, "p value below
#' 0.05") and a significance level ("at the 5% level"). Numbers written in
#' words are not checked.
#'
#' A figure found nowhere is reported in `$figures` and counted in
#' `$sections$n_unbacked`, and the run warns (`gr_synth_unbacked_figures`)
#' about the text as published. It is arithmetic the sentence does not show,
#' a pooled estimate no study reported, or a number the writer made up, and
#' nothing here can tell which. Found means copied, not right: a figure the
#' cited row carries can still be the wrong one for the sentence. The section
#' is not marked partial, because `partial` is about whether its citations
#' can be trusted, and those are checked apart.
#'
#' @seealso [gr_extract()], [gr_protocol()], [gr_screen()]
#' @export
#' @examples
#' fields <- gr_fields(design = "The study design",
#'                     n = gr_field("Participants", type = "integer"))
#' cl <- gr_mock_client(function(messages, params) {
#'   seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
#'                 collapse = " ")
#'   if (grepl("<studies>", seen, fixed = TRUE)) "One randomised trial of 120 people [study 1]."
#'   else '{"design":"randomised trial","n":120,
#'          "design__quote":"We ran a randomised trial.",
#'          "n__quote":"We enrolled 120 people."}'
#' })
#'
#' f <- tempfile(fileext = ".txt")
#' writeLines("We ran a randomised trial. We enrolled 120 people.", f)
#' x <- gr_extract(f, fields, client = cl)
#'
#' s <- gr_synthesise(x, question = "Does it work?",
#'                    outline = c("Included studies" = "How many, of what design"),
#'                    client = cl)
#' s$sections[, c("section", "n_cited", "n_unknown", "n_unbacked")]
#' # The 120 in the section, found in the row it cites.
#' s$figures[, c("number", "studies", "backed", "basis")]
gr_synthesise <- function(extraction, protocol = NULL, outline = NULL, question = NULL,
                          client = NULL, model = NULL, max_section_tokens = 1200L,
                          temperature = NULL, include_unclear = FALSE,
                          cite_style = c("auto", "marker", "author-year", "numeric"),
                          bib = NULL, style = NULL, coherence = FALSE,
                          references = TRUE, claims = NULL, gaps = NULL,
                          trace = NULL, effort = NULL) {
  cite_style <- match.arg(cite_style)
  tab <- if (inherits(extraction, "gr_extraction")) extraction$table else extraction
  if (!is.data.frame(tab) || !nrow(tab)) {
    gr_abort("`extraction` must be a gr_extraction, or a data frame shaped like its $table.",
             class = "gr_no_studies")
  }
  if (!is.null(protocol)) {
    if (!inherits(protocol, "gr_protocol")) {
      gr_abort("`protocol` must come from gr_protocol().", class = "gr_bad_protocol")
    }
    check_protocol_edited(protocol, "write against it")
    if (is.null(outline)) outline <- protocol$outline
    if (is.null(question)) question <- protocol$question
  }
  # Labelled UTF-8 before anything is pasted to them. Under a non-UTF-8 locale
  # a question, heading or register typed in a script is UTF-8 bytes marked
  # "unknown", and paste() joining it to labelled text -- the claims, or a
  # heading gr_outline() read from the model -- escaped it to "<c3><a9>"
  # before the request was built; trimws() over headings of both kinds
  # stopped the run.
  if (is.character(question)) question <- mark_utf8(question)
  if (is.character(style)) style <- mark_utf8(style)
  outline <- mark_outline(outline)
  # Read BEFORE outline_vector(), which rebuilds the vector with setNames() and
  # drops every attribute -- including the claim assignment gr_outline() put
  # there. Losing it silently would take every section back to writing from rows.
  assign_map <- attr(outline, "claims")
  closing <- as_chr1(attr(outline, "closing"), NA_character_)
  fingerprint <- attr(outline, "claims_fingerprint")
  # Which of gr_outline()'s alternatives this is, read here for the same
  # reason: once the attribute is dropped, a review written from its second
  # proposal looks like one written from its first.
  chosen <- outline_choice(outline)
  # What gr_outline() spent, kept for the audit's cost table. Only referred
  # to: this stage's own trace does not absorb it, since a caller who gave
  # gr_outline() a parent trace already has those calls there.
  outline_trace <- attr(outline, "trace", exact = TRUE)
  # A section the claim assignment names is a section to write, whatever its
  # brief says. outline_vector() drops a heading with a blank brief, and
  # gr_outline() keeps one when the model left the brief empty, so the section
  # vanished here and took its claims with it.
  outline <- fill_assigned_briefs(outline, assign_map)
  outline <- outline_vector(outline)
  if (!length(outline)) {
    gr_abort(paste0("`outline` is empty. Give the sections to write, as a named character ",
                    "vector of heading = what it must cover, or a gr_protocol() carrying one."),
             class = "gr_no_outline")
  }
  if (!is_nonblank(question)) gr_abort("`question` must be a non-empty string.")

  used <- synth_studies(tab, include_unclear)
  keep <- attr(used, "keep")

  if (!is.null(claims)) {
    if (!inherits(claims, "gr_claims")) {
      gr_abort("`claims` must come from gr_claims().", class = "gr_bad_claims")
    }
    # THE guard for this whole layer. A claim number and a `[study N]` marker are
    # the same identifier, and they agree only because both sides derive it from
    # synth_studies() over the same table. Hand gr_claims() one extraction and
    # gr_synthesise() another -- or the same one with a different
    # `include_unclear` -- and every claim silently points at a different row.
    # Nothing downstream could detect it: the numbers are all valid, they just
    # mean other studies, and the review attributes findings to papers that do
    # not contain them.
    if (!identical(study_identity(claims$studies), study_identity(used))) {
      gr_abort(paste0("These claims were drawn from a different set of studies than this ",
                      "synthesis is writing from, so their study numbers point at different ",
                      "rows. Give gr_claims() and gr_synthesise() the same `extraction` and the ",
                      "same `include_unclear`."),
               class = "gr_claims_mismatch")
    }
    if (is.null(assign_map)) {
      gr_abort(paste0("`claims` was given but the outline does not say which claims belong to ",
                      "which section, so every section would fall back to writing from rows. ",
                      "Use gr_outline(claims) for the outline, or attach the assignment ",
                      "yourself with attr(outline, \"claims\") <- data.frame(section = , ",
                      "claim_id = )."),
               class = "gr_no_claim_assignment")
    }
    if (is.null(assign_map$section) || is.null(assign_map$claim_id)) {
      gr_abort(paste0("attr(outline, \"claims\") must be a data frame with columns `section` and ",
                      "`claim_id`, as gr_outline() makes it. Without them no section finds its ",
                      "claims, and every section falls back to writing from rows."),
               class = "gr_no_claim_assignment")
    }
    # Claim numbers are positions in ONE gr_claims() result. An outline made
    # from another run -- a re-run, or a reconcile that ordered the claims
    # differently -- names the same numbers for different claims, and each
    # section argued someone else's. gr_outline() stamps the claims it was
    # given; nothing to compare against is an outline made some other way.
    if (!is.null(fingerprint) &&
        !identical(as_chr1(fingerprint), claims_fingerprint(claims$claims))) {
      gr_abort(paste0("This outline's claim assignment was made from different claims than the ",
                      "`claims` given, so its claim numbers name different claims. Derive the ",
                      "outline from these claims with gr_outline(claims)."),
               class = "gr_claims_mismatch")
    }
    # Every claim the assignment places has to land in a section that is
    # written. A claim assigned to a heading the outline no longer has -- one
    # renamed after gr_outline(), which `names<-` allows and keeps the
    # assignment through -- was never argued, the renamed section fell back to
    # writing from rows, and nothing said so.
    orphan <- !as.character(assign_map$section) %in% names(outline)
    if (any(orphan)) {
      gr_abort(sprintf(paste0("The outline assigns claim(s) %s to section(s) %s, which it does not ",
                              "contain, so those claims would never be written. A heading renamed ",
                              "after gr_outline() does this: rename it in ",
                              "attr(outline, \"claims\")$section too, or move the claims to a ",
                              "section the outline has."),
                       paste(sort(unique(assign_map$claim_id[orphan])), collapse = ", "),
                       paste0("'", unique(as.character(assign_map$section[orphan])), "'",
                              collapse = ", ")),
               class = "gr_claims_unplaced")
    }
    # gr_claims() warned when a batch came back with nothing, but that warning
    # is long gone by the time the review is written, and every section is
    # complete against claims that are not. Said again here, and by print()
    # and the audit report, because the review covers only the rest.
    lost <- claims$lost %||% integer(0)
    if (length(lost)) {
      gr_warn(sprintf(paste0("These claims were drawn with %d of %d studies contributing nothing: ",
                             "their batch was cut off, failed or was not sent (see `claims$lost`). ",
                             "The review is written from the rest. Run gr_claims() again to ",
                             "include them."),
                      length(lost), nrow(claims$studies)),
              class = "gr_claims_partial")
    }
    # The writing prompts withhold the bibliographic columns (`rendered`
    # below), but the claims reach them as gr_claims() drew them. Claims drawn
    # under a `bib` that withheld less were drawn by a model shown those
    # columns, so a claim, or the moderator it names, can carry one into every
    # section that argues it -- a first author in the claim text, in front of
    # a writer this run is keeping from naming one. `%||%` for a claims table
    # made before it recorded what it withheld: it withheld the conventional
    # names.
    had <- claims$hidden %||% unlist(bib_columns(claims$studies), use.names = FALSE)
    shown <- setdiff(unlist(bib_columns(used, bib), use.names = FALSE), had)
    if (length(shown)) {
      gr_warn(sprintf(paste0("These claims were drawn with %s shown to the model, which this ",
                             "write-up withholds as bibliographic, so the claims' text and the ",
                             "moderators they name may carry %s into the writing prompts. Pass ",
                             "the same `bib` to gr_claims() as to gr_synthesise()."),
                      paste0("'", shown, "'", collapse = ", "),
                      if (length(shown) == 1L) "it" else "them"),
              class = "gr_claims_bib_mismatch")
    }
  }

  client <- client %||% gr_client(model = model %||% gr_options("model"))
  # This function's own default, range check and name, not gr_read_spec()'s:
  # passed through raw, an NA fell back to max_answer_tokens' 1500, and any bad
  # value warned about a setting the caller never used.
  max_section_tokens <- clamp_warn(na_default(max_section_tokens, 1200L, "max_section_tokens"),
                                   16, 1e6, "max_section_tokens")
  spec <- gr_read_spec("stuff", model = model, temperature = temperature,
                       max_answer_tokens = max_section_tokens, effort = effort)
  # gr_read_spec() leaves the model NULL when none is named, and gr_budget() and
  # gr_call() fall back to different models on NULL: sections were sized for
  # gr_options("model") and sent to the client's, so a small model got a prompt
  # sized for a large one. Settled once here, so the sections, the merges and
  # the revision passes all size for, and ask, the same model.
  spec <- resolve_read_model(spec, client)
  # The parent, not the counter -- see as_parent_trace(). Running the write-up on
  # a trace that screening had already spent meant `trace_can_call()` refused
  # every section and the review came back as a list of empty headings.
  parent <- as_parent_trace(trace)
  trace <- gr_trace(meta = c(list(stage = "synthesise", question = question,
                                  sections = length(outline), studies = nrow(used)),
                             if (!is.null(chosen))
                               list(outline_alternative = chosen$alternative,
                                    outline_of = chosen$of)))
  if (!is.null(parent)) on.exit(trace_absorb(parent, trace), add = TRUE)

  # The writing model is NOT shown who wrote each study. Adding bibliographic
  # fields to a schema put "authors: Smith, J., Okafor, A." in front of a model
  # asked to cite `[study 1]`, and a model that can see a name will sooner or
  # later write "Smith and Okafor (2019) found..." instead of the marker. That
  # citation is checked by nothing and rendered by nothing: it is the model
  # asserting an attribution, which is the one thing this design exists to
  # prevent. Identity is applied afterwards, from the table. A model cannot
  # misattribute a study whose authors it was never told.
  #
  # If a bibliographic value is also a FINDING -- publication year as
  # chronology, say -- extract it a second time under a name of its own.
  rendered <- render_studies(used, hide = unlist(bib_columns(used, bib), use.names = FALSE))
  # gr_gaps() returns a table; a section wants lines. Accepting both means the
  # caller never has to know which. Lines of text are one block: as several
  # strings they were not "nonblank" and reached no section.
  if (inherits(gaps, "gr_gaps") || is.data.frame(gaps)) gaps <- render_gaps(gaps)
  # Labelled, as the question is above: they are pasted to the section's brief.
  if (is.character(gaps)) gaps <- mark_utf8(gaps)
  if (is.character(gaps) && length(gaps) > 1L) gaps <- as_chr1(gaps[nzchar(trimws(gaps))])
  if (!is_nonblank(gaps)) gaps <- NULL
  # Gaps reach exactly one section, the closing one gr_outline() marked: handing
  # them to every section makes every section recite them. An outline with no
  # such heading -- written by hand, from a protocol, or with the closing
  # heading renamed -- sent them nowhere while `$gaps` reported them.
  if (!is.null(gaps) && (is.na(closing) || !closing %in% names(outline))) {
    gr_warn(sprintf(paste0("`gaps` were given, but the outline has no closing section to state them ",
                           "(%s), so no section does. Name the heading that should with ",
                           "attr(outline, \"closing\") <- \"<heading>\"."),
                    if (is.na(closing)) "it names none" else sprintf("it names '%s'", closing)),
            class = "gr_gaps_unused")
    gaps <- NULL
  }
  # Bounded, because they are the closing section's fixed text and every batch
  # of it resends them. Cut at a line, and said: that section states only the
  # gaps it was given.
  gaps_cut <- FALSE
  if (!is.null(gaps)) {
    room <- tryCatch(gr_budget(spec$model, reserve_output = spec$max_answer_tokens)$input,
                     gr_budget_error = function(e) NA_integer_)
    fit <- if (is.na(room)) gaps else cap_gap_lines(gaps, max(1L, room %/% 4L))
    if (!identical(fit, gaps)) {
      gr_warn(sprintf(paste0("The gaps were cut to %d of %d line(s) to fit the model's window, so ",
                             "section '%s' states only those. It is marked partial."),
                      attr(fit, "kept"), attr(fit, "of"), closing),
              class = "gr_gaps_truncated")
      # A cut inside the first line ends in the default marker, which is not
      # text kept; a cut at a line boundary has none and the guard skips it.
      trace_truncation(trace, "synthesise.gaps", gaps, as.character(fit),
                       limit = max(1L, room %/% 4L), marker = " ...[truncated]",
                       section = closing)
      gaps <- as.character(fit)
      gaps_cut <- TRUE
    }
  }
  weights <- if (is.null(claims)) NULL else study_weight(used)
  # One latch for the whole write-up, so the ceiling is reported once rather
  # than once per section.
  capped <- new.env(parent = emptyenv())
  rows <- lapply(seq_along(outline), function(i) {
    heading <- names(outline)[[i]]
    ids <- if (is.null(assign_map)) integer(0) else
      as.integer(assign_map$claim_id[as.character(assign_map$section) == heading])
    is_closing <- !is.na(closing) && identical(heading, closing)
    # The closing section of a write-up from claims, with no claim placed in
    # it and no gaps to state, has nothing to say, and was written from every
    # row instead. Left out, unless it is all there is.
    if (!is.null(claims) && is_closing && !length(ids) && is.null(gaps) && length(outline) > 1L) {
      gr_msg(sprintf(paste0("Section '%s' was left out: no claim was placed in it and no gaps were ",
                            "given. Pass `gaps = gr_gaps(claims)` to write it."), heading))
      return(NULL)
    }
    gr_msg(sprintf("[%d/%d] %s", i, length(outline), heading))
    # A section that cannot be sized is that section's failure. Uncaught, a
    # budget error ended the write-up and threw away every section already
    # written and paid for.
    tryCatch(
      synth_section(heading, outline[[i]], question, rendered, used, client, spec, trace, style,
                    claims = claims, claim_ids = ids, weights = weights,
                    gaps = if (is_closing) gaps else NULL, capped = capped,
                    gaps_cut = is_closing && gaps_cut),
      gr_budget_error = function(e) synth_unwritten(heading, outline[[i]], ids, conditionMessage(e)))
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  sections <- do.call(rbind, lapply(rows, `[[`, "row"))
  citations <- rbind_evidence(lapply(rows, `[[`, "citations"))

  # ORDER MATTERS, and getting it wrong is silent. Everything downstream works
  # on the MARKER form -- the notation the model actually wrote and the citation
  # check actually ran on -- and rendering to "(Smith & Okafor, 2019)" happens
  # once, at the very end. Rendering first made the coherence pass compare a
  # rendered draft against a marked revision, so every citation in the revision
  # looked newly added and every honest revision was thrown away.
  cols <- bib_columns(used, bib)   # already resolved above; cheap and pure
  keys <- bib_keys(used, cols)
  resolved <- resolve_cite_style(cite_style, keys, cols)
  if (!identical(resolved, cite_style) && !identical(cite_style, "auto")) {
    gr_warn(paste0("`cite_style = \"", cite_style, "\"` needs a citation key for every study, and ",
                   "the table does not carry one for all of them. Falling back to markers rather ",
                   "than printing a name that may be wrong. Extract a `citation` field, or an ",
                   "`authors` and a `year` field, or point `bib` at the columns that hold them."),
            class = "gr_cite_unresolvable")
  }

  marked <- synth_document(sections)
  passes <- revise_passes(coherence)
  revised <- if (length(passes)) {
    synth_revise(marked, question, client, spec, trace, style, passes)
  } else NULL
  final_marked <- revised$text %||% marked

  # Every figure looked for in the rows its sentence cites, in the draft and
  # again in the revision that replaced it. Here, before rendering, for the
  # reason rendering waits: `[study N]` is what says which rows a sentence
  # rests on. It sends nothing, so it runs on every write-up; see
  # synth_figures().
  figs <- synth_figures(sections, revised$text, used, rendered, question, claims = claims,
                        assign_map = assign_map, gaps = gaps, closing = closing, style = style,
                        hide = unlist(cols, use.names = FALSE), trace = trace)
  sections$n_unbacked <- figs$n_unbacked

  # A study a section cited without being shown it stays a visible marker, as a
  # row that does not exist does: rendering it would print the fabrication as a
  # fact about the extraction. Per section, because the same study may be cited
  # honestly by another section that WAS shown it.
  unsupplied <- lapply(rows, `[[`, "unsupplied")
  render <- function(x, leave) render_citations(x, used, keys, resolved, leave = leave)
  # Kept because it is what the citation check ran on, so the check can be
  # re-run on the published prose at any point.
  sections$text_marked <- sections$text
  sections$text <- unlist(Map(render, sections$text, unsupplied), use.names = FALSE)
  # The draft is its sections, so it is rendered from them, each with its own
  # exceptions; rendering the joined document is the same text otherwise.
  drafted <- synth_document(sections)
  # A kept revision is one text rather than sections, so the markers to leave
  # are found in it again by heading and by sentence, pass by pass (see
  # render_revised()). `left` is the studies no marker was rendered for
  # anywhere.
  unrendered <- integer(0)
  if (is.null(revised$text)) {
    published <- drafted
    left <- setdiff(unlist(unsupplied), citations$study)
  } else {
    # Each kept pass's text, followed one at a time; the last is `final_marked`.
    steps <- if (length(revised$steps)) revised$steps else final_marked
    rr <- render_revised(steps, sections$section, sections$text_marked, unsupplied, render)
    published <- rr$text
    left <- rr$left
    # An honest citation left as a marker is the safe side of a doubt, and
    # still a citation the reader loses: said here, by print() and in
    # `$unrendered`, since no section's own counts describe the revision.
    unrendered <- rr$unrendered
    if (length(unrendered) && !identical(resolved, "marker")) {
      gr_warn(sprintf(paste0("The kept revision moved or reworded a citation of study %s that a ",
                             "section made without being given it, so where an honest citation ",
                             "of it could no longer be told from that one it is left as a marker ",
                             "(see `$unrendered`; `$draft` renders each section's own)."),
                      paste(unrendered, collapse = ", ")),
              class = "gr_synth_unrendered")
    }
  }

  # The reference list follows what the FINISHED text cites, not what the
  # sections cited before revision. A reference list carrying a study the final
  # prose never mentions claims a breadth the review does not have. Nor does it
  # carry a study the text cites only by a marker left as written: that marker
  # is a fault the check reported, not a citation to follow up.
  cited <- setdiff(cited_ids(final_marked, "study"), left)
  refs <- if (isTRUE(references)) reference_list(used, keys, cited, cols, resolved) else NULL

  out <- structure(list(
    text = append_references(published, refs),
    text_marked = final_marked,
    draft = append_references(drafted, refs),
    sections = sections,
    references = refs,
    citations = citations %||% synth_empty_citations(),
    figures = figs$table,
    studies = used,
    skipped = sum(!keep),
    question = question,
    outline = outline,
    claims = claims,
    # The claim assignment, which outline_vector() dropped from `outline`
    # above: without it nothing downstream, the audit report included, can
    # say which section a claim was given to.
    claim_sections = if (is.null(claims)) NULL else
      data.frame(section = as.character(assign_map$section),
                 claim_id = as.integer(assign_map$claim_id), stringsAsFactors = FALSE),
    gaps = gaps,
    cite_style = resolved,
    coherence = revised$report,
    unrendered = if (identical(resolved, "marker")) integer(0) else unrendered,
    trace = trace
  ), class = "gr_synthesis")
  # Added only when there is something to say, so a write-up from a single
  # outline is the object it always was.
  if (!is.null(chosen)) out$outline_alternative <- chosen
  if (inherits(outline_trace, "gr_trace")) out$outline_trace <- outline_trace
  out
}

#' Which citation style can actually be honoured.
#'
#' "auto" is the only one that silently changes: name the studies when the table
#' can name all of them, and use markers when it cannot. Asking for author-year
#' outright and not getting it is worth a warning, because the caller expected
#' something the data cannot support.
#' @noRd
resolve_cite_style <- function(want, keys, cols) {
  if (identical(want, "marker")) return("marker")
  if (identical(want, "numeric")) return(if (length(cols)) "numeric" else "marker")
  if (is.null(keys)) return("marker")
  if (identical(want, "auto")) "author-year" else want
}


#' @export
print.gr_synthesis <- function(x, ...) {
  s <- x$sections
  cat(sprintf("<gr_synthesis> %d section(s) from %d stud%s\n", nrow(s), nrow(x$studies),
              if (nrow(x$studies) == 1L) "y" else "ies"))
  if (x$skipped) {
    cat(sprintf("  %d row(s) left out: failed or read in part, duplicate, or nothing extracted\n", x$skipped))
  }
  # `%||%` for a synthesis saved before the column existed.
  unsup <- s$n_unsupplied %||% integer(nrow(s))
  unparsed <- s$n_unparsed %||% integer(nrow(s))
  cut <- s$n_truncated %||% integer(nrow(s))
  unbacked <- s$n_unbacked %||% integer(nrow(s))
  for (i in seq_len(nrow(s))) {
    flags <- c(if (s$n_unknown[i]) sprintf("%d TO A ROW THAT DOES NOT EXIST", s$n_unknown[i]),
               if (unsup[i]) sprintf("%d TO A STUDY IT WAS NOT GIVEN", unsup[i]),
               if (unparsed[i]) sprintf("%d THE CHECK CANNOT READ", unparsed[i]),
               if (cut[i]) "CUT OFF AT THE REPLY LIMIT",
               if (unbacked[i]) sprintf("%d FIGURE(S) NOT IN THE ROWS CITED", unbacked[i]))
    cat(sprintf("  %-22s %5d words, %d citation(s)%s\n",
                substr(s$section[i], 1, 22),
                lengths(strsplit(trimws(s$text[i]), "\\s+"))[1],
                s$n_cited[i],
                if (length(flags)) paste0(", ", paste(flags, collapse = ", "))
                else if (!s$n_cited[i]) ", NONE" else ""))
  }
  if (any(s$n_unknown > 0L)) {
    cat("  a citation to a row that does not exist is a fabrication; those sections are partial\n")
  }
  if (any(unsup > 0L)) {
    # "wherever it can be told apart": a merged batch draft citing a study that
    # another batch of the same section cited honestly is rendered; see
    # synth_section().
    cat(paste0("  so is a citation to a study the section was not given; those sections are ",
               "partial, and such a marker is left unrendered wherever it can be told apart ",
               "from an honest citation\n"))
  }
  if (any(unparsed > 0L)) {
    cat(paste0("  a citation the check cannot read names studies nobody checked; those sections ",
               "are partial\n"))
  }
  if (any(cut > 0L)) {
    cat("  a section cut off at the reply limit stops mid-thought; those sections are partial\n")
  }
  # The counts above are the draft's. Said of the text as published, which is
  # the revision when one was kept and changed it: the check records which it
  # read (synth_figures()). A synthesis made before the check has no
  # `$figures`, and says nothing here.
  fig <- x$figures
  if (is.data.frame(fig) && nrow(fig)) {
    stage <- attr(fig, "published", exact = TRUE) %||%
      (if (is.data.frame(x$coherence) && any(isTRUE_vec(x$coherence$kept))) "final" else "draft")
    final <- identical(stage, "final")
    bad <- sum(fig$stage == stage & !fig$backed)
    if (bad) {
      cat(sprintf(paste0("  %d figure(s) in the %s are not in the rows their sentence cites, so no ",
                         "study is behind them as written; check them before quoting (see ",
                         "$figures). No section is partial for it: that is about citations\n"),
                  bad, if (final) "revised text" else "text"))
    }
  }
  unr <- x$unrendered %||% integer(0)
  if (length(unr)) {
    cat(sprintf(paste0("  study %s: cited honestly, but left as a marker in the revised text where ",
                       "the revision made that citation impossible to tell from the one the check ",
                       "reported; see $draft\n"), paste(unr, collapse = ", ")))
  }
  # Which of several outlines the sections follow; see gr_outline_pick().
  alt <- x[["outline_alternative", exact = TRUE]]
  if (is.data.frame(alt) && nrow(alt)) {
    j <- as.integer(alt$alternative[1])
    cat(sprintf("  outline: alternative %d of the %d gr_outline() was asked for%s\n",
                j, as.integer(alt$of[1]),
                if (isTRUE(j > 1L))
                  sprintf(", grouping %.0f%% of pairs of claims unlike the first",
                          100 * as.numeric(alt$distance[1]))
                else ""))
  }
  lost <- x$claims$lost %||% integer(0)
  if (length(lost)) {
    cat(sprintf(paste0("  PARTIAL: written from claims that %d of %d studies contributed nothing to, ",
                       "their batch cut off, failed or not sent; see $claims$lost\n"),
                length(lost), nrow(x$studies)))
  }
  cost <- gr_trace_cost(x$trace)
  total <- if (nrow(cost)) sum(cost$usd) else 0
  # format_call_counts(), not `calls`: that counts embeddings requests too, and
  # a run that made any showed them as model calls, disagreeing with the trace.
  cat(sprintf("  this run: %s, %s\n", format_call_counts(x$trace),
              if (!nrow(cost)) "no cost recorded"
              else if (is.na(total)) "cost unknown (unpriced model)"
              else sprintf("$%.4f", total)))
  invisible(x)
}

#' An outline with its headings and briefs labelled UTF-8, and the headings
#' its claim assignment and closing section name, keeping every attribute.
#'
#' `x[] <-` and `names<-` rather than mark_utf8(x), whose as.character() drops
#' the attributes, the claim assignment among them. A heading renamed by hand
#' and the assignment row renamed with it are compared as the same heading only
#' when both are labelled alike.
#' @noRd
mark_outline <- function(x) {
  if (!length(x)) return(x)
  nm <- names(x)
  if (is.list(x)) {
    x[] <- lapply(x, function(v) if (is.character(v)) mark_utf8(v) else v)
  } else if (is.character(x)) {
    x[] <- mark_utf8(x)
  }
  if (!is.null(nm)) names(x) <- mark_utf8(nm)
  map <- attr(x, "claims")
  if (is.data.frame(map) && !is.null(map$section)) {
    map$section <- mark_utf8(as.character(map$section))
    attr(x, "claims") <- map
  }
  closing <- attr(x, "closing")
  if (is.character(closing)) attr(x, "closing") <- mark_utf8(closing)
  x
}

#' Give a blank brief to the heading it belongs to, for each section the
#' claim assignment names, so outline_vector() keeps the section. A heading
#' is its own brief already when an outline is a bare vector.
#' @noRd
fill_assigned_briefs <- function(outline, assign_map) {
  nms <- names(outline)
  if (is.null(assign_map) || !length(outline) || is.null(nms) || is.null(assign_map$section)) {
    return(outline)
  }
  v <- vapply(outline, as_chr1, character(1), USE.NAMES = FALSE)
  blank <- !nzchar(trimws(v)) & nzchar(trimws(nms)) & nms %in% as.character(assign_map$section)
  if (any(blank)) outline[blank] <- nms[blank]
  outline
}

#' What identifies a synthesis's rows, for comparing two sets of them.
#'
#' The document ids, else the document names. Else the rows themselves, as the
#' writing model is shown them: with neither column, or with every id NA, the
#' comparison was of character(0) with character(0), or of NAs with NAs, and
#' claims from any other table of the same length passed it.
#' @noRd
study_identity <- function(d) {
  for (col in c("document_id", "document")) {
    v <- d[[col]]
    if (!is.null(v) && !all(is.na(v))) return(as.character(v))
  }
  render_studies(d)
}

#' A fingerprint of a claims table: which claim each number is.
#'
#' gr_outline() stamps it on the outline as `attr(, "claims_fingerprint")`, and
#' gr_synthesise() compares it with the claims it is given, because an
#' assignment by claim number means nothing against another set of claims.
#' @noRd
claims_fingerprint <- function(cw) {
  gr_hash(list(claim_id = as.integer(cw$claim_id), claim = as.character(cw$claim)))
}

#' The first lines of `gaps` that fit `n` tokens, or `gaps` itself when all do;
#' a first line too long on its own is cut. `attr(, "kept")` and `attr(, "of")`
#' count the lines.
#' @noRd
cap_gap_lines <- function(gaps, n) {
  if (gr_count_tokens(gaps) <= n) return(gaps)
  lines <- strsplit(as_chr1(gaps), "\n", fixed = TRUE)[[1]]
  keep <- cumsum(gr_count_tokens(lines) + 1L) <= n
  out <- if (any(keep)) paste(lines[keep], collapse = "\n") else gr_truncate_tokens(lines[1], n)
  structure(out, kept = max(1L, sum(keep)), of = length(lines))
}

#' A section that could not be written at all, with the warning that says so.
#' @noRd
synth_unwritten <- function(heading, brief, claim_ids, why) {
  gr_warn(sprintf("Section '%s' was not written (%s). It is marked partial.", heading, why),
          class = "gr_synth_too_large")
  list(row = data.frame(section = heading, brief = as_chr1(brief), text = "",
                        n_cited = 0L, n_unknown = 0L, n_unsupplied = 0L, n_unparsed = 0L,
                        n_truncated = 0L, n_claims = length(claim_ids),
                        claims_missed = length(claim_ids), lost_batches = 0L,
                        capped_batches = 0L, merge_failed = FALSE, partial = TRUE,
                        stringsAsFactors = FALSE),
       unsupplied = integer(0), citations = NULL)
}

#' The studies a synthesis works from, numbered.
#'
#' Shared by [gr_synthesise()] and [gr_claims()] because the number IS the
#' identifier: a claim saying it rests on study 3 and a section citing
#' `[study 3]` have to mean the same row. Two copies of this filter would drift
#' the moment one of them learned about a new status value, and the symptom
#' would be a claims table that silently points at the wrong studies -- not an
#' error, just a review attributing findings to papers that do not contain them.
#' @noRd
synth_studies <- function(tab, include_unclear = FALSE) {
  keep <- synth_usable(tab, include_unclear)
  used <- tab[keep, , drop = FALSE]
  if (!nrow(used)) {
    gr_abort(paste0("No usable rows: every document either failed or was read only in part, ",
                    "was a duplicate of another, or had nothing extracted. There is nothing to ",
                    "write from."),
             class = "gr_no_studies")
  }
  used$study <- seq_len(nrow(used))
  attr(used, "keep") <- keep
  used
}

#' Which rows a write-up may draw on.
#'
#' A duplicate is excluded even though it has perfectly good values, because it
#' is the SAME study: counting it twice is the error the whole pipeline exists to
#' avoid, and it is the easiest one to make here, where the rows all look alike.
#' @noRd
synth_usable <- function(tab, include_unclear) {
  ok <- if (is.null(tab$status)) rep(TRUE, nrow(tab)) else
    tab$status %in% c("ok", "restored", "duplicate")
  distinct <- if (is.null(tab$duplicate_of)) rep(TRUE, nrow(tab)) else is.na(tab$duplicate_of)
  filled <- if (isTRUE(include_unclear) || is.null(tab$n_filled)) rep(TRUE, nrow(tab)) else
    !is.na(tab$n_filled) & tab$n_filled > 0L
  ok & distinct & filled
}

#' @noRd
synth_document <- function(sections) {
  paste(sprintf("## %s\n\n%s", sections$section, trimws(sections$text)), collapse = "\n\n")
}

#' Render a kept revision, leaving the markers the sections' checks reported.
#'
#' A revision is one text, and the check that caught a section citing a study
#' it was never given ran on the sections. Leaving only the studies that NO
#' section was given, as this once did, rendered the fabricated citation as an
#' author-year fact wherever another section had cited the same study honestly
#' -- which, with claims, is nearly every study -- while print() said the
#' marker had been left.
#'
#' So every sentence citing a reported study is followed from the draft
#' through each kept pass in turn. In the draft it is honest if its section was
#' given the study and reported if not. In each pass's text the sections are
#' found again by the `## ` headings the draft was assembled with, and a
#' sentence citing the study is
#'
#'   * honest if it is, word for word, a sentence only an honest one was,
#'     wherever it now stands;
#'   * reported under the heading of a section that reported the study, or
#'     under no heading of the draft (a preamble, a renamed section);
#'   * under the heading of a section given the study: honest or reported as
#'     the sentence it repeats word for word, and a reworded or new sentence is
#'     honest only if nothing says a reported marker could be in it -- the
#'     pass kept every reported marker where it can be seen (none deleted, none
#'     reworded away, no honest sentence taken into a reporting section), the
#'     section has no more such sentences than it lost honest ones, and the
#'     sentence has no more words in common with the reported sentences than
#'     with the honest ones it may replace.
#'
#' A marker is rendered only in an honest sentence. Following the passes one at
#' a time is what tells a cut that deleted the reported clause, then a
#' register pass that polished the honest one, from a pass that wrote the
#' reported clause into the honest sentence. Counting markers per section, as
#' this did before, took the deletion for a move and left the honest citation
#' as a marker with its reference dropped; and counts that did not change let
#' two sections trade claims unseen. Where this cannot tell, it leaves the
#' marker and says so in `unrendered`.
#'
#' `texts` is each kept pass's text in order, the last one published (one text
#' will do). `headings`, `marked` and `unsupplied` are per section: its
#' heading, its marked text, and the studies its check reported. `render(x,
#' leave)` renders one piece of text. Returns the rendered `text`; `left`, the
#' reported studies no marker was rendered for anywhere, which the reference
#' list omits; and `unrendered`, the studies a section cited honestly that are
#' left somewhere for want of telling that citation from the reported one.
#' @noRd
render_revised <- function(texts, headings, marked, unsupplied, render) {
  texts <- as.character(texts)
  text <- texts[length(texts)]
  reported <- unique(as.integer(unlist(unsupplied)))
  if (!length(reported)) {
    return(list(text = render(text, integer(0)), left = integer(0), unrendered = integer(0)))
  }
  secs <- unique(headings)
  own <- lapply(secs, function(h) unique(as.integer(unlist(unsupplied[headings == h]))))
  reports <- function(i, j) !is.na(i) && j %in% own[[i]]

  # Per sentence: the reported studies it cites, once per marker as the check
  # reads them (read once per distinct marker: a long review repeats a few
  # hundred); the sentence with its spacing evened out, which is what "word for
  # word" compares; and its words, for comparing a reworded one.
  grammar <- cite_grammar("study")$marker
  seen <- new.env(parent = emptyenv())
  marker_ids <- function(k) seen[[k]] %||% (seen[[k]] <- unique(cite_marker_ids(k, "study")))
  ids_of <- function(spans) lapply(spans, function(x) {
    if (!grepl("[", x, fixed = TRUE)) return(integer(0))
    mk <- regmatches(x, gregexpr(grammar, x, perl = TRUE, ignore.case = TRUE))[[1]]
    ids <- unlist(lapply(mk, marker_ids), use.names = FALSE)
    ids[ids %in% reported]
  })
  norm <- function(x) gsub("[[:space:]]+", " ", trimws(x))
  said <- new.env(parent = emptyenv())
  words <- function(x) {
    x <- unique(x[nzchar(x)])
    new <- x[!vapply(x, exists, logical(1), envir = said, inherits = FALSE)]
    if (length(new)) {
      low <- lower_text(to_utf8(gsub(grammar, " ", new, perl = TRUE, ignore.case = TRUE)))
      for (q in seq_along(new)) {
        w <- strsplit(low[q], "[^\\p{L}\\p{N}]+", perl = TRUE)[[1]]
        assign(new[q], unique(w[(nchar(w) >= 3L | grepl("[0-9]", w)) &
                                  !w %in% .gr_revise_stopwords]), envir = said)
      }
    }
    unique(unlist(mget(x, envir = said), use.names = FALSE))
  }
  # How many of `a` are not matched in `b`, counting repeats.
  missing_from <- function(a, b) {
    if (!length(a)) return(0L)
    ta <- table(a)
    sum(pmax(0L, as.integer(ta) - as.integer(table(factor(b, levels = names(ta))))))
  }
  # Which sentences cite each study, once per marker: by study, the positions.
  by_study <- function(ids) split(rep(seq_along(ids), lengths(ids)), unlist(ids))
  sentences <- function(span, sec) {
    out <- list(span = span, sec = sec, key = norm(span), ids = ids_of(span))
    # Every sentence that may need comparing, in one call rather than many.
    words(out$key[lengths(out$ids) > 0L])
    out
  }
  # A pass's text, cut before every heading line and then into sentences, so
  # pasting the spans back gives the text exactly.
  read_text <- function(x) {
    at <- gregexpr("(?m)^##[ \t]+[^\n]*", x, perl = TRUE)[[1]]
    at <- if (at[1] > 0L) as.integer(at) else integer(0)
    starts <- unique(c(1L, at))
    pieces <- substring(x, starts, c(starts[-1] - 1L, nchar(x)))
    first <- sub("(?s)\n.*$", "", pieces, perl = TRUE)
    head_of <- ifelse(starts %in% at,
                      trimws(sub("[ \t]+#+[ \t]*$", "", sub("^##[ \t]+", "", first))), NA_character_)
    sp <- lapply(pieces, sentence_spans)
    sentences(unlist(sp, use.names = FALSE), rep(match(head_of, trimws(secs)), lengths(sp)))
  }

  # The draft: every sentence citing a reported study, honest or reported.
  d_span <- lapply(secs, function(h) sentence_spans(paste(trimws(marked[headings == h]),
                                                          collapse = "\n\n")))
  state <- sentences(unlist(d_span, use.names = FALSE), rep(seq_along(secs), lengths(d_span)))
  state$status <- lapply(seq_along(state$key), function(s) {
    u <- unique(state$ids[[s]])
    stats::setNames(ifelse(vapply(u, reports, logical(1), i = state$sec[s]), "reported", "honest"),
                    u)
  })
  cited_honestly <- unique(unlist(lapply(state$status, function(st) names(st)[st == "honest"])))
  # The words of every sentence citing a study that has not been honest, in
  # the draft or any pass since. A pass sees only the text before it, but what
  # it rewords may have been reported a pass or two earlier.
  suspect_words <- list()
  remember <- function(st) {
    for (s in seq_along(st$key)) {
      for (jc in names(st$status[[s]])[st$status[[s]] != "honest"]) {
        suspect_words[[jc]] <<- union(suspect_words[[jc]], words(st$key[s]))
      }
    }
  }
  remember(state)

  # One kept pass: the statuses of `new`'s sentences, from `prev`'s.
  follow <- function(prev, new) {
    status <- lapply(new$ids, function(v) {
      u <- unique(v)
      stats::setNames(rep("honest", length(u)), u)
    })
    at_prev <- by_study(prev$ids)
    at_new <- by_study(new$ids)
    for (jc in intersect(names(at_new), as.character(reported))) {
      j <- as.integer(jc)
      pi <- at_prev[[jc]] %||% integer(0)
      pu <- unique(pi)
      pst <- vapply(pu, function(s) prev$status[[s]][[jc]], character(1))
      hon <- prev$key[pu][pst == "honest"]
      sus <- prev$key[pu][pst != "honest"]
      hon_only <- setdiff(hon, sus)
      # A sentence repeated word for word keeps its status; "unsure" wins over
      # "reported", so a doubt already declared is not forgotten.
      as_before <- function(key) {
        st <- pst[pst != "honest" & prev$key[pu] == key]
        if ("unsure" %in% st) "unsure" else "reported"
      }
      ni <- at_new[[jc]]
      nu <- unique(ni)
      cls <- vapply(nu, function(s) {
        key <- new$key[s]; i <- new$sec[s]
        if (key %in% hon_only) return("honest")
        if (is.na(i)) return(if (key %in% sus) as_before(key) else "unsure")
        if (j %in% own[[i]]) {
          if (key %in% sus) return(as_before(key))
          # Reworded under a reporting heading is the reported sentence --
          # unless an honest one had been standing there to be reworded.
          return(if (any(prev$sec[pu][pst == "honest"] %in% i)) "unsure" else "reported")
        }
        if (key %in% hon) return("honest")
        if (key %in% sus) return(as_before(key))
        "pending"
      }, character(1))
      # Whether a reported marker may have gone into a reworded sentence: fewer
      # markers are accounted for than the pass was given, or a reporting
      # section took in a sentence only an honest one wrote, which is what a
      # trade of claims leaves.
      kept <- sum(ni %in% nu[cls %in% c("reported", "unsure")])
      moved <- kept < sum(pi %in% pu[pst != "honest"]) ||
        any(vapply(nu[cls == "honest"], function(s) reports(new$sec[s], j), logical(1)))
      if (any(cls == "pending")) w_sus <- union(suspect_words[[jc]], words(sus))
      for (i in unique(new$sec[nu[cls == "pending"]])) {
        mine <- nu[cls == "pending" & new$sec[nu] %in% i]
        was <- prev$key[pu][pst == "honest" & prev$sec[pu] %in% i]
        now <- new$key[nu[new$sec[nu] %in% i]]
        ok <- !moved && length(mine) <= missing_from(was, now)
        w_was <- words(was)
        cls[match(mine, nu)] <- vapply(mine, function(s) {
          if (!ok) return("unsure")
          # Reworded: honest only if it reads no more like the reported
          # sentences than like the honest ones it may replace.
          w <- words(new$key[s])
          k <- sum(w %in% w_sus)
          if (k > 0L && k >= sum(w %in% w_was)) "unsure" else "honest"
        }, character(1))
      }
      for (q in seq_along(nu)) status[[nu[q]]][[jc]] <- cls[q]
    }
    new$status <- status
    new
  }
  for (x in texts) {
    state <- follow(state, read_text(x))
    remember(state)
  }

  leave <- lapply(state$status, function(st) as.integer(names(st)[st != "honest"]))
  rendered <- unique(unlist(lapply(state$status, function(st) names(st)[st == "honest"])))
  unsure <- unique(unlist(lapply(state$status, function(st) names(st)[st == "unsure"])))
  spans <- state$span
  if (!length(spans)) return(list(text = text, left = reported, unrendered = integer(0)))
  # Consecutive sentences leaving the same studies are rendered together, which
  # is every sentence of a text with nothing to leave.
  sig <- vapply(leave, function(v) paste(sort(v), collapse = ","), character(1))
  run <- cumsum(c(TRUE, sig[-1L] != sig[-length(sig)]))
  out <- vapply(split(seq_along(spans), run), function(ix) {
    render(paste(spans[ix], collapse = ""), leave[[ix[1L]]])
  }, character(1), USE.NAMES = FALSE)
  list(text = paste(out, collapse = ""),
       left = setdiff(reported, as.integer(rendered)),
       unrendered = sort(as.integer(intersect(unsure, cited_honestly))))
}

#' @noRd
append_references <- function(body, references) {
  if (!length(references)) return(body)
  paste0(body, "\n\n## References\n\n", paste(references, collapse = "\n"))
}

#' @noRd
synth_empty_citations <- function() {
  data.frame(section = character(0), study = integer(0), document = character(0),
             document_id = character(0), stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# Ordering for emphasis, and structure from the claims.
# ---------------------------------------------------------------------------

#' How much of a section a study is worth, for emphasis only.
#'
#' NOT a quality score, and deliberately NOT a design hierarchy. Ranking designs
#' would mean asserting that a cohort study beats a qualitative one, which is a
#' methodological claim this package has no standing to make on its own -- and
#' adding up per-item scores to get a total is the thing Cochrane says plainly is
#' discouraged. Design earns its place as a GROUPING variable instead: it is what
#' distinguishes the studies on each side of a disagreement, and what
#' [gr_gaps()] crosstabs.
#'
#' What is left is what the table can honestly support: how many units were
#' analysed, and how completely the row was filled with evidence that verified.
#' A principled weighting waits on `gr_appraise()` and a named instrument.
#' @noRd
study_weight <- function(used) {
  # numeric_token(), not as.numeric(): an `n` column reading "900 participants"
  # is not missing data, and as.numeric() made it NA. NA then scored 0 -- the
  # bottom of the scale -- so a 900-participant study weighed LESS than one with
  # 25, and claim_order() put the small study's claim first.
  n <- n_column(used$n %||% rep(NA, nrow(used)))
  # log1p, because the difference between 20 and 200 participants matters far
  # more than the difference between 2000 and 2180.
  size <- log1p(ifelse(is.na(n) | n < 0, NA_real_, n))
  mx <- suppressWarnings(max(size, na.rm = TRUE))
  size <- if (is.finite(mx) && mx > 0) size / mx else rep(NA_real_, length(size))
  # An `n` nobody reported is UNKNOWN, not zero -- the same distinction the
  # `filled` term below already makes by scoring NA at 0.5 rather than 0. Zero
  # punished a study for a cell the extraction could not fill.
  mid <- if (any(!is.na(size))) mean(size, na.rm = TRUE) else 0
  size[is.na(size)] <- mid
  filled <- suppressWarnings(as.numeric(used$n_filled %||% rep(NA, nrow(used))))
  unver <- suppressWarnings(as.numeric(used$n_unverified %||% rep(0, nrow(used))))
  unver[is.na(unver)] <- 0
  # A row whose values are there and whose quotes were found is worth more than
  # one held together by misses. NA filled counts as neither good nor bad.
  ok <- ifelse(is.na(filled) | filled <= 0, 0.5,
               pmax(0, (filled - unver)) / pmax(filled, 1))
  stats::setNames(0.5 + 0.5 * size + 0.5 * ok, as.character(used$study))
}
