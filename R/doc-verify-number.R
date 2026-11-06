# doc-verify-number.R: numbers read from text, as digits or words, to check a
# value against its source.

#' The document text each chunk was cut from, with nothing a model wrote.
#'
#' The shared chunk contract: a `source_text` column, where present and not NA,
#' is the text the chunk was derived from, without a contextual header or
#' propositions a segmenter had a model write into `text`. NA, or no column,
#' means `text` is itself source. A quote is evidence only if it is in the
#' document, so it is checked against this and never against model-written text.
#' `[[`, not `$`: `$` on a data frame partial-matches.
#' @noRd
extract_verbatim_source <- function(d) {
  src <- as.character(d[["text"]])
  own <- d[["source_text"]]
  if (!is.null(own)) {
    own <- as.character(own)
    use <- !is.na(own)
    src[use] <- own[use]
  }
  src
}

#' The numbers a quotation states, as absolute values.
#'
#' Wider than numeric_token(), because this looks for a value among many rather
#' than reading one: every number in the span counts, however the paper wrote
#' it. Reading digit strings alone rejected honest values the old span check
#' had verified, and require_quote then deleted them: "Twenty-four patients",
#' "three arms", "No participants died", "1 204" in the Lancet's thin-space
#' style, "0,45", "0.84" with the Lancet's middle dot, "3.2 x 10-5" and "1.2
#' million" each state the value
#' they were quoted for. So every reading below is added to the others:
#'
#' * digits with comma thousands, a decimal point and an exponent; ".05" is
#'   0.05, as APA style writes p-values;
#' * thousands grouped by a space (thin and no-break spaces included), an
#'   apostrophe or, with a decimal comma, a dot: "1 204", "1'204", "1.204,5";
#' * a decimal comma ("0,45") and the Lancet's middle-dot decimal point
#'   (U+00B7);
#' * scientific notation: "3.2 x 10^-5", with a multiplication sign (U+00D7)
#'   and a superscript exponent (U+207B U+2075), and "3.2 x 10-5" as a PDF
#'   text layer flattens the superscript;
#' * a scale word or suffix ("1.2 million", "$3bn", "$1.2 bn", 3 followed by
#'   U+4E07), in the other languages read below too ("1,2 millions", "1,2
#'   Millionen", "1,2 millones", "1,2 Mio."), and a percentage as a proportion
#'   ("54%", "54 per cent" and "Fifty-four percent" are also 0.54);
#' * "one in five" and "1 in 5" (0.2), "two and a half" (2.5), "a quarter",
#'   "two thirds" and the vulgar fraction signs (U+00BD and the like);
#' * English number words (word_numbers()) or, in a quotation written in
#'   Spanish, Portuguese, French, Italian, German or Dutch (quote_language()),
#'   that language's number words instead (foreign_numbers()); Chinese
#'   numerals (han_numbers()) and a Roman numeral after a word such as "phase"
#'   (roman_numbers()).
#'
#' Signs are dropped because a hyphen before a number is as often a range
#' ("20-30") or a name ("COVID-19") as a minus.
#'
#' `lang` is quote_language() of the whole quotation, when `s` is one piece
#' of it: an elided piece can be too short to tell its language by.
#' @noRd
quote_numbers <- function(s, lang = NULL) {
  s <- fold_numerals(as_chr1(s, ""))
  if (!nzchar(s)) return(numeric(0))
  if (is.null(lang)) lang <- quote_language(s, folded = TRUE)
  # A middle dot (U+00B7) is a decimal point in Lancet style, between two
  # digits, and a multiplication sign before a power of ten.
  times <- gsub("\u00b7(?=\\s*10)", " x ", s, perl = TRUE)
  forms <- c(gsub("(?<=[0-9])\u00b7(?=[0-9])", ".", s, perl = TRUE),
             if (!identical(times, s)) times)
  # English words are not read in another language: its "no" and "once" are
  # not 0 and 1, nor Dutch "ten" 10.
  foreign <- all(lang %in% names(.gr_numeral_languages))
  words <- if (foreign) function(f) foreign_numbers(f, lang) else word_numbers
  out <- unlist(lapply(forms, function(f) c(digit_numbers(f), words(f), han_numbers(f),
                                             roman_numbers(f))),
                use.names = FALSE)
  unique(abs(out[is.finite(out)]))
}

#' Digits of other scripts as ASCII, superscripts as a caret, and the spaces
#' and minus signs normalise_for_match() folds, folded here too, so the
#' readers below see one spelling. Lower case, as a normalised quote is, and
#' Latin letters without their accents ("veintidos", "funf", "dreissig"),
#' as the number words below are spelled, whether the accent is one code
#' point or a combining mark.
#' @noRd
fold_numerals <- function(s) {
  s <- to_utf8(s)
  # Everything below but the case is a character outside ASCII.
  if (!grepl("[^\\x01-\\x7f]", s, perl = TRUE)) return(tolower(s))
  # Digits of other scripts and their separators, as numeric_token() reads
  # them (.gr_digit_fold).
  s <- chartr(.gr_digit_fold$from, .gr_digit_fold$to, s)
  sup <- "\u2070\u00b9\u00b2\u00b3\u2074\u2075\u2076\u2077\u2078\u2079\u207a\u207b"
  # A minus sign on the line before a superscript is the exponent's own sign:
  # "10" U+2212 U+00B9 U+2070 is 10^-10.
  m <- gregexpr(paste0("[-\u2212]?[", sup, "]+"), s, perl = TRUE)
  regmatches(s, m) <- lapply(regmatches(s, m), function(x) {
    if (!length(x)) return(x)
    sign <- ifelse(grepl("^[-\u2212]", x, perl = TRUE), "-", "")
    paste0("^", sign, chartr(sup, "0123456789+-", sub("^[-\u2212]", "", x, perl = TRUE)))
  })
  s <- gsub("[\u00a0\u2007\u2009\u202f]", " ", s, perl = TRUE)
  s <- lower_text(gsub("\u2212", "-", s, fixed = TRUE))
  s <- gsub("(?<=\\p{Latin})\\p{M}+", "", s, perl = TRUE)
  s <- chartr(.gr_accent_fold$from, .gr_accent_fold$to, s)
  gsub("\u00df", "ss", gsub("\u00e6", "ae", gsub("\u0153", "oe", s, fixed = TRUE),
                            fixed = TRUE), fixed = TRUE)
}

