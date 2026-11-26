# test-effort-escalate.R: hr_effort_escalate(), hr_effort_event(),
# hr_effort_log(), the read setting effort_mode = "escalate", and
# hr_effort_check(). Unset, nothing here touches a request: the golden
# records check that. These tests check what a policy does when it is given.

ee_model <- "gpt-5.6-luna"

ee_steps <- function(tr, label) {
  Filter(function(s) identical(s$label, label) && identical(s$kind, "local"), tr$steps)
}

ee_efforts <- function(tr) {
  df <- as.data.frame(tr)
  df[!is.na(df$effort), c("stage", "effort")]
}

test_that("hr_effort_escalate() checks its arguments", {
  p <- hr_effort_escalate()
  expect_s3_class(p, "hr_effort_escalate")
  expect_identical(p$base, "low")
  expect_identical(p$to, "high")
  expect_true(all(c("truncated", "not_in_document", "disagreement") %in% p$on))
  expect_output(print(p), "raised to high")
  expect_error(hr_effort_escalate(to = c("a", "b")), class = "gr_bad_setting")
  expect_error(hr_effort_escalate(max_escalations = -1), class = "gr_bad_setting")
  expect_error(hr_effort_escalate(replies = c("x")), class = "gr_bad_setting")
  expect_error(hr_effort_escalate(on = character(0)), class = "gr_bad_setting")
  expect_identical(effort_stage("reduce.level2"), "reduce")
  expect_identical(effort_stage("hier.summarise.L3"), "hier.summarise")
  expect_identical(effort_stage("map.answer"), "map.answer")
  expect_identical(effort_stage("synthesise.revise.structure"), "synthesise.revise")
})

test_that("a trigger raises the next stage only, and the log says whether it resolved", {
  pol <- hr_effort_escalate()
  cl <- hr_mock_client(function(m, p) {
    if (identical(p$effort, "low") && grepl("first", m[[1]]$content)) {
      return(gr_result(TRUE, "Partial", finish_reason = "length"))
    }
    paste("done at", p$effort)
  })
  tr <- hr_trace()
  call <- function(txt, label) hr_call(cl, txt, model = ee_model, trace = tr, label = label,
                                       effort = pol)$text
  expect_identical(call("first a", "plan.draft"), "Partial")
  expect_identical(call("first b", "plan.draft"), "Partial")   # same stage: no change
  expect_identical(call("second", "plan.final"), "done at high")
  expect_identical(call("second again", "plan.final"), "done at high")
  expect_identical(call("third", "plan.after"), "done at low")   # back to base
  log <- hr_effort_log(tr)
  expect_identical(nrow(log), 1L)
  expect_identical(log$after, "plan.draft")
  expect_identical(log$stage, "plan.final")
  expect_identical(log$triggers, "truncated")
  expect_identical(log$calls, 2L)
  expect_true(log$resolved)
  expect_length(ee_steps(tr, "effort.escalate"), 1L)
  expect_length(ee_steps(tr, "effort.resolve"), 1L)
  # At most max_escalations raises a run: a second trigger raises nothing.
  expect_identical(call("first c", "plan.redo"), "Partial")
  expect_identical(call("fourth", "plan.end"), "done at low")
  expect_identical(nrow(hr_effort_log(tr)), 1L)
})

test_that("a raise that does not resolve its trigger is logged as unresolved", {
  pol <- hr_effort_escalate(max_escalations = 2)
  cl <- hr_mock_client(function(m, p) gr_result(TRUE, "cut", finish_reason = "length"))
  tr <- hr_trace()
  for (lab in c("a.one", "a.two")) hr_call(cl, "x", model = ee_model, trace = tr, label = lab,
                                           effort = pol)
  log <- hr_effort_log(tr)   # the run ended in the raised stage: settled from the trace
  expect_false(log$resolved)
  expect_identical(log$calls, 1L)
})

