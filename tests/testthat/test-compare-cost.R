# The cost columns of gr_compare(): what each recipe cost, the share of it
# priced from estimated token counts, and what a right answer cost.

cost_doc <- function(n = 6L) {
  paste(sprintf("Paragraph %d. Revenue was 45.2 million dollars in year %d, and costs were flat.",
                seq_len(n), 2000L + seq_len(n)), collapse = "\n\n")
}

priced_mock <- function(env = parent.frame()) {
  local_registries(env)
  gr_register_model("cmp-priced", context_window = 8000, max_output = 500,
                    input_usd = 2, output_usd = 8)
  gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
}

usd_of <- function(trace) sum(gr_trace_cost(trace)$usd)

two_readers <- function(segment = list(method = "paragraph", max_tokens = 40,
                                       overlap_tokens = 0)) {
  list(stuffed = gr_recipe("stuffed", segment = segment, read = list(reader = "stuff")),
       mapped = gr_recipe("mapped", segment = segment, read = list(reader = "map_reduce")))
}

test_that("each recipe's row says what its requests cost at the registered price", {
  cl <- priced_mock()
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced"))
  s <- cmp$summary
  expect_true(all(c("calls", "tokens_in", "tokens_out", "usd", "usd_estimated") %in% names(s)))
  expect_false(any(c("correct", "usd_per_correct") %in% names(s)))
  for (nm in s$recipe) {
    own <- gr_trace_cost(cmp$answers[[nm]]$trace)
    row <- s[s$recipe == nm, ]
    expect_equal(row$usd, sum(own$usd))
    expect_equal(row$calls, sum(own$calls))
    expect_equal(row$tokens_in, sum(own$paid_in))
    expect_equal(row$tokens_out, sum(own$paid_out))
    expect_gt(row$usd, 0)
  }
  # map_reduce reads every chunk, stuff reads once: the costs must differ.
  expect_gt(s$calls[s$recipe == "mapped"], s$calls[s$recipe == "stuffed"])
  # Nothing is shared here, so the rows add up to what the comparison spent.
  expect_equal(sum(s$usd), usd_of(cmp$trace))
})

test_that("a shared chunking is charged to every recipe that used it", {
  cl <- priced_mock()
  # The chunk contexts are written by the mock's own model, so price it too.
  gr_register_model("mock-model", context_window = 128000L, max_output = 16384L,
                    input_usd = 1, output_usd = 4)
  seg <- list(method = "contextual", context_source = "llm", max_tokens = 40,
              overlap_tokens = 0)
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(seg), client = cl,
                          model = "cmp-priced"))
  s <- cmp$summary
  shared <- Filter(function(st) is.na(as.character(st$recipe %||% NA)), cmp$trace$steps)
  shared <- Filter(function(st) !identical(st$kind, "local") && is.list(st$tokens), shared)
  expect_gt(length(shared), 0L)
  seg_usd <- usd_of(structure(list(steps = shared), class = "gr_trace"))
  expect_gt(seg_usd, 0)
  read_usd <- function(nm) {
    mine <- Filter(function(st) identical(st$recipe, nm), cmp$trace$steps)
    usd_of(structure(list(steps = mine), class = "gr_trace"))
  }
  for (nm in s$recipe) {
    expect_equal(s$usd[s$recipe == nm], seg_usd + read_usd(nm))
  }
  # Each is charged as if run alone, so together they come to more than was spent.
  expect_equal(sum(s$usd), usd_of(cmp$trace) + seg_usd)
  # The second recipe made no segmentation requests, but is counted for them,
  # as max_calls counts them.
  expect_equal(s$calls[2], length(shared) +
                 length(Filter(function(st) identical(st$recipe, "mapped") &&
                                 !identical(st$kind, "local") && is.list(st$tokens),
                               cmp$trace$steps)))
})

test_that("correct = strings adds whether each answer was right and its cost", {
  cl <- priced_mock()
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced", correct = c("45.2  MILLION")))
  s <- cmp$summary
  expect_identical(s$correct, c(TRUE, TRUE))
  expect_equal(s$usd_per_correct, s$usd)

  wrong <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                            model = "cmp-priced", correct = "99 million"))
  expect_identical(wrong$summary$correct, c(FALSE, FALSE))
  expect_identical(wrong$summary$usd_per_correct, c(Inf, Inf))
})

test_that("a pattern character in the expected text is matched as written", {
  cl <- priced_mock()
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          model = "cmp-priced", correct = "45.2 million dollars."))
  expect_true(cmp$summary$correct)
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          model = "cmp-priced", correct = "45x2"))
  expect_false(cmp$summary$correct)
})

test_that("correct = a function decides, and NA means not known", {
  cl <- priced_mock()
  seen <- character(0)
  judge <- function(a) {
    seen <<- c(seen, class(a)[1])
    if (identical(a$recipe, "stuffed")) TRUE else NA
  }
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced", correct = judge))
  expect_identical(seen, c("gr_answer", "gr_answer"))
  expect_identical(cmp$summary$correct, c(TRUE, NA))
  expect_equal(cmp$summary$usd_per_correct, c(cmp$summary$usd[1], NA))

  expect_error(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          correct = 1), "`correct`", class = "gr_bad_correct")
  expect_error(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          correct = c("a", "")), "`correct`", class = "gr_bad_correct")
})

