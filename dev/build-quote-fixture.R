# build-quote-fixture.R: write the labelled quotation set that
# tests/testthat/test-verify-match.R and dev/quote-matcher-rates.R read.
#
# Run from the repository root:
#
#   Rscript dev/build-quote-fixture.R
#
# The set is built from two documents: the bundled example
# (inst/extdata/annual_report.md) and a trial report kept beside the fixture
# (tests/testthat/fixtures/quotes/trial_report.txt). Each document is also
# written in three damaged copies, the way a text layer or OCR leaves a
# document when the cleaners do not repair it:
#
#   *_hyphen.txt    wrapped at 60 characters, long words broken with a hyphen
#   *_ligature.txt  ff, fi, fl, ffi and ffl as single ligature characters
#   *_ocr.txt       both of those, a no-break space before "percent", and
#                   letter confusions ("m" read as "rn", "l" read as "I")
#                   inside words; digits are never touched
#
# labelled.csv has one row per quotation: `id`, `source` (a file in the
# fixture directory), `variant`, `label` (TRUE for a true quotation of the
# source, FALSE for one that says something the source does not) and
# `quote`. True quotations are whole sentences and clauses quoted cleanly
# against the clean, hyphenated, ligature and OCR copies, sentences with
# typographic changes a model makes (curly quotes around it, a line break,
# JSON escapes), and sentences quoted with ligatures against the clean copy.
# False ones change a number written in digits or in words, change the
# comparison sign before a number ("p = 0.003" to "p < 0.003"), add or drop a
# negation, swap a content word, or are invented. The output depends on nothing but the two documents, so a
# rerun writes the same files.

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/build-quote-fixture.R", call. = FALSE)
}

out_dir <- file.path("tests", "testthat", "fixtures", "quotes")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

read_doc <- function(path) {
  x <- readLines(path, encoding = "UTF-8", warn = FALSE)
  paste(x, collapse = "\n")
}

docs <- list(
  annual_report = read_doc(file.path("inst", "extdata", "annual_report.md")),
  trial_report = read_doc(file.path(out_dir, "trial_report.txt"))
)

paragraphs <- function(doc) {
  p <- strsplit(doc, "\n[ \t]*\n")[[1]]
  p <- gsub("[[:space:]]+", " ", trimws(p))
  p[nzchar(p)]
}

sentences <- function(doc) {
  p <- paragraphs(doc)
  # Headings, page markers, captions and references are not prose to quote.
  p <- p[lengths(strsplit(p, " ")) >= 8L & !grepl("^(#|\\[|Figure|Table)", p)]
  s <- unlist(strsplit(p, "(?<=[.])\\s+(?=[A-Z])", perl = TRUE))
  s[lengths(strsplit(s, " ")) >= 6L]
}

# Wrap each paragraph at `width`, breaking a word of seven letters or more
# that crosses the margin with a hyphen at its middle.
hyphenate <- function(doc, width = 60L) {
  wrap_one <- function(p) {
    words <- strsplit(p, " ")[[1]]
    lines <- character(0)
    line <- ""
    for (w in words) {
      cand <- if (nzchar(line)) paste(line, w) else w
      if (nchar(cand) <= width) { line <- cand; next }
      if (grepl("^[A-Za-z]{7,}$", w)) {
        cut <- nchar(w) %/% 2L
        lines <- c(lines, paste0(if (nzchar(line)) paste0(line, " ") else "",
                                 substr(w, 1L, cut), "-"))
        line <- substr(w, cut + 1L, nchar(w))
      } else {
        lines <- c(lines, line)
        line <- w
      }
    }
    paste(c(lines, line), collapse = "\n")
  }
  paste(vapply(paragraphs(doc), wrap_one, ""), collapse = "\n\n")
}

ligate <- function(doc) {
  from <- c("ffi", "ffl", "ff", "fi", "fl")
  to <- c("ﬃ", "ﬄ", "ﬀ", "ﬁ", "ﬂ")
  for (i in seq_along(from)) doc <- gsub(from[i], to[i], doc, fixed = TRUE)
  doc
}

# Every `every`-th match of `pattern` replaced, counting from the first.
every_nth <- function(doc, pattern, replacement, every) {
  m <- gregexpr(pattern, doc, perl = TRUE)[[1]]
  if (m[1L] < 0L) return(doc)
  pick <- seq(1L, length(m), by = every)
  hit <- m[pick]
  len <- attr(m, "match.length")[pick]
  for (k in rev(seq_along(hit))) {
    doc <- paste0(substr(doc, 1L, hit[k] - 1L), replacement,
                  substr(doc, hit[k] + len[k], nchar(doc)))
  }
  doc
}

