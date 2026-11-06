# test-core-ledger-records.R: what a trace step says about the request that
# went out and the reply that came back.
#
# The trace used to record the caller's values (a temperature left NULL, the
# cap asked for where a reasoning model was sent a larger one), the model asked
# for and not the one that answered, local times with no offset, one attempt
# however many were sent, and token counts with no word on whether the
# provider reported them or they were estimated here.

# Stands in for an OpenAI-shaped server. Every body it is sent is kept, with
# the URL, and each reply carries an id, a served model, a fingerprint and a
# usage block with the reasoning and cached-input breakdowns. `fail_first`
# requests are answered 503 before any is answered 200; `usage = FALSE`
# leaves the usage block out.
ledger_endpoint <- function(fail_first = 0L, usage = TRUE, env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  seen$bodies <- list()
  seen$urls <- character(0)
  seen$n <- 0L
  respond <- function(url, status, out) {
    structure(list(url = url, status_code = status,
                   headers = structure(list(`content-type` = "application/json; charset=utf-8"),
                                       class = c("insensitive", "list")),
                   content = charToRaw(as.character(jsonlite::toJSON(out, auto_unbox = TRUE)))),
              class = "response")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) {
      seen$n <- seen$n + 1L
      if (seen$n <= fail_first) {
        return(respond(url, 503L, list(error = list(message = "busy"))))
      }
      seen$bodies <- c(seen$bodies, list(body))
      seen$urls <- c(seen$urls, url)
      served <- paste0(body$model, "-2026-01-01")
      if (grepl("/responses$", url)) {
        out <- list(id = "resp_1", object = "response", model = served, status = "completed",
                    output_text = "Revenue was 45.2 million dollars.")
        if (usage) {
          out$usage <- list(input_tokens = 1000L, output_tokens = 300L,
                            input_tokens_details = list(cached_tokens = 800L),
                            output_tokens_details = list(reasoning_tokens = 250L))
        }
      } else {
        out <- list(id = "chatcmpl_1", object = "chat.completion", model = served,
                    system_fingerprint = "fp_abc",
                    choices = list(list(index = 0, finish_reason = "stop",
                                        message = list(role = "assistant",
                                                       content = "Revenue was 45.2."))))
        if (usage) {
          out$usage <- list(prompt_tokens = 1000L, completion_tokens = 300L,
                            prompt_tokens_details = list(cached_tokens = 800L),
                            completion_tokens_details = list(reasoning_tokens = 250L))
        }
      }
      respond(url, 200L, out)
    },
    .package = "httr", .env = env)
  seen
}

ledger_client <- function(api, model, extra_body = list(), max_retries = 0L) {
  gr_client(api_key = "sk-test", base_url = "https://ledger.invalid/v1", api = api,
            model = model, extra_body = extra_body, max_retries = max_retries,
            retry_pause_base = 0)
}

# The fields of a request body that params_sent records, read from the body.
body_record <- function(body, api, extra_names) {
  responses <- identical(api, "responses")
  fmt <- if (responses) body$text$format else body$response_format$json_schema
  na <- function(x, na) if (is.null(x)) na else x
  list(
    model = body$model,
    max_output = as.integer(na(body$max_output_tokens %||% body$max_completion_tokens %||%
                                 body$max_tokens, NA_integer_)),
    temperature = as.numeric(na(body$temperature, NA_real_)),
    effort = na(if (responses) body$reasoning$effort else body$reasoning_effort,
                NA_character_),
    schema_name = na(fmt$name, NA_character_),
    schema_hash = harnessr:::json_sha256(fmt$schema),
    extra_body_hash = harnessr:::json_sha256(if (length(extra_names)) body[extra_names])
  )
}

