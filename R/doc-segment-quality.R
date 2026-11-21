# doc-segment-quality.R: how good a segmentation is, measured two ways.
#
# A chunking can be scored against a reference segmentation, a person's
# split of the document into topics, with Pk and WindowDiff, the two error
# rates the topic-segmentation literature reports. And it can be scored on
# what it is for here: whether the retriever, ranking its chunks for a
# question, puts the chunk that holds the answer among the first k. Neither
# calls a model unless the client given embeds.
#
# Pk and WindowDiff follow the definitions in NLTK's nltk.metrics.segmentation
# exactly (windows of k positions over a boundary string, L - k + 1 of them,
# and k by default NLTK's round(L / (2 * boundaries)), raised to 1 where
# NLTK's is 0), so a value here can be checked against NLTK's on the same
# strings.

#' Where a segmentation puts its boundaries, sentence by sentence
#'
#' Turns a segmentation into the boundary sequence [gr_seg_pk()] and
#' [gr_seg_windowdiff()] compare: the document is split into sentences, each
#' sentence is placed in a segment, and position `j` is 1 when sentence
#' `j + 1` is in a later segment than sentence `j`. Two segmentations of one
#' document mapped this way are on the same units and can be compared.
#'
#' A segment is matched on its text with runs of white space made one space,
#' and on a chunk's `source_text` when it has one, so the context line of a
#' `contextual` chunk is not part of the match. When every segment is a
#' verbatim part of the document, each segment and each sentence is located
#' in the document, in order, and a sentence goes to the first segment that
#' holds its first character. A sentence the document repeats, such as
#' "See note 3." at the start of two sections, therefore goes to the segment
#' it occurs in, not to the first segment whose text contains it. A
#' boundary inside a sentence counts at the end of that sentence, and
#' overlap does not add boundaries: a sentence carried into the next chunk
#' stays in the first chunk that holds its start.
#'
#' When a segment is not verbatim (a segmenter that rewrites text, or a
#' reference typed by hand), sentences are matched on text instead: each in
#' the current segment after the text the sentences before it took, or in a
#' later segment; failing that, by its opening, its first 40 characters or
#' its first half when that is shorter. A sentence placed neither way stays
#' in the segment before it and is counted in the `unplaced` attribute.
#'
#' @param x A [gr_chunks] from [gr_segment()], or a character vector of
#'   segments in document order (a reference segmentation, for example the
#'   document's topics as a person split them).
#' @param doc The document `x` segments: a `gr_document` from [gr_ingest()],
#'   or text.
#' @return An integer vector of 0 and 1 with one element per pair of
#'   neighbouring sentences (the number of sentences less one), with
#'   attributes `units` (the number of sentences) and `unplaced`.
#' @seealso [gr_seg_pk()], [gr_seg_windowdiff()], [gr_seg_recall()]
#' @family segmentation functions
#' @export
#' @examples
#' doc <- paste("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
#'              "The chair retired.", sep = "\n\n")
#' gr_seg_boundaries(c("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
#'                     "The chair retired."), doc)
#' ch <- gr_segment(doc, list(method = "sentence", max_tokens = 32))
#' gr_seg_boundaries(ch, doc)
gr_seg_boundaries <- function(x, doc) {
  text <- if (inherits(doc, "gr_document")) doc$text
          else if (is.character(doc) && length(doc) == 1L && !is.na(doc)) doc
          else gr_abort("`doc` must be a gr_document from gr_ingest(), or one string of text.",
                        class = "gr_bad_setting")
  segs <- if (inherits(x, "gr_chunks")) {
    d <- x$chunks
    own <- d[["source_text", exact = TRUE]]
    if (is.null(own)) d$text else ifelse(is.na(own), d$text, own)
  } else if (is.character(x) && length(x) && !anyNA(x)) {
    x
  } else {
    gr_abort("`x` must be a gr_chunks from gr_segment(), or a character vector of segments.",
             class = "gr_bad_setting")
  }
  squash <- function(v) trimws(gsub("\\s+", " ", mark_utf8(v), perl = TRUE))
  units <- squash(sentences_of(text))
  units <- units[nzchar(units)]
  segs <- squash(segs)
  if (length(units) < 2L) {
    gr_abort("The document has fewer than two sentences, so it has no boundaries to compare.",
             class = "gr_bad_setting")
  }
  owner <- seg_owner_by_position(units, segs, squash(text))
  if (is.null(owner)) owner <- seg_owner_by_text(units, segs)
  unplaced <- attr(owner, "unplaced")
  structure(as.integer(diff(owner) != 0L), units = length(units), unplaced = unplaced)
}

