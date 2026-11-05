# core-transport-tokenize.R -- pluggable token counting.
#
# WHY THIS FILE EXISTS
# The old `estimate_token_count()` counted whitespace-separated words. For
# English that undercounts real BPE tokens by roughly 1.3x, and far more for
# code, URLs, numbers, and non-Latin scripts. Every context-budget calculation
# in the package was built on top of it, so requests that the code believed fit
# comfortably were rejected by the API with HTTP 400 -- after the retries had
# been paid for.
#
# Token counting is now:
#   * pluggable       -- swap in a real BPE tokenizer when one is available;
#   * conservative    -- the default heuristic is deliberately biased to
#                        OVERCOUNT, because overcounting wastes a little context
#                        while undercounting produces a hard API failure;
#   * script-aware    -- CJK and other dense scripts are counted per-character.

#' Register or inspect the active tokenizer
#'
#' @param name One of the built-in tokenizers (`"heuristic"`, `"words"`,
#'   `"chars"`, `"tiktoken"`) or a name previously registered with a custom
#'   function.
#' @param fn Optional. A function taking a character vector and returning an
#'   integer vector of token counts. Supplying it registers a custom tokenizer
#'   under `name`.
#' @return Invisibly, the name of the newly active tokenizer.
#' @seealso [gr_tokenizer()], [gr_count_tokens()], [gr_budget()]
#' @family cost and token functions
#' @export
#' @examples
#' old <- gr_tokenizer()
#' gr_set_tokenizer("heuristic")
#' gr_count_tokens("the quick brown fox")
#'
#' # Register your own; budgets recompute against it immediately.
#' gr_set_tokenizer("naive_words",
#'                  function(x) lengths(strsplit(trimws(x), "\\s+")))
#' gr_count_tokens("the quick brown fox")
#' gr_set_tokenizer(old)
gr_set_tokenizer <- function(name, fn = NULL) {
  if (!is.null(fn)) {
    if (!is.function(fn)) gr_abort("`fn` must be a function.")
    gr_state$tokenizers <- utils::modifyList(gr_state$tokenizers %||% list(),
                                             stats::setNames(list(fn), name))
  }
  known <- c("heuristic", "words", "chars", "tiktoken", names(gr_state$tokenizers %||% list()))
  if (!name %in% known) {
    gr_abort(sprintf("Unknown tokenizer '%s'. Available: %s.", name,
                     paste(unique(known), collapse = ", ")))
  }
  if (identical(name, "tiktoken") && !tiktoken_available()) {
    gr_abort(paste0("Tokenizer 'tiktoken' needs the reticulate package and a Python ",
                    "'tiktoken' install. Falling back is not automatic here because a ",
                    "silent fallback would change every budget calculation."))
  }
  gr_options(tokenizer = name)
  invisible(name)
}

#' The active tokenizer
#'
#' @return The name of the tokenizer currently in use, visibly.
#' @seealso [gr_set_tokenizer()], [gr_count_tokens()]
#' @family cost and token functions
#' @export
#' @examples
#' gr_tokenizer()
gr_tokenizer <- function() gr_options("tokenizer")