#' Lower-case Latin letters with a diacritic, and the letter each is without
#' it, for fold_numerals(): Latin-1 and Latin Extended-A.
#' @noRd
.gr_accent_fold <- list(
  from = intToUtf8(c(0xE0:0xE5, 0xE7:0xEF, 0xF0:0xF6, 0xF8:0xFD, 0xFF,
                     0x101, 0x103, 0x105, 0x107, 0x109, 0x10B, 0x10D, 0x10F, 0x111,
                     0x113, 0x115, 0x117, 0x119, 0x11B, 0x11D, 0x11F, 0x121, 0x123,
                     0x125, 0x127, 0x129, 0x12B, 0x12D, 0x12F, 0x131, 0x135, 0x137,
                     0x13A, 0x13C, 0x13E, 0x140, 0x142, 0x144, 0x146, 0x148,
                     0x14D, 0x14F, 0x151, 0x155, 0x157, 0x159, 0x15B, 0x15D, 0x15F,
                     0x161, 0x163, 0x165, 0x167, 0x169, 0x16B, 0x16D, 0x16F, 0x171,
                     0x173, 0x175, 0x177, 0x17A, 0x17C, 0x17E)),
  to = paste0("aaaaaa", "ceeeeiiii", "dnooooo", "ouuuuy", "y",
              "aaaccccdd", "eeeeegggg", "hhiiiiijk",
              "llllln", "nn", "ooorrrsss",
              "stttuuuuu", "uwyzzz"))

#' Every number written in digits, in each of the forms quote_numbers() lists.
#' @noRd
digit_numbers <- function(s) {
  num <- function(x) suppressWarnings(as.numeric(x))
  grab <- function(pat) regmatches(s, gregexpr(pat, s, perl = TRUE))[[1]]
  groups <- function(pat) lapply(grab(pat), function(x)
    regmatches(x, regexec(pat, x, perl = TRUE))[[1]][-1L])
  # A figure before a scale word may use either comma: "1,200 million" is
  # 1.2e9 in English and "1,2 millions" 1.2e6 in French.
  figure <- function(x) c(if (grepl("^[0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]+)?$", x, perl = TRUE))
                            num(gsub(",", "", x, fixed = TRUE)),
                          num(chartr(",", ".", x)))
  fig <- "([0-9]+(?:[.,][0-9]+)?)"

  # As written: digits, comma thousands, a decimal point, an exponent.
  out <- num(gsub(",", "", grab("(?:[0-9][0-9,]*(?:\\.[0-9]+)?|\\.[0-9]+)(?:e[-+]?[0-9]+)?"),
                  fixed = TRUE))
  # Thousands grouped by spaces or apostrophes: every run of two to five
  # groups, since a table row "120 118" is two numbers as well as a grouping.
  # Five groups reach 999 trillion; a longer run is a row of a table, and
  # reading every stretch of one made a quoted table of counts take minutes.
  for (g in grab("(?<![0-9.,])[1-9][0-9]{0,2}(?:[ '][0-9]{3})+(?:[.,][0-9]+)?(?![0-9])")) {
    dec <- regmatches(g, regexpr("[.,][0-9]+$", g, perl = TRUE))
    parts <- strsplit(if (length(dec)) substr(g, 1L, nchar(g) - nchar(dec)) else g,
                      "[ ']", perl = TRUE)[[1]]
    k <- length(parts)
    ends <- lapply(seq_len(k - 1L), function(i) seq.int(i + 1L, min(k, i + 4L)))
    runs <- unlist(lapply(seq_len(k - 1L), function(i) vapply(ends[[i]], function(j)
      paste0(paste(parts[i:j], collapse = ""),
             if (j == k && length(dec)) paste0(".", substring(dec, 2L)) else ""),
      character(1))), use.names = FALSE)
    out <- c(out, num(runs))
  }
  # Dots for thousands with a decimal comma, and a decimal comma alone.
  eur <- grab("(?<![0-9.,])[1-9][0-9]{0,2}(?:\\.[0-9]{3})+(?:,[0-9]+)?(?![0-9]|\\.[0-9])")
  out <- c(out, num(chartr(",", ".", gsub(".", "", eur, fixed = TRUE))),
           num(chartr(",", ".", grab("(?<![0-9.,])[0-9]+,[0-9]+(?![0-9]|[.,][0-9])"))))
  # a x 10^b, and 10^b alone. The caret is optional straight after "10" once
  # an "x" has said this is a power, because a PDF's text layer writes the
  # superscript exponent of 3.2 x 10^-5 as "10-5".
  for (g in groups(paste0(fig, "\\s*[x\u00d7*]\\s*10(?:\\s*(?:\\^|\\*\\*)\\s*|(?=[-+]?[0-9]))",
                          "([-+]?[0-9]{1,3})(?![0-9])"))) {
    out <- c(out, num(chartr(",", ".", g[1])) * 10^num(g[2]))
  }
  out <- c(out, 10^num(unlist(groups("(?<![0-9.,])10\\s*(?:\\^|\\*\\*)\\s*([-+]?[0-9]{1,3})"))))
  # Scale words, suffixes and percentages.
  # setNames(), not `"\u5343" = 1e3`: a name written in a call is made a
  # symbol in the native encoding, and under LC_ALL=C that mangles it.
  # A space before "bn" and "mn" ("$1.2 bn", "3 mn"), which name nothing
  # else; none before "k" and "m", which after a space are as often a unit
  # ("2.5 K" of potassium, "1.2 m" of height). The plurals and the other
  # languages' words for a million and a billion, after a figure only: the
  # English "billion", which in French and German is 1e12, is read as 1e9.
  scale <- stats::setNames(c(1e2, 1e3, 1e6, 1e9, 1e12, 1e5, 1e7, 1e3, 1e6, 1e6, 1e9,
                             1e3, 1e4, 1e4, 1e8, 1e8),
                           c("hundred", "thousand", "million", "billion", "trillion", "lakh",
                             "crore", "k", "m", "mn", "bn",
                             "\u5343", "\u4e07", "\u842c", "\u4ebf", "\u5104"))
  scale <- c(scale, .gr_foreign_scale)
  words <- paste(c("hundred", "thousands?", "millions?", "billions?", "trillions?", "lakhs?",
                   "crores?", names(.gr_foreign_scale)), collapse = "|")
  for (g in c(groups(paste0(fig, "\\s*(", words, ")(?![a-z])")),
              groups(paste0(fig, "(k|m)(?![a-z])")),
              groups(paste0(fig, "\\s?(mn|bn)(?![a-z])")),
              groups(paste0(fig, "\\s*([\u5343\u4e07\u842c\u4ebf\u5104])")))) {
    # A plural ("millions") is the word's own scale.
    key <- if (g[2] %in% names(scale)) g[2] else sub("s$", "", g[2])
    out <- c(out, figure(g[1]) * scale[[key]])
  }
  pct <- paste0("\\s*(?:%|per ?cent(?![a-z])|per ?cento|por ?cie?nto|pour ?cent|prozent|",
                "procent)")
  for (g in groups(paste0(fig, pct))) out <- c(out, figure(g[1]) / 100)
  # "1 in 5" is 0.2; "2 and a half" and "2" followed by a fraction sign
  # (U+00BD and the like) are 2.5.
  for (g in groups("(?<![0-9.,])([1-9][0-9]{0,2}) in ([1-9][0-9]{0,2}|1000)(?![0-9]|[.,][0-9])")) {
    if (num(g[1]) < num(g[2])) out <- c(out, num(g[1]) / num(g[2]))
  }
  out <- c(out, num(unlist(groups("(?<![0-9.,])([0-9]+) and a half(?![a-z])"))) + 0.5)
  signs <- paste(names(.gr_fraction_signs), collapse = "")
  for (g in groups(paste0("(?<![0-9.,])([0-9]*)([", signs, "])"))) {
    out <- c(out, fraction_readings(if (nzchar(g[1])) num(g[1]) else 0,
                                    .gr_fraction_signs[[g[2]]]))
  }
  out
}

