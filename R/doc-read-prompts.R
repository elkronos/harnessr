# doc-read-prompts.R: the prompts the readers send.

# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------

.gr_prompts <- list(
  answer_system = paste0(
    "You answer questions using only the supplied document excerpts. ",
    "If the excerpts do not contain the answer, say exactly: NOT_IN_DOCUMENT. ",
    "Never use outside knowledge. Quote figures, dates and names exactly as written."),
  answer_system_cited = paste0(
    "You answer questions using only the supplied document excerpts. ",
    "If the excerpts do not contain the answer, say exactly: NOT_IN_DOCUMENT. ",
    "Never use outside knowledge. Quote figures, dates and names exactly as written. ",
    "Cite the excerpt you relied on for each claim using its bracketed id, e.g. [chunk 3]."),
  extract_system = paste0(
    "You extract evidence, not answers. Copy out the passages of the excerpt that bear on ",
    "the question, verbatim and without commentary. If nothing in the excerpt is relevant, ",
    "reply with exactly: NONE."),
  summarise_system = paste0(
    "You compress text while preserving everything that could bear on the question. ",
    "Keep all specific figures, dates, names and qualifications. Drop only material that ",
    "cannot possibly relate to the question."),
  merge_system = paste0(
    "You consolidate partial findings into one answer. Resolve contradictions by preferring ",
    "the finding with concrete supporting detail, and say so when findings genuinely conflict. ",
    "Do not introduce anything absent from the findings. If none of them answer the question, ",
    "say exactly: NOT_IN_DOCUMENT."),
  refine_system = paste0(
    "You revise a draft answer using a new excerpt. Add what the excerpt supports, correct what ",
    "it contradicts, and leave the rest of the draft alone. Return the complete revised answer, ",
    "not a description of your edits."),
  synthesise_system = paste0(
    "You write the '%s' section of a review, using only the study records supplied. Cite the ",
    "record behind every claim with its bracketed id, e.g. [study 3], and cite more than one ",
    "where more than one supports it. Say where the records disagree and where they are silent; ",
    "'not reported' is a finding and worth stating. Do not add studies, figures or conclusions ",
    "that are not in the records, and do not cite an id that is not there. Write prose for the ",
    "section only -- no heading, no preamble, no closing summary of what you just wrote."),
  preview_system = paste0(
    "You plan how to read a document, before reading it. You are given the question and an ",
    "outline: one line per section, with its size and a short excerpt. Decide, for each ",
    "section, whether it must be read in full ('read'), is worth scanning for stray relevant ",
    "detail ('skim'), or cannot bear on the question and should be skipped ('skip'). Reading ",
    "everything in full is the expensive default you are here to improve on, so mark 'read' ",
    "only where the section is likely to contain the answer itself. When the outline is too ",
    "thin to tell, prefer 'skim' over 'skip': a skipped section is never looked at again. Give ",
    "a short reason for each decision."),
  claims_system = paste0(
    "You turn a table of studies into a list of CLAIMS about the literature.\n\n",
    "A claim is a statement about the body of work, not about one study. ",
    "\"Trials in clinical samples found a benefit and the two community samples did not\" is a ",
    "claim. \"Study 4 found a benefit\" is not -- that is a row, and the table already has it.\n\n",
    "Rules:\n",
    "- Every claim names the studies it rests on, by the [study N] numbers shown. ",
    "Use only numbers that appear. Never invent one.\n",
    "- Where studies disagree, put the ones supporting the claim in supported_by and the ones ",
    "contradicting it in contradicted_by, and name in `moderator` the FIELD NAME from the table ",
    "that distinguishes them, copied exactly. Leave `moderator` null if nothing in the table ",
    "explains the split -- an unexplained disagreement is a finding, and guessing at a reason ",
    "is worse than reporting it as unexplained.\n",
    "- A claim may rest on one study, but say so in `scope`.\n",
    "- Do not write a claim you cannot attach to at least one study.\n",
    "- Write the claim itself without citations; the numbers go in the fields."),
  reconcile_system = paste0(
    "You are given numbered claims drawn from different batches of ONE literature. ",
    "Group the ones that make the same assertion.\n\n",
    "- Return every number exactly once, in exactly one group.\n",
    "- Two claims belong together only if they assert the same thing. Claims about different ",
    "populations, different measures, or opposite directions are DIFFERENT claims even when ",
    "they are worded alike.\n",
    "- A claim that matches nothing else is a group of one.\n",
    "- Do not write new claims and do not use numbers that were not listed."),
  outline_system = paste0(
    "You are given the CLAIMS a body of literature supports. Group them into the sections of a ",
    "review.\n\n",
    "The grouping is the review's argument, so group by what the claims are ABOUT -- a shared ",
    "population, a shared measure, a shared disagreement -- not by the order they are listed ",
    "in.\n\n",
    "Rules:\n",
    "- Every claim number goes in exactly one section. Do not leave one out and do not repeat ",
    "one.\n",
    "- Use only the numbers listed.\n",
    "- A heading names what the section argues, not a topic label. \"Measurement explains the ",
    "disagreement\" is a heading; \"Measurement\" is a label.\n",
    "- Order the sections so the review reads as an argument: what was studied before what was ",
    "found, and disagreements after the claims they are about.\n",
    "- `rationale` says in one line why those claims belong together."),
  claims_section_system = paste0(
    "You write one section of a literature review from a list of CLAIMS and the studies behind ",
    "them.\n\n",
    "Argue the claims. Do not walk through the studies one at a time -- the claims are the ",
    "structure, and a paragraph per study is what this replaces.\n\n",
    "Rules:\n",
    "- Every sentence that makes a claim carries the [study N] markers of the studies it rests ",
    "on. Cite more than one where more than one supports it.\n",
    "- Use only the numbers shown.\n",
    "- Where a claim is contested, say so in the same sentence or the next, and give the ",
    "distinguishing field if one is named. Do not resolve a disagreement the evidence leaves ",
    "open.\n",
    "- Keep every claim's hedging. If a claim rests on one small study, the sentence must say ",
    "something a reader can check that against.\n",
    "- Cover every claim you are given. Do not add claims that are not in the list."),
  coherence_system = paste0(
    "You are given the complete draft of a review, written section by section by ",
    "someone who could not see the other sections while writing. Your job is to make it read as ",
    "one argument. Fix repetition between sections, add the connective sentences that carry a ",
    "reader from one section to the next, and make terminology and tense consistent throughout. ",
    "Keep every heading, in the order given.\n\n",
    "You may not add anything. No new studies, no new figures, no new claims, no conclusion the ",
    "draft does not already reach. Every bracketed citation marker must survive exactly as it is ",
    "written, attached to the same claim -- do not add one, remove one, renumber one, or move one ",
    "to a different sentence. If a section is thin, leave it thin: that is a finding about the ",
    "evidence, and padding it would be inventing evidence. Return the full revised document and ",
    "nothing else."),
  screen_system = paste0(
    "You screen one document against a review's criteria, using only the excerpt supplied. ",
    "Answer 'include' only if the excerpt shows the document meets every inclusion criterion ",
    "and no exclusion criterion. Answer 'exclude' only if the excerpt clearly shows it fails ",
    "one; name that criterion. If the excerpt does not settle the decision, answer 'unclear' -- ",
    "that is a correct and expected answer, and it is much better than a guess, because an ",
    "'unclear' document is looked at by a person while a wrong 'exclude' is never seen again. ",
    "Do not use anything you know about the document from outside the excerpt.")
)

