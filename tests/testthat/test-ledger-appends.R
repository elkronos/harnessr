# test-ledger-appends.R: a trace's steps are appended without copying the
# whole list each time, and the list holds exactly what the old c() appends
# gave it.
#
# The reference copies of trace_record(), trace_note() and trace_absorb() run
# the package's own code with the old append put back in place of
# trace_push_steps(), so the two traces differ only in how the list grew.

old_push <- function(trace, new) {
  trace$steps <- c(trace$steps, new)
  invisible(NULL)
}

with_old_push <- function(f) {
  env <- new.env(parent = asNamespace("harnessr"))
  env$trace_push_steps <- old_push
  environment(f) <- env
  f
}

# The clock fields differ between two runs of the same calls.
drop_clock <- function(steps) {
  lapply(steps, function(st) {
    st[c("at", "started_utc", "ended_utc", "seconds")] <- NULL
    st
  })
}

# 50 steps: notes, model calls (one failed, one cached, one an embedding) and
# three child traces folded in, one of them empty.
mixed_trace <- function(record, note, absorb) {
  tr <- gr_trace(meta = list(recipe = "parent"))
  msg <- list(list(role = "user", content = "q"))
  ok <- list(ok = TRUE, text = "a", model = "m1", usage = list(input = 3L, output = 1L))
  for (i in 1:10) note(tr, sprintf("note.%d", i), list(i = i))
  for (i in 1:8) record(tr, sprintf("call.%d", i), msg, ok, params = list(model = "m1"))
  record(tr, "call.fail", msg, list(ok = FALSE, error = "boom", model = "m1"))
  record(tr, "call.cached", msg, utils::modifyList(ok, list(cached = TRUE)))
  record(tr, "embed", msg, ok, embedding = TRUE)
  for (k in 1:2) {
    ch <- gr_trace(meta = list(source = sprintf("doc%d.txt", k), recipe = "child"))
    for (i in 1:6) note(ch, sprintf("child%d.note.%d", k, i))
    for (i in 1:4) record(ch, sprintf("child%d.call.%d", k, i), msg, ok)
    record(ch, sprintf("child%d.fail", k), msg, list(ok = FALSE, error = "bad"))
    absorb(tr, ch)
  }
  absorb(tr, gr_trace())
  for (i in 1:7) note(tr, sprintf("tail.%d", i))
  tr
}

test_that("indexed appends give the same steps as the old c() appends", {
  new <- mixed_trace(harnessr:::trace_record, harnessr:::trace_note,
                     harnessr:::trace_absorb)
  ref <- mixed_trace(with_old_push(harnessr:::trace_record),
                     with_old_push(harnessr:::trace_note),
                     with_old_push(harnessr:::trace_absorb))
  expect_length(new$steps, 50L)
  expect_true(is.list(new$steps) && is.null(attributes(new$steps)))
  expect_identical(drop_clock(new$steps), drop_clock(ref$steps))
  expect_identical(vapply(new$steps, function(st) st$step, integer(1)), 1:50)
  expect_identical(new$errors, ref$errors)
  for (f in c("calls", "cached", "tokens_in", "tokens_out", "embed_tokens", "spent_usd")) {
    expect_identical(new[[f]], ref[[f]], info = f)
  }
})

test_that("folding a trace with no steps leaves a list, as c() did", {
  p <- gr_trace()
  harnessr:::trace_absorb(p, gr_trace())
  expect_identical(p$steps, list())
  # A parent whose steps were cleared still ends with a list.
  q <- gr_trace()
  q$steps <- NULL
  harnessr:::trace_absorb(q, gr_trace())
  expect_identical(q$steps, list())
  harnessr:::trace_note(q, "x")
  expect_length(q$steps, 1L)
})

test_that("appends keep the names c() kept", {
  for (start in list(list(), list(a = list(step = 1L)), list(list(step = 1L)))) {
    for (add in list(list(list(step = 9L)), list(b = list(step = 9L)))) {
      t1 <- gr_trace()
      t1$steps <- start
      t2 <- gr_trace()
      t2$steps <- start
      harnessr:::trace_push_steps(t1, add)
      old_push(t2, add)
      expect_identical(t1$steps, t2$steps)
    }
  }
})

test_that("a caller holding the old step list keeps it unchanged", {
  tr <- gr_trace()
  harnessr:::trace_note(tr, "a")
  held <- tr$steps
  harnessr:::trace_note(tr, "b")
  expect_length(held, 1L)
  expect_length(tr$steps, 2L)
})

test_that("a step numbered from the trace's length is numbered before it is added", {
  tr <- gr_trace()
  for (i in 1:5) harnessr:::trace_note(tr, "n")
  harnessr:::trace_record(tr, "c", list(), list(ok = TRUE, text = "a"))
  expect_identical(vapply(tr$steps, function(st) st$step, integer(1)), 1:6)
})
