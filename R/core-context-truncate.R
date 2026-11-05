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
