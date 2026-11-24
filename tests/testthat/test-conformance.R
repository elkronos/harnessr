# test-conformance.R: the conformance checks run every registered module of
# every kind, and every protocol, against the offline client and find no
# rule broken, and report modules of a user's own that break one.

no_failures <- function(res) {
  bad <- res[!is.na(res$ok) & !res$ok, , drop = FALSE]
  if (nrow(bad)) paste(bad$rule, bad$detail, sep = ": ", collapse = "; ") else ""
}

# Sample files for the extractors that the check cannot write itself.
conformance_paths <- function(env = parent.frame()) {
  paths <- list(pdf = testthat::test_path("fixtures", "pdf", "single-column.pdf"))
  if (nzchar(Sys.which("zip"))) {
    dir <- withr::local_tempdir(.local_envir = env)
    dir.create(file.path(dir, "word"))
    writeLines(paste0('<?xml version="1.0" encoding="UTF-8"?><w:document ',
                      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
                      '<w:body><w:p><w:r><w:t>Revenue was 45.2 million dollars.</w:t></w:r>',
                      '</w:p></w:body></w:document>'), file.path(dir, "word", "document.xml"))
    paths$docx <- file.path(dir, "sample.docx")
    withr::with_dir(dir, utils::zip(paths$docx, files = file.path("word", "document.xml"),
                                    flags = "-q"))
  }
  paths
}

test_that("every registered module of every kind passes its kind's rules", {
  local_registries()
  local_clean_cache()
  # No step is registered at load; register one so the step kind is checked.
  hr_register("step", "keep", fn = function(input, ctx) list(seen = input),
              input = "state", output = "state")
  mods <- hr_modules()
  expect_setequal(unique(mods$kind),
                  c("extractor", "cleaner", "segmenter", "reader", "embedder", "protocol",
                    "step"))
  paths <- conformance_paths()
  # An extractor runs only where its packages are installed, and only on a
  # file of its format.
  usable <- gr_extractors()$name[gr_extractors()$available]
  usable <- intersect(usable, c("txt", "md", "html", names(paths)))
  checked <- character(0)
  for (i in seq_len(nrow(mods))) {
    kind <- mods$kind[i]
    name <- mods$name[i]
    if (kind == "extractor" && !name %in% usable) next
    res <- quiet(harnessr:::check_kind(kind, name, path = paths[[name]]))
    expect_s3_class(res, "hr_conformance")
    expect_identical(attr(res, "kind"), kind)
    expect_identical(attr(res, "name"), name)
    if (kind == "reader") {
      r <- name
      expect_identical(attr(res, "kind"), "reader")
      expect_identical(attr(res, "name"), r)
      expect_true(all(c("runs", "answer_fields", "evidence", "calls_declared",
                        "calls_within_cost") %in% res$rule))
      expect_identical(no_failures(res), "", label = sprintf("rules '%s' broke", r))
    } else if (kind == "segmenter") {
      s <- name
      expect_identical(attr(res, "kind"), "segmenter")
      expect_true(all(c("runs", "chunk_columns", "within_cap", "calls_declared") %in% res$rule))
      expect_identical(no_failures(res), "", label = sprintf("rules '%s' broke", s))
    } else {
      expect_true(length(res$rule) > 2L)
      expect_identical(no_failures(res), "", label = sprintf("%s '%s' broke", kind, name))
      # Each rule is answered: only a rule with nothing to check says NA.
      expect_identical(res$rule[is.na(res$ok) & !grepl("^not checked", res$detail)],
                       character(0))
    }
    checked <- c(checked, paste(kind, name))
  }
  expect_true(all(c("extractor txt", "extractor md", "cleaner references", "embedder api",
                    "embedder lexical", "segmenter paragraph", "reader stuff",
                    "protocol claims", "step keep") %in% checked))
})

test_that("every registered protocol passes the protocol rules", {
  local_registries()
  for (p in gr_protocols()$name) {
    res <- quiet(harnessr:::check_kind("protocol", p))
    expect_identical(attr(res, "kind"), "protocol")
    expect_identical(no_failures(res), "", label = sprintf("protocol '%s' broke", p))
    expect_true(all(c("question", "criteria", "round_trip") %in% res$rule))
  }
})