#' Place each sentence in a segment by where both sit in the document.
#'
#' Used when every sentence and every segment is found, in order, in the
#' document text (white space squashed); returns NULL otherwise. Sentence `j`
#' is found after sentence `j - 1`. Segment `i` is the occurrence after the
#' start of segment `i - 1` that starts nearest the end of segment `i - 1`,
#' so a segment that overlaps the one before it, or one in a document that
#' repeats itself, lands where it was cut from. A sentence belongs to the
#' first segment, from the previous sentence's on, that holds its first
#' character. Placing by position rather than by text keeps a repeated
#' sentence, such as "See note 3.", in the segment it occurs in.
#' @noRd
seg_owner_by_position <- function(units, segs, doc) {
  find <- function(probe, from) {
    at <- regexpr(probe, substr(doc, from, nchar(doc)), fixed = TRUE)
    if (at < 1L) NA_integer_ else from + as.integer(at) - 1L
  }
  # Every start of `probe` in the document at or after `from`.
  find_all <- function(probe, from) {
    out <- integer(0)
    repeat {
      at <- find(probe, from)
      if (is.na(at)) return(out)
      out <- c(out, at)
      from <- at + 1L
    }
  }
  s_start <- integer(length(units))
  from <- 1L
  for (j in seq_along(units)) {
    at <- find(units[j], from)
    if (is.na(at)) return(NULL)
    s_start[j] <- at
    from <- at + nchar(units[j])
  }
  g_start <- g_end <- integer(length(segs))
  for (i in seq_along(segs)) {
    if (!nzchar(segs[i])) return(NULL)
    if (i == 1L) {
      at <- find(segs[i], 1L)
      if (is.na(at)) return(NULL)
    } else {
      cand <- find_all(segs[i], g_start[i - 1L] + 1L)
      if (!length(cand)) return(NULL)
      at <- cand[which.min(abs(cand - (g_end[i - 1L] + 1L)))]
    }
    g_start[i] <- at
    g_end[i] <- at + nchar(segs[i]) - 1L
  }
  owner <- integer(length(units))
  cur <- 1L
  unplaced <- 0L
  for (j in seq_along(units)) {
    i <- seq.int(cur, length(segs))
    hit <- i[g_start[i] <= s_start[j] & s_start[j] <= g_end[i]]
    if (length(hit)) cur <- hit[1] else unplaced <- unplaced + 1L
    owner[j] <- cur
  }
  structure(owner, unplaced = unplaced)
}

#' Place each sentence in a segment by matching its text, for segments that
#' are not verbatim parts of the document. Sentence `j` is looked for in the
#' current segment after the text the sentences before it took, then in the
#' segments after it; then the same by its opening; then it stays where it is.
#' @noRd
seg_owner_by_text <- function(units, segs) {
  find_from <- function(probe, cur, used) {
    for (ci in seq.int(cur, length(segs))) {
      from <- if (ci == cur) used else 0L
      at <- regexpr(probe, substr(segs[ci], from + 1L, nchar(segs[ci])), fixed = TRUE)
      if (at > 0L) return(c(ci, from + at + nchar(probe) - 1L))
    }
    NULL
  }
  owner <- integer(length(units))
  cur <- 1L
  used <- 0L
  unplaced <- 0L
  for (j in seq_along(units)) {
    hit <- find_from(units[j], cur, used)
    if (is.null(hit)) {
      hit <- find_from(substr(units[j], 1L, min(40L, ceiling(nchar(units[j]) / 2))), cur, used)
    }
    if (is.null(hit)) {
      hit <- c(cur, used)
      unplaced <- unplaced + 1L
    }
    owner[j] <- hit[1]
    cur <- hit[1]
    used <- hit[2]
  }
  structure(owner, unplaced = unplaced)
}