#' Count tokens in text
#'
#' Vectorised over `text`. Always returns a non-negative integer vector of the
#' same length; blank and `NA` entries count as 0.
#'
#' The default `"heuristic"` tokenizer is a deliberate **over-estimate**, not an
#' exact count: it classifies each word, sums the per-script contributions, and
#' adds a small per-message framing allowance. For numbers, tables, code and
#' short lines it also counts the pieces a BPE tokenizer splits text into first
#' (digit groups, punctuation runs, line breaks, indentation) and keeps the
#' larger figure, line by line. Overcounting wastes a little context;
#' undercounting produces a hard API failure after you have paid for the
#' request. Rare long words (technical and medical vocabulary) can still come in
#' under the real count, by about a tenth for a table of medical terms; that is
#' what the `safety_margin` of [gr_budget()] is for.
#'
#' For counts from OpenAI's own tokenizer install reticulate plus Python
#' `tiktoken` and call `gr_set_tokenizer("tiktoken")`. Given `model`, it counts
#' in that model's encoding. Without one, which is how the package's own budgets
#' call it, it counts in both encodings current OpenAI models use (`cl100k_base`
#' and `o200k_base`) and keeps the larger, so the count holds for any of them.
#' Models from other providers tokenize differently, and for them it is an
#' estimate without the heuristic's padding. Text that spells a special token
#' (`<|endoftext|>`, in a paper about language models) is counted as the plain
#' text it is.
#'
#' @param text Character vector.
#' @param model Optional model id; used only by tokenizers that are
#'   encoding-specific (e.g. `"tiktoken"`).
#' @return Integer vector of token counts: under the default tokenizer, an
#'   estimate built to err high (see above for the one kind of text where it
#'   can fall short).
#' @seealso [gr_set_tokenizer()], [gr_truncate_tokens()], [gr_budget()]
#' @family cost and token functions
#' @export
#' @examples
#' gr_count_tokens(c("the quick brown fox", "", "a much longer sentence than that one"))
#'
#' # Compare tokenizers on the same text.
#' old <- gr_tokenizer()
#' vapply(c("heuristic", "words", "chars"), function(t) {
#'   gr_set_tokenizer(t); gr_count_tokens("the quick brown fox jumps")
#' }, integer(1))
#' gr_set_tokenizer(old)
gr_count_tokens <- function(text, model = NULL) {
  if (is.null(text) || length(text) == 0L) return(integer(0))
  text <- vapply(text, as_chr1, character(1), USE.NAMES = FALSE)
  which <- gr_options("tokenizer")
  custom <- (gr_state$tokenizers %||% list())[[which]]
  out <- if (!is.null(custom)) {
    as.integer(custom(text))
  } else {
    switch(which,
      heuristic = tok_heuristic(text),
      words     = vapply(text, function(x) length(words_of(x)), integer(1), USE.NAMES = FALSE),
      chars     = as.integer(ceiling(nchar_or_bytes(text) / 4)),
      tiktoken  = tok_tiktoken(text, model),
      gr_abort(sprintf("Unknown tokenizer '%s'.", which))
    )
  }
  if (length(out) != length(text)) {
    gr_abort("Tokenizer returned the wrong number of counts; it must be vectorised.")
  }
  out[is.na(out) | out < 0L] <- 0L
  as.integer(out)
}

#' Characters in each string, or bytes where the string cannot be read as
#' characters.
#'
#' `nchar(type = "chars")` stops with "invalid multibyte string" on bytes in
#' another encoding (a CP1252 string in a UTF-8 session), so the "chars"
#' tokenizer failed the call on text the heuristic counts by its bytes. A
#' character is at least one byte, so counting bytes never counts fewer.
#' @noRd
nchar_or_bytes <- function(x) {
  n <- nchar(x, type = "chars", allowNA = TRUE)
  bad <- is.na(n) & !is.na(x)
  if (any(bad)) n[bad] <- nchar(x[bad], type = "bytes")
  n
}

#' Whether each string has a character other than ASCII white space, asked of
#' its bytes.
#'
#' The question `nzchar(trimws(x))` asks, without the regular expression that
#' stops with "input string 1 is invalid UTF-8" on bytes in another encoding.
#' Only ASCII white space is blank here, as it was: a line of no-break spaces
#' costs tokens, and a count must not come in under.
#' @noRd
has_nonspace_bytes <- function(x) !is.na(x) & grepl("[^ \t\r\n]", x, useBytes = TRUE)

