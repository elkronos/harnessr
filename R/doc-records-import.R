# doc-records-import.R -- the search, as the reference manager exported it.
#
# WHY THIS FILE EXISTS
# Everything else in this package starts from a folder of documents, which is
# already past the step that decides whether a review can be reproduced. A
# folder cannot say which databases were searched, with what query, on what
# date, how many records came back, or which of them were never obtained. Those
# are PRISMA items 6, 7 and 16, and no amount of care downstream substitutes for
# them: a review that cannot state its search is not a systematic review however
# good its extraction is.
#
# A reference-manager export says all of it, and is the file every researcher
# already has. Reading it also fixes something subtler. `gr_synthesise()` cites
# by author and year, and until now those came from asking a model to read a
# title page -- so the one part of a citation that must be exactly right was the
# part with the loosest guarantee. From an export they are data. The model is
# never shown them and never asserts them; they are joined on afterwards.
#
# WHY NOT synthesisr OR revtools
# Both are good and both are heavier than this needs to be. RIS is one tag per
# line and BibTeX is braces; the parsing is not the hard part. The hard part is
# the dialect drift between what Scopus, Web of Science, PubMed, Scholar and
# EndNote each call the same field, and a dependency does not remove that -- it
# just moves it somewhere this package cannot see. Everything here is base R.

#' RIS tags, mapped to the fields this package uses.
#'
#' A record type may use several tags for one idea and databases disagree about
#' which. Order matters: the first tag present wins, so the more specific tag is
#' listed first.
#' @noRd
.gr_ris_map <- list(
  type     = "TY",
  authors  = c("AU", "A1", "A2", "A3", "A4"),
  # DP is the drift this map exists for: it is "database provider" in the RIS
  # specification and "date of publication" in what PubMed exports. Listed last
  # among the year aliases, so a file carrying a real PY is unaffected, and the
  # four-digit rule below rejects it if it really was a provider name.
  year     = c("PY", "Y1", "DA", "DP"),
  title    = c("TI", "T1", "BT"),
  # T2 is the journal for an article and the book for a chapter; JO/JF/JA are
  # what the older exporters use, and Scopus emits both.
  venue    = c("JO", "JF", "JA", "T2", "T3", "SO"),
  volume   = "VL",
  issue    = c("IS", "CP"),
  pages    = c("SP", "BP"),
  doi      = c("DO", "DI"),
  abstract = c("AB", "N2"),
  keywords = "KW",
  url      = c("UR", "L1", "L2"),
  # Where the PDF is, when the manager wrote one out. EndNote and Zotero both
  # use L1; Mendeley uses a "file" tag in BibTeX.
  file     = c("L1", "LK"),
  database = "DB",
  accession = c("AN", "ID")
)

#' BibTeX fields, likewise.
#' @noRd
.gr_bib_map <- list(
  authors  = "author",
  year     = c("year", "date"),
  title    = "title",
  venue    = c("journal", "booktitle", "journaltitle", "publisher"),
  volume   = "volume",
  issue    = c("number", "issue"),
  pages    = "pages",
  doi      = "doi",
  abstract = "abstract",
  keywords = c("keywords", "keyword"),
  url      = "url",
  file     = "file",
  database = c("database", "source")
)

#' The columns every record set has, whatever it was read from.
#' @noRd
.gr_record_cols <- c("record_id", "type", "authors", "year", "title", "venue",
                     "volume", "issue", "pages", "doi", "abstract", "keywords",
                     "url", "file", "database", "accession", "source_file")

#' @noRd
empty_records <- function() {
  out <- as.data.frame(stats::setNames(
    replicate(length(.gr_record_cols), character(0), simplify = FALSE), .gr_record_cols),
    stringsAsFactors = FALSE)
  out$record_id <- integer(0)
  out
}

#' The tags the RIS specification defines.
#' @noRd
.gr_ris_tags <- c(
  "TY", "ER", "A1", "A2", "A3", "A4", "AB", "AD", "AN", "AU", "AV", "BT", "C1", "C2", "C3",
  "C4", "C5", "C6", "C7", "C8", "CA", "CN", "CP", "CT", "CY", "DA", "DB", "DI", "DO", "DP",
  "ED", "EP", "ET", "ID", "IS", "J1", "J2", "JA", "JF", "JO", "KW", "L1", "L2", "L3", "L4",
  "LA", "LB", "LK", "M1", "M2", "M3", "N1", "N2", "NV", "OP", "PB", "PP", "PY", "RI", "RN",
  "RP", "SE", "SN", "SO", "SP", "ST", "T1", "T2", "T3", "TA", "TI", "TT", "U1", "U2", "U3",
  "U4", "U5", "UR", "VL", "VO", "Y1", "Y2")

#' The tag of each RIS line, and its value; NA for a line that is not a tag.
#'
#' A tag line is "AU  - Smith, J.": exactly two characters, two spaces and a
#' hyphen. The pattern this replaced took zero to two spaces and tags of up to
#' four characters, so a wrapped abstract line was read as a tag: "ER-positive
#' tumours ..." ended the record there, and the year and DOI after it were
#' lost, and "HER2-negative disease ..." was cut out of the abstract as a tag of
#' its own. One space before the hyphen is still read, but only for a tag the
#' RIS specification defines and only with a space or nothing after the
#' hyphen, which is not how a wrapped sentence looks. And an `ER` with nothing
#' after it ends a record however it is spaced.
#' @noRd
ris_tags <- function(lines) {
  std <- grepl("^[A-Z][A-Z0-9]  -", lines)
  known <- unique(c(.gr_ris_tags, unlist(.gr_ris_map, use.names = FALSE)))
  one <- !std & grepl(sprintf("^(?:%s) -(?: |$)", paste(known, collapse = "|")), lines, perl = TRUE)
  end <- !std & !one & grepl("^ER {0,2}-[[:space:]]*$", lines)
  tag <- rep(NA_character_, length(lines))
  val <- rep(NA_character_, length(lines))
  hit <- std | one | end
  tag[hit] <- substr(lines[hit], 1L, 2L)
  val[std] <- trimws(substring(lines[std], 6L))
  val[one] <- trimws(substring(lines[one], 5L))
  val[end] <- ""
  list(tag = tag, val = val)
}

