# test-sweep.R: hr_sweep(), the param.* columns and the hr_same_config
# warning of hr_benchmark(), and hr_sweep_check().

local_quiet <- function(env = parent.frame()) {
  old <- hr_options(verbose = FALSE, embedder = "lexical")
  withr::defer(hr_options(old), envir = env)
}
sweep_ref <- function() {
  gr_qa_reference(questions = c(revenue = "What was revenue in 2024?"),
                  documents = gr_example(), answers = list("45.2 million"), split = "test")
}
sweep_client <- function() hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
bench_quiet <- function(arms, runs = 5) {
  hr_benchmark(arms, sweep_ref(), runs = runs, client = sweep_client(),
               scorer = gr_scorer_answer())
}

# --- hr_sweep -----------------------------------------------------------------

test_that("hr_sweep() builds one arm per row of a recipe arm's settings", {
  local_quiet()
  arms <- hr_sweep(gr_arm("needle"), list(top_k = c(2, 4)))
  expect_named(arms, c("needle:top_k=2", "needle:top_k=4"))
  expect_true(all(vapply(arms, inherits, logical(1), "hr_arm")))
  expect_identical(arms[[1]]$params$top_k, 2)
  expect_identical(attr(arms[[2]], "hr_settings"), list(recipe = "needle", top_k = 4))
  # Settings the base arm already had are kept, and a row overrides them.
  base <- gr_arm("needle", list(max_tokens = 300))
  arms <- hr_sweep(base, data.frame(top_k = 3))
  expect_identical(arms[[1]]$params$max_tokens, 300)
  expect_identical(arms[[1]]$params$top_k, 3)
  # A recipe column replaces the recipe.
  arms <- hr_sweep(gr_arm("needle"), list(recipe = c("needle", "fast")))
  expect_identical(vapply(arms, function(a) a$params$recipe, ""),
                   c("needle:recipe=needle" = "needle", "needle:recipe=fast" = "fast"))
})

test_that("hr_sweep() takes a function of the grid's columns", {
  local_quiet()
  arms <- hr_sweep(function(top_k, max_tokens) {
    gr_arm("needle", list(top_k = top_k, max_tokens = max_tokens))
  }, expand.grid(top_k = c(2, 8), max_tokens = c(200, 300)))
  expect_length(arms, 4L)
  expect_identical(names(arms)[4], "needle:top_k=8,max_tokens=300")
  # A hand-written arm records the row as its settings.
  arms <- hr_sweep(function(prompt) {
    hr_arm("ask", function(item, ctx) ctx$call(paste(prompt, item))$text)
  }, list(prompt = c("Briefly:", "In detail:")))
  expect_identical(attr(arms[[2]], "hr_settings"), list(prompt = "In detail:"))
  expect_false(identical(arms[[1]]$hash, arms[[2]]$hash))
})

test_that("hr_sweep() names the known settings when a column is not one", {
  local_quiet()
  err <- tryCatch(hr_sweep(gr_arm("needle"), list(topk = 2)), error = identity)
  expect_s3_class(err, "hr_unknown_setting")
  expect_match(conditionMessage(err), "'topk' is not a setting", fixed = TRUE)
  expect_match(conditionMessage(err), "top_k", fixed = TRUE)
  expect_match(conditionMessage(err), "recipe", fixed = TRUE)
  err <- tryCatch(hr_sweep(function(top_k) gr_arm("needle", list(top_k = top_k)),
                           list(top_k = 2, mmr = 0.5)), error = identity)
  expect_s3_class(err, "hr_unknown_setting")
  expect_match(conditionMessage(err), "Known settings: top_k.", fixed = TRUE)
  # An arm from hr_arm() alone records no settings to override.
  plain <- hr_arm("plain", function(item, ctx) "x")
  expect_error(hr_sweep(plain, list(top_k = 2)), class = "hr_bad_arm")
  # A chain is swept by path; a step with no schema has no settings to sweep.
  ch <- hr_chain(s = hr_step("s", function(input, ctx) input), name = "c")
  err <- tryCatch(hr_sweep(ch, list(s.k = 1:2)), error = identity)
  expect_s3_class(err, "hr_bad_arm")
  expect_s3_class(err, "hr_unknown_setting")
  expect_match(conditionMessage(err), "'s.k' is not a setting of arm 'c'", fixed = TRUE)
  swept <- hr_sweep(function(k) hr_chain(s = hr_step("s", function(input, ctx) input),
                                         name = "c", version = as.character(k)),
                    list(k = 1:2))
  expect_length(swept, 2L)
  expect_error(hr_sweep(function(top_k) "not an arm", list(top_k = 2)), class = "hr_bad_arm")
  expect_error(hr_sweep(gr_arm("needle"), data.frame()), class = "hr_bad_arm")
  expect_error(hr_sweep(gr_arm("needle"), list(top_k = 1:2), name = c("a", "b", "c")),
               class = "hr_bad_arm")
})

test_that("hr_sweep() collapses rows that build the same configuration, with a message", {
  local_quiet()
  held <- gr_recipes("needle")$read$top_k
  expect_message(arms <- hr_sweep(gr_arm("needle"), list(top_k = c(held, held, 3))),
                 class = "hr_sweep_collapsed")
  expect_length(arms, 2L)
  # A function that ignores a column builds one arm for every value of it.
  expect_message(arms <- hr_sweep(function(top_k) {
    hr_arm("same", function(item, ctx) "x")
  }, list(top_k = 1:3)), "2 of 3 rows", class = "hr_sweep_collapsed")
  expect_named(arms, "same:top_k=1")
  # The message is shown whatever `verbose` says.
  expect_message(hr_sweep(gr_arm("needle"), list(top_k = c(4, 4))), "dropped")
})

