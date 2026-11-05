# test-core-kinds.R: the kinds of module the core is told about, and the
# version of the module contract it implements.

test_that("the contract version is 0.1", {
  expect_identical(harnessr:::hr_contract_version(), "0.1")
})

test_that("the document layer registers its five kinds at load", {
  kinds <- harnessr:::hr_kinds()
  expect_identical(names(kinds),
                   c("extractor", "cleaner", "segmenter", "reader", "embedder"))
  expect_identical(vapply(kinds, `[[`, "", "registry"),
                   c(extractor = "extractors", cleaner = "cleaners",
                     segmenter = "segmenters", reader = "readers",
                     embedder = "embedders"))
})

test_that("a registered kind can be read back", {
  st <- harnessr:::hr_state
  old <- st$kinds
  withr::defer(st$kinds <- old)
  harnessr:::hr_register_kind("probe", registry = "probes", note = "x")
  expect_identical(harnessr:::hr_kinds()$probe,
                   list(name = "probe", registry = "probes", note = "x"))
  expect_identical(names(harnessr:::hr_kinds())[1:5], names(old))
})

test_that("bad kinds and worker providers are refused", {
  expect_error(harnessr:::hr_register_kind(""), "non-empty")
  expect_error(harnessr:::hr_register_kind(NA_character_), "non-empty")
  expect_error(harnessr:::hr_register_worker_state("x", 1, identity), "functions")
  expect_error(harnessr:::hr_register_worker_state("", identity, identity), "name")
  expect_identical(names(harnessr:::hr_state$worker_providers), "doc")
})
