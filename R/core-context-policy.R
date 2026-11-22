# core-context-policy.R: what a request keeps when its text does not fit.
#
# A packer fits named pieces of text into a request: a question, a set of
# instructions, a draft, an excerpt, findings to merge. When they do not fit,
# something is cut. Before this file each packer decided for itself, and every
# cut kept the start of the text. A context policy states once which pieces are
# never cut (pin rules), which are cut first (keep rules) and which part of a
# cut piece is kept (head, tail, both ends, or the units that score highest).
# Nothing here knows what the pieces are; the document layer names them.
#
# Every cut is written to the trace as a "truncate" step that names the piece,
# the part that was dropped and the tokens it held.

.hr_keep_rules <- c("head", "tail", "both", "scored")

#' Cut text to a token count, keeping the part you choose
#'
#' `keep = "head"` (the default) keeps the start of `text` and is
#' [gr_truncate_tokens()] itself, so a caller that switches to this function
#' sends what it sent before. `"tail"` keeps the end, with `marker` at the
#' front. `"both"` keeps the start and the end, about half the budget each,
#' with `marker` between them on a line of its own. `"scored"` splits the text
#' into units (the elements of `text` when it has more than one, else its
#' paragraphs, split at blank lines), keeps the units with the highest
#' `scores` that fit, and joins them with a blank line in their original
#' order, followed by `marker` when any unit was dropped; when no unit fits
#' beside the marker, the units that fit without it are kept with no marker.
#' With `marker = ""`, `"tail"` and `"both"` have the whole budget for text,
#' as `"head"` does; `"both"` keeps only the start when the end has no room,
#' and only the end when no word of the start fits. The result is never
#' longer than `n` tokens.
#'
#' With a `trace`, a cut writes a `"truncate"` step that records `where`,
#' `piece`, `keep`, `dropped_part` (`"end"`, `"start"`, `"middle"`, or the
#' units dropped, as `"units 2, 5"`), the token counts before and after and
#' `tokens_dropped`. Nothing is written when the text fits.
#'
#' @param text A single string; for `keep = "scored"`, a character vector of
#'   units is accepted as well.
#' @param n Maximum token count.
#' @param keep `"head"`, `"tail"`, `"both"` or `"scored"`.
#' @param scores For `keep = "scored"`: one number per unit, higher kept
#'   first. Ties keep the earlier unit.
#' @param marker The text that marks a cut; `""` for none. As in
#'   [gr_truncate_tokens()], it is dropped when it would cost half the budget
#'   or more.
#' @param trace Optional `gr_trace` to write the cut to.
#' @param where The cut site, written to the trace, in the dotted style of
#'   call labels (`"refine.draft"`).
#' @param piece The name of the piece that was cut, written to the trace, or
#'   `NULL`.
#' @return A single string.
#' @seealso [hr_context_policy()], [hr_context_fit()], [gr_truncate_tokens()]
#' @family cost and token functions
#' @export
#' @examples
#' txt <- paste("Para", 1:6, "says something about revenue.", collapse = "\n\n")
#' hr_truncate(txt, 20)                      # the start, as gr_truncate_tokens()
#' hr_truncate(txt, 20, keep = "tail")       # the end
#' cat(hr_truncate(txt, 24, keep = "both"))  # both ends
#' # The paragraphs that score highest, in document order.
#' cat(hr_truncate(txt, 20, keep = "scored", scores = c(1, 9, 2, 8, 3, 4)))
#'
#' # The cut is written to a trace.
#' tr <- gr_trace()
#' invisible(hr_truncate(txt, 20, keep = "tail", trace = tr, where = "demo", piece = "notes"))
#' tr$steps[[1]]$detail[c("where", "piece", "dropped_part", "tokens_dropped")]
hr_truncate <- function(text, n, keep = c("head", "tail", "both", "scored"), scores = NULL,
                        marker = " ...[truncated]", trace = NULL, where = "truncate",
                        piece = NULL) {
  keep <- match_keep(keep)
  marker <- as_chr1(marker, "")
  if (!identical(keep, "scored") || length(text) <= 1L) text <- as_chr1(text, "")
  if (identical(keep, "head")) {
    out <- gr_truncate_tokens(text, n, marker)
    log_cut(trace, where, piece, keep, text, out, n, marker,
            if (nzchar(out) || !nzchar(text)) "end" else "all")
    return(out)
  }
  force(n)
  n <- suppressWarnings(as.numeric(n)[1])
  if (is.na(n)) n <- 0
  if (identical(keep, "scored")) return(truncate_scored(text, n, scores, marker, trace, where,
                                                        piece))
  text <- mark_utf8(text)
  if (is.infinite(n) && n > 0) return(text)
  n <- as.integer(clamp(n, 0, .Machine$integer.max))
  if (n <= 0L || !nzchar(text)) {
    log_cut(trace, where, piece, keep, text, "", n, "", "all")
    return("")
  }
  if (gr_count_tokens(text) <= n) return(text)
  if (!validUTF8(text)) text <- to_utf8(text)
  mk <- trimws(marker)
  if (gr_count_tokens(mk) >= n / 2) mk <- ""
  # The marker and the space or line that joins it cost what they cost; with
  # no marker the whole budget is the text's.
  budget <- if (nzchar(mk)) max(n - gr_count_tokens(mk) - 1L, 1L) else n
  tail_cut <- function() {
    kept <- tail_tokens(text, budget)
    out <- if (nzchar(mk) && nzchar(kept)) paste0(mk, " ", kept) else kept
    if (gr_count_tokens(out) > n) out <- kept
    log_cut(trace, where, piece, "tail", text, kept, n, "", if (nzchar(kept)) "start" else "all")
    out
  }
  if (identical(keep, "tail")) return(tail_cut())
  # "both": the start and the end, the budget split between them. The start
  # takes the first half; when no word of the start fits in it, the start
  # takes what the whole budget allows and the end what is left.
  sep <- if (nzchar(mk)) paste0("\n", mk, "\n") else "\n"
  first <- gr_truncate_tokens(text, max(budget %/% 2L, 1L), marker = "")
  if (!nzchar(first)) first <- gr_truncate_tokens(text, budget, marker = "")
  if (!nzchar(first)) {
    # Not even the start fits: keep what the end allows, as "tail" does.
    return(tail_cut())
  }
  rest <- substr(text, nchar(first) + 1L, nchar(text))
  last <- tail_tokens(rest, max(budget - gr_count_tokens(first), 0L))
  while (nzchar(last) && gr_count_tokens(paste0(first, sep, last)) > n) {
    last <- tail_tokens(last, max(gr_count_tokens(last) - 2L, 0L))
  }
  if (!nzchar(last)) {
    # No room for the end: keep the start, as "head" does.
    out <- gr_truncate_tokens(text, n, marker)
    log_cut(trace, where, piece, "both", text, out, n, marker, "end")
    return(out)
  }
  out <- paste0(first, sep, last)
  log_cut(trace, where, piece, keep, text, paste0(first, last), n, "", "middle")
  out
}