#' A fraction as the numbers a paper may round it to: 2/3 is 0.667 and 0.67
#' as well. `whole` is added to it, for "2 and a half".
#' @noRd
fraction_readings <- function(whole, frac) {
  x <- whole + frac
  unique(c(x, round(x, 2), round(x, 3)))
}

#' The vulgar fraction signs, U+00BC to U+00BE and U+2153 to U+215E.
#' @noRd
.gr_fraction_signs <- stats::setNames(
  c(1 / 4, 1 / 2, 3 / 4, 1 / 3, 2 / 3, 1 / 5, 2 / 5, 3 / 5, 4 / 5, 1 / 6, 5 / 6,
    1 / 8, 3 / 8, 5 / 8, 7 / 8),
  strsplit(intToUtf8(c(0xBC, 0xBD, 0xBE, 0x2153:0x215E)), "")[[1]])

#' The words for a million and a billion in the languages foreign_numbers()
#' reads, as a figure is followed by them ("1,2 millions", "1,2 Mio."),
#' spelled as fold_numerals() leaves them.
#' @noRd
.gr_foreign_scale <- c(millones = 1e6, millon = 1e6, milhoes = 1e6, milhao = 1e6,
                       millionen = 1e6, milioni = 1e6, milione = 1e6, miljoen = 1e6,
                       miljoenen = 1e6, mio = 1e6, milliards = 1e9, milliard = 1e9,
                       milliarden = 1e9, milliarde = 1e9, miliardi = 1e9, miliardo = 1e9,
                       miljard = 1e9, miljarden = 1e9, mrd = 1e9)

#' English number words.
#'
#' APA and AMA style spell out a number that starts a sentence and, in APA,
#' most numbers below ten, so "Twenty-four patients were enrolled" and
#' "randomised to three arms" are how a count is often quoted. Cardinals to
#' the trillions, joined by spaces, hyphens and "and" ("one hundred and
#' twenty"), a compound ordinal ("twenty-first"), a percentage ("Fifty-four
#' percent" is 0.54 too), "two and a half", a fraction ("a quarter", "two
#' thirds") and "one in five".
#'
#' A word that does not name a number is read only where it counts
#' something, because nearly every sentence has one and the value check is
#' there to catch an invented 0, 1 or 2: "no" is 0 before a counted noun ("no
#' deaths", "No participants died"), never before "difference", "significant"
#' or "effect"; "none", "nobody" and "no one" are 0; "both" and "twice" are 2.
#' A bare ordinal ("the first visit", "the second author"), "one of" and
#' "once" or "single" are not counts, and "half" is 0.5 only as "a half",
#' "one half" or "half of".
#' @noRd
word_numbers <- function(s) {
  m <- gregexpr("[a-z]+", s, perl = TRUE)[[1]]
  if (m[1] < 0L) return(numeric(0))
  toks <- regmatches(s, list(m))[[1]]
  from <- as.integer(m)
  to <- from + attr(m, "match.length") - 1L
  n <- length(toks)
  # glue[i]: token i runs on from token i - 1, across a space or hyphen and
  # never across punctuation.
  glue <- c(FALSE, if (n > 1L) grepl("^[ -]+$", substring(s, to[-n] + 1L, from[-1L] - 1L)))
  # The k-th token after token i, when every step to it is glued; else "".
  after <- function(i, k = 1L) {
    j <- i + k
    if (j > n || !all(glue[(i + 1L):j])) "" else toks[j]
  }
  before <- function(i) if (i > 1L && glue[i]) toks[i - 1L] else ""
  small <- c(.gr_number_words, .gr_ordinal_words)

  # Runs of number words: value, first and last token, and whether the run is
  # a lone ordinal, which is a position rather than a count.
  rv <- numeric(0); rf <- integer(0); rl <- integer(0); rb <- logical(0)
  total <- 0; cur <- 0; last <- ""; start <- 1L; end <- 1L; card <- FALSE
  close <- function() {
    if (nzchar(last)) {
      rv <<- c(rv, total + cur); rf <<- c(rf, start); rl <<- c(rl, end); rb <<- c(rb, !card)
    }
    total <<- 0; cur <<- 0; last <<- ""; card <<- FALSE
  }
  then <- function(i, set) after(i) %in% set
  for (i in seq_len(n)) {
    t <- toks[i]
    if (i > 1L && !glue[i]) close()
    if (t == "one" && (then(i, c("of", "another")) || before(i) == "no")) {
      close()
    } else if (t %in% names(small)) {
      v <- small[[t]]
      kind <- if (v < 10) "unit" else if (v < 20) "teen" else "tens"
      # "twenty four" is one number; "two three" and "twenty thirty" are two.
      if (last %in% c("unit", "teen") || (last == "tens" && kind != "unit")) close()
      if (!nzchar(last)) start <- i
      cur <- cur + v
      last <- kind
      end <- i
      if (t %in% names(.gr_ordinal_words)) close() else card <- TRUE
    } else if (t %in% c("hundred", "dozen") && nzchar(last) && last != "hundred") {
      cur <- (if (cur > 0) cur else 1) * (if (t == "hundred") 100 else 12)
      last <- "hundred"
      end <- i
      card <- TRUE
    } else if (t %in% names(.gr_scale_words) && nzchar(last)) {
      # Only after a number: the "million" of "1.2 million" is not 1e6 on its
      # own (digit_numbers() reads that one), and "a million" set `last`.
      total <- total + (if (cur > 0) cur else 1) * .gr_scale_words[[t]]
      cur <- 0
      last <- "scale"
      end <- i
      card <- TRUE
    } else if (t == "and" && last %in% c("hundred", "scale") && then(i, names(small))) {
      next
    } else if (t == "a" && then(i, c("hundred", "dozen", names(.gr_scale_words)))) {
      close()
      start <- i
      cur <- 1
      last <- "a"
    } else {
      close()
    }
  }
  close()

  count <- !rb
  out <- rv[count]
  for (r in which(count)) {
    e <- rl[r]
    if (grepl("^\\s*(?:%|per ?cent(?![a-z]))", substr(s, to[e] + 1L, to[e] + 12L), perl = TRUE)) {
      out <- c(out, rv[r] / 100)
    }
    if (after(e) == "and" && after(e, 2L) == "a" && after(e, 3L) == "half") {
      out <- c(out, rv[r] + 0.5)
    }
    nx <- which(rf == e + 2L & count)
    if (after(e) == "in" && length(nx) && rv[r] >= 1 && rv[nx[1]] > rv[r]) {
      out <- c(out, rv[r] / rv[nx[1]])
    }
  }
  # A fraction: its numerator is the run of number words just before, or "a"
  # where a fraction of something follows ("a quarter of", "a half.") and
  # not a position ("a third arm", "a half-hour").
  for (i in which(toks %in% names(.gr_fraction_words))) {
    num <- NA_real_
    if (glue[i] && length(r <- which(rl == i - 1L & count))) {
      num <- rv[r[1]]
    } else if ((before(i) == "a" && (after(i) %in% c("", "of"))) ||
               (toks[i] == "half" && then(i, c("of", "the")) &&
                !before(i) %in% c(names(.gr_ordinal_words), "the", "last", "other"))) {
      num <- 1
    }
    if (!is.na(num) && num >= 1 && num < 100) {
      out <- c(out, fraction_readings(0, num / .gr_fraction_words[[toks[i]]]))
    }
  }
  # Words that state a count without being a numeral, where they count.
  for (i in which(toks %in% names(.gr_count_words))) {
    if (toks[i] == "no" && after(i) != "one") {
      nxt <- c(after(i), after(i, 2L), after(i, 3L))
      if (!any(nxt %in% .gr_counted_nouns) || any(nxt %in% .gr_uncounted_words)) next
    }
    out <- c(out, .gr_count_words[[toks[i]]])
  }
  out
}

