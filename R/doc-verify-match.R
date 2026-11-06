# doc-verify-match.R: the edit-distance quote matcher, run in shadow mode.
#
# span_match() (doc-verify-quote.R) decides `verified` and scores a miss by
# the longest run of consecutive words. That score depends on where an edit
# falls: one changed word in the middle of a span halves it, the same change
# at an end barely moves it, and further edits outside the longest run leave
# it as it was. It cannot be compared across quotes or given a threshold.
#
# match_span() below scores a quote by how many character edits separate it
# from the closest window of the source, after both are normalised, and keeps
# numbers and negations out of what "close" may forgive. For now it decides
# nothing: verify_spans() records its status and score next to the old
# `verified` and `match`, so the two can be compared on real runs before the
# default changes. The false-rejection rates of both on a labelled set are in
# tests/testthat/test-verify-match.R and dev/quote-matcher-rates.R.

#' The statuses a quotation check reports.
#'
#' One vocabulary for every quote check. `verbatim` is found exactly once
#' normalised; `near_verbatim` is close enough by edit distance with the
#' numbers and negations identical, and is reported apart from `verbatim`,
#' never folded into it; `unverified` is neither; `not_checked` is a quote or
#' source with nothing to compare. `entailed`, `not_entailed` and
#' `contradicted` belong to a support check this matcher does not make.
#' @noRd
.gr_quote_statuses <- c("verbatim", "near_verbatim", "entailed", "not_entailed",
                        "contradicted", "unverified", "not_checked")

#' Compatibility characters folded before matching, from and to.
#'
#' The NFKC mappings a quotation actually meets, as a table, since base R has
#' no Unicode normalisation: the Latin ligatures a PDF text layer keeps (the
#' "fi" of "efficacy" as one character), the long s, the ellipsis, and the
#' full-width forms of the ASCII range. Superscript and subscript digits are
#' left alone on purpose, although NFKC folds them: "10" followed by a
#' superscript 6 would become "106", a different number.
#' @noRd
.gr_compat_fold <- stats::setNames(
  c("ff", "fi", "fl", "ffi", "ffl", "st", "st", "IJ", "ij", "s", "...", ".", ".."),
  c("\ufb00", "\ufb01", "\ufb02", "\ufb03", "\ufb04", "\ufb05", "\ufb06",
    "\u0132", "\u0133", "\u017f", "\u2026", "\u2024", "\u2025")
)

#' Words after a number that are part of what it says: "45.2 million" is not
#' "45.2 billion", and "3 days" is not "3 weeks". Lower case, as normalised.
#' @noRd
.gr_quote_units <- c(
  "%", "percent", "per cent", "percentage points", "pp", "million", "billion", "thousand",
  "trillion", "bn", "m", "k", "dollars", "usd", "eur", "euros", "gbp", "pounds",
  "mg", "g", "kg", "mcg", "ml", "l", "mm", "cm", "km", "mmhg", "mmol", "iu",
  "s", "sec", "seconds", "min", "minutes", "h", "hours", "days", "weeks", "months", "years",
  "units", "patients", "participants", "people", "times", "fold"
)

#' Text as the edit-distance matcher compares it.
#'
#' In order: JSON escapes a model left in its reply undone (`\\"`, `\\n`,
#' `\\uXXXX`); the compatibility characters of .gr_compat_fold expanded;
#' combining accents composed (compose_marks()); quote marks, dashes, spaces
#' and case folded as normalise_for_match() folds them; a word broken across
#' a line with a hyphen joined, and then every hyphen between two letters
#' taken out, so "investi-\\ngator", "investigator" and "investi-gator" are
#' one word on both sides; soft hyphens and zero-width characters dropped;
#' runs of white space collapsed to one space. Both the quotation and its
#' source go through the same steps, so nothing here can make a quotation
#' match text that differs from it in letters or digits.
#' @noRd
normalise_quote_text <- function(x) {
  x <- to_utf8(as.character(x))
  x[is.na(x)] <- ""
  esc <- grepl("\\", x, fixed = TRUE)
  if (any(esc)) x[esc] <- json_unescape(x[esc])
  x <- gsub("[\u00ad\u200b\u200c\u200d\u2060\ufeff]", "", x, perl = TRUE)
  wide <- grepl("[^\\x01-\\x7f]", x, perl = TRUE)
  if (any(wide)) {
    for (ch in names(.gr_compat_fold)) {
      x[wide] <- gsub(ch, .gr_compat_fold[[ch]], x[wide], fixed = TRUE)
    }
    x[wide] <- fold_compat_width(x[wide])
  }
  x <- fold_for_match(compose_marks(x))
  # A hyphen at a line end between two letters is the layout's, not the word's.
  x <- gsub("(?<=[\\p{L}\\p{M}])-[ \t]*\r?\n[ \t]*(?=\\p{L})", "", x, perl = TRUE)
  x <- join_hyphens(x)
  trimws(gsub("[[:space:]]+", " ", x, perl = TRUE))
}

