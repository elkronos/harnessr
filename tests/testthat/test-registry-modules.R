# test-registry-modules.R: hr_register() and hr_modules(), one way to register
# and list modules of every kind, over the registries each kind already has.

# Put a document layer registry back as it was when the test ends.
keep_registry <- function(slot, env = parent.frame()) {
  st <- harnessr:::gr_state
  old <- st[[slot]]
  withr::defer(assign(slot, old, envir = st), envir = env)
}

probe_reader <- function(chunks, question, client, spec, trace) {
  new_answer("probe", "probe", question, character(0), trace)
}

test_that("a module registered by kind is the one the kind's own function registers", {
  keep_registry("readers")
  hr_register("reader", "probe_a", fn = probe_reader, signature = "one|1|none",
              cost_calls = "1", description = "a probe", calls = "probe_a.answer")
  gr_register_reader("probe_b", fn = probe_reader, signature = "one|1|none",
                     cost_calls = "1", description = "a probe", calls = "probe_a.answer")
  reg <- harnessr:::gr_state$readers
  a <- reg$probe_a; b <- reg$probe_b
  # hr_register() also keeps the module's version and the contract it was
  # registered under; the kind's own function keeps neither.
  expect_identical(a[c("version", "contract")],
                   list(version = NA_character_, contract = harnessr:::hr_contract_version()))
  expect_null(b$version)
  expect_null(b$contract)
  a$name <- b$name <- a$version <- a$contract <- NULL
  expect_identical(a, b)
  expect_identical(hr_register("reader", "probe_a", fn = probe_reader, signature = "one|1|none"),
                   "probe_a")
  expect_true("probe_a" %in% gr_readers()$name)
  m <- hr_modules("reader")
  expect_identical(m$signature[m$name == "probe_a"], "one|1|none")
  expect_identical(m$calls[m$name == "probe_a"][[1]], "probe_a")
})

test_that("every kind the document layer brings can be registered and listed", {
  for (s in c("extractors", "cleaners", "segmenters", "embedders")) keep_registry(s)
  hr_register("extractor", "probe_ex", extensions = "PRB",
              fn = function(path, opts) data.frame(text = "x", kind = "text"))
  hr_register("cleaner", "probe_cl", stage = "late", fn = function(x, o) x)
  hr_register("segmenter", "probe_sg", cost = "llm", needs_client = TRUE,
              fn = function(doc, spec, client, trace) NULL)
  hr_register("embedder", "probe_em", deterministic = TRUE,
              fn = function(texts, params) matrix(1, length(texts), 1))
  m <- hr_modules()
  got <- m[grepl("^probe_", m$name), c("kind", "name")]
  rownames(got) <- NULL
  expect_identical(got, data.frame(
    kind = c("extractor", "cleaner", "segmenter", "embedder"),
    name = c("probe_ex", "probe_cl", "probe_sg", "probe_em"), stringsAsFactors = FALSE))
  expect_identical(hr_modules("extractor")$extensions[hr_modules("extractor")$name == "probe_ex"],
                   list("prb"))
  expect_identical(subset(hr_modules("cleaner"), name == "probe_cl")$stage, "late")
  expect_identical(subset(hr_modules("segmenter"), name == "probe_sg")$cost, "llm")
  expect_true(subset(hr_modules("embedder"), name == "probe_em")$deterministic)
  expect_true("probe_cl" %in% gr_cleaners()$name)
  expect_true("probe_ex" %in% gr_extractors()$name)
  expect_true("probe_em" %in% gr_embedders()$name)
})

test_that("a cleaner or extractor registered by kind takes a registration stamp", {
  keep_registry("cleaners")
  before <- harnessr:::gr_state$registrations
  hr_register("cleaner", "probe_cl", fn = function(x, o) x)
  expect_identical(harnessr:::gr_state$cleaners$probe_cl$registered, before + 1)
})

test_that("an unknown kind is refused", {
  expect_error(hr_register("ranker", "x", fn = identity), class = "hr_unknown_kind")
  expect_error(hr_register(NA_character_, "x", fn = identity), class = "hr_unknown_kind")
  expect_error(hr_modules("ranker"), class = "hr_unknown_kind")
  expect_error(hr_modules("model"), "Kinds you can list: extractor")
})

test_that("hr_register() runs the checks of the kind's own function", {
  for (s in c("readers", "segmenters", "cleaners")) keep_registry(s)
  expect_error(hr_register("reader", "auto", fn = probe_reader, signature = "one|1|none"),
               class = "gr_reserved_name")
  expect_error(hr_register("reader", "probe_a", fn = probe_reader, signature = "one"),
               "select\\|calls\\|state")
  expect_error(hr_register("reader", "probe_a", fn = probe_reader, signature = "one|1|none",
                           calls = "has space"), class = "gr_bad_setting")
  expect_error(hr_register("segmenter", "probe_sg", fn = identity, cost = "gold"),
               "should be one of")
  expect_error(hr_register("segmenter", "probe_sg", fn = "not a function"), "must be a function")
  expect_error(hr_register("cleaner", "probe_cl", fn = function(x, o) x, calls = "a.b"),
               class = "gr_bad_setting")
  expect_error(hr_register("cleaner", "probe_cl", fn = function(x, o) x, colour = "red"),
               "unused argument")
  expect_error(hr_register("embedder", "probe_em", fn = function(texts, params) 1,
                           calls = "x"), class = "gr_bad_setting")
  expect_error(hr_register("extractor", "probe_ex", fn = function(path, ...) NULL,
                           calls = "x"), class = "gr_bad_setting")
  expect_false("probe_em" %in% names(harnessr:::gr_state$embedders))
  expect_false("probe_ex" %in% names(harnessr:::gr_state$extractors))
  expect_false(any(c("auto", "probe_a") %in% names(harnessr:::gr_state$readers)))
  expect_false("probe_sg" %in% names(harnessr:::gr_state$segmenters))
  expect_false("probe_cl" %in% names(harnessr:::gr_state$cleaners))
})