#' Split a RIS file into records.
#'
#' A record starts at `TY  -` and ends at `ER  -`. Both are required by the
#' format and both are routinely mangled: some exporters omit the trailing `ER`
#' on the last record, and Scholar writes `TY  - ` with no type. Splitting on
#' `ER` and tolerating a missing final one is what survives real files.
#' @noRd
ris_records <- function(lines) {
  # A continuation line has no tag and belongs to the tag above. See ris_tags()
  # for what counts as a tag.
  rt <- ris_tags(lines)
  ends <- which(rt$tag %in% "ER")
  starts <- which(rt$tag %in% "TY")
  if (!length(starts)) return(list())
  # Pair each start with the first end after it; a start with no end runs to the
  # next start, or to the end of the file.
  out <- vector("list", length(starts))
  for (i in seq_along(starts)) {
    s <- starts[i]
    nxt <- if (i < length(starts)) starts[i + 1L] - 1L else length(lines)
    e <- ends[ends > s]
    stop_at <- if (length(e)) min(e[1] - 1L, nxt) else nxt
    tags <- list(); last <- NULL
    for (k in s:max(s, stop_at)) {
      if (!is.na(rt$tag[k])) {
        last <- rt$tag[k]
        tags[[last]] <- c(tags[[last]], rt$val[k])
      } else if (!is.null(last) && nzchar(trimws(lines[k]))) {
        # A wrapped abstract. Append to the tag it continues rather than
        # dropping it, which is how half an abstract goes missing.
        n <- length(tags[[last]])
        tags[[last]][n] <- paste(tags[[last]][n], trimws(lines[k]))
      }
    }
    out[[i]] <- tags
  }
  out
}

#' Pull one field out of a tag list, following the alias order.
#' @noRd
tag_value <- function(tags, aliases, collapse = "; ") {
  for (a in aliases) {
    v <- tags[[a]]
    v <- v[nzchar(trimws(as.character(v)))]
    if (length(v)) return(paste(trimws(v), collapse = collapse))
  }
  NA_character_
}

#' @noRd
records_from_ris <- function(lines, source_file) {
  recs <- ris_records(lines)
  if (!length(recs)) return(empty_records())
  rows <- lapply(recs, function(tags) {
    vals <- lapply(names(.gr_ris_map), function(f) tag_value(tags, .gr_ris_map[[f]]))
    names(vals) <- names(.gr_ris_map)
    as.data.frame(c(vals, list(source_file = source_file)), stringsAsFactors = FALSE)
  })
  finish_records(do.call(rbind, rows))
}

#' MEDLINE tags (PubMed's own format), mapped as .gr_ris_map maps RIS.
#'
#' Authors and the DOI are not here: they need more than the first tag present
#' (see records_from_medline()).
#' @noRd
.gr_medline_map <- list(
  type     = "PT",
  year     = c("DP", "DEP"),
  title    = c("TI", "BTI"),
  venue    = c("JT", "TA"),
  volume   = "VI",
  issue    = "IP",
  pages    = "PG",
  abstract = "AB",
  keywords = c("OT", "MH"),
  accession = "PMID"
)

#' Split a PubMed file (.nbib, "PubMed" format in PubMed's Save menu) into
#' records.
#'
#' This is what PubMed's "Send to: Citation manager" writes, and it is not RIS:
#' a record starts at `PMID- `, tags are padded to four characters ("FAU - ",
#' "LID - "), and a long value continues on lines indented by six spaces. Read
#' as RIS it had no `TY` and gave no records, so the most searched database in
#' health reviews dropped out of "records identified" behind a warning that
#' blamed the file.
#' @noRd
medline_records <- function(lines) {
  tagged <- grepl("^[A-Z](?:[A-Z0-9]{3}|[A-Z0-9]{2} |[A-Z0-9]  )-(?: |$)", lines, perl = TRUE)
  tag <- ifelse(tagged, trimws(substr(lines, 1L, 4L)), NA_character_)
  val <- ifelse(tagged, trimws(substring(lines, 6L)), NA_character_)
  starts <- which(tag %in% "PMID")
  if (!length(starts)) return(list())
  ends <- c(starts[-1L] - 1L, length(lines))
  lapply(seq_along(starts), function(i) {
    tg <- character(0); vl <- character(0)
    for (k in starts[i]:ends[i]) {
      if (!is.na(tag[k])) {
        tg <- c(tg, tag[k]); vl <- c(vl, val[k])
      } else if (length(tg) && grepl("^[[:space:]]", lines[k]) && nzchar(trimws(lines[k]))) {
        # A continuation, which PubMed indents. An unindented line that is not
        # a tag is not part of any field.
        vl[length(vl)] <- paste(vl[length(vl)], trimws(lines[k]))
      }
    }
    list(tag = tg, val = vl)
  })
}

#' @noRd
records_from_medline <- function(lines, source_file) {
  recs <- medline_records(lines)
  if (!length(recs)) return(empty_records())
  rows <- lapply(recs, function(r) {
    tags <- split(r$val, factor(r$tag, levels = unique(r$tag)))
    vals <- lapply(names(.gr_medline_map), function(f) tag_value(tags, .gr_medline_map[[f]]))
    names(vals) <- names(.gr_medline_map)
    # Authors in the order they are listed: the full names (FAU) where the
    # record has them, else the short ones (AU), with a group author (CN) where
    # it stands in the list.
    au <- if ("FAU" %in% r$tag) c("FAU", "CN") else c("AU", "CN")
    who <- trimws(r$val[r$tag %in% au])
    vals$authors <- if (length(who[nzchar(who)])) paste(who[nzchar(who)], collapse = "; ") else NA_character_
    # "LID - 10.1000/xyz [doi]" and "AID - S0140-6736(20)30183-5 [pii]": the
    # DOI is the identifier marked as one.
    ids <- trimws(r$val[r$tag %in% c("LID", "AID")])
    doi <- sub("[[:space:]]*\\[doi\\]$", "", ids[grepl("\\[doi\\]$", ids)])
    vals$doi <- if (length(doi)) doi[1] else NA_character_
    as.data.frame(c(vals, list(source_file = source_file)), stringsAsFactors = FALSE)
  })
  finish_records(do.call(rbind, rows))
}

#' `@string`, `@preamble` and `@comment` are not records. They match the same
#' `@word{` opener, and each one became a row with all seventeen fields NA --
#' which dedupe_records() cannot collapse, because an NA key matches nothing,
#' and nothing else filters. JabRef, Mendeley and publisher exports all emit
#' them, so "records identified" -- the first number of a PRISMA flow diagram --
#' came out too high by however many the file happened to carry.
#' @noRd
.gr_bib_skip <- c("string", "preamble", "comment")

