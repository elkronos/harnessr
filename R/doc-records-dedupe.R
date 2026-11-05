# doc-records-dedupe.R: duplicate records found and merged.

#' Latin letters that carry a diacritic, and the plain letter each folds to.
#'
#' A table rather than `iconv(to = "ASCII//TRANSLIT")`, which folded an
#' e-acute to "e" but DELETED every letter it had no ASCII spelling for: Greek,
#' Cyrillic and CJK titles came out as their digits and Latin fragments, so
#' "PPAR-alpha" and "PPAR-gamma" (the Greek letters, not the words) were one
#' title, and two different Chinese titles about type 2 diabetes were both "2".
#' What it keeps also depends on the platform's iconv and the locale -- glibc
#' in the C locale writes "?" for an e-acute -- so a table is the only way two
#' machines agree on which records are one work.
#' @noRd
.gr_latin_fold <- local({
  one <- c(
    a = "\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u0101\u0103\u0105",
    A = "\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u0100\u0102\u0104",
    c = "\u00e7\u0107\u0109\u010b\u010d", C = "\u00c7\u0106\u0108\u010a\u010c",
    d = "\u010f\u0111\u00f0", D = "\u010e\u0110\u00d0",
    e = "\u00e8\u00e9\u00ea\u00eb\u0113\u0115\u0117\u0119\u011b",
    E = "\u00c8\u00c9\u00ca\u00cb\u0112\u0114\u0116\u0118\u011a",
    g = "\u011d\u011f\u0121\u0123", G = "\u011c\u011e\u0120\u0122",
    h = "\u0125\u0127", H = "\u0124\u0126",
    i = "\u00ec\u00ed\u00ee\u00ef\u0129\u012b\u012d\u012f\u0131",
    I = "\u00cc\u00cd\u00ce\u00cf\u0128\u012a\u012c\u012e\u0130",
    j = "\u0135", J = "\u0134", k = "\u0137", K = "\u0136",
    l = "\u013a\u013c\u013e\u0140\u0142", L = "\u0139\u013b\u013d\u013f\u0141",
    n = "\u00f1\u0144\u0146\u0148", N = "\u00d1\u0143\u0145\u0147",
    o = "\u00f2\u00f3\u00f4\u00f5\u00f6\u00f8\u014d\u014f\u0151",
    O = "\u00d2\u00d3\u00d4\u00d5\u00d6\u00d8\u014c\u014e\u0150",
    r = "\u0155\u0157\u0159", R = "\u0154\u0156\u0158",
    s = "\u015b\u015d\u015f\u0161\u0219", S = "\u015a\u015c\u015e\u0160\u0218",
    t = "\u0163\u0165\u0167\u021b", T = "\u0162\u0164\u0166\u021a",
    u = "\u00f9\u00fa\u00fb\u00fc\u0169\u016b\u016d\u016f\u0171\u0173",
    U = "\u00d9\u00da\u00db\u00dc\u0168\u016a\u016c\u016e\u0170\u0172",
    w = "\u0175", W = "\u0174",
    y = "\u00fd\u00ff\u0177", Y = "\u00dd\u0178\u0176",
    z = "\u017a\u017c\u017e", Z = "\u0179\u017b\u017d")
  # Every other letter in Latin Extended-B and Latin Extended Additional whose
  # canonical decomposition is one plain letter and marks: Vietnamese above all
  # ("Nguy\u1ec5n" was a different surname from "Nguyen", where the old iconv step
  # made them one), and what a BibTeX accent command composes to.
  ext <- c(
    a = paste0("\u01ce\u01df\u01e1\u01fb\u0201\u0203\u0227\u1e01\u1ea1\u1ea3\u1ea5\u1ea7",
               "\u1ea9\u1eab\u1ead\u1eaf\u1eb1\u1eb3\u1eb5\u1eb7"),
    A = paste0("\u01cd\u01de\u01e0\u01fa\u0200\u0202\u0226\u1e00\u1ea0\u1ea2\u1ea4\u1ea6",
               "\u1ea8\u1eaa\u1eac\u1eae\u1eb0\u1eb2\u1eb4\u1eb6"),
    b = "\u1e03\u1e05\u1e07", B = "\u1e02\u1e04\u1e06", c = "\u1e09", C = "\u1e08",
    d = "\u1e0b\u1e0d\u1e0f\u1e11\u1e13", D = "\u1e0a\u1e0c\u1e0e\u1e10\u1e12",
    e = paste0("\u0205\u0207\u0229\u1e15\u1e17\u1e19\u1e1b\u1e1d\u1eb9\u1ebb\u1ebd\u1ebf",
               "\u1ec1\u1ec3\u1ec5\u1ec7"),
    E = paste0("\u0204\u0206\u0228\u1e14\u1e16\u1e18\u1e1a\u1e1c\u1eb8\u1eba\u1ebc\u1ebe",
               "\u1ec0\u1ec2\u1ec4\u1ec6"),
    f = "\u1e1f", F = "\u1e1e", g = "\u01e7\u01f5\u1e21", G = "\u01e6\u01f4\u1e20",
    h = "\u021f\u1e23\u1e25\u1e27\u1e29\u1e2b\u1e96", H = "\u021e\u1e22\u1e24\u1e26\u1e28\u1e2a",
    i = "\u01d0\u0209\u020b\u1e2d\u1e2f\u1ec9\u1ecb", I = "\u01cf\u0208\u020a\u1e2c\u1e2e\u1ec8\u1eca",
    j = "\u01f0\u0237", k = "\u01e9\u1e31\u1e33\u1e35", K = "\u01e8\u1e30\u1e32\u1e34",
    l = "\u1e37\u1e39\u1e3b\u1e3d", L = "\u1e36\u1e38\u1e3a\u1e3c",
    m = "\u1e3f\u1e41\u1e43", M = "\u1e3e\u1e40\u1e42",
    n = "\u01f9\u1e45\u1e47\u1e49\u1e4b", N = "\u01f8\u1e44\u1e46\u1e48\u1e4a",
    o = paste0("\u01a1\u01d2\u01eb\u01ed\u01ff\u020d\u020f\u022b\u022d\u022f\u0231",
               "\u1e4d\u1e4f\u1e51\u1e53\u1ecd\u1ecf\u1ed1\u1ed3\u1ed5\u1ed7\u1ed9\u1edb\u1edd\u1edf",
               "\u1ee1\u1ee3"),
    O = paste0("\u01a0\u01d1\u01ea\u01ec\u01fe\u020c\u020e\u022a\u022c\u022e\u0230",
               "\u1e4c\u1e4e\u1e50\u1e52\u1ecc\u1ece\u1ed0\u1ed2\u1ed4\u1ed6\u1ed8\u1eda\u1edc\u1ede",
               "\u1ee0\u1ee2"),
    p = "\u1e55\u1e57", P = "\u1e54\u1e56",
    r = "\u0211\u0213\u1e59\u1e5b\u1e5d\u1e5f", R = "\u0210\u0212\u1e58\u1e5a\u1e5c\u1e5e",
    s = "\u1e61\u1e63\u1e65\u1e67\u1e69\u017f", S = "\u1e60\u1e62\u1e64\u1e66\u1e68",
    t = "\u1e6b\u1e6d\u1e6f\u1e71\u1e97", T = "\u1e6a\u1e6c\u1e6e\u1e70",
    u = paste0("\u01b0\u01d4\u01d6\u01d8\u01da\u01dc\u0215\u0217\u1e73\u1e75\u1e77\u1e79",
               "\u1e7b\u1ee5\u1ee7\u1ee9\u1eeb\u1eed\u1eef\u1ef1"),
    U = paste0("\u01af\u01d3\u01d5\u01d7\u01d9\u01db\u0214\u0216\u1e72\u1e74\u1e76\u1e78",
               "\u1e7a\u1ee4\u1ee6\u1ee8\u1eea\u1eec\u1eee\u1ef0"),
    v = "\u1e7d\u1e7f", V = "\u1e7c\u1e7e",
    w = "\u1e81\u1e83\u1e85\u1e87\u1e89\u1e98", W = "\u1e80\u1e82\u1e84\u1e86\u1e88",
    x = "\u1e8b\u1e8d", X = "\u1e8a\u1e8c",
    y = "\u0233\u1e8f\u1e99\u1ef3\u1ef5\u1ef7\u1ef9", Y = "\u0232\u1e8e\u1ef2\u1ef4\u1ef6\u1ef8",
    z = "\u1e91\u1e93\u1e95", Z = "\u1e90\u1e92\u1e94")
  # Compatibility characters, which are one character spelled another way: a
  # superscript or subscript digit or letter, a full-width letter from a CJK
  # input method, a Roman numeral or circled digit from the same, the script
  # small l of "m\u2113", the ordinal indicators of "1\u00ba ano", the micro sign
  # (which NFKC makes the Greek letter). The iconv step folded most of these,
  # so "m\u00b2" and "m2" were one title, and so were "Phase \u2161" and "Phase II";
  # the table has to say so itself. (No "-" anywhere in these strings: chartr()
  # reads it as a range.)
  compat_from <- paste0("\u2070\u00b9\u00b2\u00b3\u2074\u2075\u2076\u2077\u2078\u2079",
                        "\u2080\u2081\u2082\u2083\u2084\u2085\u2086\u2087\u2088\u2089",
                        intToUtf8(c(0xFF10:0xFF19, 0xFF21:0xFF3A, 0xFF41:0xFF5A)), "\u00b5",
                        "\u2071\u207f\u2090\u2091\u2092\u2093\u2095\u2096\u2097\u2098\u2099",
                        "\u209a\u209b\u209c\u02b0\u02b2\u02b3\u02b7\u02b8\u02e1\u02e2\u02e3",
                        "\u2160\u2164\u2169\u216c\u216d\u216e\u216f",
                        "\u2170\u2174\u2179\u217c\u217d\u217e\u217f",
                        intToUtf8(c(0x24EA, 0x2460:0x2468, 0x24B6:0x24CF, 0x24D0:0x24E9)),
                        "\u2113\u210e\u210a\u212f\u2134\u212a\u212b\u00aa\u00ba")
  compat_to <- paste0("0123456789", "0123456789", "0123456789",
                      paste(LETTERS, collapse = ""), paste(letters, collapse = ""), "\u03bc",
                      "inaeoxhklmnpsthjrwylsx", "IVXLCDM", "ivxlcdm",
                      "0123456789",
                      paste(LETTERS, collapse = ""), paste(letters, collapse = ""),
                      "lhgeoKAao")
  roman <- c("II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII")
  out <- list(from = paste0(paste(one, collapse = ""), paste(ext, collapse = ""), compat_from),
       to = paste0(paste(rep(names(one), nchar(one)), collapse = ""),
                   paste(rep(names(ext), nchar(ext)), collapse = ""), compat_to),
       # Two vectors, not a named one: a name is a symbol, and a symbol is
       # translated to the native encoding, which in the C locale turned "\u00df"
       # into "<U+00DF>" and folded nothing. Ligatures come from PDF metadata
       # ("E\ufb03cacy"), and a vulgar fraction was "1/2" to the iconv step.
       multi_from = c("\u00df", "\u1e9e", "\u00e6", "\u00c6", "\u0153", "\u0152",
                      "\u00fe", "\u00de", "\u0133", "\u0132", "\u01fd", "\u01fc",
                      "\ufb00", "\ufb01", "\ufb02", "\ufb03", "\ufb04", "\ufb05", "\ufb06",
                      "\u00bc", "\u00bd", "\u00be", "\u2153", "\u2154", "\u2155", "\u215b",
                      "\u2150", "\u2151", "\u2152", "\u2156", "\u2157", "\u2158", "\u2159",
                      "\u215a", "\u215c", "\u215d", "\u215e", "\u2189", "\u215f",
                      intToUtf8(c(0x2161:0x2163, 0x2165:0x2168, 0x216A, 0x216B), multiple = TRUE),
                      intToUtf8(c(0x2171:0x2173, 0x2175:0x2178, 0x217A, 0x217B), multiple = TRUE),
                      intToUtf8(0x2469:0x2473, multiple = TRUE),
                      intToUtf8(0x2474:0x2487, multiple = TRUE),
                      intToUtf8(0x2488:0x249B, multiple = TRUE),
                      intToUtf8(0x249C:0x24B5, multiple = TRUE)),
       multi_to = c("ss", "SS", "ae", "AE", "oe", "OE", "th", "TH", "ij", "IJ", "ae", "AE",
                    "ff", "fi", "fl", "ffi", "ffl", "st", "st",
                    "1/4", "1/2", "3/4", "1/3", "2/3", "1/5", "1/8",
                    "1/7", "1/9", "1/10", "2/5", "3/5", "4/5", "1/6",
                    "5/6", "3/8", "5/8", "7/8", "0/3", "1/",
                    roman, tolower(roman), as.character(10:20),
                    sprintf("(%d)", 1:20), sprintf("%d.", 1:20), sprintf("(%s)", letters)))
  stopifnot(nchar(out$from) == nchar(out$to), length(out$multi_from) == length(out$multi_to),
            !anyDuplicated(strsplit(out$from, "")[[1]]))
  # One character class of them all, to find the strings that need the loop.
  out$multi_class <- paste0("[", paste(out$multi_from, collapse = ""), "]")
  out
})

