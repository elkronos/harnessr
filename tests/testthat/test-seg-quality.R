# gr_seg_pk(), gr_seg_windowdiff(), gr_seg_boundaries() and gr_seg_recall():
# segmentation measured against a reference and by what retrieval finds.
#
# Every expected value below is worked by hand in the comment above it. A
# window of k positions starting at i covers positions i to i + k - 1, and a
# sequence of length L has L - k + 1 of them, as in NLTK.

test_that("WindowDiff matches the hand count on NLTK's three strings", {
  s1 <- "000100000010"   # boundaries at 4 and 11
  s2 <- "000010000100"   # boundaries at 5 and 10
  s3 <- "100000010000"   # boundaries at 1 and 8
  # Identical strings: no window differs.
  expect_equal(as.numeric(gr_seg_windowdiff(s1, s1, k = 3)), 0)
  # s1 against s2, k = 3, windows 1..10. Counts (s1, s2) per window:
  # [1-3] 0,0  [2-4] 1,0 x  [3-5] 1,1  [4-6] 1,1  [5-7] 0,1 x
  # [6-8] 0,0  [7-9] 0,0  [8-10] 0,1 x  [9-11] 1,1  [10-12] 1,1
  # 3 of 10 differ: 0.3.
  expect_equal(as.numeric(gr_seg_windowdiff(s1, s2, k = 3)), 3 / 10)
  # s2 against s3, k = 3: counts (s2, s3)
  # [1-3] 0,1 x  [2-4] 0,0  [3-5] 1,0 x  [4-6] 1,0 x  [5-7] 1,0 x
  # [6-8] 0,1 x  [7-9] 0,1 x  [8-10] 1,1  [9-11] 1,0 x  [10-12] 1,0 x
  # 8 of 10 differ: 0.8.
  expect_equal(as.numeric(gr_seg_windowdiff(s2, s3, k = 3)), 8 / 10)
  expect_identical(attr(gr_seg_windowdiff(s1, s2, k = 3), "k"), 3L)
})

test_that("Pk matches the hand count, with NLTK's default window", {
  s1 <- "000100000010"
  s2 <- "000010000100"
  # Default k: round(12 / (2 * 2)) = 3. No window above holds two
  # boundaries, so Pk counts the same 3 windows as WindowDiff: 0.3.
  p <- gr_seg_pk(s1, s2)
  expect_equal(as.numeric(p), 3 / 10)
  expect_identical(attr(p, "k"), 3L)
  # NLTK's pk('0100' * 100, '1' * 400, 2). The hypothesis has a boundary
  # in every window. The reference "0100" repeated has none in the windows
  # starting at i = 3, 7, ..., 399 (100 windows: positions "00") and
  # i = 4, 8, ..., 396 (99 windows: the "0" ending one block and the "0"
  # opening the next), so 199 of the 399 windows are errors.
  ref <- strrep("0100", 100)
  expect_equal(as.numeric(gr_seg_pk(ref, strrep("1", 400), k = 2)), 199 / 399)
  # And the all-0 hypothesis errs in exactly the other 200 windows.
  expect_equal(as.numeric(gr_seg_pk(ref, strrep("0", 400), k = 2)), 200 / 399)
  expect_equal(as.numeric(gr_seg_pk(ref, ref, k = 2)), 0)
})

test_that("Pk and WindowDiff differ where a window holds two boundaries", {
  # Reference 0110 has boundaries at 2 and 3, hypothesis 0100 at 2; k = 2,
  # windows [1-2], [2-3], [3-4]. Counts (ref, hyp): 1,1 ; 2,1 ; 1,0.
  # Pk (any boundary in the window): same, same, differ: 1/3.
  # WindowDiff (the count): same, differ, differ: 2/3.
  expect_equal(as.numeric(gr_seg_pk("0110", "0100", k = 2)), 1 / 3)
  expect_equal(as.numeric(gr_seg_windowdiff("0110", "0100", k = 2)), 2 / 3)
  # Vectors of 0 and 1, and logical vectors, give the same values as strings.
  expect_equal(gr_seg_windowdiff(c(0, 1, 1, 0), c(FALSE, TRUE, FALSE, FALSE), k = 2),
               gr_seg_windowdiff("0110", "0100", k = 2))
})

test_that("bad sequences and windows are refused", {
  expect_error(gr_seg_pk("0102", "0100", k = 2), class = "gr_bad_setting")
  expect_error(gr_seg_pk("010", "0100", k = 2), class = "gr_bad_setting")
  expect_error(gr_seg_pk("0000", "0100"), "no boundaries", class = "gr_bad_setting")
  expect_error(gr_seg_pk("0100", "0100", k = 5), class = "gr_bad_setting")
  expect_error(gr_seg_windowdiff("0100", "0100", k = 1.5), class = "gr_bad_setting")
  expect_error(gr_seg_windowdiff(c(0, NA, 1), c(0, 0, 1), k = 1), class = "gr_bad_setting")
  # A reference dense with boundaries gives a default window of at least 1:
  # round(4 / (2 * 4)) = round(0.5) = 0 (half to even), raised to 1.
  expect_identical(attr(gr_seg_pk("1111", "1111"), "k"), 1L)
})

