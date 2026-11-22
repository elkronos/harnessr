# test-context-policy.R: hr_truncate(), hr_context_policy() and
# hr_context_fit(), and the read settings that use them: context_policy,
# refine_state, restate = "window" and context_order in merges. Each is off by
# default, so a default spec sends what it sent before; the golden records
# check that. These tests check what each does when it is on.

cp_chunks <- function(txt) {
  new_chunks(txt, "precomputed", gr_segment_spec(max_tokens = max(gr_count_tokens(txt), 32L)))
}

cp_truncates <- function(tr) {
  Filter(function(s) identical(s$label, "truncate") && identical(s$kind, "local"), tr$steps)
}

cp_paras <- paste("Paragraph", 1:8, "reports a figure for one of the regions.",
                  collapse = "\n\n")

# --- hr_truncate -------------------------------------------------------------

test_that("hr_truncate() keeps the head by default, exactly as gr_truncate_tokens()", {
  texts <- c(cp_paras, paste(rep("alpha beta gamma", 40), collapse = " "),
             "Arm | N\nA | 482\nB | 479\nC | 470", "short enough", "")
  for (t in texts) for (n in c(0, 1, 3, 8, 20, 200)) {
    expect_identical(hr_truncate(t, n), gr_truncate_tokens(t, n), info = paste(n, t))
    expect_identical(hr_truncate(t, n, keep = "head", marker = ""),
                     gr_truncate_tokens(t, n, marker = ""))
  }
})

test_that("tail, both and scored keep the part asked for and stay within n", {
  tail <- hr_truncate(cp_paras, 30, keep = "tail")
  expect_match(tail, "Paragraph 8", fixed = TRUE)
  expect_false(grepl("Paragraph 1 ", tail, fixed = TRUE))
  expect_true(startsWith(tail, "...[truncated]"))
  both <- hr_truncate(cp_paras, 60, keep = "both")
  expect_match(both, "^Paragraph 1")
  expect_match(both, "Paragraph 8", fixed = TRUE)
  expect_match(both, "...[truncated]", fixed = TRUE)
  sc <- hr_truncate(cp_paras, 45, keep = "scored", scores = c(0, 0, 0, 9, 0, 8, 0, 0))
  expect_match(sc, "Paragraph 4.*Paragraph 6")
  expect_false(grepl("Paragraph 1 ", sc, fixed = TRUE))
  for (k in c("tail", "both")) for (n in c(1, 2, 5, 9, 17, 40)) {
    expect_lte(gr_count_tokens(hr_truncate(cp_paras, n, keep = k)), n)
  }
  units <- c("first unit", "second unit", "third unit")
  expect_identical(hr_truncate(units, 100, keep = "scored", scores = 1:3),
                   paste(units, collapse = "\n\n"))
  expect_identical(hr_truncate("fits", 100, keep = "tail"), "fits")
  expect_error(hr_truncate(cp_paras, 10, keep = "scored"), class = "gr_bad_setting")
  expect_error(hr_truncate(cp_paras, 10, keep = "middle"), class = "gr_bad_setting")
})

test_that("tail and both use the whole budget when no marker is used", {
  x <- "aaa bbb ccc ddd eee fff ggg hhh"
  for (n in 4:12) {
    head <- hr_truncate(x, n, marker = "")
    tail <- hr_truncate(x, n, keep = "tail", marker = "")
    both <- hr_truncate(x, n, keep = "both", marker = "")
    # Where the start keeps a word, the end and both ends keep one too.
    if (nzchar(head)) {
      expect_true(nzchar(tail), info = n)
      expect_match(both, "^aaa", info = n)
    }
    expect_true(endsWith(x, tail), info = n)
    expect_false(grepl("^\\s*$", both) && nzchar(both), info = n)
    expect_lte(gr_count_tokens(both), n)
  }
  # Nothing kept is "" and logged as all dropped, not a bare line break.
  tr <- gr_trace()
  expect_identical(hr_truncate(x, 3, keep = "both", marker = "", trace = tr), "")
  expect_identical(cp_truncates(tr)[[1]]$detail$dropped_part, "all")
  cjk <- strrep("\u65e5\u672c\u8a9e\u306e\u30c6\u30ad\u30b9\u30c8", 200)
  expect_true(nzchar(hr_truncate(cjk, 5, keep = "tail")))
  expect_true(nzchar(hr_truncate(cjk, 5, keep = "both")))
  expect_false(identical(hr_truncate(cjk, 5, keep = "both"), "\n"))
})