test_that("a cut counts for the stage whose request it was made for", {
  pol <- hr_effort_escalate()
  cl <- hr_mock_client(function(m, p) paste("done at", p$effort))
  long <- paste(rep("word", 200), collapse = " ")
  call <- function(tr, label) hr_call(cl, "x", model = ee_model, trace = tr, label = label,
                                      effort = pol)$text
  # A cut made while stage b packs its first request belongs to b: b goes out
  # at base and the stage after it is raised.
  tr <- hr_trace()
  expect_identical(call(tr, "a.x"), "done at low")
  hr_truncate(long, 10, trace = tr, where = "b.input")
  expect_identical(call(tr, "b.x"), "done at low")
  expect_identical(call(tr, "c.x"), "done at high")
  log <- hr_effort_log(tr)
  expect_identical(log$after, "b.x")
  expect_identical(log$stage, "c.x")
  expect_identical(log$triggers, "truncated")
  # A cut made before the run's first request belongs to the first stage.
  tr2 <- hr_trace()
  hr_truncate(long, 10, trace = tr2, where = "a.input")
  expect_identical(call(tr2, "a.x"), "done at low")
  expect_identical(call(tr2, "b.x"), "done at high")
  expect_identical(hr_effort_log(tr2)$after, "a.x")
  # An event reported after a stage's last request still belongs to it.
  tr3 <- hr_trace()
  call(tr3, "a.x")
  hr_effort_event(tr3, "unclear")
  expect_identical(call(tr3, "b.x"), "done at high")
  expect_identical(hr_effort_log(tr3)$after, "a.x")
  # In a read: refine cuts the excerpt of its first chunk before the draft
  # request, so the cut is the draft's and the revisions are raised.
  local_registries()
  hr_register_model("ee-tiny", context_window = 700, max_output = 100, reasoning = TRUE)
  txt <- vapply(1:3, function(i) paste(rep(sprintf("Fact %d about the region.", i), 30),
                                       collapse = " "), "")
  ch <- new_chunks(txt, "precomputed", gr_segment_spec(max_tokens = 300))
  tr4 <- hr_trace()
  quiet(gr_read(ch, "Q?", cl, gr_read_spec("refine", model = "ee-tiny", effort_mode = "escalate"),
                trace = tr4))
  ef <- ee_efforts(tr4)
  expect_identical(ef$effort[ef$stage == "refine.draft"], "low")
  expect_true(all(ef$effort[ef$stage == "refine.revise"] == "high"))
  expect_identical(hr_effort_log(tr4)$after, "refine.draft")
})

test_that("a raised stage that fires again raises the next one while raises are left", {
  pol <- hr_effort_escalate(max_escalations = 2)
  cl <- hr_mock_client(function(m, p) paste("done at", p$effort))
  tr <- hr_trace()
  sent <- vapply(c("a.x", "b.x", "c.x", "d.x"), function(lab) {
    out <- hr_call(cl, "x", model = ee_model, trace = tr, label = lab, effort = pol)$text
    hr_effort_event(tr, "unclear")
    out
  }, "")
  expect_identical(unname(sent), c("done at low", "done at high", "done at high", "done at low"))
})

test_that("a reply sentinel fires only when every request of the stage gave it", {
  pol <- hr_effort_escalate(replies = c(not_in_document = "NOT_IN_DOCUMENT"))
  seen <- character(0)
  answers <- c("NOT_IN_DOCUMENT", "Revenue was 45.2 million.", "x", "NOT_IN_DOCUMENT", "y")
  k <- 0
  cl <- hr_mock_client(function(m, p) {
    k <<- k + 1
    seen <<- c(seen, p$effort)
    answers[[k]]
  })
  tr <- hr_trace()
  hr_call(cl, "a", model = ee_model, trace = tr, label = "s.one", effort = pol)
  hr_call(cl, "b", model = ee_model, trace = tr, label = "s.one", effort = pol)
  hr_call(cl, "c", model = ee_model, trace = tr, label = "s.two", effort = pol)
  expect_identical(seen, c("low", "low", "low"))
  hr_call(cl, "d", model = ee_model, trace = tr, label = "s.three", effort = pol)
  hr_call(cl, "e", model = ee_model, trace = tr, label = "s.four", effort = pol)
  expect_identical(seen[5], "high")
  expect_identical(hr_effort_log(tr)$triggers, "not_in_document")
})

test_that("a reply that is not the JSON asked for is a trigger", {
  pol <- hr_effort_escalate()
  cl <- hr_mock_client(function(m, p) if (identical(p$effort, "low")) "not json" else '{"a": 1}')
  tr <- hr_trace()
  r1 <- gr_call_json(cl, "q", schema = list(type = "object"), model = ee_model, trace = tr,
                     label = "j.one", effort = pol)
  expect_false(r1$ok)
  r2 <- gr_call_json(cl, "q", schema = list(type = "object"), model = ee_model, trace = tr,
                     label = "j.two", effort = pol)
  expect_true(r2$ok)
  expect_identical(hr_effort_log(tr)$triggers, "parse_failure")
})

