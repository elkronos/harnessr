# core-context-truncate.R: cut text to a token count.

#' Truncate text to at most `n` tokens
#'
#' The result is the start of `text` as written -- line breaks, indentation and
#' paragraph breaks kept -- followed by `marker`. The cut falls at the end of a
#' word where the text has whitespace. When the next unit is too long to be a
#' word (a CJK run, base64, a data URI, minified JSON, a long URL: anything that
#' alone would cost more than 16 tokens) the cut goes inside it at a character,
#' so a long unbroken run fills the budget instead of being dropped whole;
#' otherwise the cap would be unenforceable, or nearly all of it wasted, for
#' exactly the inputs that most need it. Returns `""` for empty input and never
#' returns `NA`.
#'
#' @param text A single string.
#' @param n Maximum token count.
#' @param marker Appended when truncation occurred; set `""` to suppress. It is
#'   dropped when it would cost half the budget or more.
#' @return A single string. `""` when `n <= 0` or the input is blank. This is
#'   not treated as an error.
#' @seealso [gr_count_tokens()]
#' @family cost and token functions
#' @export
#' @examples
#' gr_truncate_tokens(paste(rep("alpha beta gamma", 40), collapse = " "), 20)
#' gr_truncate_tokens("short enough already", 100)
#'
#' # A table keeps its rows.
#' cat(gr_truncate_tokens("Arm | N | Events\nA | 482 | 31\nB | 479 | 44\nC | 470 | 50", 24))
gr_truncate_tokens <- function(text, n, marker = " ...[truncated]") {
  text <- mark_utf8(as_chr1(text))
  force(n)   # see clamp(): forcing inside suppressWarnings() eats the caller's warnings
  n <- suppressWarnings(as.numeric(n)[1])
  if (is.na(n)) n <- 0
  if (is.infinite(n) && n > 0) return(text)          # Inf used to crash
  n <- as.integer(clamp(n, 0, .Machine$integer.max))
  if (n <= 0L || !nzchar(text)) return("")
  if (gr_count_tokens(text) <= n) return(text)
  # Positions are characters, and the cuts below are substr() of the text
  # itself; that needs text R can index by character.
  if (!validUTF8(text)) text <- to_utf8(text)

  # Drop the marker when it would eat the whole budget. The old code always
  # subtracted its cost, so every n <= 10 returned "" -- total content loss.
  mk <- if (gr_count_tokens(marker) < n / 2) marker else ""
  budget <- max(n - gr_count_tokens(mk), 1L)
  fits <- function(k) gr_count_tokens(substr(text, 1L, k)) <= budget
  # The largest k in [lo, hi] that fits, given that lo does (or is 0).
  widest <- function(lo, hi, at = identity) {
    while (lo < hi) {
      mid <- as.integer((lo + hi + 1L) %/% 2L)
      if (fits(at(mid))) lo <- mid else hi <- mid - 1L
    }
    lo
  }

  # Where each whitespace-delimited unit ends, in the text as written. The old
  # code re-joined the units with " ", so any truncation turned a table, an
  # outline or merge_giveup's "---"-separated findings into a single line.
  m <- gregexpr("[^[:space:]]+", text)[[1]]
  ends <- if (m[1] > 0L) as.integer(m + attr(m, "match.length") - 1L) else integer(0)
  if (!length(ends)) return("")
  whole <- widest(0L, length(ends), function(k) ends[k])
  cut <- if (whole > 0L) ends[whole] else 0L
  # Into the next unit when it is too long to be a word. Stopping before it
  # kept only what came first: a "[chunk 7 p.3]" header and none of the long
  # CJK chunk after it, 12 tokens of a 3000-token budget. A short word is not
  # cut, so prose still ends on a whole word.
  if (whole < length(ends)) {
    from <- as.integer(m[whole + 1L])
    unit <- substr(text, from, ends[whole + 1L])
    if (whole == 0L || gr_count_tokens(unit) > 16L) {
      inner <- widest(from - 1L, ends[whole + 1L] - 1L)
      if (inner >= from) cut <- inner
    }
  }
  if (cut <= 0L) return("")
  out <- paste0(substr(text, 1L, cut), mk)
  # Counts are not strictly additive; never hand back more than was asked for.
  if (gr_count_tokens(out) > n) out <- substr(text, 1L, cut)
  out
}

#' Write a cut to the trace: where it was made and how many tokens it dropped.
#'
#' `before` is the text as it was and `after` what was kept. Nothing is written
#' when the two are identical. `marker` is the text the cut appended, if any; it
#' is left out of the kept count, so `tokens_dropped` is the source text lost
#' and not the source text lost less the marker. `where` names the cut site in
#' the dotted style of call labels ("refine.draft"), and `...` adds detail such
#' as the chunk or the round. Returns the tokens dropped, invisibly; 0 for no
#' cut.
#'
#' A cut used to be visible only as a partial flag or a count of cuts, so a
#' trace could not say which text had been shortened or by how much, and a
#' decline caused by a cut could not be told from one caused by the model.
#' @noRd
trace_truncation <- function(trace, where, before, after, limit = NA_integer_,
                             marker = "", ...) {
  before <- as_chr1(before, "")
  after <- as_chr1(after, "")
  if (identical(before, after)) return(invisible(0L))
  kept <- after
  if (nzchar(marker) && endsWith(kept, marker)) {
    kept <- substr(kept, 1L, nchar(kept) - nchar(marker))
  }
  had <- as.integer(gr_count_tokens(before))
  left <- as.integer(gr_count_tokens(kept))
  dropped <- max(had - left, 0L)
  trace_note(trace, "truncate", c(list(where = as_chr1(where),
                                       limit = as_int1(limit, NA_integer_),
                                       tokens_before = had, tokens_kept = left,
                                       tokens_dropped = dropped), list(...)))
  invisible(dropped)
}

#' gr_truncate_tokens(), with the cut written to the trace.
#'
#' The text returned is exactly what gr_truncate_tokens() returns, so a caller
#' that switches to this sends the same request it sent before. Returns a list:
#' `text`, and `dropped`, the tokens the cut removed (0 when the text fit).
#' @noRd
truncate_logged <- function(text, n, where, trace = NULL, marker = " ...[truncated]", ...) {
  out <- gr_truncate_tokens(text, n, marker)
  dropped <- trace_truncation(trace, where, text, out, limit = n, marker = marker, ...)
  list(text = out, dropped = dropped)
}
