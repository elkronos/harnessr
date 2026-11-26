# test-core-price-reports.R: every report of a cost in dollars says where its
# prices came from. For each model it prices: whether the model has a price,
# the month of that price (`as_of`) and whether the registry entry is a fact
# (`certain`). A model with no price costs NA, never 0, and the printed cost
# names it with the function that sets one. A total over several models of
# which some have no price says it covers only the priced ones.

# One request to `model` with the given token counts, recorded on `tr`.
pr_record <- function(tr, model, input = 1000L, output = 10L, label = "a") {
  harnessr:::trace_record(tr, label, list(list(role = "user", content = "q")),
                          harnessr:::gr_result(TRUE, text = "x", model = model,
                                               usage = list(input = input, output = output)))
}

# Register a model with prices from the month `as_of`. The tests that use it
# set `today` to 2026-12-01, so a recent month raises no stale price warning.
pr_price <- function(id, as_of, input_usd = 2, output_usd = 8) {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f), add = TRUE)
  writeLines(c("id,context_window,max_output,input_usd,output_usd,as_of",
               sprintf("%s,128000,4096,%s,%s,%s", id, input_usd, output_usd, as_of)), f)
  hr_load_models(f)
}

test_that("hr_trace_cost() says, per model, whether it is priced, as of when, and how surely", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  tr <- hr_trace()
  pr_record(tr, "pr-priced")
  pr_record(tr, "pr-registered-unpriced")
  hr_register_model("pr-registered-unpriced", context_window = 128000L, max_output = 4096L)
  suppressWarnings(pr_record(tr, "gpt-4o-2099-01-01"))
  cost <- suppressWarnings(hr_trace_cost(tr))
  # The columns there before come first, unchanged, and the new ones last.
  expect_identical(names(cost),
                   c("model", "calls", "paid_calls", "paid_in", "paid_out", "usd",
                     "paid_reasoning", "paid_cached_in", "priced", "as_of", "certain"))
  row <- function(m) cost[cost$model == m, ]
  expect_true(row("pr-priced")$priced)
  expect_identical(row("pr-priced")$as_of, "2026-11")
  expect_true(row("pr-priced")$certain)
  expect_equal(row("pr-priced")$usd, 1000 / 1e6 * 2 + 10 / 1e6 * 8)
  # A registered model with no price: NA, not 0, and no month.
  expect_false(row("pr-registered-unpriced")$priced)
  expect_true(is.na(row("pr-registered-unpriced")$as_of))
  expect_true(row("pr-registered-unpriced")$certain)
  expect_true(is.na(row("pr-registered-unpriced")$usd))
  # A family guess has no price and is not certain.
  expect_false(row("gpt-4o-2099-01-01")$priced)
  expect_false(row("gpt-4o-2099-01-01")$certain)
  # An empty trace has the same columns.
  expect_identical(names(hr_trace_cost(hr_trace())), names(cost))
})

test_that("the price columns raise neither the unknown model nor the stale price warning", {
  local_registries()
  local_price_warnings()
  pr_price("pr-old", "2020-01")
  tr <- hr_trace()
  suppressWarnings(pr_record(tr, "pr-old"))
  local_price_warnings()
  st <- harnessr:::price_status(c("pr-old", "a-model-nobody-has"))
  expect_identical(st$priced, c(TRUE, FALSE))
  expect_identical(st$as_of, c("2020-01", NA))
  expect_identical(st$certain, c(TRUE, FALSE))
  expect_silent(harnessr:::price_status(c("pr-old", "a-model-nobody-has")))
})

