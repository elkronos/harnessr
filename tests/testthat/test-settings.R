# test-settings.R: declared settings, where their defaults come from, and the
# settings that were constants in the code until they were declared.
#
# Each setting that used to be a constant has a test that a value other than
# its default changes what it controls, and the defaults are checked to leave
# specs, keys and traces as they were.

ns <- asNamespace("harnessr")
# Every option as it was when the test started, put back when it ends.
local_options <- function(env = parent.frame()) {
  old <- gr_options()
  withr::defer(gr_options(old), envir = env)
}
spec_schemas <- function() {
  list(read = ns$.gr_read_schema, segment = ns$.gr_segment_schema,
       ingest = ns$.gr_ingest_schema)
}

# --- evidence and tiers -------------------------------------------------------

test_that("every parameter of every module schema says where its default comes from", {
  for (mod in names(spec_schemas())) {
    for (p in spec_schemas()[[mod]]) {
      ev <- p$evidence
      expect_true(is.list(ev), info = paste(mod, p$name))
      expect_true(ev$status %in% c("measured", "cited", "untested"), info = paste(mod, p$name))
      expect_true(is.character(ev$source) && length(ev$source) == 1L &&
                    nzchar(trimws(ev$source)), info = paste(mod, p$name))
    }
  }
  # And every tuning option.
  for (nm in names(ns$.gr_option_rules)) {
    rule <- ns$.gr_option_rules[[nm]]
    if (!identical(rule$kind, "tune")) next
    expect_true(ns$evidence_ok(rule$evidence), info = nm)
  }
})

test_that("hr_param() refuses evidence that does not say where the value comes from", {
  expect_error(hr_param("x", "integer", default = 1L, evidence = list(status = "tuned")),
               class = "gr_bad_setting")
  expect_error(hr_param("x", "integer", default = 1L,
                        evidence = list(status = "untested", source = "")),
               class = "gr_bad_setting")
  expect_error(hr_param("x", "integer", default = 1L, evidence = "untested"),
               class = "gr_bad_setting")
  p <- hr_param("x", "integer", default = 1L,
                evidence = list(status = "untested", source = "Set by hand."))
  expect_identical(p$evidence$status, "untested")
  out <- capture.output(print(hr_schema(p)))
  expect_match(out[2], "untested", fixed = TRUE)
})

test_that("each module keeps at most five basic parameters", {
  for (mod in names(spec_schemas())) {
    tiers <- vapply(spec_schemas()[[mod]], `[[`, "", "tier")
    expect_lte(sum(tiers == "basic"), 5L)
  }
  basic <- names(Filter(function(p) identical(p$tier, "basic"), ns$.gr_read_schema))
  expect_setequal(basic, c("reader", "model", "top_k", "cite", "verify"))
})

test_that("the help states each default's source, as the schema declares it", {
  md <- ns$schema_sources_md(ns$.gr_read_schema)
  for (p in ns$.gr_read_schema) expect_match(md, paste0("`", p$name, "`"), fixed = TRUE)
  expect_match(md, "`bm25_k1` (default `1.5`, advanced): cited.", fixed = TRUE)
})

# --- defaults leave specs, keys and traces as they were -----------------------

test_that("a default spec carries none of the settings declared later", {
  expect_false(any(ns$.gr_read_late_params %in% names(gr_read_spec())))
  expect_false(any(ns$.gr_segment_late_params %in% names(gr_segment_spec())))
  expect_false("layout_opts" %in% names(gr_ingest_spec()))
  # Given at their default, they are still left out.
  expect_identical(gr_read_spec(max_merge_levels = 6, bm25_b = 0.75), gr_read_spec())
  expect_identical(gr_segment_spec(context_reply_tokens = 90), gr_segment_spec())
  expect_identical(gr_ingest_spec(layout_opts = list()), gr_ingest_spec())
  # Set, they are in the spec and in what it reports as changed.
  sp <- gr_read_spec(bm25_k1 = 1.2, verify = TRUE, accept_near_verbatim = TRUE)
  expect_identical(sp$bm25_k1, 1.2)
  expect_true(sp$accept_near_verbatim)
  expect_identical(ns$read_settings(sp),
                   list(verify = TRUE, accept_near_verbatim = TRUE, bm25_k1 = 1.2))
  expect_identical(gr_segment_spec(proposition_reply_tokens = 500)$proposition_reply_tokens, 500L)
  expect_identical(gr_ingest_spec(layout_opts = list(share = 0.5))$layout_opts,
                   list(share = 0.5))
})

