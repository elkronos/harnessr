# test-compose.R: hr_step(), hr_chain() and the built-in steps as hr_steps.

compose_reference <- function() {
  gr_qa_reference(questions = c(revenue = "What was revenue in 2024?",
                                units = "How many units did Sheffield produce?"),
                  documents = gr_example(), answers = list("45.2 million", "12,400"),
                  split = "test")
}

compose_client <- function() {
  gr_mock_client(function(messages, params) {
    if (grepl("You grade one response", messages[[1]]$content, fixed = TRUE)) {
      return('{"verdict": "pass", "reason": "same figure"}')
    }
    "Revenue was 45.2 million dollars."
  })
}

compose_schema <- function() {
  hr_schema(hr_param("marks", "integer", default = 1L, min = 0, max = 5,
                     evidence = ev_untested("A test setting.")))
}

compose_shout <- function(...) {
  hr_step("shout", function(input, ctx) {
    paste0(toupper(input), strrep("!", ctx$step_params$marks))
  }, schema = compose_schema(), ...)
}

compose_steps <- function(top_k = 4) {
  list(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = top_k),
       read = gr_step("read", reader = "stuff"))
}

compose_judge <- function() {
  hr_step("judge", function(a, ctx) {
    j <- ctx$judge(a$answer, mode = "grade", reference = "45.2 million",
                   rubric = "Does it give the figure?", orders = 1)
    ctx$note("judged", j$verdicts$verdict[1])
    a
  })
}

# ---------------------------------------------------------------------------
# hr_step()
# ---------------------------------------------------------------------------

test_that("hr_step() checks its function, name and declarations", {
  ok <- function(input, ctx) input
  expect_error(hr_step("a", fn = 1), class = "hr_bad_step")
  expect_error(hr_step("a", fn = function(x) x), class = "hr_bad_step")
  expect_error(hr_step("a"), class = "hr_bad_step")
  expect_error(hr_step("a", fn = ok, build = function(p) ok), class = "hr_bad_step")
  expect_error(hr_step("a", build = function(p) 1), class = "hr_bad_step")
  expect_error(hr_step("a", build = "nope"), class = "hr_bad_step")
  expect_error(hr_step("", ok), class = "hr_bad_step")
  expect_error(hr_step(c("a", "b"), ok), class = "hr_bad_step")
  expect_error(hr_step("a", ok, input = "chunk"), class = "hr_bad_step")
  expect_error(hr_step("a", ok, output = c("doc", "chunks")), class = "hr_bad_step")
  expect_error(hr_step("a", ok, version = ""), class = "hr_bad_step")
  expect_error(hr_step("a", ok, params = list(1)), class = "hr_bad_step")
  expect_error(hr_step("a", ok, params = list(x = 1, x = 2)), class = "hr_bad_step")
  expect_error(hr_step("a", ok, schema = list()), class = "hr_bad_step")
  expect_error(hr_step("a", ok, skill = "x"), class = "hr_bad_step")
  # A function of dots is enough.
  expect_s3_class(hr_step("dots", function(...) 1), "hr_step")
  # Dots are allowed in a step's own name; hr_chain() refuses them.
  expect_identical(attr(hr_step("a.b", ok), "name"), "a.b")
})

test_that("hr_step() resolves settings against its schema", {
  s <- compose_shout(params = list(marks = 2L))
  expect_s3_class(s, c("hr_step", "function"), exact = TRUE)
  expect_identical(attr(s, "params"), list(marks = 2L))
  expect_identical(attr(s, "resolved"), list(marks = 2L))
  expect_identical(attr(s, "extras"), list())
  expect_identical(attr(compose_shout(), "resolved"), list(marks = 1L))
  expect_identical(s("hi", list(step_params = attr(s, "resolved"))), "HI!!")
  expect_warning(s9 <- compose_shout(params = list(marks = 9L)), class = "gr_clamped")
  expect_identical(attr(s9, "resolved")$marks, 5L)
  # Without a schema, params are kept as given.
  p <- hr_step("p", function(input, ctx) input, params = list(a = 1, b = "x"))
  expect_identical(attr(p, "resolved"), list(a = 1, b = "x"))
  expect_null(attr(p, "schema"))
  expect_output(print(s), "<hr_step> shout \\(\\? to \\?\\) version 0.0.1")
  expect_output(print(s), "marks = 2")
})