test_that("hr_estimate_cost(detail = TRUE) gives the figure with where its prices came from", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-10")
  d <- hr_estimate_cost("pr-priced", 1e6, 1e5, detail = TRUE)
  expect_s3_class(d, "data.frame")
  expect_identical(names(d), c("model", "usd", "priced", "as_of", "certain"))
  expect_equal(d$usd, hr_estimate_cost("pr-priced", 1e6, 1e5))
  expect_true(d$priced)
  expect_identical(d$as_of, "2026-10")
  expect_true(d$certain)
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  u <- hr_estimate_cost("pr-unpriced", 1e6, 1e5, detail = TRUE)
  expect_true(is.na(u$usd))
  expect_false(u$priced)
  expect_true(is.na(u$as_of))
  # The default is still the figure alone.
  expect_identical(hr_estimate_cost("pr-priced", 1e6, 1e5), d$usd)
  expect_error(hr_estimate_cost("pr-priced", 1, 1, detail = NA), class = "gr_bad_setting")
  expect_error(hr_estimate_cost("pr-priced", 1, 1, detail = "yes"), class = "gr_bad_setting")
})

test_that("as.data.frame(trace) gives each request's price columns, last", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  tr <- hr_trace()
  pr_record(tr, "pr-priced")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  pr_record(tr, "pr-unpriced")
  df <- as.data.frame(tr)
  expect_identical(utils::tail(names(df), 3L), c("priced", "as_of", "certain"))
  expect_identical(names(df)[1:14],
                   c("step", "document", "recipe", "stage", "model", "ok", "cached",
                     "tokens_in", "tokens_out", "usd", "seconds", "error", "prompt", "reply"))
  expect_identical(df$priced, c(TRUE, FALSE))
  expect_identical(df$as_of, c("2026-11", NA))
  expect_true(is.na(df$usd[2]))
})

test_that("a printed trace gives the month of its prices", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  tr <- hr_trace()
  pr_record(tr, "pr-priced")
  out <- capture.output(print(tr))
  expect_true(any(grepl("cost: $0.0021 across pr-priced, prices as of 2026-11", out,
                        fixed = TRUE)))
  # Prices from different months give the range.
  pr_price("pr-older", "2026-09")
  pr_record(tr, "pr-older")
  out <- capture.output(print(tr))
  expect_true(any(grepl("prices as of 2026-09 to 2026-11", out, fixed = TRUE)))
})

test_that("a total over priced and unpriced models says it covers only the priced ones", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  tr <- hr_trace()
  pr_record(tr, "pr-priced")
  pr_record(tr, "pr-unpriced")
  line <- grep("cost:", capture.output(print(tr)), value = TRUE)
  expect_match(line, "$0.0021 covers the priced models only (pr-priced, prices as of 2026-11)",
               fixed = TRUE)
  expect_match(line, "no price set for pr-unpriced (set one with hr_register_model()",
               fixed = TRUE)
  # The data still say NA for the total: printing does not make it a number.
  expect_true(is.na(sum(hr_trace_cost(tr)$usd)))
})

test_that("a cost with no priced model prints as unknown, naming the model", {
  local_registries()
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  tr <- hr_trace()
  pr_record(tr, "pr-unpriced")
  line <- grep("cost:", capture.output(print(tr)), value = TRUE)
  expect_match(line, paste0("cost unknown: no price set for pr-unpriced (set one with ",
                            "hr_register_model() or hr_load_models())"), fixed = TRUE)
  expect_false(grepl("$0", line, fixed = TRUE))
})

test_that("a priced model with an unknown token count is not reported as unpriced", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  cost <- data.frame(model = "pr-priced", usd = NA_real_, stringsAsFactors = FALSE)
  txt <- harnessr:::format_trace_cost(cost)
  expect_identical(txt, "cost unknown: token counts unknown for pr-priced")
})