test_that("the new options leave keys and the trace's options alone at their defaults", {
  local_options()
  cl <- gr_mock_client(function(m, p) "x")
  key <- function() ns$cache_key(cl, list(list(role = "user", content = "q")), "m", 100L,
                                 NULL, NULL, NULL, NULL)
  base <- key()
  snap <- ns$config_snapshot()$options
  expect_false(any(ns$.gr_late_options %in% names(snap)))
  gr_options(reasoning_floor = 512)
  expect_false(identical(key(), base))
  expect_identical(ns$config_snapshot()$options$reasoning_floor, 512)
  gr_options(reasoning_floor = 2048)
  expect_identical(key(), base)
  expect_false("reasoning_floor" %in% names(ns$config_snapshot()$options))
})

test_that("a non-default option moves the corpus store key, and the default does not", {
  local_options()
  cl <- gr_mock_client(function(m, p) "x")
  rec <- ns$as_recipe("fast")
  k0 <- ns$corpus_key("some text", "Q?", rec, cl)
  gr_options(near_verbatim_sim = 0.8)
  k1 <- ns$corpus_key("some text", "Q?", rec, cl)
  gr_options(near_verbatim_sim = 0.9)
  expect_false(identical(k0, k1))
  expect_identical(ns$corpus_key("some text", "Q?", rec, cl), k0)
})

# --- options ------------------------------------------------------------------

test_that("auto_max_tokens and auto_room_share move the auto recipe's choice", {
  local_options()
  fast <- list(read = list(max_answer_tokens = 1500L, model = "gpt-5.6-terra"))
  expect_identical(ns$pick_auto_recipe(1000, fast), "fast")
  gr_options(auto_max_tokens = 500)
  expect_identical(ns$pick_auto_recipe(1000, fast), "thorough")
  gr_options(auto_max_tokens = 50000)
  expect_identical(ns$pick_auto_recipe(40000, fast), "fast")
  gr_options(auto_room_share = 0.01)
  expect_identical(ns$pick_auto_recipe(40000, fast), "thorough")
})

test_that("reasoning_floor sets the least cap a reasoning model is sent", {
  local_options()
  info <- list(reasoning = TRUE, max_output = 100000, context_window = 400000)
  expect_identical(ns$reasoning_output_cap(100L, info, 0), 2048L)
  gr_options(reasoning_floor = 512)
  expect_identical(ns$reasoning_output_cap(100L, info, 0), 512L)
  gr_options(reasoning_floor = 0)
  expect_identical(ns$reasoning_output_cap(100L, info, 0), 100L)
  expect_warning(gr_options(reasoning_floor = -1), class = "gr_bad_option")
  expect_identical(gr_options("reasoning_floor"), 0)
})

test_that("output_reserve_share sets the reply room gr_budget() reserves", {
  local_options()
  def <- gr_budget("gpt-5.6-terra")
  gr_options(output_reserve_share = 0.05)
  small <- gr_budget("gpt-5.6-terra")
  expect_lt(small$output, def$output)
  expect_gt(small$input, def$input)
  # An explicit reserve is not touched.
  expect_identical(gr_budget("gpt-5.6-terra", reserve_output = 1000)$output, 1000L)
})

test_that("the near-verbatim thresholds decide the shadow matcher's status", {
  local_options()
  src <- "The company reported total revenue of 45.2 million dollars in the fiscal year 2024."
  q <- "The firm reported total revenue of 45.2 million dollars in the fiscal year 2024."
  expect_identical(ns$match_span(q, src)$status, "near_verbatim")
  gr_options(near_verbatim_sim = 0.99)
  expect_identical(ns$match_span(q, src)$status, "unverified")
  # The short-passage floor applies once the passage counts as short.
  gr_options(near_verbatim_sim = 0.9, near_verbatim_sim_short = 0.99,
             near_verbatim_short_chars = 1000)
  expect_identical(ns$match_span(q, src)$status, "unverified")
  gr_options(near_verbatim_sim_short = 0.95, near_verbatim_short_chars = 40)
  expect_identical(ns$match_span(q, src)$status, "near_verbatim")
})

# --- read spec ----------------------------------------------------------------

mk_chunks <- function(x) ns$new_chunks(x, "test", gr_segment_spec())

