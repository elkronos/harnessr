# test-core-schema.R: parameter schemas, declared call stems and reader cost
# functions.

# A label is covered by a stem it equals or that it starts with, then a dot.
covered_by <- function(label, stems) {
  any(label == stems | startsWith(label, paste0(stems, ".")))
}

request_labels <- function(trace) {
  st <- Filter(function(s) !identical(s$kind, "local") && !identical(s$kind, "embedding") &&
                 !is.null(s$tokens), trace$steps)
  unique(vapply(st, function(s) as.character(s$label), character(1)))
}

test_that("hr_validate clamps numbers into range and says so", {
  s <- hr_schema(hr_param("k", "integer", default = 6L, min = 1, max = 10))
  expect_identical(hr_validate(s, list(k = 3))$k, 3L)
  expect_warning(v <- hr_validate(s, list(k = 99)), class = "hr_param_clamped")
  expect_identical(v$k, 10L)
  # The older class still reaches handlers written for it.
  expect_warning(hr_validate(s, list(k = 0)), class = "gr_clamped")
  # Missing or not a number: the default, not the bottom of the range.
  expect_warning(v <- hr_validate(s, list(k = NA)), class = "gr_bad_setting")
  expect_identical(v$k, 6L)
  expect_warning(v <- hr_validate(s, list(k = "abc")), class = "gr_bad_setting")
  expect_identical(v$k, 6L)
  expect_identical(hr_validate(s)$k, 6L)
})

test_that("a bound can depend on a parameter resolved before it", {
  s <- hr_schema(
    hr_param("max_tokens", "integer", default = 1200L, min = 32, max = 1e6),
    hr_param("overlap_tokens", "integer", default = 0L, min = 0,
             max = function(p) p$max_tokens - 1L))
  expect_warning(v <- hr_validate(s, list(max_tokens = 100, overlap_tokens = 500)),
                 class = "hr_param_clamped")
  expect_identical(v$overlap_tokens, 99L)
})

test_that("enums match as match.arg() does and name the setting when they do not", {
  s <- hr_schema(hr_param("order", "enum", choices = c("relevance", "document", "edges")))
  expect_identical(hr_validate(s, list(order = "doc"))$order, "document")
  expect_identical(hr_validate(s, list(order = c("relevance", "document", "edges")))$order,
                   "relevance")
  expect_identical(hr_validate(s)$order, "relevance")
  expect_error(hr_validate(s, list(order = "sideways")), "`order` must be one of",
               class = "gr_bad_setting")
})

test_that("booleans are strict or lenient as declared", {
  s <- hr_schema(hr_param("strict", "boolean", default = FALSE),
                 hr_param("lenient", "boolean", default = FALSE, strict = FALSE))
  expect_error(hr_validate(s, list(strict = "yes")), class = "gr_bad_setting")
  expect_error(hr_validate(s, list(strict = NA)), class = "gr_bad_setting")
  expect_false(hr_validate(s, list(lenient = "yes"))$lenient)
  expect_true(hr_validate(s, list(strict = TRUE, lenient = TRUE))$lenient)
})

test_that("a schema refuses names it does not have, and keeps NULL settings", {
  s <- hr_schema(hr_param("model", "string"), hr_param("n", "integer", default = 1L))
  expect_error(hr_validate(s, list(modle = "x")), class = "hr_unknown_param")
  v <- hr_validate(s, list())
  expect_true("model" %in% names(v))
  expect_null(v$model)
  expect_error(hr_schema(hr_param("a", "integer"), hr_param("a", "number")),
               class = "gr_bad_setting")
  expect_error(hr_param("a", "enum"), class = "gr_bad_setting")
  expect_error(hr_param("a", "float"), "`type` of 'a' must be one of", class = "gr_bad_setting")
  expect_error(hr_param("a", "integer", tier = "expert"), "`tier` of 'a' must be one of",
               class = "gr_bad_setting")
  expect_error(hr_validate(hr_schema(hr_param("a", "string", required = TRUE))),
               "required", class = "gr_bad_setting")
})

