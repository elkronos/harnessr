# test-registry-snapshot.R: the module registries show what they showed when
# fixtures/registry/listings.rds was recorded.
#
# A change to how modules are registered or listed must keep each gr_*()
# listing's columns, column types, row order and row names (the extractor
# listing is named by extractor), the `registered` stamps of the built-in
# cleaners and extractors, and the code an ingestion would run, whose hash is
# part of the ingest cache key. The machinery is in helper-listings.R. When a
# change is intended, rerun `Rscript dev/record-listings.R` from the repository
# root and say why in the commit message.

listings_now <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) cache <<- listings_snapshot()
    cache
  }
})

listings_was <- function() readRDS(listings_path())

test_that("the snapshot covers every listing and every built-in cleaner and extractor", {
  was <- listings_was()
  expect_setequal(names(was$listing), listings_functions)
  expect_setequal(names(was$ingest), names(listings_ingest_cases()))
  expect_gt(length(was$stamps$cleaners), 0L)
  expect_gt(length(was$stamps$extractors), 0L)
})

for (f in listings_functions) {
  local({
    f <- f
    test_that(sprintf("%s() keeps its columns, types, row order and row names", f), {
      was <- listings_was()$listing[[f]]
      now <- listings_now()$listing[[f]]
      expect_identical(now$class, was$class)
      expect_identical(now$names, was$names)
      expect_identical(now$types, was$types)
      expect_identical(now$rownames, was$rownames)
      expect_identical(now$data, was$data)
    })
  })
}

test_that("the extractor listing is named by extractor", {
  expect_identical(rownames(gr_extractors())[1:3], c("txt", "md", "html"))
})

test_that("the built-in cleaners and extractors keep their registration stamps", {
  was <- listings_was()$stamps
  now <- listings_now()$stamps
  expect_identical(now$cleaners, was$cleaners)
  expect_identical(now$extractors, was$extractors)
})

test_that("the code an ingestion would run keys the ingest cache as it did", {
  was <- listings_was()$ingest
  now <- listings_now()$ingest
  for (nm in names(was)) {
    # The functions, the stage and scope of each cleaner and the stamps, with
    # each function named by what it is registered as.
    expect_identical(now[[nm]]$named, was[[nm]]$named, info = nm)
    # The key's hash, with each unnamed environment's address left out (it
    # differs between sessions). It takes in each function's deparsed code,
    # which another version of R may print differently; where this R deparses
    # the code as the recording R did, the hash must be the same.
    if (identical(now[[nm]]$fn_text, was[[nm]]$fn_text)) {
      expect_identical(now[[nm]]$hash, was[[nm]]$hash, info = nm)
    }
  }
})