#' @noRd
.gr_number_words <- c(zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5, six = 6,
                      seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11, twelve = 12,
                      thirteen = 13, fourteen = 14, fifteen = 15, sixteen = 16,
                      seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
                      thirty = 30, forty = 40, fifty = 50, sixty = 60, seventy = 70,
                      eighty = 80, ninety = 90)

#' @noRd
.gr_ordinal_words <- c(first = 1, second = 2, third = 3, fourth = 4, fifth = 5, sixth = 6,
                       seventh = 7, eighth = 8, ninth = 9, tenth = 10, eleventh = 11,
                       twelfth = 12, thirteenth = 13, fourteenth = 14, fifteenth = 15,
                       sixteenth = 16, seventeenth = 17, eighteenth = 18, nineteenth = 19,
                       twentieth = 20, thirtieth = 30, fortieth = 40, fiftieth = 50,
                       sixtieth = 60, seventieth = 70, eightieth = 80, ninetieth = 90)

#' @noRd
.gr_scale_words <- c(thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12,
                     lakh = 1e5, crore = 1e7)

#' Words that state a count without being a numeral; "no" only before a
#' counted noun (see word_numbers()).
#' @noRd
.gr_count_words <- c(no = 0, none = 0, nil = 0, nobody = 0, nought = 0, twice = 2, both = 2,
                     thrice = 3)

#' The denominators of a fraction written in words.
#' @noRd
.gr_fraction_words <- c(half = 2, halves = 2, third = 3, thirds = 3, quarter = 4, quarters = 4,
                        fourth = 4, fourths = 4, fifth = 5, fifths = 5, sixth = 6, sixths = 6,
                        seventh = 7, sevenths = 7, eighth = 8, eighths = 8, ninth = 9,
                        ninths = 9, tenth = 10, tenths = 10)

#' What "no" counts when it is 0: "no deaths", "No participants died", "no
#' serious adverse events". Within three words of it, and with none of
#' .gr_uncounted_words there: "no difference in deaths" counts nothing.
#' @noRd
.gr_counted_nouns <- c(
  "patient", "patients", "participant", "participants", "subject", "subjects", "person",
  "persons", "people", "individual", "individuals", "adult", "adults", "child", "children",
  "infant", "infants", "neonate", "neonates", "baby", "babies", "woman", "women", "man", "men",
  "volunteer", "volunteers", "respondent", "respondents", "case", "cases", "death", "deaths",
  "died", "event", "events", "fatality", "fatalities", "withdrawal", "withdrawals", "dropout",
  "dropouts", "loss", "losses", "relapse", "relapses", "recurrence", "recurrences",
  "complication", "complications", "infection", "infections", "hospitalisation",
  "hospitalisations", "hospitalization", "hospitalizations", "admission", "admissions",
  "readmission", "readmissions", "fracture", "fractures", "fall", "falls", "stroke", "strokes",
  "reaction", "reactions", "toxicity", "toxicities", "site", "sites", "centre", "centres",
  "center", "centers", "hospital", "hospitals", "clinic", "clinics", "study", "studies", "trial",
  "trials", "arm", "arms", "cohort", "cohorts", "record", "records", "article", "articles")

#' Words that make "no" a verdict rather than a count: "no difference", "no
#' significant effect", "no evidence", "no one".
#' @noRd
.gr_uncounted_words <- c(
  "difference", "differences", "different", "significant", "significantly", "significance",
  "statistically", "statistical", "evidence", "effect", "effects", "association",
  "associations", "associated", "change", "changes", "changed", "correlation", "relationship",
  "role", "impact", "influence", "benefit", "benefits", "increase", "increased", "decrease",
  "decreased", "reduction", "improvement", "longer", "more", "less", "fewer", "further",
  "other", "one", "clear", "major", "substantial", "relevant", "meaningful", "history",
  "prior", "previous", "known", "data", "information", "sign", "signs", "trend", "risk",
  "interaction", "heterogeneity", "bias", "conflict", "conflicts", "competing", "need")