#' Split a BibTeX file into entries.
#'
#' Brace-counting rather than a regex: a title containing braces -- which is how
#' BibTeX protects capitalisation, so `{DNA}` is common -- breaks any regex that
#' assumes the first `}` ends the field.
#'
#' In bytes, not characters. Once one letter anywhere in the file is not ASCII
#' the text is UTF-8, and R finds every character position it reports or takes
#' (gregexpr(), regmatches(), substr()) by walking from the start of the
#' string: a library of 8,000 entries with one accented name in it took 200 s
#' against 16 s for the same file in ASCII, with nothing to show it was not
#' hung. Braces and "@" are ASCII, so a byte offset never falls inside a
#' character. Each entry is still counted from its own opening brace: its
#' closing brace is the first brace after it that returns the depth to where it
#' was before the entry opened.
#' @noRd
bib_entries <- function(txt) {
  txt <- paste(txt, collapse = "\n")
  starts <- gregexpr("@[A-Za-z]+[[:space:]]*\\{", txt, perl = TRUE, useBytes = TRUE)[[1]]
  if (starts[1] == -1L) return(list())
  b <- charToRaw(txt)
  open <- as.integer(starts + attr(starts, "match.length") - 1L)
  types <- tolower(vapply(seq_along(starts), function(k) {
    sub("[[:space:]]*\\{$", "", rawToChar(b[(starts[k] + 1L):open[k]]))
  }, character(1)))
  brace <- which(b == as.raw(0x7bL) | b == as.raw(0x7dL))
  depth <- cumsum(ifelse(b[brace] == as.raw(0x7bL), 1L, -1L))     # after each brace
  at_depth <- split(seq_along(brace), depth)
  lines_at <- which(b == as.raw(0x0aL))
  out <- vector("list", length(starts))
  for (idx in seq_along(starts)) {
    if (types[idx] %in% .gr_bib_skip) next
    o <- match(open[idx], brace)
    # Depth moves one step at a time, so the first later brace at one level
    # below the opening brace is where it closes.
    v <- at_depth[[as.character(depth[o] - 1L)]]
    j <- if (is.null(v)) 0L else findInterval(o, v) + 1L
    close <- if (j >= 1L && j <= length(v)) brace[v[j]] else NA_integer_
    if (is.na(close)) {
      # Silently dropping it removed a study from the review -- from the counts,
      # from screening and from the flow diagram -- with nothing to notice.
      gr_warn(sprintf(paste0("A BibTeX @%s entry beginning on line %d has no closing ",
                             "brace and was skipped; check the file for an unbalanced '{'."),
                      types[idx], findInterval(starts[idx], lines_at) + 1L),
              class = "gr_bib_unterminated")
      next
    }
    out[[idx]] <- if (close - 1L < open[idx] + 1L) "" else
      mark_utf8(rawToChar(b[(open[idx] + 1L):(close - 1L)]))
  }
  out[!vapply(out, is.null, logical(1))]
}

#' Split one entry's body into its `name = value` fields.
#'
#' The same depth counting bib_entries() uses, not a regex. The regex this
#' replaced allowed one level of braces inside a value, and real exports nest
#' deeper: `M{\"{u}}ller` (how Web of Science and BibDesk write an umlaut) and
#' `{{DNA}}` are two. The value then fell back to "up to the first comma", the
#' rest of it was rescanned for fields, and the last one seen won -- so an
#' author list lost everyone after the first accented name, a title stopped at
#' its comma, and "year = 1999" in an abstract replaced the real year.
#'
#' A separator counts only at brace depth zero and outside a quoted value; a
#' quote inside braces (`{\"u}`) does not end one, and neither does one written
#' `\"`, which is not valid BibTeX but is how a hand-typed umlaut looks. Values
#' joined with `#` are concatenated. The first occurrence of a field wins, as it
#' does in BibTeX. A value ends where its braces or quotes close, so a
#' hand-edited file that left out the comma before the next field still reads
#' that field.
#' @noRd
bib_fields <- function(body) {
  ch <- strsplit(body, "", fixed = TRUE)[[1]]
  n <- length(ch)
  if (!n) return(list())
  step <- (ch == "{") - (ch == "}")
  depth <- cumsum(step) - step                  # depth before each character
  # Quotes that open or close a value. An umlaut written `\"` makes it text:
  # counting `author="M\"uller, J."` as three quotes flipped the parity for the
  # rest of the entry, and its title and year were lost. Only when a letter or
  # a brace follows, as one does an accent: a value that ends in a backslash
  # ("... a line break\\") still closes at its quote.
  q <- ch == "\"" & depth == 0L &
    !(c("", ch[-n]) == "\\" & grepl("^[[:alpha:]{]$", c(ch[-1L], "")))
  inq <- (cumsum(q) - q) %% 2L == 1L
  top <- depth == 0L & !inq & !q
  ws <- grepl("^[[:space:]]$", ch)
  # The first of the sorted positions `x` that comes after `v`, or NA.
  after <- function(x, v) {
    k <- findInterval(v, x) + 1L
    if (k > length(x)) NA_integer_ else x[k]
  }
  eq_or_comma <- which(top & (ch == "=" | ch == ","))
  closes <- which(ch == "}" & depth == 1L)       # a brace that returns to depth zero
  quotes <- which(q)
  # A bare (unbraced, unquoted) value runs to the next comma, `#` or line end,
  # as the regex this replaced read it: `journal = Nature Medicine,` is two
  # words, not "Nature". It stops early only where the next word is the name of
  # a field (`year = 2022 month = jan`, a missing comma).
  stops <- which(ch == "\n" | ch == "\r" | (top & (ch == "," | ch == "#")))
  solid <- which(!ws)
  text <- function(a, b) if (a > b) "" else paste(ch[a:b], collapse = "")
  tags <- list()
  i <- 1L
  while (i <= n) {
    s <- after(eq_or_comma, i - 1L)
    if (is.na(s)) break
    # A comma before any "=": the citation key, or stray text.
    if (ch[s] == ",") { i <- s + 1L; next }
    nm <- tolower(sub("^.*[[:space:]]", "", trimws(text(i, s - 1L))))
    parts <- character(0)
    v <- after(solid, s)
    e <- n
    while (!is.na(v)) {
      if ((ch[v] == "{" && top[v]) || q[v]) {
        # An unclosed quote runs to the end of the entry rather than losing it.
        e <- after(if (q[v]) quotes else closes, v)
        parts <- c(parts, if (is.na(e)) text(v + 1L, n) else text(v + 1L, e - 1L))
        if (is.na(e)) e <- n
      } else if (top[v] && ch[v] %in% c(",", "#")) {
        e <- v - 1L                             # "name = ," is an empty value
      } else {
        e <- after(stops, v); e <- if (is.na(e)) n else e - 1L
        nxt <- regexpr("[[:space:]]+[[:alnum:]_:.+-]+[[:space:]]*=", text(v, e))
        if (nxt > 0L) e <- v + nxt - 2L
        while (e > v && ws[e]) e <- e - 1L
        parts <- c(parts, text(v, e))
      }
      nx <- after(solid, e)
      v <- if (!is.na(nx) && ch[nx] == "#" && top[nx]) after(solid, nx) else NA_integer_
    }
    if (grepl("^[[:alnum:]_:.+-]+$", nm) && is.null(tags[[nm]])) {
      tags[[nm]] <- paste(parts, collapse = "")
    }
    nx <- after(solid, e)
    i <- if (is.na(nx)) n + 1L else if (ch[nx] == "," && top[nx]) nx + 1L else nx
  }
  tags
}

