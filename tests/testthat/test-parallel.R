# test-parallel.R -- parallel execution must not change what a run reports.
#
# `parallel = TRUE` was a speed flag that silently disabled the accounting. A
# worker is a separate process, so the trace it was handed was a copy and every
# call it recorded went away with it: a six-chunk map_reduce reported one call
# instead of seven, and hr_trace_cost() under-reported the bill in proportion to
# how parallel the run was. The answer was right, which is what made it hard to
# notice.
#
# There were no tests for `parallel = TRUE` in the suite at all. These are them.

# skip_if_no_future() is in helper-parallel.R.

para_doc <- function(n = 6) {
  f <- tempfile(fileext = ".txt")
  writeLines(paste(sprintf("Paragraph %d. Revenue in region %d was %d million dollars this year.",
                           seq_len(n), seq_len(n), 40 + seq_len(n)), collapse = "\n\n"), f)
  f
}

# Everything the trace claims about a run, in one comparable row.
trace_shape <- function(ans) {
  s <- hr_trace_summary(ans$trace)
  cost <- hr_trace_cost(ans$trace)
  list(calls = as.integer(s$calls), steps = as.integer(s$steps),
       cached = as.integer(s$cached),
       tokens_in = as.integer(s$tokens_in), tokens_out = as.integer(s$tokens_out),
       usd = sum(cost$usd), labels = sort(vapply(ans$trace$steps,
                                                 function(x) as_chr1_p(x$label), character(1))))
}
as_chr1_p <- function(x) if (length(x)) as.character(x)[1] else NA_character_

read_both <- function(recipe, f, ...) {
  out <- lapply(c(FALSE, TRUE), function(par) {
    cl <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
    quiet(answer_document(f, "What was revenue?", recipe, client = cl,
                          max_tokens = 40, parallel = par, ...))
  })
  names(out) <- c("seq", "par")
  out
}

test_that("a parallel run reports exactly what the same sequential run reports", {
  skip_if_no_future()
  f <- para_doc()
  # Comparing the two paths to each other is necessary and NOT sufficient: a
  # change that loses the per-chunk calls on BOTH paths leaves them agreeing at
  # one call each, and the comparison passes. So each recipe also states, in
  # absolute terms, how many per-chunk calls its trace has to contain.
  cases <- list(list(recipe = "thorough", label = "map.answer",  least = 6L),
                list(recipe = "precise",  label = "skim.extract", least = 8L))
  for (case in cases) {
    both <- read_both(case$recipe, f)
    count <- function(a) sum(vapply(a$trace$steps, function(s) as_chr1_p(s$label),
                                    character(1)) == case$label)
    expect_gte(count(both$seq), case$least)
    expect_gte(count(both$par), case$least)
    expect_identical(trace_shape(both$par), trace_shape(both$seq), info = case$recipe)
    # The answer is unchanged, which it was before the fix too -- the bug was in
    # the accounting, not the reading.
    expect_identical(both$par$answer, both$seq$answer, info = case$recipe)
  }
})

test_that("the merge tree records its calls from workers too", {
  # tree_merge() fans out over merge GROUPS, which only form when the findings
  # do not fit one prompt. A model with a small context window is what makes
  # more than one group, and therefore what exercises the parallel path at all.
  skip_if_no_future()
  local_registries()
  hr_register_model("small-ctx", context_window = 1200L, max_output = 200L,
                    input_usd = 0, output_usd = 0)
  f <- para_doc(10)
  shape <- lapply(c(FALSE, TRUE), function(par) {
    cl <- hr_mock_client(function(messages, params)
      paste(rep("A finding about revenue in one of the regions.", 12), collapse = " "))
    a <- quiet(answer_document(f, "What was revenue?", "thorough", client = cl,
                               model = "small-ctx", max_tokens = 40, parallel = par))
    labels <- vapply(a$trace$steps, function(s) as_chr1_p(s$label), character(1))
    list(merges = sum(grepl("^reduce\\.level", labels)), calls = a$trace$calls)
  })
  expect_gte(shape[[1]]$merges, 2L)          # the tree really did branch
  expect_identical(shape[[2]], shape[[1]])   # and parallel recorded the same
})

test_that("every call a worker makes reaches the parent trace", {
  skip_if_no_future()
  f <- para_doc(6)
  both <- read_both("thorough", f)
  s <- hr_trace_summary(both$par$trace)
  # Six per-chunk calls plus the merge. Before the fix this was 1.
  expect_gte(s$calls, 6L)
  expect_gt(s$tokens_in, 0L)
  expect_false(any(is.na(hr_trace_cost(both$par$trace)$usd)))
  labels <- vapply(both$par$trace$steps, function(x) as_chr1_p(x$label), character(1))
  expect_true(sum(labels == "map.answer") >= 6L)
})

