# doc-read-score.R: lexical scores of chunks against a question.

#' Deterministic hashed bag-of-words vectors.
#'
#' An honest fallback: it measures lexical overlap, not meaning. Unlike the code
#' it replaces, it is at least a function of the text's *content*, is
#' deterministic without touching the RNG, and is labelled as non-semantic
#' wherever it is used.
#' @noRd
lexical_embed <- function(texts, dim = 512L) {
  m <- t(vapply(texts, function(tx) {
    w <- lexical_terms(tx, min_chars = 3L)
    v <- numeric(dim)
    if (!length(w)) return(v)
    tf <- table(w)
    for (i in seq_along(tf)) {
      h <- strtoi(substr(gr_hash(names(tf)[i]), 1, 6), 16L)
      slot <- (h %% dim) + 1L
      v[slot] <- v[slot] + (1 + log(as.numeric(tf[i])))
    }
    n <- sqrt(sum(v^2)); if (n > 0) v / n else v
  }, numeric(dim), USE.NAMES = FALSE))
  m
}

#' Cosine similarity of one vector against every row of a matrix.
#' @noRd
cosine_against <- function(mat, vec) {
  if (!is.matrix(mat) || nrow(mat) == 0L) return(numeric(0))
  vec <- as.numeric(vec)
  n <- min(ncol(mat), length(vec))
  if (n == 0L) return(rep(0, nrow(mat)))
  mat <- mat[, seq_len(n), drop = FALSE]; vec <- vec[seq_len(n)]
  dv <- sqrt(sum(vec^2))
  dm <- sqrt(rowSums(mat^2))
  out <- as.numeric(mat %*% vec)
  denom <- dm * dv
  out[denom == 0 | !is.finite(denom)] <- 0
  ok <- denom > 0 & is.finite(denom)
  out[ok] <- out[ok] / denom[ok]
  out
}

#' Okapi BM25 scores for a query against a set of documents.
#'
#' Pure R, no API cost. Used by the `rerank` reader as a cheap prefilter and as
#' the offline path for `retrieve` when embeddings are unavailable.
#' @noRd
bm25_scores <- function(docs, query, k1 = 1.5, b = 0.75) {
  norm <- function(x) lexical_terms(x, min_chars = 2L)
  dt <- lapply(docs, norm)
  q <- unique(norm(query))
  if (!length(q) || !length(dt)) return(rep(0, length(docs)))
  lens <- vapply(dt, length, integer(1))
  avg <- mean(lens[lens > 0]); if (!is.finite(avg) || avg == 0) avg <- 1
  N <- length(dt)
  vapply(seq_along(dt), function(i) {
    d <- dt[[i]]
    if (!length(d)) return(0)
    tf <- table(d)
    sum(vapply(q, function(term) {
      f <- as.numeric(tf[term]); if (is.na(f)) return(0)
      n_q <- sum(vapply(dt, function(dd) term %in% dd, logical(1)))
      idf <- log(1 + (N - n_q + 0.5) / (n_q + 0.5))
      idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * lens[i] / avg))
    }, numeric(1)))
  }, numeric(1))
}

#' The terms of a text for word matching: lowercased runs of letters, marks and
#' digits, in any script.
#'
#' Unicode classes, not POSIX ones. Without `(*UCP)`, PCRE's `[:alnum:]`
#' matches ASCII only, so the old `[^[:alnum:][:space:]]` blanked every letter
#' outside A-Z: a Russian, Greek, Arabic or Chinese document had no terms at
#' all, BM25 scored every chunk 0 and lexical vectors were all zero, so rerank
#' and retrieve picked chunks in document order without saying so, and the
#' German word for "size", with its umlaut and sharp s, became "Gr" and "e".
#' `\p{M}` is in the class because Devanagari, Thai, Arabic and Hebrew write
#' vowels and diacritics as combining marks, and blanking those broke every
#' word apart. For ASCII text nothing changes.
#'
#' Scripts written without spaces between words (Chinese, Japanese, Thai, Lao,
#' Khmer, Myanmar) give one "word" per clause, which matches nothing, so a run
#' of those characters is indexed as overlapping character pairs, the usual
#' unit for matching such text without a dictionary. The pairs are kept
#' whatever `min_chars` says: the floor is there to drop short function words
#' in space-separated scripts.
#' @noRd
lexical_terms <- function(x, min_chars = 2L) {
  x <- gsub("[^\\p{L}\\p{M}\\p{N}\\s]", " ", to_utf8(as_chr1(x)), perl = TRUE)
  w <- lower_text(words_of(x))
  if (!length(w)) return(character(0))
  dense_script <- "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Thai}\\p{Lao}\\p{Khmer}\\p{Myanmar}"
  # A run starts with a character of such a script and carries on through
  # modifier letters and marks (the Japanese long-vowel mark, Thai tone marks).
  run_re <- sprintf("[%s][%s\\p{Lm}\\p{M}]*", dense_script, dense_script)
  dense <- grepl(sprintf("[%s]", dense_script), w, perl = TRUE)
  out <- w[!dense & nchar(w) >= min_chars]
  if (any(dense)) {
    d <- w[dense]
    runs <- unlist(regmatches(d, gregexpr(run_re, d, perl = TRUE)), use.names = FALSE)
    rest <- unlist(lapply(gsub(run_re, " ", d, perl = TRUE), words_of), use.names = FALSE)
    pairs <- unlist(lapply(strsplit(runs, "", fixed = TRUE), function(ch) {
      if (length(ch) < 2L) ch else paste0(ch[-length(ch)], ch[-1L])
    }), use.names = FALSE)
    out <- c(out, rest[nchar(rest) >= min_chars], pairs)
  }
  # Labelled consistently: lexical_embed() hashes each term, and a hash of the
  # same characters differs by encoding label (see key_text()).
  mark_utf8(out)
}
