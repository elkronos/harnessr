# test-condensation.R: gr_condensation_check(), its scorer and summary, and
# gr_reverse_text().

test_that("gr_reverse_text() turns paragraphs and sentences around", {
  expect_identical(gr_reverse_text("A one.\n\nB two.\n\n\nC three."), "C three.\n\nB two.\n\nA one.")
  expect_identical(gr_reverse_text("One. Two? Three!", unit = "sentence"), "Three! Two? One.")
  expect_identical(gr_reverse_text(gr_reverse_text("x\n\ny\n\nz")), "x\n\ny\n\nz")
  expect_identical(gr_reverse_text(""), "")
})

test_that("gr_condensation_check() plants facts, lures and a correction in both orders", {
  chk <- gr_condensation_check(n_facts = 5, n_lures = 2, n_documents = 2, paragraphs = 10)
  expect_s3_class(chk, "gr_condensation_check")
  expect_s3_class(chk$reference, "hr_reference")
  expect_s3_class(chk$scorer, "hr_scorer")
  it <- chk$items
  expect_identical(nrow(it), 20L)
  expect_identical(as.vector(table(it$kind)[c("fact", "lure", "correction")]), c(8L, 8L, 4L))
  expect_setequal(names(chk$documents), c("d1.forward", "d1.reversed", "d2.forward",
                                          "d2.reversed"))
  fwd <- chk$documents[["d1.forward"]]
  for (i in which(it$document == "d1" & it$order == "forward")) {
    expect_true(grepl(it$answer[i], fwd, fixed = TRUE), info = it$item[i])
    if (!is.na(it$lure[i])) expect_true(grepl(it$lure[i], fwd, fixed = TRUE))
  }
  cor <- it[it$kind == "correction" & it$document == "d1" & it$order == "forward", ]
  expect_match(fwd, sprintf("Correction: [^.]* was %s[^.]*\\. The figure of %s given earlier",
                            cor$answer, cor$superseded))
  # The superseded value comes first in the forward document, last reversed.
  first_at <- function(doc, v) regexpr(v, doc, fixed = TRUE)[1]
  expect_lt(first_at(fwd, cor$superseded), first_at(fwd, "Correction:"))
  rev <- chk$documents[["d1.reversed"]]
  expect_identical(gr_reverse_text(rev), fwd)
  # Fixed by the seed, not by the random number generator.
  set.seed(99)
  again <- gr_condensation_check(n_facts = 5, n_lures = 2, n_documents = 2, paragraphs = 10)
  expect_identical(again$documents, chk$documents)
  expect_identical(again$reference$hash, chk$reference$hash)
  expect_false(identical(gr_condensation_check(seed = 2)$documents,
                         gr_condensation_check(seed = 1)$documents))
  # The payload holds the question and document only; the values are in the label.
  p <- chk$reference$items[[1]]
  expect_named(p, c("question", "document"))
  expect_output(print(chk), "2 document")
  # A document's forward and reversed copies hold the same facts: one cluster.
  expect_setequal(unique(chk$reference$cluster), c("d1", "d2"))
})

test_that("planting into a text of your own keeps its paragraphs", {
  own <- paste("Paragraph", 1:6, "of the report.", collapse = "\n\n")
  chk <- gr_condensation_check(own, n_facts = 3, n_lures = 1, orders = "forward")
  expect_identical(unique(chk$items$order), "forward")
  expect_match(chk$documents[[1]], "^Paragraph 1 of the report\\.")
  expect_error(gr_condensation_check("one paragraph only"), class = "gr_bad_setting")
  expect_error(gr_condensation_check(n_facts = 1), class = "gr_bad_setting")
  expect_error(gr_condensation_check(n_lures = 6, n_facts = 6), class = "gr_bad_setting")
  expect_error(gr_condensation_check(orders = "sideways"), class = "gr_bad_setting")
})

test_that("the scorer finds the fact, the lure and the superseded value deterministically", {
  s <- gr_condensation_check()$scorer$fn
  fact <- c(answer = "1,204", lure = NA, superseded = NA)
  lure <- c(answer = "41.3", lure = "47.9", superseded = NA)
  cor <- c(answer = "248", lure = NA, superseded = "212")
  expect_true(s(NULL, "It had 1204 staff.", fact)$correct)
  expect_identical(s(NULL, "It was 47.9 million.", lure)$outcome, "lure")
  both <- s(NULL, "Either 41.3 or 47.9 million.", lure)
  expect_false(both$correct)
  expect_identical(both$outcome, "answer+lure")
  expect_true(s(NULL, "The staff count was 248.", cor)$correct)
  old <- s(NULL, "The staff count was 212.", cor)
  expect_identical(old$outcome, "superseded")
  expect_identical(old$failure_kind, "wrong")
  nf <- s(NULL, "NOT_IN_DOCUMENT", cor)
  expect_identical(nf$failure_kind, "not_in_document")
  expect_identical(s(NULL, NA_character_, cor)$failure_kind, "parse_failure")
})

test_that("arms that differ in refine settings run on the check, and the summary reads them", {
  chk <- gr_condensation_check(n_facts = 4, n_lures = 1, paragraphs = 8)
  it <- chk$items
  lure_item <- it[it$kind == "lure", ][1, ]
  cor_item <- it[it$kind == "correction", ][1, ]
  # A stand-in that answers the lure question with the lure's value under the
  # draft and with the fact under the ledger, and the correction question
  # with the superseded value under the draft.
  cl <- hr_mock_client(function(m, p) {
    last <- m[[length(m)]]$content
    if (grepl("Reply with the edits", last, fixed = TRUE)) return("ADD: noted.")
    all <- paste(vapply(m, function(x) x$content, ""), collapse = "\n")
    ledger <- grepl("<findings>", all, fixed = TRUE)
    asks <- vapply(m, function(x) x$content, "")
    asks <- asks[startsWith(asks, "Question: ")]
    q <- sub("^Question: ", "", asks[length(asks)])
    row <- it[it$question == q, ][1, ]
    if (is.na(row$item)) return("NOT_IN_DOCUMENT")
    if (row$kind == "lure" && !ledger) return(paste("It was", row$lure))
    if (row$kind == "correction" && !ledger) return(paste("It was", row$superseded))
    paste("It was", row$answer)
  })
  arms <- hr_sweep(gr_arm("thorough", list(reader = "refine", method = "paragraph")),
                   list(refine_state = c("draft", "ledger")))
  bench <- quiet(hr_benchmark(arms, chk$reference, runs = 2, client = cl, scorer = chk$scorer))
  sm <- gr_condensation_summary(chk, bench)
  expect_identical(nrow(sm), 4L)
  draft <- sm[grepl("draft", sm$arm), ]
  ledger <- sm[grepl("ledger", sm$arm), ]
  expect_true(all(draft$lure_rate == 1))
  expect_true(all(draft$correction_won == 0))
  expect_true(all(ledger$lure_rate == 0))
  expect_true(all(ledger$correction_won == 1))
  expect_true(all(ledger$fact_recall == 1))
  expect_error(gr_condensation_summary(list(), bench), class = "gr_bad_setting")
})