test_that("scored keeps a unit at every budget where one fits, with or without the marker", {
  u <- paste("Para", 1:6, "says something about revenue.")
  kept <- vapply(6:40, function(n) {
    out <- hr_truncate(u, n, keep = "scored", scores = 6:1)
    expect_lte(gr_count_tokens(out), n)
    sum(vapply(u, function(x) grepl(x, out, fixed = TRUE), TRUE))
  }, numeric(1))
  # The units kept never fall as the budget grows.
  expect_true(all(diff(kept) >= 0))
  one <- min(which(vapply(6:40, function(n) gr_count_tokens(u[1]) <= n, TRUE))) + 5L
  expect_match(hr_truncate(u, one, keep = "scored", scores = 6:1), "^Para 1 ")
  expect_match(hr_truncate(u, 16, keep = "scored", scores = 6:1), "^Para 1 ")
})

test_that("every cut writes a truncate step that names the piece and what was dropped", {
  tr <- gr_trace()
  invisible(hr_truncate(cp_paras, 20, keep = "tail", trace = tr, where = "demo", piece = "notes"))
  invisible(hr_truncate(cp_paras, 20, trace = tr, where = "demo2"))
  invisible(hr_truncate(cp_paras, 45, keep = "scored", scores = 8:1, trace = tr, where = "demo3"))
  invisible(hr_truncate("fits", 50, keep = "tail", trace = tr))
  st <- cp_truncates(tr)
  expect_length(st, 3L)
  expect_identical(st[[1]]$detail$piece, "notes")
  expect_identical(st[[1]]$detail$dropped_part, "start")
  expect_identical(st[[1]]$detail$keep, "tail")
  expect_gt(st[[1]]$detail$tokens_dropped, 0L)
  expect_identical(st[[2]]$detail$dropped_part, "end")
  expect_match(st[[3]]$detail$dropped_part, "^units ")
})

# --- hr_context_policy and hr_context_fit ----------------------------------

test_that("hr_context_policy() checks its rules", {
  p <- hr_context_policy()
  expect_s3_class(p, "hr_context_policy")
  expect_identical(p$pin, c("question", "instructions"))
  expect_output(print(p), "pin:")
  expect_error(hr_context_policy(pin = "draft", cut_order = "draft"), class = "gr_bad_setting")
  expect_error(hr_context_policy(keep = "middle"), class = "gr_bad_setting")
  expect_error(hr_context_policy(keep = c("head", "tail")), class = "gr_bad_setting")
  expect_error(hr_context_policy(order_merges = NA), class = "gr_bad_setting")
})

test_that("hr_context_fit() never cuts a pinned piece and cuts in the order given", {
  pieces <- c(question = "What was revenue?",
              draft = paste(rep("Revenue rose.", 30), collapse = " "),
              excerpt = paste(rep("Costs fell.", 30), collapse = " "))
  tr <- gr_trace()
  fit <- hr_context_fit(pieces, 80, hr_context_policy(pin = c("question", "draft")),
                        trace = tr, where = "t")
  expect_identical(fit$pieces[["draft"]], pieces[["draft"]])
  expect_identical(fit$pieces[["question"]], pieces[["question"]])
  expect_identical(fit$cut, "excerpt")
  expect_false(fit$fits)   # the pinned draft alone is over the budget
  expect_identical(cp_truncates(tr)[[1]]$detail$where, "t.excerpt")
  # Unpinned and unordered pieces go last first; cut_order goes before them.
  fit2 <- hr_context_fit(pieces, 60, hr_context_policy(cut_order = "draft"))
  expect_identical(fit2$cut[1], "draft")
  expect_true(fit2$fits)
  expect_lte(fit2$tokens, 60)
  fit3 <- hr_context_fit(pieces, 60, hr_context_policy())
  expect_identical(fit3$cut[1], "excerpt")
  # Nothing is cut when the pieces fit.
  same <- hr_context_fit(pieces, 1e4, hr_context_policy())
  expect_identical(same$pieces, pieces)
  expect_length(same$cut, 0L)
  expect_error(hr_context_fit(c("a", "b"), 10, hr_context_policy()), class = "gr_bad_setting")
})