test_that("a setting the schema does not name is refused, unless build takes it", {
  err <- expect_error(compose_shout(params = list(mark = 2L)), class = "hr_unknown_param")
  expect_s3_class(err, "hr_unknown_setting")
  expect_match(conditionMessage(err), "'mark'")
  # With build, a setting outside the schema is a fixed extra.
  got <- NULL
  b <- hr_step("b", build = function(params) {
    got <<- params
    function(input, ctx) params$extra
  }, params = list(marks = 3L, extra = "kept"), schema = compose_schema())
  expect_identical(got, list(marks = 3L, extra = "kept"))
  expect_identical(attr(b, "resolved"), list(marks = 3L))
  expect_identical(attr(b, "extras"), list(extra = "kept"))
  expect_identical(b(NULL, NULL), "kept")
  # gr_step() keeps settings the read schema does not name as extras.
  r <- quiet(gr_step("read", reader = "stuff", my_opt = 3))
  expect_identical(attr(r, "extras"), list(my_opt = 3))
  expect_identical(attr(r, "spec")$my_opt, 3)
})

test_that("build is called when the step is built", {
  n <- 0L
  hr_step("b", build = function(params) {
    n <<- n + 1L
    if (!isTRUE(params$ok)) stop("not ok")
    function(input, ctx) input
  }, params = list(ok = TRUE))
  expect_identical(n, 1L)
  expect_error(hr_step("b", build = function(params) {
    if (!isTRUE(params$ok)) stop("not ok")
    function(input, ctx) input
  }, params = list(ok = FALSE)), "not ok")
})

test_that("gr_step() and gr_step_retrieve() are hr_steps with their schemas", {
  s <- gr_step("read", reader = "stuff", name = "answer")
  expect_s3_class(s, c("gr_step", "hr_step", "function"), exact = TRUE)
  expect_identical(attr(s, "params"), list(reader = "stuff"))
  expect_identical(attr(s, "input"), "chunks")
  expect_identical(attr(s, "output"), "answer")
  expect_identical(attr(s, "version"), as.character(utils::packageVersion("harnessr")))
  expect_identical(names(attr(s, "schema")), names(.gr_read_schema))
  expect_identical(attr(s, "spec"), gr_read_spec("stuff"))
  expect_identical(attr(gr_step("ingest"), "input"), "document")
  expect_identical(attr(gr_step("ingest"), "output"), "doc")
  expect_identical(attr(gr_step("segment"), "input"), "doc")
  expect_identical(attr(gr_step("segment"), "output"), "chunks")
  r <- gr_step_retrieve(3, mmr = 0.5, cite = TRUE)
  expect_identical(names(attr(r, "schema")),
                   intersect(names(.gr_read_schema), c("top_k", "min_score", "mmr", "fusion",
                                                       "rrf_k", "lexical_blend", "bm25_k1",
                                                       "bm25_b")))
  expect_identical(attr(r, "params"), list(top_k = 3, mmr = 0.5, cite = TRUE))
  expect_identical(attr(r, "extras"), list(cite = TRUE))
  expect_identical(attr(r, "spec"), gr_read_spec("retrieve", top_k = 3, mmr = 0.5, cite = TRUE))
  expect_identical(attr(gr_step_retrieve(), "params"), list())
  expect_identical(attr(gr_step_retrieve(), "spec"), gr_read_spec("retrieve"))
  # Settings given by position or by a partial name reach the spec as before.
  sg <- gr_step("segment", "sentence", 300)
  expect_identical(attr(sg, "params"), list(method = "sentence", max_tokens = 300))
  expect_identical(attr(sg, "spec"), gr_segment_spec("sentence", 300))
  expect_identical(attr(gr_step("read", top = 3), "spec"), gr_read_spec(top = 3))
})

test_that("a built-in step warns about a setting once", {
  n <- 0L
  withCallingHandlers(gr_step("read", effort = "hihg"), warning = function(w) {
    n <<- n + 1L
    invokeRestart("muffleWarning")
  })
  expect_identical(n, 1L)
  n <- 0L
  withCallingHandlers(gr_step("segment", max_tokens = 5), warning = function(w) {
    n <<- n + 1L
    invokeRestart("muffleWarning")
  })
  expect_identical(n, 1L)
})