test_that("hr_modules() has one row per module and a list column of calls", {
  # No step is registered at load; register one so every kind has a row.
  local_registries()
  hr_register("step", "probe_step", fn = function(input, ctx) input)
  m <- hr_modules()
  expect_s3_class(m, "data.frame")
  expect_identical(names(m), c("kind", "name", "description", "calls", "version", "contract"))
  expect_identical(vapply(m, typeof, ""), c(kind = "character", name = "character",
                                            description = "character", calls = "list",
                                            version = "character", contract = "character"))
  expect_identical(attr(m, "row.names"), seq_len(nrow(m)))
  expect_identical(unique(m$kind), names(harnessr:::hr_kinds()))
  st <- harnessr:::gr_state
  expect_identical(nrow(m), sum(lengths(mget(c("extractors", "cleaners", "segmenters",
                                                "readers", "embedders", "protocols"),
                                              envir = st))) +
                     length(harnessr:::hr_state$steps))
  r <- m[m$kind == "reader", ]
  rownames(r) <- NULL
  expect_identical(r$name, sort(names(st$readers), method = "radix"))
  expect_identical(r$calls, unname(lapply(st$readers[r$name], `[[`, "calls")))
  expect_true(all(lengths(m$calls[m$kind %in% c("cleaner", "extractor", "embedder",
                                                 "protocol")]) == 0L))
  r1 <- hr_modules("reader")
  expect_identical(r1[, names(m)], r)
  expect_true(all(c("signature", "cost_calls") %in% names(r1)))
  expect_false(any(c("fn", "cost", "registered") %in% names(r1)))
  expect_false("registered" %in% names(hr_modules("cleaner")))
})

test_that("get and set are kept apart from the kinds table", {
  st <- harnessr:::hr_state
  old_kinds <- st$kinds; old_access <- st$kind_access
  withr::defer({ st$kinds <- old_kinds; st$kind_access <- old_access })
  store <- list()
  harnessr:::hr_register_kind("probe", registry = "probes",
    get = function() store,
    set = function(name, fn, ..., description = "", calls = NULL) {
      store[[name]] <<- list(name = name, fn = fn, description = description, calls = calls)
    })
  expect_identical(harnessr:::hr_kinds()$probe, list(name = "probe", registry = "probes"))
  hr_register("probe", "one", fn = identity, description = "first", calls = "one.call")
  m <- hr_modules("probe")
  expect_identical(m$name, "one")
  expect_identical(m$calls, list("one.call"))
  expect_identical(tail(hr_modules()$kind, 1), "probe")
  # A kind without the accessor asked for is an unknown kind for that use.
  expect_error(harnessr:::check_kind("probe", "one"), class = "hr_unknown_kind")
  expect_error(harnessr:::check_kind("probe", "one"), "Kinds you can check: [^.]*step\\.$")
  harnessr:::hr_register_kind("noget", registry = "nogets", get = NULL, set = NULL)
  expect_error(hr_modules("noget"), class = "hr_unknown_kind")
  expect_error(hr_register("noget", "x", fn = identity), class = "hr_unknown_kind")
  expect_false("noget" %in% hr_modules()$kind)
  expect_error(harnessr:::hr_register_kind("bad", get = 1), "function or NULL")
})

test_that("the shiny app's registry reads still work after hr_register()", {
  keep_registry("segmenters")
  hr_register("segmenter", "probe_sg", description = "probe",
              fn = function(doc, spec, client, trace) NULL)
  seg_choices <- gr_segmenters()$name
  read_choices <- setdiff(gr_readers()$name, c("extract", "screen"))
  clean_choices <- gr_cleaners()$name
  expect_true("probe_sg" %in% seg_choices)
  expect_gt(length(read_choices), 0L)
  expect_gt(length(clean_choices), 0L)
  d <- gr_segmenters()
  expect_identical(as.character(d$description[d$name == "probe_sg"]), "probe")
  expect_identical(as.character(d$cost[d$name %in% "probe_sg"]), "free")
  d <- gr_readers()
  expect_length(sprintf("%s [%s]: %s", d$name, d$cost_calls, d$description), nrow(d))
})

test_that("an unknown kind has no conformance check", {
  expect_error(harnessr:::check_kind("model", "mock-model"), class = "hr_unknown_kind")
  expect_error(harnessr:::check_kind("model", "mock-model"), "Kinds you can check: extractor")
})
