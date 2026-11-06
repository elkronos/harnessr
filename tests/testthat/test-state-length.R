# test-state-length.R: refine and hierarchical write the length of the state
# they carry at every step, and every cut writes the tokens it dropped.

step_labels <- function(tr) vapply(tr$steps, function(s) as_chr1(s$label), character(1))

truncation_steps <- function(tr) {
  Filter(function(s) identical(s$label, "truncate") && identical(s$kind, "local"), tr$steps)
}

test_that("refine writes the draft length on every request step", {
  ch <- gr_segment(gr_ingest(sample_doc(3, 2)), list(method = "paragraph", max_tokens = 60))
  draft <- "The cohort comprised 482 participants."
  a <- quiet(gr_read(ch, "How many participants?", mock_echo(draft), list(reader = "refine")))
  steps <- Filter(function(s) startsWith(as_chr1(s$label), "refine."), a$trace$steps)
  expect_identical(length(steps), nrow(ch$chunks))
  expect_true(all(vapply(steps, function(s) is.list(s$state), logical(1))))
  # The first request carries no draft; every later one carries the last.
  expect_identical(steps[[1]]$state$tokens_in, 0L)
  n <- as.integer(gr_count_tokens(draft))
  expect_identical(steps[[1]]$state$tokens_out, n)
  for (s in steps[-1]) {
    expect_identical(s$label, "refine.revise")
    expect_identical(s$state$tokens_in, n)
    expect_identical(s$state$tokens_out, n)
  }
  # The record survives the trip through JSON.
  js <- jsonlite::fromJSON(as_json(a$trace), simplifyVector = FALSE)
  rev <- Filter(function(s) identical(s$label, "refine.revise"), js$steps)
  expect_identical(as.integer(rev[[1]]$state$tokens_in), n)
})

test_that("refine keeps the old draft's length when a revision is unusable", {
  ch <- gr_segment(gr_ingest(sample_doc(3, 2)), list(method = "paragraph", max_tokens = 60))
  k <- 0L
  cl <- gr_mock_client(function(messages, params) {
    k <<- k + 1L
    if (k == 2L) "" else "Answer one two three."
  })
  a <- quiet(gr_read(ch, "Q?", cl, list(reader = "refine")))
  rev <- Filter(function(s) identical(s$label, "refine.revise"), a$trace$steps)
  n <- as.integer(gr_count_tokens("Answer one two three."))
  expect_identical(rev[[1]]$state, list(tokens_in = n, tokens_out = n))
})

test_that("a refine cut writes where it was and the tokens it dropped", {
  local_registries()
  gr_register_model("refine-window", context_window = 900L, max_output = 150L,
                    input_usd = 0, output_usd = 0)
  long <- paste(rep("The cohort comprised 482 participants recruited across nine clinical sites.",
                    30), collapse = " ")
  ch <- new_chunks(c(long, long), "fixed", gr_segment_spec(max_tokens = 4000L))
  a <- quiet(gr_read(ch, "How many participants?", mock_echo("482 participants."),
                     list(reader = "refine", model = "refine-window",
                          max_answer_tokens = 100L)))
  cuts <- truncation_steps(a$trace)
  expect_length(cuts, a$notes$truncations)
  expect_true(all(vapply(cuts, function(s) s$detail$where, character(1)) == "refine.excerpt"))
  for (s in cuts) {
    d <- s$detail
    expect_gt(d$tokens_dropped, 0L)
    expect_identical(d$tokens_dropped, d$tokens_before - d$tokens_kept)
    expect_lte(d$tokens_kept, d$limit)
  }
  expect_identical(a$notes$tokens_truncated,
                   sum(vapply(cuts, function(s) s$detail$tokens_dropped, integer(1))))
  # The cut is written before the request it shortened.
  labs <- step_labels(a$trace)
  expect_identical(labs[which(labs == "truncate")[1] + 1L], "refine.draft")
  expect_true(any(grepl("token\\(s\\) cut to fit", capture.output(print(a)))))
})