#' Undo the escaping a JSON string adds, for a quotation copied out of a
#' reply that was escaped twice. Only the escapes JSON defines.
#' @noRd
json_unescape <- function(x) {
  vapply(x, function(s) {
    if (grepl("\\u", s, fixed = TRUE)) {
      m <- gregexpr("\\\\u[0-9A-Fa-f]{4}", s, perl = TRUE)
      regmatches(s, m) <- list(vapply(regmatches(s, m)[[1]], function(h) {
        intToUtf8(strtoi(substr(h, 3L, 6L), 16L))
      }, character(1)))
    }
    s <- gsub("\\\\", "\001", s, fixed = TRUE)
    s <- gsub("\\n", "\n", s, fixed = TRUE)
    s <- gsub("\\r", "\n", s, fixed = TRUE)
    s <- gsub("\\t", " ", s, fixed = TRUE)
    s <- gsub("\\\"", "\"", s, fixed = TRUE)
    s <- gsub("\\/", "/", s, fixed = TRUE)
    gsub("\001", "\\", s, fixed = TRUE)
  }, character(1), USE.NAMES = FALSE)
}

#' Every full-width form of the ASCII range as its ASCII character. Wider than
#' fold_width(), which keeps the full-width sentence marks for the sentence
#' tests of span_match(); this matcher has no sentence tests.
#' @noRd
fold_compat_width <- function(x) {
  hit <- which(grepl("[\uff01-\uff5e]", x, perl = TRUE))
  for (i in hit) {
    cp <- utf8ToInt(x[i])
    if (anyNA(cp)) next
    w <- cp >= 0xFF01L & cp <= 0xFF5EL
    cp[w] <- cp[w] - 0xFEE0L
    x[i] <- intToUtf8(cp)
  }
  x
}

#' The words of normalised text: a run of letters, marks and digits, with a
#' full stop, comma or apostrophe allowed inside it ("45.2", "12,400",
#' "don't") and a per cent sign after it; in a script written without spaces,
#' each character.
#' @noRd
quote_tokens <- function(s) {
  pat <- sprintf("[%s]|[\\p{L}\\p{M}\\p{N}]+(?:[.,'][\\p{L}\\p{M}\\p{N}]+)*%%?", .gr_unspaced)
  regmatches(s, gregexpr(pat, s, perl = TRUE))[[1]]
}

#' The numbers of normalised text, each with its sign, a comparison sign
#' before it ("p < 0.04" is not "p = 0.04") and the unit after it, the
#' values of numbers written in words (word_numbers(): "twelve months" is not
#' "eleven months"), and its negations, in order. Two texts whose critical
#' tokens differ say different things however few characters apart they are.
#' @noRd
critical_tokens <- function(s) {
  units <- paste(gsub("([.%])", "\\\\\\1", .gr_quote_units[order(-nchar(.gr_quote_units))]),
                 collapse = "|")
  num_pat <- paste0("(?<![\\p{L}\\p{N}.,])(?:(?:[<>]=?|=|[\u2264\u2265])\\s?)?",
                    "[-+]?\\p{N}+(?:[.,]\\p{N}+)*",
                    "(?:\\s?(?:", units, ")(?![\\p{L}\\p{N}]))?")
  nums <- regmatches(s, gregexpr(num_pat, s, perl = TRUE))[[1]]
  nums <- gsub("\\s+", "", nums)
  spelled <- word_numbers(s)
  if (length(spelled)) nums <- c(nums, paste0("w", format(spelled, digits = 15, trim = TRUE)))
  words <- regmatches(s, gregexpr("[\\p{L}\\p{M}']+", s, perl = TRUE))[[1]]
  words <- gsub("^'+|'+$", "", words)
  neg <- words[words %in% .gr_negations | grepl("n't$|^n'", words)]
  marks <- if (grepl("[^\\x01-\\x7f]", s, perl = TRUE)) {
    regmatches(s, gregexpr(.gr_negation_marks, s, perl = TRUE))[[1]]
  } else character(0)
  list(numbers = nums, negations = c(neg, marks))
}