#' LaTeX accent commands, each with the letters it composes with.
#'
#' `from` and `to` are the letters and what each becomes under that accent,
#' from Unicode's canonical compositions. The letters include ones that already
#' carry an accent, so the second of two stacked accents composes as well: a
#' Vietnamese letter has two ("Nguy{\\~{\\^e}}n" is "Nguy\u1ec5n"), and so does
#' Pinyin's u-umlaut with a tone. An accent on a letter that has no composed
#' form keeps the combining mark after it.
#' @noRd
.gr_tex_accents <- local({
  # The Vietnamese letters that take a second accent.
  viet <- "\u00e2\u00ea\u00f4\u0103\u01a1\u01b0\u00c2\u00ca\u00d4\u0102\u01a0\u01af"
  acc <- list(
    list(cmd = "'", mark = "\u0301",
         from = paste0("acegiklmnoprsuwyzACEGIKLMNOPRSUWYZ", viet, "\u00fc\u00dc\u00e7\u00c7"),
         to = paste0("\u00e1\u0107\u00e9\u01f5\u00ed\u1e31\u013a\u1e3f\u0144\u00f3\u1e55\u0155",
                     "\u015b\u00fa\u1e83\u00fd\u017a\u00c1\u0106\u00c9\u01f4\u00cd\u1e30\u0139",
                     "\u1e3e\u0143\u00d3\u1e54\u0154\u015a\u00da\u1e82\u00dd\u0179",
                     "\u1ea5\u1ebf\u1ed1\u1eaf\u1edb\u1ee9\u1ea4\u1ebe\u1ed0\u1eae\u1eda\u1ee8",
                     "\u01d8\u01d7\u1e09\u1e08")),
    list(cmd = "`", mark = "\u0300", from = paste0("aeinouwyAEINOUWY", viet, "\u00fc\u00dc"),
         to = paste0("\u00e0\u00e8\u00ec\u01f9\u00f2\u00f9\u1e81\u1ef3\u00c0\u00c8\u00cc\u01f8",
                     "\u00d2\u00d9\u1e80\u1ef2",
                     "\u1ea7\u1ec1\u1ed3\u1eb1\u1edd\u1eeb\u1ea6\u1ec0\u1ed2\u1eb0\u1edc\u1eea",
                     "\u01dc\u01db")),
    list(cmd = "^", mark = "\u0302",
         from = paste0("aceghijosuwyzACEGHIJOSUWYZ", "\u1ea1\u1eb9\u1ecd\u1ea0\u1eb8\u1ecc"),
         to = paste0("\u00e2\u0109\u00ea\u011d\u0125\u00ee\u0135\u00f4\u015d\u00fb\u0175\u0177",
                     "\u1e91\u00c2\u0108\u00ca\u011c\u0124\u00ce\u0134\u00d4\u015c\u00db\u0174",
                     "\u0176\u1e90", "\u1ead\u1ec7\u1ed9\u1eac\u1ec6\u1ed8")),
    list(cmd = "\"", mark = "\u0308", from = "aehiotuwxyAEHIOUWXY",
         to = paste0("\u00e4\u00eb\u1e27\u00ef\u00f6\u1e97\u00fc\u1e85\u1e8d\u00ff\u00c4\u00cb",
                     "\u1e26\u00cf\u00d6\u00dc\u1e84\u1e8c\u0178")),
    list(cmd = "~", mark = "\u0303", from = paste0("aeinouvyAEINOUVY", viet),
         to = paste0("\u00e3\u1ebd\u0129\u00f1\u00f5\u0169\u1e7d\u1ef9\u00c3\u1ebc\u0128\u00d1",
                     "\u00d5\u0168\u1e7c\u1ef8",
                     "\u1eab\u1ec5\u1ed7\u1eb5\u1ee1\u1eef\u1eaa\u1ec4\u1ed6\u1eb4\u1ee0\u1eee")),
    list(cmd = "=", mark = "\u0304", from = "aegiouyAEGIOUY\u00fc\u00dc",
         to = paste0("\u0101\u0113\u1e21\u012b\u014d\u016b\u0233\u0100\u0112\u1e20\u012a\u014c",
                     "\u016a\u0232\u01d6\u01d5")),
    list(cmd = ".", mark = "\u0307", from = "cegzCEGIZ",
         to = "\u010b\u0117\u0121\u017c\u010a\u0116\u0120\u0130\u017b"),
    list(cmd = "u", mark = "\u0306", from = "aegiouAEGIOU\u1ea1\u1ea0",
         to = "\u0103\u0115\u011f\u012d\u014f\u016d\u0102\u0114\u011e\u012c\u014e\u016c\u1eb7\u1eb6"),
    list(cmd = "v", mark = "\u030c", from = "acdeghijklnorstuzACDEGHIKLNORSTUZ\u00fc\u00dc",
         to = paste0("\u01ce\u010d\u010f\u011b\u01e7\u021f\u01d0\u01f0\u01e9\u013e\u0148\u01d2",
                     "\u0159\u0161\u0165\u01d4\u017e\u01cd\u010c\u010e\u011a\u01e6\u021e\u01cf",
                     "\u01e8\u013d\u0147\u01d1\u0158\u0160\u0164\u01d3\u017d\u01da\u01d9")),
    list(cmd = "H", mark = "\u030b", from = "ouOU", to = "\u0151\u0171\u0150\u0170"),
    list(cmd = "c", mark = "\u0327", from = "cegklnrstCEGKLNRST",
         to = paste0("\u00e7\u0229\u0123\u0137\u013c\u0146\u0157\u015f\u0163\u00c7\u0228\u0122",
                     "\u0136\u013b\u0145\u0156\u015e\u0162")),
    list(cmd = "k", mark = "\u0328", from = "aeiouAEIOU",
         to = "\u0105\u0119\u012f\u01eb\u0173\u0104\u0118\u012e\u01ea\u0172"),
    list(cmd = "r", mark = "\u030a", from = "auAU", to = "\u00e5\u016f\u00c5\u016e"),
    list(cmd = "d", mark = "\u0323", from = paste0("adehiklmnorstuyzADEHIKLMNORSTUYZ", viet),
         to = paste0("\u1ea1\u1e0d\u1eb9\u1e25\u1ecb\u1e33\u1e37\u1e43\u1e47\u1ecd\u1e5b\u1e63",
                     "\u1e6d\u1ee5\u1ef5\u1e93\u1ea0\u1e0c\u1eb8\u1e24\u1eca\u1e32\u1e36\u1e42",
                     "\u1e46\u1ecc\u1e5a\u1e62\u1e6c\u1ee4\u1ef4\u1e92",
                     "\u1ead\u1ec7\u1ed9\u1eb7\u1ee3\u1ef1\u1eac\u1ec6\u1ed8\u1eb6\u1ee2\u1ef0")),
    # The hook above, from the vietnam package.
    list(cmd = "h", mark = "\u0309", from = paste0("aeiouyAEIOUY", viet),
         to = paste0("\u1ea3\u1ebb\u1ec9\u1ecf\u1ee7\u1ef7\u1ea2\u1eba\u1ec8\u1ece\u1ee6\u1ef6",
                     "\u1ea9\u1ec3\u1ed5\u1eb3\u1edf\u1eed\u1ea8\u1ec2\u1ed4\u1eb2\u1ede\u1eec"))
  )
  # Any letter, so an accent over one that already has one is read too.
  base <- "(\\\\[ij](?![A-Za-z])|\\p{L})"
  lapply(acc, function(a) {
    cmd <- a$cmd
    # A symbol accent may be followed by its letter directly (\'a); a letter
    # accent needs a brace or a space, or it is a different command (\vspace).
    re <- if (grepl("^[A-Za-z]$", cmd)) {
      sprintf("\\\\%s(?:[[:space:]]*\\{[[:space:]]*%s[[:space:]]*\\}|[[:space:]]+%s)", cmd, base, base)
    } else {
      sprintf("\\\\\\%s[[:space:]]*(?:\\{[[:space:]]*%s[[:space:]]*\\}|%s)", cmd, base, base)
    }
    from <- strsplit(a$from, "")[[1]]
    to <- strsplit(a$to, "")[[1]]
    stopifnot(length(from) == length(to))
    list(re = re, mark = a$mark, from = from, to = to)
  })
})