#' Fold Latin diacritics to plain letters, leaving every other letter alone.
#'
#' Case is kept (route 4 of match_files() needs it). Combining marks are
#' dropped, so a decomposed "e" + U+0301 -- how macOS spells a filename --
#' folds the same way as the precomposed U+00E9.
#' @noRd
fold_latin <- function(x) {
  x <- mark_utf8(as.character(x))
  x <- chartr(.gr_latin_fold$from, .gr_latin_fold$to, x)
  # Only the strings that hold one of them go through the hundred replacements.
  hit <- grepl(.gr_latin_fold$multi_class, x, perl = TRUE)
  if (any(hit)) {
    y <- x[hit]
    for (k in seq_along(.gr_latin_fold$multi_from)) {
      y <- gsub(.gr_latin_fold$multi_from[k], .gr_latin_fold$multi_to[k], y, fixed = TRUE)
    }
    x[hit] <- y
  }
  gsub("\\p{M}+", "", x, perl = TRUE)
}

#' A title reduced to what two exports of one paper have in common.
#'
#' Case, punctuation, accents and the trailing full stop all differ between
#' databases for the same article. What survives is the letters and digits --
#' all of them, in any script: a letter with no ASCII spelling is still part of
#' the title, and deleting it made different studies one key.
#' @noRd
title_key <- function(x) {
  # lower_text(), not tolower(), which in a C locale on Linux lowers A-Z
  # alone: a Greek or Cyrillic title in capitals and the same title in lower
  # case were two works in CI and one on a laptop. Lower-cased again after
  # folding, for a capital neither table has that the fold turns into an ASCII
  # one.
  v <- lower_text(fold_latin(lower_text(mark_utf8(as.character(x)))))
  v <- gsub("[^\\p{L}\\p{N}]+", "", v, perl = TRUE)
  v[is.na(v) | !nzchar(v)] <- NA_character_
  v
}

