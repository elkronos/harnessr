# core-util-misc.R -- tiny helpers shared across the package.
#
# Design rule for this file: nothing here may make a network call, mutate global
# state outside `gr_state`, or return NULL where a caller is going to index into
# the result. The original codebase's most common crash class was a function
# returning NULL / character(0) into a caller that assumed character(1); the
# helpers here exist to make that impossible by construction.

#' Null-coalescing operator.
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Empty-coalescing: falls back when `x` is NULL, length 0, all-NA, or all-"".
#' @noRd
`%|z|%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) return(y)
  if (is.character(x) && all(is.na(x) | !nzchar(x))) return(y)
  if (all(is.na(x))) return(y)
  x
}

#' Coerce anything to a single non-NA character string.
#'
#' Guards against the `NULL` / `character(0)` / `NA` / length > 1 cases that
#' repeatedly crashed `if (!nzchar(x))` style checks in the previous codebase.
#' @noRd
as_chr1 <- function(x, default = "") {
  if (is.null(x)) return(default)
  if (length(x) == 0L) return(default)
  x <- as.character(x)
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(default)
  if (length(x) > 1L) x <- paste(x, collapse = "\n")
  x
}

#' Coerce to a length-one numeric, never to NULL or a zero-length vector.
#'
#' `utils::modifyList()` DELETES a key whose value is NULL, and `data.frame()`
#' silently drops a zero-length column. A registry entry holding NULL or
#' `numeric(0)` therefore produced rows with different column sets, and the
#' `rbind` that builds `gr_models()` failed. Every registry field that becomes a
#' data-frame column goes through this.
#' @noRd
as_num1 <- function(x, default = NA_real_) {
  force(x)   # see clamp(): forcing inside suppressWarnings() eats the caller's warnings
  if (is.null(x) || length(x) == 0L) return(default)
  x <- suppressWarnings(as.numeric(x)[1])
  if (is.na(x)) default else x
}

#' @noRd
as_int1 <- function(x, default = NA_integer_) {
  x <- as_num1(x, NA_real_)
  if (is.na(x) || is.infinite(x)) return(default)
  # The range test has to come BEFORE the coercion, not after: as.integer(3e9)
  # is NA with a warning, so the is.na() guard above ran on the value that could
  # not yet be NA and the function returned the NA its own contract says it
  # never returns. gr_screen(screen_tokens = 3e9) then marked every document in
  # the corpus "failed" with "missing value where TRUE/FALSE needed".
  if (x > .Machine$integer.max || x < -.Machine$integer.max) return(default)
  as.integer(x)
}

#' Is `x` a usable, non-blank single string?
#' @noRd
is_nonblank <- function(x) {
  !is.null(x) && length(x) == 1L && is.character(x) && !is.na(x) && has_visible(x)
}

#' The white space a line can be made of besides ASCII space and tab: the
#' no-break space, the Ogham space, the en quad to the hair space, the narrow
#' no-break space, the medium mathematical space and the ideographic space. As
#' the inside of a regex character class.
#' @noRd
.gr_uspace <- "\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000"

#' Whether each string has a character that is not white space.
#'
#' `nzchar(trimws(x))` asked this with a regular expression, which stops with
#' "input string 1 is invalid UTF-8" on bytes in another encoding (a question
#' read from a CP1252 file), so a check that only asks whether anything is
#' there crashed the call. And trimws() strips ASCII space alone, so a line of
#' no-break or ideographic spaces, which is how HTML and Word exports and
#' Chinese and Japanese text leave a blank line, counted as content. The bytes
#' are looked at first; only a string whose first byte past ASCII space is not
#' ASCII can still be all space, and only that is read as characters. Bytes
#' that are not valid UTF-8 are content.
#' @noRd
has_visible <- function(x) {
  x <- as.character(x)
  out <- !is.na(x) & grepl("[^ \t\r\n]", x, perl = TRUE, useBytes = TRUE)
  chk <- which(out & grepl("^[ \t\r\n]*[^\\x01-\\x7f]", x, perl = TRUE, useBytes = TRUE))
  chk <- chk[validUTF8(x[chk])]
  if (length(chk)) {
    out[chk] <- grepl(sprintf("[^ \t\r\n\u2028\u2029%s]", .gr_uspace), mark_utf8(x[chk]),
                      perl = TRUE)
  }
  out
}

#' Fall back to a default when a setting is missing, and say so.
#'
#' `clamp()` maps NA to the low end of the range, which is right for a bound and
#' wrong for a setting: it silently picks whichever extreme happens to be `lo`.
#' @noRd
na_default <- function(x, default, name) {
  # Not just NA: anything that cannot become a number lands on `lo` too, and
  # `gr_read_spec(mmr = "abc")` selecting pure diversity is the same defect as
  # `mmr = NA` doing it.
  usable <- length(x) == 1L && !is.na(x) &&
    (is.numeric(x) || is.finite(suppressWarnings(as.numeric(x))))
  if (usable) return(x)
  if (!identical(x, default)) {
    gr_warn(sprintf("`%s` is missing or not a single value; using the default (%s).",
                    name, format(default)), class = "gr_bad_setting")
  }
  default
}

#' Vectorised, NA-safe isTRUE.
#' @noRd
isTRUE_vec <- function(x) !is.na(x) & as.logical(x)

#' Warn when a `...` name looks like a misspelt formal.
#'
#' `gr_read_spec()` and `gr_segment_spec()` keep a `...` because a custom reader
#' or segmenter needs somewhere to put its own settings -- `fields`, `include`,
#' `screen_tokens` and the rest all arrive that way. The cost is that a TYPO
#' lands there too: `gr_read_spec("retrieve", topk = 8)` is accepted in full,
#' stores a `topk` nobody reads, and leaves `top_k` at its default of 6. The run
#' then works perfectly and answers the wrong question, which is the failure this
#' package spends most of its guards trying not to have.
#'
#' R's own partial matching catches the prefix cases (`max_token` finds
#' `max_tokens`) and nothing else, so this covers the rest: a name one edit away
#' from a formal, or the same name written with different case or punctuation.
#' It warns rather than errors, because the escape hatch has to stay open for
#' the field that really is new.
#' @noRd
warn_near_miss <- function(dots, formals, what) {
  nms <- names(dots)
  nms <- nms[nzchar(nms %||% "")]
  if (!length(nms)) return(invisible(NULL))
  formals <- setdiff(formals, "...")
  flat <- function(x) tolower(gsub("[._]", "", x))
  hits <- lapply(nms, function(nm) {
    if (nm %in% formals) return(character(0))
    same <- formals[flat(formals) == flat(nm)]
    near <- formals[as.integer(utils::adist(nm, formals)) <= 1L]
    unique(c(same, near))
  })
  bad <- which(lengths(hits) > 0L)
  for (i in bad) {
    gr_warn(sprintf(paste0("`%s` is not a %s setting, but `%s` is. If that is a typo the ",
                           "real setting keeps its default and the run will look fine. Passed ",
                           "through as given."),
                    nms[i], what, paste(hits[[i]], collapse = "` or `")),
            class = "gr_near_miss")
  }
  invisible(NULL)
}

#' Vectorised, NA-safe "has visible content".
#' @noRd
has_content <- function(x) {
  if (is.null(x) || length(x) == 0L) return(logical(0))
  x <- vapply(x, as_chr1, character(1), USE.NAMES = FALSE)
  has_visible(x)
}

#' Safe integer sequence: `seq_len2(from, to)` is empty when `to < from`.
#'
#' Replaces the `2:length(x)` idiom, which silently counts *down* when
#' `length(x) < 2` and was a live crash in `chunk_text_semantic()`.
#' @noRd
seq_between <- function(from, to) {
  if (!is.finite(from) || !is.finite(to) || to < from) return(integer(0))
  seq.int(from, to)
}

#' Clamp a numeric into [lo, hi], announcing the change.
#'
#' Silently rewriting a user's parameter is how v1 fed documents to the model
#' backwards. Every spec constructor clamps through this, so an out-of-range
#' setting is always reported rather than quietly replaced.
#' @noRd
clamp_warn <- function(x, lo, hi, what, integer = TRUE) {
  out <- clamp(x, lo, hi)
  if (integer) out <- as.integer(out)
  same <- tryCatch(isTRUE(all.equal(as.numeric(x), as.numeric(out))), error = function(e) FALSE)
  if (!same) {
    gr_warn(sprintf("`%s` %s is outside [%s, %s]; using %s.",
                    what, format(x), format(lo), format(hi), format(out)),
            class = "gr_clamped")
  }
  out
}

#' Clamp a numeric into [lo, hi].
#' @noRd
clamp <- function(x, lo = -Inf, hi = Inf) {
  # force() FIRST, outside suppressWarnings. `x` arrives as a promise, and
  # forcing it inside suppressWarnings() swallows every warning raised while
  # EVALUATING the argument, not merely the coercion warning this is meant to
  # quiet -- so `clamp_warn(na_default(mmr, 1, "mmr"), 0, 1, "mmr")` silently
  # ate na_default()'s "using the default" warning, and any other
  # clamp(f(...)) would have eaten f()'s warnings too. Same shape as
  # `expect_warning(suppressWarnings(...))` never firing: the inner handler is
  # established first and wins.
  force(x)
  x <- suppressWarnings(as.numeric(x))
  # `||` short-circuits on a scalar, so a length-2 x reached `is.na(x)` and R
  # >= 4.3 stopped with "'length = 2' in coercion to 'logical(1)'" -- a message
  # naming neither the setting nor the function, from inside gr_budget(), for
  # every read in the session. A setting that is not one number is a setting to
  # fix, so say so.
  if (length(x) > 1L) {
    gr_abort(sprintf("Expected a single number, got %d values.", length(x)),
             class = "gr_bad_setting")
  }
  if (length(x) == 0L || is.na(x)) x <- lo
  min(max(x, lo), hi)
}

#' Stop with a class so callers can catch package errors specifically.
#' @noRd
gr_abort <- function(msg, class = "gr_error", ...) {
  stop(structure(
    class = c(class, "gr_error", "error", "condition"),
    list(message = msg, call = sys.call(-1), ...)
  ))
}

#' Emit a warning with a package class.
#' @noRd
gr_warn <- function(msg, class = "gr_warning", ...) {
  # sys.parent(), not -1: when the call is wrapped in withCallingHandlers() to
  # record it, -1 is that wrapper, and the console named it instead of the
  # function the user called.
  warning(structure(
    class = c(class, "gr_warning", "warning", "condition"),
    list(message = msg, call = sys.call(sys.parent()), ...)
  ))
  invisible(NULL)
}

#' Record the package's warnings as they are raised, without muffling them.
#'
#' A warning printed at the console is gone once the script moves on, and in a
#' run over a folder it cannot be tied to the document that raised it. Results
#' keep their own copy: `record` is a calling handler for `gr_warning`, and
#' `get()` returns the messages named by each condition's most specific class.
#' The warning still reaches the console as before.
#' @noRd
warning_recorder <- function() {
  env <- new.env(parent = emptyenv())
  env$msg <- character(0)
  env$cls <- character(0)
  list(
    record = function(w) {
      # One valid string per warning, whatever the message was: a zero-length
      # or two-element message would otherwise shift every name after it, and
      # bytes in another encoding would break printing later.
      env$msg <- c(env$msg, to_utf8(as_chr1(conditionMessage(w))))
      env$cls <- c(env$cls, class(w)[1])
      invisible(NULL)
    },
    get = function() stats::setNames(env$msg, env$cls)
  )
}

#' Verbosity-aware message.
#' @noRd
gr_msg <- function(...) {
  if (isTRUE(gr_options("verbose"))) message(...)
  invisible(NULL)
}

#' Label bytes that ARE valid UTF-8 as UTF-8, without converting anything.
#'
#' `enc2utf8()` is a no-op on an unlabelled string in a non-UTF-8 locale, and
#' `validUTF8()` then trusts the absent label -- the same trap that made
#' `to_utf8()`'s transcoding path dead code. Anything that decodes code points
#' (`utf8ToInt`, a `(*UCP)` regex) needs the label to be right, or it silently
#' falls back to counting bytes and gives a different answer on a different
#' machine. Cheap: it touches only the strings that need it.
#' @noRd
mark_utf8 <- function(x) {
  if (!length(x)) return(x)
  x <- as.character(x)
  need <- !is.na(x) & Encoding(x) != "UTF-8" & validUTF8(x)
  if (any(need)) { tmp <- x[need]; Encoding(tmp) <- "UTF-8"; x[need] <- tmp }
  x
}

#' Coerce text to valid UTF-8, whatever it arrived as.
#'
#' Latin-1 and CP1252 exports are common in the documents this package targets,
#' and a non-UTF-8 locale marks even ASCII-adjacent strings "unknown". Either
#' made the perl regexes throw "input string 1 is invalid UTF-8" from deep
#' inside cleaning, with no class and no guidance.
#' @noRd
to_utf8 <- function(x) {
  if (!length(x)) return(character(0))
  x <- as.character(x)

  # LABEL FIRST. `enc2utf8()` treats an UNMARKED string as *native*, so in a
  # non-UTF-8 locale it re-encodes bytes that were already perfectly valid
  # UTF-8 -- corrupting them, and leaving the result neither valid UTF-8 nor
  # labelled. Everything downstream then diverged by locale: the ligature and
  # smart-quote cleaners stopped matching, `utf8ToInt()` fell back to counting
  # bytes, and the SAME document produced a different token count, different
  # chunk boundaries and a different cost estimate on a different machine.
  out <- mark_utf8(x)

  # Anything R has explicitly labelled latin1 is converted, not just relabelled.
  lat <- which(Encoding(out) == "latin1")
  if (length(lat)) out <- mark_utf8(replace(out, lat, enc2utf8(out[lat])))

  # Whatever is still not valid UTF-8 is genuinely mis-encoded bytes.
  bad <- which(is.na(out) | !validUTF8(out))
  if (length(bad)) {
    pending <- x[bad]
    fixed <- rep(NA_character_, length(bad))
    fixed[is.na(pending)] <- ""
    # CP1252 before latin1: the two agree except on 0x80-0x9F, where Windows
    # text means smart quotes, dashes and ellipses and latin1 means C1 control
    # characters. latin1 maps all 256 bytes, so it is the catch-all.
    for (from in c("CP1252", "latin1")) {
      todo <- which(is.na(fixed))
      if (!length(todo)) break
      cand <- suppressWarnings(iconv(pending[todo], from = from, to = "UTF-8"))
      good <- !is.na(cand) & validUTF8(cand)
      if (any(good)) fixed[todo[good]] <- cand[good]
    }
    # Last resort: drop the bytes that cannot be interpreted at all. Lossy, but
    # a document with three mangled characters beats an aborted run.
    todo <- which(is.na(fixed))
    if (length(todo)) {
      cand <- suppressWarnings(iconv(pending[todo], from = "UTF-8", to = "UTF-8", sub = ""))
      fixed[todo] <- ifelse(is.na(cand), "", cand)
    }
    out <- replace(out, bad, fixed)
  }
  out[is.na(out)] <- ""
  # Label again, then normalise newlines, then label once more: every base-R
  # string operation between here and the caller can drop the mark in a
  # non-UTF-8 locale.
  mark_utf8(normalise_newlines(mark_utf8(out)))
}

#' Normalise CRLF and lone CR to LF.
#'
#' Every structural regex in this package -- paragraph splitting, heading
#' detection, page-number and running-head removal -- is anchored on `\n`. A file
#' saved on Windows arrives as `\r\n`, so `\n[ \t]*\n` never matched and the
#' whole document became a single block: one chunk, one enormous prompt, and
#' every structure-aware segmenter silently degraded to `stuff`.
#' @noRd
normalise_newlines <- function(x) {
  if (!length(x)) return(x)
  # useBytes: CR and LF are ASCII, so this substitution is byte-safe, and it is
  # reached from paths that have not been transcoded yet -- a regex engine given
  # not-yet-valid UTF-8 aborts the whole ingest with "input string 1 is invalid
  # UTF-8". Bail out early when there is nothing to do, which is the common case.
  if (!any(grepl("\r", x, fixed = TRUE, useBytes = TRUE))) return(x)
  enc <- Encoding(x)
  out <- gsub("\r\n?", "\n", x, perl = TRUE, useBytes = TRUE)
  Encoding(out) <- enc
  out
}

#' `strsplit(x, pattern, perl = TRUE)[[1]]` for one string, in time in
#' proportion to its length.
#'
#' strsplit() with a Perl pattern starts again on what is left after each
#' piece, and took time in proportion to the length times the number of
#' pieces: 16,000 paragraphs took six seconds to find, and a long block as
#' long to cut into sentences. The places are marked in one pass with gsub()
#' instead, which also keeps what comes before each place in view of a
#' look-behind, and the marks are split on as bytes. A string that already
#' holds the mark is split the old way.
#' @noRd
split_perl <- function(x, pattern) {
  if (is.na(x) || grepl("\u0004", x, fixed = TRUE, useBytes = TRUE)) {
    return(strsplit(x, pattern, perl = TRUE)[[1]])
  }
  out <- strsplit(gsub(pattern, "\u0004", x, perl = TRUE), "\u0004", fixed = TRUE,
                  useBytes = TRUE)[[1]]
  # Split as bytes, the pieces come back unlabelled.
  if (identical(Encoding(x), "latin1")) {
    Encoding(out) <- "latin1"
    out
  } else mark_utf8(out)
}

#' Split text into words, dropping the empty leading token that
#' `strsplit(" a", "\\s+")` produces.
#' @noRd
words_of <- function(text) {
  text <- as_chr1(text)
  if (!has_visible(text)) return(character(0))
  # Bytes that are not valid UTF-8 are split as bytes: a regex reading them as
  # characters stops the call.
  bytes <- !validUTF8(text)
  w <- unlist(strsplit(text, "[[:space:]]+", useBytes = bytes), use.names = FALSE)
  w[nzchar(w)]
}

#' Cosine similarity between two numeric vectors. Returns 0 (not NaN) for
#' zero-norm inputs.
#' @noRd
cosine_similarity <- function(a, b) {
  if (is.null(a) || is.null(b)) return(0)
  n <- min(length(a), length(b))
  if (n == 0L) return(0)
  a <- as.numeric(a[seq_len(n)]); b <- as.numeric(b[seq_len(n)])
  da <- sqrt(sum(a * a)); db <- sqrt(sum(b * b))
  if (!is.finite(da) || !is.finite(db) || da == 0 || db == 0) return(0)
  as.numeric(sum(a * b) / (da * db))
}

#' Generate a run identifier without touching the global RNG stream.
#'
#' The previous code called `set.seed()` inside `compute_embedding()`, silently
#' destroying reproducibility of anything else in the user's session. Nothing in
#' this package may call `set.seed()`; where randomness is needed, use a
#' local, restored RNG (see `with_private_rng()`).
#'
#' Two ids made in the same millisecond were told apart only by the clock
#' going into the hash, which R before 4.3 turned into text to the whole
#' second; and the counter meant to separate them was never counted. Two
#' clients built back to back then shared a `.client_id`, the identity the
#' response cache keys on, and one was served the other's answers. The counter
#' now goes up on every call, so no two ids of a session hash the same input.
#' `now` is for tests.
#' @noRd
gr_new_id <- function(prefix = "run", now = Sys.time()) {
  gr_state$counter <- (gr_state$counter %||% 0) + 1
  paste0(prefix, "_", format(now, "%Y%m%d%H%M%OS3"), "_",
         substr(gr_hash(list(format(now, "%Y%m%d%H%M%OS6"), Sys.getpid(), gr_state$counter)),
                1, 6))
}

#' Run an expression with a private RNG stream, restoring the caller's state.
#' @noRd
with_private_rng <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv(), inherits = FALSE) else NULL
  on.exit({
    if (had) assign(".Random.seed", old, envir = globalenv())
    else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }, add = TRUE)
  set.seed(seed)
  force(expr)
}

#' A path expressed relative to a directory, or NA when it is not under it.
#'
#' Both sides are normalised first: a root given as "~/docs" or with a trailing
#' slash must still match a path that `list.files()` returned in full.
#' @noRd
relative_path <- function(path, root) {
  np <- tryCatch(normalizePath(path, winslash = "/", mustWork = FALSE),
                 error = function(e) NA_character_)
  nr <- tryCatch(normalizePath(root, winslash = "/", mustWork = FALSE),
                 error = function(e) NA_character_)
  if (is.na(np) || is.na(nr)) return(NA_character_)
  nr <- sub("/+$", "", nr)
  # `startsWith(np, nr)` alone would match /docs-old against a root of /docs.
  # The separator has to be there.
  if (!startsWith(np, paste0(nr, "/"))) return(NA_character_)
  sub("^/+", "", substring(np, nchar(nr) + 1L))
}

#' @noRd
format_bytes <- function(b) {
  if (!length(b) || is.na(b)) return("unknown size")
  u <- c("B", "KB", "MB", "GB", "TB"); i <- 1L
  while (b >= 1024 && i < length(u)) { b <- b / 1024; i <- i + 1L }
  sprintf("%.1f %s", b, u[i])
}