test_that("the assembled trace reads in input order, not completion order", {
  # Workers finish in whatever order they finish. A trace whose steps were
  # numbered by completion would differ from run to run, and two runs of the
  # same work would not be comparable.
  skip_if_no_future()
  f <- para_doc(6)
  cl <- hr_mock_client(function(messages, params) "Revenue was 45.2 million dollars.")
  a <- quiet(answer_document(f, "What was revenue?", "thorough", client = cl,
                             max_tokens = 40, parallel = TRUE))
  b <- quiet(answer_document(f, "What was revenue?", "thorough",
                             client = hr_mock_client(function(m, p) "Revenue was 45.2 million dollars."),
                             max_tokens = 40, parallel = TRUE))
  lab <- function(x) vapply(x$trace$steps, function(s) as_chr1_p(s$label), character(1))
  expect_identical(lab(a), lab(b))
  expect_identical(vapply(a$trace$steps, function(s) as.integer(s$step), integer(1)),
                   seq_along(a$trace$steps))
})

test_that("gr_lapply() hands the trace to its function either way", {
  # The sequential path must pass it through too, or the two paths diverge in
  # the one respect this whole change is about.
  gl <- harnessr:::gr_lapply
  tr <- harnessr:::hr_trace()
  got <- gl(1:3, function(i, trace) identical(trace, tr), parallel = FALSE, trace = tr)
  expect_true(all(unlist(got)))

  # And a NULL trace is not an error -- the OCR path has no trace to give.
  expect_identical(unlist(gl(1:3, function(i, trace) is.null(trace), parallel = FALSE)),
                   c(TRUE, TRUE, TRUE))
})

test_that("gr_lapply() absorbs worker traces, and is harmless without one", {
  skip_if_no_future()
  gl <- harnessr:::gr_lapply
  tr <- harnessr:::hr_trace()
  res <- gl(1:4, function(i, trace) {
    harnessr:::trace_record(trace, sprintf("w%d", i), list(),
                           harnessr:::gr_result(TRUE, "x", model = "mock-model",
                                               usage = list(input = 10L, output = 2L)))
    i * 2L
  }, parallel = TRUE, workers = 2, trace = tr)

  expect_identical(unlist(res), c(2L, 4L, 6L, 8L))     # results, in order
  expect_identical(tr$calls, 4L)                        # and every call recorded
  expect_identical(tr$tokens_in, 40L)
  expect_identical(tr$tokens_out, 8L)
  expect_identical(vapply(tr$steps, function(s) as_chr1_p(s$label), character(1)),
                   c("w1", "w2", "w3", "w4"))

  # No trace supplied: the work still runs and nothing errors.
  expect_identical(unlist(gl(1:3, function(i, trace) i + 1L, parallel = TRUE, workers = 2)),
                   c(2L, 3L, 4L))
})

test_that("a budget stop inside a worker is not lost", {
  # `budget_stop` is what marks an answer partial when the call cap bites. It is
  # set on the worker's trace, so it has to travel back with everything else.
  skip_if_no_future()
  gl <- harnessr:::gr_lapply
  tr <- harnessr:::hr_trace()
  gl(1:2, function(i, trace) { if (i == 2L) trace$budget_stop <- TRUE; i },
     parallel = TRUE, workers = 2, trace = tr)
  expect_true(tr$budget_stop)
})

test_that("workers see modules registered in the parent session", {
  skip_if_no_future()
  local_registries()
  gr_register_segmenter("seg", function(doc, spec, client, trace) list(doc))
  gr_register_reader("rd", function(chunks, question, client, spec, trace) "x",
                     signature = "all|1|none")
  # A worker loads the package afresh, so it knows these two only if the
  # document layer's worker hook handed its registries over.
  seen <- harnessr:::gr_lapply(1:2, function(i, trace) {
    c("seg" %in% harnessr::gr_segmenters()$name, "rd" %in% harnessr::gr_readers()$name)
  }, parallel = TRUE, workers = 2)
  expect_true(all(unlist(seen)))
})

test_that("workers see steps registered in the parent session", {
  skip_if_no_future()
  local_registries()
  hr_register("step", "shout", fn = function(input, ctx) toupper(input))
  expect_true("steps" %in% names(harnessr:::worker_state()$core))
  seen <- harnessr:::gr_lapply(1:2, function(i, trace) {
    "shout" %in% harnessr::hr_modules("step")$name
  }, parallel = TRUE, workers = 2)
  expect_true(all(unlist(seen)))
})