ocr <- function(doc) {
  doc <- hyphenate(doc)
  doc <- every_nth(doc, "(?<=[a-z])m(?=[a-z])", "rn", 4L)
  doc <- every_nth(doc, "(?<=[a-z])l(?=[a-z])", "I", 5L)
  doc <- gsub(" percent", " percent", doc, fixed = TRUE)
  ligate(doc)
}

write_doc <- function(text, name) {
  con <- file(file.path(out_dir, name), open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(text, "\n"))), con)
}

clause <- function(s) {
  w <- strsplit(s, " ")[[1]]
  paste(w[seq_len(max(5L, ceiling(length(w) * 0.6)))], collapse = " ")
}

typographic <- function(s, i) {
  w <- strsplit(s, " ")[[1]]
  mid <- length(w) %/% 2L
  if (i %% 2L) {
    paste0("“", paste(w[seq_len(mid)], collapse = "  "), "\n",
           paste(w[-seq_len(mid)], collapse = " "), "”")
  } else {
    # Escaped twice, as a reply that was serialised again arrives.
    paste0("\\\"", paste(w[seq_len(mid)], collapse = " "), "\\n",
           paste(w[-seq_len(mid)], collapse = " "), "\\\"")
  }
}

# The first number of `s` (or, with `which = "last"`, the last when there are
# two or more) with its final digit moved on by three.
change_number <- function(s, which = c("first", "last")) {
  which <- match.arg(which)
  m <- gregexpr("[0-9]+(\\.[0-9]+)?", s)[[1]]
  if (m[1L] < 0L) return(NA_character_)
  if (which == "last" && length(m) < 2L) return(NA_character_)
  k <- if (which == "first") 1L else length(m)
  at <- m[k]
  len <- attr(m, "match.length")[k]
  num <- substr(s, at, at + len - 1L)
  last <- as.integer(substr(num, len, len))
  num <- paste0(substr(num, 1L, len - 1L), (last + 3L) %% 10L)
  paste0(substr(s, 1L, at - 1L), num, substr(s, at + len, nchar(s)))
}

# The first number of `s` written as a word, as the next one ("twelve" to
# "thirteen", "Two" to "Three").
.number_words <- c("zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
                   "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
                   "sixteen", "seventeen", "eighteen", "nineteen", "twenty")
change_number_word <- function(s) {
  pat <- paste0("\\b(", paste(.number_words, collapse = "|"), ")\\b")
  m <- regexpr(pat, s, ignore.case = TRUE, perl = TRUE)
  if (m < 0L) return(NA_character_)
  word <- regmatches(s, m)
  k <- match(tolower(word), .number_words)
  to <- .number_words[k %% length(.number_words) + 1L]
  if (grepl("^[A-Z]", word)) to <- paste0(toupper(substr(to, 1L, 1L)), substr(to, 2L, nchar(to)))
  regmatches(s, m) <- to
  s
}

# The first comparison sign before a number in `s` (or the last, when there
# are two or more) turned round or made strict: "=" to "<", "<" to ">", ">"
# to "<", and the two signs with a bar swapped for each other.
change_comparison <- function(s, which = c("first", "last")) {
  which <- match.arg(which)
  ge <- "\u2265"
  le <- "\u2264"
  m <- gregexpr(paste0("(<=|>=|[<>=", ge, le, "])(?=\\s?[0-9])"), s, perl = TRUE)[[1]]
  if (m[1L] < 0L) return(NA_character_)
  if (which == "last" && length(m) < 2L) return(NA_character_)
  k <- if (which == "first") 1L else length(m)
  m <- structure(m[k], match.length = attr(m, "match.length")[k])
  sign <- regmatches(s, m)
  to <- switch(sign, "=" = "<", "<" = ">", ">" = "<", "<=" = ">=", ">=" = "<=")
  if (is.null(to)) to <- if (sign == ge) le else ge
  regmatches(s, m) <- to
  s
}

flip_negation <- function(s) {
  if (grepl("\\bnot ", s)) return(sub("\\bnot ", "", s))
  if (grepl("\\bno ", s)) return(sub("\\bno ", "", s))
  aux <- "\\b(was|were|is|are|did|does|has|had|will|would|can)\\b"
  if (grepl(aux, s)) return(sub(aux, "\\1 not", s))
  NA_character_
}