test_that("gr_seg_boundaries maps chunks and reference segments to sentences", {
  doc <- paste("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
               "The chair retired.", sep = "\n\n")
  # Five sentences, so four positions; the topics end after sentences 2 and 4.
  ref <- gr_seg_boundaries(c("Revenue rose. Costs fell.", "Staff grew. Offices moved.",
                             "The chair retired."), doc)
  expect_identical(as.integer(ref), c(0L, 1L, 0L, 1L))
  expect_identical(attr(ref, "units"), 5L)
  expect_identical(attr(ref, "unplaced"), 0L)
  # Two chunks, the first four sentences and then the last, put one
  # boundary where the reference has its second.
  ch <- new_chunks(c("Revenue rose. Costs fell. Staff grew. Offices moved.",
                     "The chair retired."), "manual", gr_segment_spec(max_tokens = 100))
  hyp <- gr_seg_boundaries(ch, gr_ingest(doc))
  expect_identical(as.integer(hyp), c(0L, 0L, 0L, 1L))
  # Pk with k = 2 over 0101 and 0001: windows [1-2] 1,0 x ; [2-3] 1,0 x ;
  # [3-4] 1,1. 2 of 3.
  expect_equal(as.numeric(gr_seg_pk(ref, hyp, k = 2)), 2 / 3)
})

test_that("overlap adds no boundary, and a cut inside a sentence counts at its end", {
  doc <- "One two three. Four five six. Seven eight nine."
  # Chunks that overlap by a sentence: sentence 2 is placed in the first.
  over <- gr_seg_boundaries(c("One two three. Four five six.",
                              "Four five six. Seven eight nine."), doc)
  expect_identical(as.integer(over), c(0L, 1L))
  # A cut inside sentence 2, "Four five six." (14 characters): no chunk
  # holds it whole, so it is placed by its first 7 characters, "Four fi",
  # which are in the first chunk, and the boundary comes after it.
  cut <- gr_seg_boundaries(c("One two three. Four five", "six. Seven eight nine."), doc)
  expect_identical(as.integer(cut), c(0L, 1L))
  expect_identical(attr(cut, "unplaced"), 0L)
  expect_error(gr_seg_boundaries("One sentence.", "One sentence."), class = "gr_bad_setting")
  expect_error(gr_seg_boundaries(1:3, doc), class = "gr_bad_setting")
})

test_that("a repeated sentence is placed in the segment it occurs in", {
  # "See note 3." opens both sections. Matched on text alone, the second one
  # was found in the first section, which moved the boundary one sentence
  # later: 0 0 1 instead of 0 1 0.
  segs <- c("See note 3. Revenue rose sharply.", "See note 3. Costs fell slightly.")
  b <- gr_seg_boundaries(segs, paste(segs, collapse = "\n\n"))
  expect_identical(as.integer(b), c(0L, 1L, 0L))
  expect_identical(attr(b, "unplaced"), 0L)
  # A short sentence that is part of an earlier one in the same section.
  short <- c("Costs fell. Costs fell sharply in May.", "Costs fell. Staff grew.")
  expect_identical(as.integer(gr_seg_boundaries(short, paste(short, collapse = " "))),
                   c(0L, 1L, 0L))
  # Segments that are not verbatim parts of the document are matched on
  # text, after the text already placed, and keep the boundary too.
  loose <- c("See note 3.  Revenue rose sharply!", "See note 3. Costs fell slightly.")
  doc <- "See note 3. Revenue rose sharply. See note 3. Costs fell slightly."
  lb <- gr_seg_boundaries(loose, doc)
  expect_identical(as.integer(lb), c(0L, 1L, 0L))
  expect_identical(attr(lb, "unplaced"), 0L)
})

test_that("fixed chunks of a text that repeats itself keep their boundaries", {
  old <- gr_options(verbose = FALSE)
  on.exit(gr_options(old))
  # Three sentences five times over: 15 sentences. The four fixed chunks
  # are cut inside sentences 5, 9 and 13, so each cut counts at the end of
  # that sentence. Matched on text alone, every boundary was lost.
  txt <- paste(rep(paste("Revenue rose sharply this year.", "Costs fell slightly in the spring.",
                         "Staff numbers grew again."), 5), collapse = " ")
  ch <- gr_segment(txt, list(method = "fixed", max_tokens = 32, overlap = 4))
  expect_identical(nrow(ch$chunks), 4L)
  b <- gr_seg_boundaries(ch, txt)
  expect_identical(which(b == 1L), c(5L, 9L, 13L))
  expect_identical(attr(b, "unplaced"), 0L)
})