# ---------------------------------------------------------------------------
# hr_chain(): building, deriving and checking the order
# ---------------------------------------------------------------------------

test_that("hr_chain() builds an arm from steps", {
  st <- compose_steps()
  ch <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read, name = "c")
  expect_s3_class(ch, "hr_arm")
  expect_identical(ch$name, "c")
  expect_identical(names(attr(ch, "hr_steps")), c("segment", "retrieve", "read"))
  expect_identical(ch$params, list(retrieve.top_k = 4, read.reader = "stuff"))
  expect_identical(attr(ch, "hr_settings"), ch$params)
  expect_true(all(c("segment.max_tokens", "retrieve.top_k", "read.reader") %in%
                    attr(ch, "hr_known")))
  expect_false("retrieve.reader" %in% attr(ch, "hr_known"))
  expect_true(is.character(attr(ch, "hr_config")))
  # Unnamed steps keep their own names; an argument name wins and is written in.
  ch2 <- hr_chain(st$segment, st$retrieve, answer = st$read, name = "c2")
  expect_identical(names(attr(ch2, "hr_steps")), c("segment", "retrieve", "answer"))
  expect_identical(attr(attr(ch2, "hr_steps")$answer, "name"), "answer")
  expect_identical(ch2$params, list(retrieve.top_k = 4, answer.reader = "stuff"))
})