swap_word <- function(s, donor) {
  w <- strsplit(s, " ")[[1]]
  long <- which(grepl("^[a-z]{7,}$", w))
  pool <- unique(regmatches(donor, gregexpr("\\b[a-z]{7,}\\b", donor))[[1]])
  if (!length(long) || !length(pool)) return(NA_character_)
  at <- long[ceiling(length(long) / 2)]
  pool <- setdiff(pool, w[at])
  if (!length(pool)) return(NA_character_)
  w[at] <- pool[1L]
  paste(w, collapse = " ")
}

invented <- list(
  annual_report = c(
    "Northwind Instruments opened a third plant in Lyon during the fourth quarter of 2024.",
    "The board approved a share buyback of 15 million dollars to be completed in 2025.",
    "Headcount across the group fell by 9 percent after the restructuring programme.",
    "The Sheffield plant was closed for six weeks while the coolant system was rebuilt.",
    "Management expects gross margin to reach 48 percent by the end of 2026.",
    "Research and development spending rose to 3.8 million dollars in fiscal 2024.",
    "The company hedges all currency exposure for a rolling period of 36 months.",
    "A new distribution agreement in Brazil contributed 2.2 million dollars of revenue."
  ),
  trial_report = c(
    "Children aged 6 to 11 years were enrolled at two additional sites in Canada.",
    "The primary outcome was the time to first hospital admission for any cause.",
    "Two participants in the placebo group died from respiratory failure during follow-up.",
    "Adherence fell below 70 percent in the active group after the sixth month.",
    "The drug was compared directly with daily budesonide in a secondary analysis.",
    "Quality of life improved by 1.4 points on the Asthma Quality of Life Questionnaire.",
    "The sponsor designed the trial and wrote the first draft of the manuscript.",
    "Weight gain of more than 3 kilograms was recorded in 14 percent of participants."
  )
)

rows <- list()
add <- function(source, variant, label, quote) {
  if (is.na(quote)) return(invisible())
  rows[[length(rows) + 1L]] <<- data.frame(source = source, variant = variant, label = label,
                                           quote = quote, stringsAsFactors = FALSE)
}

for (name in names(docs)) {
  doc <- docs[[name]]
  clean_file <- paste0(name, ".txt")
  if (name != "trial_report") write_doc(doc, clean_file)
  write_doc(hyphenate(doc), paste0(name, "_hyphen.txt"))
  write_doc(ligate(doc), paste0(name, "_ligature.txt"))
  write_doc(ocr(doc), paste0(name, "_ocr.txt"))
  s <- sentences(doc)
  for (i in seq_along(s)) {
    add(clean_file, "exact", TRUE, s[i])
    add(clean_file, "clause", TRUE, clause(s[i]))
    add(clean_file, "typographic", TRUE, typographic(s[i], i))
    add(clean_file, "ligature_in_quote", TRUE, ligate(s[i]))
    add(paste0(name, "_hyphen.txt"), "hyphenation", TRUE, s[i])
    add(paste0(name, "_ligature.txt"), "ligature", TRUE, s[i])
    add(paste0(name, "_ocr.txt"), "ocr", TRUE, s[i])
    add(clean_file, "number_changed", FALSE, change_number(s[i]))
    add(clean_file, "number_changed", FALSE, change_number(s[i], "last"))
    add(clean_file, "number_word_changed", FALSE, change_number_word(s[i]))
    add(clean_file, "comparison_changed", FALSE, change_comparison(s[i]))
    add(clean_file, "comparison_changed", FALSE, change_comparison(s[i], "last"))
    add(clean_file, "negation_flipped", FALSE, flip_negation(s[i]))
    add(clean_file, "word_swapped", FALSE, swap_word(s[i], s[(i %% length(s)) + 1L]))
  }
  for (q in invented[[name]]) add(clean_file, "invented", FALSE, q)
}

tab <- do.call(rbind, rows)
tab <- cbind(id = seq_len(nrow(tab)), tab)
utils::write.csv(tab, file.path(out_dir, "labelled.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("%d quotations (%d true, %d false) written to %s\n", nrow(tab), sum(tab$label),
            sum(!tab$label), file.path(out_dir, "labelled.csv")))
print(table(tab$variant, tab$label))
