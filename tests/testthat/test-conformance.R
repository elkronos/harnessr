# test-conformance.R: gr_check_reader() and gr_check_segmenter() run every
# built-in module against the offline client and find no rule broken, and
# report a reader of a user's own that breaks one.

no_failures <- function(res) {
  bad <- res[!is.na(res$ok) & !res$ok, , drop = FALSE]
  if (nrow(bad)) paste(bad$rule, bad$detail, sep = ": ", collapse = "; ") else ""
}

test_that("every registered reader passes the reader rules", {
  local_registries()
  local_clean_cache()
  for (r in gr_readers()$name) {
    res <- quiet(gr_check_reader(r))
    expect_s3_class(res, "hr_conformance")
    expect_identical(attr(res, "kind"), "reader")
    expect_identical(attr(res, "name"), r)
    expect_true(all(c("runs", "answer_fields", "evidence", "calls_declared",
                      "calls_within_cost") %in% res$rule))
    expect_identical(no_failures(res), "", label = sprintf("rules '%s' broke", r))
  }
})

test_that("every registered segmenter passes the segmenter rules", {
  local_registries()
  local_clean_cache()
  for (s in gr_segmenters()$name) {
    res <- quiet(gr_check_segmenter(s))
    expect_identical(attr(res, "kind"), "segmenter")
    expect_true(all(c("runs", "chunk_columns", "within_cap", "calls_declared") %in% res$rule))
    expect_identical(no_failures(res), "", label = sprintf("rules '%s' broke", s))
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