test_that("the document layer hands its module registries to workers", {
  layers <- harnessr:::worker_state()$layers
  expect_true("doc" %in% names(layers))
  expect_true(all(c("extractors", "cleaners", "segmenters", "readers", "embedders",
                    "protocols") %in% names(layers$doc$values)))
  expect_true(is.function(layers$doc$restore))
})

# ---------------------------------------------------------------------------
# The parallel matrix: every reader, and the ways a run can be set up, give
# the same record sequentially and across two workers.
# ---------------------------------------------------------------------------
#
# The tests above check counts on two recipes. These compare everything a run
# records, for every registered reader: each step of the trace with its clock
# fields taken out, the trace's totals, and the answer. The only difference
# allowed is the `parallel` setting the segment and preflight steps record,
# which says how the run was asked to go.
#
# The mock is golden_reply() from helper-golden.R: a reply chosen from the
# request alone, JSON where the reader asks for JSON and text otherwise, so a
# worker answers as the parent would.

par_matrix_doc <- function() {
  f <- tempfile(fileext = ".txt")
  writeLines(paste(sprintf("Paragraph %d. Revenue in region %d was %d million dollars this year. %s",
                           1:8, 1:8, 40 + 1:8,
                           strrep("Filler sentence about operations. ", 40)),
                   collapse = "\n\n"), f)
  f
}

# Readers that make their requests one after another by design, so a run of
# theirs never goes to the workers: refine and iterative carry each answer
# into the next request, and the others make one request.
par_matrix_sequential <- c("iterative", "refine", "retrieve", "screen", "stuff")

par_matrix_spec <- function(reader) {
  p <- golden_protocol()
  switch(reader,
         extract = gr_read_spec(reader, fields = p$fields),
         screen = gr_read_spec(reader, include = p$include),
         ensemble = gr_read_spec(reader, members = c("retrieve", "map_reduce", "refine")),
         gr_read_spec(reader))
}

par_matrix_recipe <- function(reader, segment = list(method = "paragraph", max_tokens = 150)) {
  gr_recipe(paste0("par-", reader), segment = segment, read = par_matrix_spec(reader))
}

# One run, with the messages it printed. `client` and `trace` are functions,
# so each run gets its own.
par_matrix_run <- function(par, recipe, client = function() hr_mock_client(golden_reply),
                           trace = function() NULL, file = par_matrix_doc()) {
  # The document cache keys on the ingest spec, which records `parallel`, so
  # a run is not served a document the run before it ingested.
  harnessr:::gr_flush_caches()
  msgs <- character(0)
  tr <- trace()
  ans <- withCallingHandlers(
    suppressWarnings(answer_document(file, golden_protocol()$question, recipe,
                                     client = client(), parallel = par, trace = tr)),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    })
  list(answer = ans, trace = ans$trace, messages = msgs)
}

# A step as the comparison sees it: no clock fields, and no `parallel` in the
# settings the segment and preflight steps record.
par_matrix_step <- function(st) {
  st <- st[setdiff(names(st), c("at", "started_utc", "ended_utc", "seconds"))]
  if (as_chr1_p(st$label) %in% c("segment", "preflight") && is.list(st$detail) &&
      is.list(st$detail$settings)) {
    set <- st$detail$settings
    set <- set[setdiff(names(set), "parallel")]
    st$detail$settings <- if (length(set)) set else list()
  }
  st
}

par_matrix_totals <- c("calls", "cached", "tokens_in", "tokens_out", "spent_usd", "refusals",
                       "errors", "budget_stop")

par_matrix_expect_same <- function(seq, par, info) {
  expect_identical(lapply(par$trace$steps, par_matrix_step),
                   lapply(seq$trace$steps, par_matrix_step), info = info)
  for (k in par_matrix_totals) {
    expect_identical(par$trace[[k]], seq$trace[[k]], info = paste(info, k))
  }
  expect_identical(par$answer$answer, seq$answer$answer, info = info)
}

par_matrix_compare <- function(recipe, info, workers = TRUE, file = par_matrix_doc(), ...) {
  seq <- par_matrix_run(FALSE, recipe, file = file, ...)
  par <- par_matrix_run(TRUE, recipe, file = file, ...)
  par_matrix_expect_same(seq, par, info)
  if (workers) {
    expect_true(any(grepl("across 2 workers", par$messages, fixed = TRUE)), info = info)
  }
  expect_false(any(grepl("across 2 workers", seq$messages, fixed = TRUE)), info = info)
  invisible(list(seq = seq, par = par))
}