test_that("hr_chain() derives a chain by dropping, replacing and adding steps", {
  st <- compose_steps()
  checked <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read,
                      judge = compose_judge(), name = "checked")
  nojudge <- hr_chain(checked, judge = NULL, name = "nojudge")
  expect_identical(names(attr(nojudge, "hr_steps")), c("segment", "retrieve", "read"))
  wider <- hr_chain(checked, retrieve = gr_step_retrieve(top_k = 8), name = "wider")
  expect_identical(names(attr(wider, "hr_steps")), c("segment", "retrieve", "read", "judge"))
  expect_identical(wider$params$retrieve.top_k, 8)
  more <- hr_chain(nojudge, tidy = hr_step("tidy", function(a, ctx) a, input = "answer"),
                   name = "more")
  expect_identical(names(attr(more, "hr_steps")), c("segment", "retrieve", "read", "tidy"))
  # The original is unchanged.
  expect_identical(names(attr(checked, "hr_steps")), c("segment", "retrieve", "read", "judge"))
  expect_error(hr_chain(checked, judge = NULL), class = "hr_bad_chain")
  expect_error(hr_chain(checked, nothing = NULL, name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(st$segment, read = NULL, name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(hr_arm("plain", function(item, ctx) item), st$read, name = "x"),
               class = "hr_bad_chain")
  expect_error(hr_chain(checked, judge = NULL, judge = compose_judge(), name = "x"),
               class = "hr_bad_chain")
  expect_error(hr_chain(checked, segment = NULL, retrieve = NULL, read = NULL, judge = NULL,
                        name = "x"), class = "hr_bad_chain")
})

test_that("hr_chain() refuses bad names and arguments", {
  st <- compose_steps()
  expect_error(hr_chain(st$segment, st$segment, name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(a = st$segment, a = st$read, name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(seg.ment = st$segment, name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(hr_step("a.b", function(x, ctx) x), name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(hr_step("version", function(x, ctx) x), name = "x"),
               class = "hr_bad_chain")
  expect_error(hr_chain(hr_step("name", function(x, ctx) x), name = "x"),
               class = "hr_bad_chain")
  expect_error(hr_chain(st$segment), class = "hr_bad_chain")
  expect_error(hr_chain(st$segment, name = ""), class = "hr_bad_chain")
  expect_error(hr_chain(st$segment, name = "x", version = ""), class = "hr_bad_chain")
  expect_error(hr_chain(name = "x"), class = "hr_bad_chain")
  expect_error(hr_chain(function(x, ctx) x, name = "x"), class = "hr_bad_chain")
})

test_that("hr_chain() warns about a gap and refuses a step that cannot follow an answer", {
  st <- compose_steps()
  expect_warning(hr_chain(read = st$read, name = "x"), class = "hr_chain_gap")
  expect_warning(hr_chain(retrieve = st$retrieve, read = st$read, name = "x"),
                 class = "hr_chain_gap")
  expect_no_warning(hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read,
                             name = "x"))
  expect_no_warning(hr_chain(ingest = gr_step("ingest"), segment = st$segment,
                             read = st$read, name = "x"))
  expect_error(hr_chain(segment = st$segment, read = st$read, retrieve = st$retrieve,
                        name = "x"), class = "hr_bad_chain")
  # A step that takes the answer, or declares nothing, may follow it.
  expect_s3_class(hr_chain(segment = st$segment, read = st$read, judge = compose_judge(),
                           tidy = hr_step("tidy", function(a, ctx) a, input = "answer"),
                           log = hr_step("log", function(a, ctx) a, input = "state"),
                           name = "x"), "hr_arm")
})

# ---------------------------------------------------------------------------
# Running a chain
# ---------------------------------------------------------------------------

test_that("a step sees the arm's params as ctx$params, and its own settings", {
  seen <- new.env()
  look <- hr_step("look", function(input, ctx) {
    seen$params <- ctx$params
    seen$step <- ctx$step
    seen$step_params <- ctx$step_params
    "45.2 million"
  }, params = list(marks = 3L), schema = compose_schema())
  ch <- hr_chain(peek = look, name = "looked")
  b <- quiet(hr_benchmark(ch, compose_reference(), runs = 1, client = compose_client(),
                          scorer = gr_scorer_answer()))
  expect_identical(nrow(b), 2L)
  expect_identical(seen$params, ch$params)
  expect_identical(seen$params, list(peek.marks = 3L))
  expect_identical(seen$step, "peek")
  expect_identical(seen$step_params, list(marks = 3L))
  expect_identical(b$param.peek.marks, c(3L, 3L))
  # Called outside a benchmark, the chain still runs with a bare context.
  expect_identical(ch$run(list(), NULL), "45.2 million")
})

test_that("a chain sends the requests the same steps folded by hand send", {
  cl1 <- compose_client()
  cl2 <- compose_client()
  st <- compose_steps()
  hand <- hr_arm("composed", function(item, ctx) {
    Reduce(function(x, step) step(x, ctx), st, item)
  })
  chain <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read,
                    name = "composed")
  b1 <- quiet(hr_benchmark(hand, compose_reference(), runs = 2, client = cl1,
                           scorer = gr_scorer_answer()))
  b2 <- quiet(hr_benchmark(chain, compose_reference(), runs = 2, client = cl2,
                           scorer = gr_scorer_answer()))
  t1 <- attr(b1, "traces")
  t2 <- attr(b2, "traces")
  for (i in seq_len(nrow(b1))) {
    expect_identical(request_fingerprints(t2[[b2$ledger_id[i]]]),
                     request_fingerprints(t1[[b1$ledger_id[i]]]))
  }
  expect_identical(b2$answer, b1$answer)
  expect_identical(b2$correct, b1$correct)
})

test_that("a chain of the compose-steps record sends the recorded requests", {
  run <- function() golden_request_run(function(cl) {
    ch <- hr_chain(segment = gr_step("segment"), retrieve = gr_step_retrieve(top_k = 4),
                   read = gr_step("read", reader = "stuff"), name = "composed")
    hr_benchmark(ch, golden_compose_reference(), runs = 1, client = cl,
                 scorer = gr_scorer_answer())
  })
  path <- file.path(golden_dir(), "compose-steps.json")
  expect_true(file.exists(path))
  d <- golden_diff(golden_read(path), golden_roundtrip(run()), path = "compose-steps")
  expect(length(d) == 0L, paste(c("compose-steps as a chain changed:", utils::head(d, 10)),
                                collapse = "\n"))
})

# ---------------------------------------------------------------------------
# Hashes and configurations
# ---------------------------------------------------------------------------

test_that("a chain built twice has the same hash and configuration", {
  a <- hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
                name = "c")
  b <- hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
                name = "c")
  expect_identical(a$hash, b$hash)
  expect_identical(attr(a, "hr_config"), attr(b, "hr_config"))
  expect_identical(arm_config(a), attr(a, "hr_config"))
  # Saved and read back, it keeps both.
  f <- tempfile(fileext = ".rds")
  saveRDS(a, f)
  back <- readRDS(f)
  expect_identical(back$hash, a$hash)
  expect_identical(attr(back, "hr_config"), attr(a, "hr_config"))
})

test_that("steps that differ only in the values their code reads give different hashes", {
  make <- function(prompt) hr_step("ask", function(item, ctx) paste(prompt, item))
  a <- hr_chain(ask = make("Answer briefly:"), name = "c")
  b <- hr_chain(ask = make("Answer in full:"), name = "c")
  expect_false(identical(attr(make("x"), "fingerprint"), attr(make("y"), "fingerprint")))
  expect_false(identical(a$hash, b$hash))
  expect_false(identical(attr(a, "hr_config"), attr(b, "hr_config")))
  expect_identical(a$run("q", NULL), "Answer briefly: q")
})

test_that("settings change the configuration; a setting at its default does not", {
  st <- compose_steps()
  two <- hr_chain(segment = st$segment, retrieve = gr_step_retrieve(top_k = 2),
                  read = st$read, name = "c")
  eight <- hr_chain(segment = st$segment, retrieve = gr_step_retrieve(top_k = 8),
                    read = st$read, name = "c")
  expect_false(identical(attr(two, "hr_config"), attr(eight, "hr_config")))
  expect_false(identical(two$hash, eight$hash))
  plain <- hr_chain(segment = st$segment, retrieve = gr_step_retrieve(), read = st$read,
                    name = "c")
  six <- hr_chain(segment = st$segment, retrieve = gr_step_retrieve(top_k = 6),
                  read = st$read, name = "c")
  expect_identical(attr(plain, "hr_config"), attr(six, "hr_config"))
  # The settings as given still differ, so the arms record them.
  expect_identical(plain$params, list(read.reader = "stuff"))
  expect_identical(six$params, list(retrieve.top_k = 6, read.reader = "stuff"))
  # So the benchmark warns that the two are one configuration.
  classes <- character(0)
  withCallingHandlers(
    suppressMessages(hr_benchmark(list(plain, hr_chain(six, name = "six")),
                                  compose_reference(), runs = 1, client = compose_client(),
                                  scorer = gr_scorer_answer())),
    warning = function(w) {
      classes <<- c(classes, class(w))
      invokeRestart("muffleWarning")
    })
  expect_true("hr_same_config" %in% classes)
  # The step's own version and the chain's version are part of the configuration.
  v2 <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read, name = "c",
                 version = "0.0.2")
  v1 <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read, name = "c")
  expect_false(identical(attr(v1, "hr_config"), attr(v2, "hr_config")))
})