#' A keep rule, matched, with an error that names the choices.
#' @noRd
match_keep <- function(keep, arg = "keep") {
  if (identical(keep, .hr_keep_rules)) return("head")
  ok <- is.character(keep) && length(keep) == 1L && !is.na(keep) && keep %in% .hr_keep_rules
  if (!ok) {
    gr_abort(sprintf("`%s` must be one of %s.", arg,
                     paste0("\"", .hr_keep_rules, "\"", collapse = ", ")),
             class = "gr_bad_setting")
  }
  keep
}

#' The end of `text` that fits `n` tokens, starting at a word where the text
#' has white space, else at a character.
#' @noRd
tail_tokens <- function(text, n) {
  n <- as.integer(n)
  if (n <= 0L || !nzchar(text)) return("")
  if (gr_count_tokens(text) <= n) return(text)
  len <- nchar(text)
  fits <- function(k) gr_count_tokens(substr(text, k, len)) <= n
  # The smallest start position that fits.
  lo <- 1L; hi <- len + 1L
  while (lo < hi) {
    mid <- (lo + hi) %/% 2L
    if (fits(mid)) hi <- mid else lo <- mid + 1L
  }
  start <- lo
  if (start > len) return("")
  # Forward to the start of the next word, unless that leaves nothing.
  if (start > 1L && !grepl("[[:space:]]", substr(text, start - 1L, start - 1L))) {
    m <- regexpr("[[:space:]]+", substr(text, start, len))
    if (m > 0L) {
      nxt <- start + as.integer(m) - 1L + attr(m, "match.length")
      if (nxt <= len) start <- nxt
    }
  }
  sub("^[[:space:]]+", "", substr(text, start, len))
}

