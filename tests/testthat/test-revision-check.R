# test-revision-check.R: revision_check = "judge", the advisory sentence
# judge behind the lexicon guard of the write-up's revision passes. Off by
# default; the golden records check that a default write-up is unchanged.

rc_draft <- paste(
  "Regular exercise is associated with lower blood pressure in adults [study 1].",
  "Exercise may also improve sleep [study 2].")
rc_stronger <- paste(
  "Regular exercise reduces blood pressure in adults [study 1].",
  "Exercise may also improve sleep [study 2].")
rc_hedged_draft <- paste(
  "Two trials of older adults reported lower blood pressure after training [study 1].",
  "Training may lower blood pressure [study 1].")
rc_moved <- paste(
  "Two trials of older adults reported that training may lower blood pressure [study 1].",
  "Training was followed by lower blood pressure in these trials [study 1].")

# A judge that calls a sentence stronger when its reference says "associated
# with" and it says "reduces"; anything else holds. The revision pass itself
# gets `revision`.
rc_client <- function(revision) {
  gr_mock_client(function(m, p) {
    if (grepl("You grade one response", m[[1]]$content, fixed = TRUE)) {
      body <- m[[2]]$content
      ref <- sub(".*Reference answer:\n(.*?)\n\n.*", "\\1", body)
      resp <- sub(".*Response to grade:\n(.*?)(\n\n.*|$)", "\\1", body)
      if (grepl("associated with", ref) && grepl("reduces", resp)) {
        return('{"verdict": "stronger", "reason": "An association became a cause."}')
      }
      return('{"verdict": "holds", "reason": "Same claim."}')
    }
    revision
  })
}

rc_spec <- function(check = "judge") {
  sp <- gr_read_spec("stuff", model = "mock-model", max_answer_tokens = 400)
  if (!is.null(check)) sp$revision_check <- check
  sp
}

test_that("the lexicon guard passes both revisions, so only the judge can tell them apart", {
  expect_true(strength_guard(rc_draft, rc_stronger)$ok)
  expect_true(strength_guard(rc_hedged_draft, rc_moved)$ok)
})

test_that("the judge rejects 'is associated with' becoming 'reduces'", {
  tr <- gr_trace()
  j <- judge_revision(rc_draft, rc_stronger, rc_client(""), rc_spec(), tr)
  expect_identical(nrow(j), 1L)
  expect_match(j$sentence, "reduces blood pressure")
  expect_identical(j$verdict, "stronger")
  # Its requests are part of the run, held to the run's governor.
  expect_gte(tr$calls, 1L)
})

test_that("the judge accepts a hedge moved into another sentence", {
  j <- judge_revision(rc_hedged_draft, rc_moved, rc_client(""), rc_spec(), gr_trace())
  expect_identical(nrow(j), 2L)
  expect_true(all(j$verdict == "holds"))
})

test_that("the judge is advisory: a flagged revision is kept, word for word", {
  tr <- gr_trace()
  expect_warning(step <- revise_once(rc_draft, "Does exercise help?", rc_client(rc_stronger),
                                     rc_spec(), tr, NULL, "register"),
                 class = "gr_revision_flagged")
  expect_true(step$kept)
  expect_identical(step$text, rc_stronger)
  expect_identical(step$judged$verdict, "stronger")
  ok <- revise_once(rc_hedged_draft, "Does training help?", rc_client(rc_moved), rc_spec(),
                    gr_trace(), NULL, "register")
  expect_true(ok$kept)
  expect_true(all(ok$judged$verdict == "holds"))
  # Without the setting no judge is asked.
  cl <- rc_client(rc_stronger)
  plain <- revise_once(rc_draft, "Does exercise help?", cl, rc_spec(NULL), gr_trace(), NULL,
                       "register")
  expect_true(plain$kept)
  expect_null(plain$judged)
  expect_false(any(grepl("^judge", call_labels(cl))))
})

test_that("synth_revise() reports the flags only under the judge", {
  rev <- suppressWarnings(synth_revise(rc_draft, "Does exercise help?", rc_client(rc_stronger),
                                       rc_spec(), gr_trace(), passes = "register"))
  expect_identical(rev$report$flagged, 1L)
  expect_identical(rev$flags$verdict, "stronger")
  expect_identical(rev$flags$pass, "register")
  plain <- synth_revise(rc_draft, "Does exercise help?", rc_client(rc_stronger), rc_spec(NULL),
                        gr_trace(), passes = "register")
  expect_false("flagged" %in% names(plain$report))
  expect_null(plain$flags)
})

test_that("revision_check is a setting of gr_synthesise() with a guide and evidence", {
  s <- gr_settings_table("synthesise")
  row <- s[s$name == "revision_check", ]
  expect_identical(row$default, "lexicon")
  expect_identical(row$status, "untested")
  expect_identical(row$guide, "review#set-synthesis")
  expect_error(gr_synthesise(data.frame(), revision_check = "oracle"))
})

test_that("revision_check is swept as arms", {
  arms <- hr_sweep(function(revision_check) {
    hr_arm(paste0("write-", revision_check), function(item, ctx) item,
           params = list(revision_check = revision_check))
  }, list(revision_check = c("lexicon", "judge")))
  expect_length(arms, 2L)
})
