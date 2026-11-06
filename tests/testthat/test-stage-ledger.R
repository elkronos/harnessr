# Every review stage records its calls on a trace of its own and folds that
# trace into the one it is given. gr_claims() and gr_outline() used to record
# straight onto the given trace (gr_outline() onto `claims$trace` when given
# none), so their `$trace` held other stages' calls and a parent trace past
# the call limit stopped them before they sent anything.

ledger_quiet <- function(expr) suppressWarnings(suppressMessages(expr))

ledger_review <- function(client, review) {
  p <- golden_protocol()
  s <- gr_screen(gr_example(), p, client = client, trace = review)
  x <- gr_extract(s, p, client = client, trace = review)
  cm <- gr_claims(x, question = p$question, client = client, trace = review)
  o <- gr_outline(cm, client = client, trace = review)
  syn <- gr_synthesise(x, protocol = p, outline = o, claims = cm, client = client,
                       trace = review)
  list(screen = s$trace, extract = x$trace, claims = cm$trace, outline = attr(o, "trace"),
       synthesise = syn$trace, claims_result = cm, outline_result = o, synthesis = syn,
       table = x)
}

# The extraction claims are drawn from, made with `client`.
golden_table <- function(client) {
  p <- golden_protocol()
  s <- ledger_quiet(gr_screen(gr_example(), p, client = client))
  ledger_quiet(gr_extract(s, p, client = client))
}

ledger_requests <- function(tr) {
  Filter(function(st) !identical(st$kind, "local") && !is.null(st$tokens), tr$steps)
}

test_that("the review's trace is the sum of its stages, with no call recorded twice", {
  local_registries()
  cl <- gr_mock_client(golden_reply)
  review <- gr_trace()
  r <- ledger_quiet(ledger_review(cl, review))
  stages <- r[c("screen", "extract", "claims", "outline", "synthesise")]
  for (nm in names(stages)) expect_s3_class(stages[[nm]], "gr_trace")
  # Five traces, none of them the parent and none shared between stages.
  ids <- vapply(stages, function(t) t$run_id, character(1))
  expect_false(anyDuplicated(ids) > 0L)
  expect_false(review$run_id %in% ids)

  sum_of <- function(k) sum(vapply(stages, function(t) as.numeric(t[[k]]), numeric(1)))
  expect_identical(as.numeric(review$calls), sum_of("calls"))
  expect_identical(as.numeric(review$tokens_in), sum_of("tokens_in"))
  expect_identical(as.numeric(review$tokens_out), sum_of("tokens_out"))
  expect_identical(length(review$steps),
                   sum(vapply(stages, function(t) length(t$steps), integer(1))))
  expect_equal(sum(gr_trace_cost(review)$usd),
               sum(vapply(stages, function(t) sum(gr_trace_cost(t)$usd), numeric(1))))
  # Each request the client answered is in the parent exactly once.
  expect_identical(length(ledger_requests(review)), length(cl$calls()))
  expect_identical(review$calls, length(cl$calls()))

  # The claims stage holds its own calls and nothing else.
  labels <- function(t) vapply(t$steps, function(st) as.character(st$label %||% ""), character(1))
  expect_true(all(startsWith(labels(r$claims), "claims.")))
  expect_true(all(startsWith(labels(r$outline), "outline.")))
  expect_identical(sum(startsWith(labels(review), "claims.")), length(r$claims$steps))
  expect_identical(sum(startsWith(labels(review), "outline.")), length(r$outline$steps))
})

test_that("gr_outline() leaves the trace of the claims it is given as it was", {
  local_registries()
  cl <- gr_mock_client(golden_reply)
  cm <- ledger_quiet(gr_claims(golden_table(cl), question = "How did revenue change?",
                               client = cl))
  before <- list(calls = cm$trace$calls, steps = length(cm$trace$steps))
  o <- ledger_quiet(gr_outline(cm, client = cl))
  expect_identical(list(calls = cm$trace$calls, steps = length(cm$trace$steps)), before)
  # Its call is on the outline's own trace instead.
  tr <- attr(o, "trace")
  expect_s3_class(tr, "gr_trace")
  expect_identical(tr$calls, 1L)
  expect_identical(tr$steps[[1]]$label, "outline.derive")
  expect_identical(tr$meta$stage, "outline")
})