local_par_matrix <- function(env = parent.frame()) {
  local_registries(env)
  # Two workers, a call cap far above what a run needs so the preflight
  # passes on both paths, and the messages that say the run went parallel.
  hr_options(workers = 2, max_calls = 500, verbose = TRUE)
}

test_that("every reader records the same run sequentially and across two workers", {
  skip_if_no_future()
  local_par_matrix()
  f <- par_matrix_doc()
  for (reader in gr_readers()$name) {
    par_matrix_compare(par_matrix_recipe(reader), info = reader,
                       workers = !reader %in% par_matrix_sequential, file = f)
  }
})

test_that("a parallel run through a response cache records what a sequential one does", {
  skip_if_no_future()
  local_par_matrix()
  # A fresh cache for each run, so neither is served by the other.
  par_matrix_compare(par_matrix_recipe("map_reduce"), info = "cache", client = function() {
    hr_cache_client(hr_mock_client(golden_reply), hr_cache(tempfile("par-cache")))
  })
})

test_that("a parallel replay records what a sequential replay does", {
  skip_if_no_future()
  local_par_matrix()
  f <- par_matrix_doc()
  rec <- par_matrix_recipe("map_reduce")
  recorded <- par_matrix_run(FALSE, rec, file = f)
  # A replay hands out its recording in order, so a batch it serves runs in
  # this process, one item at a time, and says so.
  out <- par_matrix_compare(rec, info = "replay", file = f, workers = FALSE,
                            client = function() hr_replay_client(recorded$trace))
  expect_true(any(grepl("one at a time: a replay", out$par$messages, fixed = TRUE)))
  expect_identical(out$par$answer$answer, recorded$answer$answer)
})

test_that("a parallel run under a parent trace keeps its draw index and scope", {
  skip_if_no_future()
  local_par_matrix()
  out <- par_matrix_compare(par_matrix_recipe("skim"), info = "parent trace", trace = function() {
    tr <- hr_trace()
    tr$draw_index <- 3L
    tr$draw_scope <- "armA"
    tr
  })
  req <- Filter(function(s) !identical(s$kind, "local"), out$par$trace$steps)
  expect_gt(length(req), 1L)
  expect_true(all(vapply(req, function(s) identical(as.integer(s$params$draw_index), 3L),
                         logical(1))))
  expect_true(all(vapply(req, function(s) identical(s$draw_scope, "armA"), logical(1))))
})

test_that("a parallel run under a raised effort records what a sequential one does", {
  skip_if_no_future()
  local_par_matrix()
  par_matrix_compare(par_matrix_recipe("map_reduce"), info = "effort raised",
                     trace = function() hr_trace(meta = list(effort_raised = "high")))
})

test_that("a model segmenter records the same run sequentially and across two workers", {
  skip_if_no_future()
  local_par_matrix()
  seg <- list(method = "contextual", context_source = "llm", max_tokens = 150)
  out <- par_matrix_compare(par_matrix_recipe("map_reduce", segment = seg),
                            info = "model segmenter")
  labels <- vapply(out$par$trace$steps, function(s) as_chr1_p(s$label), character(1))
  expect_gt(sum(labels == "segment.context"), 1L)
})

test_that("a user reader and tokenizer record the same run sequentially and across two workers", {
  skip_if_no_future()
  local_par_matrix()
  old_tok <- hr_tokenizer()
  on.exit(hr_set_tokenizer(old_tok), add = TRUE)
  hr_set_tokenizer("par_words", function(x) lengths(strsplit(trimws(x), "\\s+")))
  gr_register_reader("par_first", signature = "one|1|none", cost_calls = "1",
                     calls = "par_first.answer",
                     cost = function(input_stats, params) hr_cost(calls = 1),
                     fn = function(chunks, question, client, spec, trace) {
                       d <- chunks$chunks
                       res <- hr_call(client, list(list(
                         role = "user", content = paste0(d$text[1], "\n\nQuestion: ", question))),
                         trace = trace, label = "par_first.answer")
                       new_answer(res$text, "par_first", question, d$chunk_id[1], trace)
                     })
  seg <- list(method = "contextual", context_source = "llm", max_tokens = 150)
  rec <- gr_recipe("par-user", segment = seg, read = gr_read_spec("par_first"))
  out <- par_matrix_compare(rec, info = "user reader and tokenizer")
  labels <- vapply(out$par$trace$steps, function(s) as_chr1_p(s$label), character(1))
  expect_true("par_first.answer" %in% labels)
})