#' How long a body has to be before the question is worth repeating.
#'
#' A number, and an arbitrary one: what it should be is a question about a
#' particular corpus and a particular model, which is why `restate` is a read
#' setting -- gr_compare() can take two recipes differing only in it and measure
#' the difference, rather than the package asserting one.
#' @noRd
.gr_restate_tokens <- 1200L

#' @noRd
restate_now <- function(body, how = "auto") {
  how <- as_chr1(how, "auto")
  if (identical(how, "always")) return(TRUE)
  if (identical(how, "never")) return(FALSE)
  gr_count_tokens(as_chr1(body)) > .gr_restate_tokens
}

#' The question again, after a body long enough to bury the first ask.
#' @noRd
restate_tail <- function(body, question, how = "auto") {
  if (!restate_now(body, how)) return("")
  paste0("\n\nAgain, the question: ", as_chr1(question))
}

#' The system prompt `answer_messages()` will actually send.
#'
#' Named rather than inlined so that the budget can be computed from the same
#' string the call sends. Budgeting with `answer_system` and then sending
#' `answer_system_cited` understates the overhead by 22 tokens whenever
#' `cite = TRUE`, and the excerpts are then sized to fill the gap.
#'
#' `premise`: the premise rule (read-premise.R) is appended here, so every
#' reader that budgets with this string budgets for it.
#' @noRd
answer_system <- function(cite = FALSE, premise = FALSE) {
  base <- if (isTRUE(cite)) .gr_prompts$answer_system_cited else .gr_prompts$answer_system
  if (isTRUE(premise)) paste0(base, .gr_premise_prompts$answer) else base
}

#' Build the standard question-answering message list.
#' @noRd
answer_messages <- function(question, body, cite = FALSE, label = "Excerpts",
                            restate = "auto", premise = FALSE) {
  # The question is already LAST here, which is the position that gets followed.
  # What was missing is the other end: over a few thousand tokens of excerpt, an
  # instruction that appears once at the bottom is easy to lose track of on the
  # way down. Added INSIDE the existing message rather than as a fourth one, so
  # nothing that indexes these positionally shifts.
  lead <- if (restate_now(body, restate)) paste0("Question: ", question, "\n\n") else ""
  list(
    list(role = "system", content = answer_system(cite, premise)),
    list(role = "user", content = paste0(lead, "<", tolower(label), ">\n", body,
                                         "\n</", tolower(label), ">")),
    list(role = "user", content = paste0("Question: ", question))
  )
}
