# test-core-json-schema.R: a JSON reply is checked against the request schema
# before it is accepted or cached.

js_schema <- list(
  type = "object", additionalProperties = FALSE,
  required = list("decision", "score", "tags", "detail"),
  properties = list(
    decision = list(type = "string", enum = list("include", "exclude")),
    score = list(type = "integer"),
    tags = list(type = "array", items = list(type = "string")),
    detail = list(type = "object", required = list("note"),
                  properties = list(note = list(type = c("string", "null")),
                                    ids = list(type = "array",
                                               items = list(type = "array",
                                                            items = list(type = "integer")))))))

js_good <- '{"decision":"include","score":3,"tags":["a","b"],"detail":{"note":null,"ids":[[1,2],[3]]}}'

js_problem <- function(txt, ...) harnessr:::json_reply(txt, js_schema, ...)$problem

test_that("a reply that meets the schema is accepted and simplified as before", {
  r <- harnessr:::json_reply(js_good, js_schema)
  expect_true(r$ok)
  expect_null(r$problem)
  expect_identical(r$value$tags, c("a", "b"))
  expect_identical(r$value$score, 3L)
  # 3.0 is an integer in JSON Schema.
  expect_true(harnessr:::json_reply(sub('"score":3', '"score":3.0', js_good, fixed = TRUE), js_schema)$ok)
})

test_that("type, enum, required and nested shapes are each checked", {
  expect_match(js_problem(sub('"include"', '"maybe"', js_good, fixed = TRUE)),
               "$.decision: the string \"maybe\" is not one of the allowed values", fixed = TRUE)
  expect_match(js_problem(sub('"score":3', '"score":"3"', js_good, fixed = TRUE)),
               "$.score: expected integer", fixed = TRUE)
  expect_match(js_problem(sub('"score":3', '"score":2.5', js_good, fixed = TRUE)),
               "$.score: expected integer", fixed = TRUE)
  expect_match(js_problem(sub('"score":3,', "", js_good, fixed = TRUE)),
               "$: missing required score", fixed = TRUE)
  expect_match(js_problem(sub('"note":null', '"other":1', js_good, fixed = TRUE)),
               "$.detail: missing required note", fixed = TRUE)
  expect_match(js_problem(sub('["a","b"]', '["a",2]', js_good, fixed = TRUE)),
               "$.tags[1]: expected string, got 2", fixed = TRUE)
  expect_match(js_problem(sub('[[1,2],[3]]', '[1,2,3]', js_good, fixed = TRUE)),
               "$.detail.ids[0]: expected array, got 1", fixed = TRUE)
  expect_match(js_problem(sub('"tags":["a","b"]', '"tags":{"a":1}', js_good, fixed = TRUE)),
               "$.tags: expected array, got an object", fixed = TRUE)
  expect_match(js_problem(sub('"decision":"include"', '"decision":null', js_good, fixed = TRUE)),
               "$.decision: expected string, got null", fixed = TRUE)
  # Not JSON and not an object keep their own reasons.
  expect_identical(js_problem("not json"), "not JSON")
  expect_identical(js_problem("[1, 2]"), "not an object")
})

test_that("enum values compare within one kind and NA marks null", {
  s <- list(type = "object", properties = list(
    k = list(type = c("string", "null"), enum = as.list(c("1", "null", NA)))))
  ok <- function(txt) harnessr:::json_reply(txt, s)$ok
  expect_true(ok('{"k":"1"}'))
  expect_true(ok('{"k":"null"}'))
  expect_true(ok('{"k":null}'))
  expect_false(ok('{"k":1}'))
  expect_false(ok('{"k":"2"}'))
})

test_that("allow_empty waives the top object's required fields only", {
  s <- list(type = "object", required = list("a", "b"),
            properties = list(a = list(type = "string"),
                              b = list(type = "object", required = list("c"),
                                       properties = list(c = list(type = "integer")))))
  ok <- function(txt) harnessr:::json_reply(txt, s, allow_empty = TRUE)$ok
  expect_true(ok("{}"))
  expect_true(ok('{"a":"x"}'))
  # A top-level null is "nothing here" too, as a field left out is.
  expect_true(ok('{"a":null}'))
  expect_false(ok('{"a":1}'))
  expect_false(ok('{"b":{}}'))
})