test_that("for each recorded step, params_sent equals the HTTP body that was sent", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE, temperature = 0.3)
  seen <- ledger_endpoint()
  schema <- list(type = "object", properties = list(revenue = list(type = "number")),
                 required = list("revenue"), additionalProperties = FALSE)
  cases <- list(
    # A temperature that only the option sets, on a model that takes one.
    list(api = "chat", model = "gpt-4o", args = list()),
    list(api = "responses", model = "gpt-4o", args = list(schema = schema)),
    # A reasoning model: no temperature, an effort, and a small cap that is
    # sent raised to the reasoning floor.
    list(api = "responses", model = "gpt-5.6-luna",
         args = list(max_output = 100, effort = "low", schema = schema)),
    list(api = "chat", model = "gpt-5.6-luna", args = list(max_output = 100, effort = "high")),
    # Extra body fields from the client and from the call.
    list(api = "chat", model = "gpt-4o", extra_body = list(user = "u-1"),
         args = list(temperature = 0.9, metadata = list(team = "a"))),
    list(api = "responses", model = "gpt-4o", extra_body = list(user = "u-2"), args = list())
  )
  tr <- gr_trace()
  extras <- list()
  for (cs in cases) {
    cl <- ledger_client(cs$api, cs$model, extra_body = cs$extra_body %||% list())
    res <- do.call(gr_call, c(list(cl, "What was revenue?", trace = tr), cs$args))
    expect_true(res$ok)
    extras <- c(extras, list(c(names(cs$extra_body), setdiff(names(cs$args),
      c("max_output", "temperature", "schema", "effort")))))
  }
  expect_length(seen$bodies, length(cases))
  for (i in seq_along(cases)) {
    sent <- tr$steps[[i]]$params_sent
    want <- body_record(seen$bodies[[i]], cases[[i]]$api, extras[[i]])
    for (f in names(want)) {
      expect_identical(sent[[f]], want[[f]], info = sprintf("case %d, %s", i, f))
    }
    expect_identical(sent$api, cases[[i]]$api)
    expect_identical(paste0(sent$base_url, if (sent$api == "responses") "/responses"
                                           else "/chat/completions"), seen$urls[i])
  }
  # The resolved values, which `params` does not hold: the option's
  # temperature, the raised cap, and no temperature for a reasoning model.
  expect_identical(tr$steps[[1]]$params_sent$temperature, 0.3)
  expect_null(tr$steps[[1]]$params$temperature)
  expect_identical(tr$steps[[3]]$params$max_output, 100L)
  expect_identical(tr$steps[[3]]$params_sent$max_output, 2048L)
  expect_true(is.na(tr$steps[[3]]$params_sent$temperature))
  expect_identical(tr$steps[[3]]$params_sent$effort, "low")
  expect_false(is.na(tr$steps[[5]]$params_sent$extra_body_hash))
  expect_true(is.na(tr$steps[[1]]$params_sent$extra_body_hash))
})

test_that("a cache hit records what would have been sent, and no attempt", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  seen <- ledger_endpoint()
  dir <- withr::local_tempdir()
  cl <- gr_cache_client(ledger_client("chat", "gpt-4o"), gr_cache(dir))
  tr <- gr_trace()
  first <- gr_call(cl, "What was revenue?", trace = tr)
  again <- gr_call(cl, "What was revenue?", trace = tr)
  expect_identical(seen$n, 1L)
  expect_true(again$cached)
  expect_identical(tr$steps[[2]]$params_sent, tr$steps[[1]]$params_sent)
  want <- body_record(seen$bodies[[1]], "chat", character(0))
  expect_identical(tr$steps[[2]]$params_sent[names(want)], want)
  expect_identical(tr$steps[[1]]$attempts, 1L)
  expect_identical(tr$steps[[2]]$attempts, 0L)
  # The stored reply keeps its breakdown, provenance and served model.
  expect_identical(again$usage, first$usage)
  expect_identical(tr$steps[[2]]$served_model, "gpt-4o-2026-01-01")
  expect_identical(tr$steps[[2]]$tokens$provenance, "reported")
})