test_that("the progress line gives the priced spend, and says that is what it is", {
  local_registries()
  local_mocked_bindings(progress_wanted = function() TRUE,
                        price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  tr <- hr_trace()
  pr_record(tr, "pr-priced")
  p <- harnessr:::progress_start(3L, "item", trace = tr)
  expect_identical(harnessr:::progress_cost(p), ", $0.0021 spent")
  pr_record(tr, "pr-unpriced")
  expect_identical(harnessr:::progress_cost(p), ", $0.0021 spent on priced models")
  # With no priced request, nothing is known.
  tr2 <- hr_trace()
  pr_record(tr2, "pr-unpriced")
  p2 <- harnessr:::progress_start(3L, "item", trace = tr2)
  expect_identical(harnessr:::progress_cost(p2), ", cost unknown")
})

# A benchmark of two arms: one on a priced model, one on a model with none.
pr_bench <- function() {
  ref <- hr_reference(items = list(q1 = "France", q2 = "Peru"), labels = c("Paris", "Lima"),
                      cluster = c("a", "b"), split = "test")
  cl <- hr_mock_client(function(messages, params) {
    if (grepl("France", messages[[1]]$content)) "Paris" else "Lima"
  })
  arm <- function(name, model) {
    hr_arm(name, function(item, ctx) ctx$call(paste0("Capital of ", item), model = model)$text)
  }
  suppressWarnings(hr_benchmark(list(arm("priced", "pr-priced"), arm("unpriced", "pr-unpriced")),
                                ref, runs = 2, client = cl,
                                governor = hr_governor(max_calls = 100)))
}

test_that("hr_benchmark() gives each run's price columns after `reportable`", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  b <- pr_bench()
  at <- match("reportable", names(b))
  expect_identical(names(b)[at + 0:3], c("reportable", "priced", "as_of", "certain"))
  expect_true(all(b$priced[b$arm == "priced"]))
  expect_true(all(b$as_of[b$arm == "priced"] == "2026-11"))
  expect_false(any(b$priced[b$arm == "unpriced"]))
  expect_true(all(is.na(b$as_of[b$arm == "unpriced"])))
  expect_true(all(is.na(b$usd[b$arm == "unpriced"])))
  out <- capture.output(print(b))
  line <- grep("cost:", out, value = TRUE)
  expect_match(line, "covers the priced models only (pr-priced, prices as of 2026-11)",
               fixed = TRUE)
  expect_match(line, "no price set for pr-unpriced", fixed = TRUE)
})

test_that("hr_report() gives each arm's price columns and a line under the cost table", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  b <- pr_bench()
  rep <- suppressWarnings(hr_report(b, B = 100))
  co <- rep$cost
  expect_identical(utils::tail(names(co), 3L), c("priced", "as_of", "certain"))
  expect_identical(co$priced[co$arm == "priced"], TRUE)
  expect_identical(co$as_of[co$arm == "priced"], "2026-11")
  expect_identical(co$priced[co$arm == "unpriced"], FALSE)
  expect_true(is.na(co$as_of[co$arm == "unpriced"]))
  expect_true(is.na(co$usd_per_item[co$arm == "unpriced"]))
  expect_true(any(grepl("No price set for a model that unpriced used", rep$notes, fixed = TRUE)))
  out <- capture.output(print(rep))
  expect_true(any(grepl("prices as of 2026-11; no price set for a model of unpriced", out,
                        fixed = TRUE)))
  # A plain table without the columns reports them as NA and prints no line.
  plain <- as.data.frame(b)[c("cluster", "item", "arm", "run", "correct", "usd")]
  rp <- suppressWarnings(hr_report(plain, B = 100))
  expect_true(all(is.na(rp$cost$priced)))
  expect_false(any(grepl("prices as of", capture.output(print(rp)), fixed = TRUE)))
})