test_that("hierarchical writes each summary's length and each level's total", {
  ch <- gr_segment(gr_ingest(sample_doc(3, 3)), list(method = "paragraph", max_tokens = 60))
  a <- quiet(gr_read(ch, "Summarise the findings", mock_echo("A short summary."),
                     list(reader = "hierarchical")))
  summ <- Filter(function(s) startsWith(as_chr1(s$label), "hier.summarise.L"), a$trace$steps)
  expect_identical(length(summ), nrow(ch$chunks))
  n <- as.integer(gr_count_tokens("A short summary."))
  ins <- vapply(summ, function(s) s$state$tokens_in, integer(1))
  expect_identical(ins, as.integer(gr_count_tokens(ch$chunks$text)))
  expect_true(all(vapply(summ, function(s) s$state$tokens_out, integer(1)) == n))
  lvl <- Filter(function(s) identical(s$label, "hier.state.L1"), a$trace$steps)
  expect_length(lvl, 1L)
  expect_identical(lvl[[1]]$kind, "local")
  expect_identical(lvl[[1]]$detail$summaries, nrow(ch$chunks))
  body <- paste(rep("A short summary.", nrow(ch$chunks)), collapse = "\n\n")
  expect_identical(lvl[[1]]$detail$tokens, as.integer(gr_count_tokens(body)))
  ans <- Filter(function(s) identical(s$label, "hier.answer"), a$trace$steps)
  expect_identical(ans[[1]]$state$tokens_in, as.integer(gr_count_tokens(body)))
  expect_length(truncation_steps(a$trace), 0L)
})

test_that("hierarchical writes a state record for every level it runs", {
  local_registries()
  gr_register_model("small-window", context_window = 900L, max_output = 200L,
                    input_usd = 0, output_usd = 0)
  ch <- gr_segment(gr_ingest(sample_doc(6, 5)), list(method = "paragraph", max_tokens = 60))
  a <- quiet(gr_read(ch, "Summarise the findings", mock_bulky(),
                     list(reader = "hierarchical", model = "small-window",
                          fan_in = 3L, max_levels = 2L, max_summary_tokens = 150L)))
  labs <- step_labels(a$trace)
  expect_identical(sum(startsWith(labs, "hier.state.L")), a$notes$levels)
  l2 <- Filter(function(s) identical(s$label, "hier.summarise.L2"), a$trace$steps)
  expect_gt(length(l2), 0L)
  expect_true(all(vapply(l2, function(s) s$state$tokens_in > s$state$tokens_out, logical(1))))
})

test_that("summaries cut to fit write the tokens dropped", {
  local_registries()
  gr_register_model("small-window", context_window = 900L, max_output = 200L,
                    input_usd = 0, output_usd = 0)
  ch <- gr_segment(gr_ingest(sample_doc(6, 5)), list(method = "paragraph", max_tokens = 60))
  a <- quiet(gr_read(ch, "Summarise the findings", mock_bulky(),
                     list(reader = "hierarchical", model = "small-window",
                          fan_in = 3L, max_levels = 1L, max_summary_tokens = 150L)))
  expect_true(a$notes$summaries_truncated)
  cuts <- truncation_steps(a$trace)
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$where, "hier.summaries")
  expect_identical(d$level, 1L)
  expect_gt(d$tokens_dropped, 0L)
  expect_identical(a$notes$tokens_truncated, d$tokens_dropped)
  ans <- Filter(function(s) identical(s$label, "hier.answer"), a$trace$steps)
  expect_lte(ans[[1]]$state$tokens_in, d$limit)
})

test_that("the cut text is what gr_truncate_tokens() returns", {
  tr <- gr_trace()
  x <- paste(rep("alpha beta gamma delta", 60), collapse = " ")
  got <- harnessr:::truncate_logged(x, 20L, "test.site", tr, chunk = 3L)
  expect_identical(got$text, gr_truncate_tokens(x, 20L))
  cuts <- truncation_steps(tr)
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$where, "test.site")
  expect_identical(d$chunk, 3L)
  expect_identical(d$limit, 20L)
  expect_identical(d$tokens_before, as.integer(gr_count_tokens(x)))
  # The marker is not counted as text kept.
  kept <- sub(" ...[truncated]", "", got$text, fixed = TRUE)
  expect_identical(d$tokens_kept, as.integer(gr_count_tokens(kept)))
  expect_identical(got$dropped, d$tokens_dropped)
  # Text that fits is not cut and writes nothing.
  same <- harnessr:::truncate_logged("short", 20L, "test.site", tr)
  expect_identical(same, list(text = "short", dropped = 0L))
  expect_length(truncation_steps(tr), 1L)
  # No trace, no record, and the same text.
  expect_identical(harnessr:::truncate_logged(x, 20L, "test.site")$text, got$text)
})