test_that("a handler's params_sent is what the handler was given", {
  local_registries()
  gr_options(verbose = FALSE, temperature = 0.5)
  got <- list()
  cl <- gr_mock_client(function(m, p) { got[[length(got) + 1L]] <<- p; "ok" })
  tr <- gr_trace()
  gr_call(cl, "hi", trace = tr, schema = list(type = "object"), schema_name = "thing")
  gr_call(cl, "hi", trace = tr, temperature = 0.2)
  for (i in 1:2) {
    sent <- tr$steps[[i]]$params_sent
    p <- got[[i]]
    expect_identical(sent$model, p$model)
    expect_identical(sent$max_output, p$max_output)
    expect_identical(sent$temperature, if (is.null(p$temperature)) NA_real_ else p$temperature)
    expect_identical(sent$schema_hash, harnessr:::json_sha256(p$schema))
    expect_true(is.na(sent$extra_body_hash))
    expect_identical(tr$steps[[i]]$attempts, 1L)
  }
  expect_identical(tr$steps[[1]]$params_sent$schema_name, "thing")
  expect_true(is.na(tr$steps[[2]]$params_sent$schema_name))
})

test_that("the provider's served model, id, fingerprint and token breakdown are recorded", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  ledger_endpoint()
  tr <- gr_trace()
  gr_call(ledger_client("chat", "gpt-4o"), "What was revenue?", trace = tr)
  gr_call(ledger_client("responses", "gpt-4o"), "What was revenue?", trace = tr)
  st <- tr$steps[[1]]
  # `model` stays the model asked for; what answered is beside it.
  expect_identical(st$model, "gpt-4o")
  expect_identical(st$served_model, "gpt-4o-2026-01-01")
  expect_identical(st$response_id, "chatcmpl_1")
  expect_identical(st$fingerprint, "fp_abc")
  expect_identical(st$tokens, list(input = 1000L, output = 300L, reasoning = 250L,
                                   cached_input = 800L, provenance = "reported"))
  expect_identical(tr$steps[[2]]$response_id, "resp_1")
  expect_true(is.na(tr$steps[[2]]$fingerprint))
  expect_identical(tr$steps[[2]]$tokens$reasoning, 250L)
  expect_identical(tr$steps[[2]]$tokens$cached_input, 800L)
  # Breakdowns are parts of the counts, not additions to them.
  s <- gr_trace_summary(tr)
  expect_identical(s$tokens_out, 600L)
  expect_identical(s$tokens_reasoning, 500L)
  expect_identical(s$tokens_cached_in, 1600L)
  expect_identical(s$usage_estimated, 0)
  df <- as.data.frame(tr)
  expect_identical(df$served_model, rep("gpt-4o-2026-01-01", 2))
  expect_identical(df$tokens_reasoning, c(250L, 250L))
  out <- paste(capture.output(print(tr)), collapse = "\n")
  expect_match(out, "served by: gpt-4o-2026-01-01", fixed = TRUE)
})

test_that("cached input is priced at the cached rate where the model has one", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  ledger_endpoint()
  gr_register_model("ledger-priced", context_window = 128000L, max_output = 4096L,
                    input_usd = 2, output_usd = 10, cached_input_usd = 0.5)
  gr_register_model("ledger-flat", context_window = 128000L, max_output = 4096L,
                    input_usd = 2, output_usd = 10)
  tr <- gr_trace()
  gr_call(ledger_client("chat", "ledger-priced"), "What was revenue?", trace = tr)
  gr_call(ledger_client("chat", "ledger-flat"), "What was revenue?", trace = tr)
  # 200 input at $2, 800 cached at $0.50, 300 output at $10, reasoning
  # included once in the output.
  split <- (200 * 2 + 800 * 0.5 + 300 * 10) / 1e6
  flat <- (1000 * 2 + 300 * 10) / 1e6
  cost <- gr_trace_cost(tr)
  expect_equal(cost$usd[cost$model == "ledger-priced"], split)
  expect_equal(cost$usd[cost$model == "ledger-flat"], flat)
  expect_identical(cost$paid_cached_in, c(800L, 800L))
  expect_identical(cost$paid_reasoning, c(250L, 250L))
  expect_equal(tr$spent_usd, split + flat)
  expect_equal(as.data.frame(tr)$usd, c(split, flat))
  expect_equal(gr_estimate_cost("ledger-priced", 1000, 300, cached_input_tokens = 800), split)
  expect_equal(gr_estimate_cost("ledger-priced", 1000, 300), flat)
  expect_equal(gr_estimate_cost("ledger-flat", 1000, 300, cached_input_tokens = 800), flat)
})