#' Words that make an author an organisation rather than a person.
#'
#' This file's own list, not the citation code's: which records are one work
#' and which file is whose must not change when the rules for rendering a
#' citation do.
#' @noRd
.gr_rec_corporate <- paste0(
  "\\b(group|collaborat\\w*|consortium|investigators?|committee|organi[sz]ations?|",
  "associations?|institutes?|society|council|agency|department|ministry|foundation|",
  "universit(y|ies)|cent(re|er)s?|commission|federation|bureau|administration|network|",
  "academy|alliance|coalition|initiative|task ?force|working party|trialists|panel)\\b")

#' Particles that are part of a surname but not what identifies it.
#' @noRd
.gr_rec_particles <- c("van", "von", "der", "den", "de", "del", "della", "di", "da", "dos",
                       "das", "du", "la", "le", "ten", "ter", "bin", "ibn", "al", "el", "st",
                       "zu", "af", "av")

#' The first author of each record: surname, first initial, and whether it is
#' an organisation.
#'
#' Only the first author, read on its own. Reading the whole list and giving up
#' when any entry was doubtful -- which is right for a rendered citation --
#' lost the first author whenever a later one was a group ("Horby P; Lim WS;
#' RECOVERY Collaborative Group") or an acronym, and with it the author check
#' on duplicates and the author-year route to a file.
#'
#' The shapes: "Smith, J.", "van der Berg, P." and "VAN DAM, P" (surname before
#' the comma, whatever its case); "King, Jr., Robert" (BibTeX's suffix in the
#' middle); "Smith JA", "SMITH J" and "LE ROUX J" (Vancouver: surname, then
#' initials); "John Smith" (the last word); "WHO" (one word is the name); and an
#' organisation, kept whole.
#' @noRd
record_first_author <- function(authors) {
  a <- mark_utf8(as.character(authors))
  n <- length(a)
  out <- list(surname = rep(NA_character_, n), initial = rep(NA_character_, n),
              corporate = rep(FALSE, n), entry = rep(NA_character_, n))
  is_ini <- function(w) grepl("^(?:\\p{Lu}[.\\-]*){1,4}$", w, perl = TRUE)
  for (k in seq_len(n)) {
    e <- a[k]
    if (is.na(e)) next
    e <- trimws(gsub("[{}\"]", "", sub(";.*$", "", e)))
    e <- trimws(sub("[,[:space:]]*(et[[:space:]]+al\\.?|and others)[.]?$", "", e,
                    ignore.case = TRUE, perl = TRUE))
    # One author per slot is the norm; a single field holding the whole list
    # ("Smith, J., Okafor, A. and Lee, K.") gives up its first name here.
    e <- trimws(strsplit(e, "[[:space:]]*(?:\\band\\b|&)[[:space:]]*", perl = TRUE)[[1]][1])
    if (is.na(e) || !grepl("\\p{L}", e, perl = TRUE)) next
    out$entry[k] <- e
    if (!grepl(",", e, fixed = TRUE) && grepl("[[:space:]]", e) &&
        grepl(.gr_rec_corporate, e, ignore.case = TRUE, perl = TRUE)) {
      out$surname[k] <- e
      out$corporate[k] <- TRUE
      next
    }
    comma <- grepl(",", e, fixed = TRUE)
    head <- if (comma) trimws(sub(",.*$", "", e)) else e
    rest <- if (comma) trimws(sub("^[^,]*,", "", e)) else ""
    # BibTeX's three-part "King, Jr., Robert": the suffix is the middle part,
    # and its "J" is not the initial.
    rest <- sub("^(?:(?i:jr|sr)|II|III|IV|2nd|3rd|4th)\\.?[[:space:]]*(?:,|$)[[:space:]]*", "", rest,
                perl = TRUE)
    w <- strsplit(head, "[[:space:]]+")[[1]]
    # A suffix is not the surname ("Wallace RB 3rd"). Before a comma "JR" can
    # only be one; without a comma "SMITH JR" is Smith with the initials J R.
    sfx <- if (comma) "^(?:(?i:jr|sr)|II|III|IV|2nd|3rd|4th)\\.?$"
           else "^(?:Jr|Sr|II|III|IV|2nd|3rd|4th)\\.?$"
    w <- w[nzchar(w) & !grepl(sfx, w, perl = TRUE)]
    if (!length(w)) next
    ini <- is_ini(w)
    if (length(w) == 1L) {
      s <- w; g <- rest
    } else if (all(ini) && !comma) {
      # "LI WS", "KIM S", "LE ROUX J": all capitals and no comma, so every word
      # looks like initials. Vancouver writes the surname first and the
      # initials last: the last word, and any single letters before it. A
      # particle belongs to the word after it ("LE ROUX", not "ROUX"), and a
      # lone letter first is a given name ("J LI"). With a comma the part
      # before it is the whole surname, however short its words: "VAN DAM, P"
      # was read as surname "VAN", initial "D".
      bare <- lower_text(gsub("[^\\p{L}]", "", w, perl = TRUE))
      len <- nchar(bare)
      np <- 0L
      while (np < length(w) - 1L && bare[np + 1L] %in% .gr_rec_particles) np <- np + 1L
      # ...but "LE T" is the surname Le and the initial T.
      if (np && len[np + 1L] < 2L) np <- 0L
      m <- length(w) - 1L
      while (m > 1L && len[m] == 1L) m <- m - 1L
      m <- min(length(w), max(m, np + 1L))
      if (all(len[seq_len(m)] == 1L)) {
        s <- w[length(w)]; g <- paste(w[-length(w)], collapse = " ")
      } else {
        s <- paste(w[seq_len(m)], collapse = " "); g <- paste(w[-seq_len(m)], collapse = " ")
      }
    } else if (ini[length(w)] && !all(ini)) {
      last <- max(which(!ini))
      s <- paste(w[seq_len(last)], collapse = " ")
      g <- paste(w[-seq_len(last)], collapse = " ")
    } else if (comma) {
      s <- paste(w, collapse = " "); g <- rest
    } else {
      # The given name first: the surname is the last word, with the particles
      # in lower case before it ("Jan van Leeuwen", BibTeX's "von" part). A
      # capitalised one is a given name as often as not ("Bin Li", "Le Wang").
      f <- length(w)
      while (f > 1L && w[f - 1L] %in% .gr_rec_particles) f <- f - 1L
      s <- paste(w[f:length(w)], collapse = " "); g <- if (f > 1L) w[1] else ""
    }
    s <- gsub("^[^\\p{L}\\p{N}]+|[^\\p{L}\\p{N}]+$", "", s, perl = TRUE)
    if (!grepl("\\p{L}", s, perl = TRUE)) next
    out$surname[k] <- s
    g1 <- regmatches(g, regexpr("\\p{L}", g, perl = TRUE))
    if (length(g1)) out$initial[k] <- g1
  }
  # Folded once for the whole vector: the fold table is long, and chartr()
  # builds it afresh on every call.
  out$initial <- toupper(fold_latin(out$initial))
  out
}