test_that("a reader that breaks the contract is reported, and still registered", {
  local_registries()
  local_clean_cache()
  gr_register_reader("sloppy", signature = "one|2|none", calls = "sloppy.answer",
    cost = function(input_stats, params) hr_cost(calls = 1),
    fn = function(chunks, question, client, spec, trace) {
      a <- gr_call(client, list(list(role = "user", content = question)),
                   model = spec$model, trace = trace, label = "sloppy.answer")
      b <- gr_call(client, list(list(role = "user", content = question)),
                   model = spec$model, trace = trace, label = "unlisted.step")
      ev <- data.frame(chunk_id = 999L, text = a$text, page = NA_integer_,
                       section = NA_character_, score = NA_real_, stringsAsFactors = FALSE)
      new_answer(b$text, "sloppy", question, 999L, trace, evidence = ev)
    })
  res <- quiet(gr_check_reader("sloppy"))
  failed <- res$rule[!is.na(res$ok) & !res$ok]
  expect_setequal(failed, c("evidence", "chunks_used", "calls_declared", "calls_within_cost"))
  expect_match(res$detail[res$rule == "calls_declared"], "unlisted.step", fixed = TRUE)
  expect_match(res$detail[res$rule == "calls_within_cost"], "2 request(s) made, at most 1",
               fixed = TRUE)
  expect_match(res$detail[res$rule == "evidence"], "999", fixed = TRUE)
  out <- capture.output(print(res))
  expect_match(out[2], "fails 4 of", fixed = TRUE)
  expect_match(out[3], "FAIL", fixed = TRUE)
  # A report only: the reader is still there and still reads.
  expect_true("sloppy" %in% gr_readers()$name)
})

test_that("a reader that errors fails `runs`, and one without a cost is not checked on it", {
  local_registries()
  local_clean_cache()
  gr_register_reader("broken", signature = "one|1|none",
    fn = function(chunks, question, client, spec, trace) stop("cannot read today"))
  res <- quiet(gr_check_reader("broken"))
  expect_false(res$ok[res$rule == "runs"])
  expect_match(res$detail[res$rule == "runs"], "cannot read today")
  expect_true(all(is.na(res$ok[-(1:2)])))

  gr_register_reader("costless", signature = "one|1|none", calls = "costless.answer",
    fn = function(chunks, question, client, spec, trace) {
      res <- gr_call(client, list(list(role = "user", content = question)),
                     model = spec$model, trace = trace, label = "costless.answer")
      new_answer(res$text, "costless", question, chunks$chunks$chunk_id[1], trace)
    })
  res <- quiet(gr_check_reader("costless"))
  expect_identical(no_failures(res), "")
  expect_true(is.na(res$ok[res$rule == "calls_within_cost"]))
})

test_that("a segmenter whose chunks break the rules is reported", {
  local_registries()
  local_clean_cache()
  gr_register_segmenter("lumpy", calls = character(0),
    fn = function(doc, spec, client, trace) {
      new_chunks(c(paste(rep("word", 400), collapse = " "), "a short one"), "lumpy", spec)
    })
  res <- quiet(gr_check_segmenter("lumpy"))
  expect_false(res$ok[res$rule == "within_cap"])
  expect_match(res$detail[res$rule == "within_cap"], "150-token cap", fixed = TRUE)
  expect_true(res$ok[res$rule == "chunk_ids"])
})

test_that("the checks refuse a name that is not registered and a client that is not one", {
  expect_error(gr_check_reader("no_such_reader"), class = "gr_unknown_method")
  expect_error(gr_check_segmenter("no_such_segmenter"), class = "gr_unknown_method")
  expect_error(gr_check_reader("stuff", client = "mock"), class = "gr_bad_setting")
  expect_error(gr_check_segmenter("paragraph", client = "mock"), class = "gr_bad_setting")
})