#' Chinese (and Japanese) numerals: U+4E09 U+7EC4 is "three groups", U+4E00
#' U+767E U+4E8C U+5341 is 120, and a year may be written digit by digit.
#' @noRd
han_numbers <- function(s) {
  # Named with setNames() for the reason digit_numbers() gives.
  digit <- stats::setNames(c(0, 0, 1, 2, 2, 2, 3, 4, 5, 6, 7, 8, 9),
                           c("\u96f6", "\u3007", "\u4e00", "\u4e8c", "\u4e24", "\u5169",
                             "\u4e09", "\u56db", "\u4e94", "\u516d", "\u4e03", "\u516b",
                             "\u4e5d"))
  unit <- stats::setNames(c(10, 100, 1000), c("\u5341", "\u767e", "\u5343"))
  big <- stats::setNames(c(1e4, 1e4, 1e8, 1e8), c("\u4e07", "\u842c", "\u4ebf", "\u5104"))
  runs <- regmatches(s, gregexpr(paste0("[", paste(c(names(digit), names(unit), names(big)),
                                                   collapse = ""), "]+"), s, perl = TRUE))[[1]]
  # A run with no digit and no ten states no number: the hundred (U+767E) of
  # "per cent" or a lone ten thousand (U+4E07) is not 0.
  runs <- runs[grepl(paste0("[", paste(c(names(digit), "\u5341"), collapse = ""), "]"), runs,
                     perl = TRUE)]
  vapply(runs, function(r) {
    total <- 0; section <- 0; n <- 0; prev_digit <- FALSE
    for (ch in strsplit(r, "", fixed = TRUE)[[1]]) {
      if (ch %in% names(digit)) {
        n <- if (prev_digit) n * 10 + digit[[ch]] else digit[[ch]]
        prev_digit <- TRUE
      } else if (ch %in% names(unit)) {
        # Ten then two (U+5341 U+4E8C) is 12: a bare ten counts one ten.
        section <- section + (if (n == 0 && !prev_digit) 1 else n) * unit[[ch]]
        n <- 0; prev_digit <- FALSE
      } else {
        total <- if (big[[ch]] >= 1e8) (total + section + n) * big[[ch]]
                 else total + (section + n) * big[[ch]]
        section <- 0; n <- 0; prev_digit <- FALSE
      }
    }
    total + section + n
  }, numeric(1), USE.NAMES = FALSE)
}

#' Roman numerals where a paper uses them for a number: "phase III", "stage
#' IIb", "grade II/III". Only after such a word, because on its own "iv" is
#' intravenous and "vi" a sixth of nothing.
#' @noRd
roman_numbers <- function(s) {
  pat <- paste0("(?<![a-z])(?:phase|stage|grade|type|class|level|tier|category|group|arm|",
                "part|wave|cycle|step)s?\\s+([ivxl]+)[abc]?(?:\\s*[/-]\\s*([ivxl]+)[abc]?)?",
                "(?![a-z])")
  hits <- regmatches(s, gregexpr(pat, s, perl = TRUE))[[1]]
  romans <- unlist(lapply(hits, function(x) regmatches(x, regexec(pat, x, perl = TRUE))[[1]][-1L]),
                   use.names = FALSE)
  romans <- romans[nzchar(romans)]
  # utils::as.roman() reads "iiii" and "vx" too; it is the value that counts.
  out <- suppressWarnings(as.integer(utils::as.roman(toupper(romans))))
  as.numeric(out[!is.na(out)])
}

#' Which language a quotation's number words are in.
#'
#' English and Chinese number words are read in any quotation (word_numbers(),
#' han_numbers()). One written in Spanish, Portuguese, French, Italian, German
#' or Dutch is read with that language's words instead (foreign_numbers()):
#' its "veinticuatro" is 24, and its "no", "once" and "ten" are not the
#' English 0, 1 and 10. A quotation is in one of those languages when it holds
#' none of the commonest English words (.gr_english_words) and at least two
#' words of that language, one of them a word English prose does not use
#' (.gr_numeral_languages). So "SE", "de novo", "en bloc", "von Willebrand",
#' a Greek letter or an accented name leave an English sentence English.
#'
#' A quotation most of whose letters are of a script other than Latin, Han
#' and kana (Cyrillic, Greek, Arabic, Hangul and the like) is "script": no
#' reader here knows its number words (see pieces_back_value()).
#'
#' `folded` says `s` has been through fold_numerals() already.
#' @return "en", "script", or the codes of the languages it is in (more than
#'   one only on a tie).
#' @noRd
quote_language <- function(s, folded = FALSE) {
  if (!folded) s <- fold_numerals(as_chr1(s, ""))
  count <- function(pat) {
    m <- gregexpr(pat, s, perl = TRUE)[[1]]
    if (m[1] < 0L) 0L else length(m)
  }
  if (grepl("[^\\x01-\\x7f]", s, perl = TRUE)) {
    other <- count("(?=\\p{L})[^\\p{Latin}\\p{Han}\\p{Hiragana}\\p{Katakana}]")
    if (other > 0L && 2L * other > count("\\p{L}")) return("script")
  }
  toks <- unique(regmatches(s, gregexpr("[a-z]+", s, perl = TRUE))[[1]])
  if (!length(toks) || any(toks %in% .gr_english_words)) return("en")
  score <- vapply(.gr_numeral_languages, function(L) {
    # A number word counts as a word of the language when English has no
    # such word: "veinticuatro" and "vierundzwanzig" do, "once" and "cent"
    # do not.
    cand <- toks[nchar(toks) >= 4L & !toks %in% c(L$one, .gr_numeral_false_friends) &
                   grepl(L$pattern, toks, perl = TRUE)]
    strong <- sum(toks %in% L$strong) +
      sum(vapply(cand, function(t) !is.null(numeral_parts(t, L)), logical(1)))
    weak <- sum(toks %in% L$weak)
    if (strong >= 1L && strong + weak >= 2L) strong + weak else 0L
  }, integer(1))
  if (max(score) == 0L) return("en")
  names(score)[score == max(score)]
}

#' Words English quotations are nearly all written with and none of the
#' languages quote_language() tells apart uses. One of them makes a quotation
#' English, whatever else it holds.
#' @noRd
.gr_english_words <- c("the", "and", "with", "were", "which", "from", "this", "that", "these",
                       "those", "been", "are", "has", "have", "their", "they", "we", "our",
                       "than", "into", "during", "between", "after", "who", "there", "it", "its")

#' Number words of the languages below that are English words too, or common
#' in English prose: not evidence that a quotation is in another language.
#' @noRd
.gr_numeral_false_friends <- c("once", "cent", "cents", "sept", "seize", "zero", "otto", "tres",
                               "nove", "venti", "null", "mille", "mila", "twee", "tien", "million",
                               "millions")