test_that("hr_effort_event() records only under a policy", {
  tr <- hr_trace()
  expect_false(hr_effort_event(tr, "disagreement"))
  expect_length(tr$steps, 0L)
  expect_false(hr_effort_event(NULL, "disagreement"))
  cl <- hr_mock_client(function(m, p) paste("at", p$effort))
  pol <- hr_effort_escalate()
  hr_call(cl, "a", model = ee_model, trace = tr, label = "e.one", effort = pol)
  expect_true(hr_effort_event(tr, "disagreement", members = 2))
  expect_identical(hr_call(cl, "b", model = ee_model, trace = tr, label = "e.two",
                           effort = pol)$text, "at high")
  expect_error(hr_effort_event(tr, c("a", "b")), class = "gr_bad_setting")
})

test_that("effort_mode is off by default and leaves a default spec alone", {
  sp <- gr_read_spec("map_reduce")
  expect_null(sp$effort)
  expect_null(sp$effort_mode)
  on <- gr_read_spec("map_reduce", effort_mode = "escalate")
  expect_s3_class(on$effort, "hr_effort_escalate")
  expect_identical(on$effort$base, "low")
  expect_identical(on$effort_mode, "escalate")
  on2 <- gr_read_spec("map_reduce", effort = c(map = "minimal", reduce = "medium"),
                      effort_mode = "escalate")
  expect_identical(on2$effort$base, c(map = "minimal", reduce = "medium"))
  # Rebuilt from its own fields, a spec keeps the policy it had.
  again <- as_read_spec(unclass(on2))
  expect_identical(again$effort$base, on2$effort$base)
  # A segmenter is handed the base effort.
  seg <- segment_effort(gr_segment_spec(method = "contextual"), on)
  expect_false(inherits(seg$effort, "hr_effort_escalate"))
})

test_that("under effort_mode = 'escalate' a read raises the stage after a trigger", {
  ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 200))
  n <- 0
  cl <- hr_mock_client(function(m, p) {
    n <<- n + 1
    if (n == 1) "NOT_IN_DOCUMENT" else paste("Revenue at", p$effort)
  })
  tr <- hr_trace()
  quiet(gr_read(ch, "What was revenue?", cl,
                gr_read_spec("refine", model = ee_model, effort_mode = "escalate"), trace = tr))
  ef <- ee_efforts(tr)
  expect_identical(ef$effort[ef$stage == "refine.draft"], "low")
  expect_true(all(ef$effort[ef$stage == "refine.revise"] == "high"))
  log <- hr_effort_log(tr)
  expect_identical(log$triggers, "not_in_document")
  expect_true(log$resolved)
  # Static: the same read at one effort throughout.
  n <- 0
  tr2 <- hr_trace()
  quiet(gr_read(ch, "What was revenue?", cl, gr_read_spec("refine", model = ee_model,
                                                          effort = "low"), trace = tr2))
  expect_true(all(ee_efforts(tr2)$effort == "low"))
  expect_identical(nrow(hr_effort_log(tr2)), 0L)
})

test_that("ensemble members that disagree raise the adjudication", {
  ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 120))
  cl <- hr_mock_client(function(m, p) {
    sys <- m[[1]]$content
    if (grepl("different reading strategies", sys, fixed = TRUE)) return(paste("adj", p$effort))
    if (grepl("<excerpts>", m[[2]]$content, fixed = TRUE) &&
        grepl("revenue", m[[2]]$content, ignore.case = TRUE)) {
      return("Revenue was 45.2 million dollars.")
    }
    if (grepl("consolidate", sys)) return("Revenue was about 45 million.")
    "NOT_IN_DOCUMENT"
  })
  tr <- hr_trace()
  a <- quiet(gr_read(ch, "What was revenue?", cl,
                     gr_read_spec("ensemble", model = ee_model, effort_mode = "escalate"),
                     trace = tr))
  expect_length(ee_steps(tr, "effort.event"), 1L)
  ef <- ee_efforts(tr)
  expect_identical(unique(ef$effort[ef$stage == "ensemble.adjudicate"]), "high")
})

test_that("effort_mode is swept as recipe arms", {
  arms <- hr_sweep(gr_arm("thorough"), list(effort_mode = c("static", "escalate")))
  expect_length(arms, 2L)
})

