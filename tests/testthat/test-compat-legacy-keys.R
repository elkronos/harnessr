# test-compat-legacy-keys.R: caches and recordings made before the key change still
# answer.
#
# fixtures/legacy-0.6.0/ was written by the build before harnessr-cache-v3 and
# harnessr-replay-v2 (see dev/record-legacy-keys.R and helper-legacy-keys.R).
# Every call in it must be answered here, with no miss and nothing sent, and
# every answer must come through the old key.

# Run the fixture's calls, counting each hr_legacy_key warning. With `each`,
# the once-per-session record is cleared after every warning, so each reply
# found under an old key warns and the count is the number of such replies.
legacy_keys_run <- function(cl, each = TRUE, trace = NULL) {
  warned <- 0L
  out <- withCallingHandlers(
    legacy_keys_calls(cl, trace),
    hr_legacy_key = function(w) {
      warned <<- warned + 1L
      if (each) {
        state <- harnessr:::hr_state
        state$legacy_key_warned <- NULL
      }
      invokeRestart("muffleWarning")
    })
  list(out = out, warned = warned)
}

legacy_keys_text <- function(out) {
  vapply(out, function(r) if (inherits(r, "gr_result")) r$text else r$result$text, character(1))
}

legacy_keys_recorded <- function() {
  rec <- jsonlite::fromJSON(file.path(legacy_keys_dir(), "recording.json"),
                            simplifyVector = FALSE)
  vapply(rec$steps, function(s) s$response, character(1))
}

test_that("the fixture was written under the old keys", {
  files <- list.files(file.path(legacy_keys_dir(), "cache"), recursive = TRUE)
  expect_length(files, 5L)
  expect_true(all(grepl("^[0-9a-f]{2}/[0-9a-f]{16}\\.rds$", files)))
  rec <- jsonlite::fromJSON(file.path(legacy_keys_dir(), "recording.json"),
                            simplifyVector = FALSE)
  expect_length(rec$steps, 6L)
  expect_false(any(vapply(rec$steps, function(s) !is.null(s$replay_key), logical(1))))
})

test_that("an old cache answers every call through the old key, each hit warning", {
  local_registries()
  harnessr::gr_options(verbose = FALSE)
  dir <- withr::local_tempdir()
  file.copy(file.path(legacy_keys_dir(), "cache"), dir, recursive = TRUE)
  cache <- gr_cache(file.path(dir, "cache"))
  base <- legacy_keys_client()
  cl <- gr_cache_client(base, cache)

  run <- legacy_keys_run(cl)
  expect_identical(run$warned, 6L)
  expect_identical(legacy_keys_text(run$out), legacy_keys_recorded())
  expect_true(all(vapply(run$out, function(r) {
    if (inherits(r, "gr_result")) r$cached else r$result$cached
  }, logical(1))))
  # Nothing was sent, nothing was missed, and nothing was rewritten.
  expect_length(base$calls(), 0L)
  s <- gr_cache_stats(cache)
  expect_identical(s[c("entries", "hits", "misses", "writes", "legacy_hits")],
                   data.frame(entries = 5L, hits = 6L, misses = 0L, writes = 0L,
                              legacy_hits = 6L))
  # A reply found under the old key carries no trace of how it was found.
  expect_null(attr(run$out[[1]], "legacy_key"))

  # Left to itself, the warning is once per cache in a session, and the count
  # goes on.
  again <- legacy_keys_run(cl, each = FALSE)
  expect_identical(again$warned, 1L)
  third <- legacy_keys_run(cl, each = FALSE)
  expect_identical(third$warned, 0L)
  expect_identical(gr_cache_stats(cache)$legacy_hits, 18L)
})

test_that("an old cache is not read for a draw", {
  local_registries()
  dir <- withr::local_tempdir()
  file.copy(file.path(legacy_keys_dir(), "cache"), dir, recursive = TRUE)
  cache <- gr_cache(file.path(dir, "cache"))
  base <- legacy_keys_client()
  cl <- gr_cache_client(base, cache)
  res <- gr_call(cl, "What was revenue in 2024?", draw_index = 1)
  expect_false(res$cached)
  expect_length(base$calls(), 1L)
  # Written under the new key, beside the old entries.
  expect_identical(gr_cache_stats(cache)[c("entries", "legacy_hits")],
                   data.frame(entries = 6L, legacy_hits = 0L))
  # gr_cache_clear() removes entries under both keys.
  expect_identical(gr_cache_clear(cache), 6L)
})