test_that("accept_near_verbatim lets a near-verbatim quotation stop the iterative reader", {
  ch <- mk_chunks("The company reported total revenue of 45.2 million dollars in the fiscal year 2024.")
  value <- list(quotes = data.frame(
    chunk_id = 1L, stringsAsFactors = FALSE,
    text = "The firm reported total revenue of 45.2 million dollars in the fiscal year 2024."))
  expect_false(ns$step_quotes(value, ch$chunks, 1L)$verified)
  expect_true(ns$step_quotes(value, ch$chunks, 1L, near = TRUE)$verified)
  # A changed number is never near-verbatim, so it is refused either way.
  value$quotes$text <- sub("45.2", "45.3", value$quotes$text, fixed = TRUE)
  expect_false(ns$step_quotes(value, ch$chunks, 1L, near = TRUE)$verified)
  expect_error(gr_read_spec(accept_near_verbatim = NA), class = "gr_bad_setting")
})

test_that("accept_near_verbatim without verify is refused, naming verify", {
  expect_error(gr_read_spec("iterative", accept_near_verbatim = TRUE),
               "`verify = TRUE`", class = "gr_bad_setting")
  expect_error(gr_read_spec("iterative", verify = FALSE, accept_near_verbatim = TRUE),
               class = "gr_bad_setting")
  # Given as an override of a recipe that does not verify, it is refused too.
  expect_error(quiet(answer_document(gr_example(), "q?", "fast",
                                     client = gr_mock_client(function(m, p) "x"),
                                     accept_near_verbatim = TRUE)),
               "`verify = TRUE`", class = "gr_bad_setting")
  expect_true(gr_read_spec("iterative", verify = TRUE,
                           accept_near_verbatim = TRUE)$accept_near_verbatim)
  # Off, it needs nothing.
  expect_identical(gr_read_spec("iterative", accept_near_verbatim = FALSE),
                   gr_read_spec("iterative"))
})

test_that("with accept_near_verbatim the iterative reader answers, marked partial", {
  ch <- quiet(gr_segment(gr_example(), list(method = "paragraph", max_tokens = 80)))
  cl <- gr_mock_client(function(m, p) {
    if (!grepl("reading iteratively", m[[1]]$content, fixed = TRUE)) return("x")
    as.character(jsonlite::toJSON(list(
      can_answer = TRUE, answer = "Revenue was 45.2 million.", next_query = "",
      quotes = list(list(chunk_id = 2L,
                         text = "reported total revenue of 45.2 million dollars in fiscal 2024"))),
      auto_unbox = TRUE))
  })
  read <- function(acc) {
    quiet(gr_read(ch, "What was revenue in 2024?", cl,
                  gr_read_spec("iterative", verify = TRUE, top_k = 3L,
                               accept_near_verbatim = acc)))
  }
  expect_true(is_not_found(read(FALSE)$answer))
  a <- read(TRUE)
  expect_identical(a$answer, "Revenue was 45.2 million.")
  # The quotation stopped the loop but is still not verified.
  expect_true(a$partial)
  expect_false(a$evidence$verified)
  expect_identical(a$evidence$quote_status, "near_verbatim")
})

test_that("max_merge_levels caps how deep a merge goes", {
  local_registries()
  gr_register_model("merge-ctx", context_window = 1200L, max_output = 200L,
                    input_usd = 0, output_usd = 0)
  cl <- gr_mock_client(function(m, p) paste(rep("merged finding text", 60), collapse = " "))
  pieces <- rep(paste(rep("a finding about revenue", 10), collapse = " "), 200)
  merge <- function(levels) {
    sp <- gr_read_spec("map_reduce", model = "merge-ctx", max_answer_tokens = 100L,
                       max_merge_levels = levels)
    quiet(ns$tree_merge(cl, "Q?", pieces, sp, gr_trace()))
  }
  deep <- merge(6L)
  expect_true(deep$ok)
  expect_gt(deep$levels, 2L)
  capped <- merge(1L)
  expect_false(capped$ok)
  expect_identical(capped$levels, 2L)
  expect_identical(capped$error, "merge depth cap reached")
})