test_that("usage the provider did not report is marked estimated, and the summary says so", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  ledger_endpoint(usage = FALSE)
  tr <- gr_trace()
  gr_call(ledger_client("chat", "gpt-4o"), "What was revenue?", trace = tr)
  expect_identical(tr$steps[[1]]$tokens$provenance, "estimated")
  expect_null(tr$steps[[1]]$tokens$reasoning)
  gr_call(gr_mock_client(function(m, p) {
    gr_result(TRUE, text = "x", usage = list(input = 3L, output = 1L))
  }), "hi", trace = tr)
  expect_identical(tr$steps[[2]]$tokens$provenance, "reported")
  expect_identical(gr_trace_summary(tr)$usage_estimated, 0.5)
  expect_match(paste(capture.output(print(tr)), collapse = "\n"),
               "usage: estimated locally for 50% of requests", fixed = TRUE)
  expect_true(is.na(gr_trace_summary(gr_trace())$usage_estimated))
})

test_that("retried requests are counted as attempts", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  seen <- ledger_endpoint(fail_first = 2L)
  tr <- gr_trace()
  res <- quiet(gr_call(ledger_client("chat", "gpt-4o", max_retries = 3L), "hi", trace = tr))
  expect_true(res$ok)
  expect_identical(seen$n, 3L)
  expect_identical(res$attempts, 3L)
  expect_identical(tr$steps[[1]]$attempts, 3L)
})

test_that("steps carry UTC start and end times, and the run its UTC start", {
  local_registries()
  gr_options(verbose = FALSE)
  tr <- gr_trace()
  gr_call(gr_mock_client(), "hi", trace = tr)
  iso <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"
  st <- tr$steps[[1]]
  expect_match(st$started_utc, iso)
  expect_match(st$ended_utc, iso)
  expect_true(st$started_utc <= st$ended_utc)
  js <- jsonlite::fromJSON(as_json(tr), simplifyVector = FALSE)
  expect_match(js$started, iso)
})

test_that("actor fields come from gr_trace(), then the actor option, else NA", {
  local_registries()
  gr_options(verbose = FALSE)
  empty <- gr_trace()
  expect_identical(empty$actor, list(system = NA_character_, owner = NA_character_,
                                     run_by = NA_character_, purpose = NA_character_,
                                     approved_by = NA_character_))
  gr_options(actor = list(system = "screening", owner = "Evidence team", run_by = "kim"))
  tr <- gr_trace(run_by = "lee", approved_by = "pat")
  expect_identical(tr$actor$system, "screening")
  expect_identical(tr$actor$owner, "Evidence team")
  expect_identical(tr$actor$run_by, "lee")
  expect_identical(tr$actor$approved_by, "pat")
  expect_true(is.na(tr$actor$purpose))
  js <- jsonlite::fromJSON(as_json(tr), simplifyVector = FALSE)
  expect_identical(js$actor$run_by, "lee")
  expect_null(js$actor$purpose)
  expect_match(paste(capture.output(print(tr)), collapse = "\n"), "run_by = lee", fixed = TRUE)
  expect_error(gr_options(actor = list(operator = "x")), class = "gr_bad_option")
  expect_error(gr_trace(owner = c("a", "b")), class = "gr_bad_option")
})

test_that("the config snapshot holds the options in force, without header values", {
  local_registries()
  gr_options(verbose = FALSE, max_calls = 12, api_headers = c(`api-key` = "secret-value"))
  tr <- gr_trace()
  expect_identical(tr$config$options$max_calls, 12)
  expect_identical(tr$config$options$api_headers, c(`api-key` = "<set>"))
  expect_false(grepl("secret-value", as_json(tr), fixed = TRUE))
  expect_true(is.character(tr$config$r_version))
})

test_that("a replayed step reports what the recorded step did, and sends nothing", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  ledger_endpoint()
  rec <- gr_trace()
  gr_call(ledger_client("chat", "gpt-4o"), "What was revenue?", trace = rec)
  path <- withr::local_tempfile(fileext = ".json")
  gr_trace_save(rec, path)
  tr <- gr_trace()
  rp <- gr_replay_client(path)
  gr_call(rp, "What was revenue?", model = "gpt-4o", trace = tr)
  st <- tr$steps[[1]]
  expect_true(st$cached)
  expect_identical(st$attempts, 0L)
  expect_identical(st$served_model, "gpt-4o-2026-01-01")
  expect_identical(st$tokens, rec$steps[[1]]$tokens)
  expect_identical(st$params_sent, rec$steps[[1]]$params_sent)
})

