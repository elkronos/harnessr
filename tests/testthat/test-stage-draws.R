# test-stage-draws.R: a stage that records on a trace of its own (gr_claims(),
# gr_outline(), gr_synthesise(), gr_read_many()) sends its requests at the
# draw index and draw scope of the trace it is given, and its governor holds
# the calls that trace has left.

draws_table <- function(n = 4L) {
  data.frame(document = paste0(letters[seq_len(n)], ".pdf"),
             document_id = paste0("h", seq_len(n)), status = "ok",
             duplicate_of = NA_character_, n_filled = 2L, n_unverified = 0L,
             conflicts = NA_character_,
             n = c(400L, 60L, 900L, 25L)[seq_len(n)],
             design = c("randomised trial", "cross-sectional", "randomised trial",
                        "qualitative")[seq_len(n)],
             finding = c("supports", "contradicts", "supports", "mixed")[seq_len(n)],
             stringsAsFactors = FALSE)
}

# A sampler: every request that reaches it gets a new reply number, and the
# draw index each request carried is kept.
draws_sampler <- function() {
  env <- new.env()
  env$n <- 0L
  env$draws <- integer()
  env$client <- gr_mock_client(function(messages, params) {
    env$n <- env$n + 1L
    env$draws <- c(env$draws, as.integer(params$draw_index %||% 0L))
    sys <- messages[[1]]$content
    if (grepl("turn a table of studies", sys, fixed = TRUE)) {
      return(sprintf(paste0('{"claims":[{"claim":"Claim %d.","kind":"finding",',
                            '"supported_by":[1,3],"contradicted_by":[],"moderator":null,',
                            '"scope":null}]}'), env$n))
    }
    if (grepl("sections", sys, ignore.case = TRUE) && grepl("claims", sys, fixed = TRUE) &&
        !grepl("[study", sys, fixed = TRUE)) {
      return('{"sections":[{"heading":"A","brief":"first","claims":[1],"rationale":null}]}')
    }
    sprintf("Section text %d [study 1].", env$n)
  })
  env
}

draws_cache <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  gr_cache(dir = dir)
}

test_that("gr_claims sends the given trace's draw index, so a cache keeps the draws apart", {
  s <- draws_sampler()
  cache <- draws_cache()
  ccl <- gr_cache_client(s$client, cache)
  got <- vapply(1:3, function(r) {
    tr <- gr_trace()
    tr$draw_index <- r
    cm <- quiet(gr_claims(draws_table(), question = "Q?", client = ccl, temperature = 1,
                          trace = tr))
    st <- Filter(function(x) !is.null(x$model), tr$steps)
    expect_identical(vapply(st, function(x) as.integer(x$params$draw_index), 1L), r)
    paste(cm$claims$claim, collapse = ";")
  }, character(1))
  expect_identical(got, c("Claim 1.", "Claim 2.", "Claim 3."))
  expect_identical(s$draws, 1:3)
  expect_identical(gr_cache_stats(cache)$hits, 0L)

  # A trace with no draw index sends draw 0, as it always did.
  tr <- gr_trace()
  quiet(gr_claims(draws_table(), question = "Q?", client = ccl, temperature = 1, trace = tr))
  expect_identical(tail(s$draws, 1L), 0L)
})

test_that("gr_synthesise sends the given trace's draw index, so a cache keeps the draws apart", {
  s <- draws_sampler()
  cache <- draws_cache()
  ccl <- gr_cache_client(s$client, cache)
  got <- vapply(1:3, function(r) {
    tr <- gr_trace()
    tr$draw_index <- r
    tr$draw_scope <- "arm"
    syn <- quiet(gr_synthesise(draws_table(), question = "Q?",
                               outline = c(Findings = "What they found"),
                               client = ccl, temperature = 1, trace = tr))
    st <- Filter(function(x) !is.null(x$model), tr$steps)
    expect_true(all(vapply(st, function(x) identical(x$draw_scope, "arm"), logical(1))))
    syn$sections$text[1]
  }, character(1))
  expect_length(unique(got), 3L)
  expect_true(all(s$draws %in% 1:3))
  expect_identical(sort(unique(s$draws)), 1:3)
  expect_identical(gr_cache_stats(cache)$hits, 0L)
})

test_that("gr_read_many sends the given trace's draw index", {
  d <- withr::local_tempdir()
  writeLines("Revenue was 45.2 million dollars in 2024.", file.path(d, "a.txt"))
  writeLines("Revenue was 12 million dollars in 2023.", file.path(d, "b.txt"))
  s <- draws_sampler()
  tr <- gr_trace()
  tr$draw_index <- 4L
  quiet(gr_read_many(d, "What was revenue?", recipe = "fast", client = s$client, trace = tr))
  expect_gt(length(s$draws), 0L)
  expect_true(all(s$draws == 4L))
})

test_that("an hr_benchmark arm that calls gr_claims on ctx$trace makes distinct draws", {
  s <- draws_sampler()
  cache <- draws_cache()
  ccl <- gr_cache_client(s$client, cache)
  ref <- hr_reference(items = list(q1 = "Q?"), labels = "x", cluster = "a", split = "test")
  arm <- hr_arm("claims", function(item, ctx) {
    # As a recipe arm does (see doc_arm_run()).
    ctx$trace$draw_index <- ctx$draw_index
    cm <- quiet(gr_claims(draws_table(), question = item, client = ctx$client,
                          temperature = 1, trace = ctx$trace))
    paste(cm$claims$claim, collapse = ";")
  })
  b <- quiet(hr_benchmark(list(arm), ref, runs = 5, client = ccl, scorer = hr_scorer_exact()))
  d <- as.data.frame(b)
  expect_identical(nrow(d), 5L)
  expect_identical(sort(s$draws), 1:5)
  expect_identical(gr_cache_stats(cache)$hits, 0L)
})