#' LaTeX commands that are letters in their own right.
#' @noRd
.gr_tex_letters <- list(
  cmd = c("ss", "ae", "AE", "oe", "OE", "aa", "AA", "o", "O", "l", "L", "i", "j",
          "ohorn", "OHORN", "uhorn", "UHORN"),
  to = c("\u00df", "\u00e6", "\u00c6", "\u0153", "\u0152", "\u00e5", "\u00c5", "\u00f8",
         "\u00d8", "\u0142", "\u0141", "\u0131", "\u0237", "\u01a1", "\u01a0", "\u01b0", "\u01af"))

#' Turn LaTeX accents in a BibTeX value into the letters they spell.
#'
#' Scholar, JabRef and BibDesk write "Dvo{\\v{r}}{\\'a}k"; a database writes
#' "Dvo\u0159\u00e1k". Stripping the braces and keeping the rest gave
#' "Dvo\\vr\\'ak", which is nobody's name: it went into citations as that, and
#' its key "dvovrak" matched neither the database's record nor a filename. The
#' symbol accents (\\" and \\') vanished from keys by luck; the letter ones
#' (\\v, \\c, \\H, \\k, \\u) left a stray letter inside the surname.
#'
#' The passes repeat until nothing changes, so stacked accents are read from
#' the inside out: one pass left "Nguy\\~\u00ean". A letter command ends at a
#' non-letter; the space after it is dropped ("Stra\\ss e") unless an empty
#' group ended it ("Pawe\\l{} Nowak"), which in LaTeX keeps the space. Eating
#' that one too stored "Pawe\u0142Nowak", and "Wei\\ss{} and Smith" as one author.
#' @noRd
bib_unlatex <- function(v) {
  if (is.na(v) || !grepl("\\", v, fixed = TRUE)) return(v)
  for (pass in 1:4) {
    before <- v
    for (a in .gr_tex_accents) {
      m <- gregexpr(a$re, v, perl = TRUE)
      if (m[[1]][1] == -1L) next
      regmatches(v, m) <- list(vapply(regmatches(v, m)[[1]], function(s) {
        b <- sub(a$re, "\\1\\2", s, perl = TRUE)
        b <- sub("^\\\\", "", b)                  # \i and \j are the dotless letters
        k <- match(b, a$from)
        if (is.na(k)) paste0(b, a$mark) else a$to[k]
      }, character(1), USE.NAMES = FALSE))
    }
    for (k in seq_along(.gr_tex_letters$cmd)) {
      v <- gsub(sprintf("\\\\%s(?![A-Za-z])(?:\\{\\}|[[:space:]]*)", .gr_tex_letters$cmd[k]),
                .gr_tex_letters$to[k], v, perl = TRUE)
    }
    if (identical(v, before) || !grepl("\\", v, fixed = TRUE)) break
  }
  mark_utf8(v)
}

#' Split a BibTeX name list on " and " at brace depth zero.
#'
#' Braces are how BibTeX says "one name": `{Centers for Disease Control and
#' Prevention}` is one author. Splitting after the braces had been stripped
#' made it two, "Centers for Disease Control" and "Prevention", and the
#' citation read "(Control & Prevention, 2020)".
#' @noRd
bib_split_names <- function(v) {
  if (is.na(v)) return(v)
  m <- gregexpr("[[:space:]]+and[[:space:]]+", v, perl = TRUE)[[1]]
  if (m[1] == -1L) return(v)
  ch <- strsplit(v, "", fixed = TRUE)[[1]]
  depth <- cumsum((ch == "{") - (ch == "}"))
  top <- depth[m] == 0L
  if (!any(top)) return(v)
  at <- as.integer(m[top]); len <- attr(m, "match.length")[top]
  substring(v, c(1L, at + len), c(at - 1L, nchar(v)))
}

