# test-contract-02.R: module contract 0.2. The protocol and step kinds, the
# `version` and `contract` fields of a registry entry, the listings that show
# them last, and signal calibrations that keep their own contract at 0.1.

listing_functions <- c("gr_readers", "gr_segmenters", "gr_cleaners", "gr_extractors",
                       "gr_embedders", "gr_protocols")

test_that("every listing ends with the version and contract columns", {
  for (f in listing_functions) {
    x <- get(f)()
    expect_identical(tail(names(x), 2), c("version", "contract"), info = f)
    expect_type(x$version, "character")
    expect_type(x$contract, "character")
  }
  # The built-ins registered through their kind's own function carry neither.
  expect_true(all(is.na(gr_readers()$version)))
  expect_true(all(is.na(gr_readers()$contract)))
  expect_true(all(is.na(gr_protocols()$contract)))
})

test_that("hr_register() records the version given and the contract, and the old way records NA", {
  local_registries()
  hr_register("cleaner", "probe_cl", fn = function(x, o) x, version = "1.2.0")
  row <- gr_cleaners()[gr_cleaners()$name == "probe_cl", ]
  expect_identical(row$version, "1.2.0")
  expect_identical(row$contract, harnessr:::hr_contract_version())
  m <- hr_modules("cleaner")
  expect_identical(m$contract[m$name == "probe_cl"], "0.2")
  expect_identical(tail(names(m), 2), c("version", "contract"))
  # Registered again through the kind's own function, the fields are gone.
  gr_register_cleaner("probe_cl", fn = function(x, o) x)
  row <- gr_cleaners()[gr_cleaners()$name == "probe_cl", ]
  expect_true(is.na(row$version))
  expect_true(is.na(row$contract))
  expect_error(hr_register("cleaner", "probe_cl", fn = function(x, o) x, version = 2),
               class = "gr_bad_setting")
  expect_error(hr_register("cleaner", "probe_cl", fn = function(x, o) x, version = ""),
               class = "gr_bad_setting")
})

test_that("the new fields leave the ingest code and its stamps as they were", {
  local_registries()
  before <- harnessr:::gr_state$registrations
  hr_register("extractor", "probe_ex", extensions = "prb", version = "0.1.0",
              fn = function(path, opts) "x")
  e <- harnessr:::gr_state$extractors$probe_ex
  expect_identical(e$registered, before + 1)
  code <- harnessr:::ingest_code(gr_ingest_spec(), TRUE, FALSE, "a.prb")
  expect_identical(code$extractor, list(e$fn, e$registered))
  expect_identical(rownames(gr_extractors())[nrow(gr_extractors())], "probe_ex")
})

test_that("a protocol can be registered by kind and comes back as it was built", {
  local_registries()
  p <- gr_protocol("mine", question = "What was revenue?", include = "Reports revenue")
  hr_register("protocol", "mine", fn = p, description = "revenue only", version = "1")
  row <- gr_protocols()[gr_protocols()$name == "mine", ]
  expect_identical(row$description, "revenue only")
  expect_identical(row$contract, "0.2")
  got <- gr_protocols("mine")
  expect_s3_class(got, "gr_protocol")
  expect_null(got$version)
  expect_null(got$contract)
  p$description <- "revenue only"
  expect_identical(got, p)
  res <- quiet(harnessr:::check_kind("protocol", "mine"))
  expect_identical(attr(res, "contract"), "0.2")
  expect_error(hr_register("protocol", "bad", fn = list(question = "q")),
               class = "gr_bad_protocol")
  expect_error(hr_register("protocol", "bad", fn = p, calls = "x"), class = "gr_bad_setting")
  expect_error(hr_register("protocol", "bad", fn = p, outline = "x"), class = "gr_bad_setting")
  expect_false("bad" %in% gr_protocols()$name)
})

test_that("a step can be registered by kind, listed and checked", {
  local_registries()
  shout <- hr_step("shout", function(input, ctx) toupper(input), input = "answer",
                   output = "state", version = "2.0.0")
  hr_register("step", "shout", fn = shout, description = "upper case")
  m <- hr_modules("step")
  expect_identical(m$name, "shout")
  expect_identical(m$description, "upper case")
  expect_identical(m$input, "answer")
  expect_identical(m$output, "state")
  expect_identical(m$version, "2.0.0")
  expect_identical(m$contract, "0.2")
  expect_identical(m$calls, list(character(0)))
  expect_identical(harnessr:::registry_get("step", "shout")$fn, shout)

  # A function is made into a step with the arguments in `...`.
  hr_register("step", "liar", fn = function(input, ctx) list(text = input),
              input = "document", output = "chunks", calls = "liar.call", version = "0.9")
  liar <- harnessr:::registry_get("step", "liar")$fn
  expect_s3_class(liar, "hr_step")
  expect_identical(attr(liar, "output"), "chunks")
  expect_identical(subset(hr_modules("step"), name == "liar")$version, "0.9")
  expect_identical(subset(hr_modules(), kind == "step" & name == "liar")$calls,
                   list("liar.call"))
  res <- harnessr:::check_kind("step", "liar", input = "Some text.")
  expect_identical(attr(res, "kind"), "step")
  expect_false(res$ok[res$rule == "declared_output"])
  res <- harnessr:::check_kind("step", "shout", input = "hi")
  expect_true(all(res$ok[res$rule %in% c("runs", "returns_value", "declared_output")]))

  expect_error(hr_register("step", "shout", fn = shout, input = "answer"),
               class = "gr_bad_setting")
  expect_error(hr_register("step", "odd", fn = function(input, ctx) 1, calls = NA_character_),
               class = "gr_bad_setting")
  expect_error(hr_register("step", "odd", fn = "not a function"), class = "hr_bad_step")
  expect_error(harnessr:::registry_get("step", "odd"), "Unknown step 'odd'")
})

test_that("a conformance report records contract 0.2", {
  res <- hr_check_module(identity, function() 1, kind = "function", name = "identity")
  expect_identical(attr(res, "contract"), "0.2")
})

test_that("a calibration key keeps contract version 0.1, so a saved record stays valid", {
  graded <- data.frame(score = rep(c(0.9, 0.2), 20), correct = rep(c(TRUE, FALSE), 20),
                       answerable = rep(c(TRUE, TRUE, TRUE, FALSE), 10))
  key <- list(served_model = "m-2026", version = "2026", task = "qa", format = "pdf",
              prompt_hash = "abc", effort = NA, module = "iterative")
  cal <- hr_calibrate_signal("demo", graded, key, seed = 1, B = 0)
  expect_identical(cal$key$contract_version, "0.1")
  expect_true(hr_calibration_valid(cal, key))
  # A record saved under 0.1 with the field spelled out is valid too.
  expect_true(hr_calibration_valid(cal, c(key, list(contract_version = "0.1"))))
  v <- hr_calibration_valid(cal, c(key, list(contract_version = "0.2")))
  expect_false(v)
  expect_identical(attr(v, "differs"), "contract_version")
})