test_that("a segmenter that declares no calls is given the client passed to the check", {
  local_registries()
  local_clean_cache()
  gr_register_segmenter("sneaky", calls = character(0),
    fn = function(doc, spec, client, trace) {
      if (!is.null(client)) {
        gr_call(client, list(list(role = "user", content = "context")),
                model = spec$model, trace = trace, label = "undeclared.step")
      }
      new_chunks(c("Revenue was 45.2 million dollars.", "Costs rose."), "sneaky", spec)
    })
  res <- quiet(gr_check_segmenter("sneaky", client = gr_mock_client()))
  expect_false(res$ok[res$rule == "calls_declared"])
  expect_match(res$detail[res$rule == "calls_declared"], "undeclared.step", fixed = TRUE)
  # With no client given, it is not handed the offline one.
  res <- quiet(gr_check_segmenter("sneaky"))
  expect_identical(no_failures(res), "")
})

test_that("the offline reply keeps the type of an enum value", {
  expect_identical(harnessr:::schema_sample(list(enum = list(1L, "x"))), 1L)
  expect_identical(harnessr:::schema_sample(list(enum = list(TRUE, "n/a"))), TRUE)
  expect_identical(harnessr:::schema_sample(list(enum = list(NULL, "a"))), "a")
  enum_mixed <- list(type = "object", properties = list(a = list(enum = list(1L, "x"))))
  reply <- harnessr:::check_reply(list(), list(schema = enum_mixed))
  expect_null(harnessr:::schema_problem(jsonlite::fromJSON(reply, simplifyVector = FALSE),
                                        enum_mixed))
})

test_that("the offline reply follows the first branch of anyOf or oneOf that is not null", {
  nested <- list(type = "object", properties = list(a = list(anyOf = list(
    list(type = "null"),
    list(type = "object", properties = list(b = list(type = "integer", maximum = 3L)))))))
  expect_identical(harnessr:::schema_sample(nested), list(a = list(b = 3L)))
  expect_identical(harnessr:::schema_sample(list(oneOf = list(list(type = "boolean")))), TRUE)
})

test_that("extractors, cleaners, embedders and protocols that break the rules are reported", {
  local_registries()
  local_clean_cache()
  gr_register_extractor("listy", "lst", fn = function(path, opts) list(text = "x"))
  f <- withr::local_tempfile(fileext = ".lst")
  writeLines("one line", f)
  res <- quiet(harnessr:::check_kind("extractor", "listy", path = f))
  expect_false(res$ok[res$rule == "blocks_shape"])
  expect_match(res$detail[res$rule == "blocks_shape"], "list", fixed = TRUE)

  gr_register_extractor("typed", "typ", fn = function(path, opts) {
    data.frame(text = "Revenue.", page = "one", stringsAsFactors = FALSE)
  })
  g <- withr::local_tempfile(fileext = ".typ")
  writeLines("x", g)
  res <- quiet(harnessr:::check_kind("extractor", "typed", path = g))
  expect_false(res$ok[res$rule == "block_columns"])
  expect_match(res$detail[res$rule == "block_columns"], "page", fixed = TRUE)
  # With no file and a format the check cannot write, it asks for one.
  expect_error(harnessr:::check_kind("extractor", "typed"), class = "gr_bad_setting")

  gr_register_cleaner("wipe", stage = "late", fn = function(x, o) "")
  res <- quiet(harnessr:::check_kind("cleaner", "wipe"))
  expect_false(res$ok[res$rule == "keeps_text"])
  counter <- 0
  gr_register_cleaner("drifty", stage = "late", fn = function(x, o) {
    counter <<- counter + 1
    paste(x, counter)
  })
  res <- quiet(harnessr:::check_kind("cleaner", "drifty"))
  expect_false(res$ok[res$rule == "deterministic"])

  gr_register_embedder("long", deterministic = TRUE,
    fn = function(texts, params) matrix(stats::runif(length(texts) * 4, 2, 3), ncol = 4))
  res <- quiet(harnessr:::check_kind("embedder", "long"))
  failed <- res$rule[!is.na(res$ok) & !res$ok]
  expect_setequal(failed, c("unit_rows", "deterministic"))

  gr_register_embedder("short", fn = function(texts, params) diag(2))
  # gr_embed() refuses vectors for the wrong number of texts, so the run fails.
  res <- quiet(harnessr:::check_kind("embedder", "short"))
  expect_false(res$ok[res$rule == "runs"])
  expect_match(res$detail[res$rule == "runs"], "row", fixed = TRUE)

  p <- gr_protocol("thin", question = "What was revenue?", include = "Reports revenue")
  p$question <- ""
  p$outline <- c("no heading")
  gr_register_protocol("thin", p)
  res <- quiet(harnessr:::check_kind("protocol", "thin"))
  failed <- res$rule[!is.na(res$ok) & !res$ok]
  expect_true(all(c("question", "outline") %in% failed))
  # A report only: each module stays registered.
  expect_true(all(c("listy", "typed") %in% gr_extractors()$name))
  expect_true("thin" %in% gr_protocols()$name)
  expect_error(harnessr:::check_kind("model", "mock-model"), class = "hr_unknown_kind")
})