test_that("the spec schemas have the constructors' defaults", {
  ns <- asNamespace("harnessr")
  check <- function(schema, fn) {
    fm <- formals(fn)
    for (p in schema) {
      d <- eval(fm[[p$name]])
      want <- if (identical(p$type, "enum")) d[1] else d
      got <- hr_validate(schema, stats::setNames(list(d), p$name))[[p$name]]
      if (is.null(p$resolve) && !identical(p$type, "enum")) {
        expect_identical(p$default, d, info = p$name)
      }
      if (!is.null(want) && is.null(p$resolve)) expect_identical(got, want, info = p$name)
    }
    expect_setequal(names(schema), setdiff(names(fm), "..."))
  }
  check(get(".gr_read_schema", ns), gr_read_spec)
  check(get(".gr_segment_schema", ns), gr_segment_spec)
  check(get(".gr_ingest_schema", ns), gr_ingest_spec)
})

test_that("spec constructors clamp and fall back as before", {
  expect_identical(suppressWarnings(gr_read_spec(fan_in = 999))$fan_in, 32L)
  expect_identical(suppressWarnings(gr_read_spec(mmr = NA))$mmr, 1)
  expect_identical(gr_read_spec(min_score = -Inf)$min_score, -Inf)
  expect_identical(gr_read_spec(context_order = "doc")$context_order, "document")
  expect_error(gr_read_spec(context_order = "sideways"), class = "gr_bad_setting")
  expect_error(gr_read_spec(premise = "yes"), class = "gr_bad_setting")
  expect_identical(suppressWarnings(gr_segment_spec(max_tokens = 100,
                                                    overlap_tokens = 500))$overlap_tokens, 99L)
  expect_identical(gr_segment_spec("contextual", context_source = "l")$context_source, "llm")
  expect_identical(suppressWarnings(gr_ingest_spec(min_chars = NA))$min_chars, 20L)
  expect_null(gr_ingest_spec()$layout)
  expect_identical(gr_ingest_spec(layout = "raw")$layout, "raw")
  # The fields of a default spec, in order, are what store keys were made from.
  expect_identical(names(gr_read_spec()),
                   c("reader", "model", "temperature", "max_answer_tokens", "max_chunk_tokens",
                     "max_summary_tokens", "top_k", "min_score", "mmr", "context_order",
                     "restate", "rerank_candidates", "rerank_min_score", "fan_in",
                     "max_levels", "max_rounds", "preview_tokens", "members", "cite",
                     "skim_model", "summary_model", "parallel", "delay_between_calls",
                     "on_overflow"))
  expect_identical(names(gr_segment_spec()),
                   c("method", "max_tokens", "overlap_tokens", "min_tokens", "separators",
                     "prefix_section", "semantic_window", "semantic_percentile",
                     "context_source", "proposition_batch_tokens", "parallel"))
})

test_that("an effort map may only name declared call stems", {
  expect_error(gr_read_spec(effort = c(extrac = "low")), "extract.chunk",
               class = "hr_unknown_effort_key")
  expect_error(gr_read_spec(effort = c(map = "low", "synthesise.secton" = "high")),
               class = "hr_unknown_effort_key")
  # A stem, a part of one up to a dot, a label under one, and the default.
  ok <- c(map = "low", reduce = "high", "reduce.level1" = "low", segment = "minimal",
          synthesise = "low", "hier.summarise.L2" = "low", "outline.derive.alt2" = "high",
          default = "medium")
  expect_identical(gr_read_spec(effort = ok)$effort, ok)
  expect_identical(gr_read_spec(effort = c("low", map = "high"))$effort, c("low", map = "high"))
  # A reader of the user's declares its own stems.
  local_registries()
  gr_register_reader("longest", function(chunks, question, client, spec, trace) NULL,
                     signature = "one|1|none", calls = "longest.pick")
  expect_silent(gr_read_spec(effort = c("longest.pick" = "low")))
  expect_error(gr_read_spec(effort = c(longest = "low", "longest.answer" = "low")),
               class = "hr_unknown_effort_key")
  # One that declares none stands under its name.
  gr_register_reader("shortest", function(chunks, question, client, spec, trace) NULL,
                     signature = "one|1|none")
  expect_silent(gr_read_spec(effort = c("shortest.answer" = "low")))
  expect_error(gr_register_reader("bad", function(...) NULL, signature = "a|1|none",
                                  calls = c("a b")), class = "gr_bad_setting")
})