test_that("the pre-flight call bound follows max_merge_levels above and below the default", {
  local_registries()
  local_options()
  gr_options(max_calls = 2000L)
  gr_register_model("merge-bound-ctx", context_window = 900L, max_output = 300L,
                    input_usd = 0, output_usd = 0)
  # Each reply is as long as a finding, so a merge takes two at a time and
  # 512 findings need nine levels.
  piece <- paste(rep("Revenue rose.", 50), collapse = " ")
  cl <- gr_mock_client(function(m, p) piece)
  room <- gr_budget("merge-bound-ctx", reserve_output = 200L,
                    overhead = ns$prompt_overhead("Q?", ns$.gr_prompts$merge_system,
                                                  "never"))$input
  stats <- list(n_chunks = 512L, tokens = 1e5,
                reply_cap = function(model, cap) 200, room = function(...) room)
  default_worst <- ns$merge_tree_worst(512, gr_count_tokens(piece), 200, room)
  for (levels in c(12L, 3L)) {
    sp <- gr_read_spec("map_reduce", model = "merge-bound-ctx", max_answer_tokens = 200L,
                       max_merge_levels = levels)
    tr <- gr_trace()
    m <- quiet(ns$tree_merge(cl, "Q?", rep(piece, 512), sp, tr))
    worst <- ns$merge_tree_worst(512, gr_count_tokens(piece), 200, room, levels = levels)
    expect_gte(worst$calls, tr$calls)
    # The cost functions pass the spec's cap on.
    expect_equal(ns$cost_map_reduce(stats, sp)$calls_max, 512 + worst$calls)
    expect_equal(ns$cost_skim(stats, sp)$calls_max, 512 + worst$calls + 1)
    if (levels == 12L) {
      # Nine levels, more than the default cap lets the bound count.
      expect_true(m$ok)
      expect_identical(m$levels, 9L)
      expect_gt(tr$calls, default_worst$calls)
    } else {
      # Four levels make requests, fewer than the default cap counts.
      expect_identical(m$error, "merge depth cap reached")
      expect_lt(worst$calls, default_worst$calls)
    }
  }
})

test_that("a NULL override of a setting held only when not default names the default", {
  r <- ns$as_recipe("fast")
  msg <- function(nm) {
    tryCatch(ns$apply_overrides(r, stats::setNames(list(NULL), nm)),
             gr_bad_override = function(e) conditionMessage(e))
  }
  expect_match(msg("restate_tokens"), "recipe's value (the default, 1200)", fixed = TRUE)
  expect_match(msg("max_merge_levels"), "recipe's value (the default, 6)", fixed = TRUE)
  expect_match(msg("context_reply_tokens"), "recipe's value (the default, 90)", fixed = TRUE)
  expect_match(msg("layout_opts"), "recipe's value (the default, list())", fixed = TRUE)
  # A setting the recipe holds is named as it is.
  expect_match(msg("top_k"), "recipe's value (6)", fixed = TRUE)
  set <- ns$apply_overrides(r, list(max_merge_levels = 9L))
  expect_error(ns$apply_overrides(set, list(max_merge_levels = NULL)),
               "recipe's value (9)", fixed = TRUE, class = "gr_bad_override")
  expect_error(answer_document(gr_example(), "q?", "fast",
                               client = gr_mock_client(function(m, p) "x"),
                               restate_tokens = NULL),
               "(the default, 1200)", fixed = TRUE, class = "gr_bad_override")
})

test_that("restate_tokens sets the body length that brings the question forward", {
  sent <- NULL
  cl <- gr_mock_client(function(m, p) { sent <<- m; "Revenue was 45.2 million." })
  ch <- mk_chunks("Revenue was 45.2 million dollars in 2024.")
  # The excerpts are the second message; the question always comes last.
  quiet(gr_read(ch, "What was revenue?", cl, gr_read_spec("stuff")))
  expect_true(startsWith(sent[[2]]$content, "<excerpts>"))
  quiet(gr_read(ch, "What was revenue?", cl, gr_read_spec("stuff", restate_tokens = 2)))
  expect_true(startsWith(sent[[2]]$content, "Question: What was revenue?"))
  expect_true(ns$restate_now("a b c", ns$restate_how(list(restate = "auto",
                                                          restate_tokens = 1))))
  expect_false(ns$restate_now("a b c", ns$restate_how(list(restate = "never",
                                                           restate_tokens = 1))))
})

test_that("bm25_b changes which chunk rerank's prefilter puts forward", {
  ch <- mk_chunks(c("Revenue was reported.",
                    paste("Staff rose over the long period with other words about revenue and",
                          "revenue again here and more words."),
                    "Costs fell."))
  scored <- character(0)
  cl <- gr_mock_client(function(m, p) {
    if (identical(p$schema_name, "relevance")) {
      scored <<- c(scored, m[[3]]$content)
      return('{"score": 8, "reason": "r"}')
    }
    "Answer."
  })
  quiet(gr_read(ch, "revenue?", cl, gr_read_spec("rerank", rerank_candidates = 1)))
  expect_match(scored, "Revenue was reported.", fixed = TRUE)
  scored <- character(0)
  # No length normalisation: the chunk that says it twice wins.
  quiet(gr_read(ch, "revenue?", cl, gr_read_spec("rerank", rerank_candidates = 1, bm25_b = 0)))
  expect_match(scored, "Staff rose", fixed = TRUE)
  # k1 changes the scores themselves.
  expect_false(isTRUE(all.equal(ns$bm25_scores(ch$chunks$text, "revenue", k1 = 1.5),
                                ns$bm25_scores(ch$chunks$text, "revenue", k1 = 0.5))))
})