test_that("a skimmed section cut to fit writes its cut", {
  local_registries()
  gr_register_model("preview-window", context_window = 1200L, max_output = 150L,
                    input_usd = 0, output_usd = 0)
  ch <- gr_segment(gr_ingest(sample_doc(3, 12)), list(method = "paragraph", max_tokens = 120))
  a <- quiet(gr_read(ch, "Q?", mock_planner(c("skim", "skim", "skim")),
                     list(reader = "preview", model = "preview-window",
                          max_answer_tokens = 100L)))
  cuts <- Filter(function(s) identical(s$detail$where, "preview.skim"), truncation_steps(a$trace))
  # This layout cuts five skimmed sections; none would be a regression, not a skip.
  expect_gt(length(cuts), 0L)
  expect_identical(a$notes$tokens_truncated,
                   sum(vapply(cuts, function(s) s$detail$tokens_dropped, integer(1))))
  # The chunk ids stay an array in JSON, for a section of one chunk as for more.
  js <- jsonlite::fromJSON(as_json(a$trace), simplifyVector = FALSE)
  skim <- Filter(function(s) identical(s$label, "truncate") &&
                   identical(s$detail$where, "preview.skim"), js$steps)
  expect_true(all(vapply(skim, function(s) is.list(s$detail$chunk_ids), logical(1))))
  tr <- gr_trace()
  harnessr:::truncate_logged(paste(rep("word", 50), collapse = " "), 10L, "preview.skim", tr,
                             chunk_ids = 5L)
  one <- jsonlite::fromJSON(as_json(tr), simplifyVector = FALSE)$steps[[1]]$detail$chunk_ids
  expect_identical(one, list(5L))
})

test_that("an outline cut to preview_tokens writes its cut", {
  ch <- gr_segment(gr_ingest(sample_doc(3, 12)), list(method = "paragraph", max_tokens = 120))
  a <- quiet(gr_read(ch, "Q?", mock_planner(c("skim", "skim", "skim")),
                     list(reader = "preview", preview_tokens = 100L)))
  cuts <- Filter(function(s) identical(s$detail$where, "preview.outline"),
                 truncation_steps(a$trace))
  expect_length(cuts, 1L)
  expect_identical(cuts[[1]]$detail$limit, 100L)
  expect_gt(cuts[[1]]$detail$tokens_dropped, 0L)
})

test_that("a screened opening cut to screen_tokens writes its cut", {
  long <- paste(rep("filler words about the background of the study", 150), collapse = " ")
  ch <- new_chunks(c(long, "We randomly assigned participants."), "fixed",
                   gr_segment_spec(max_tokens = 4000L))
  cl <- gr_mock_client(function(messages, params) {
    '{"decision":"unclear","reason":"Not stated.","criterion":null,"quote":null}'
  })
  a <- quiet(gr_read(ch, "Do statins work?", cl,
                     list(reader = "screen", include = "Reports a randomised comparison",
                          screen_tokens = 300L)))
  cuts <- Filter(function(s) identical(s$detail$where, "screen.opening"),
                 truncation_steps(a$trace))
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$limit, 300L)
  expect_identical(d$chunk_id, ch$chunks$chunk_id[1])
  expect_identical(d$tokens_before, as.integer(gr_count_tokens(long)))
  expect_lte(d$tokens_kept, 300L)
  expect_identical(d$tokens_dropped, d$tokens_before - d$tokens_kept)
})

test_that("a long contextual header cut to fit writes its own room as the limit", {
  header <- paste(rep("This passage sits in the methods of the cohort study.", 30),
                  collapse = " ")
  tr <- gr_trace()
  ch <- quiet(gr_segment(gr_ingest(sample_doc(2, 3)),
                         gr_segment_spec("contextual", max_tokens = 200, context_source = "llm"),
                         client = mock_echo(header), trace = tr))
  cuts <- Filter(function(s) identical(s$detail$where, "segment.contextual.header"),
                 truncation_steps(tr))
  expect_gt(length(cuts), 0L)
  for (s in cuts) {
    d <- s$detail
    expect_true(is.integer(d$chunk))
    expect_identical(d$limit, d$tokens_kept)
    expect_gt(d$tokens_dropped, 0L)
  }
})

test_that("the findings a failed merge returns write their cut", {
  spec <- gr_read_spec(max_answer_tokens = 100L)
  piece <- paste(rep("The quarterly revenue figure was reported in the filing.", 25),
                 collapse = " ")
  tr <- gr_trace()
  out <- quiet(harnessr:::tree_merge(mock_dead(), "q", c(piece, piece, piece), spec, tr,
                                    label = "map.merge"))
  expect_false(out$ok)
  cuts <- Filter(function(s) identical(s$detail$where, "map.merge.giveup"),
                 truncation_steps(tr))
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$limit, 300L)
  expect_gt(d$tokens_dropped, 0L)
  # The marker is not counted as kept.
  kept <- sub("\n\n...[merge failed; findings above are truncated]", "", out$text, fixed = TRUE)
  expect_identical(d$tokens_kept, as.integer(gr_count_tokens(kept)))
})