#' @noRd
records_from_bib <- function(txt, source_file) {
  entries <- bib_entries(txt)
  if (!length(entries)) return(empty_records())
  clean <- function(v, nm) {
    # Not in a path or a link, where "\o" is a folder, not a letter.
    if (!nm %in% c("file", "url", "doi")) v <- bib_unlatex(v)
    # Capitalisation-protecting braces are not part of the value, and the
    # characters BibTeX makes you escape are not meant to keep their
    # backslash: "Memory {\\&} Cognition" is "Memory & Cognition".
    v <- gsub("\\\\([&%$#_{}])", "\\1", v, perl = TRUE)
    trimws(gsub("[{}]", "", v))
  }
  rows <- lapply(entries, function(body) {
    fields <- bib_fields(body)
    tags <- lapply(names(fields), function(nm) {
      v <- trimws(fields[[nm]])
      if (!identical(nm, "author")) return(clean(v, nm))
      # BibTeX joins authors with " and "; RIS gives one per line. Normalise to
      # the RIS shape so downstream sees one convention -- split while the
      # braces that hold one name together are still there.
      a <- vapply(bib_split_names(v), clean, character(1), nm = nm, USE.NAMES = FALSE)
      paste(a[!is.na(a) & nzchar(a)], collapse = "; ")
    })
    names(tags) <- names(fields)
    vals <- lapply(names(.gr_bib_map), function(f) tag_value(tags, .gr_bib_map[[f]]))
    names(vals) <- names(.gr_bib_map)
    as.data.frame(c(vals, list(type = NA_character_, accession = NA_character_,
                               source_file = source_file)), stringsAsFactors = FALSE)
  })
  finish_records(do.call(rbind, rows))
}

#' Normalise whatever the parsers produced into the standard frame.
#' @noRd
finish_records <- function(df) {
  for (nm in .gr_record_cols) if (is.null(df[[nm]])) df[[nm]] <- NA_character_
  df <- df[, .gr_record_cols, drop = FALSE]
  for (nm in setdiff(.gr_record_cols, "record_id")) {
    v <- mark_utf8(as.character(df[[nm]]))
    v[!nzchar(trimws(v))] <- NA_character_
    df[[nm]] <- v
  }
  # A year is whatever four digits the field contains: exporters write "2019",
  # "2019/03/12", "2019 Mar" and "c2019" for the same year.
  df$year <- sub(".*?((?:1[6-9]|20)[0-9]{2}).*", "\\1", df$year, perl = TRUE)
  df$year[!grepl("^[0-9]{4}$", df$year)] <- NA_character_
  # DOIs arrive as bare, as a URL, and with a "doi:" prefix. One shape, so two
  # records for one paper can be recognised as one paper.
  df$doi <- lower_text(trimws(df$doi))
  df$doi <- sub("^(https?://)?(dx\\.)?doi\\.org/", "", df$doi)
  df$doi <- sub("^doi:[[:space:]]*", "", df$doi)
  df$doi[!grepl("^10\\.[0-9]{4,9}/", df$doi)] <- NA_character_
  df$record_id <- seq_len(nrow(df))
  rownames(df) <- NULL
  df
}

#' Read a search export, and say what the search found
#'
#' Reads RIS or BibTeX exports from one or more databases, removes the records
#' that are the same work, and matches what is left to the documents you have on
#' disk. It is the step before [gr_screen()], and it is where a review's numbers
#' come from: how many records were identified, how many duplicates went, how
#' many reports were sought and how many were never obtained.
#'
#' Nothing here calls a model. Which paper a record is, and whether two records
#' are one paper, are questions a DOI answers exactly.
#'
#' @section Why start here rather than at a folder:
#' A folder of PDFs cannot say which databases were searched, with what query,
#' on what date, or how many records came back (PRISMA items 6, 7 and 16), and
#' no care further down substitutes for them. It also cannot say what is
#' *missing*: a record with no PDF is "report not retrieved", which is a finding
#' about the review, and a folder represents it as nothing at all.
#'
#' It fixes something quieter too. [gr_synthesise()] cites by author and year,
#' and without an export those come from asking a model to read a title page.
#' That is the one part of a citation that must be exactly right, resting on the
#' loosest guarantee in the pipeline. From an export they are data.
#'
#' @param exports Paths to `.ris`, `.txt`, `.bib`, `.bibtex` or `.nbib` files,
#'   or directories containing them. Several exports from several databases is
#'   the normal case and is what the duplicate counts are for. The format is
#'   read from the content, not the extension: RIS, BibTeX, or PubMed's own
#'   format (what its "Send to: Citation manager" writes, usually `.nbib`). A
#'   file that is not UTF-8 is read as Windows-1252, with a warning naming it.
#' @param files A directory of documents, or a character vector of paths, to
#'   match records against. Optional: a record set is useful before anything has
#'   been downloaded.
#' @param search A [gr_search()] describing how the export was produced. Not
#'   required, and the reason to supply it is that a review has to report it.
#' @param dedupe `"doi"` matches on DOI alone; `"doi+title"` (the default) falls
#'   back to normalised title and year when a DOI cannot settle it, which is
#'   what catches the same conference paper indexed twice, or indexed once with
#'   its DOI and once without. The title fallback also needs the first author's
#'   surname to agree as a whole name ("Smith, J." and "Smith JA" agree, "Li" and
#'   "Lin" do not) and the first initials not to differ ("Wang, L." and
#'   "Wang, H." are two people), or, when a record has no authors, the venue. An
#'   organisation agrees with its acronym ("WHO" and "World Health
#'   Organization"). Between two records without DOIs, a surname that is the
#'   other record's given name ("Li, W." and "Li Wei") also agrees when the
#'   initial bears it out and the venues do not disagree. It ignores titles
#'   shorter than 12 letters ("Reply", "Editorial") and never merges records
#'   carrying two different DOIs. A record without a DOI is merged with one that
#'   has a DOI, and a title with fewer than 12 Latin letters or digits is merged
#'   at all, only when the venues do not disagree and the surname (not a given
#'   name) or the venue confirms it. The kept row takes any field it lacks (the
#'   DOI, the journal) from the rows merged into it. `"none"` keeps everything.
#' @return An object of class `gr_records`:
#'   \describe{
#'     \item{`records`}{One row per distinct work, with `duplicate_of` naming the
#'       row a dropped record repeats, `file` the document matched to it, and
#'       `retrieved` whether one was found. A duplicate's file path counts
#'       towards the row it repeats, which is where the match is reported; a
#'       second copy the duplicate's own path points to is shown on the
#'       duplicate's row.}
#'     \item{`counts`}{Identified, per database, duplicates removed, distinct
#'       records, reports sought, reports retrieved, reports not retrieved.}
#'     \item{`search`}{The `gr_search()`, or `NULL`.}
#'     \item{`unmatched_files`}{Documents on disk that no record claims, usually
#'       a sign the export and the folder are out of step.}
#'   }
#' @seealso [gr_search()], [gr_screen()], [gr_flow()], [gr_inventory()]
#' @family corpus functions
#' @export
#' @examples
#' ris <- tempfile(fileext = ".ris")
#' writeLines(c("TY  - JOUR", "AU  - Smith, J.", "TI  - A trial of spacing",
#'              "PY  - 2019", "DO  - 10.1000/abc", "ER  - "), ris)
#' recs <- gr_records(ris)
#' recs
#' recs$records[, c("authors", "year", "title", "doi", "retrieved")]
gr_records <- function(exports, files = NULL, search = NULL,
                       dedupe = c("doi+title", "doi", "none")) {
  dedupe <- match.arg(dedupe)
  if (!is.null(search) && !inherits(search, "gr_search")) {
    gr_abort("`search` must come from gr_search().", class = "gr_bad_search")
  }
  paths <- export_paths(exports)
  if (!length(paths)) {
    gr_abort(paste0("No export files found. Pass .ris, .bib or .txt files from a reference ",
                    "manager, or a directory containing them."), class = "gr_no_exports")
  }
  parsed <- lapply(paths, read_export)
  recs <- do.call(rbind, parsed)
  recs$record_id <- seq_len(nrow(recs))
  rownames(recs) <- NULL
  if (!nrow(recs)) gr_abort("Those exports contain no records.", class = "gr_no_exports")

  identified <- nrow(recs)
  # `source_file` is already a basename. basename() again translated it to the
  # native encoding, and in a C locale an export named "\u00c9vora.ris" aborted
  # the whole call.
  by_db <- table(ifelse(is.na(recs$database), recs$source_file, recs$database))

  recs$duplicate_of <- dedupe_records(recs, dedupe)
  distinct <- is.na(recs$duplicate_of)
  recs <- merge_duplicate_fields(recs)

  matched <- match_files(recs, files)
  recs$file <- matched$file
  recs$retrieved <- !is.na(recs$file)
  # A duplicate is not separately "not retrieved": it is the same work as a row
  # that either was or was not. Counting it again would inflate both numbers.
  recs$retrieved[!distinct] <- NA

  counts <- data.frame(
    stage = c("records identified", "duplicates removed", "records screened",
              "reports sought", "reports retrieved", "reports not retrieved"),
    n = c(identified, sum(!distinct), sum(distinct), sum(distinct),
          sum(distinct & recs$retrieved %in% TRUE),
          sum(distinct & recs$retrieved %in% FALSE)),
    stringsAsFactors = FALSE)

  structure(list(records = recs, counts = counts, by_database = by_db,
                 search = search, exports = paths,
                 unmatched_files = matched$unmatched, dedupe = dedupe),
            class = "gr_records")
}