test_that("the default Pk window is NLTK's round(L / (2 * boundaries))", {
  # 4 positions, 1 boundary: round(4 / 2) = 2. Half the mean segment length
  # (5 units in 2 segments) would be 1.25.
  expect_identical(attr(gr_seg_pk("0100", "0100"), "k"), 2L)
})

test_that("a contextual chunk is matched on its source text, not its context line", {
  old <- gr_options(verbose = FALSE)
  on.exit(gr_options(old))
  doc <- gr_ingest(paste("Revenue rose. Costs fell.", "Staff grew. Offices moved.", sep = "\n\n"))
  ch <- gr_segment(doc, list(method = "contextual", max_tokens = 60))
  expect_false(is.null(ch$chunks$source_text))
  b <- gr_seg_boundaries(ch, doc)
  expect_identical(attr(b, "unplaced"), 0L)
  expect_length(b, 3L)
})

test_that("gr_seg_recall counts the questions whose answer ranks in the top k", {
  old <- gr_options(verbose = FALSE, embedder = "lexical")
  on.exit(gr_options(old))
  doc <- paste("Revenue was 45.2 million dollars in fiscal 2024.",
               "The plant in Leeds made 12,400 units.",
               "Staff numbered 310 at year end.", sep = "\n\n")
  ref <- gr_qa_reference(
    c(rev = "What was revenue?", units = "How many units did Leeds make?",
      ceo = "Who is the chief executive?"),
    documents = doc, answers = list("45.2 million", "12400", NA), unanswerable = "ceo",
    split = "test")
  # One chunk per sentence: each answer is in exactly one chunk, and each
  # question shares a word with its own chunk only ("revenue", "units"), so
  # both rank first. The unanswerable question is left out.
  r <- gr_seg_recall(ref, list(one = list(method = "sentence", max_tokens = 32)), k = c(1, 2))
  expect_identical(r$segmenter, c("one", "one"))
  expect_identical(r$k, 1:2)
  expect_identical(r$hits, c(2L, 2L))
  expect_identical(r$questions, c(2L, 2L))
  expect_equal(r$recall, c(1, 1))
  expect_identical(attr(r, "ranks")$rank, c(1L, 1L))
  # "12400" is matched against "12,400" after the separator is folded.
  expect_identical(attr(r, "ranks")$item, c("rev", "units"))
})

test_that("an answer cut in two is in no chunk and misses at every k", {
  old <- gr_options(verbose = FALSE, embedder = "lexical")
  on.exit(gr_options(old))
  doc <- paste("The group sold goods in many markets over the year and kept its costs under",
               "close watch throughout. Revenue was 45.2 million dollars in fiscal 2024 for",
               "the group as a whole.")
  ref <- gr_qa_reference(c(rev = "What was revenue?"), documents = doc,
                         answers = list("45.2 million dollars in fiscal 2024"), split = "test")
  whole <- gr_seg_recall(ref, list(sentence = list(method = "sentence", max_tokens = 64)), k = 1)
  expect_identical(whole$hits, 1L)
  expect_identical(whole$no_chunk, 0L)
  # Fixed windows of 32 tokens: whatever the tokenizer, check first that no
  # window holds the whole answer, then that the question misses at every k.
  ch <- gr_segment(doc, list(method = "fixed", max_tokens = 32))
  expect_false(any(grepl("45.2 million dollars in fiscal 2024", ch$chunks$text, fixed = TRUE)))
  tiny <- gr_seg_recall(ref, list(method = "fixed", max_tokens = 32), k = 1:3)
  expect_identical(tiny$segmenter[1], "fixed_32")
  expect_true(all(tiny$hits == 0L))
  expect_true(all(tiny$no_chunk == 1L))
  expect_true(is.na(attr(tiny, "ranks")$rank))
})

test_that("gr_seg_recall refuses what it cannot use", {
  old <- gr_options(verbose = FALSE, embedder = "lexical")
  on.exit(gr_options(old))
  ref <- gr_qa_reference(c(a = "Who is the chair?"), documents = "The chair is Ana Ruiz.",
                         answers = list("Ana Ruiz"), split = "dev")
  expect_error(gr_seg_recall(ref, "sentence"), class = "hr_bad_reference")
  expect_error(gr_seg_recall(ref, "sentence", split = "dev", k = 0), class = "gr_bad_setting")
  expect_error(gr_seg_recall(ref, list(a = "sentence", a = "paragraph"), split = "dev"),
               class = "gr_bad_setting")
  expect_error(gr_seg_recall(ref, "sentence", split = "dev", read = list(1)),
               class = "gr_bad_setting")
  expect_identical(gr_seg_recall(ref, "sentence", split = "dev", k = 1)$hits, 1L)
})
