# test-synth-context.R: gr_synthesise()'s context_policy and context_order.
# Both are off by default, so a default write-up sends what it sent before;
# the golden records check that. These tests check what each does when set.

sc_table <- function(n = 4L) {
  data.frame(document = sprintf("d%02d.pdf", seq_len(n)), document_id = sprintf("h%02d", seq_len(n)),
             status = "ok", duplicate_of = NA_character_, n_filled = 2L, n_unverified = 0L,
             conflicts = NA_character_, design = "trial", stringsAsFactors = FALSE)
}

sc_claim <- function(text, ids) {
  sprintf(paste0('{"claim":"%s","kind":"finding","supported_by":[%s],"contradicted_by":[],',
                 '"moderator":null,"scope":null}'), text, paste(ids, collapse = ","))
}

# Claim 1 rests on one study, claim 4 on four, so by rank (the sign test)
# claim 4 comes first and claim 1 last. Every section prompt is kept.
sc_client <- function(env) {
  env$seen <- list()
  hr_mock_client(function(messages, params) {
    sys <- messages[[1]]$content
    if (grepl("turn a table of studies", sys, fixed = TRUE)) {
      return(sprintf('{"claims":[%s,%s,%s,%s]}', sc_claim("Claim one.", 1),
                     sc_claim("Claim two.", 1:2), sc_claim("Claim three.", 1:3),
                     sc_claim("Claim four.", 1:4)))
    }
    if (grepl("Group the ones", sys, fixed = TRUE)) return('{"groups":[]}')
    env$seen[[length(env$seen) + 1L]] <- messages
    "All four [study 1] [study 2] [study 3] [study 4]."
  })
}

sc_claim_order <- function(msgs) {
  txt <- paste(vapply(msgs, function(m) as.character(m$content), ""), collapse = "\n")
  as.integer(regmatches(txt, gregexpr("(?<=\\[claim )[0-9]+(?=\\])", txt, perl = TRUE))[[1]])
}

test_that("context_order places a section's claims and keeps each claim's sentence budget", {
  env <- new.env()
  cl <- sc_client(env)
  cm <- quiet(gr_claims(sc_table(), question = "Q?", client = cl))
  o <- c(Findings = "what was found")
  attr(o, "claims") <- data.frame(section = "Findings", claim_id = 1:4)
  run <- function(...) {
    env$seen <- list()
    quiet(gr_synthesise(sc_table(), outline = o, question = "Q?", client = cl, claims = cm, ...))
    env$seen[[1]]
  }
  rel <- run()
  expect_identical(sc_claim_order(rel), c(4L, 3L, 2L, 1L))
  expect_identical(run(context_order = "relevance"), rel)
  expect_identical(sc_claim_order(run(context_order = "document")), 1:4)
  edges <- run(context_order = "edges")
  expect_identical(sc_claim_order(edges), c(4L, 2L, 1L, 3L))
  txt <- paste(vapply(edges, function(m) as.character(m$content), ""), collapse = "\n")
  expect_match(txt, "[claim 4] (two or three sentences)", fixed = TRUE)
  expect_match(txt, "[claim 3] (one or two sentences)", fixed = TRUE)
  expect_match(txt, "[claim 1] (one sentence)", fixed = TRUE)
  expect_error(gr_synthesise(sc_table(), outline = o, question = "Q?", client = cl, claims = cm,
                             context_order = "middle"))
  expect_error(gr_synthesise(sc_table(), outline = o, question = "Q?", client = cl, claims = cm,
                             context_policy = "tail"), class = "gr_bad_setting")
})