#' keep = "scored": the units with the highest scores that fit, in order.
#' @noRd
truncate_scored <- function(text, n, scores, marker, trace, where, piece) {
  units <- if (length(text) > 1L) as.character(text) else {
    u <- strsplit(as_chr1(text, ""), "\n[[:space:]]*\n")[[1]]
    if (!length(u)) "" else u
  }
  units[is.na(units)] <- ""
  if (is.null(scores) || !is.numeric(scores) || length(scores) != length(units) ||
      anyNA(scores)) {
    gr_abort(sprintf(paste0("`keep = \"scored\"` needs `scores`, one number per unit: the text ",
                            "has %d unit(s) (its elements, or its paragraphs split at blank ",
                            "lines)."), length(units)), class = "gr_bad_setting")
  }
  whole <- paste(units, collapse = "\n\n")
  if (is.infinite(n) && n > 0) return(whole)
  n <- as.integer(clamp(n, 0, .Machine$integer.max))
  if (gr_count_tokens(whole) <= n && n > 0L) return(whole)
  mk <- trimws(marker)
  if (gr_count_tokens(mk) >= n / 2) mk <- ""
  ord <- order(-scores, seq_along(units))
  pick <- function(budget) {
    kept <- integer(0)
    for (i in ord) {
      try_ids <- sort(c(kept, i))
      if (gr_count_tokens(paste(units[try_ids], collapse = "\n\n")) <= budget) kept <- try_ids
    }
    kept
  }
  kept <- pick(if (nzchar(mk)) n - gr_count_tokens(mk) - 1L else n)
  # A unit that fits only without the marker is kept without it.
  if (!length(kept) && nzchar(mk)) {
    mk <- ""
    kept <- pick(n)
  }
  body <- paste(units[kept], collapse = "\n\n")
  out <- if (length(kept) && nzchar(mk)) paste0(body, "\n\n", mk) else body
  if (gr_count_tokens(out) > n) out <- body
  gone <- setdiff(seq_along(units), kept)
  log_cut(trace, where, piece, "scored", whole, body, n, "",
          if (length(gone)) paste("units", paste(gone, collapse = ", ")) else "none")
  out
}

#' Write a cut to the trace, with the piece and the part dropped.
#' @noRd
log_cut <- function(trace, where, piece, keep, before, kept, n, marker, part) {
  if (is.null(trace) || identical(as_chr1(before, ""), as_chr1(kept, ""))) return(invisible(0L))
  trace_truncation(trace, as_chr1(where, "truncate"), before, kept, limit = n, marker = marker,
                   piece = if (is.null(piece)) NA_character_ else as_chr1(piece),
                   keep = keep, dropped_part = part)
}

