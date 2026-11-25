# test-run-ctx.R: the run snapshot a parallel batch hands its workers
# (new_hr_ctx(), format_hr_ctx(), worker_item()), and the API key it carries.
#
# The parallel tests run the installed harnessr in each worker. Reinstall the
# package into the library before running them, or a worker runs the old code.

# skip_if_no_future() is in helper-parallel.R.

fake_key <- "sk-FAKE123"

# Whether the fake key appears anywhere in `x`, however it is stored.
has_fake_key <- function(x) {
  any(grepl(fake_key, deparse(x, control = "all"), fixed = TRUE))
}

# Whether the fake key appears in any file name or file under `dir`.
dir_has_fake_key <- function(dir) {
  files <- list.files(dir, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  any(grepl(fake_key, files, fixed = TRUE)) ||
    any(vapply(files, function(f) {
      length(grepRaw(fake_key, readBin(f, "raw", file.size(f)), fixed = TRUE)) > 0L
    }, logical(1)))
}

test_that("new_hr_ctx() checks what it is given once, where it is built", {
  ctx <- harnessr:::new_hr_ctx(key = fake_key, parent_meta = list(run = "a"),
                               governor = hr_governor(max_calls = 3),
                               draw = list(index = 2L, scope = "armA"),
                               packages = c("harnessr", "harnessr"))
  expect_s3_class(ctx, "hr_ctx")
  expect_identical(ctx$packages, "harnessr")
  expect_error(harnessr:::new_hr_ctx(key = NA_character_), class = "gr_bad_ctx")
  expect_error(harnessr:::new_hr_ctx(key = c("a", "b")), class = "gr_bad_ctx")
  expect_error(harnessr:::new_hr_ctx(opts = "x"), class = "gr_bad_ctx")
  expect_error(harnessr:::new_hr_ctx(governor = list(max_calls = 1)), class = "gr_bad_ctx")
  expect_error(harnessr:::new_hr_ctx(packages = 1), class = "gr_bad_ctx")
  expect_error(harnessr:::format_hr_ctx(list()), class = "gr_bad_ctx")
})

test_that("format_hr_ctx() says a key is set and never shows it", {
  ctx <- harnessr:::new_hr_ctx(key = fake_key, opts = hr_options(),
                               regs = harnessr:::worker_state(),
                               parent_meta = list(run = "a"),
                               governor = hr_governor(max_calls = 3),
                               draw = list(index = 2L, scope = "armA"),
                               globals = list(helper = function() 1), packages = "harnessr")
  txt <- harnessr:::format_hr_ctx(ctx)
  expect_type(txt, "character")
  expect_false(any(grepl(fake_key, txt, fixed = TRUE)))
  expect_true("  key: set" %in% txt)
  expect_true(any(grepl("max_calls 3", txt, fixed = TRUE)))
  expect_true(any(grepl("index 2, scope armA", txt, fixed = TRUE)))
  expect_true(any(grepl("globals: helper", txt, fixed = TRUE)))
  expect_true("  key: none" %in% harnessr:::format_hr_ctx(harnessr:::new_hr_ctx()))
})

test_that("an item sets the key while it runs and puts the prior value back", {
  read_key <- function(item, trace) Sys.getenv("OPENAI_API_KEY", unset = "<unset>")
  wrapped <- harnessr:::worker_item(read_key, harnessr:::new_hr_ctx(key = fake_key), NULL)

  withr::local_envvar(OPENAI_API_KEY = NA)
  expect_identical(wrapped(1)$value, fake_key)
  expect_true(is.na(Sys.getenv("OPENAI_API_KEY", unset = NA)))

  withr::local_envvar(OPENAI_API_KEY = "sk-prior")
  expect_identical(wrapped(1)$value, fake_key)
  expect_identical(Sys.getenv("OPENAI_API_KEY"), "sk-prior")

  # An item that fails puts it back too.
  failing <- harnessr:::worker_item(function(item, trace) stop("boom"),
                                    harnessr:::new_hr_ctx(key = fake_key), NULL)
  expect_s3_class(failing(1)$error, "error")
  expect_identical(Sys.getenv("OPENAI_API_KEY"), "sk-prior")

  # A snapshot with no key leaves the environment alone.
  nokey <- harnessr:::worker_item(read_key, harnessr:::new_hr_ctx(), NULL)
  expect_identical(nokey(1)$value, "sk-prior")
})

test_that("the function a worker runs keeps the snapshot without its globals", {
  ctx <- harnessr:::new_hr_ctx(globals = list(big = seq_len(1e5)), packages = "harnessr")
  wrapped <- harnessr:::worker_item(function(item, trace) item, ctx, NULL)
  kept <- get("ctx", environment(wrapped))
  expect_s3_class(kept, "hr_ctx")
  expect_identical(kept$globals, list())
  expect_identical(kept$packages, character(0))
})

test_that("a mock batch never sets the key, and the worker's value is what it was", {
  skip_if_no_future()
  withr::local_envvar(OPENAI_API_KEY = NA)
  withr::local_options(harnessr.api_key = fake_key)
  cl <- hr_mock_client(function(messages, params) {
    Sys.getenv("OPENAI_API_KEY", unset = "<unset>")
  })
  got <- harnessr:::gr_lapply(1:4, function(i, trace) {
    list(seen = hr_call(cl, "hi", trace = trace)$text,
         after = Sys.getenv("OPENAI_API_KEY", unset = "<unset>"), pid = Sys.getpid())
  }, parallel = TRUE, workers = 2, client = cl)
  expect_false(any(vapply(got, `[[`, integer(1), "pid") == Sys.getpid()))
  expect_identical(vapply(got, `[[`, character(1), "seen"), rep("<unset>", 4))
  expect_identical(vapply(got, `[[`, character(1), "after"), rep("<unset>", 4))
  expect_true(is.na(Sys.getenv("OPENAI_API_KEY", unset = NA)))
})

test_that("a worker's key does not outlive its item", {
  skip_if_no_future()
  withr::local_envvar(OPENAI_API_KEY = NA)
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(future::multisession, workers = 2)
  wrapped <- harnessr:::worker_item(function(item, trace) {
    Sys.getenv("OPENAI_API_KEY", unset = "<unset>")
  }, harnessr:::new_hr_ctx(key = fake_key), NULL)
  # The item and then a read of the environment, both in one worker process.
  got <- future::value(future::future({
    during <- wrapped(1)$value
    list(during = during, after = Sys.getenv("OPENAI_API_KEY", unset = "<unset>"),
         pid = Sys.getpid())
  }, packages = "harnessr"))
  expect_false(identical(got$pid, Sys.getpid()))
  expect_identical(got$during, fake_key)
  expect_identical(got$after, "<unset>")
})

test_that("a backend handler that reads the environment gets the key in parallel", {
  skip_if_no_future()
  local_registries()
  withr::local_envvar(OPENAI_API_KEY = NA)
  withr::local_options(harnessr.api_key = fake_key)
  # The handler answers whether it saw the key, never the key itself, so the
  # scans below look only at what harnessr recorded.
  cl <- hr_backend_client(function(messages, params) {
    if (identical(Sys.getenv("OPENAI_API_KEY"), "sk-FAKE123")) "key seen" else "no key"
  }, model = "gpt-4o", id = "ctx-backend")
  cache_dir <- withr::local_tempdir("ctx-cache")
  cl <- hr_cache_client(cl, hr_cache(cache_dir))
  tr <- hr_trace()
  got <- harnessr:::gr_lapply(1:4, function(i, trace) {
    list(text = hr_call(cl, sprintf("item %d", i), trace = trace)$text, pid = Sys.getpid())
  }, parallel = TRUE, workers = 2, trace = tr, client = cl)
  expect_false(any(vapply(got, `[[`, integer(1), "pid") == Sys.getpid()))
  expect_identical(vapply(got, `[[`, character(1), "text"), rep("key seen", 4))
  expect_identical(tr$calls, 4L)
  # This process's environment is as it was.
  expect_true(is.na(Sys.getenv("OPENAI_API_KEY", unset = NA)))

  # The key is in none of what the run recorded or keyed.
  expect_false(has_fake_key(tr$config))
  expect_false(grepl(fake_key, as_json(tr), fixed = TRUE))
  expect_gt(length(list.files(cache_dir, recursive = TRUE)), 0L)
  expect_false(dir_has_fake_key(cache_dir))

  # A key mixed into a cache key is hashed, so the scan above cannot see it.
  # The same prompts run here with no key must give the same cache entries.
  withr::local_options(harnessr.api_key = NULL)
  keyless_dir <- withr::local_tempdir("ctx-cache-keyless")
  cl2 <- hr_cache_client(hr_backend_client(function(messages, params) "no key",
                                           model = "gpt-4o", id = "ctx-backend"),
                         hr_cache(keyless_dir))
  harnessr:::gr_lapply(1:4, function(i, trace) {
    hr_call(cl2, sprintf("item %d", i), trace = trace)$text
  }, parallel = FALSE, trace = hr_trace(), client = cl2)
  entries <- function(dir) sort(basename(list.files(dir, recursive = TRUE)))
  expect_identical(entries(cache_dir), entries(keyless_dir))
})