#' Pk and WindowDiff: how far a segmentation's boundaries are from a reference
#'
#' Both slide a window of `k` positions along two boundary sequences of the
#' same length and count the windows where they disagree, as a share of the
#' `L - k + 1` windows of a sequence of length `L`. `gr_seg_pk()` (Beeferman,
#' Berger and Lafferty 1999) counts a window as an error when one sequence
#' has a boundary in it and the other has none. `gr_seg_windowdiff()`
#' (Pevzner and Hearst 2002) counts it when the two have a different number
#' of boundaries in it, so it also sees a window where the hypothesis puts
#' two boundaries and the reference one. Both are 0 for identical sequences
#' and rise towards 1; lower is better.
#'
#' These are the definitions of NLTK's `pk()` and `windowdiff()`, with the
#' same windows and the same default `k`, `round(L / (2 * boundaries))`,
#' rounded half to even as Python rounds. That is NLTK's
#' approximation of half the mean reference segment length. Half the mean
#' length itself, as Beeferman et al. define `k`, is
#' `(L + 1) / (2 * (boundaries + 1))`, since `L` positions describe `L + 1`
#' units in `boundaries + 1` segments. For `"0100"` the default is 2: the
#' reference has 5 units in 2 segments, a mean length of 2.5, and half of
#' that, 1.25, would round to 1. Give `k` to use that figure.
#'
#' The default `k` matches NLTK's except in one case: when every position of
#' the reference is a boundary, `round(L / (2 * L))` is `round(0.5)`, which is
#' 0. NLTK then uses a window of 0 positions and returns 0 for any hypothesis;
#' this function raises `k` to 1. With that exception, and whenever `k` is
#' given, values agree with NLTK's on the same strings.
#'
#' They measure whether chunk edges fall where topics change. A chunker held
#' to a token cap much smaller than the topics has to cut inside them, and
#' both measures count those cuts as errors; that is a cost of the size as
#' much as of the segmenter, so compare segmenters at one size.
#'
#' @param reference,hypothesis Boundary sequences of the same length: strings
#'   of `"0"` and `"1"`, or vectors of 0 and 1 (or `TRUE` and `FALSE`), as
#'   [gr_seg_boundaries()] returns.
#' @param k The window, a whole number from 1 to the sequence length. `NULL`
#'   takes the default above, which needs at least one reference boundary.
#' @return One number from 0 to 1, with the window used as attribute `k`.
#' @references
#' Beeferman, D., Berger, A. and Lafferty, J. (1999). Statistical models for
#' text segmentation. *Machine Learning* 34, 177-210.
#'
#' Pevzner, L. and Hearst, M. A. (2002). A critique and improvement of an
#' evaluation metric for text segmentation. *Computational Linguistics*
#' 28(1), 19-36.
#' @seealso [gr_seg_boundaries()], [gr_seg_recall()]
#' @family segmentation functions
#' @export
#' @examples
#' gr_seg_pk("000100000010", "000010000100", k = 3)
#' gr_seg_windowdiff("000100000010", "000010000100", k = 3)
#' # A window where the hypothesis has one boundary and the reference two is
#' # an error for WindowDiff only.
#' gr_seg_pk("0110", "0100", k = 2)
#' gr_seg_windowdiff("0110", "0100", k = 2)
gr_seg_pk <- function(reference, hypothesis, k = NULL) {
  seg_window_error(reference, hypothesis, k, function(r, h) (r > 0) != (h > 0))
}

#' @rdname gr_seg_pk
#' @export
gr_seg_windowdiff <- function(reference, hypothesis, k = NULL) {
  seg_window_error(reference, hypothesis, k, function(r, h) r != h)
}

#' The shared window count of Pk and WindowDiff: `wrong(r, h)` says, from the
#' number of boundaries each sequence has in a window, whether the window is
#' an error.
#' @noRd
seg_window_error <- function(reference, hypothesis, k, wrong) {
  ref <- seg_boundary_vector(reference, "reference")
  hyp <- seg_boundary_vector(hypothesis, "hypothesis")
  L <- length(ref)
  if (length(hyp) != L) {
    gr_abort(sprintf("`reference` and `hypothesis` must be the same length; they are %d and %d.",
                     L, length(hyp)), class = "gr_bad_setting")
  }
  if (is.null(k)) {
    if (!sum(ref)) {
      gr_abort("The reference has no boundaries, so `k` has no default; give `k`.",
               class = "gr_bad_setting")
    }
    k <- max(1L, as.integer(round(L / (2 * sum(ref)))))
  }
  if (!is.numeric(k) || length(k) != 1L || is.na(k) || k != round(k) || k < 1 || k > L) {
    gr_abort(sprintf("`k` must be a whole number from 1 to %d, the sequence length.", L),
             class = "gr_bad_setting")
  }
  k <- as.integer(k)
  n <- L - k + 1L
  cr <- cumsum(c(0L, ref))
  ch <- cumsum(c(0L, hyp))
  at <- seq_len(n)
  r <- cr[at + k] - cr[at]
  h <- ch[at + k] - ch[at]
  structure(sum(wrong(r, h)) / n, k = k)
}

