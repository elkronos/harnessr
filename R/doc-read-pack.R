# doc-read-pack.R: chunks packed into a prompt that fits.

#' Render chunks into a labelled block for a prompt.
#' @noRd
render_chunks <- function(df, ids = NULL) {
  if (!nrow(df)) return("")
  ids <- ids %||% df$chunk_id
  paste(vapply(seq_len(nrow(df)), function(i) {
    loc <- c(if (!is.na(df$page[i])) paste0("p.", page_text(df$page[i])),
             if (!is.na(df$section[i])) sprintf("\u00a7 %s", df$section[i]))
    hdr <- sprintf("[chunk %s%s]", ids[i], if (length(loc)) paste0(" ", paste(loc, collapse = ", ")) else "")
    paste0(hdr, "\n", df$text[i])
  }, character(1)), collapse = "\n\n")
}

#' A page as a label, whatever a segmenter recorded it as.
#'
#' new_chunks() takes provenance as given, and a custom segmenter may record a
#' PDF's page labels ("iv", "A-3") or a fractional page. "%d" took only a whole
#' number, and every reader failed on anything else with a bare sprintf()
#' error that named neither the chunk nor the segmenter. A number is written
#' in full, never as "1e+05".
#' @noRd
page_text <- function(p) {
  if (is.numeric(p)) {
    return(vapply(p, function(v) if (is.na(v)) NA_character_
                  else format(v, scientific = FALSE, trim = TRUE, digits = 15L),
                  character(1), USE.NAMES = FALSE))
  }
  as.character(p)
}

#' Greedily fit as many chunks as the budget allows, in the order given. A chunk
#' that would overflow is skipped, not truncated. Returns the indices used and
#' the rendered body.
#'
#' The multi-chunk readers (`stuff`, `retrieve`, `rerank`) go through this; the
#' rest bound their prompts with `gr_truncate_tokens()` or `tree_merge()`. Every
#' path is bounded one way or the other -- that is the failure mode that produced
#' unbounded merge prompts and HTTP 400s in `gpt_read_chunked()` and
#' `gpt_read_hierarchical()`.
#' @noRd
fit_chunks <- function(df, budget_tokens, order = NULL, prefix = FALSE) {
  idx <- order %||% seq_len(nrow(df))
  used <- integer(0); total <- 0L
  for (i in idx) {
    t <- gr_count_tokens(render_chunks(df[i, , drop = FALSE]))
    if (total + t > budget_tokens) {
      # Skipping over an oversized chunk and carrying on is right for a RANKED
      # order -- take as much of the good stuff as fits. It is wrong for a
      # contiguous read: `screen` shows the model the opening of a document, and
      # an opening assembled from chunks 1, 2 and 47 is not an opening. `prefix`
      # stops at the first thing that does not fit.
      if (prefix) break else next
    }
    used <- c(used, i); total <- total + t
  }
  list(idx = used, tokens = total, dropped = setdiff(idx, used))
}

#' Standard overhead accounting for a reader's prompt.
#' @noRd
prompt_overhead <- function(question, system_prompt, restate = "auto") {
  # The question is counted TWICE unless restatement is off, because that is how
  # many times it appears. `answer_messages()` adds a second copy before the body
  # once the body is long, and the body was sized against a budget computed here
  # -- so the prompt overran the window by exactly the length of the question.
  # With a long question and a model whose window the run nearly fills,
  # gr_call() refused to dispatch at all and the reader returned NOT_IN_DOCUMENT
  # with nothing in it but `notes$error`. The default is the safe direction:
  # reserving room that goes unused costs a little context, under-reserving
  # costs the answer.
  again <- if (identical(as_chr1(restate, "auto"), "never")) 0L else
    gr_count_tokens(as_chr1(question))
  sum(gr_count_tokens(c(as_chr1(question), as_chr1(system_prompt)))) + again + 64L
}

#' The most one request of a batch can cost: `input_tokens` in and the reply
#' at `max_output`, or at the model's own ceiling when that is lower.
#'
#' What gr_lapply() holds a parallel batch to against what the run has spent,
#' since the workers cannot see it. Priced at the model that bills the request:
#' an ellmer chat bills as the model it was built with, whatever the request
#' names. NA when that model has no price, which gr_lapply() counts as the
#' trace counts such a call, as nothing.
#'
#' The reply is priced at the cap the request is sent with, which for a
#' reasoning model is raised to leave room for its reasoning
#' (reasoning_output_cap()): priced at the cap asked for, a 90-token context
#' line or a 200-token relevance score understated what each item can bill by
#' up to about 1,850 tokens.
#' @noRd
batch_item_usd <- function(client, model, input_tokens, max_output) {
  m <- client_billed_model(client) %||% as_chr1(model, "")
  # The request itself warns about an unknown model; once is enough.
  quiet <- function(expr) tryCatch(suppressWarnings(expr, classes = "gr_unknown_model"),
                                   error = function(e) NULL)
  info <- quiet(gr_model_info(m))
  if (is.null(info)) return(NA_real_)
  out <- reasoning_output_cap(min(as_num1(max_output, 0), as_num1(info$max_output, Inf)),
                              info, input_tokens)
  as_num1(quiet(gr_estimate_cost(m, input_tokens, out)), NA_real_)
}

#' The largest of some token counts, 0 for none.
#' @noRd
max_tokens_of <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[!is.na(x)]
  if (length(x)) max(x) else 0
}

#' The document text behind each chunk row, to verify a quotation against.
#'
#' A segmenter that writes model text into `text` -- a contextual header, or
#' propositions rewritten from the source -- keeps the document text it worked
#' from in `source_text`. A quotation is checked against that, so a figure the
#' segmenting model invented cannot verify as a quotation of the document; and
#' verbatim evidence shows it, since that is what the document says. An absent
#' column or an NA means `text` is itself the document's.
#' @noRd
reader_source_text <- function(d) {
  txt <- as.character(d$text)
  src <- d[["source_text"]]
  if (is.null(src)) return(txt)
  src <- as.character(src)
  ifelse(is.na(src), txt, src)
}