#' Conservative script-aware token estimate.
#'
#' Blends three signals and sums their contributions, then adds a small constant for
#' per-message chat overhead. Calibration targets (cl100k/o200k-family):
#'   * English prose:        ~1.30 tokens/word, ~0.25 tokens/char
#'   * Code and identifiers: ~0.77 tokens/char (L / 1.3)
#'   * CJK:                  ~1.0 tokens/char
#' @noRd
tok_heuristic <- function(text) {
  # Label valid UTF-8 as UTF-8 BEFORE decoding. `enc2utf8()` on an unlabelled
  # string is a no-op in a non-UTF-8 locale, so `utf8ToInt()` failed and the
  # byte fallback below charged a 1-codepoint em dash as 3 characters. The same
  # document then produced different token counts on different machines -- and
  # therefore different budgets, different chunk boundaries and different cost
  # estimates -- purely from the locale R happened to start in. Measured: 16
  # tokens labelled versus 24 unlabelled, for identical bytes.
  text <- mark_utf8(text)
  vapply(text, function(x) {
    # Asked of the bytes: trimws() is a regular expression, and it stopped the
    # count of a CP1252 string in a UTF-8 session with "invalid UTF-8" before
    # the byte fallback below could count it.
    if (!has_nonspace_bytes(x)) return(0L)
    # Work on code points, so multibyte text is measured rather than its byte
    # length. The byte fallback now fires only for genuinely undecodable input.
    cp <- tryCatch(utf8ToInt(x), error = function(e) NULL)
    if (is.null(cp) || anyNA(cp)) cp <- as.integer(charToRaw(x))
    n <- length(cp); if (!n) return(0L)

    # Classify by how densely each script tokenizes. The previous version
    # treated only U+1100-U+FFEF as dense, excluding Cyrillic, Greek, Hebrew,
    # Arabic, Devanagari, Thai and every astral character including all emoji.
    # Those under-counted by up to 5.5x, and since every budget is built on this
    # number, a prompt believed to fit could be 1.5x the whole context window.
    is_ascii  <- cp < 128L
    is_astral <- cp >= 0x10000L
    is_cjk    <- (cp >= 0x2E80L & cp <= 0xA4CFL) | (cp >= 0xAC00L & cp <= 0xD7AFL) |
                 (cp >= 0xF900L & cp <= 0xFAFFL) | (cp >= 0xFE30L & cp <= 0xFFEFL) |
                 (cp >= 0x3040L & cp <= 0x30FFL)
    n_astral <- sum(is_astral); n_cjk <- sum(is_cjk)
    n_other  <- sum(!is_ascii & !is_astral & !is_cjk)

    # ASCII is estimated per whitespace-delimited word, because ordinary prose
    # (~4 chars/token) and dense strings such as base64, hex, ids and minified
    # JSON (~1.6 chars/token) cannot share one divisor without either
    # under-counting the dense case or wasting a third of the context on prose.
    ascii_est <- 0
    if (any(is_ascii)) {
      acp <- cp[is_ascii]
      a <- intToUtf8(acp)
      g <- gregexpr("[^[:space:]]+", a)[[1]]
      if (g[1] > 0L) {
        L <- attr(g, "match.length")
        w <- substring(a, g, g + L - 1L)
        # "Normal" = a plain word, optionally capitalised, optionally with
        # attached punctuation. Everything else is treated as dense.
        normal <- grepl("^[[:punct:]]*[A-Za-z][a-z]*[[:punct:]]*$", w, perl = TRUE)
        words <- list(start = as.integer(g), cost = ifelse(normal, pmax(1, L / 4.0), L / 1.3))
        # The larger of the per-word figure and the pieces floor (see
        # tok_pieces()), line by line: taken over the whole text, the prose in
        # a chunk over-counted enough to hide the table under-counted beside
        # it.
        ascii_est <- per_line_max(acp, words, tok_pieces(a, acp))
      }
    }
    est <- ascii_est + n_cjk * 1.15 + n_other * 1.15 + n_astral * 6.5
    # Rounded before ceiling(): the costs are fractions (n/3, L/4, L/1.3), and
    # sum() accumulates in long double, which is 80 bits on x86-64 Linux and 64
    # on Apple silicon. A total that sits on a whole number came out a hair
    # above it on one and below on the other, so the same text counted one
    # token apart on two machines, and chunk boundaries and budgets with it.
    as.integer(ceiling(round(est, 6)) + 3L)   # +3 for per-message framing overhead
  }, integer(1), USE.NAMES = FALSE)
}

#' A floor under the ASCII estimate, from the pieces a BPE tokenizer cuts
#' text into before it merges anything.
#'
#' cl100k and o200k split text into pieces first, and every piece is at least
#' one token: digits never join the space before them and go in groups of at
#' most three, and every run of punctuation, every line break and every run of
#' indentation is a piece of its own. The per-word estimate charges a digit
#' 0.77 of a token and a line break nothing, so against real cl100k counts it
#' came in under on exactly the text that fills a budget fastest: 0.83x on an
#' aligned table, 0.71x on tab-separated values, 0.39x on a list of single
#' digits, 0.90x on prose broken into short punctuated lines. That is the
#' direction that overruns the window. Pieces are found with the cl100k
#' pattern (letters and digits being ASCII here) and charged: a digit group or
#' a whitespace run 1; a punctuation run one per three characters, at least 1;
#' a letter run 1 up to seven letters and one more per three letters past that
#' (common words are one token, long technical ones several), plus 1 when a
#' character other than a space leads it ("\tyes", "(x"), which the vocabulary
#' seldom joins. Ordinary prose, where the per-word figure is the larger, is
#' unchanged. Measured against cl100k and o200k this lands at or above the
#' real count on tables, digit lists, tab-separated values and short
#' punctuated lines. Rare long words are what neither figure covers: a table
#' of medical terms still came in about 10% under, which is what the budget's
#' safety margin is for.
#' @noRd
tok_pieces <- function(a, cp = utf8ToInt(a)) {
  g <- gregexpr(.gr_piece_pattern, a, perl = TRUE)[[1]]
  if (g[1] < 0L) return(list(start = integer(0), cost = numeric(0)))
  # Classified by code point rather than by extracting each piece as a string:
  # this runs on every count, and the string version made counting five times
  # slower.
  n <- attr(g, "match.length")
  start <- as.integer(g)
  first <- cp[start]
  last <- cp[start + n - 1L]
  second <- cp[pmin(start + 1L, length(cp))]
  is_alpha <- function(x) (x >= 65L & x <= 90L) | (x >= 97L & x <= 122L)
  is_space <- function(x) x == 32L | (x >= 9L & x <= 13L)
  alpha <- is_alpha(last)                        # a letter run, or 's 't 're ...
  digit <- !alpha & last >= 48L & last <= 57L    # a group of one to three digits
  punct <- !alpha & !digit & (!is_space(first) | (n > 1L & !is_space(second)))
  led <- alpha & !is_alpha(first)                # " word", "(word", "'s"
  cost <- rep(1, length(n))                      # digit groups and whitespace runs
  cost[punct] <- pmax(1, n[punct] / 3)
  cost[alpha] <- pmax(1, (n[alpha] - led[alpha] - 4) / 3) +
    (led[alpha] & first[alpha] != 32L & first[alpha] != 39L)
  list(start = start, cost = cost)
}

