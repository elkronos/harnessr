# gr_label_sheet() and gr_read_labels(): sheets written blind, filled by
# hand, and read back strictly.

labels_tmp <- function(name) {
  dir <- tempfile("labels-")
  dir.create(dir)
  file.path(dir, name)
}

# What a person does in a spreadsheet: open the sheet, type into the
# decision columns, save it as CSV.
labels_fill <- function(file, ...) {
  s <- utils::read.csv(file, fileEncoding = "UTF-8-BOM", colClasses = "character",
                       check.names = FALSE, na.strings = "")
  vals <- list(...)
  for (col in names(vals)) s[[col]] <- vals[[col]]
  utils::write.csv(s, file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(s)
}

labels_qa_items <- function() {
  data.frame(document = c("a.pdf", "a.pdf", "b.pdf", "c.pdf"),
             question = c("What was revenue?", "Who audited it?", "When did it start?",
                          "How many sites?"),
             answer = c("45.2 million", "Not stated", "2019", "12"),
             score = c(0.9, 0.2, 0.7, 0.6),
             split = "calibration",
             stringsAsFactors = FALSE)
}

test_that("a QA sheet round-trips, typed, with the items joined back", {
  items <- labels_qa_items()
  path <- labels_tmp("qa.csv")
  sheet <- gr_label_sheet("qa", items, path = path)
  expect_true(file.exists(path))
  guide <- sub("[.]csv$", "_instructions.txt", path)
  expect_true(file.exists(guide))
  expect_true(any(grepl("answerable", readLines(guide))))
  expect_identical(attr(sheet, "paths"), c(path, guide))
  expect_identical(sheet$item_id, c("qa-0001", "qa-0002", "qa-0003", "qa-0004"))

  labels_fill(path, answerable = c("Yes", "no", "y", ""),
              answer = c("45.2 million dollars", "", "March 2019", ""),
              quote = c("Revenue was 45.2 million", "", "", ""))
  lab <- gr_read_labels(path, "qa", items = items)
  expect_identical(lab$item_id, sheet$item_id)
  expect_identical(lab$answerable, c(TRUE, FALSE, TRUE, NA))
  expect_identical(lab$answer, c("45.2 million dollars", NA, "March 2019", NA))
  expect_identical(attr(lab, "unlabelled"), 1L)
  expect_identical(attr(lab, "label_kind"), "qa")
  # The design and model columns come back from `items`, not from the sheet.
  expect_identical(lab$split, rep("calibration", 4))
  expect_identical(lab$score, items$score)
  # The items' `answer` is the model's, kept beside the person's.
  expect_identical(lab$model_answer, items$answer)
})

test_that("a blind sheet has no model output and no sampling details", {
  items <- labels_qa_items()
  items$model_reason <- "because"
  blind <- gr_label_sheet("qa", items)
  expect_identical(names(blind), c("item_id", "document", "question", "answerable", "answer",
                                   "quote", "note"))
  expect_true(all(is.na(blind$answer)))

  open <- gr_label_sheet("qa", items, blind = FALSE)
  expect_true(all(c("model_answer", "model_score", "model_reason") %in% names(open)))
  expect_identical(open$model_answer, items$answer)
  expect_false("split" %in% names(open))
  expect_false("model_split" %in% names(open))
  expect_true(all(is.na(open$answer)))
})

test_that("a screening sheet reads back as a reference gr_calibrate() takes", {
  tab <- data.frame(document = paste0("d", 1:6, ".pdf"),
                    decision = c("include", "exclude", "exclude", "unclear", "exclude",
                                 "include"),
                    reason = "r", stringsAsFactors = FALSE)
  items <- data.frame(document = tab$document, title = paste("Title", 1:6),
                      decision = tab$decision, stringsAsFactors = FALSE)
  path <- labels_tmp("screen.csv")
  sheet <- gr_label_sheet("screening", items, path = path, reviewers = 2)
  files <- paste0(sub("[.]csv$", "", path), c("_r1.csv", "_r2.csv"))
  expect_true(all(file.exists(files)))
  expect_identical(attr(sheet, "paths")[1:2], files)
  # Neither reviewer sees the model's decision or the other's.
  one <- utils::read.csv(files[1], fileEncoding = "UTF-8-BOM", colClasses = "character")
  expect_false(any(c("decision", "model_decision") %in% names(one)))
  expect_identical(unique(one$reviewer), "1")

  labels_fill(files[1], human_decision = c("include", "exclude", "exclude", "include",
                                           "exclude", "include"))
  labels_fill(files[2], human_decision = c("INCLUDE", "exclude", "exclude", "exclude",
                                           "exclude", "include"))
  lab <- gr_read_labels(files, "screening", items = items)
  expect_identical(lab$reviewer, rep(c("1", "2"), each = 6))
  expect_identical(lab$human_decision[1], "include")
  expect_identical(lab$human_decision[7], "include")

  ref <- gr_reference_consensus(lab, rule = "any_include")
  expect_identical(ref$human_decision,
                   c("include", "exclude", "exclude", "include", "exclude", "include"))
  cal <- suppressWarnings(gr_calibrate(structure(list(table = tab), class = "gr_screening"),
                                       ref, min_positives = 1))
  expect_s3_class(cal, "gr_calibration")
  expect_false(is.null(cal$reviewers))
})

test_that("a blind reference key survives a screening sheet", {
  tab <- data.frame(document = paste0("d", 1:6, ".pdf"),
                    decision = c("include", "exclude", "exclude", "unclear", "exclude",
                                 "include"),
                    reason = "r", stringsAsFactors = FALSE)
  ref <- gr_reference(structure(list(table = tab), class = "gr_screening"), n = 2,
                      of = "excluded", seed = 1)
  sheet <- gr_label_sheet("screening", as.data.frame(ref))
  expect_identical(sheet$sampled_from, ref$sampled_from)
  # A plain frame name would say what the model decided, so it goes on the
  # sheet as a key instead.
  plain <- gr_reference(structure(list(table = tab), class = "gr_screening"), n = 2,
                        of = "excluded", seed = 1, blind = FALSE)
  keyed <- gr_label_sheet("screening", as.data.frame(plain))
  expect_false(any(c("frame_n", "screened_n") %in% names(keyed)))
  expect_false(any(keyed$sampled_from == "excluded"))
  key <- harnessr:::frame_unkey(keyed$sampled_from[1])
  expect_identical(key[c("of", "frame_n", "screened_n")],
                   list(of = "excluded", frame_n = 3L, screened_n = 6L))
})

test_that("a blind stacked sheet read back without items keeps its frame", {
  dec <- c(rep("include", 60), rep("unclear", 20), rep("exclude", 320))
  tab <- data.frame(document = sprintf("d%03d.pdf", seq_along(dec)), decision = dec,
                    reason = "r", stringsAsFactors = FALSE)
  scr <- structure(list(table = tab), class = "gr_screening")
  ref <- gr_reference(scr, n = 60, of = "stacked", seed = 2, blind = FALSE)
  kept <- which(ref$stratum == "kept")
  ref$human_decision <- "exclude"
  ref$human_decision[kept[seq(1, length(kept), by = 2)]] <- "include"
  ref$human_decision[which(ref$stratum == "excluded")[1:3]] <- "include"
  items <- as.data.frame(ref)
  items$human_decision <- NULL

  path <- labels_tmp("stacked.csv")
  sheet <- gr_label_sheet("screening", items, path = path)
  expect_false(any(c("stratum", "inclusion_prob", "frame_n") %in% names(sheet)))
  labels_fill(path, human_decision = ref$human_decision)
  lab <- gr_read_labels(path, "screening")
  cal <- gr_calibrate(scr, lab)
  # 40 of the 80 kept are eligible, and 3 of the 60 drawn from 320 excluded,
  # weighted up to 16: recall 40 / 56.
  expect_equal(cal$recall$estimate, 40 / 56)
  expect_equal(cal$recall, gr_calibrate(scr, ref)$recall)
  expect_equal(gr_calibrate(scr, gr_read_labels(path, "screening", items = items))$recall,
               cal$recall)

  # Without what a stacked key needs, the frame is left off with a warning.
  items$inclusion_prob <- NULL
  expect_warning(bare <- gr_label_sheet("screening", items), class = "gr_labels_missing")
  expect_false("sampled_from" %in% names(bare))
})

test_that("an extraction sheet round-trips into gr_extract_agreement()", {
  fields <- gr_fields(
    design = gr_field("Study design", type = "enum", values = c("rct", "cohort")),
    n = gr_field("Number randomised", type = "integer"),
    funded = gr_field("Industry funding declared", type = "boolean")
  )
  items <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf"), stringsAsFactors = FALSE)
  path <- labels_tmp("extract.csv")
  sheet <- gr_label_sheet("extraction", items, path = path, fields = fields)
  expect_identical(names(sheet), c("item_id", "document", "design", "n", "funded", "note"))
  guide <- readLines(sub("[.]csv$", "_instructions.txt", path))
  expect_true(any(grepl("n (integer): Number randomised", guide, fixed = TRUE)))

  labels_fill(path, design = c("RCT", "cohort", ""), n = c("120", "not reported", ""),
              funded = c("yes", "no", ""))
  lab <- gr_read_labels(path, "extraction", fields = fields)
  expect_identical(lab$n, c("120", "not reported", NA))
  expect_identical(attr(lab, "unlabelled"), 1L)

  model <- data.frame(document = c("a.pdf", "b.pdf"), design = c("rct", "cohort"),
                      n = c(120, NA), funded = c(TRUE, FALSE))
  ag <- gr_extract_agreement(model, lab[1:2, ], fields = fields, B = 0)
  expect_identical(ag$table$percent_agreement[ag$table$field == "design"], 1)
  expect_identical(ag$table$percent_agreement[ag$table$field == "funded"], 1)

  # Without a schema, every column that is not the sheet's own is a field.
  lab2 <- gr_read_labels(path, "extraction")
  expect_true(all(c("design", "n", "funded") %in% names(lab2)))
})

test_that("a calibration sheet gives a graded set with clusters", {
  items <- labels_qa_items()
  items$item_id <- c("c1", "c2", "c3", "c4")
  blind <- gr_label_sheet("calibration", items)
  expect_false("correct" %in% names(blind))
  open <- gr_label_sheet("calibration", items, blind = FALSE)
  expect_true(all(c("correct", "model_answer") %in% names(open)))

  open$answerable <- c("yes", "no", "yes", "no")
  open$answer <- c("45.2 million", NA, "2019", NA)
  open$correct <- c("1", "0", "true", "FALSE")
  lab <- gr_read_labels(open, "calibration", items = items)
  expect_identical(lab$correct, c(TRUE, FALSE, TRUE, FALSE))
  expect_identical(lab$cluster, items$document)
  expect_identical(lab$score, items$score)
})

test_that("a judge sheet reads pass and fail and counts them", {
  items <- data.frame(item_id = sprintf("j%d", 1:3), question = "Is it supported?",
                      candidate = c("x", "y", "z"), verdict = c("pass", "pass", "fail"),
                      stringsAsFactors = FALSE)
  sheet <- gr_label_sheet("judge", items)
  expect_true(all(is.na(sheet$verdict)))
  sheet$verdict <- c("Pass", "fail", "")
  old <- hr_options(verbose = TRUE)
  on.exit(hr_options(old), add = TRUE)
  expect_message(lab <- gr_read_labels(sheet, "judge"), "1 pass, 1 fail.*at least 50")
  expect_identical(lab$verdict, c("pass", "fail", NA))
  # With the items, the judge's own verdicts come back beside the person's.
  lab <- suppressMessages(gr_read_labels(sheet, "judge", items = items))
  expect_identical(lab$verdict, c("pass", "fail", NA))
  expect_identical(lab$model_verdict, items$verdict)
})

test_that("invalid values stop with the sheet, row and item named", {
  items <- labels_qa_items()
  path <- labels_tmp("bad.csv")
  gr_label_sheet("qa", items, path = path)
  labels_fill(path, answerable = c("yes", "no", "maybe", "yes"),
              answer = c("45.2 million", "", "", ""))
  err <- tryCatch(gr_read_labels(path, "qa"), gr_bad_labels = function(e) e)
  expect_s3_class(err, "gr_bad_labels")
  expect_match(conditionMessage(err), "bad.csv row 4 \\(item 'qa-0003'\\): `answerable` must be yes or no; found 'maybe'")
  expect_match(conditionMessage(err), "row 5 \\(item 'qa-0004'\\): `answerable` is yes but `answer` is empty")
  expect_identical(err$problems$row, c(4L, 5L))

  ext <- labels_tmp("ext.csv")
  fields <- gr_fields(n = gr_field("Number randomised", type = "integer"),
                      arm = gr_field("Arm", type = "enum", values = c("a", "b")))
  gr_label_sheet("extraction", data.frame(document = c("x.pdf", "y.pdf")), path = ext,
                 fields = fields)
  labels_fill(ext, n = c("about a hundred", "40"), arm = c("a", ""))
  expect_error(gr_read_labels(ext, "extraction", fields = fields),
               "row 2 \\(item 'extraction-0001'\\): `n` must be a whole number", class = "gr_bad_labels")
  expect_error(gr_read_labels(ext, "extraction", fields = fields),
               "row 3 \\(item 'extraction-0002'\\): `arm` is empty", class = "gr_bad_labels")

  contra <- gr_label_sheet("qa", items[1:3, ])
  contra$answerable <- c("no", "no", "no")
  contra$answer <- c("something", NA, NA)
  expect_error(gr_read_labels(contra, "qa"),
               "row 2 \\(item 'qa-0001'\\): `answerable` is no but `answer` is filled",
               class = "gr_bad_labels")

  scr <- gr_label_sheet("screening", data.frame(document = c("p", "q")))
  scr$human_decision <- c("include", "maybe")
  expect_error(gr_read_labels(scr, "screening"),
               "row 3 \\(item 'screening-0002'\\): `human_decision` must be include or exclude",
               class = "gr_bad_labels")
})

test_that("rows are numbered as the spreadsheet numbers them, empty rows skipped", {
  items <- labels_qa_items()
  path <- labels_tmp("gaps.csv")
  # An empty line after the second item, and an all-empty row at the end.
  fill_with_gaps <- function(answerable) {
    gr_label_sheet("qa", items, path = path)
    labels_fill(path, answerable = answerable, answer = c("45.2 million", "", "", ""))
    lines <- readLines(path, encoding = "UTF-8")
    writeLines(c(lines[1:3], "", lines[4:5], ",,,,,,"), path, useBytes = TRUE)
  }
  fill_with_gaps(c("yes", "no", "maybe", "no"))
  err <- tryCatch(gr_read_labels(path, "qa", items = items), gr_bad_labels = function(e) e)
  expect_identical(nrow(err$problems), 1L)
  expect_match(conditionMessage(err), "gaps.csv row 5 \\(item 'qa-0003'\\)")

  fill_with_gaps(c("yes", "no", "no", "no"))
  lab <- gr_read_labels(path, "qa", items = items)
  expect_identical(lab$item_id, c("qa-0001", "qa-0002", "qa-0003", "qa-0004"))
  expect_identical(lab$answerable, c(TRUE, FALSE, FALSE, FALSE))
})

test_that("ids are checked against each other and against the items", {
  items <- labels_qa_items()
  sheet <- gr_label_sheet("qa", items)
  dup <- sheet
  dup$item_id[2] <- "qa-0001"
  expect_error(gr_read_labels(dup, "qa"), "row 3 .*appears more than once",
               class = "gr_bad_labels")
  stray <- sheet
  stray$item_id[4] <- "qa-0099"
  expect_error(gr_read_labels(stray, "qa", items = items),
               "row 5 \\(item 'qa-0099'\\): item 'qa-0099' is not one of `items`",
               class = "gr_bad_labels")
  blank <- sheet
  blank$item_id[1] <- " "
  expect_error(gr_read_labels(blank, "qa"), "row 2 .*`item_id` is empty",
               class = "gr_bad_labels")
  expect_warning(gr_read_labels(sheet[1:3, ], "qa", items = items), "qa-0004",
                 class = "gr_labels_missing")
  expect_error(gr_read_labels(sheet, "screening"), "not a screening sheet",
               class = "gr_bad_labels")
})

test_that("accented text and leading zeros survive the file", {
  items <- data.frame(item_id = c("007", "010"), document = c("\u00e9vora.pdf", "b.pdf"),
                      question = c("Qu\u00e9?", "Why?"), stringsAsFactors = FALSE)
  path <- labels_tmp("utf.csv")
  gr_label_sheet("qa", items, path = path)
  labels_fill(path, answerable = c("no", "no"))
  lab <- gr_read_labels(path, "qa", items = items)
  expect_identical(lab$item_id, c("007", "010"))
  expect_identical(lab$document[1], "\u00e9vora.pdf")
  expect_identical(lab$question[1], "Qu\u00e9?")
})

test_that("bad settings stop with gr_bad_setting", {
  items <- labels_qa_items()
  expect_error(gr_label_sheet("qa", items[, "question", drop = FALSE]), "`document`",
               class = "gr_bad_setting")
  expect_error(gr_label_sheet("extraction", data.frame(document = "a")), "fields",
               class = "gr_bad_setting")
  expect_error(gr_label_sheet("extraction", data.frame(document = c("a", "a")), fields = "n"),
               "one row per document", class = "gr_bad_setting")
  expect_error(gr_label_sheet("extraction", data.frame(document = "a"), fields = "note"),
               "clash", class = "gr_bad_setting")
  # Another kind's decision column would not read back as a field.
  expect_error(gr_label_sheet("extraction", data.frame(document = "a"),
                              fields = c("answer", "z")),
               "'answer'.*clash", class = "gr_bad_setting")
  expect_error(gr_label_sheet("qa", items, reviewers = 0), class = "gr_bad_setting")
  expect_error(gr_label_sheet("qa", items, blind = NA), class = "gr_bad_setting")
  expect_error(gr_read_labels(labels_tmp("none.csv"), "qa"), "No sheet",
               class = "gr_bad_setting")
  expect_error(gr_read_labels(items, "quiz"), class = "gr_bad_setting")
})

test_that("an id-like column is not taken for the ids, so a blind sheet stays blind", {
  # No item_id or id column: the ids are the kind and the row number, as
  # documented, not the reference answers in `ideal_answer`.
  qa <- data.frame(document = c("a.pdf", "a.pdf", "b.pdf"),
                   question = c("What was revenue?", "Who audited it?",
                                "When did the trial start?"),
                   ideal_answer = c("45.2 million dollars", "KPMG", "March 2019"))
  sheet <- gr_label_sheet("qa", qa)
  expect_identical(sheet$item_id, c("qa-0001", "qa-0002", "qa-0003"))
  expect_false(any(unlist(lapply(sheet, as.character)) %in% qa$ideal_answer, na.rm = TRUE))
})

test_that("a blind = FALSE calibration sheet read without items is a graded set", {
  items <- data.frame(item_id = sprintf("c%d", 1:4), document = c("a", "a", "b", "b"),
                      question = "q?", answer = c("x", "y", "z", "w"),
                      score = c(0.9, 0.2, 0.7, 0.4))
  open <- gr_label_sheet("calibration", items, blind = FALSE)
  path <- labels_tmp("cal.csv")
  suppressMessages(gr_label_sheet("calibration", items, path = path, blind = FALSE))
  labels_fill(path, answerable = c("yes", "no", "yes", "no"), answer = c("x", NA, "z", NA),
              correct = c("yes", "no", "yes", "no"))
  lab <- suppressMessages(gr_read_labels(path, "calibration"))
  # model_score went through the CSV as text; it comes back as the numbers
  # 0.9, 0.2, 0.7 and 0.4 the items had.
  expect_identical(lab$score, c(0.9, 0.2, 0.7, 0.4))
  expect_identical(lab$cluster, c("a", "a", "b", "b"))
  key <- list(served_model = "m", version = "1", task = "qa", format = "pdf",
              prompt_hash = "h", effort = NA, module = "it")
  cal <- hr_calibrate_signal("s", lab, key, seed = 1, B = 0)
  expect_identical(cal$n_items, 4L)
  # A logical score is written TRUE and FALSE and read back as 1 and 0.
  items$score <- c(TRUE, FALSE, TRUE, FALSE)
  open <- gr_label_sheet("calibration", items, blind = FALSE)
  open$answerable <- c("yes", "no", "yes", "no")
  open$answer <- c("x", NA, "z", NA)
  open$correct <- c("yes", "no", "yes", "no")
  expect_identical(suppressMessages(gr_read_labels(open, "calibration"))$score, c(1, 0, 1, 0))
})

# ---- pairwise sheets ---------------------------------------------------------

labels_pairs <- function(n = 40) {
  data.frame(item_id = sprintf("p%02d", seq_len(n)), question = "Which is right?",
             candidate_a = sprintf("Answer A%02d", seq_len(n)),
             candidate_b = sprintf("Answer B%02d", seq_len(n)),
             judge_verdict = "A", stringsAsFactors = FALSE)
}

test_that("a pairwise sheet shows the two texts in a blinded order behind a key", {
  items <- labels_pairs()
  sheet <- gr_label_sheet("pairwise", items)
  expect_identical(names(sheet), c("item_id", "question", "text_1", "text_2", "order_key",
                                   "preferred", "note"))
  # The candidates' own columns, and anything else in `items`, stay off it.
  expect_false(any(c("candidate_a", "candidate_b", "judge_verdict") %in% names(sheet)))
  b_first <- sheet$text_1 == items$candidate_b
  # Every row shows both texts once, in one order or the other.
  expect_true(all(ifelse(b_first, sheet$text_2 == items$candidate_a,
                         sheet$text_1 == items$candidate_a)))
  # Both orders occur, and the order is the same when the sheet is written
  # again: it comes from the row, not from the random state.
  expect_true(any(b_first) && any(!b_first))
  set.seed(99)
  expect_identical(gr_label_sheet("pairwise", items)$text_1, sheet$text_1)
  # The keys are opaque and of one length whichever order a row has.
  expect_true(all(grepl("^pk[0-9a-f]+$", sheet$order_key)))
  expect_length(unique(nchar(sheet$order_key)), 1L)
  # Without blind, other columns are copied as model_ columns, the order
  # is still blinded and the candidates are still not written as they are.
  open <- gr_label_sheet("pairwise", items, blind = FALSE)
  expect_true("model_judge_verdict" %in% names(open))
  expect_false(any(c("candidate_a", "candidate_b", "model_candidate_a") %in% names(open)))
  expect_identical(open$text_1, sheet$text_1)
  expect_error(gr_label_sheet("pairwise", items[, c("item_id", "candidate_a")]),
               class = "gr_bad_setting")
})

test_that("pairwise labels come back as A, B or tie in candidate order", {
  items <- labels_pairs(6)
  path <- labels_tmp("pairs.csv")
  sheet <- suppressMessages(gr_label_sheet("pairwise", items, path = path))
  expect_true(any(grepl("preferred", readLines(sub("[.]csv$", "_instructions.txt", path)))))
  # The person prefers whichever text is shown first on rows 1 to 4 and
  # calls rows 5 and 6 a tie. In candidate order, row i's answer is the
  # candidate its text_1 came from.
  labels_fill(path, preferred = c("1", "1", "1", "1", "tie", "TIE"))
  lab <- suppressMessages(gr_read_labels(path, "pairwise", items = items))
  first <- ifelse(sheet$text_1 == items$candidate_a, "A", "B")
  expect_identical(lab$shown_first, first)
  expect_identical(lab$preferred, c(first[1:4], "tie", "tie"))
  # And text_2 on a row shown B first is candidate A.
  labels_fill(path, preferred = rep("2", 6))
  lab2 <- suppressMessages(gr_read_labels(path, "pairwise"))
  expect_identical(lab2$preferred, ifelse(first == "A", "B", "A"))
  # The items' columns are joined back, so the candidates sit beside the label.
  expect_identical(lab$candidate_a, items$candidate_a)
})

test_that("pairwise labels feed hr_judge_validate with ties counted as negative", {
  # 60 pairs where people prefer A, 30 where they prefer B and 30 ties.
  # The judge agrees on every A and B pair and calls every tie "A".
  # Positive is "A": human positives 60, negatives 60 (B and tie).
  # Judge positives: the 60 A pairs and the 30 ties. Sensitivity 60/60 = 1,
  # specificity 30/60 = 0.5: the ties the judge called A are false positives.
  n <- 120
  items <- labels_pairs(n)
  sheet <- gr_label_sheet("pairwise", items)
  human <- rep(c("A", "B", "tie"), c(60, 30, 30))
  first <- ifelse(sheet$text_1 == items$candidate_a, "A", "B")
  sheet$preferred <- ifelse(human == "tie", "tie", ifelse(human == first, "1", "2"))
  lab <- suppressMessages(gr_read_labels(sheet, "pairwise"))
  expect_identical(lab$preferred, human)
  judge <- ifelse(human == "tie", "A", human)
  cfg <- hr_judge_config("mock-model", "Which answer is right?", mode = "pairwise")
  v <- hr_judge_validate(cfg, data.frame(judge = judge, human = lab$preferred),
                         positive = "A", B = 0)
  expect_identical(v$n_pos, 60L)
  expect_identical(v$n_neg, 60L)
  expect_equal(v$sensitivity$estimate, 1)
  expect_equal(v$specificity$estimate, 0.5)
})

test_that("a pairwise row with a bad value or a key from another row is refused", {
  items <- labels_pairs(4)
  sheet <- gr_label_sheet("pairwise", items)
  sheet$preferred <- c("1", "3", "tie", "2")
  err <- tryCatch(gr_read_labels(sheet, "pairwise"), gr_bad_labels = function(e) e)
  expect_s3_class(err, "gr_bad_labels")
  expect_match(conditionMessage(err), "1, 2 or tie")
  expect_identical(err$problems$item_id, "p02")
  # Keys swapped between rows 1 and 2, and one key typed over, are caught.
  sheet$preferred <- "1"
  sheet$order_key[1:2] <- sheet$order_key[2:1]
  sheet$order_key[4] <- "pk0000000000"
  err <- tryCatch(gr_read_labels(sheet, "pairwise"), gr_bad_labels = function(e) e)
  expect_identical(err$problems$item_id, c("p01", "p02", "p04"))
  expect_match(err$problems$problem[1], "order_key")
  # A sheet with no key column is not a pairwise sheet.
  sheet$order_key <- NULL
  expect_error(gr_read_labels(sheet, "pairwise"), "order_key", class = "gr_bad_labels")
})