test_that("under a policy the gaps cut lists the lines left out and says not to count", {
  local_registries()
  hr_register_model("sc-small", context_window = 3000L, max_output = 400L,
                    input_usd = 0, output_usd = 0)
  env <- new.env()
  cl <- sc_client(env)
  cm <- quiet(gr_claims(sc_table(), question = "Q?", client = cl))
  o <- c(Findings = "what was found", "What is missing" = "the gaps")
  attr(o, "claims") <- data.frame(section = "Findings", claim_id = 1:4)
  attr(o, "closing") <- "What is missing"
  g <- data.frame(kind = "combination unstudied", dimension = "design x setting",
                  detail = sprintf("design = 'trial' with setting = 'site %d'", 1:300))
  pol <- hr_context_policy(overflow = "stubs", stub_tokens = 120,
                           disclose_subset = "{shown} of {total} gaps shown; do not state totals.")
  w <- character(0)
  s <- withCallingHandlers(
    suppressMessages(gr_synthesise(sc_table(), outline = o, question = "Q?", client = cl,
                                   claims = cm, gaps = g, model = "sc-small",
                                   max_section_tokens = 300, context_policy = pol)),
    warning = function(c) { w <<- c(w, class(c)[1]); invokeRestart("muffleWarning") })
  expect_true("gr_gaps_truncated" %in% w)
  expect_true(s$sections$partial[s$sections$section == "What is missing"])
  closing <- env$seen[[length(env$seen)]]
  body <- sub("(?s)^.*<gaps>\n(.*)\n</gaps>.*$", "\\1",
              paste(vapply(closing, function(m) as.character(m$content), ""), collapse = "\n"),
              perl = TRUE)
  lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  kept <- grep("^- combination unstudied", lines, value = TRUE)
  expect_true(length(kept) > 0L && length(kept) < 300L)
  expect_match(kept[1], "site 1'", fixed = TRUE)
  expect_true(sprintf("%d of 300 gaps shown; do not state totals.", length(kept)) %in% lines)
  at <- match("Left out for space:", lines)
  expect_false(is.na(at))
  stubs <- lines[seq.int(at + 1L, length(lines))]
  expect_identical(stubs[1], sprintf("- gap %d: combination unstudied (design x setting)",
                                     length(kept) + 1L))
  expect_match(stubs[length(stubs)], "^- and [0-9]+ more$")
  expect_lte(hr_count_tokens(paste(c("Left out for space:", stubs), collapse = "\n")), 120L)
  # Without the policy the same cut lists nothing.
  env$seen <- list()
  quiet(suppressWarnings(gr_synthesise(sc_table(), outline = o, question = "Q?", client = cl,
                                       claims = cm, gaps = g, model = "sc-small",
                                       max_section_tokens = 300)))
  plain <- paste(vapply(env$seen[[length(env$seen)]], function(m) as.character(m$content), ""),
                 collapse = "\n")
  expect_false(grepl("Left out for space", plain, fixed = TRUE))
  expect_false(grepl("gaps shown", plain, fixed = TRUE))
})

# Forty studies of about 130 tokens each: on a 3000-token window a section is
# drafted in three batches and merged.
sc_big <- function(n = 40L) {
  d <- sc_table(n)
  d$finding <- paste(rep("The intervention reduced the outcome modestly in adults.", 9),
                     collapse = " ")
  d
}

test_that("the merges of a write-up follow the policy: draft order and the cut's marker", {
  local_registries()
  hr_register_model("sc-merge", context_window = 3000, max_output = 400,
                    input_usd = 0, output_usd = 0)
  merges <- list()
  long <- FALSE
  cl <- hr_mock_client(function(m, p) {
    txt <- paste(vapply(m, function(x) as.character(x$content), ""), collapse = "\n")
    if (grepl("<draft", txt, fixed = TRUE)) {
      merges[[length(merges) + 1L]] <<- txt
      return("Merged [study 1].")
    }
    first <- regmatches(txt, regexpr("\\[study [0-9]+\\]", txt))
    if (long) paste(first, paste(rep("A long draft sentence about the outcome.", 400),
                                 collapse = " "))
    else sprintf("Draft from %s.", first)
  })
  run <- function(...) {
    merges <<- list()
    suppressWarnings(quiet(gr_synthesise(sc_big(), outline = c(Findings = "what"),
                                         question = "Q?", client = cl, model = "sc-merge",
                                         max_section_tokens = 300, ...)))
    merges[[length(merges)]]
  }
  firsts <- function(txt) regmatches(txt, gregexpr("Draft from \\[study [0-9]+\\]", txt))[[1]]
  plain <- firsts(run())
  expect_length(plain, 3L)
  # context_order alone does not move the drafts; order_merges does.
  expect_identical(firsts(run(context_order = "edges")), plain)
  expect_identical(firsts(run(context_order = "edges",
                              context_policy = hr_context_policy(order_merges = TRUE))),
                   plain[c(1, 3, 2)])
  # A draft too long for a merge is cut, and fills a merge's room alone, so
  # the drafts are joined unmerged: the joined text shows the cut's marker.
  long <- TRUE
  hr_register_model("sc-merge-long", context_window = 3000, max_output = 1000,
                    input_usd = 0, output_usd = 0)
  joined <- function(...) {
    s <- suppressWarnings(quiet(gr_synthesise(sc_big(), outline = c(Findings = "what"),
                                              question = "Q?", client = cl,
                                              model = "sc-merge-long",
                                              max_section_tokens = 800, ...)))
    s$sections$text_marked
  }
  cut <- joined(context_policy = list(marker = " [{tokens_dropped} tokens of this draft cut]"))
  expect_match(cut, "[0-9]+ tokens of this draft cut\\]")
  expect_false(grepl(" ...[truncated]", cut, fixed = TRUE))
  expect_match(joined(), " ...[truncated]", fixed = TRUE)
})