#' Rules for what a request keeps when its text does not fit
#'
#' A context policy tells a packer, the code that fits named pieces of text
#' into a request, what to do when they do not fit. `pin` names the pieces
#' that are never cut, such as the question and the instructions. `cut_order`
#' names the pieces cut first, in order; the pieces it does not name are cut
#' after them, the last piece of the request first. `keep` says which part
#' of a cut piece is kept (see [hr_truncate()]): one rule for every piece, or
#' a character vector named by piece, with an unnamed element as the rule for
#' the pieces it does not name. `order_merges = TRUE` asks the packers that
#' merge findings to place them by the read's `context_order` as well; see
#' [gr_read_spec()] for which packers those are.
#'
#' [hr_context_fit()] applies a policy to a set of pieces. In the document
#' layer, a read takes one as the `context_policy` setting of
#' [gr_read_spec()]; `NULL`, the default, keeps each reader's own cuts.
#'
#' @param pin Names of pieces that are never cut.
#' @param cut_order Names of pieces cut first, in order.
#' @param keep `"head"`, `"tail"`, `"both"` or `"scored"`, or a character
#'   vector of them named by piece.
#' @param order_merges Whether merge packers follow `context_order`.
#' @param x An `hr_context_policy`.
#' @param ... Ignored.
#' @return An object of class `hr_context_policy`: a list of `pin`,
#'   `cut_order`, `keep` and `order_merges`.
#' @seealso [hr_context_fit()], [hr_truncate()], [gr_read_spec()]
#' @family cost and token functions
#' @export
#' @examples
#' p <- hr_context_policy(pin = c("question", "instructions", "draft"),
#'                        keep = c(excerpt = "both", "head"))
#' p
hr_context_policy <- function(pin = c("question", "instructions"), cut_order = character(0),
                              keep = "head", order_merges = FALSE) {
  names_ok <- function(x) is.character(x) && !anyNA(x) && all(nzchar(trimws(x)))
  if (is.null(pin)) pin <- character(0)
  if (is.null(cut_order)) cut_order <- character(0)
  if (!names_ok(pin) && length(pin)) {
    gr_abort("`pin` must be a character vector of piece names.", class = "gr_bad_setting")
  }
  if (!names_ok(cut_order) && length(cut_order)) {
    gr_abort("`cut_order` must be a character vector of piece names.", class = "gr_bad_setting")
  }
  both <- intersect(pin, cut_order)
  if (length(both)) {
    gr_abort(sprintf("%s is both pinned and in `cut_order`; a pinned piece is never cut.",
                     paste0("'", both, "'", collapse = ", ")), class = "gr_bad_setting")
  }
  if (!is.character(keep) || !length(keep) || anyNA(keep) || !all(keep %in% .hr_keep_rules)) {
    gr_abort(sprintf("`keep` must be one or more of %s, named by piece.",
                     paste0("\"", .hr_keep_rules, "\"", collapse = ", ")),
             class = "gr_bad_setting")
  }
  kn <- names(keep) %||% rep("", length(keep))
  kn[is.na(kn)] <- ""
  if (sum(!nzchar(kn)) > 1L || anyDuplicated(kn[nzchar(kn)])) {
    gr_abort("`keep` may have one unnamed rule and one rule per piece name.",
             class = "gr_bad_setting")
  }
  if (!isTRUE(order_merges) && !isFALSE(order_merges)) {
    gr_abort("`order_merges` must be TRUE or FALSE.", class = "gr_bad_setting")
  }
  structure(list(pin = unique(as.character(pin)), cut_order = unique(as.character(cut_order)),
                 keep = keep, order_merges = order_merges), class = "hr_context_policy")
}

#' @rdname hr_context_policy
#' @export
print.hr_context_policy <- function(x, ...) {
  kn <- names(x$keep) %||% rep("", length(x$keep))
  keep <- ifelse(nzchar(kn), paste0(kn, " = ", x$keep), unname(x$keep))
  cat("<hr_context_policy>\n")
  cat(sprintf("  pin:          %s\n", if (length(x$pin)) paste(x$pin, collapse = ", ") else "-"))
  cat(sprintf("  cut first:    %s\n",
              if (length(x$cut_order)) paste(x$cut_order, collapse = ", ") else "-"))
  cat(sprintf("  keep:         %s\n", paste(keep, collapse = ", ")))
  cat(sprintf("  order merges: %s\n", x$order_merges))
  invisible(x)
}

#' The keep rule a policy gives a piece. `"scored"` becomes `"head"` when the
#' packer has no scores for the piece.
#' @noRd
policy_keep <- function(policy, piece, scored = FALSE) {
  keep <- policy$keep
  kn <- names(keep) %||% rep("", length(keep))
  kn[is.na(kn)] <- ""
  rule <- if (piece %in% kn) keep[[which(kn == piece)[1]]]
          else if (any(!nzchar(kn))) keep[[which(!nzchar(kn))[1]]] else "head"
  if (identical(rule, "scored") && !isTRUE(scored)) "head" else unname(rule)
}