test_that("lexical_blend weighs cosine against BM25 in an offline retrieve", {
  local_options()
  gr_options(embedder = "lexical")
  cl <- gr_mock_client(function(m, p) "Answer.")
  ch <- mk_chunks(c("beta beta beta beta beta", "alpha gamma delta epsilon", "beta iota kappa"))
  pick <- function(w) {
    quiet(gr_read(ch, "alpha beta", cl,
                  gr_read_spec("retrieve", top_k = 1, lexical_blend = w)))$evidence$chunk_id
  }
  expect_identical(pick(1), 1L)
  expect_identical(pick(0), 2L)
})

# --- segment spec -------------------------------------------------------------

test_that("the contextual and proposition caps reach the requests", {
  doc <- quiet(gr_ingest(paste(rep("Revenue rose in 2024 and costs fell over the same period.",
                                   400), collapse = " ")))
  caps <- integer(0)
  docs <- character(0)
  cl <- gr_mock_client(function(m, p) {
    caps <<- c(caps, as.integer(p$max_output))
    if (!is.null(p$schema)) return('{"propositions": ["Revenue rose in 2024."]}')
    docs <<- c(docs, m[[2]]$content)
    "Part of a report on revenue."
  })
  seg <- function(...) quiet(gr_segment(doc, gr_segment_spec("contextual", max_tokens = 400,
                                                             context_source = "llm", ...),
                                        client = cl))
  seg()
  expect_true(all(caps == 90L))
  long <- max(nchar(docs))
  caps <- integer(0); docs <- character(0)
  seg(context_reply_tokens = 40, context_document_tokens = 200)
  expect_true(all(caps == 40L))
  expect_lt(max(nchar(docs)), long)

  small <- quiet(gr_ingest("Revenue rose in 2024. Costs fell in 2024."))
  caps <- integer(0)
  quiet(gr_segment(small, gr_segment_spec("proposition"), client = cl))
  expect_identical(unique(caps), 2000L)
  caps <- integer(0)
  quiet(gr_segment(small, gr_segment_spec("proposition", proposition_reply_tokens = 300),
                   client = cl))
  expect_identical(unique(caps), 300L)
})

# --- ingest spec --------------------------------------------------------------

test_that("references_after sets where a bibliography heading may end the text", {
  body <- paste(sprintf("Body line %d of the paper.", 1:6), collapse = "\n")
  tail <- paste(sprintf("Later line %d of the paper.", 1:14), collapse = "\n")
  x <- paste(body, "References", tail, sep = "\n")
  # The heading starts about 30% in: before 40%, so it is kept by default.
  expect_identical(as.character(gr_clean(x, steps = "references")), x)
  cut <- gr_clean(x, steps = "references", opts = list(references_after = 0.2))
  expect_false(grepl("References", cut, fixed = TRUE))
  expect_match(cut, "Body line 6", fixed = TRUE)
  expect_warning(gr_clean(x, steps = "references", opts = list(references_after = 2)),
                 class = "gr_clamped")
  # Through the ingest spec.
  doc <- quiet(gr_ingest(x, gr_ingest_spec(clean = "references",
                                           cleaner_opts = list(references_after = 0.2))))
  expect_false(grepl("Later line", doc$text, fixed = TRUE))
})