#' One language for foreign_numbers(), from space-separated lists.
#'
#' `words` is "word value" pairs of the cardinals below a thousand spelled as
#' one word; `one` the words for one, which are articles too and so count
#' only inside a larger number; `hundred` the words for a hundred, which
#' multiply the number before them; `scale` "word value" pairs for a thousand
#' and more; `alone` the ones of those that are a number with nothing before
#' them ("mil pacientes"); `join` the word for "and" inside a number.
#' `compound` for a language that writes a number as one word
#' ("vierundzwanzig", "centoventi"); `inner` the forms of such a language that
#' occur only inside one ("vent" of "ventotto"); `reversed` for one that puts
#' the unit before the tens ("vier und zwanzig"); `french` for the tens of
#' French ("soixante-dix", "dix-sept"); `prepare` a function run on the text
#' first; `idioms` two-word phrases in which a number word is not a number
#' (German "ausser acht", disregarded). `strong` and `weak` are the language's
#' common words, those English does not use and those it does, for
#' quote_language().
#' @noRd
numeral_language <- function(words, one, hundred, scale, alone, join, strong, weak,
                             compound = FALSE, reversed = FALSE, french = FALSE, inner = "",
                             prepare = NULL, idioms = character(0)) {
  sp <- function(x) {
    x <- strsplit(x, " ", fixed = TRUE)[[1]]
    x[nzchar(x)]
  }
  pairs <- function(x) {
    x <- sp(x)
    stats::setNames(as.numeric(x[c(FALSE, TRUE)]), x[c(TRUE, FALSE)])
  }
  words <- pairs(words)
  scale <- pairs(scale)
  all <- unique(c(names(words), sp(one), sp(hundred), names(scale), sp(join)))
  # Longest first, so a split tries "dieci" before "die" and "cento" before
  # "cent" -- and, failing, the shorter.
  morphemes <- all[order(-nchar(all), all)]
  alt <- paste(morphemes, collapse = "|")
  list(words = words, one = sp(one), hundred = sp(hundred), scale = scale, alone = sp(alone),
       join = sp(join), strong = sp(strong), weak = sp(weak), compound = compound,
       reversed = reversed, french = french, inner = sp(inner), prepare = prepare,
       idioms = idioms, morphemes = morphemes,
       pattern = if (compound) paste0("^(?:", alt, ")+$") else paste0("^(?:", alt, ")$"))
}

#' The languages whose number words foreign_numbers() reads, spelled without
#' accents as fold_numerals() leaves them.
#' @noRd
.gr_numeral_languages <- list(
  es = numeral_language(
    words = paste("cero 0 dos 2 tres 3 cuatro 4 cinco 5 seis 6 siete 7 ocho 8 nueve 9 diez 10",
                  "once 11 doce 12 trece 13 catorce 14 quince 15 dieciseis 16 diecisiete 17",
                  "dieciocho 18 diecinueve 19 veinte 20 veintiuno 21 veintiuna 21 veintiun 21",
                  "veintidos 22 veintitres 23 veinticuatro 24 veinticinco 25 veintiseis 26",
                  "veintisiete 27 veintiocho 28 veintinueve 29 treinta 30 cuarenta 40",
                  "cincuenta 50 sesenta 60 setenta 70 ochenta 80 noventa 90 doscientos 200",
                  "doscientas 200 trescientos 300 trescientas 300 cuatrocientos 400",
                  "cuatrocientas 400 quinientos 500 quinientas 500 seiscientos 600",
                  "seiscientas 600 setecientos 700 setecientas 700 ochocientos 800",
                  "ochocientas 800 novecientos 900 novecientas 900"),
    one = "un uno una", hundred = "cien ciento", scale = "mil 1e3 millon 1e6 millones 1e6",
    alone = "mil", join = "y",
    strong = paste("el los las que por una unos unas fueron fue eran entre sus como tras",
                   "durante hubo han sido pacientes estudio grupo grupos mujeres hombres",
                   "tratamiento incluyeron incluidos"),
    weak = "de la en se y al del con para no lo"),
  pt = numeral_language(
    words = paste("zero 0 dois 2 duas 2 tres 3 quatro 4 cinco 5 seis 6 sete 7 oito 8 nove 9",
                  "dez 10 onze 11 doze 12 treze 13 catorze 14 quatorze 14 quinze 15",
                  "dezesseis 16 dezasseis 16 dezessete 17 dezassete 17 dezoito 18 dezenove 19",
                  "dezanove 19 vinte 20 trinta 30 quarenta 40 cinquenta 50 sessenta 60",
                  "setenta 70 oitenta 80 noventa 90 duzentos 200 duzentas 200 trezentos 300",
                  "trezentas 300 quatrocentos 400 quatrocentas 400 quinhentos 500",
                  "quinhentas 500 seiscentos 600 seiscentas 600 setecentos 700 setecentas 700",
                  "oitocentos 800 oitocentas 800 novecentos 900 novecentas 900"),
    one = "um uma", hundred = "cem cento", scale = "mil 1e3 milhao 1e6 milhoes 1e6",
    alone = "mil", join = "e",
    strong = paste("foram foi eram uma pelo pela pelos pelas seus suas ao aos nao sao tambem",
                   "entre durante estudo pacientes grupo grupos mulheres homens tratamento",
                   "incluidos das nas nos"),
    weak = "de da do dos os as no na em com e um que se para por"),
  fr = numeral_language(
    words = paste("zero 0 deux 2 trois 3 quatre 4 cinq 5 six 6 sept 7 huit 8 neuf 9 dix 10",
                  "onze 11 douze 12 treize 13 quatorze 14 quinze 15 seize 16 vingt 20",
                  "vingts 20 trente 30 quarante 40 cinquante 50 soixante 60 septante 70",
                  "huitante 80 octante 80 nonante 90 quatrevingt 80"),
    one = "un une", hundred = "cent cents",
    scale = "mille 1e3 million 1e6 millions 1e6 milliard 1e9 milliards 1e9",
    alone = "mille", join = "et",
    strong = paste("les des du dans avec sont une ont qui aux ete etait etaient sur pour leur",
                   "leurs chez ces cette apres selon ainsi etude groupe groupes traitement",
                   "femmes hommes ans inclus"),
    weak = "le la de en se et au par plus est un",
    french = TRUE,
    # "quatre-vingts" is 80, not 4 and 20.
    prepare = function(s) gsub("quatre[- ]vingts?(?![a-z])", "quatrevingt", s, perl = TRUE)),
  it = numeral_language(
    words = paste("zero 0 due 2 tre 3 quattro 4 cinque 5 sei 6 sette 7 otto 8 nove 9 dieci 10",
                  "undici 11 dodici 12 tredici 13 quattordici 14 quindici 15 sedici 16",
                  "diciassette 17 diciotto 18 diciannove 19 venti 20 vent 20 trenta 30",
                  "trent 30 quaranta 40 quarant 40 cinquanta 50 cinquant 50 sessanta 60",
                  "sessant 60 settanta 70 settant 70 ottanta 80 ottant 80 novanta 90",
                  "novant 90"),
    one = "uno un una", hundred = "cento cent",
    scale = "mille 1e3 mila 1e3 milione 1e6 milioni 1e6 miliardo 1e9 miliardi 1e9",
    alone = "mille", join = "",
    strong = paste("il gli della delle dello degli dei sono stati stato state nel nella nelle",
                   "nei negli che una tra fra sul sulla alla alle ai agli anni pazienti gruppo",
                   "gruppi trattamento donne uomini inclusi erano essere anche dopo durante",
                   "secondo ogni"),
    weak = "di con per e ed del al la le un uno era studio",
    compound = TRUE,
    inner = "vent trent quarant cinquant sessant settant ottant novant cent"),
  de = numeral_language(
    words = paste("null 0 eins 1 zwei 2 zwo 2 drei 3 vier 4 funf 5 fuenf 5 sechs 6 sieben 7",
                  "acht 8 neun 9 zehn 10 elf 11 zwolf 12 zwoelf 12 dreizehn 13 vierzehn 14",
                  "funfzehn 15 fuenfzehn 15 sechzehn 16 siebzehn 17 achtzehn 18 neunzehn 19",
                  "zwanzig 20 dreissig 30 vierzig 40 funfzig 50 fuenfzig 50 sechzig 60",
                  "siebzig 70 achtzig 80 neunzig 90"),
    one = "ein eine", hundred = "hundert",
    scale = "tausend 1e3 million 1e6 millionen 1e6 milliarde 1e9 milliarden 1e9",
    alone = "tausend", join = "und",
    strong = paste("der das und mit wurden wurde eine einer einem einen eines zu bei dem im ist",
                   "sind nach auf fur aus nicht sich zum zur je oder wie als auch durch uber",
                   "unter zwischen jahre jahren patienten studie gruppe gruppen behandlung",
                   "frauen manner eingeschlossen insgesamt umfasste"),
    weak = "die den des von in es war an so",
    compound = TRUE, reversed = TRUE,
    idioms = c("ausser acht", "acht lassen", "acht gelassen", "acht nehmen", "acht genommen",
               "acht geben", "acht gegeben")),
  nl = numeral_language(
    words = paste("nul 0 twee 2 drie 3 vier 4 vijf 5 zes 6 zeven 7 acht 8 negen 9 tien 10",
                  "elf 11 twaalf 12 dertien 13 veertien 14 vijftien 15 zestien 16 zeventien 17",
                  "achttien 18 negentien 19 twintig 20 dertig 30 veertig 40 vijftig 50",
                  "zestig 60 zeventig 70 tachtig 80 negentig 90"),
    one = "een", hundred = "honderd",
    scale = "duizend 1e3 miljoen 1e6 miljoenen 1e6 miljard 1e9 miljarden 1e9",
    alone = "duizend", join = "en",
    strong = paste("het een werden werd zijn met bij voor naar uit niet dat ook door tussen",
                   "jaar jaren patienten studie groep groepen behandeling vrouwen mannen",
                   "ingesloten totaal opzichte"),
    weak = "de en van in is op te ten er als dan na of",
    compound = TRUE, reversed = TRUE,
    idioms = c("acht nemen", "acht genomen", "acht neemt", "acht nam", "acht slaan",
               "acht geslagen")))

