# test-core-names.R: the core functions carry hr_ names, and their objects
# keep the gr_ classes that saved files and user code test for.
#
# The 27 core exports below were gr_ functions up to 0.6.0. They were renamed
# to hr_ with no alias. The classes and condition classes they create kept
# their gr_ names, so an object made before the rename still dispatches.

core_renamed <- c(
  "api_key", "backend_client", "budget", "cache", "cache_clear", "cache_client",
  "cache_stats", "call", "client", "count_tokens", "ellmer_client", "embed",
  "estimate_cost", "mock_client", "model_info", "model_limits", "models",
  "options", "register_model", "replay_client", "set_tokenizer", "tokenizer",
  "trace", "trace_cost", "trace_save", "trace_summary", "truncate_tokens"
)

test_that("each core function is exported under its hr_ name only", {
  ns <- asNamespace("harnessr")
  exports <- getNamespaceExports("harnessr")
  new <- paste0("hr_", core_renamed)
  old <- paste0("gr_", core_renamed)
  expect_true(all(new %in% exports), info = paste(setdiff(new, exports), collapse = ", "))
  for (nm in new) expect_true(is.function(get(nm, envir = ns)), info = nm)
  expect_identical(intersect(old, exports), character(0))
  expect_identical(old[vapply(old, exists, logical(1), envir = ns, inherits = FALSE)],
                   character(0))
})

test_that("the renamed constructors still make gr_ classes", {
  local_registries()
  mock <- hr_mock_client(function(m, p) "an answer")
  expect_true(inherits(mock, "gr_mock_client"))
  expect_true(inherits(mock, "gr_client"))
  expect_true(inherits(hr_client(model = "gpt-4o-mini", api_key = "sk-test"), "gr_client"))
  backend <- hr_backend_client(function(m, p) "an answer")
  expect_true(inherits(backend, "gr_backend_client"))
  cache <- hr_cache(withr::local_tempdir())
  expect_true(inherits(cache, "gr_cache"))
  cached <- hr_cache_client(mock, cache)
  expect_true(inherits(cached, "gr_mock_client"))
  expect_true(inherits(cached$.cache, "gr_cache"))
  tr <- hr_trace()
  expect_true(inherits(tr, "gr_trace"))
  invisible(hr_call(mock, "a question", trace = tr))
  replay <- hr_replay_client(tr)
  expect_true(inherits(replay, "gr_replay_client"))
  expect_true(inherits(replay, "gr_client"))
})

test_that("a trace saved by hr_trace_save() reads back as a gr_trace", {
  local_registries()
  mock <- hr_mock_client(function(m, p) "an answer")
  tr <- hr_trace()
  invisible(hr_call(mock, "a question", trace = tr))
  path <- withr::local_tempfile(fileext = ".json")
  hr_trace_save(tr, path)
  replay <- hr_replay_client(path)
  expect_identical(hr_call(replay, "a question")$text, "an answer")
})