test_that("gaps whose first line is over the cap write the cut without the marker", {
  local_registries()
  gr_register_model("gaps-window", context_window = 3000L, max_output = 400L,
                    input_usd = 0, output_usd = 0)
  tab <- data.frame(document = c("a.pdf", "b.pdf"), document_id = c("h1", "h2"),
                    status = "ok", duplicate_of = NA_character_, n_filled = 2L,
                    n_unverified = 0L, conflicts = NA_character_,
                    design = c("trial", "survey"), stringsAsFactors = FALSE)
  cl <- gr_mock_client(function(messages, params) "The studies [study 1] [study 2].")
  g <- data.frame(kind = "combination unstudied", dimension = "design x setting",
                  detail = paste(rep("word", 3000), collapse = " "))
  outline <- structure(c(Findings = "f", "What is missing" = "gaps"),
                       closing = "What is missing")
  s <- quiet(gr_synthesise(tab, outline = outline, question = "Q?", client = cl, gaps = g,
                           model = "gaps-window", max_section_tokens = 300))
  cuts <- Filter(function(s) identical(s$detail$where, "synthesise.gaps"),
                 truncation_steps(s$trace))
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$section, "What is missing")
  expect_true(endsWith(s$gaps, " ...[truncated]"))
  kept <- sub(" ...[truncated]", "", s$gaps, fixed = TRUE)
  expect_identical(d$tokens_kept, as.integer(gr_count_tokens(kept)))
  expect_identical(d$tokens_dropped, d$tokens_before - d$tokens_kept)
})

test_that("an embedding input cut to the model's window writes its cut", {
  local_registries()
  gr_register_model("tiny-embed", context_window = 40L, max_output = 1L,
                    input_usd = 0, output_usd = 0)
  withr::local_envvar(OPENAI_API_KEY = "sk-test")
  cl <- gr_client(base_url = "https://gw.invalid", max_retries = 0L)
  sent <- new.env(parent = emptyenv())
  local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) {
      sent$body <- body
      simpleError("no network in tests")
    }, .package = "httr")
  long <- paste(rep("alpha beta gamma delta epsilon", 40), collapse = " ")
  tr <- gr_trace()
  expect_error(harnessr:::embed_api(c("short text", long),
                                    list(client = cl, model = "tiny-embed", cache = FALSE,
                                         embedder = "api", batch_size = 8L, trace = tr)),
               class = "gr_embed_error")
  cuts <- truncation_steps(tr)
  expect_length(cuts, 1L)
  d <- cuts[[1]]$detail
  expect_identical(d$where, "embed.input")
  expect_identical(d$input, 2L)
  expect_identical(d$limit, 24L)
  expect_gt(d$tokens_dropped, 0L)
  # What was sent is the same cut as before.
  expect_identical(unlist(sent$body$input), c("short text", gr_truncate_tokens(long, 24L, "")))
})

test_that("a finding cut to fit a merge writes its cut", {
  local_registries()
  gr_register_model("merge-window", context_window = 900L, max_output = 150L,
                    input_usd = 0, output_usd = 0)
  spec <- gr_read_spec(model = "merge-window", max_answer_tokens = 100L)
  big <- paste(rep("The quarterly revenue figure was reported in the filing.", 200),
               collapse = " ")
  tr <- gr_trace()
  out <- quiet(harnessr:::tree_merge(mock_echo("merged"), "q",
                                    c(big, "Small finding one.", "Small finding two."),
                                    spec, tr, label = "map.merge"))
  # The mock makes no progress, so the merge also gives up and writes that cut.
  cuts <- Filter(function(s) identical(s$detail$where, "map.merge.input"),
                 truncation_steps(tr))
  expect_length(cuts, out$truncated)
  d <- cuts[[1]]$detail
  expect_identical(d$where, "map.merge.input")
  expect_identical(d$level, 1L)
  expect_identical(d$piece, 1L)
  expect_gt(d$tokens_dropped, 0L)
})

test_that("the contextual segmenter writes the cut of the document it summarises", {
  doc <- gr_ingest(sample_doc(6, 6))
  skip_if(gr_count_tokens(doc$text) <= 1500, "the sample document fits the summary cap")
  tr <- gr_trace()
  quiet(gr_segment(doc, gr_segment_spec("contextual", max_tokens = 200, context_source = "llm"),
                   client = mock_echo("It is about the cohort."), trace = tr))
  cuts <- Filter(function(s) identical(s$detail$where, "segment.contextual.document"),
                 truncation_steps(tr))
  expect_length(cuts, 1L)
  expect_identical(cuts[[1]]$detail$limit, 1500L)
  expect_identical(cuts[[1]]$detail$tokens_dropped,
                   as.integer(gr_count_tokens(doc$text)) - cuts[[1]]$detail$tokens_kept)
})