#' @noRd
export_paths <- function(exports) {
  ext <- c("ris", "bib", "bibtex", "txt", "nbib")
  in_dir <- function(d) {
    f <- list.files(d, full.names = TRUE, no.. = TRUE)
    f <- f[!dir.exists(f)]
    f <- f[tolower(tools::file_ext(f)) %in% ext]
    # Byte order, not sort(): sort() follows LC_COLLATE, so "adams" came before
    # "Baker" on a laptop and after it under cron or R CMD check. The export
    # order decides record_id and which copy of a duplicated work is the one
    # kept, and a record set should not depend on the machine that read it.
    # mark_utf8(), not enc2utf8(): in a C locale enc2utf8() rewrites the
    # unlabelled UTF-8 bytes of "\u00c9vora.ris" as the text "<c3><89>vora.ris",
    # which sorts before "Baker".
    f[order(mark_utf8(f), method = "radix")]
  }
  if (is.character(exports) && length(exports) == 1L && !is.na(exports) && dir.exists(exports)) {
    return(in_dir(exports))
  }
  p <- as.character(unlist(exports, use.names = FALSE))
  p <- p[!is.na(p)]
  missing <- p[!file.exists(p)]
  if (length(missing)) {
    gr_abort(sprintf("Export file(s) not found: %s.",
                     paste(sprintf("'%s'", missing), collapse = ", ")),
             class = "gr_no_exports")
  }
  # A folder among several paths is read as it is on its own. Taken as a file,
  # it failed to open, contributed nothing and still counted as an export:
  # gr_records(c("exports/wos", "pubmed.ris")) read none of Web of Science.
  folder <- dir.exists(p)
  if (any(folder)) {
    p <- unlist(lapply(seq_along(p), function(i) {
      if (!folder[i]) return(p[i])
      f <- in_dir(p[i])
      if (!length(f)) {
        gr_warn(sprintf(paste0("The folder '%s' holds no .ris, .bib, .bibtex, .txt or .nbib ",
                               "files. It contributed no records."), p[i]),
                class = "gr_unknown_export")
      }
      f
    }), use.names = FALSE)
    # A file named on its own and found again in a folder is one export, not
    # two: reading it twice would count its records twice as "identified".
    real <- vapply(p, function(x) tryCatch(normalizePath(x, winslash = "/", mustWork = FALSE),
                                           error = function(e) x), character(1), USE.NAMES = FALSE)
    p <- p[!duplicated(real)]
  }
  p
}

#' Read one export, choosing the parser by content rather than by extension.
#'
#' Exporters are careless with extensions -- Web of Science writes RIS into a
#' `.txt`, and a `.txt` from Scholar is BibTeX. Looking at the first line is
#' more reliable than trusting the name.
#'
#' The lines are made UTF-8 first. `readLines(encoding = "UTF-8")` only labels
#' the bytes, and an EndNote export saved as "ANSI" on Windows is Windows-1252:
#' with an accent in its first sixty lines every test below failed on it and
#' the file was dropped as "not RIS", and with one further down the parser
#' stopped gr_records() with "input string 2 is invalid in this locale". It is
#' read as Windows-1252, the one guess to_utf8() makes, and a warning names the
#' file, since a file in another encoding would come out with the wrong
#' letters.
#' @noRd
read_export <- function(path) {
  # readLines() warns with the reason a file cannot be opened and then fails
  # with "cannot open the connection"; the warning is the part worth saying.
  held <- list()
  lines <- tryCatch(withCallingHandlers(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    warning = function(w) { held[[length(held) + 1L]] <<- w; invokeRestart("muffleWarning") }),
    error = function(e) { held[[length(held) + 1L]] <<- e; NULL })
  if (is.null(lines)) {
    # An empty frame with no warning of the package's own was how an export
    # that could not be opened dropped out of "records identified" unnoticed.
    gr_warn(sprintf("'%s' could not be read (%s). It contributed no records.", basename(path),
                    conditionMessage(held[[1]])), class = "gr_export_unreadable")
    return(empty_records())
  }
  for (w in held) warning(w)                  # a file that did read keeps its warnings
  if (!length(lines)) return(empty_records())
  bad <- sum(!validUTF8(lines))
  lines <- to_utf8(lines)
  lines[1] <- sub("^\ufeff", "", lines[1])                     # a byte-order mark
  if (bad) {
    gr_warn(sprintf(paste0("'%s' is not UTF-8: %d line(s) were read as Windows-1252 (Latin-1). ",
                           "Check the accented names in its records, or export it again as UTF-8."),
                    basename(path), bad), class = "gr_export_encoding")
  }
  head_lines <- utils::head(lines, 60)
  head_txt <- paste(head_lines, collapse = "\n")
  if (grepl("^[[:space:]]*@[[:alpha:]]+[[:space:]]*\\{", head_txt) ||
      grepl("\n[[:space:]]*@[[:alpha:]]+[[:space:]]*\\{", head_txt)) {
    return(records_from_bib(lines, basename(path)))
  }
  if (any(ris_tags(head_lines)$tag %in% "TY")) {
    return(records_from_ris(lines, basename(path)))
  }
  if (any(grepl("^PMID- ", head_lines))) {
    return(records_from_medline(lines, basename(path)))
  }
  gr_warn(sprintf(paste0("'%s' does not look like RIS, BibTeX or PubMed: no 'TY  -', no ",
                         "'@article{' and no 'PMID- '. It contributed no records."), basename(path)),
          class = "gr_unknown_export")
  empty_records()
}