#' Number words of the languages quote_language() names, read as
#' word_numbers() reads English ones.
#'
#' "veinticuatro", "vinte e quatro", "vingt-quatre", "ventiquattro",
#' "vierundzwanzig" and "vierentwintig" are each 24; "ciento veinte", "cent
#' vingt" and "hundertzwanzig" 120; "dos mil" 2000 and "un millon" 1e6; and
#' "cincuenta por ciento" 0.5 as well as 50. A word for one alone ("un",
#' "ein", "een") is an article as often as a number, so it counts only inside
#' a larger number ("veintiuno", "un millon"). Where two languages tie, a
#' common word of the other is not read as a number ("dos" is "of the" in
#' Portuguese).
#' @noRd
foreign_numbers <- function(s, langs) {
  out <- numeric(0)
  for (code in langs) {
    L <- .gr_numeral_languages[[code]]
    avoid <- unlist(lapply(.gr_numeral_languages[setdiff(langs, code)],
                           function(o) c(o$strong, o$weak)), use.names = FALSE)
    out <- c(out, read_numerals(if (is.null(L$prepare)) s else L$prepare(s), L, avoid))
  }
  out
}

#' foreign_numbers() for one language `L` (see numeral_language()).
#' @noRd
read_numerals <- function(s, L, avoid = character(0)) {
  m <- gregexpr("[a-z]+", s, perl = TRUE)[[1]]
  if (m[1] < 0L) return(numeric(0))
  toks <- regmatches(s, list(m))[[1]]
  from <- as.integer(m)
  to <- from + attr(m, "match.length") - 1L
  n <- length(toks)
  # A number runs on across a space or hyphen, never across punctuation.
  glue <- c(FALSE, if (n > 1L) grepl("^[ -]+$", substring(s, to[-n] + 1L, from[-1L] - 1L)))
  parts <- vector("list", n)
  for (i in which(grepl(L$pattern, toks, perl = TRUE) & !toks %in% avoid)) {
    idiom <- (glue[i] && paste(toks[i - 1L], toks[i]) %in% L$idioms) ||
      (i < n && glue[i + 1L] && paste(toks[i], toks[i + 1L]) %in% L$idioms)
    if (!idiom) parts[i] <- list(numeral_parts(toks[i], L))
  }
  if (all(vapply(parts, is.null, logical(1)))) return(numeric(0))

  out <- numeric(0)
  total <- 0; cur <- 0; big <- Inf; end <- 0L
  started <- FALSE; strong <- FALSE; joined <- FALSE
  emit <- function() {
    if (strong) {
      v <- total + cur
      out <<- c(out, v)
      if (grepl("^\\s*(?:%|por ?cie?nto|por ?cento|pour ?cent|per ?cento|prozent|procent)",
                substr(s, to[end] + 1L, to[end] + 16L), perl = TRUE)) {
        out <<- c(out, v / 100)
      }
    }
    total <<- 0; cur <<- 0; big <<- Inf
    started <<- FALSE; strong <<- FALSE; joined <<- FALSE
  }
  add <- function(i, weak = FALSE) {
    started <<- TRUE
    if (!weak) strong <<- TRUE
    joined <<- FALSE
    end <<- i
  }
  step <- function(mm, i) {
    if (mm %in% L$join) {
      if (started) joined <<- TRUE
    } else if (mm %in% names(L$scale)) {
      sv <- L$scale[[mm]]
      if (started && sv < big) {
        total <<- total + max(cur, 1) * sv
        cur <<- 0
      } else {
        # "millones" alone is not a number; "mil" alone is 1000.
        emit()
        if (!mm %in% L$alone) return(invisible())
        total <<- sv
      }
      big <<- sv
      add(i)
    } else if (mm %in% L$hundred) {
      if (cur >= 10) emit()
      cur <<- max(cur, 1) * 100
      add(i)
    } else {
      weak <- mm %in% L$one
      v <- if (weak) 1 else L$words[[mm]]
      if (v == 0) {
        emit()
        out <<- c(out, 0)
        return(invisible())
      }
      if (!numeral_fits(cur, v, joined, L)) emit()
      cur <<- cur + v
      add(i, weak)
    }
    invisible()
  }
  for (i in seq_len(n)) {
    if (i > 1L && !glue[i]) emit()
    p <- parts[[i]]
    # The hundred of "por ciento", "pour cent" or "per cento" says per cent.
    if (is.null(p) || (toks[i] %in% L$hundred && glue[i] &&
                       toks[i - 1L] %in% c("por", "pour", "per"))) {
      emit()
      next
    }
    for (mm in p) step(mm, i)
  }
  emit()
  out
}