#' The fewest character edits that turn `q` into some window of `s`, and the
#' window. Both are integer code points.
#'
#' Approximate substring matching (Sellers 1980): the edit table with a free
#' start along the source, filled a row at a time. The insertion term of a
#' row depends on the cell before it, which is a running minimum, so each row
#' is one vector operation. The end of the best window is where the last row
#' is lowest (the first such place); its start comes from the same table run
#' backwards from that end, taking the shortest window with the same count.
#' @noRd
window_edits <- function(q, s) {
  m <- length(q)
  n <- length(s)
  if (!m || !n) return(list(edits = NA_integer_, start = NA_integer_, end = NA_integer_))
  last_row <- function(q, s, free) {
    n <- length(s)
    idx <- 0:n
    D <- if (free) integer(n + 1L) else idx
    for (i in seq_along(q)) {
      diag <- D[-(n + 1L)] + (s != q[i])
      up <- D[-1L] + 1L
      E <- c(D[1L] + 1L, pmin(diag, up))
      D <- cummin(E - idx) + idx
    }
    D
  }
  D <- last_row(q, s, TRUE)
  end <- which.min(D[-1L])
  edits <- D[end + 1L]
  R <- last_row(rev(q), rev(s[seq_len(end)]), FALSE)
  back <- which(R[-1L] == edits)[1L]
  if (is.na(back)) back <- end
  list(edits = as.integer(edits), start = as.integer(end - back + 1L), end = as.integer(end))
}

#' The share of `a`'s tokens that appear, in order, in `b`: the longest common
#' subsequence over `a`'s length. One row at a time, as window_edits() fills
#' its table; the running maximum carries the cell before.
#' @noRd
lcs_coverage <- function(a, b) {
  if (!length(a)) return(NA_real_)
  if (!length(b)) return(0)
  L <- integer(length(b) + 1L)
  for (w in a) {
    eq <- as.integer(b == w)
    L <- c(0L, cummax(pmax(L[-1L], L[-length(L)] + eq)))
  }
  L[length(L)] / length(a)
}

#' Grow a window of `cp` to whole words: a window that starts or ends inside
#' a word or a number takes all of it, and a sign directly before a number
#' comes with it. "5%" matched inside "25%" is then the window "25%", and its
#' number differs from the quotation's.
#' @noRd
widen_window <- function(cp, start, end) {
  alnum <- function(i) {
    i >= 1L && i <= length(cp) &&
      grepl("[\\p{L}\\p{M}\\p{N}]", intToUtf8(cp[i]), perl = TRUE)
  }
  while (start > 1L && alnum(start - 1L) && alnum(start)) start <- start - 1L
  while (end < length(cp) && alnum(end + 1L) && alnum(end)) end <- end + 1L
  if (start > 1L && cp[start - 1L] %in% c(45L, 43L) &&
      grepl("\\p{N}", intToUtf8(cp[start]), perl = TRUE) &&
      !alnum(start - 2L)) {
    start <- start - 1L
  }
  c(start, end)
}

#' Match one normalised passage against a normalised source.
#' @noRd
match_passage <- function(qn, sn, scp = utf8ToInt(sn), max_cells = 5e7) {
  qtok <- quote_tokens(qn)
  na <- list(status = "not_checked", sim = NA_real_, coverage = NA_real_,
             n_edits = NA_integer_, critical_ok = NA, start = NA_integer_, end = NA_integer_,
             too_long = FALSE)
  if (!length(qtok) || !nzchar(sn)) return(na)
  qcrit <- critical_tokens(qn)
  qcp <- utf8ToInt(qn)
  judge <- function(edits, start, end) {
    wide <- widen_window(scp, start, end)
    win <- intToUtf8(scp[wide[1L]:wide[2L]])
    ok <- identical(critical_tokens(win), qcrit)
    sim <- 1 - edits / max(length(qcp), end - start + 1L)
    list(sim = sim, coverage = lcs_coverage(qtok, quote_tokens(win)),
         n_edits = edits, critical_ok = ok, start = wide[1L], end = wide[2L], too_long = FALSE)
  }
  # Found as written: the first place where its numbers and negations are
  # also whole is a verbatim quotation, with no table to fill.
  at <- gregexpr(qn, sn, fixed = TRUE)[[1]]
  if (at[1L] > 0L) {
    for (a in utils::head(at, 50L)) {
      r <- judge(0L, a, a + length(qcp) - 1L)
      if (r$critical_ok) return(c(list(status = "verbatim"), r))
    }
  }
  # The edit table has a cell per character pair; past max_cells it is not
  # filled, and the passage is reported as skipped for size, not as empty.
  if (as.numeric(length(qcp)) * length(scp) > max_cells) {
    na$too_long <- TRUE
    return(na)
  }
  w <- window_edits(qcp, scp)
  r <- judge(w$edits, w$start, w$end)
  c(list(status = passage_status(r, qn, qtok)), r)
}