test_that("the references cleaner cuts at a Markdown heading", {
  body <- paste(sprintf("Body line %d of the paper.", 1:10), collapse = "\n")
  refs <- "[1] First source.\n[2] Second source."
  for (h in c("## References", "# Bibliography", "### 7. References",
              "## References ##", "  ## Works cited")) {
    out <- as.character(gr_clean(paste(body, h, refs, sep = "\n"), steps = "references"))
    expect_false(grepl("First source", out, fixed = TRUE), info = h)
    expect_match(out, "Body line 10", fixed = TRUE)
  }
  # Not a heading: a # mark with no space, closing marks with no space, more
  # than six marks, and a heading with words after the keyword.
  for (h in c("#References", "## References#", "####### References",
              "## References and notes")) {
    x <- paste(body, h, refs, sep = "\n")
    expect_identical(as.character(gr_clean(x, steps = "references")), x, info = h)
  }
  # The share rule still applies: a heading before 40% is kept.
  early <- paste("## References", body, sep = "\n")
  expect_identical(as.character(gr_clean(early, steps = "references")), early)
  # A "# references" comment in a fenced code block is code, not a heading.
  long <- paste(rep("Body sentence about results and methods here.", 40), collapse = "\n")
  for (fence in c("```", "~~~")) {
    code <- paste0(long, "\n", fence, "\n# references\nx <- 1\n", fence, "\n", refs)
    expect_identical(as.character(gr_clean(code, steps = "references")), code, info = fence)
    after <- paste0(code, "\n## References\n[3] Third source.")
    cut <- as.character(gr_clean(after, steps = "references"))
    expect_match(cut, "x <- 1", fixed = TRUE)
    expect_false(grepl("Third source", cut, fixed = TRUE))
  }
  # A fence that never closes is not taken as one.
  open_fence <- paste(body, "```", "## References", refs, sep = "\n")
  expect_false(grepl("First source", as.character(gr_clean(open_fence, steps = "references")),
                     fixed = TRUE))
  # The example report ends with "## References": the academic preset now
  # cuts its reference list and the standard preset does not.
  ex <- quiet(gr_ingest(gr_example(), gr_ingest_spec(clean = "academic")))
  expect_false(grepl("Northwind Instruments, Annual Report 2023", ex$text, fixed = TRUE))
  st <- quiet(gr_ingest(gr_example(), gr_ingest_spec(clean = "standard")))
  expect_match(st$text, "Northwind Instruments, Annual Report 2023", fixed = TRUE)
})

test_that("layout_opts is checked and changes which running lines are dropped", {
  expect_error(gr_ingest_spec(layout_opts = list(deep = 3)), class = "gr_bad_setting")
  expect_warning(sp <- gr_ingest_spec(layout_opts = list(share = 2)), class = "gr_clamped")
  expect_identical(sp$layout_opts$share, 1)
  pages <- lapply(1:4, function(pg) c("Journal of Learning Studies, vol. 12",
                                      sprintf("Body %d.%d of the page text here.", pg, 1:5)))
  dropped <- ns$drop_running_lines(pages)
  expect_false(any(grepl("Journal", unlist(dropped))))
  kept <- do.call(ns$drop_running_lines, c(list(pages), list(min_pages = 10L)))
  expect_true(any(grepl("Journal", unlist(kept))))
})

test_that("gr_compare()'s settings column names layout_opts and cleaner_opts entries", {
  local_options()
  gr_options(embedder = "lexical")
  rd <- gr_read_spec(reader = "retrieve")
  recipes <- list(
    a = gr_recipe(read = rd),
    d = gr_recipe(read = rd, ingest = gr_ingest_spec(layout_opts = list(depth = 3))),
    r = gr_recipe(read = rd, ingest = gr_ingest_spec(clean = "academic",
                                                     cleaner_opts = list(references_after = 0.5))))
  cmp <- quiet(gr_compare(gr_example(), "What was revenue?", recipes,
                          client = gr_mock_client(function(m, p) "It rose.")))
  expect_identical(cmp$summary$settings,
                   c("", "layout_opts.depth=3", "cleaner_opts.references_after=0.5"))
})

# --- synthesis ----------------------------------------------------------------

synth_client <- function(sentence) {
  gr_mock_client(function(messages, params) {
    seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
                  collapse = " ")
    if (grepl("<studies>", seen, fixed = TRUE)) sentence
    else '{"design":"randomised trial","n":120,
           "design__quote":"We ran a randomised trial.",
           "n__quote":"We enrolled 120 people."}'
  })
}

test_that("figure_bands sets how near a qualified figure must be", {
  fields <- gr_fields(design = "The study design",
                      n = gr_field("Participants", type = "integer"))
  cl <- synth_client("One randomised trial of about 140 people [study 1].")
  f <- withr::local_tempfile(fileext = ".txt")
  writeLines("We ran a randomised trial. We enrolled 120 people.", f)
  x <- quiet(gr_extract(f, fields, client = cl))
  run <- function(...) quiet(gr_synthesise(x, question = "Does it work?",
                                           outline = c("Included studies" = "How many"),
                                           client = cl, ...))
  fig <- function(s) s$figures[s$figures$number == "140", ]
  expect_false(fig(run())$backed)
  wide <- fig(run(figure_bands = c(about = 0.2)))
  expect_true(wide$backed)
  expect_identical(wide$basis, "approximate")
  expect_error(run(figure_bands = c(near = 0.2)), class = "gr_bad_setting")
})