#' A name reduced to the ways two exports can spell it.
#'
#' The folded key, and a looser one that also reads "ue" as "u", "oe" as "o",
#' "ae" as "a" and "aa" as "a" -- the German and Scandinavian transliterations,
#' so "M\u00fcller", "Mueller" and "Muller" are one name, and "S\u00f8rensen" and
#' "Soerensen".
#' @noRd
record_name_forms <- function(x) {
  lapply(title_key(x), function(k) {
    if (is.na(k)) character(0) else unique(c(k, gsub("aa", "a", gsub("([aou])e", "\\1", k))))
  })
}

#' The words of each name, less its particles, in both spellings.
#' @noRd
record_name_words <- function(x) {
  lapply(lower_text(fold_latin(x)), function(v) {
    if (is.na(v)) return(character(0))
    w <- strsplit(v, "[^\\p{L}\\p{N}]+", perl = TRUE)[[1]]
    w <- w[nchar(w) >= 2L]
    core <- w[!w %in% .gr_rec_particles]
    if (length(core)) w <- core
    unique(c(w, gsub("aa", "a", gsub("([aou])e", "\\1", w))))
  })
}

#' The significant words of each venue name, for record_venue_match().
#' @noRd
record_venue_words <- function(v) {
  v <- gsub("\\([^)]*\\)", " ", mark_utf8(as.character(v)))
  lapply(lower_text(fold_latin(v)), function(x) {
    if (is.na(x)) return(character(0))
    w <- strsplit(x, "[^\\p{L}\\p{N}]+", perl = TRUE)[[1]]
    w[nzchar(w) & !w %in% c("the", "of", "and", "for", "in", "on", "an", "de", "la", "le",
                            "der", "und", "des", "du", "et", "y", "e", "at", "to")]
  })
}