test_that("a stage forked from a trace holds the calls the trace's governor has left", {
  cl <- gr_mock_client(function(messages, params) {
    if (grepl("turn a table of studies", messages[[1]]$content, fixed = TRUE)) {
      return(paste0('{"claims":[{"claim":"C.","kind":"finding","supported_by":[1,3],',
                    '"contradicted_by":[],"moderator":null,"scope":null}]}'))
    }
    "Section text [study 1]."
  })
  par <- gr_trace(governor = hr_governor(max_calls = 2))
  gr_call(cl, "one", trace = par)
  gr_call(cl, "two", trace = par)
  expect_identical(harnessr:::fork_governor(par)$max_calls, 0)
  cm <- quiet(gr_claims(draws_table(), question = "Q?", client = cl, trace = par))
  expect_identical(par$calls, 2L)
  expect_identical(nrow(cm$claims), 0L)
  quiet(gr_synthesise(draws_table(), question = "Q?", outline = c(A = "a", B = "b"),
                      client = cl, trace = par))
  expect_identical(par$calls, 2L)
  expect_length(cl$calls(), 2L)

  # One call left: the stage may make one, not two.
  par2 <- gr_trace(governor = hr_governor(max_calls = 2))
  gr_call(cl, "one", trace = par2)
  expect_identical(harnessr:::fork_governor(par2)$max_calls, 1)
  quiet(gr_synthesise(draws_table(), question = "Q?", outline = c(A = "a", B = "b"),
                      client = cl, trace = par2))
  expect_identical(par2$calls, 2L)

  # Cache hits and embeddings requests are calls to the governor, and the
  # fork takes them off too.
  cache <- draws_cache()
  ccl <- gr_cache_client(cl, cache)
  par3 <- gr_trace(governor = hr_governor(max_calls = 3))
  gr_call(ccl, "same", trace = par3)
  gr_call(ccl, "same", trace = par3)
  expect_identical(par3$cached, 1L)
  expect_identical(harnessr:::fork_governor(par3)$max_calls, 1)
})

test_that("an hr_benchmark run's governor holds a stage's calls to what the run has left", {
  cl <- gr_mock_client(function(messages, params) {
    if (grepl("turn a table of studies", messages[[1]]$content, fixed = TRUE)) {
      return(paste0('{"claims":[{"claim":"C.","kind":"finding","supported_by":[1,3],',
                    '"contradicted_by":[],"moderator":null,"scope":null}]}'))
    }
    "x"
  })
  ref <- hr_reference(items = list(q1 = "Q?"), labels = "x", cluster = "a", split = "test")
  arm <- hr_arm("a", function(item, ctx) {
    ctx$call("one")
    ctx$call("two")
    quiet(gr_claims(draws_table(), question = item, client = ctx$client, trace = ctx$trace))
    "x"
  })
  b <- quiet(hr_benchmark(list(arm), ref, runs = 1, client = cl, scorer = hr_scorer_exact(),
                          governor = hr_governor(max_calls = 2)))
  expect_length(cl$calls(), 2L)
})

test_that("the items of a parallel batch carry the run's draw index and scope", {
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")
  cl <- gr_mock_client(function(messages, params) "ok")
  tr <- gr_trace()
  tr$draw_index <- 3L
  tr$draw_scope <- "arm"
  quiet(harnessr:::gr_lapply(1:4, function(i, trace) {
    gr_call(cl, sprintf("item %d", i), trace = trace, temperature = 1)
  }, parallel = TRUE, workers = 2, trace = tr, client = cl))
  st <- Filter(function(x) !is.null(x$model), tr$steps)
  expect_length(st, 4L)
  expect_true(all(vapply(st, function(x) identical(as.integer(x$params$draw_index), 3L),
                         logical(1))))
  expect_true(all(vapply(st, function(x) identical(x$draw_scope, "arm"), logical(1))))
})

test_that("a recording made before stages carried the draw index still replays", {
  # A stage's requests were sent at draw 0 before its trace carried the run's
  # draw index. A replay that now asks for draw 1 is answered with the reply
  # recorded at draw 0, marked as served without its own draw key.
  s <- draws_sampler()
  rec <- gr_trace()
  quiet(gr_claims(draws_table(), question = "Q?", client = s$client, temperature = 1,
                  trace = rec))
  expect_identical(unique(s$draws), 0L)
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  gr_trace_save(rec, path)

  tr <- gr_trace()
  tr$draw_index <- 1L
  cm <- quiet(gr_claims(draws_table(), question = "Q?", client = gr_replay_client(path),
                        temperature = 1, trace = tr))
  expect_identical(cm$claims$claim[[1]], "Claim 1.")
  req <- Filter(function(st) !is.null(st$prompt), tr$steps)
  expect_true(length(req) > 0L)
  expect_true(all(vapply(req, function(st) isTRUE(st$cached) && !is.character(st$replay_key),
                         logical(1))))
  # A second draw has nothing recorded for it and runs out, as before.
  tr2 <- gr_trace()
  tr2$draw_index <- 2L
  expect_error(quiet(gr_claims(draws_table(), question = "Q?", client = gr_replay_client(path),
                               temperature = 1, trace = tr2)),
               class = "hr_replay_exhausted")
})