test_that("the registries list each module's call stems", {
  r <- gr_readers()
  expect_identical(r$calls[r$name == "map_reduce"], "map.answer, reduce")
  s <- gr_segmenters()
  expect_identical(s$calls[s$name == "paragraph"], "")
  expect_identical(s$calls[s$name == "proposition"], "segment.proposition")
})

test_that("every request a built-in reader makes carries a label it declares", {
  ch <- gr_segment(gr_ingest(sample_doc(3, 3)), list(method = "paragraph", max_tokens = 80))
  readers <- gr_readers()
  stems_of <- function(r) strsplit(readers$calls[readers$name == r], ", ", fixed = TRUE)[[1]]
  for (r in c("stuff", "map_reduce", "refine", "skim", "retrieve", "rerank", "hierarchical",
              "iterative", "preview")) {
    tr <- gr_trace()
    quiet(gr_read(ch, "How many participants?", mock_echo("482 participants."),
                  gr_read_spec(r, fan_in = 2, max_summary_tokens = 16), trace = tr))
    labels <- request_labels(tr)
    expect_true(length(labels) > 0, info = r)
    for (l in labels) expect_true(covered_by(l, stems_of(r)), info = paste(r, l))
  }
  tr <- gr_trace()
  quiet(gr_read(ch, "How many participants?", mock_echo("482 participants."),
                gr_read_spec("ensemble", members = c("stuff", "refine")), trace = tr))
  stems <- c(stems_of("ensemble"), stems_of("stuff"), stems_of("refine"))
  for (l in request_labels(tr)) expect_true(covered_by(l, stems), info = l)
  expect_true("ensemble.adjudicate" %in% request_labels(tr))
})

test_that("the segmenters that call a model label their calls as declared", {
  doc <- gr_ingest(sample_doc(2, 3))
  s <- gr_segmenters()
  for (m in c("proposition", "contextual")) {
    tr <- gr_trace()
    quiet(gr_segment(doc, gr_segment_spec(m, context_source = "llm", max_tokens = 200),
                     client = mock_echo("A context line."), trace = tr))
    labels <- request_labels(tr)
    expect_true(length(labels) > 0, info = m)
    for (l in labels) expect_true(covered_by(l, s$calls[s$name == m]), info = paste(m, l))
  }
})

test_that("a named_map takes a character vector or a fully named list", {
  s <- hr_schema(hr_param("a", "named_map", default = list()))
  expect_identical(hr_validate(s, list())$a, list())
  expect_identical(hr_validate(s, list(a = list(x = 1)))$a, list(x = 1))
  expect_identical(hr_validate(s, list(a = c(x = "low")))$a, c(x = "low"))
  expect_error(hr_validate(s, list(a = list(1))), class = "gr_bad_setting")
  expect_error(hr_validate(s, list(a = list(x = 1, 2))), class = "gr_bad_setting")
  expect_error(hr_validate(s, list(a = 3)), class = "gr_bad_setting")
})

test_that("every built-in reader states a numeric cost", {
  rd <- harnessr:::gr_state$readers
  expect_true(length(rd) > 0)
  for (r in names(rd)) expect_true(is.function(rd[[r]]$cost), info = r)
})