#' @export
print.gr_records <- function(x, ...) {
  cat(sprintf("<gr_records> %d record(s) from %d export(s)\n",
              nrow(x$records), length(x$exports)))
  if (length(x$by_database)) {
    cat(sprintf("  %s\n", paste(sprintf("%s %d", names(x$by_database),
                                        as.integer(x$by_database)), collapse = ", ")))
  }
  for (i in seq_len(nrow(x$counts))) {
    cat(sprintf("  %-24s %d\n", x$counts$stage[i], x$counts$n[i]))
  }
  gone <- x$counts$n[x$counts$stage == "reports not retrieved"]
  if (length(gone) && gone > 0L) {
    cat(sprintf("  ! %d record(s) have no document. They are part of the review and are\n", gone))
    cat("    reported as sought-but-not-retrieved, not quietly dropped.\n")
  }
  if (length(x$unmatched_files)) {
    cat(sprintf("  ! %d file(s) on disk match no record: %s\n", length(x$unmatched_files),
                paste(utils::head(basename(x$unmatched_files), 3), collapse = ", ")))
  }
  if (is.null(x$search)) {
    cat("  no gr_search() attached: the review cannot report what was searched\n")
  }
  invisible(x)
}

#' Record how the search was run
#'
#' The part of a review that no tool can infer and every review must state:
#' which databases were searched, with what query, on what date, and what limits
#' were applied. PRISMA items 6 and 7 ask for it, and item 7 asks for the full
#' strategy for at least one database *so that it could be repeated*.
#'
#' This function computes nothing. It exists so the answer travels with the run
#' instead of living in a lab notebook. It reaches [gr_flow()] and the audit
#' report, and, given to [gr_protocol()] as `search`, it round-trips through
#' [gr_protocol_save()] alongside the criteria, so what was searched and what
#' was eligible are one artifact.
#'
#' @param databases Named character vector or list: name of each source, value
#'   the query string run against it. The query is the point; a review reporting
#'   "we searched PubMed" without it cannot be repeated.
#' @param dates When each search was run, as `YYYY-MM-DD`. One value, or one per
#'   database. Searches drift: a review is a statement about a date.
#' @param limits Limits applied: language, publication years, study design
#'   filters. Free text; a review states them whatever they were.
#' @param registration Registration identifier (a PROSPERO number, say), or
#'   `NA` and say so. PRISMA item 24 asks either way.
#' @param other Any further sources: reference lists checked, experts contacted,
#'   registers, preprint servers, hand-searched journals.
#' @param notes Anything else the methods section has to say.
#' @return An object of class `gr_search`.
#' @seealso [gr_records()], [gr_protocol()], [gr_flow()]
#' @family corpus functions
#' @export
#' @examples
#' gr_search(
#'   databases = c(PubMed = "(spaced practice[tiab]) AND (retention[tiab])",
#'                 Scopus = "TITLE-ABS-KEY(\"spaced practice\" AND retention)"),
#'   dates = "2026-02-14",
#'   limits = "English; 2000 onwards; primary studies only",
#'   registration = "PROSPERO CRD42026000000",
#'   other = "Reference lists of included studies hand-searched"
#' )
gr_search <- function(databases, dates = NULL, limits = NULL, registration = NA_character_,
                      other = NULL, notes = NULL) {
  db <- unlist(databases, use.names = TRUE)
  if (!length(db) || is.null(names(db)) || any(!nzchar(names(db)))) {
    gr_abort(paste0("`databases` must be named: the name is the source and the value is the ",
                    "query run against it. A review that reports which databases it searched ",
                    "but not what it asked them cannot be repeated, which is what PRISMA ",
                    "item 7 is for."), class = "gr_bad_search")
  }
  db <- vapply(db, as_chr1, character(1))
  if (any(!nzchar(trimws(db)))) {
    gr_abort(sprintf("No query given for %s.",
                     paste(sprintf("'%s'", names(db)[!nzchar(trimws(db))]), collapse = ", ")),
             class = "gr_bad_search")
  }
  dates <- if (is.null(dates)) NA_character_ else as.character(dates)
  if (length(dates) > 1L && length(dates) != length(db)) {
    gr_abort("`dates` must be one value, or one per database.", class = "gr_bad_search")
  }
  bad <- dates[!is.na(dates) & !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dates)]
  if (length(bad)) {
    gr_warn(sprintf("Search date(s) %s are not YYYY-MM-DD. They are recorded as given.",
                    paste(sprintf("'%s'", bad), collapse = ", ")), class = "gr_bad_search_date")
  }
  structure(list(
    databases = db,
    dates = rep(dates, length.out = length(db)),
    limits = if (is.null(limits)) NA_character_ else as.character(limits),
    registration = as_chr1(registration, NA_character_),
    other = if (is.null(other)) character(0) else as.character(other),
    notes = if (is.null(notes)) NA_character_ else as_chr1(notes)
  ), class = "gr_search")
}

#' @export
print.gr_search <- function(x, ...) {
  cat(sprintf("<gr_search> %d source(s)\n", length(x$databases)))
  for (i in seq_along(x$databases)) {
    cat(sprintf("  %s%s\n    %s\n", names(x$databases)[i],
                if (is.na(x$dates[i])) "" else sprintf("  (searched %s)", x$dates[i]),
                substr(x$databases[i], 1, 100)))
  }
  if (!is.na(x$limits[1])) cat(sprintf("  limits : %s\n", paste(x$limits, collapse = "; ")))
  for (o in x$other) cat(sprintf("  also   : %s\n", o))
  cat(sprintf("  registration: %s\n",
              if (is.na(x$registration)) "NOT REGISTERED; say so in the report"
              else x$registration))
  invisible(x)
}