claims_frame <- function(n) {
  data.frame(claim_id = seq_len(n), claim = sprintf("Claim %d.", seq_len(n)),
             n_support = rev(seq_len(n)), n_contradict = 0L, moderator = NA_character_,
             scope = NA_character_, stringsAsFactors = FALSE)
}

test_that("prominence sets how many claims get each sentence budget", {
  cw <- claims_frame(6)
  support <- data.frame(claim_id = 1:6, study = 1:6, role = "supports", stringsAsFactors = FALSE)
  w <- stats::setNames(rep(1, 6), 1:6)
  tiers <- function(...) {
    b <- ns$render_claims(cw, support, w, collapse = FALSE, ...)
    sub("^\\[claim [0-9]+\\] \\(([^)]*)\\).*", "\\1", b)
  }
  expect_identical(table(tiers())[c("two or three sentences", "one or two sentences",
                                    "one sentence")],
                   table(rep(c("two or three sentences", "one or two sentences",
                               "one sentence"), each = 2))[c("two or three sentences",
                                                             "one or two sentences",
                                                             "one sentence")])
  half <- tiers(prominence = c(top = 0.5, middle = 0.5))
  expect_identical(sum(half == "two or three sentences"), 3L)
  expect_identical(sum(half == "one or two sentences"), 3L)
  # Thirds, given explicitly, are the default.
  expect_identical(tiers(prominence = c(top = 1/3, middle = 1/3)), tiers())
  expect_error(ns$check_prominence(c(0.8, 0.8)), class = "gr_bad_setting")
})

test_that("study_weights changes which claims rank first", {
  cw <- claims_frame(2)
  cw$n_support <- 1L
  support <- data.frame(claim_id = 1:2, study = 1:2, role = "supports", stringsAsFactors = FALSE)
  used <- data.frame(study = 1:2, n = c(900, 20), n_filled = 2, n_unverified = 0)
  expect_identical(ns$claim_order(cw, support, ns$study_weight(used)), 1:2)
  flip <- ns$user_study_weights(function(u) ifelse(u$n < 100, 2, 1), used)
  expect_identical(ns$claim_order(cw, support, flip), 2:1)
  expect_error(ns$user_study_weights(function(u) -1, used), class = "gr_bad_setting")
})

test_that("coherence_rounds lets a pass revise its own revision", {
  draft <- paste0("## Findings\n\nTwo small trials may suggest a modest benefit [study 1] ",
                  "[study 2]. One cohort could show harm [study 3].")
  calls <- 0L
  cl <- gr_mock_client(function(m, p) {
    calls <<- calls + 1L
    d <- sub("^<draft>\n", "", sub("\n</draft>$", "", m[[3]]$content))
    if (grepl("modest", d, fixed = TRUE)) return(sub("modest", "slight", d, fixed = TRUE))
    if (grepl("slight", d, fixed = TRUE)) return(sub("slight", "small", d, fixed = TRUE))
    d
  })
  sp <- gr_read_spec("stuff", model = "mock-model")
  one <- quiet(ns$synth_revise(draft, "Q?", cl, sp, gr_trace(), passes = "register"))
  expect_identical(calls, 1L)
  expect_identical(one$report$round, 1L)
  expect_match(one$text, "slight benefit", fixed = TRUE)
  calls <- 0L
  more <- quiet(ns$synth_revise(draft, "Q?", cl, sp, gr_trace(), passes = "register",
                                rounds = 5L))
  # The third round gave the text back unchanged, so the pass stopped there.
  expect_identical(calls, 3L)
  expect_identical(more$report$round, 1:3)
  expect_match(more$text, "small benefit", fixed = TRUE)
})

# --- calibration and reports --------------------------------------------------

test_that("max_width sets when a one-stratum sample is adequate", {
  scr <- structure(list(table = data.frame(document = sprintf("d%04d.pdf", 1:500),
                                           decision = c(rep("exclude", 480),
                                                        rep("include", 20)),
                                           reason = "r", stringsAsFactors = FALSE)),
                   class = "gr_screening")
  ex <- gr_reference(scr, n = 20, of = "excluded", seed = 1)
  ex$human_decision <- "exclude"
  expect_false(gr_calibrate(scr, ex)$adequate)
  wide <- gr_calibrate(scr, ex, max_width = 0.5)
  expect_true(wide$adequate)
  expect_identical(wide$adequacy$bar, 0.5)
  expect_error(gr_calibrate(scr, ex, max_width = 0), class = "gr_bad_setting")
})