#' Whether two venue names, as record_venue_words() gives them, are one journal.
#'
#' `loose` is the test for records that have no authors to compare: one name
#' contained in the other, as before, or one an abbreviation of the other. The
#' strict test, for a merge the title key alone never made (see
#' dedupe_records()), drops containment -- "BMJ" is in "BMJ Open", and "Sleep"
#' in "Sleep Medicine", and neither is the same journal -- and keeps the same
#' spelling, a word-for-word abbreviation ("J Educ Psychol" of "Journal of
#' Educational Psychology"), or an acronym ("BMJ", "JAMA").
#'
#' Two spellings the databases use are read as what they are, not as a longer
#' name: an acronym written with its expansion ("JAMA - Journal of the American
#' Medical Association", "BMJ-British Medical Journal" in Web of Science and
#' Scopus) is that journal, and "of the United States of America" after the
#' PNAS title adds a country, not a journal. "BMJ Open" is neither.
#' @noRd
record_venue_match <- function(wa, wb, loose = TRUE) {
  if (!length(wa) || !length(wb)) return(NA)
  country <- function(w) {
    n <- length(w)
    for (tail in list(c("united", "states", "america"), c("u", "s", "a"), "usa")) {
      k <- length(tail)
      if (n - k >= 2L && identical(w[(n - k + 1L):n], tail)) return(w[seq_len(n - k)])
    }
    w
  }
  wa <- country(wa); wb <- country(wb)
  ka <- paste(wa, collapse = ""); kb <- paste(wb, collapse = "")
  if (identical(ka, kb)) return(TRUE)
  if (loose && (grepl(ka, kb, fixed = TRUE) || grepl(kb, ka, fixed = TRUE))) return(TRUE)
  # "educ" abbreviates "educational": same first letter, then its letters in order.
  abbrev <- function(s, l) {
    substr(s, 1, 1) == substr(l, 1, 1) &&
      grepl(paste0("^", paste(strsplit(s, "")[[1]], collapse = ".*")), l)
  }
  if (length(wa) == length(wb) &&
      all(mapply(function(x, y) abbrev(x, y) || abbrev(y, x), wa, wb))) return(TRUE)
  acronym <- function(s, l) length(s) == 1L && length(l) >= 2L &&
    identical(s, paste(substr(l, 1, 1), collapse = ""))
  if (acronym(wa, wb) || acronym(wb, wa)) return(TRUE)
  # An acronym first and the words it spells after it: the name is either.
  spelled <- function(w) length(w) >= 3L && acronym(w[1], w[-1])
  for (sw in list(list(wa, wb), list(wb, wa))) {
    a <- sw[[1]]; b <- sw[[2]]
    if (spelled(a) && !spelled(b)) {
      return(isTRUE(record_venue_match(a[1], b, loose)) || isTRUE(record_venue_match(a[-1], b, loose)))
    }
  }
  FALSE
}