test_that("the pre-flight check counts a reader by its cost function", {
  local_registries()
  ch <- gr_segment(gr_ingest(sample_doc(2, 3)), list(method = "paragraph", max_tokens = 150))
  n <- nrow(ch$chunks)
  sent <- 0L
  fn <- function(chunks, question, client, spec, trace) {
    sent <<- sent + 1L
    new_answer("x", "costly", question, integer(0), trace)
  }
  gr_register_reader("costly", fn, signature = "some|10|none", calls = "costly.ask",
                     cost = function(input_stats, params) {
                       hr_cost(calls = 10, calls_max = 12, embed_max = 1)
                     })
  gr_options(max_calls = 5)
  expect_error(quiet(gr_read(ch, "q", gr_mock_client(), "costly")), "about 11 more requests",
               class = "gr_call_cap")
  expect_identical(sent, 0L)
  gr_options(max_calls = 100)
  tr <- gr_trace()
  quiet(gr_read(ch, "q", gr_mock_client(), "costly", trace = tr))
  note <- Filter(function(s) identical(s$label, "preflight"), tr$steps)[[1]]$detail
  expect_identical(c(note$est_calls, note$embed_calls, note$worst_calls), c(11L, 1L, 13L))
  # A reader that states no cost is one request per chunk.
  gr_register_reader("plain", fn, signature = "some|N|none")
  tr <- gr_trace()
  quiet(gr_read(ch, "q", gr_mock_client(), "plain", trace = tr))
  note <- Filter(function(s) identical(s$label, "preflight"), tr$steps)[[1]]$detail
  expect_identical(note$est_calls, as.integer(n))
  # An ensemble is its members' costs and one adjudication.
  tr <- gr_trace()
  quiet(gr_read(ch, "q", mock_echo(), list(reader = "ensemble", members = c("costly", "stuff")),
                trace = tr))
  note <- Filter(function(s) identical(s$label, "preflight"), tr$steps)[[1]]$detail
  expect_identical(note$est_calls, 13L)
  expect_error(gr_register_reader("x", fn, signature = "a|1|none", cost = "N"),
               class = "gr_bad_setting")
  # A plain list in the shape of the module contract, worst case only.
  gr_register_reader("worst", fn, signature = "some|N|none",
                     cost = function(input_stats, params) {
                       list(calls_max = 4, tokens_in_max = 0, tokens_out_max = 0, embed_max = 0)
                     })
  tr <- gr_trace()
  quiet(gr_read(ch, "q", gr_mock_client(), "worst", trace = tr))
  note <- Filter(function(s) identical(s$label, "preflight"), tr$steps)[[1]]$detail
  expect_identical(c(note$est_calls, note$worst_calls), c(4L, 4L))
  # The core tells a cost function the reply cap a request is sent.
  seen <- NULL
  gr_register_reader("peek", fn, signature = "some|N|none",
                     cost = function(input_stats, params) {
                       seen <<- input_stats$out_cap
                       hr_cost(calls = 1)
                     })
  quiet(gr_read(ch, "q", gr_mock_client(), "peek"))
  expect_true(is.numeric(seen) && length(seen) == 1L && seen > 0)
})

test_that("hr_cost checks its counts and costs add up", {
  expect_error(hr_cost(calls = -1), class = "gr_bad_setting")
  expect_error(hr_cost(calls = 1, sends = list(1)), class = "gr_bad_setting")
  a <- hr_cost(calls = 2, sends = list(list(tokens = 10, model = "m")), batched = FALSE)
  b <- hr_cost(calls = 3, calls_max = 5, tokens_in_max = 7, tokens_out_max = 4, embed_max = 1)
  s <- harnessr:::cost_sum(list(a, b), extra_calls = 1)
  expect_identical(c(s$calls, s$calls_max, s$tokens_in_max, s$tokens_out_max, s$embed_max),
                   c(6, 8, 7, 4, 1))
  expect_length(s$sends, 1L)
  expect_true(s$batched)
})

test_that("the governor names the limit a whole run cannot fit", {
  chk <- function(...) harnessr:::governor_run_check(...)$limit
  tr <- gr_trace(governor = hr_governor(max_calls = 5, max_cost_usd = 1))
  expect_identical(chk(tr, calls = 6, calls_max = 6), "calls")
  expect_identical(chk(tr, calls = 4, calls_max = 9, parallel = TRUE), "calls_worst")
  expect_true(is.na(chk(tr, calls = 4, calls_max = 9, parallel = FALSE, calls_only = TRUE)))
  expect_identical(chk(tr, calls = 1, calls_max = 1, unit_usd = c(m = NA_real_)), "unpriced")
  expect_true(is.na(chk(tr, calls = 1, calls_max = 1, unit_usd = c(m = NA_real_), exempt = TRUE)))
  expect_identical(chk(tr, calls = 1, calls_max = 1, unit_usd = c(m = 1), floor_usd = 2), "floor")
  expect_identical(chk(tr, calls = 1, calls_max = 1, unit_usd = c(m = 1), parallel = TRUE,
                       worst_usd = 2), "worst")
  expect_true(is.na(chk(tr, calls = 1, calls_max = 1, unit_usd = c(m = 1), worst_usd = 2)))
  tr0 <- gr_trace(governor = hr_governor(max_cost_usd = 0))
  expect_identical(chk(tr0, calls = 1, calls_max = 1, unit_usd = c(m = 1)), "zero")
})