test_that("a failed request records a counted zero, not a reported one", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) stop("connection refused"),
    .package = "httr")
  tr <- gr_trace()
  res <- quiet(gr_call(ledger_client("chat", "gpt-4o", max_retries = 2L), "hi", trace = tr))
  expect_false(res$ok)
  st <- tr$steps[[1]]
  expect_identical(st$attempts, 3L)
  expect_identical(st$tokens$provenance, "counted")
  expect_identical(c(st$tokens$input, st$tokens$output), c(0L, 0L))
})

test_that("a 503 that never clears records a counted zero", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  seen <- ledger_endpoint(fail_first = 99L)
  tr <- gr_trace()
  res <- quiet(gr_call(ledger_client("chat", "gpt-4o", max_retries = 2L), "hi", trace = tr))
  expect_false(res$ok)
  expect_identical(seen$n, 3L)
  expect_identical(tr$steps[[1]]$attempts, 3L)
  expect_identical(tr$steps[[1]]$tokens$provenance, "counted")
})

test_that("a handler's gr_result with no usage is counted locally, not reported as 0/0", {
  local_registries()
  gr_options(verbose = FALSE)
  tr <- gr_trace()
  gr_call(gr_mock_client(function(m, p) gr_result(TRUE, text = "hello world there")),
          "hi", trace = tr)
  tok <- tr$steps[[1]]$tokens
  expect_false(identical(tok$provenance, "reported"))
  expect_true(tok$output > 0L)
})

# An embeddings endpoint answering 503 `fail_first` times, then either with
# vectors and a served model, or (`empty = TRUE`) with no embeddings at all.
embed_endpoint <- function(fail_first = 0L, empty = FALSE, env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  seen$n <- 0L
  respond <- function(url, status, out) {
    structure(list(url = url, status_code = status,
                   headers = structure(list(`content-type` = "application/json; charset=utf-8"),
                                       class = c("insensitive", "list")),
                   content = charToRaw(as.character(jsonlite::toJSON(out, auto_unbox = TRUE)))),
              class = "response")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL, encode = NULL) {
      seen$n <- seen$n + 1L
      if (seen$n <= fail_first) return(respond(url, 503L, list(error = list(message = "busy"))))
      if (empty) return(respond(url, 200L, list(object = "list", data = list())))
      data <- lapply(seq_along(body$input), function(i)
        list(object = "embedding", index = i - 1L, embedding = c(1, i, 0.5)))
      respond(url, 200L, list(object = "list", data = data,
                              model = "text-embedding-3-small-v2",
                              usage = list(prompt_tokens = 4L, total_tokens = 4L)))
    },
    .package = "httr", .env = env)
  seen
}

test_that("an embeddings request records its attempts, served model and provenance", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  seen <- embed_endpoint(fail_first = 1L)
  tr <- gr_trace()
  quiet(gr_embed(ledger_client("chat", "gpt-4o", max_retries = 2L), c("a", "b"),
                 trace = tr, cache = FALSE))
  st <- tr$steps[[1]]
  expect_identical(st$kind, "embedding")
  expect_identical(seen$n, 2L)
  expect_identical(st$attempts, 2L)
  expect_identical(st$served_model, "text-embedding-3-small-v2")
  expect_identical(st$tokens$provenance, "reported")
})

test_that("a failed embeddings request has a provenance", {
  local_registries()
  local_clean_cache()
  gr_options(verbose = FALSE)
  embed_endpoint(fail_first = 99L)
  tr <- gr_trace()
  quiet(gr_embed(ledger_client("chat", "gpt-4o", max_retries = 1L), c("a", "b"),
                 trace = tr, cache = FALSE))
  st <- tr$steps[[1]]
  expect_false(st$ok)
  expect_identical(st$attempts, 2L)
  expect_identical(st$tokens$provenance, "counted")
})
