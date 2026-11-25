# test-registry-routing.R: the document layer and the core read the module
# registries through each kind's accessor, the built-in segmenters carry their
# effort label on their registry entries, and the core makes no call into the
# document layer.

# Put a document layer registry back as it was when the test ends.
keep_slot <- function(slot, env = parent.frame()) {
  st <- harnessr:::gr_state
  old <- st[[slot]]
  withr::defer(assign(slot, old, envir = st), envir = env)
}

# Swap a kind's `get` for the length of a test.
swap_get <- function(kind, get, env = parent.frame()) {
  hs <- harnessr:::hr_state
  old <- hs$kind_access
  access <- old
  access[[kind]]$get <- get
  hs$kind_access <- access
  withr::defer(assign("kind_access", old, envir = hs), envir = env)
}

# test-boundary.R checks that the core makes no crossing outside this list.
test_that("the core may cross into the document layer nowhere", {
  expect_identical(nrow(boundary_allowed()), 0L)
})

test_that("registry_get() without a state reads a kind through its accessor", {
  rg <- harnessr:::registry_get
  st <- harnessr:::gr_state
  expect_identical(rg("reader"), st$readers)
  expect_identical(rg("segmenter"), st$segmenters)
  expect_identical(rg("extractor"), st$extractors)
  expect_identical(rg("cleaner"), st$cleaners)
  expect_identical(rg("embedder"), st$embedders)
  expect_identical(rg("reader", "stuff"), st$readers$stuff)
  # The same error, with the same words, as a read of the slot.
  by_kind <- tryCatch(rg("reader", "nope"), error = identity)
  by_slot <- tryCatch(rg("readers", "nope", "readers", state = st), error = identity)
  expect_s3_class(by_kind, "gr_unknown_method")
  expect_identical(conditionMessage(by_kind), conditionMessage(by_slot))
  # A slot name is not a kind.
  expect_error(rg("readers", "stuff"), class = "hr_unknown_kind")
  # Models keep their own state.
  expect_error(rg("model", "x"), class = "hr_unknown_kind")
})

test_that("the document layer sees what the kind's accessor returns", {
  only <- harnessr:::gr_state$readers["stuff"]
  swap_get("reader", function() only)
  stems <- harnessr:::declared_call_stems()
  expect_false("refine.answer" %in% stems)
  expect_true(all(only$stuff$calls %in% stems))
  expect_error(gr_read_spec("refine"), "Unknown reader .refine.. Registered: stuff")
})

test_that("declared call stems keep their order", {
  of <- function(reg) unlist(lapply(reg, function(e) e$calls), use.names = FALSE)
  st <- harnessr:::gr_state
  expect_identical(harnessr:::declared_call_stems(),
                   unique(c(of(st$readers), of(st$segmenters),
                            unlist(harnessr:::.gr_stage_calls, use.names = FALSE))))
})

test_that("each built-in segmenter carries its effort label, kept out of the listings", {
  reg <- harnessr:::gr_state$segmenters
  builtin <- c("fixed", "paragraph", "sentence", "recursive", "structural", "page",
               "semantic", "contextual", "proposition")
  for (m in builtin) expect_true(is.function(reg[[m]]$effort_label), info = m)
  label <- function(m, ...) reg[[m]]$effort_label(gr_segment_spec(m, ...))
  for (m in builtin[1:7]) expect_identical(label(m), "", info = m)
  expect_identical(label("contextual"), "")
  expect_identical(label("contextual", context_source = "llm"), "segment.context")
  expect_identical(label("proposition"), "segment.proposition")
  expect_false("effort_label" %in% names(hr_modules("segmenter")))
  expect_false("effort_label" %in% names(gr_segmenters()))
})

test_that("a segmenter registered without a label gets the whole effort map", {
  keep_slot("segmenters")
  read <- gr_read_spec("stuff", effort = c(segment = "minimal", stuff = "high"))
  mine <- function(doc, spec, client, trace) new_chunks(doc$text, "mine", spec)
  hr_register("segmenter", "proposition", mine, cost = "llm")
  expect_null(harnessr:::gr_state$segmenters$proposition$effort_label)
  expect_identical(harnessr:::segment_effort(gr_segment_spec("proposition"), read)$effort,
                   read$effort)
  # A label you give is used.
  hr_register("segmenter", "mine", mine, calls = "mine.call",
              effort_label = function(spec) "segment")
  expect_identical(harnessr:::segment_effort(gr_segment_spec("mine"), read)$effort, "minimal")
  # A label that is not a function is refused, and nothing is registered.
  expect_error(hr_register("segmenter", "other", mine, effort_label = "segment"),
               class = "gr_bad_setting")
  expect_null(harnessr:::gr_state$segmenters$other)
  # An unregistered method has no label either.
  expect_identical(harnessr:::segment_effort(gr_segment_spec("absent"), read)$effort,
                   read$effort)
})

test_that("the document layer's embedder choice agrees with hr_embed()", {
  local_registries()
  keep_slot("embedders")
  cl <- hr_mock_client()
  texts <- c("cats sleep", "dogs bark")
  source_of <- function() attr(hr_embed(cl, texts), "embedding_source")
  expect_identical(harnessr:::resolve_embedder(cl)$name, source_of())
  hr_options(embedder = "lexical")
  expect_identical(harnessr:::resolve_embedder(cl)$name, source_of())
  gr_register_embedder("ones", function(texts, params) matrix(1, length(texts), 2),
                       deterministic = TRUE)
  hr_options(embedder = "ones")
  expect_identical(harnessr:::resolve_embedder(cl)$name, source_of())
  expect_identical(source_of(), "ones")
})

test_that("hr_embed() falls back on the registered lexical embedder", {
  local_registries()
  keep_slot("embedders")
  broken <- function(texts, params) stop("down")
  texts <- c("cats sleep", "dogs bark")
  out <- suppressWarnings(hr_embed(hr_mock_client(), texts, embedder = broken))
  expect_identical(attr(out, "embedding_source"), "lexical")
  expect_true(isTRUE(attr(out, "embedding_fallback")))
  expect_equal(as.vector(out), as.vector(harnessr:::lexical_embed(texts)))
  gr_register_embedder("lexical", function(texts, params) matrix(1, length(texts), 3),
                       deterministic = TRUE)
  out <- suppressWarnings(hr_embed(hr_mock_client(), texts, embedder = broken))
  expect_identical(ncol(out), 3L)
})

test_that("a registered lexical embedder that fails falls back on the built-in one", {
  local_registries()
  keep_slot("embedders")
  broken <- function(texts, params) stop("down")
  texts <- c("cats sleep", "dogs bark")
  hr_register("embedder", "lexical", fn = function(texts, params) stop("lexical down"))
  warned <- character(0)
  out <- withCallingHandlers(
    hr_embed(hr_mock_client(), texts, embedder = broken),
    warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  expect_true(any(grepl("lexical down", warned, fixed = TRUE)))
  expect_identical(attr(out, "embedding_source"), "lexical")
  expect_true(isTRUE(attr(out, "embedding_fallback")))
  expect_equal(as.vector(out), as.vector(harnessr:::lexical_embed(texts)))
  # With fallback = "error" the request's failure is the error, as before.
  expect_error(suppressWarnings(hr_embed(hr_mock_client(), texts, embedder = broken,
                                         fallback = "error")),
               class = "gr_embed_error")
})