ee_bench <- function() {
  ref <- hr_reference(sprintf("q%02d", 1:40), labels = rep("yes", 40),
                      cluster = sprintf("c%02d", rep(1:20, each = 2)), split = "test")
  arm_at <- function(name, effort) {
    hr_arm(name, function(item, ctx) {
      hr_call(ctx$client, paste("first", item), model = ee_model, trace = ctx$trace,
              label = "task.draft", effort = effort)
      hr_call(ctx$client, paste("final", item), model = ee_model, trace = ctx$trace,
              label = "task.final", effort = effort)$text
    })
  }
  cl <- hr_mock_client(function(m, p) {
    hard <- grepl("q0[1-4]", m[[1]]$content)
    if (grepl("first", m[[1]]$content) && hard) {
      return(gr_result(TRUE, "cut", finish_reason = "length"))
    }
    if (hard && identical(p$effort, "low")) "no" else "yes"
  })
  arms <- list(arm_at("low", "low"), arm_at("high", "high"),
               arm_at("escalate", hr_effort_escalate()))
  quiet(hr_benchmark(arms, ref, runs = 5, client = cl,
                     governor = hr_governor(max_calls = 2000, max_cost_usd = 10)))
}

test_that("hr_effort_check() tests the policy against fixed levels, with Holm and cost", {
  bench <- ee_bench()
  chk <- hr_effort_check(bench, "escalate", margin = 0.05, cost_test = FALSE, B = 200)
  expect_s3_class(chk, "hr_effort_check")
  expect_true(chk$post_hoc)
  expect_setequal(chk$contrasts$reference, c("low", "high"))
  expect_true(all(chk$contrasts$label == "post hoc"))
  # Holm over the two: the smaller p-value is tested at alpha / 2.
  lv <- sort(chk$contrasts$level)
  expect_equal(lv, c(0.0125, 0.025))
  expect_identical(chk$best_fixed, "high")
  ct <- chk$cost
  esc <- ct[ct$arm == "escalate", ]
  expect_equal(esc$escalations, 0.1)          # 4 of 40 items raise once
  expect_equal(esc$escalated_calls, 0.1)
  expect_equal(esc$resolved, 1)
  expect_equal(ct$escalations[ct$arm == "high"], 0)
  expect_equal(esc$accuracy, ct$accuracy[ct$arm == "high"])
  expect_gt(esc$accuracy, ct$accuracy[ct$arm == "low"])
  expect_equal(esc$calls, 2)
  expect_output(print(chk), "post hoc")
  expect_error(hr_effort_check(bench, "nope"), class = "gr_bad_setting")
  expect_error(hr_effort_check(bench, "escalate", comparators = "escalate"),
               class = "gr_bad_setting")
  expect_error(hr_effort_check(bench, "escalate", margin = 2), class = "gr_bad_setting")
})

test_that("hr_effort_check() gives NA for an arm's cost when a run's price is unknown", {
  df <- data.frame(arm = c("a", "a", "b", "b", "c"), correct = TRUE,
                   usd = c(1e-4, NA, NA, NA, 2e-4), priced = c(TRUE, FALSE, FALSE, FALSE, TRUE),
                   as_of = c("2026-11", NA, NA, NA, "2026-11"), certain = TRUE,
                   stringsAsFactors = FALSE)
  ct <- harnessr:::effort_costs(df)
  # One run of a has no price: the mean of the priced run alone is not a's.
  expect_identical(ct$usd[ct$arm == "a"], NA_real_)
  # No run of b has a price: NA, never NaN.
  expect_identical(ct$usd[ct$arm == "b"], NA_real_)
  expect_false(any(is.nan(ct$usd)))
  expect_equal(ct$usd[ct$arm == "c"], 2e-4)
  expect_identical(ct$priced, c(FALSE, FALSE, TRUE))

  bench <- ee_bench()
  bench$usd[bench$arm == "low"] <- NA_real_
  bench$priced[bench$arm == "low"] <- FALSE
  chk <- hr_effort_check(bench, "escalate", margin = 0.05, cost_test = FALSE, B = 200)
  expect_identical(chk$cost$usd[chk$cost$arm == "low"], NA_real_)
  out <- capture.output(print(chk))
  expect_true(any(grepl("usd is NA for low: no price set for a model of that arm", out,
                        fixed = TRUE)))
  expect_true(any(grepl("hr_load_models()", out, fixed = TRUE)))
})