test_that("hr_sweep() names arms by prefix or one per row", {
  local_quiet()
  expect_named(hr_sweep(gr_arm("needle"), list(top_k = 2:3), name = "k"),
               c("k:top_k=2", "k:top_k=3"))
  expect_named(hr_sweep(gr_arm("needle"), list(top_k = 2:3), name = c("low", "high")),
               c("low", "high"))
  expect_named(hr_sweep(gr_arm("needle"), list(top_k = 2), name = "only"), "only")
  # A list column carries values that are not single values.
  arms <- hr_sweep(gr_arm("fast"), data.frame(clean = I(list("standard", c("page_numbers",
                                                                           "references")))))
  expect_identical(arms[[2]]$params$clean, c("page_numbers", "references"))
  expect_match(names(arms)[2], "clean=c(\"page_numbers\", \"references\")", fixed = TRUE)
})

# --- hr_benchmark: param columns and hr_same_config ---------------------------

test_that("hr_benchmark() adds a param column per recorded setting", {
  local_quiet()
  arms <- c(hr_sweep(gr_arm("needle"), list(top_k = c(2, 3))),
            list(plain = hr_arm("plain", function(item, ctx) "45.2 million")))
  bench <- bench_quiet(arms)
  expect_true(all(c("param.recipe", "param.top_k") %in% names(bench)))
  expect_identical(unique(bench$param.top_k[bench$arm == "needle:top_k=3"]), 3)
  expect_true(all(is.na(bench$param.top_k[bench$arm == "plain"])))
  agg <- aggregate(correct ~ param.top_k, bench, mean)
  expect_identical(agg$param.top_k, c(2, 3))
  # Arms that record nothing add no columns.
  b2 <- bench_quiet(list(hr_arm("plain", function(item, ctx) "45.2 million")))
  expect_false(any(startsWith(names(b2), "param.")))
})

test_that("hr_benchmark() warns hr_same_config for arms that resolve alike", {
  local_quiet()
  held <- gr_recipes("needle")$read$top_k
  arms <- list(gr_arm("needle", name = "a"), gr_arm("needle", list(top_k = held), name = "b"))
  expect_warning(bench_quiet(arms), class = "hr_same_config")
  plain <- function(nm) hr_arm(nm, function(item, ctx) "45.2 million")
  expect_warning(bench_quiet(list(plain("x"), plain("y"))), "'x' and 'y'",
                 class = "hr_same_config")
  # Different settings: no warning.
  arms <- list(gr_arm("needle", list(top_k = 2), name = "a"),
               gr_arm("needle", list(top_k = 3), name = "b"))
  expect_no_warning(bench_quiet(arms))
})

test_that("a setting held by a helper closure keeps arms apart", {
  local_quiet()
  # The run function reads only `ask`; the prompt is in ask's environment.
  mk <- function(prefix) {
    ask <- function(item, ctx) ctx$call(paste(prefix, item))$text
    function(item, ctx) ask(item, ctx)
  }
  arms <- list(hr_arm("one", mk("Answer in one word:")),
               hr_arm("long", mk("Explain at length:")))
  expect_no_warning(bench_quiet(arms))
  same <- list(hr_arm("a", mk("Briefly:")), hr_arm("b", mk("Briefly:")))
  expect_warning(bench_quiet(same), class = "hr_same_config")
  expect_no_message(swept <- hr_sweep(function(prefix) hr_arm("p", mk(prefix)),
                                      list(prefix = c("Answer in one word:",
                                                      "Explain at length:"))))
  expect_length(swept, 2L)
  # A helper that calls itself does not loop.
  rec <- function(prefix) {
    ask <- function(item, ctx, n = 0) if (n > 0) ask(item, ctx, n - 1) else
      ctx$call(paste(prefix, item))$text
    function(item, ctx) ask(item, ctx)
  }
  expect_length(hr_sweep(function(prefix) hr_arm("r", rec(prefix)),
                         list(prefix = c("A:", "B:"))), 2L)
})

# --- hr_sweep_check -----------------------------------------------------------

test_that("hr_sweep_check() reports a setting that changed nothing sent", {
  local_quiet()
  # `fast` sends the whole document in one request, so top_k is not used.
  bench <- bench_quiet(hr_sweep(gr_arm("fast"), list(top_k = c(2, 8))))
  chk <- hr_sweep_check(bench)
  expect_identical(nrow(chk), 1L)
  expect_identical(chk$arm, "fast:top_k=8")
  expect_identical(chk$same_as, "fast:top_k=2")
  expect_identical(chk$runs, 5L)
  expect_identical(chk$requests, 5L)
  expect_identical(chk$settings, "top_k: 2 vs 8")
})

test_that("hr_sweep_check() finds nothing when a setting changed the requests", {
  local_quiet()
  bench <- bench_quiet(hr_sweep(gr_arm("fast"), list(temperature = c(0, 1))))
  chk <- hr_sweep_check(bench)
  expect_identical(nrow(chk), 0L)
  expect_named(chk, c("arm", "same_as", "runs", "requests", "settings"))
  # Arms that sent no request are not reported.
  none <- bench_quiet(list(hr_arm("a", function(item, ctx) "45.2 million"),
                           hr_arm("b", function(item, ctx) "45.2 million.")))
  expect_identical(nrow(hr_sweep_check(none)), 0L)
  expect_error(hr_sweep_check(data.frame(arm = "a")), class = "gr_bad_setting")
})