#' Which rows repeat an earlier one.
#'
#' Returns the `record_id` of the first row a duplicate repeats, or NA. A DOI is
#' exact and is tried first; the title fallback exists because conference papers
#' and preprints are routinely indexed without one.
#' @noRd
dedupe_records <- function(recs, how) {
  n <- nrow(recs)
  out <- rep(NA_integer_, n)
  if (identical(how, "none") || n < 2L) return(out)
  # The first earlier row with the same key, or NA. match(), not an environment
  # keyed on the value: an environment's names are symbols, translated to the
  # native encoding, so in the C locale every non-Latin title warned.
  first_of <- function(key) {
    m <- match(key, key)
    m[is.na(key) | m == seq_along(key)] <- NA_integer_
    m
  }
  doi_hit <- first_of(recs$doi)
  by_title <- identical(how, "doi+title")
  key <- rep(NA_character_, n)
  if (by_title) {
    # A title key is built for EVERY row, DOI or not. Blanking it on rows with a
    # DOI -- meant to keep two different DOIs apart -- also meant a DOI-less
    # record (Scholar, a conference index, grey literature) could never match
    # the same paper exported from Scopus with its DOI, which is the commonest
    # duplicate there is. What keeps two DOIs apart is the check below.
    tk <- title_key(recs$title)
    # Short titles are not identities: "Reply", "Editorial", "Erratum" recur in
    # every journal every year. The same floor match_files() uses for a title.
    tk[!is.na(tk) & nchar(tk) < 12L] <- NA_character_
    key <- ifelse(is.na(tk) | is.na(recs$year), NA_character_, paste0(tk, "|", recs$year))
    # A title and year that rows with two different DOIs share is two papers
    # with one title -- which happens, and merging them would lose a study. A
    # DOI-less row with that title could be either, so it is merged with
    # neither rather than with whichever came first. Two DOI-less rows of it
    # can still be one another's copy, as they always could: blanking the key
    # for them too kept the same Scholar letter twice whenever two other
    # letters of that title had DOIs.
    ok <- !is.na(key) & !is.na(recs$doi)
    kid <- match(key, key)
    multi_doi <- rep(FALSE, n)
    if (any(ok)) {
      n_doi <- vapply(split(recs$doi[ok], kid[ok]), function(d) length(unique(d)), integer(1))
      multi_doi <- !is.na(key) & kid %in% as.integer(names(n_doi)[n_doi > 1L])
    }
    # A title and year is not enough on its own either: two letters titled
    # "Response to the commentary on ..." in one year are not one letter. The
    # first author's surname has to agree as a whole name -- "Smith, J." and
    # "Smith JA" are one person, "Li" and "Lin" are not -- or, when a record has
    # no authors, the venue.
    fa <- record_first_author(recs$authors)
    forms <- record_name_forms(fa$surname)
    words <- record_name_words(fa$surname)
    entry_words <- record_name_words(fa$entry)
    all_key <- title_key(recs$authors)
    all_words <- record_name_words(recs$authors)
    # Merges the old title key could never make are held to more: a DOI-less
    # record with one that has a DOI (it used to blank the key of any row with
    # a DOI), and a title with fewer than 12 Latin letters or digits (its key
    # was the digits and nothing else, so a Chinese title could never match).
    # Identical generic titles are common in both, and there a surname alone is
    # thin: "Wang, L." and "Wang, H." wrote different papers, and so did two
    # authors of one name in two journals.
    latin <- !is.na(tk) & nchar(gsub("[^a-z0-9]", "", tk)) >= 12L
    # "Organisation" and "Organization", "Centre" and "Center": one name.
    corp_key <- vapply(forms, function(f) if (length(f)) f[1] else NA_character_, character(1))
    corp_key <- gsub("tre", "ter", gsub("z", "s", corp_key, fixed = TRUE), fixed = TRUE)
    # An author that is one word in capitals may be an organisation's acronym.
    acro <- ifelse(!fa$corporate & grepl("^(?:\\p{Lu}\\.?){2,8}$", fa$entry, perl = TRUE),
                   lower_text(fold_latin(gsub("[^\\p{L}]", "", fa$entry, perl = TRUE))), NA_character_)
    # "WHO" is the World Health Organization, "CDC" the Centers for Disease
    # Control and Prevention and "NICE" the National Institute for Health and
    # Care Excellence: the acronym's letters are the initials of the name's
    # words, in order, from the first, with at most two words left out. The
    # whole name, "and" included, as the export wrote it.
    first_full <- mark_utf8(trimws(sub(";.*$", "", recs$authors)))
    acronym_of <- function(p, g) {
      a <- acro[p]
      if (is.na(a) || is.na(first_full[g])) return(FALSE)
      w <- strsplit(lower_text(fold_latin(first_full[g])), "[^\\p{L}]+", perl = TRUE)[[1]]
      w <- w[nchar(w) > 1L & !w %in% c("of", "for", "and", "the", "on", "in", "to", "at", "de",
                                       "la", "du", "des", "et", "y")]
      ini <- paste(substr(w, 1, 1), collapse = "")
      nchar(ini) >= nchar(a) && nchar(ini) - nchar(a) <= 2L &&
        substr(a, 1, 1) == substr(ini, 1, 1) &&
        grepl(paste0("^", paste(strsplit(a, "")[[1]], collapse = ".*")), ini)
    }
    raw_words <- lapply(lower_text(fold_latin(fa$entry)), function(v) {
      if (is.na(v)) character(0) else strsplit(v, "[^\\p{L}\\p{N}]+", perl = TRUE)[[1]]
    })
    ini_lc <- lower_text(fa$initial)
    # Row i's surname is a given name in row j's entry, and row i's initial is
    # the first letter of another word there: "Li, W." read against "Li Wei".
    # "Li, W." against "Zhang, Li" fails the second half, as W is not Zhang.
    swapped <- function(i, j) {
      if (is.na(ini_lc[i]) || !any(words[[i]] %in% entry_words[[j]])) return(FALSE)
      other <- raw_words[[j]][nzchar(raw_words[[j]]) & !raw_words[[j]] %in% words[[i]]]
      ini_lc[i] %in% substr(other, 1, 1)
    }
    authors_agree <- function(i, j) {
      if (is.na(fa$surname[i]) || is.na(fa$surname[j])) return(NA)
      if (fa$corporate[i] || fa$corporate[j]) {
        if (fa$corporate[i] && fa$corporate[j]) {
          a <- corp_key[i]; b <- corp_key[j]
          return(if (grepl(a, b, fixed = TRUE) || grepl(b, a, fixed = TRUE)) "yes" else "no")
        }
        # A group first in one export and a person first in the other is one
        # work when either names the other somewhere in its author list, or
        # the person is the group's acronym.
        g <- if (fa$corporate[i]) i else j
        p <- if (fa$corporate[i]) j else i
        hit <- (!is.na(all_key[p]) && grepl(forms[[g]][1], all_key[p], fixed = TRUE)) ||
          any(words[[p]] %in% all_words[[g]]) || acronym_of(p, g)
        return(if (hit) "yes" else "no")
      }
      if (any(forms[[i]] %in% forms[[j]]) || any(words[[i]] %in% words[[j]])) {
        # Two initials that differ are two people of one surname, whatever the
        # title: "Wang, L." and "Wang, H." each wrote a "Letter to the editor".
        if (!is.na(fa$initial[i]) && !is.na(fa$initial[j]) &&
            fa$initial[i] != fa$initial[j]) return("no")
        return("yes")
      }
      # "Li Wei" in one export and "Li, W." in the other: a given name first.
      # Only when each reading bears the other out.
      if (swapped(i, j) || swapped(j, i)) return("order")
      "no"
    }
    venue_words <- record_venue_words(recs$venue)
    same_work <- function(i, j, strict) {
      a <- authors_agree(i, j)
      if (identical(a, "no")) return(FALSE)
      # Name order is a reading, not a match: it never joins a record to one
      # with a DOI (the DOI, and its file, would go to the other paper), and
      # it needs the venues not to disagree.
      if (strict && identical(a, "order")) return(FALSE)
      v <- record_venue_match(venue_words[[i]], venue_words[[j]], loose = !strict)
      if (!strict) return(identical(a, "yes") || !isFALSE(v))
      # Nothing may contradict it, and something beyond the title must confirm it.
      !isFALSE(v) && (identical(a, "yes") || isTRUE(v))
    }
  }
  # `root` is the kept row each row belongs to. Every row is resolved to a KEPT
  # row as it is reached, so `duplicate_of` never points at another duplicate.
  root <- seq_len(n)
  has_doi <- !is.na(recs$doi)
  group_doi <- has_doi
  kid <- match(key, key)
  holders <- vector("list", n)
  for (i in seq_len(n)) {
    if (!is.na(doi_hit[i])) {
      root[i] <- root[doi_hit[i]]
    } else if (by_title && !is.na(key[i])) {
      h <- holders[[kid[i]]]
      if (length(h)) {
        # Every row of a work that carries this title has to agree, not just
        # one: a group holding Smith's record and an authorless one is still
        # Smith's paper, and Jones's letter in the same journal is not it.
        gs <- unique(root[h])
        fits <- vapply(gs, function(g) {
          # A DOI of its own and one in the group are two DOIs (the same one
          # would have matched above).
          if (has_doi[i] && group_doi[g]) return(FALSE)
          if (multi_doi[i] && (has_doi[i] || group_doi[g])) return(FALSE)
          strict <- has_doi[i] || group_doi[g] || !latin[i]
          all(vapply(h[root[h] == g], function(j) same_work(i, j, strict), logical(1)))
        }, logical(1))
        # Two different works it could equally be is no match at all.
        if (sum(fits) == 1L) root[i] <- gs[fits]
      }
    }
    group_doi[root[i]] <- group_doi[root[i]] || has_doi[i]
    if (by_title && !is.na(key[i])) holders[[kid[i]]] <- c(holders[[kid[i]]], i)
  }
  dup <- root != seq_len(n)
  out[dup] <- recs$record_id[root[dup]]
  out
}

#' Fill the kept row's empty fields from the rows it absorbed.
#'
#' The kept row is the one that came first, which is often the export with the
#' least in it: "scholar.bib" sorts before "scopus.ris", and Scholar gives no
#' DOI. Its duplicate had the DOI and the journal, the file was found through
#' that DOI, and then the extraction table and every citation built from it
#' said DOI NA and venue NA -- the document identified by a DOI the record set
#' then denied it had. Only empty fields are filled, in record order; where the
#' search came from (database, accession, source file) and the file path stay
#' each row's own.
#' @noRd
merge_duplicate_fields <- function(recs) {
  dup <- recs$duplicate_of
  if (is.null(dup) || all(is.na(dup))) return(recs)
  fill <- c("type", "authors", "year", "title", "venue", "volume", "issue", "pages", "doi",
            "abstract", "keywords")
  kept <- match(dup, recs$record_id)
  for (f in fill) {
    v <- recs[[f]]
    src <- which(!is.na(kept) & !is.na(v))       # duplicates that have it, in record order
    src <- src[!duplicated(kept[src])]            # the first of them for each kept row
    gap <- is.na(v[kept[src]])
    v[kept[src][gap]] <- v[src[gap]]
    recs[[f]] <- v
  }
  recs
}
