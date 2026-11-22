# test-reading-options.R: the opt-in reading options of package 6a. Each is
# off by default, so a default spec sends what it sent before; the golden
# records check that. These tests check what each option does when it is on.

ro_chunks <- function(txt, section = NA_character_) {
  new_chunks(txt, "precomputed", gr_segment_spec(max_tokens = max(gr_count_tokens(txt), 32L)),
             section = section)
}

ro_steps <- function(tr, label) {
  Filter(function(s) identical(s$label, label) && identical(s$kind, "local"), tr$steps)
}

# ---------------------------------------------------------------------------
# P1D-06: preview safeguards
# ---------------------------------------------------------------------------

ro_preview_doc <- function() {
  txt <- c("The board met in spring and approved the plan.",
           "Office moves were finished in the autumn.",
           "Enrolment reached 482 participants across nine sites.",
           "The auditors signed the accounts in March.")
  ro_chunks(txt, section = sprintf("Part %d", 1:4))
}

ro_planner <- function(treatments, answer = function(body) "PLANNED ANSWER") {
  gr_mock_client(function(m, p) {
    sys <- m[[1]]$content
    if (grepl("You plan how to read a document", sys, fixed = TRUE)) {
      return(preview_plan_json(treatments))
    }
    if (grepl("extract evidence, not answers", sys, fixed = TRUE)) return("NONE")
    answer(paste(vapply(m, function(x) x$content, ""), collapse = "\n"))
  })
}

test_that("unskip_k is off by default and leaves the spec as it was", {
  expect_null(gr_read_spec("preview")$unskip_k)
  expect_null(gr_read_spec("preview")$reread_on)
  expect_identical(gr_read_spec("preview", unskip_k = 1)$unskip_k, 1L)
  expect_identical(gr_read_spec("preview", reread_on = "not")$reread_on, "not_found")
  expect_error(gr_read_spec("preview", reread_on = "always"), class = "gr_bad_setting")
})

test_that("each skip is logged with its score, and the plan is followed by default", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  cl <- ro_planner(c("read", "read", "skip", "read"))
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, "preview", trace = tr))
  skips <- ro_steps(tr, "preview.skip")
  expect_length(skips, 1L)
  expect_identical(skips[[1]]$detail$section, 3L)
  expect_gt(skips[[1]]$detail$score, 0)
  expect_false(skips[[1]]$detail$unskipped)
  expect_identical(a$notes$skipped, 1L)
  expect_null(a$notes$unskipped)
  expect_false(grepl("482", cl$calls()[[length(cl$calls())]]$messages[[3]]$content))
})

test_that("unskip_k = 1 reads the only section holding the question's words", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  cl <- ro_planner(c("read", "read", "skip", "skip"))
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", unskip_k = 1), trace = tr))
  expect_identical(a$notes$unskipped, 3L)
  expect_identical(a$notes$skipped, 1L)
  skips <- ro_steps(tr, "preview.skip")
  expect_identical(vapply(skips, function(s) s$detail$unskipped, logical(1)), c(TRUE, FALSE))
  last <- cl$calls()[[length(cl$calls())]]
  expect_true(any(grepl("482", vapply(last$messages, function(x) x$content, ""))))
  # A section that shares no word with the question is not unskipped.
  cl2 <- ro_planner(c("read", "skip", "read", "read"))
  a2 <- quiet(gr_read(ch, q, cl2, gr_read_spec("preview", unskip_k = 1)))
  expect_identical(a2$notes$unskipped, integer(0))
  expect_identical(a2$notes$skipped, 1L)
})