test_that("every reader and segmenter keeps its rules under each mock mode", {
  local_registries()
  local_clean_cache()
  modes <- list("bad_json", "refuse", "at_cap", c(429L, 500L, 200L))
  for (mode in modes) {
    label <- paste(mode, collapse = "-")
    for (r in gr_readers()$name) {
      cl <- gr_mock_client(harnessr:::check_reply, mode = mode)
      res <- quiet(gr_check_reader(r, client = cl))
      expect_identical(no_failures(res), "",
                       label = sprintf("reader '%s' under mode %s", r, label))
      # The cost bound holds whatever the replies are.
      expect_true(res$ok[res$rule == "calls_within_cost"] %in% c(TRUE, NA))
    }
    for (s in gr_segmenters()$name) {
      cl <- gr_mock_client(harnessr:::check_reply, mode = mode)
      res <- quiet(gr_check_segmenter(s, client = cl))
      expect_identical(no_failures(res), "",
                       label = sprintf("segmenter '%s' under mode %s", s, label))
    }
  }
})

test_that("every reader keeps to a call cap of 0, 1 and 3", {
  local_registries()
  local_clean_cache()
  for (r in gr_readers()$name) {
    for (k in c(0, 1, 3)) {
      res <- quiet(harnessr:::check_reader_governor(r, k))
      expect_identical(res$rule, c("is_function", "runs", "within_max_calls", "stops_cleanly",
                                   "partial_when_capped"))
      expect_identical(no_failures(res), "",
                       label = sprintf("reader '%s' at max_calls = %d", r, k))
      expect_true(res$ok[res$rule == "runs"])
    }
  }
  # At 0, nothing is sent: every reader is refused before its first request.
  zero <- vapply(gr_readers()$name, function(r) {
    res <- quiet(harnessr:::check_reader_governor(r, 0))
    res$detail[res$rule == "stops_cleanly"]
  }, character(1))
  expect_true(all(zero == "refused before the first request"))
})

test_that("an answer cut short by a refused request must be marked partial", {
  local_registries()
  local_clean_cache()
  # A reader that asks three times under a cap of one: the governor refuses
  # the last two, and gr_read() marks the answer partial whatever the reader
  # said.
  gr_register_reader("greedy", signature = "one|1|none", calls = "greedy.answer",
    cost = function(input_stats, params) hr_cost(calls = 1),
    fn = function(chunks, question, client, spec, trace) {
      texts <- vapply(1:3, function(i) {
        gr_call(client, list(list(role = "user", content = question)), model = spec$model,
                trace = trace, label = "greedy.answer")$text
      }, character(1))
      ans <- new_answer(paste(texts, collapse = " "), "greedy", question,
                        chunks$chunks$chunk_id[1], trace)
      ans$partial <- FALSE
      ans
    })
  res <- quiet(harnessr:::check_reader_governor("greedy", 1))
  expect_identical(no_failures(res), "")
  expect_true(res$ok[res$rule == "within_max_calls"])
  expect_true(res$ok[res$rule == "partial_when_capped"])
  # The rule itself fails an answer that is not marked partial.
  tr <- gr_trace()
  tr$budget_stop <- TRUE
  rule <- harnessr:::gr_rules_governor(tr, 1)$partial_when_capped
  got <- rule(structure(list(partial = FALSE), class = "gr_answer"))
  expect_false(got$ok)
  expect_match(got$detail, "not marked partial", fixed = TRUE)
  expect_true(is.na(harnessr:::gr_rules_governor(gr_trace(), 1)$partial_when_capped(
    structure(list(partial = FALSE), class = "gr_answer"))$ok))
})