#' The words a number word of language `L` is made of: itself, or for a
#' language that writes a number as one word, its parts ("vier", "und",
#' "zwanzig"). NULL when it is not one number: a compound that opens or
#' closes on "and" ("vieren", "tienen"), an inner form on its own ("vent"),
#' or parts that are not one number together (Italian "undue", 1 and 2).
#' @noRd
numeral_parts <- function(tok, L) {
  if (!L$compound) return(tok)
  split <- function(rest) {
    if (!nzchar(rest)) return(character(0))
    for (m in L$morphemes) {
      if (startsWith(rest, m)) {
        tail <- split(substring(rest, nchar(m) + 1L))
        if (!is.null(tail)) return(c(m, tail))
      }
    }
    NULL
  }
  p <- split(tok)
  if (is.null(p) || p[1L] %in% L$join || p[length(p)] %in% L$join ||
      (length(p) == 1L && p %in% L$inner)) return(NULL)
  if (length(p) == 1L) return(p)
  cur <- 0; big <- Inf; joined <- FALSE
  for (m in p) {
    if (m %in% L$join) {
      joined <- TRUE
      next
    }
    if (m %in% names(L$scale)) {
      if (L$scale[[m]] >= big) return(NULL)
      big <- L$scale[[m]]
      cur <- 0
    } else if (m %in% L$hundred) {
      if (cur >= 10) return(NULL)
      cur <- max(cur, 1) * 100
    } else {
      v <- if (m %in% L$one) 1 else L$words[[m]]
      if (v == 0 || !numeral_fits(cur, v, joined, L)) return(NULL)
      cur <- cur + v
    }
    joined <- FALSE
  }
  p
}

#' Can a word worth `v` (below a thousand) carry on a number whose part below
#' a thousand is `cur`, in language `L`? "treinta y dos" is one number and
#' "tres cuatro" two, as in word_numbers(); so are "vier und zwanzig" (`joined`
#' by "und", in a language that puts the unit first), and "soixante-dix" and
#' "dix-sept" in French.
#' @noRd
numeral_fits <- function(cur, v, joined, L) {
  low <- cur %% 100
  if (v >= 100) return(cur == 0)
  if (v >= 20 && v %% 10 == 0) return(low == 0 || (L$reversed && joined && low %in% 1:9))
  if (v >= 20) return(low == 0)
  if (v >= 10) return(low == 0 || (L$french && low %in% c(60, 80)))
  low == 0 || (low >= 20 && low %% 10 == 0) || (L$french && low == 10)
}

#' Is `x` among the numbers a quotation states?
#' @noRd
value_among <- function(x, got) {
  length(got) > 0L && is.finite(x) && any(abs(got - x) <= 1e-9 * max(1, x))
}

#' Does a quotation carry the value it is cited for?
#'
#' span_match() answers whether the span is in the chunk. This answers whether,
#' being there, it backs THIS value, and it fails the ways a quote can be real
#' and still prove nothing:
#'
#' * It must sit on word boundaries in the chunk. "120 participants" occurs
#'   inside "1120 participants", and "2" inside almost anything. The boundary
#'   test is span_match()'s own (found_at()), run on the chunk as written: a
#'   separate one here rejected what span_match() rightly accepts -- a sentence
#'   stopping before a superscript reference PDF text keeps inline
#'   ("mortality12"), a clause of Thai or Khmer -- and require_quote deleted
#'   those values although their quotes verified.
#' * For an integer or a number, the value must be one of the numbers the span
#'   states, in whatever form it states them (quote_numbers()). A real
#'   sentence paired with an invented number was the worst case
#'   numeric_token() describes -- a figure certified that the paper never gives.
#'   The one exception is a quotation in a script whose number words nothing
#'   here reads, that states no number that can be read (see
#'   pieces_back_value()); ?gr_extract says so.
#' * Anything else cannot be looked for in its quote (TRUE is not written in
#'   "funded by Pfizer"), so the quote has to be a passage rather than a word
#'   that occurs anywhere: two words at least, or long enough to be specific in
#'   a script written without spaces, unless the one word is the value itself.
#'
#' A quotation made of several passages (separate lines, bullets, "[...]",
#' **bold**) is split as span_match() splits it (quote_passages()): each
#' passage must sit on word boundaries, and the value may be in any of them.
#' Checked as one string, such a quote never verified here although
#' span_match() accepted it, so require_quote deleted a faithfully quoted
#' value. What the split leaves out is checked too (passage_gaps_ok()), so an
#' elision cannot drop a "not" or join one sentence's subject to another's
#' claim. The value is still ANDed with span_match().
#'
#' A value this rejects is kept and counted in `n_unverified`, as a paraphrase
#' is; only `require_quote = TRUE` drops it.
#' @noRd
quote_backs_value <- function(value, quote, source, field) {
  if (is.null(value) || is.null(field)) return(FALSE)
  q <- quote_passages(quote)
  txt <- as_chr1(source, "")
  # match_source(), as span_match() reads the chunk: its `text` is the
  # normalised chunk, and the boundary test sees an em dash or a grouping
  # space as written rather than folded into a minus sign or a word break.
  src <- match_source(txt)
  if (!length(q$raw) || !nzchar(src$text)) return(FALSE)
  # Bold is emphasis, in the quotation or the source: try the quotation as
  # written and, failing that, with bold taken out of both sides, as
  # span_match() does -- never out of one side only.
  if (pieces_back_value(value, q$raw, src, field)) return(TRUE)
  if (is.null(q$plain) && !grepl("**", txt, fixed = TRUE)) return(FALSE)
  pieces_back_value(value, q$plain %||% q$raw, match_source(strip_bold(txt)), field)
}
