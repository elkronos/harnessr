# doc-records-match.R: records matched to the files in a folder.

#' Match records to documents on disk.
#'
#' Four routes, in order of how much they prove: the path the export itself
#' recorded, a filename containing the DOI's suffix, a filename whose letters
#' match the title's, and a filename naming the first author and the year.
#' Nothing fuzzier -- a wrong match attributes one paper's findings to another,
#' which is worse than reporting the report as not retrieved.
#' @noRd
match_files <- function(recs, files) {
  n <- nrow(recs)
  if (is.null(files)) return(list(file = rep(NA_character_, n), unmatched = character(0)))
  paths <- if (is.character(files) && length(files) == 1L && !is.na(files) && dir.exists(files)) {
    corpus_sources(files, recursive = TRUE, quiet = TRUE)
  } else as.character(unlist(files, use.names = FALSE))
  paths <- unname(paths[!is.na(paths)])
  if (!length(paths)) return(list(file = rep(NA_character_, n), unmatched = character(0)))

  base <- basename(paths)
  stem <- title_key(tools::file_path_sans_ext(base))
  # Case kept, for route 4: "SmithEtAl2019" is three words and "Parkinson" one.
  fstem <- fold_latin(tools::file_path_sans_ext(base))
  out <- rep(NA_character_, n)
  taken <- rep(FALSE, length(paths))

  # A duplicate is matched AS the row it repeats. Letting it claim a file on its
  # own gave the document to a row every later stage ignores: when only the
  # second copy of a paper carried the PDF path (an EndNote export beside a
  # Scopus one, or one library holding the item twice), the kept record was
  # "not retrieved", the file was taken so it was not unmatched either, and the
  # full text never reached screening or the flow counts. So each kept row
  # matches with everything its duplicates know, the kept row's own evidence
  # first and then each duplicate's in record order.
  dup <- recs$duplicate_of %||% rep(NA_integer_, n)
  owner <- ifelse(is.na(dup), seq_len(n), match(dup, recs$record_id))
  kept <- is.na(dup)
  members <- split(which(!is.na(owner)), owner[!is.na(owner)])

  # Route 4 below matches on first-author surname plus year, which is ambiguous
  # the moment two records share both. Checking only that ONE FILE matched the
  # record let the first of two Smith-2019 papers claim smith2019.pdf and the
  # second find nothing -- a coin flip presented as a match, and the way one
  # paper's findings end up attributed to another. Ambiguity is a property of
  # the record set, so it is settled here, before anything claims anything.
  #
  # Every route needs that settlement. A key that two works share identifies
  # neither of them, and without this the FIRST record listed took the file
  # while the second went unretrieved -- a coin flip decided by export order.
  # Two folders each holding a `report.txt`, which is what a `year/report.pdf`
  # archive looks like, put the 2019 file on the 2020 record and the 2020 file
  # on the 2019 record, both marked retrieved. That is one paper's findings
  # published under another paper's authors, year and DOI. A key the rows of
  # ONE work share (a record and its duplicate) is not ambiguous.
  #
  # The author-year key is the exception (`own_first`). There a kept row is
  # settled against kept rows only, and a duplicate's key is extra evidence
  # for its work, used only when no other work has it at all: the same paper
  # routinely carries its e-pub year in one database and its print year in
  # another, and its PubMed copy's "jones|2019" made a different Jones's 2019
  # paper unmatchable even after the first Jones had claimed its own file.
  settle <- function(k, own_first = FALSE) {
    k[is.na(owner)] <- NA_character_
    kid <- match(k, k)
    shared <- function(rows) {
      cnt <- vapply(split(owner[rows], kid[rows]), function(g) length(unique(g)), integer(1))
      as.integer(names(cnt)[cnt > 1L])
    }
    ok <- !is.na(k)
    if (!own_first) {
      if (any(ok)) k[kid %in% shared(which(ok))] <- NA_character_
      return(k)
    }
    if (any(ok & kept)) k[kept & kid %in% shared(which(ok & kept))] <- NA_character_
    if (any(ok & !kept)) k[!kept & kid %in% shared(which(ok))] <- NA_character_
    k
  }
  sur <- record_first_author(recs$authors)$surname
  sur_k <- title_key(sur)
  ay <- ifelse(is.na(sur_k) | nchar(sur_k) < 3L | is.na(recs$year), NA_character_,
               paste0(sur_k, "|", recs$year))
  ay <- settle(ay, own_first = TRUE)
  # The surname as a whole word of the filename, not as any substring of it.
  # `grepl("chen", "cheng2020")` gave Chen's record Cheng's paper, "park" found
  # "Parkinson disease and exercise", and "lee" found "Sleep quality". A word
  # starts where letters start, and ends where they stop or where a lower-case
  # letter meets a capital, so "SmithEtAl2019" and "SmithJ_2019" still name
  # Smith, and so does "smithetal2019". A capital inside a word does not start
  # one: "McKay2019" is not Kay's, "DeWitt" not Witt's. An all-lower
  # "smithj2019" is left unmatched rather than guessed at, since "chenl" cannot
  # be told from "cheng".
  #
  # Nor is the end of a longer surname one: not after an apostrophe
  # ("O'Connor" is not Connor's) or a particle ("De Souza", "van der Berg",
  # "Mc Kay"), and not on either side of a hyphen that joins two capitalised
  # names ("Garcia-Lopez" is neither Garcia's nor Lopez's). Each of these gave
  # a record whose own file was missing the file of the longer name, and a
  # file that both records matched went to neither. The record's own capitals
  # mark its parts, so "DeWitt" also finds "De Witt" and "OBrien" "O'Brien".
  sur_f <- fold_latin(sur)
  particle <- paste0("(?i:(?<!\\p{L})", c(.gr_rec_particles, "mc", "mac"), ")[ _.\\-]")
  # The apostrophe and hyphen as characters, not as \x{...}: an all-ASCII
  # pattern and folder are matched in PCRE's byte mode, which rejects those.
  before <- paste0("(?<!\\p{L})(?<!\\p{L}['\u2019])(?:(?<!\\p{L}[\\-\u2010])|(?=\\p{Ll}))",
                   "(?<!", paste(c(particle, "(?i:(?<!\\p{L})st\\.)[ _]"), collapse = "|"), ")")
  after <- paste0("(?:(?:[^\\p{L}\\p{N}]*(?i:et[^\\p{L}\\p{N}]*al))?(?!\\p{L}|[\\-\u2010]\\p{Lu})",
                  "|(?<=\\p{Ll})(?=\\p{Lu}))")
  sur_re <- vapply(seq_len(n), function(i) {
    if (is.na(ay[i])) return(NA_character_)
    parts <- gsub("(\\p{Ll})(\\p{Lu})|(\\p{Lu})(\\p{Lu}\\p{Ll})", "\\1\\3 \\2\\4", sur_f[i], perl = TRUE)
    w <- lower_text(regmatches(parts, gregexpr("[\\p{L}\\p{N}]+", parts, perl = TRUE))[[1]])
    if (!length(w)) return(NA_character_)
    paste0(before, "(?i:", paste(w, collapse = "[^\\p{L}\\p{N}]*"), ")", after)
  }, character(1))

  cand_all <- ifelse(is.na(recs$file), NA_character_,
                     sub("^:+", "", sub(":[[:alpha:]]+$", "", recs$file)))
  base_key <- settle(ifelse(is.na(cand_all), NA_character_, basename(cand_all)))
  doi_key <- settle(vapply(seq_len(n), function(i) {
    if (is.na(recs$doi[i])) return(NA_character_)
    sfx <- title_key(sub("^10\\.[0-9]{4,9}/", "", recs$doi[i]))
    if (is.na(sfx) || nchar(sfx) < 6L) NA_character_ else sfx
  }, character(1)))
  tk_all <- title_key(recs$title)
  ttl_key <- settle(ifelse(is.na(tk_all) | nchar(tk_all) < 12L, NA_character_,
                           substr(tk_all, 1, 24)))
  # Route 3's other direction, a filename that is the start of a title, needs
  # a stem as long as the title floor: "2.pdf" in a folder of numbered
  # downloads was the start of "2019 novel coronavirus ..." and went to it as
  # retrieved. And a stem that begins the titles of two works identifies
  # neither, even where settle() above blanked one of their keys (it compares
  # the first 24 letters of the titles, not the stem's shorter prefix of them).
  stem_24 <- substr(stem, 1, 24)
  stem_ok <- !is.na(stem) & nchar(stem) >= 12L
  live <- !is.na(owner) & !is.na(tk_all) & nchar(tk_all) >= 12L
  for (len in unique(nchar(stem_24[stem_ok]))) {
    has <- live & nchar(tk_all) >= len
    pre <- substr(tk_all[has], 1, len)
    pre <- pre[!duplicated(paste(pre, owner[has], sep = "\r"))]  # one per work
    shared <- unique(pre[duplicated(pre)])
    j <- stem_ok & nchar(stem_24) == len
    stem_ok[j] <- !stem_24[j] %in% shared
  }

  # Each route gives, for one row, the untaken files it points to, or NULL when
  # the row has nothing to offer that route.
  hits <- list(
    # 1. The export said where the file is. Mendeley writes ":path:pdf";
    # EndNote writes "internal-pdf://...". The full path first, and the
    # basename only when no full path matches.
    function(i) {
      if (is.na(cand_all[i])) return(NULL)
      j <- which(!taken & paths == cand_all[i])
      if (!length(j) && !is.na(base_key[i])) j <- which(!taken & base == base_key[i])
      j
    },
    # 2. The DOI suffix appears in the filename -- how most managers name files.
    function(i) {
      if (is.na(doi_key[i])) return(NULL)
      which(!taken & grepl(doi_key[i], stem, fixed = TRUE))
    },
    # 3. The title, reduced to letters, is a prefix of the filename or contains
    # it. Requires a long enough overlap that a coincidence is implausible.
    function(i) {
      if (is.na(ttl_key[i])) return(NULL)
      which(!taken & !is.na(stem) &
              (startsWith(stem, ttl_key[i]) | (stem_ok & startsWith(tk_all[i], stem_24))))
    },
    # 4. First author's surname and the year both appear in the filename. This
    # is how people actually name downloaded PDFs -- "smith2019.pdf",
    # "Smith 2019 - Cognitive Load.pdf" -- and without it the routes above match
    # almost nothing in a real folder. Both parts are required and the match
    # must be unique, so two Smith papers from 2019 match neither rather than
    # attributing one paper's findings to the other. `pos` and `len` are where
    # the surname starts in the filename and how long it runs there, which with
    # the author list says whose file "Kim and Lee 2020" is (running(), below).
    # They do not change while the route is run again, so they are found once
    # per row, in `r4`.
    function(i) {
      if (is.na(sur_re[i])) return(NULL)
      if (is.null(r4[[i]])) {
        at <- regexpr(sur_re[i], fstem, perl = TRUE)
        j <- which(at > 0L & grepl(recs$year[i], base, fixed = TRUE))
        r4[[i]] <<- list(j = j, pos = as.integer(at[j]), len = attr(at, "match.length")[j])
      }
      keep <- !taken[r4[[i]]$j]
      structure(r4[[i]]$j[keep], pos = r4[[i]]$pos[keep], len = r4[[i]]$len[keep])
    }
  )
  r4 <- vector("list", n)
  # What one work offers a route: `pick`, the files of the first of its rows
  # that points anywhere (the kept row's own recorded path beats a duplicate's,
  # so two copies of one paper, each with its own PDF, are not an ambiguity);
  # `want`, everything any of its rows points to, which is what it contests;
  # and each row's own files, for the copies a route-1 claim also accounts for.
  offer <- function(g, route) {
    pick <- integer(0); want <- integer(0); pos <- integer(0); len <- integer(0); by_row <- list()
    for (i in members[[as.character(g)]]) {
      j <- hits[[route]](i)
      if (is.null(j)) next
      by_row[[as.character(i)]] <- as.integer(j)
      if (!length(pick)) pick <- as.integer(j)
      p <- attr(j, "pos") %||% rep(0L, length(j))
      l <- attr(j, "len") %||% rep(0L, length(j))
      for (k in seq_along(j)) {
        m <- match(j[k], want)
        if (is.na(m)) {
          want <- c(want, j[k]); pos <- c(pos, p[k]); len <- c(len, l[k])
        } else if (p[k] < pos[m]) {
          pos[m] <- p[k]; len[m] <- l[k]
        }
      }
    }
    list(pick = pick, want = want, pos = pos, len = len, by_row = by_row)
  }

  # Which of the works that want one file at route 4 are in the running for
  # it. One whose title's opening words are in the filename as well is the
  # one. Otherwise a filename names its first author first, so a work named
  # earlier in it rules out one named later -- but only when that is what the
  # name shows: the later surname is among the earlier work's authors ("Kim and
  # Lee 2020" is Kim's paper, not Lee's), or lies inside the earlier match. A
  # surname that merely comes first proves nothing: "Early Intervention in
  # Psychiatry - 2020 - Smith - Screening..." is Smith's paper,
  # "jama_smith_2019" is a Smith's and not a Jama's, and "Young adults exercise
  # - Smith 2019" is not Young's. When nothing tells them apart, the file goes
  # to none of them and is listed as unmatched.
  work_of <- function(g, x) unique(unlist(x[members[[as.character(g)]]], use.names = FALSE))
  sur_w <- record_name_words(sur)
  au_w <- record_name_words(recs$authors)
  running <- function(g, what, pos, len) {
    front <- rep(TRUE, length(what))
    for (f in unique(what[duplicated(what)])) {
      k <- which(what == f)
      titled <- vapply(k, function(x) {
        t <- work_of(g[x], ttl_key)
        t <- t[!is.na(t)]
        !is.na(stem[f]) && length(t) > 0L && any(vapply(t, grepl, logical(1), x = stem[f], fixed = TRUE))
      }, logical(1))
      if (sum(titled) == 1L) {
        front[k] <- titled
        next
      }
      behind <- vapply(k, function(a) any(vapply(k, function(b) {
        pos[b] < pos[a] &&
          (pos[a] + len[a] <= pos[b] + len[b] || any(work_of(g[a], sur_w) %in% work_of(g[b], au_w)))
      }, logical(1))), logical(1))
      front[k] <- !behind
    }
    front
  }

  # One route at a time across ALL records, strongest first -- not every route
  # for one record before the next record is looked at. Record by record, a
  # weak surname match for an early record took a file that was an exact title
  # match for a later one, and which paper got the file depended on export
  # order. A claim needs the file to be the work's only candidate at that route
  # (two files of one name on disk is the same ambiguity as two records
  # claiming one file, seen from the other end) and the work to be the file's
  # only claimant. A file two works both want goes to neither; it stays on the
  # table, as a key two works share does, for a later route that only one work
  # passes -- or for nobody, and then unmatched_files says so.
  #
  # A route is run again while it still settles something: once a work has
  # claimed its file, a work that wanted that file and one other now wants only
  # the other. And at route 4 a file naming two surnames goes to the one the
  # name shows is its first author (running() above): "Kim and Lee 2020" is
  # Kim's, and it no longer stops Lee's record taking "Lee 2020".
  pending <- which(kept & !is.na(owner))
  for (route in seq_along(hits)) {
    repeat {
      if (!length(pending) || all(taken)) break
      offers <- lapply(pending, offer, route = route)
      who <- rep(seq_along(offers), vapply(offers, function(o) length(o$want), integer(1)))
      what <- unlist(lapply(offers, `[[`, "want"))
      if (!length(what)) break
      front <- if (route == 4L) {
        running(pending[who], what, unlist(lapply(offers, `[[`, "pos")),
                unlist(lapply(offers, `[[`, "len")))
      } else rep(TRUE, length(what))
      wanted <- tabulate(what[front], nbins = length(paths))
      win <- vapply(seq_along(offers), function(w) {
        p <- offers[[w]]$pick
        length(p) == 1L && wanted[p] == 1L && any(who == w & what == p & front)
      }, logical(1))
      if (!any(win)) break
      for (w in which(win)) {
        g <- pending[w]
        f <- offers[[w]]$pick
        out[g] <- paths[f]
        taken[f] <- TRUE
        if (route == 1L) {
          # The other rows' own recorded files are that work's other copies --
          # one library holding the item twice, each with its PDF attached --
          # and each is reported on the row that recorded it, as it was before
          # duplicates were pooled. Only a file no other work points to.
          for (nm in names(offers[[w]]$by_row)) {
            i <- as.integer(nm)
            j <- offers[[w]]$by_row[[nm]]
            if (i != g && length(j) == 1L && !taken[j] && wanted[j] == 1L) {
              out[i] <- paths[j]
              taken[j] <- TRUE
            }
          }
        }
      }
      pending <- pending[!win]
    }
  }
  list(file = out, unmatched = paths[!taken])
}
