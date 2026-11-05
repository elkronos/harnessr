# doc-segment-text.R: text split into paragraphs and sentences, and lower case.

#' Lower case that does not depend on the session's locale.
#'
#' `tolower()` lowers what the C library's locale calls a letter. In a C locale
#' on Linux (cron, containers, `R CMD check`) that is A-Z alone, so a Russian
#' sentence kept its capital letter and a quotation of it in lower case did not
#' match, on that machine only. The common cased scripts are mapped here code point by code
#' point, which `chartr()` does the same way in every locale; `tolower()` then
#' does what else the locale can.
#'
#' Both read every character of the text, and where the locale is not UTF-8
#' each took most of a second over 80,000 Chinese characters, none of which
#' has a case. Both map one character to one character, so a long UTF-8
#' string is lowered one distinct code point at a time instead (lower_long()):
#' the same result, at the cost of the few letters that have a case.
#'
#' The text is labelled UTF-8 first where its bytes are UTF-8. In a C locale
#' chartr() reads an unlabelled string as native bytes and rewrote the bytes
#' of a Greek or accented letter into something that is not UTF-8 at all, so
#' the lowered text matched nothing and broke whatever printed it. The names
#' and other attributes stay as they were.
#' @noRd
lower_text <- function(x) {
  if (!is.character(x)) return(lower_chars(x))
  if (length(x)) x[] <- mark_utf8(x)
  long <- which(!is.na(x) & nchar(x, type = "bytes") > 512L)
  if (!length(long)) return(lower_chars(x))
  out <- lower_chars(replace(x, long, ""))
  for (i in long) out[i] <- lower_long(x[i])
  out
}

#' lower_text() the direct way, character by character.
#' @noRd
lower_chars <- function(x) {
  # Bytes that are not UTF-8 (a CP1252 string in a UTF-8 session) are left as
  # they came. chartr() and tolower() read them as the locale's multibyte text
  # and stop with "invalid input multibyte string" under a C locale on Linux;
  # both sides of a comparison go through here, so leaving them is consistent.
  bad <- !is.na(x) & !validUTF8(x)
  if (!any(bad)) return(tolower(chartr(.gr_case_map$upper, .gr_case_map$lower, x)))
  x[!bad] <- tolower(chartr(.gr_case_map$upper, .gr_case_map$lower, x[!bad]))
  x
}

#' lower_text() of one long string: only the distinct code points that have a
#' case (a capital, a title-case letter, a Roman numeral or a circled capital)
#' are lowered, together, and put back where they stand. A string that is not
#' UTF-8 goes the direct way.
#' @noRd
lower_long <- function(s) {
  utf8 <- Encoding(s) == "UTF-8" || (isTRUE(l10n_info()[["UTF-8"]]) && validUTF8(s))
  cp <- if (utf8) utf8ToInt(s) else NA_integer_
  if (anyNA(cp)) return(lower_chars(s))
  up <- cp >= 65L & (cp <= 90L | cp > 127L)
  if (!any(up)) return(s)
  u <- unique(cp[up])
  cased <- grepl("[\\p{Lu}\\p{Lt}\\p{Nl}\u24b6-\u24cf]", intToUtf8(u, multiple = TRUE), perl = TRUE)
  if (!any(cased)) return(s)
  u <- u[cased]
  low <- utf8ToInt(lower_chars(intToUtf8(u)))
  if (length(low) != length(u) || anyNA(low)) return(lower_chars(s))
  hit <- match(cp, u)
  at <- !is.na(hit)
  cp[at] <- low[hit[at]]
  intToUtf8(cp)
}

#' Upper- and lower-case letters for lower_text(), as two strings of the same
#' length: Latin-1, Latin Extended-A and Additional (Vietnamese), Greek,
#' Cyrillic and Armenian. Pairs whose lower case is not one code point (the
#' Turkish dotted capital I) are left to `tolower()`.
#' @noRd
.gr_case_map <- local({
  plus <- function(from, by) list(up = from, low = from + by)
  pairs <- list(
    plus(c(0xC0:0xD6, 0xD8:0xDE), 32L),                                   # Latin-1
    plus(c(seq(0x100L, 0x12EL, 2L), seq(0x132L, 0x136L, 2L), seq(0x139L, 0x147L, 2L),
           seq(0x14AL, 0x176L, 2L), 0x179L, 0x17BL, 0x17DL), 1L),          # Latin Extended-A
    list(up = 0x178L, low = 0xFFL),                                       # Y with diaeresis
    plus(c(seq(0x1E00L, 0x1E94L, 2L), seq(0x1EA0L, 0x1EFEL, 2L)), 1L),    # Latin Extended Additional
    plus(c(0x391:0x3A1, 0x3A3:0x3AB), 32L),                               # Greek
    list(up = c(0x386L, 0x388:0x38A, 0x38CL, 0x38EL, 0x38FL),
         low = c(0x3ACL, 0x3AD:0x3AF, 0x3CCL, 0x3CDL, 0x3CEL)),           # Greek with tonos
    plus(0x400:0x40F, 80L), plus(0x410:0x42F, 32L),                       # Cyrillic
    plus(c(seq(0x460L, 0x480L, 2L), seq(0x48AL, 0x4BEL, 2L), seq(0x4D0L, 0x52EL, 2L)), 1L),
    plus(seq(0x4C1L, 0x4CDL, 2L), 1L),
    plus(0x531:0x556, 48L)                                                # Armenian
  )
  list(upper = intToUtf8(unlist(lapply(pairs, `[[`, "up"))),
       lower = intToUtf8(unlist(lapply(pairs, `[[`, "low"))))
})