test_that("an old recording replays strictly through the old key, each hit warning", {
  local_registries()
  harnessr::gr_options(verbose = FALSE)
  rp <- gr_replay_client(file.path(legacy_keys_dir(), "recording.json"), strict = TRUE)
  tr <- gr_trace()
  run <- legacy_keys_run(rp, trace = tr)
  expect_identical(run$warned, 6L)
  expect_identical(legacy_keys_text(run$out), legacy_keys_recorded())
  expect_identical(rp$stats()[c("recorded", "hits", "repeats", "misses", "legacy_hits")],
                   data.frame(recorded = 6L, hits = 6L, repeats = 0L, misses = 0L,
                              legacy_hits = 6L))

  # A reply found by the old key was not checked against the temperature, cap
  # or schema, so the replay's own trace records it without a new key, and a
  # replay of that trace goes through the old key again.
  expect_true(all(vapply(tr$steps, function(st) is.null(st$replay_key), logical(1))))
  rp2 <- gr_replay_client(tr, strict = TRUE)
  again <- legacy_keys_run(rp2, trace = NULL)
  expect_identical(again$warned, 6L)
  expect_identical(legacy_keys_text(again$out), legacy_keys_recorded())
  expect_identical(rp2$stats()$legacy_hits, 6L)

  # The old recording holds two replies to the repeated prompt and no more.
  expect_error(gr_call(rp, "What was revenue in 2024?"), class = "hr_replay_exhausted")
})

test_that("a reply found by the old key at another temperature keeps no new key", {
  local_registries()
  harnessr::gr_options(verbose = FALSE)
  rp <- gr_replay_client(file.path(legacy_keys_dir(), "recording.json"), strict = TRUE)
  tr <- gr_trace()
  res <- withCallingHandlers(
    gr_call(rp, "What was revenue in 2024?", temperature = 0.9, trace = tr),
    hr_legacy_key = function(w) invokeRestart("muffleWarning"))
  expect_match(res$text, "default temperature", fixed = TRUE)
  expect_null(tr$steps[[1]]$replay_key)

  # Replayed at the same temperature, the reply is still one found by the old
  # key, and says so.
  rp2 <- gr_replay_client(tr, strict = TRUE)
  expect_warning(again <- gr_call(rp2, "What was revenue in 2024?", temperature = 0.9),
                 class = "hr_legacy_key")
  expect_identical(again$text, res$text)
  expect_identical(rp2$stats()$legacy_hits, 1L)
})

test_that("the old cache key names this package's functions as readgpt's", {
  ns <- asNamespace("harnessr")
  expect_identical(harnessr:::env_identity(ns), "readgpt")
  expect_identical(harnessr:::env_name(ns), "harnessr")

  # None of the fixture's calls hashes a function, so the mapping is checked
  # here against the parts 0.6.0 hashed. A literal key would change with any
  # edit to clamp()'s body, so the expected key is built the same way instead.
  cl <- legacy_keys_client()
  f <- harnessr:::clamp
  extra <- list(f = f)
  xx <- function(s) digest::digest(s, algo = "xxhash64")
  extra_hash <- xx(paste(c("=<list:1>",
                           paste0("/f=function:", paste(deparse(f), collapse = "\n"),
                                  "@readgpt")),
                         collapse = "\u0001"))
  msgs <- list(list(role = "user", content = "Hi"))
  got <- harnessr:::legacy_cache_key_v2(cl, msgs, "gpt-4o-mini", 100L, NULL,
                                        NULL, NULL, extra)
  want <- harnessr:::gr_hash(c(
    "readgpt-cache-v2", cl$api, cl$base_url, cl$.client_id, "gpt-4o-mini", "100",
    "<null>", "result", "<no-schema>", harnessr:::gr_hash(cl$extra_body %||% list()),
    extra_hash, "user", "Hi"))
  expect_identical(got, want)
  # Named as harnessr's, the same function hashes differently, so the test
  # above fails if the mapping is dropped.
  as_harnessr <- xx(paste(c("=<list:1>",
                            paste0("/f=function:", paste(deparse(f), collapse = "\n"),
                                   "@harnessr")),
                          collapse = "\u0001"))
  expect_false(identical(extra_hash, as_harnessr))
})