test_that("a parent past the call limit does not stop claims or the outline", {
  local_registries()
  cl <- gr_mock_client(golden_reply)
  tab <- golden_table(cl)
  gr_options(max_calls = 5)
  review <- gr_trace()
  # As if an earlier stage had spent more than the per-stage limit.
  review$calls <- 50L
  cm <- ledger_quiet(gr_claims(tab, question = "How did revenue change?", client = cl,
                               trace = review))
  expect_false(cm$partial)
  expect_gt(nrow(cm$claims), 0L)
  o <- NULL
  expect_no_warning(o <- suppressMessages(gr_outline(cm, client = cl, trace = review)))
  expect_identical(attr(o, "trace")$calls, 1L)
  expect_identical(review$calls, 50L + cm$trace$calls + 1L)
})

test_that("calls made before an error still reach the parent", {
  local_registries()
  n <- 0L
  cl <- gr_mock_client(function(messages, params) {
    n <<- n + 1L
    golden_reply(messages, params)
  })
  cm <- ledger_quiet(gr_claims(golden_table(cl), question = "How did revenue change?",
                               client = cl))
  review <- gr_trace()
  before <- n
  # Fails after the outline's request was answered.
  local_mocked_bindings(finish_outline = function(...) stop("boom"))
  expect_error(ledger_quiet(gr_outline(cm, client = cl, trace = review)), "boom")
  expect_identical(n - before, 1L)
  expect_identical(review$calls, 1L)
})

test_that("calls gr_claims() made before an error still reach the parent", {
  local_registries()
  n <- 0L
  cl <- gr_mock_client(function(messages, params) {
    n <<- n + 1L
    golden_reply(messages, params)
  })
  tab <- golden_table(cl)
  review <- gr_trace()
  before <- n
  # Fails after the claims.draw request was answered.
  local_mocked_bindings(new_claims = function(...) stop("boom"))
  expect_error(ledger_quiet(gr_claims(tab, question = "How did revenue change?", client = cl,
                                      trace = review)), "boom")
  expect_gt(n - before, 0L)
  expect_identical(review$calls, n - before)
})

test_that("an outline at the call cap is not requested and costs the parent nothing", {
  local_registries()
  cl <- gr_mock_client(golden_reply)
  cm <- ledger_quiet(gr_claims(golden_table(cl), question = "How did revenue change?",
                               client = cl))
  gr_options(max_calls = 0)
  review <- gr_trace()
  before <- length(cl$calls())
  o <- NULL
  expect_warning(o <- suppressMessages(gr_outline(cm, client = cl, trace = review)),
                 "not requested: the run had reached its call cap", class = "gr_outline_failed")
  expect_identical(length(cl$calls()), before)
  expect_identical(attr(o, "trace")$calls, 0L)
  expect_identical(review$calls, 0L)
})

test_that("the audit's claims row counts the outline's calls once", {
  local_registries()
  cl <- gr_mock_client(golden_reply)
  review <- gr_trace()
  r <- ledger_quiet(ledger_review(cl, review))
  st <- harnessr:::claims_cost_stage(r$claims_result, r$synthesis$outline_trace)
  expect_identical(st$trace$calls, r$claims$calls + r$outline$calls)
  # The same trace given twice is read once.
  again <- harnessr:::claims_cost_stage(r$claims_result, r$claims)
  expect_identical(again$trace$calls, r$claims$calls)

  # An outline recorded on the claims' own trace (`trace = cm$trace`) is
  # folded into it too, and still counted once.
  cm <- r$claims_result
  claims_only <- length(ledger_requests(cm$trace))
  o <- ledger_quiet(gr_outline(cm, client = cl, trace = cm$trace))
  expect_identical(cm$trace$calls, claims_only + attr(o, "trace")$calls)
  syn <- ledger_quiet(gr_synthesise(r$table, protocol = golden_protocol(), outline = o,
                                    claims = cm, client = cl))
  st <- harnessr:::claims_cost_stage(cm, syn$outline_trace)
  expect_identical(st$trace$calls, claims_only + attr(o, "trace")$calls)
})