# --- the read settings --------------------------------------------------------

test_that("the new read settings are left out of a default spec", {
  sp <- gr_read_spec("refine")
  expect_null(sp$context_policy)
  expect_null(sp$refine_state)
  expect_identical(sp$restate, "auto")
  on <- gr_read_spec("refine", context_policy = list(keep = "tail"), refine_state = "ledger")
  expect_s3_class(on$context_policy, "hr_context_policy")
  expect_identical(on$refine_state, "ledger")
  expect_error(gr_read_spec(context_policy = "tail"), class = "gr_bad_setting")
})

test_that("restate = 'window' warns that no window is measured and uses 50,000 tokens", {
  expect_warning(sp <- gr_read_spec("stuff", restate = "window"), class = "gr_window_unmeasured")
  how <- restate_how(sp)
  expect_identical(as.character(how), "auto")
  expect_identical(attr(how, "tokens"), 50000L)
  expect_false(restate_now(paste(rep("word", 2000), collapse = " "), how))
})

test_that("under a context policy refine fits its draft and excerpt together", {
  long <- paste(rep("Sales rose in the north region this year.", 150), collapse = " ")
  ch <- cp_chunks(c("Revenue was 45.2 million dollars.", long))
  local_registries()
  gr_register_model("cp-small", context_window = 1500, max_output = 200)
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  tr <- gr_trace()
  pol <- hr_context_policy(keep = c(excerpt = "tail", "head"))
  a <- quiet(gr_read(ch, "What was revenue?", cl,
                     gr_read_spec("refine", model = "cp-small", max_answer_tokens = 100,
                                  context_policy = pol), trace = tr))
  st <- cp_truncates(tr)
  expect_gte(length(st), 1L)
  expect_identical(st[[1]]$detail$where, "refine.excerpt")
  expect_identical(st[[1]]$detail$keep, "tail")
  expect_identical(st[[1]]$detail$dropped_part, "start")
  expect_gte(a$notes$truncations, 1L)
  expect_true(a$partial)
  # Without a policy, the same read halves the budget and keeps the head.
  tr0 <- gr_trace()
  quiet(gr_read(ch, "What was revenue?", cl,
                gr_read_spec("refine", model = "cp-small", max_answer_tokens = 100),
                trace = tr0))
  expect_null(cp_truncates(tr0)[[1]]$detail$keep)
})

test_that("a policy whose pinned pieces do not fit warns and refine cuts as without one", {
  local_registries()
  gr_register_model("cp-pin", context_window = 700, max_output = 100, input_usd = 1,
                    output_usd = 1)
  txt <- vapply(1:3, function(i) paste(rep(sprintf("Fact %d about the region.", i), 75),
                                       collapse = " "), "")
  ch <- cp_chunks(txt)
  cl <- gr_mock_client(function(m, p) "An answer.")
  pol <- hr_context_policy(pin = c("question", "instructions", "draft", "excerpt"))
  tr <- gr_trace()
  expect_warning(
    a <- suppressMessages(gr_read(ch, "Q?", cl, gr_read_spec("refine", model = "cp-pin",
                                                       max_answer_tokens = 100,
                                                       context_policy = pol), trace = tr)),
    class = "gr_context_policy_unfit")
  tr0 <- gr_trace()
  b <- quiet(gr_read(ch, "Q?", cl, gr_read_spec("refine", model = "cp-pin",
                                                max_answer_tokens = 100), trace = tr0))
  expect_identical(a$notes$failed_calls, b$notes$failed_calls)
  expect_identical(a$notes$truncations, b$notes$truncations)
  expect_gt(a$notes$truncations, 0L)
  # A pinned piece that a packer has to cut is cut as before, with the warning.
  long <- paste(rep("word", 200), collapse = " ")
  spec <- list(context_policy = hr_context_policy(pin = c("question", "instructions", "outline")))
  tr2 <- gr_trace()
  expect_warning(out <- cut_piece(long, 10, "x", tr2, spec, "outline"),
                 class = "gr_context_policy_unfit")
  expect_identical(out$text, truncate_logged(long, 10, "x")$text)
  # Once per cut site and run.
  expect_no_warning(cut_piece(long, 10, "x", tr2, spec, "outline"))
  expect_no_warning(cut_piece("short", 10, "y", gr_trace(), spec, "outline"))
})