test_that("a renamed chain keeps its steps", {
  st <- compose_steps()
  arms <- hr_sweep(function(k) {
    hr_chain(segment = st$segment, retrieve = gr_step_retrieve(top_k = k), read = st$read,
             name = "swept")
  }, list(k = c(2, 8)))
  expect_length(arms, 2L)
  for (a in arms) {
    expect_identical(names(attr(a, "hr_steps")), c("segment", "retrieve", "read"))
  }
  expect_identical(arms[[2]]$params$retrieve.top_k, 8)
})

test_that("a chain and the chain without its judge benchmark under a cache", {
  st <- compose_steps()
  checked <- hr_chain(segment = st$segment, retrieve = st$retrieve, read = st$read,
                      judge = compose_judge(), name = "checked")
  nojudge <- hr_chain(checked, judge = NULL, name = "nojudge")
  cl <- gr_cache_client(compose_client(), gr_cache(tempfile("compose-")))
  b <- expect_no_error(quiet(hr_benchmark(list(checked, nojudge), compose_reference(),
                                          runs = 2, client = cl,
                                          scorer = gr_scorer_answer())))
  expect_identical(nrow(b), 8L)
  expect_false(any(b$failure_kind %in% c("error", "budget_stop")))
  s <- hr_signals(b, "judged")
  expect_identical(unique(s$arm), "checked")
  expect_identical(nrow(s), 4L)
})