#' Split text into paragraphs on blank lines. Always returns a character vector
#' (possibly length 0) -- never NULL.
#'
#' A line of no-break or ideographic spaces is a blank line too: HTML and Word
#' exports separate paragraphs with one, and Chinese and Japanese text with a
#' line of ideographic spaces, and both paragraphs came out as one block.
#' @noRd
paragraphs_of <- function(text) {
  text <- mark_utf8(normalise_newlines(as_chr1(text)))
  if (!has_visible(text)) return(character(0))
  blank <- sprintf("\n[ \t%s]*\n[ \t\n%s]*", .gr_uspace, .gr_uspace)
  p <- split_perl(text, blank)
  p <- trimws(p, which = "right")
  # Re-label. In a non-UTF-8 locale `paste`, `strsplit` and `trimws` all return
  # unmarked strings even when the input was marked UTF-8, and every downstream
  # UTF-8 pattern then silently stops matching.
  p <- mark_utf8(p)
  p[has_visible(p)]
}

#' Where one sentence ends and the next begins, for strsplit().
#'
#' After a full stop, question or exclamation mark (and the Arabic, Urdu and
#' Devanagari ones) and a space, before a capital, a letter of a script with
#' no case (Arabic, Hebrew, Devanagari, Chinese, Korean ...) or a digit, which
#' an opening quote or bracket may precede; and after the ideographic full
#' stop and the full-width marks, where no space follows, unless a closing
#' quote or bracket does, and then after that. The first rule wanted an ASCII
#' capital or digit, so Russian, Greek, Arabic and Chinese paragraphs came
#' back as one sentence, and a French or German sentence starting with a
#' capital with an accent was glued to the one before; every segmenter,
#' overlap and cap that cuts at sentences then cut inside one. The Greek
#' question mark is the semicolon, and is not a sentence end here.
#' @noRd
.gr_sentence_split <- paste0(
  "(?<=[.!?\u061f\u06d4\u0964\u0965])[ \t]+",
  "(?=[\"'(\\[\u00ab\u201c\u201e\u2018\u00bf\u00a1\u300c\u300e]?[\\p{Lu}\\p{Lt}\\p{Lo}\\p{N}])",
  "|(?<=[\u3002\uff01\uff1f])(?![\u300d\u300f\uff09\u201d\u2019\"')\\]])[ \t]*",
  "|(?<=[\u3002\uff01\uff1f][\u300d\u300f\uff09\u201d\u2019])[ \t]*",
  "|\n{2,}")

#' Split text into sentences using a conservative abbreviation-aware regex.
#' @noRd
sentences_of <- function(text) {
  text <- mark_utf8(as_chr1(text))
  if (!has_visible(text)) return(character(0))
  # Protect common abbreviations and decimals from being treated as boundaries.
  guarded <- text
  abbrevs <- c("Mr", "Mrs", "Ms", "Dr", "Prof", "Sr", "Jr", "St", "vs", "etc",
               "e.g", "i.e", "cf", "al", "Fig", "Eq", "No", "Inc", "Ltd", "Co")
  for (a in abbrevs) {
    guarded <- gsub(paste0("\\b", gsub("\\.", "\\\\.", a), "\\."), paste0(a, "\u0001"),
                    guarded, perl = TRUE)
  }
  guarded <- gsub("(\\d)\\.(\\d)", "\\1\u0001\\2", guarded, perl = TRUE)
  parts <- split_perl(mark_utf8(guarded), .gr_sentence_split)
  parts <- gsub("\u0001", ".", parts, fixed = TRUE)
  parts <- trimws(parts)
  parts[nzchar(parts)]
}