test_that("refine_state = 'ledger' applies edits and answers from the list", {
  ch <- cp_chunks(c("Revenue was 40 million.", "Costs were 12 million.",
                    "Correction: revenue was 45.2 million, not 40 million."))
  seen <- list()
  cl <- gr_mock_client(function(m, p) {
    seen[[length(seen) + 1L]] <<- m
    last <- m[[length(m)]]$content
    excerpt <- if (length(m) >= 4L) m[[4]]$content else ""
    if (grepl("Reply with the edits", last, fixed = TRUE)) {
      if (grepl("Correction", excerpt)) return("REPLACE 1: Revenue was 45.2 million.")
      if (grepl("Costs", excerpt)) return("ADD: Costs were 12 million.\nDROP 9")
      return("ADD: Revenue was 40 million.")
    }
    "Revenue was 45.2 million."
  })
  tr <- gr_trace()
  a <- quiet(gr_read(ch, "What was revenue?", cl, gr_read_spec("refine", refine_state = "ledger"),
                     trace = tr))
  labels <- vapply(Filter(function(s) is.null(s$kind), tr$steps), `[[`, "", "label")
  expect_identical(labels, c("refine.draft", "refine.revise", "refine.revise", "refine.answer"))
  final <- seen[[4]][[2]]$content
  expect_match(final, "1. Revenue was 45.2 million.", fixed = TRUE)
  expect_match(final, "2. Costs were 12 million.", fixed = TRUE)
  expect_false(grepl("40 million", final, fixed = TRUE))
  expect_identical(a$notes$ledger_items, 2L)
  expect_identical(a$answer, "Revenue was 45.2 million.")
  # The edits as the code applies them.
  led <- ledger_apply(c("a", "b", "c"), "REPLACE 2: B\nDROP 3\nADD: d\nREPLACE 7: x\nnoise")
  expect_identical(led, c("a", "B", "d"))
  expect_identical(ledger_from_text(ledger_text(c("x y", "z"))), c("x y", "z"))
  # An empty ledger is not found, with no answering request.
  none <- gr_mock_client(function(m, p) "NONE")
  tr2 <- gr_trace()
  b <- quiet(gr_read(ch, "Who is the chief executive?", none,
                     gr_read_spec("refine", refine_state = "ledger"), trace = tr2))
  expect_true(is_not_found(b$answer))
  expect_false(any(vapply(tr2$steps, function(s) identical(s$label, "refine.answer"), TRUE)))
  # The pre-flight cost counts the answering request.
  st <- list(n_chunks = 3L, tokens = 30)
  expect_equal(cost_refine(st, gr_read_spec("refine", refine_state = "ledger"))$calls, 4)
  expect_equal(cost_refine(st, gr_read_spec("refine"))$calls, 3)
})