test_that("reread_on = 'not_found' reads what the plan left out after a not-found", {
  ch <- ro_preview_doc()
  q <- "How many participants across nine sites?"
  answer <- function(body) if (grepl("482", body)) "482 participants." else "NOT_IN_DOCUMENT"
  # Default: the not-found stands and no second answer request is sent.
  cl <- ro_planner(c("read", "read", "skip", "read"), answer)
  a <- quiet(gr_read(ch, q, cl, "preview"))
  expect_true(is_not_found(a$answer))
  expect_false("preview.reread" %in% vapply(cl$calls(), function(x) x$label, ""))
  # Opted in: one more request over the skipped section finds it.
  cl <- ro_planner(c("read", "read", "skip", "read"), answer)
  tr <- gr_trace()
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found"), trace = tr))
  expect_identical(a$answer, "482 participants.")
  expect_identical(vapply(cl$calls(), function(x) x$label, "")[length(cl$calls())],
                   "preview.reread")
  expect_true(a$notes$reread$found)
  expect_identical(a$chunks_used, 3L)
  expect_length(ro_steps(tr, "preview.reread"), 1L)
  # A plan that skipped everything is re-read too.
  cl <- ro_planner(rep("skip", 4), answer)
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found")))
  expect_identical(a$answer, "482 participants.")
  # A re-read that finds nothing leaves the not-found and says so.
  cl <- ro_planner(c("read", "read", "skip", "read"), function(body) "NOT_IN_DOCUMENT")
  a <- quiet(gr_read(ch, q, cl, gr_read_spec("preview", reread_on = "not_found")))
  expect_true(is_not_found(a$answer))
  expect_false(a$notes$reread$found)
})

test_that("reread_on raises the preview's worst case by one request", {
  ch <- ro_preview_doc()
  st <- harnessr:::read_input_stats(ch, gr_read_spec("preview"), gr_mock_client(), "q")
  base <- harnessr:::cost_preview(st, gr_read_spec("preview"))
  more <- harnessr:::cost_preview(st, gr_read_spec("preview", reread_on = "not_found"))
  expect_identical(as.integer(more$calls_max), as.integer(base$calls_max) + 1L)
})

# ---------------------------------------------------------------------------
# P1D-07: rerank when every candidate scores low
# ---------------------------------------------------------------------------

ro_rerank_client <- function(score = 1, answer = "NOT_IN_DOCUMENT") {
  gr_mock_client(function(m, p) {
    if (identical(p$schema_name, "relevance")) {
      return(sprintf('{"score": %d, "reason": "weak"}', as.integer(score)))
    }
    answer
  })
}

ro_rerank_doc <- function() {
  ro_chunks(sprintf("Budget line %d mentions revenue planning for year %d.", 1:8, 2010 + 1:8))
}

test_that("rerank records retrieval_low_score when every candidate scores low", {
  ch <- ro_rerank_doc()
  cl <- ro_rerank_client(score = 1)
  tr <- gr_trace()
  a <- quiet(gr_read(ch, "What was revenue?", cl, "rerank", trace = tr))
  expect_true(is_not_found(a$answer))
  expect_true(a$notes$retrieval_low_score)
  expect_false(a$partial)
  expect_false("rerank.answer" %in% vapply(cl$calls(), function(x) x$label, ""))
  low <- ro_steps(tr, "rerank.low_score")
  expect_length(low, 1L)
  expect_identical(low[[1]]$detail$action, "not_found")
  # A candidate at the cut is not low.
  a2 <- quiet(gr_read(ch, "What was revenue?", ro_rerank_client(score = 4, answer = "x"),
                      "rerank"))
  expect_null(a2$notes$retrieval_low_score)
})

test_that("low_score = 'read_top_k' sends the top 5 and marks a not-found", {
  ch <- ro_rerank_doc()
  spec <- gr_read_spec("rerank", low_score = "read_top_k", top_k = 2)
  expect_identical(spec$low_score, "read_top_k")
  expect_null(gr_read_spec("rerank")$low_score)
  cl <- ro_rerank_client(score = 1)
  a <- quiet(gr_read(ch, "What was revenue?", cl, spec))
  calls <- cl$calls()
  last <- calls[[length(calls)]]
  expect_identical(last$label, "rerank.answer")
  expect_length(regmatches(last$messages[[2]]$content,
                           gregexpr("\\[chunk [0-9]+\\]", last$messages[[2]]$content))[[1]], 5L)
  expect_true(is_not_found(a$answer))
  expect_true(a$notes$retrieval_low_score)
  expect_true(a$notes$read_below_min_score)
  # An answer found below the cut is kept, and says what it read.
  a2 <- quiet(gr_read(ch, "What was revenue?", ro_rerank_client(1, "Revenue was 4."), spec))
  expect_identical(a2$answer, "Revenue was 4.")
  expect_null(a2$notes$retrieval_low_score)
  expect_true(a2$notes$read_below_min_score)
})