test_that("a correct function that fails or returns a non-logical costs one cell, not the run", {
  cl <- priced_mock()
  for (judge in list(function(a) stop("judge broke"), function(a) "yes")) {
    warned <- character(0)
    cmp <- withCallingHandlers(
      suppressMessages(gr_compare(cost_doc(), "What was revenue?", two_readers(),
                                  client = cl, model = "cmp-priced", correct = judge)),
      gr_bad_correct = function(w) {
        warned <<- c(warned, conditionMessage(w))
        invokeRestart("muffleWarning")
      })
    expect_length(warned, 2L)
    expect_match(warned, "recipe '(stuffed|mapped)'")
    expect_identical(cmp$summary$correct, c(NA, NA))
    expect_identical(cmp$summary$usd_per_correct, c(NA_real_, NA_real_))
    expect_true(all(cmp$summary$usd > 0))
    expect_length(cmp$answers, 2L)
    expect_gt(length(cmp$trace$steps), 0L)
  }
})

test_that("a recipe a spending limit stopped before it found anything is not known, not wrong", {
  cl <- priced_mock()
  one <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          model = "cmp-priced"))
  # Room for the first recipe and nothing after it.
  old <- gr_options("max_cost_usd")
  on.exit(gr_options(max_cost_usd = old), add = TRUE)
  gr_options(max_cost_usd = one$summary$usd * 1.01)
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced", correct = "45.2 million"))
  s <- cmp$summary
  expect_identical(s$correct[1], TRUE)
  expect_true(s$partial[2])
  expect_true(s$not_found[2])
  expect_identical(s$correct[2], NA)
  expect_identical(s$usd_per_correct[2], NA_real_)
  expect_false(is.null(cmp$answers$mapped$notes$cost_cap_reached))
})

test_that("a failed recipe is wrong, and keeps the cost of what it sent", {
  cl <- priced_mock()
  local_mocked_bindings(finish_answer = function(ans, doc, chunks, recipe) {
    if (identical(recipe, "mapped")) stop("boom")
    ans$recipe <- recipe
    ans$document <- list(source = doc$source, stats = doc$stats)
    ans$segmentation <- as.list(gr_chunk_stats(chunks))
    ans
  })
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced", correct = "45.2 million"))
  s <- cmp$summary
  expect_identical(s$correct, c(TRUE, FALSE))
  expect_gt(s$usd[2], 0)
  expect_identical(s$usd_per_correct[2], Inf)
})

test_that("a free model's wrong answer has no cost per right answer", {
  local_registries()
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          correct = "99 million"))
  expect_equal(cmp$summary$usd, 0)
  expect_false(cmp$summary$correct)
  expect_identical(cmp$summary$usd_per_correct, NA_real_)
  expect_identical(cmp$summary$usd_estimated, NA_real_)
})

test_that("an unpriced model leaves the cost unknown, not zero", {
  local_registries()
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers()[1], client = cl,
                          model = "cmp-unpriced-model", correct = "45.2 million"))
  expect_true(is.na(cmp$summary$usd))
  expect_true(is.na(cmp$summary$usd_estimated))
  expect_true(is.na(cmp$summary$usd_per_correct))
  expect_gt(cmp$summary$calls, 0L)
})

test_that("the estimated share follows the step provenance on a mock run", {
  cl <- priced_mock()
  cmp <- quiet(gr_compare(cost_doc(), "What was revenue?", two_readers(), client = cl,
                          model = "cmp-priced"))
  for (nm in cmp$summary$recipe) {
    steps <- Filter(function(st) !identical(st$kind, "local") && is.list(st$tokens),
                    cmp$answers[[nm]]$trace$steps)
    prov <- vapply(steps, function(st) as.character(st$tokens$provenance %||% NA), character(1))
    got <- cmp$summary$usd_estimated[cmp$summary$recipe == nm]
    if (all(is.na(prov))) {
      expect_identical(got, NA_real_)
    } else {
      expect_gte(got, 0)
      expect_lte(got, 1)
      if (all(prov %in% "estimated")) expect_equal(got, 1)
    }
  }
})

test_that("the estimated share is of the dollars, over requests that say how they counted", {
  local_registries()
  gr_register_model("cmp-priced", context_window = 8000, max_output = 500,
                    input_usd = 1, output_usd = 0)
  step <- function(input, prov, cached = FALSE) {
    list(model = "cmp-priced", ok = TRUE, cached = cached,
         tokens = list(input = as.integer(input), output = 0L, provenance = prov))
  }
  cost <- harnessr:::recipe_cost(list(step(300, "estimated"), step(100, "reported"),
                                      step(600, NA_character_)))
  expect_equal(cost$calls, 3L)
  expect_equal(cost$tokens_in, 1000L)
  expect_equal(cost$usd, as.numeric(gr_estimate_cost("cmp-priced", 1000L, 0L)))
  # 300 of the 400 tokens whose provenance is known were estimated.
  expect_equal(cost$usd_estimated, 0.75)

  # A cached request cost nothing, so it moves neither side of the share.
  cost <- harnessr:::recipe_cost(list(step(300, "estimated", cached = TRUE),
                                      step(100, "reported")))
  expect_equal(cost$usd_estimated, 0)

  none <- harnessr:::recipe_cost(list(step(100, NA_character_)))
  expect_identical(none$usd_estimated, NA_real_)

  empty <- harnessr:::recipe_cost(list())
  expect_identical(c(empty$calls, empty$tokens_in, empty$tokens_out), c(0L, 0L, 0L))
  expect_equal(empty$usd, 0)
  expect_identical(empty$usd_estimated, NA_real_)
})