#' Fit named pieces of text into a token budget under a context policy
#'
#' When the pieces together are longer than `budget` tokens, cuts them under
#' `policy` ([hr_context_policy()]): pinned pieces are never cut; the pieces
#' in `cut_order` are cut first, in order, and then the others, the last
#' piece first. Each piece is cut only as far as the total needs, by
#' [hr_truncate()] with the piece's keep rule, and a piece that must go
#' entirely becomes `""`. Each cut is written to `trace` as a `"truncate"`
#' step with `where` set to `"<where>.<piece>"`.
#'
#' @param pieces A named character vector (or a named list of single
#'   strings), in the order the request carries them.
#' @param budget The most tokens the pieces may hold together.
#' @param policy An [hr_context_policy()].
#' @param scores For pieces cut with `keep = "scored"`: a list of score
#'   vectors named by piece. A piece without scores is cut with `"head"`.
#' @param trace Optional `gr_trace`.
#' @param where The packer's name, the start of each cut's `where`.
#' @return A list of `pieces` (named character, in the order given), `fits`
#'   (whether they now fit; `FALSE` when the pinned pieces alone do not),
#'   `tokens` (their total), `cut` (the names of the pieces cut) and
#'   `tokens_dropped`.
#' @seealso [hr_context_policy()], [hr_truncate()]
#' @family cost and token functions
#' @export
#' @examples
#' pieces <- c(question = "What was revenue?",
#'             draft = paste(rep("Revenue rose.", 30), collapse = " "),
#'             excerpt = paste(rep("Costs fell.", 30), collapse = " "))
#' fit <- hr_context_fit(pieces, 80, hr_context_policy(pin = c("question", "draft")))
#' vapply(fit$pieces, gr_count_tokens, numeric(1))
#' fit$cut
hr_context_fit <- function(pieces, budget, policy = hr_context_policy(), scores = NULL,
                           trace = NULL, where = "context") {
  if (is.list(pieces)) pieces <- vapply(pieces, function(p) as_chr1(p, ""), character(1))
  nm <- names(pieces)
  if (!is.character(pieces) || is.null(nm) || anyNA(nm) || !all(nzchar(nm)) ||
      anyDuplicated(nm)) {
    gr_abort("`pieces` must be a character vector with a distinct name for every piece.",
             class = "gr_bad_setting")
  }
  if (!inherits(policy, "hr_context_policy")) {
    gr_abort("`policy` must come from hr_context_policy().", class = "gr_bad_setting")
  }
  budget <- suppressWarnings(as.numeric(budget)[1])
  if (is.na(budget) || budget < 0) {
    gr_abort("`budget` must be one number of tokens, 0 or more.", class = "gr_bad_setting")
  }
  pieces[is.na(pieces)] <- ""
  size <- function() sum(gr_count_tokens(pieces))
  total <- size()
  cut <- character(0)
  dropped <- 0
  if (total > budget) {
    free <- setdiff(nm, policy$pin)
    seq_cut <- c(intersect(policy$cut_order, free), rev(setdiff(free, policy$cut_order)))
    for (p in seq_cut) {
      excess <- total - budget
      if (excess <= 0) break
      had <- gr_count_tokens(pieces[[p]])
      if (had <= 0) next
      target <- had - excess
      sc <- scores[[p]]
      rule <- policy_keep(policy, p, scored = !is.null(sc))
      before <- pieces[[p]]
      pieces[[p]] <- if (target <= 0) {
        log_cut(trace, paste0(where, ".", p), p, rule, before, "", 0L, "", "all")
        ""
      } else {
        hr_truncate(before, target, keep = rule, scores = sc, trace = trace,
                    where = paste0(where, ".", p), piece = p)
      }
      cut <- c(cut, p)
      dropped <- dropped + max(had - gr_count_tokens(pieces[[p]]), 0)
      total <- size()
    }
  }
  list(pieces = pieces, fits = total <= budget, tokens = total, cut = cut,
       tokens_dropped = dropped)
}