#' The status of a passage from its score.
#'
#' `verbatim` needs no edit at all. A quotation under five words (a number, a
#' name) is close to too many things to be judged by distance, so it is
#' verbatim or unverified. Otherwise `near_verbatim` needs a similarity of
#' 0.90 for 40 characters or more and 0.95 below that, with every number,
#' unit and negation identical. The thresholds are provisional, from
#' practitioner sources, until they are tuned on a local OCR sample.
#' @noRd
passage_status <- function(r, qn, qtok) {
  if (!isTRUE(r$critical_ok)) return("unverified")
  if (identical(r$n_edits, 0L)) return("verbatim")
  if (length(qtok) < 5L) return("unverified")
  floor <- if (nchar(qn) >= 40L) 0.90 else 0.95
  if (r$sim >= floor) "near_verbatim" else "unverified"
}

#' Does a quotation appear in a source, by edit distance?
#'
#' The quotation is split where it marks an elision ("...", "[...]") or a
#' blank line, each passage is normalised (normalise_quote_text()) and
#' matched against the normalised source on its own (match_passage()), and
#' the quotation takes the worst status of its passages, the lowest
#' similarity and coverage, the sum of their edits, and is critical_ok only
#' when every passage is. Unlike span_match() it does not check that elided
#' passages come in order or what an elision leaves out; it is a score, and
#' in this release it decides nothing.
#'
#' A passage is not scored when its length times the source's exceeds
#' `max_cells` (5e7 character pairs, a few seconds of work); the quotation is
#' then `not_checked` with `method = "too_long"`, which says it was skipped
#' for size rather than having nothing to compare.
#'
#' @return `list(status, sim, coverage, n_edits, critical_ok, start, end,
#'   method)`, where `method` is `"edit_window"`, or `"too_long"` as above. `sim` is 1 minus the edits over the longer of the passage and
#'   its window; `coverage` the share of the passage's words found in order in
#'   the window; `start` and `end` the window, in characters of the
#'   normalised source, for a quotation of one passage.
#' @noRd
match_span <- function(quote, source, max_cells = 5e7) {
  out <- function(status, sim = NA_real_, coverage = NA_real_, n_edits = NA_integer_,
                  critical_ok = NA, start = NA_integer_, end = NA_integer_,
                  method = "edit_window") {
    list(status = status, sim = sim, coverage = coverage, n_edits = n_edits,
         critical_ok = critical_ok, start = start, end = end, method = method)
  }
  q <- as_chr1(quote, "")
  s <- as_chr1(source, "")
  if (!nzchar(trimws(q)) || !nzchar(trimws(s))) return(out("not_checked"))
  sn <- normalise_quote_text(s)
  # Split before normalising, which would collapse the blank lines away.
  pieces <- strsplit(to_utf8(q), "\\[\\s*(?:\\.\\s*){3}\\]|\\[\\s*\u2026\\s*\\]|\\.{3}|\u2026|\r?\n[ \t]*\r?\n",
                     perl = TRUE)[[1]]
  pieces <- trim_quote_edges(normalise_quote_text(pieces))
  pieces <- pieces[grepl("[\\p{L}\\p{N}]", pieces, perl = TRUE)]
  if (!length(pieces)) return(out("not_checked"))
  scp <- utf8ToInt(sn)
  got <- lapply(pieces, match_passage, sn = sn, scp = scp, max_cells = max_cells)
  st <- vapply(got, `[[`, "", "status")
  # Worst last; the support statuses of .gr_quote_statuses never come from here.
  order_worst <- intersect(.gr_quote_statuses,
                           c("verbatim", "near_verbatim", "unverified", "not_checked"))
  rank <- match(st, order_worst)
  worst <- st[which.max(rank)]
  num <- function(f) vapply(got, function(g) as.numeric(g[[f]]), numeric(1))
  one <- length(got) == 1L
  out(worst, sim = round(min(num("sim")), 4), coverage = round(min(num("coverage")), 4),
      n_edits = as.integer(sum(num("n_edits"))),
      critical_ok = all(vapply(got, function(g) isTRUE(g$critical_ok), logical(1))),
      start = if (one) got[[1L]]$start else NA_integer_,
      end = if (one) got[[1L]]$end else NA_integer_,
      method = if (any(vapply(got, function(g) isTRUE(g$too_long), logical(1))))
        "too_long" else "edit_window")
}