test_that("a cut ledger keeps only whole findings", {
  L <- sprintf(paste("The budget of site %d was %d.5 million dollars in the fiscal year",
                     "that ended in June of the following year."), 1:11, 41:51)
  t <- ledger_text(L)
  for (n in c(150, 200, 270, 280, 300)) {
    kept <- ledger_whole(L, gr_truncate_tokens(t, n, ""))
    expect_true(all(kept %in% L), info = n)
    expect_identical(kept, L[seq_along(kept)], info = n)
  }
  for (k in c("tail", "both")) {
    kept <- ledger_whole(L, hr_truncate(t, 200, keep = k, marker = ""))
    expect_true(length(kept) > 0L && all(kept %in% L), info = k)
  }
  # In a read, under the default cut and under a policy, every finding the
  # last request carries is one the ledger was given whole.
  local_registries()
  gr_register_model("cp-led", context_window = 900, max_output = 100)
  ch <- cp_chunks(sprintf("Site %d reported its budget for the year.", 1:4))
  for (pol in list(NULL, hr_context_policy(pin = c("question", "instructions", "excerpt")))) {
    seen <- list()
    cl <- gr_mock_client(function(m, p) {
      seen[[length(seen) + 1L]] <<- m
      if (grepl("Reply with the edits", m[[length(m)]]$content, fixed = TRUE)) {
        return(paste0("ADD: ", L, collapse = "\n"))
      }
      "Done."
    })
    quiet(gr_read(ch, "What were the budgets?", cl,
                  gr_read_spec("refine", model = "cp-led", max_answer_tokens = 100,
                               refine_state = "ledger", context_policy = pol)))
    sent <- unlist(lapply(seen, function(m) {
      body <- vapply(m, function(x) as.character(x$content), "")
      ledger_from_text(paste(body[grepl("^<ledger>|^1\\. ", body)], collapse = "\n"))
    }))
    sent <- sub("\n?</ledger>$", "", sent)
    expect_true(all(sent %in% L), info = if (is.null(pol)) "default" else "policy")
  }
})

test_that("order_merges places findings and members by context_order", {
  ch <- cp_chunks(sprintf("Region %s reported revenue.", c("A", "B", "C", "D")))
  merges <- list()
  cl <- gr_mock_client(function(m, p) {
    if (grepl("consolidate", m[[1]]$content)) {
      merges[[length(merges) + 1L]] <<- m[[2]]$content
      return("Merged.")
    }
    sub(".*(Region [A-D]).*", "\\1 found", m[[2]]$content)
  })
  first_of <- function(body) regmatches(body, gregexpr("Region [A-D]", body))[[1]]
  quiet(gr_read(ch, "Which regions?", cl, gr_read_spec("map_reduce", context_order = "edges")))
  expect_identical(first_of(merges[[1]]), c("Region A", "Region B", "Region C", "Region D"))
  pol <- hr_context_policy(order_merges = TRUE)
  quiet(gr_read(ch, "Which regions?", cl, gr_read_spec("map_reduce", context_order = "edges",
                                                       context_policy = pol)))
  expect_identical(first_of(merges[[2]]), c("Region A", "Region C", "Region D", "Region B"))
  expect_identical(merge_order(4, list(context_policy = pol, context_order = "document")), 1:4)
  expect_identical(merge_order(4, list(context_order = "edges")), 1:4)
})

test_that("under a context policy a chunk packer names the chunks it left out", {
  local_registries()
  gr_register_model("cp-tiny", context_window = 700, max_output = 100)
  txt <- vapply(1:12, function(i) paste(rep(sprintf("Fact %d about the region.", i), 8),
                                        collapse = " "), "")
  ch <- cp_chunks(txt)
  cl <- gr_mock_client(function(m, p) "An answer.")
  tr <- gr_trace()
  quiet(gr_read(ch, "Q?", cl, gr_read_spec("stuff", model = "cp-tiny", max_answer_tokens = 50,
                                           context_policy = hr_context_policy()), trace = tr))
  st <- cp_truncates(tr)
  expect_length(st, 1L)
  expect_identical(st[[1]]$detail$where, "stuff.chunks")
  expect_match(st[[1]]$detail$dropped_part, "^chunks ")
  tr0 <- gr_trace()
  quiet(gr_read(ch, "Q?", cl, gr_read_spec("stuff", model = "cp-tiny", max_answer_tokens = 50),
                trace = tr0))
  expect_length(cp_truncates(tr0), 0L)
})

test_that("context_policy and refine_state are swept as recipe arms", {
  arms <- hr_sweep(gr_arm("thorough", list(reader = "refine")),
                   list(refine_state = c("draft", "ledger")))
  expect_length(arms, 2L)
  arms <- hr_sweep(function(cut) {
    gr_arm("thorough", list(reader = "refine",
                            context_policy = if (cut == "tail") hr_context_policy(keep = "tail")))
  }, list(cut = c("head", "tail")))
  expect_length(arms, 2L)
})