#' Sum, over the lines of `cp`, the larger of two estimates of each line.
#'
#' `a` and `b` are lists of `start` (a position in `cp`) and `cost`.
#' @noRd
per_line_max <- function(cp, a, b) {
  nl <- which(cp == 10L)
  if (!length(nl)) return(max(sum(a$cost), sum(b$cost)))
  k <- length(nl) + 1L
  by_line <- function(x) {
    v <- numeric(k)
    if (!length(x$cost)) return(v)
    s <- rowsum(x$cost, findInterval(x$start, nl) + 1L)
    v[as.integer(rownames(s))] <- s[, 1L]
    v
  }
  sum(pmax(by_line(a), by_line(b)))
}

#' cl100k's pre-tokenizer, with its letter and digit classes written for the
#' ASCII text tok_pieces() is given.
#' @noRd
.gr_piece_pattern <- paste0("'(?i:[sdmt]|ll|ve|re)|[^\\r\\nA-Za-z0-9]?[A-Za-z]+|[0-9]{1,3}|",
                            " ?[^\\sA-Za-z0-9]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+")

#' @noRd
tiktoken_available <- function() {
  requireNamespace("reticulate", quietly = TRUE) &&
    isTRUE(try(reticulate::py_module_available("tiktoken"), silent = TRUE))
}

#' @noRd
tok_tiktoken <- function(text, model = NULL) {
  if (!tiktoken_available()) gr_abort("tiktoken backend unavailable.")
  # Python is handed text, and bytes in another encoding (a CP1252 string in a
  # UTF-8 session) are not text to it; they are transcoded the way ingestion
  # does, a character for each byte, so the count does not come in under.
  bad <- !validUTF8(text)
  if (any(bad)) text[bad] <- to_utf8(text[bad])
  counts <- lapply(tiktoken_encodings(model), function(enc) {
    vapply(text, function(x) {
      if (!nzchar(x)) return(0L)
      # disallowed_special = (): tiktoken's default raises a ValueError on any
      # text that spells a special token, so one ML paper quoting
      # "<|endoftext|>" aborted the whole pipeline at its first count. Document
      # text is text; it is encoded as such.
      as.integer(length(enc$encode(x, disallowed_special = list())))
    }, integer(1), USE.NAMES = FALSE)
  })
  do.call(pmax, counts)
}

#' The encodings a tiktoken count is taken in.
#'
#' Every call site in the package counts without a model, so this always used
#' gpt-4o's o200k_base -- wrong for the cl100k models still in the registry
#' (gpt-4, gpt-4-turbo, gpt-3.5), which need more tokens for the same
#' non-English text, and with none of the heuristic's padding to absorb it.
#' Without a model, or for one tiktoken does not know, both encodings current
#' OpenAI models use are returned and the larger count kept.
#' @noRd
tiktoken_encodings <- function(model = NULL) {
  tk <- reticulate::import("tiktoken", delay_load = TRUE)
  if (!is.null(model)) {
    enc <- tryCatch(tk$encoding_for_model(as_chr1(model)), error = function(e) NULL)
    if (!is.null(enc)) return(list(enc))
  }
  list(tk$get_encoding("cl100k_base"), tk$get_encoding("o200k_base"))
}