test_that("hr_report's min_runs and auto_bootstrap_at move its method", {
  set.seed(3)
  b <- do.call(rbind, lapply(1:12, function(c) {
    expand.grid(cluster = sprintf("c%02d", c), item = sprintf("q%02d_%d", c, 1:3), arm = "a",
                run = 1:3, stringsAsFactors = FALSE)
  }))
  b$correct <- stats::runif(nrow(b)) < 0.7
  expect_true(hr_report(b, B = 100)$descriptive)
  r <- hr_report(b, B = 100, min_runs = 3L)
  expect_false(r$descriptive)
  expect_identical(r$method, "cluster_t")
  r <- hr_report(b, B = 100, min_runs = 3L, auto_bootstrap_at = c(items = 30, clusters = 10))
  expect_identical(r$method, "bootstrap")
  expect_match(r$method_reason, "30 items and 10 clusters", fixed = TRUE)
  expect_error(hr_report(b, min_runs = 1), class = "gr_bad_setting")
})

test_that("hr_calibrate_signal's minimums are settable and recorded", {
  key <- list(served_model = "mock-model-2026-01-01", version = "2026-01-01", task = "qa",
              format = "md", prompt_hash = "p1", effort = NA, module = "iterative")
  g <- data.frame(score = rep(c(0.9, 0.1), 10), correct = rep(c(TRUE, FALSE), 10),
                  answerable = rep(c(TRUE, FALSE), c(15, 5)))
  def <- hr_calibrate_signal("demo", g, key, method = "none", seed = 1, B = 0)
  expect_true(any(grepl("fewer than the 100", def$reasons, fixed = TRUE)))
  low <- hr_calibrate_signal("demo", g, key, method = "none", seed = 1, B = 0, min_errors = 5)
  expect_false(any(grepl("wrong items", low$reasons, fixed = TRUE)))
  expect_true(any(grepl("min_errors was set to 5 (default 100)", low$notes, fixed = TRUE)))
  expect_error(hr_calibrate_signal("demo", g, key, method = "isotonic", seed = 1, B = 0),
               class = "hr_bad_calibration")
  iso <- hr_calibrate_signal("demo", g, key, method = "isotonic", seed = 1, B = 0,
                             isotonic_min_items = 10)
  expect_identical(iso$method, "isotonic")
})

test_that("a run's trace records the ingest settings it used", {
  cl <- gr_mock_client(function(m, p) "x")
  a <- quiet(answer_document(gr_example(), "q?", "fast", client = cl,
                             layout_opts = list(depth = 4)))
  ing <- Filter(function(s) identical(s$label, "ingest"), a$trace$steps)
  expect_length(ing, 1L)
  expect_equal(ing[[1]]$detail$settings, list(layout_opts.depth = 4))
  # At the defaults the ingest step carries no settings.
  b <- quiet(answer_document(gr_example(), "q?", "fast", client = cl))
  ing <- Filter(function(s) identical(s$label, "ingest"), b$trace$steps)
  expect_null(ing[[1]]$detail$settings)
})

test_that("gr_settings returns each module's schema, and as.data.frame shows its sources", {
  for (mod in names(spec_schemas())) {
    expect_identical(gr_settings(mod), spec_schemas()[[mod]])
  }
  expect_identical(gr_settings(), spec_schemas()$read)
  expect_error(gr_settings("screen"))
  d <- as.data.frame(gr_settings("read"))
  expect_identical(names(d), c("name", "type", "default", "range", "tier", "status",
                               "source", "help"))
  expect_identical(d$name, names(spec_schemas()$read))
  row <- d[d$name == "bm25_k1", ]
  expect_identical(row$default, "1.5")
  expect_identical(row$range, "[0, 10]")
  expect_identical(row$status, "cited")
  expect_match(row$source, "Robertson and Zaragoza")
  # An enum's default is its first choice; a bound set by another parameter is f().
  seg <- as.data.frame(gr_settings("segment"))
  expect_identical(seg$default[seg$name == "context_source"], "metadata")
  expect_identical(seg$range[seg$name == "overlap_tokens"], "[0, f()]")
  # A parameter with no evidence declared reads NA, not an error.
  bare <- as.data.frame(hr_schema(hr_param("k", "integer", default = 3L)))
  expect_true(is.na(bare$status) && is.na(bare$source))
  expect_identical(bare$default, "3")
})