#' A boundary sequence as an integer vector of 0 and 1.
#' @noRd
seg_boundary_vector <- function(x, what) {
  v <- if (is.character(x) && length(x) == 1L && !is.na(x)) {
    if (!grepl("^[01]+$", x)) {
      gr_abort(sprintf("`%s` as a string must hold only 0 and 1.", what), class = "gr_bad_setting")
    }
    as.integer(strsplit(x, "", fixed = TRUE)[[1]])
  } else if ((is.numeric(x) || is.logical(x)) && length(x) && !anyNA(x) &&
             all(as.numeric(x) %in% c(0, 1))) {
    as.integer(x)
  } else {
    gr_abort(sprintf("`%s` must be a string of 0 and 1, or a vector of 0 and 1.", what),
             class = "gr_bad_setting")
  }
  v
}

#' Retrieval recall at k, per segmenter
#'
#' For each segmenter, cuts each document of a question-answering reference,
#' ranks its chunks for each question the way the `retrieve` reader does,
#' and counts the questions whose answer is in one of the first `k` chunks.
#' This is the share of questions a `retrieve` reader with `top_k = k` could
#' answer, before any model reads anything, so segmenters and chunk sizes can
#' be compared for nothing (with the lexical embedder) or for one embedding
#' request per question and segmenter.
#'
#' A chunk holds the answer when its text (its `source_text`, when it has
#' one) contains one of the item's accepted answers, matched as
#' [gr_scorer_answer()] matches them: case, white space and thousands
#' separators folded, numbers matched whole. An answer cut in two by a chunk
#' edge is in no chunk, and the question counts as a miss at every `k`; the
#' `no_chunk` column counts those questions. Unanswerable items and items
#' with no label are left out.
#'
#' The ranking is cosine similarity on the embeddings `client` gives (see
#' [gr_embed()]), blended with BM25 by `lexical_blend` when the embeddings
#' are lexical, as in [gr_read()]. `read` takes those [gr_read_spec()]
#' settings (`lexical_blend`, `bm25_k1`, `bm25_b`). The `mmr` and
#' `min_score` settings of the reader are not applied: this is the ranking
#' alone.
#'
#' The figures are descriptive. Questions about one document share its
#' chunking, so they are not independent, and no interval is given; compare
#' segmenters on the same questions, and on a split you did not tune on.
#'
#' @param reference A reference from [gr_qa_reference()].
#' @param segmenters The segmentations: a character vector of segmenter
#'   names, or a list of names, [gr_segment_spec()] objects or named lists of
#'   its settings. One spec or one list of settings on its own is one
#'   segmentation. Unnamed entries are named by their method and size, as
#'   `"fixed_32"`.
#' @param k The cut-offs, whole numbers of at least 1.
#' @param client The client that embeds, or `NULL` for the lexical embedder
#'   (and for segmenters that call no model).
#' @param read Named list of [gr_read_spec()] settings for the ranking.
#' @param split The split or splits of `reference` to use.
#' @return A data frame with one row per segmenter and `k`: `segmenter`,
#'   `k`, `hits`, `questions`, `recall`, `no_chunk` (questions whose answer
#'   is in no chunk), `chunks` (mean chunks per document) and `documents`.
#'   Attribute `ranks` holds one row per segmenter and question with the
#'   rank of the first chunk holding the answer (`NA` when none does).
#' @seealso [gr_seg_pk()], [gr_chunk_stats()], [hr_benchmark()]
#' @family segmentation functions
#' @export
#' @examples
#' old <- gr_options(verbose = FALSE, embedder = "lexical")
#' doc <- paste("Revenue was 45.2 million dollars in fiscal 2024.",
#'              "The plant in Leeds made 12,400 units.",
#'              "Staff numbered 310 at year end.", sep = "\n\n")
#' ref <- gr_qa_reference(c(rev = "What was revenue?", units = "How many units?"),
#'                        documents = doc, answers = list("45.2 million", "12,400"),
#'                        split = "test")
#' gr_seg_recall(ref, list(sentence = list(method = "sentence", max_tokens = 40),
#'                         fixed = list(method = "fixed", max_tokens = 32)), k = 1:2)
#' gr_options(old)
gr_seg_recall <- function(reference, segmenters, k = c(1, 3, 5), client = NULL, read = list(),
                          split = "test") {
  check_reference(reference)
  if (!is.numeric(k) || !length(k) || anyNA(k) || any(k < 1) || any(k != round(k))) {
    gr_abort("`k` must be whole numbers of at least 1.", class = "gr_bad_setting")
  }
  k <- sort(unique(as.integer(k)))
  if (!is.null(client) && !inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client() or gr_mock_client(), or be NULL.",
             class = "gr_bad_setting")
  }
  if (!is.list(read) || (length(read) && is.null(names(read)))) {
    gr_abort("`read` must be a named list of gr_read_spec() settings.", class = "gr_bad_setting")
  }
  spec <- do.call(gr_read_spec, c(list(reader = "retrieve"), read))
  # One segmentation given on its own (a spec, or a named list of its
  # settings) is a list of one.
  one_spec <- inherits(segmenters, "gr_segment_spec") ||
    (is.list(segmenters) && length(segmenters) && !is.null(names(segmenters)) &&
       all(names(segmenters) %in% names(formals(gr_segment_spec))))
  if (one_spec) segmenters <- list(segmenters)
  if (is.character(segmenters)) segmenters <- as.list(segmenters)
  if (!is.list(segmenters) || !length(segmenters)) {
    gr_abort("`segmenters` must be segmenter names, gr_segment_spec() objects or lists of settings.",
             class = "gr_bad_setting")
  }
  specs <- lapply(segmenters, as_segment_spec)
  nms <- names(segmenters) %||% rep("", length(specs))
  auto <- vapply(specs, function(s) sprintf("%s_%d", s$method, s$max_tokens), character(1))
  nms <- ifelse(is.na(nms) | !nzchar(nms), auto, nms)
  if (anyDuplicated(nms)) {
    gr_abort(sprintf("Segmenter names must be unique; repeated: %s.",
                     paste(unique(nms[duplicated(nms)]), collapse = ", ")),
             class = "gr_bad_setting")
  }
  if (!is.character(split) || !all(split %in% .hr_splits)) {
    gr_abort(sprintf("`split` must name one or more of %s.", paste(.hr_splits, collapse = ", ")),
             class = "gr_bad_setting")
  }
  sel <- which(reference$split %in% split)
  wanted <- lapply(sel, function(i) {
    acc <- label_text(reference$labels[[i]])
    acc <- acc[!is.na(acc) & nzchar(trimws(acc))]
    if (!length(acc) || any(vapply(acc, is_not_found, logical(1)))) return(NULL)
    unique(fold_answer(acc))
  })
  keep <- !vapply(wanted, is.null, logical(1))
  sel <- sel[keep]
  wanted <- wanted[keep]
  if (!length(sel)) {
    gr_abort("The reference has no answerable, labelled questions in the chosen split.",
             class = "hr_bad_reference")
  }
  items <- lapply(sel, function(i) qa_item(reference$items[[i]]))
  doc_key <- vapply(items, function(it) gr_hash(it$document), character(1))
  trace <- gr_trace(meta = list(stage = "seg_recall"))
  docs <- list()
  for (j in seq_along(items)) {
    if (is.null(docs[[doc_key[j]]])) {
      d <- items[[j]]$document
      docs[[doc_key[j]]] <- if (inherits(d, "gr_document")) d else gr_ingest(d, trace = trace)
    }
  }
  ranks <- list()
  rows <- list()
  for (s in seq_along(specs)) {
    chunked <- lapply(docs, function(d) gr_segment(d, specs[[s]], client = client, trace = trace))
    first <- vapply(seq_along(items), function(j) {
      d <- chunked[[doc_key[j]]]$chunks
      own <- d[["source_text", exact = TRUE]]
      body <- fold_answer(if (is.null(own)) d$text else ifelse(is.na(own), d$text, own))
      holds <- vapply(body, function(t) any(vapply(wanted[[j]], contains_answer, logical(1),
                                                     text = t)), logical(1))
      if (!any(holds)) return(NA_integer_)
      sc <- retrieve_scores(d$text, items[[j]]$question, client, spec, trace)$scores
      ord <- order(-sc, seq_along(sc))
      as.integer(min(match(which(holds), ord)))
    }, integer(1))
    ranks[[s]] <- data.frame(segmenter = nms[s], item = reference$ids[sel], rank = first,
                             stringsAsFactors = FALSE)
    n_chunks <- mean(vapply(chunked, function(ch) nrow(ch$chunks), integer(1)))
    for (kk in k) {
      hits <- sum(!is.na(first) & first <= kk)
      rows[[length(rows) + 1L]] <- data.frame(
        segmenter = nms[s], k = kk, hits = hits, questions = length(first),
        recall = hits / length(first), no_chunk = sum(is.na(first)),
        chunks = round(n_chunks, 1), documents = length(docs), stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  r <- do.call(rbind, ranks)
  rownames(r) <- NULL
  attr(out, "ranks") <- r
  out
}