test_that("hr_judge() says where the judge's prices came from", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-judge", "2026-10")
  cl <- hr_mock_client(function(m, p) '{"verdict": "A", "reason": "checked"}')
  res <- hr_judge(c("Paris", "Lyon"), cl, mode = "select", model = "pr-judge", rubric = "r")
  expect_true(res$judge_cost$priced)
  expect_identical(res$judge_cost$as_of, "2026-10")
  expect_true(res$judge_cost$certain)
  expect_identical(res$judge_cost$models, "pr-judge")
  expect_true(any(grepl("judge cost: 2 call(s), $", capture.output(print(res)), fixed = TRUE)))
  expect_true(any(grepl(", prices as of 2026-10", capture.output(print(res)), fixed = TRUE)))
  hr_register_model("pr-judge-unpriced", context_window = 128000L, max_output = 4096L)
  un <- suppressWarnings(hr_judge(c("Paris", "Lyon"), cl, mode = "select",
                                  model = "pr-judge-unpriced", rubric = "r"))
  expect_true(is.na(un$judge_cost$usd))
  expect_false(un$judge_cost$priced)
  expect_true(any(grepl("judge cost: 2 call(s), unknown: no price set for pr-judge-unpriced",
                        capture.output(print(un)), fixed = TRUE)))
})

test_that("hr_effort_check() gives each arm's price columns", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  hr_register_model("pr-unpriced", context_window = 128000L, max_output = 4096L)
  b <- pr_bench()
  costs <- harnessr:::effort_costs(b)
  expect_identical(utils::tail(names(costs), 3L), c("priced", "as_of", "certain"))
  expect_identical(costs$priced, c(TRUE, FALSE))
  expect_identical(costs$as_of, c("2026-11", NA))
})

test_that("a free failed request to an unpriced model leaves a run's cost priced", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  pr_price("pr-priced", "2026-11")
  ref <- hr_reference(items = list(q1 = "France", q2 = "Peru"), labels = c("Paris", "Lima"),
                      cluster = c("a", "b"), split = "test")
  cl <- hr_mock_client(function(messages, params) {
    if (grepl("France", messages[[1]]$content)) "Paris" else "Lima"
  })
  # An embeddings request to a model with no price fails before it sends a
  # token, which costs nothing, then a priced call.
  arm <- hr_arm("a", function(item, ctx) {
    harnessr:::trace_record(ctx$trace, "embed.request", list(list(role = "user", content = "q")),
                            harnessr:::gr_result(FALSE, error = "HTTP 404", status = 404L,
                                                 model = "pr-emb-unpriced"),
                            embedding = TRUE)
    ctx$call(paste0("Capital of ", item), model = "pr-priced")$text
  })
  b <- suppressWarnings(hr_benchmark(list(arm), ref, runs = 2, client = cl,
                                     governor = hr_governor(max_calls = 100)))
  cost <- hr_trace_cost(attr(b, "traces")[[1]])
  expect_identical(cost$usd[cost$model == "pr-emb-unpriced"], 0)
  expect_false(cost$priced[cost$model == "pr-emb-unpriced"])
  expect_true(all(b$priced))
  expect_true(all(b$as_of == "2026-11"))
  expect_false(anyNA(b$usd))
  rep <- suppressWarnings(hr_report(b, B = 100))
  expect_identical(rep$cost$priced, TRUE)
  expect_false(any(grepl("No price set", rep$notes, fixed = TRUE)))
  expect_false(any(grepl("no price set", capture.output(print(rep)), fixed = TRUE)))

  # The judge's cost and gr_compare()'s rows read the same rule.
  jt <- hr_trace()
  harnessr:::trace_record(jt, "embed.request", list(list(role = "user", content = "q")),
                          harnessr:::gr_result(FALSE, error = "HTTP 404", status = 404L,
                                               model = "pr-emb-unpriced"), embedding = TRUE)
  pr_record(jt, "pr-priced")
  jc <- harnessr:::judge_steps_cost(jt, 0L)
  expect_true(jc$priced)
  expect_identical(jc$as_of, "2026-11")
  expect_true(harnessr:::cost_prices(hr_trace_cost(jt))$priced)
  # A cost that is unknown still counts as unpriced.
  pr_record(jt, "pr-emb-unpriced")
  expect_false(harnessr:::judge_steps_cost(jt, 0L)$priced)
  expect_false(harnessr:::cost_prices(hr_trace_cost(jt))$priced)
})