test_that("own_scalars leaves scalar values to the caller and checks the rest", {
  s <- list(type = "object", properties = list(
    n = list(type = c("integer", "null")),
    kind = list(type = "string", enum = list("x", "y")),
    list = list(type = "array", items = list(type = "integer"))))
  check <- function(txt) harnessr:::json_reply(txt, s, own_scalars = TRUE)$ok
  expect_true(check('{"n":"1,204","kind":"z"}'))
  expect_true(check('{"list":["a"]}'))
  expect_false(check('{"list":"a"}'))
})

test_that("a reply that breaks the schema fails the call and is never cached", {
  dir <- withr::local_tempdir()
  replies <- c(sub('"include"', '"maybe"', js_good, fixed = TRUE), js_good)
  sent <- 0L
  cl <- gr_mock_client(function(m, p) { sent <<- sent + 1L; replies[min(sent, 2L)] })
  cl <- gr_cache_client(cl, gr_cache(dir))
  msgs <- list(list(role = "user", content = "Decide."))

  bad <- harnessr:::gr_call_json(cl, msgs, schema = js_schema)
  expect_false(bad$ok)
  expect_null(bad$value)
  expect_true(bad$result$ok)
  expect_match(bad$problem, "$.decision", fixed = TRUE)

  # Asked again: the broken reply was not stored, so the request is sent.
  good <- harnessr:::gr_call_json(cl, msgs, schema = js_schema)
  expect_true(good$ok)
  expect_identical(sent, 2L)

  # And the good reply was stored: a third call is served from the cache.
  again <- harnessr:::gr_call_json(cl, msgs, schema = js_schema)
  expect_true(again$ok)
  expect_identical(sent, 2L)
})

test_that("a cached reply that breaks the schema is asked again", {
  dir <- withr::local_tempdir()
  msgs <- list(list(role = "user", content = "Decide."))
  bad <- sub('"score":3', '"score":"three"', js_good, fixed = TRUE)
  # A plain gr_call() stores any reply, as an entry written before the check
  # existed would have been.
  old_client <- gr_cache_client(gr_mock_client(function(m, p) bad), gr_cache(dir))
  expect_true(gr_call(old_client, msgs, schema = js_schema, schema_name = "result")$ok)

  sent <- 0L
  cl <- gr_cache_client(gr_mock_client(function(m, p) { sent <<- sent + 1L; js_good }), gr_cache(dir))
  cl$.client_id <- old_client$.client_id
  out <- harnessr:::gr_call_json(cl, msgs, schema = js_schema)
  expect_true(out$ok)
  expect_identical(sent, 1L)
})

test_that("a lone surrogate in a value that breaks the schema is a problem, not an error", {
  # Half of a split emoji arrives as "\udc00". The value is repaired before it
  # is read, and the schema check has to see the repaired value too: on the raw
  # bytes it stopped with "invalid multibyte string" and took the document down.
  enum_schema <- list(type = "object",
                      properties = list(d = list(type = "string", enum = list("a"))))
  int_schema <- list(type = "object", properties = list(n = list(type = "integer")))
  for (case in list(list('{"d":"\\udc00"}', enum_schema),
                    list('{"d":"a\\udc00"}', enum_schema),
                    list('{"n":"\\udc00"}', int_schema))) {
    out <- harnessr:::json_reply(case[[1]], case[[2]])
    expect_false(out$ok)
    expect_type(out$problem, "character")
  }
  expect_true(harnessr:::json_reply('{"d":"a"}', enum_schema)$ok)

  cl <- gr_mock_client(function(messages, params)
    '{"decision":"\\udc00include","reason":"r","criterion":null,"quote":null}')
  f <- withr::local_tempfile(fileext = ".txt")
  writeLines("We randomly assigned 1,204 participants to two groups.", f)
  s <- quiet(gr_screen(f, question = "Q?", include = "Reports a randomised comparison",
                       client = cl))
  expect_identical(s$table$status, "failed")
  expect_match(s$table$error, "$.decision", fixed = TRUE)
  expect_false(grepl("multibyte", s$table$error))
})
