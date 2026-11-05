# test-golden.R -- characterisation tests: the package does today what it did
# when the fixtures were recorded.
#
# Each shipped recipe, each built-in reader and each review stage (screen,
# extract, claims, outline, synthesise) is run on the bundled example with a
# fixed offline mock, and compared with fixtures/golden/: every request it
# sends (a hash of messages, model, parameters and schema, plus a readable
# summary), the response-cache key the package computes for each, and the
# trace with times, run ids and paths taken out. api.json holds every export's
# arguments and defaults, and the exported S3 methods. Any difference fails,
# and the message names the fields that changed.
#
# The machinery is in helper-golden.R. When a change in behaviour is intended,
# regenerate the fixtures with `Rscript dev/record-golden.R` from the
# repository root and say in the commit message what changed and why.

golden_skip <- function() {
  for (p in golden_needs) {
    skip_if_not(requireNamespace(p, quietly = TRUE), sprintf("needs the '%s' package", p))
  }
}

# Computed once for the whole file, on first use: the runs take several
# seconds together and every test below reads the same record.
golden_now <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) cache <<- lapply(golden_compute(), golden_roundtrip)
    cache
  }
})

golden_expected <- c(names(golden_runs()), "api")

test_that("there is a fixture for every golden record, and no fixture without one", {
  golden_skip()
  dir <- golden_dir()
  expect_true(dir.exists(dir), info = "fixtures/golden/ is missing; run dev/record-golden.R")
  on_disk <- sub("\\.json$", "", list.files(dir, pattern = "\\.json$"))
  expect_setequal(on_disk, golden_expected)
  expect_setequal(names(golden_now()), golden_expected)
})

test_that("the fixtures are small and hold nothing specific to a machine or a run", {
  golden_skip()
  files <- list.files(golden_dir(), pattern = "\\.json$", full.names = TRUE)
  expect_gt(length(files), 0L)
  expect_lt(sum(file.size(files)), 1024^2)
  txt <- unlist(lapply(files, readLines, warn = FALSE, encoding = "UTF-8"))
  expect_false(any(grepl(tempdir(), txt, fixed = TRUE)))
  expect_false(any(grepl(R.home(), txt, fixed = TRUE)))
  expect_false(any(grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:", txt)))
  expect_false(any(grepl(as.character(getRversion()), txt, fixed = TRUE)))
  # A path or version left in by the session that recorded the fixtures would
  # not match this session's tempdir() or R.home(), so look for any.
  # A drive letter is a lone letter before ":/" or ":\\" (escaped in JSON).
  expect_false(any(grepl("Rtmp|/tmp/|/home/|/Users/|(^|[^A-Za-z])[A-Za-z]:(/|\\\\\\\\)", txt)))
  expect_false(any(grepl(as.character(utils::packageVersion("harnessr")), txt, fixed = TRUE)))
})

test_that("every built-in reader has a golden run", {
  golden_skip()
  # extract and screen are covered by the stage-* records.
  expect_setequal(golden_readers, setdiff(golden_builtin_readers(), c("extract", "screen")))
})

for (nm in golden_expected) {
  local({
    nm <- nm
    test_that(sprintf("golden record '%s' is unchanged", nm), {
      golden_skip()
      path <- file.path(golden_dir(), paste0(nm, ".json"))
      if (!file.exists(path)) fail(sprintf("No fixture %s; run dev/record-golden.R.", basename(path)))
      now <- golden_now()[[nm]]
      if (!file.exists(path) || is.null(now)) return(invisible())
      was <- golden_read(path)
      d <- golden_diff(was, now, path = nm)
      expect(length(d) == 0L, paste0(
        "Golden record '", nm, "' changed (fixture -> now):\n  ", paste(d, collapse = "\n  "),
        "\nIf the change is intended, run `Rscript dev/record-golden.R` and say why in the commit."))
    })
  })
}

test_that("a golden run is the same twice in one session", {
  golden_skip()
  # The fixtures are only worth comparing against if a run cannot differ from
  # itself: no clock, no session id, no state left behind by the run before.
  run <- golden_runs()[["reader-map_reduce"]]
  a <- golden_roundtrip(run())
  b <- golden_roundtrip(run())
  expect_identical(a, b)
  expect_identical(a, golden_now()[["reader-map_reduce"]])
})
