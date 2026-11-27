# test-extract-advisory.R: a value resolve = "model" chose is marked as a
# model's pick, in the answer, the table, the print and the audit report. No
# validation record backs the choice, so it is advisory.

adv_say <- function(s) paste(rep(s, 3), collapse = " ")

adv_doc <- function(dir = NULL) {
  f <- if (is.null(dir)) tempfile(fileext = ".txt") else file.path(dir, "conflict.txt")
  writeLines(c(adv_say("The abstract reports that we enrolled 120 patients in the trial overall."),
               "",
               adv_say("The results section reports that we enrolled 150 patients in the trial overall."),
               "",
               adv_say("The design was a randomised controlled trial run at four sites overall.")),
             f)
  f
}

adv_json <- function(...) {
  as.character(jsonlite::toJSON(list(...), auto_unbox = TRUE, digits = NA, null = "null"))
}

# Chunks give n = 120 and n = 150; design is stated once. `choice` is what
# the adjudicating call answers: a number, or "fail" for an error.
adv_client <- function(choice) {
  hr_mock_client(function(m, p) {
    if (grepl("different values", m[[1]]$content, fixed = TRUE)) {
      if (identical(choice, "fail")) stop("HTTP 500 server error")
      return(sprintf('{"choice": %s}', choice))
    }
    ex <- m[[length(m)]]$content
    if (grepl("abstract", ex, fixed = TRUE)) {
      adv_json(n = 120,
               n__quote = "The abstract reports that we enrolled 120 patients in the trial overall.")
    } else if (grepl("results section", ex, fixed = TRUE)) {
      adv_json(n = 150,
               n__quote = "The results section reports that we enrolled 150 patients in the trial overall.")
    } else {
      adv_json(design = "randomised controlled trial",
               design__quote = "The design was a randomised controlled trial run at four sites overall.")
    }
  })
}

adv_fields <- function() {
  gr_fields(n = gr_field("Participants", type = "integer"), design = "The study design")
}

adv_extract <- function(choice, resolve = "model", ...) {
  quiet(gr_extract(adv_doc(), adv_fields(), client = adv_client(choice), recipe = "thorough",
                   max_tokens = 48, resolve = resolve, ...))
}

test_that("a value a model chose is named in the answer and in model_picks", {
  x <- adv_extract(2, keep_answers = TRUE)
  expect_identical(x$table$n, 150L)
  expect_identical(x$answers[[1]]$notes$model_picks, "n")
  expect_identical(x$table$model_picks, "n")
  # The column follows `error`, so every column before it keeps its position.
  expect_identical(utils::tail(names(x$table), 2L), c("error", "model_picks"))
  # A field stated once was not chosen by a model.
  expect_false(grepl("design", x$table$model_picks, fixed = TRUE))
})

test_that("a pick of the first value is still a model's pick", {
  x <- adv_extract(1)
  expect_identical(x$table$n, 120L)
  expect_identical(x$table$model_picks, "n")
})

test_that("a call that settled nothing names no pick", {
  for (choice in c("0", "fail", "7")) {
    x <- adv_extract(choice, keep_answers = TRUE)
    expect_identical(x$table$n, 120L, info = choice)
    expect_true(is.na(x$table$model_picks), info = choice)
    expect_length(x$answers[[1]]$notes$model_picks, 0L)
  }
})

test_that("the other resolve rules keep the table's columns as they were", {
  cols <- c("document", "document_id", "n", "design", "n_filled", "n_unverified",
            "conflicts", "status", "duplicate_of", "error")
  for (rule in c("first", "vote")) {
    x <- adv_extract(2, resolve = rule)
    expect_identical(names(x$table), cols, info = rule)
    expect_false(any(grepl("chosen by a model", capture.output(print(x)), fixed = TRUE)),
                 info = rule)
  }
})

test_that("the print says how many values a model chose, and that they are advisory", {
  out <- capture.output(print(adv_extract(2)))
  expect_true(any(grepl(paste0("1 value(s) chosen by a model under resolve = \"model\" (see ",
                               "`model_picks`): advisory, so check each against its quote"),
                        out, fixed = TRUE)))
  out <- capture.output(print(adv_extract(0)))
  expect_false(any(grepl("chosen by a model", out, fixed = TRUE)))
})

test_that("the audit report says a model's pick is advisory and flags it", {
  x <- adv_extract(2)
  h <- tempfile(fileext = ".html")
  quiet(gr_audit_report(h, extraction = x, open = FALSE))
  html <- paste(readLines(h, warn = FALSE), collapse = "\n")
  expect_match(html, "Values a model chose.", fixed = TRUE)
  expect_match(html, "A model's pick is advisory", fixed = TRUE)
  expect_match(html, "<span class='flag'>n</span>", fixed = TRUE)
  # Without a pick the paragraph is not there.
  y <- adv_extract(0)
  quiet(gr_audit_report(h, extraction = y, open = FALSE))
  html <- paste(readLines(h, warn = FALSE), collapse = "\n")
  expect_false(grepl("Values a model chose.", html, fixed = TRUE))
})

test_that("a restored document keeps its picks", {
  store <- withr::local_tempdir()
  dir <- withr::local_tempdir()
  doc <- adv_doc(dir)
  cl <- adv_client(2)
  first <- quiet(gr_extract(doc, adv_fields(), client = cl, recipe = "thorough",
                            max_tokens = 48, resolve = "model", store = store))
  again <- quiet(gr_extract(doc, adv_fields(), client = cl, recipe = "thorough",
                            max_tokens = 48, resolve = "model", store = store))
  expect_identical(again$table$status, "restored")
  expect_identical(first$table$model_picks, "n")
  expect_identical(again$table$model_picks, "n")
})

test_that("model_picks is bookkeeping, never a field", {
  expect_error(gr_fields(model_picks = "A field"), class = "gr_bad_field")
  used <- data.frame(document = "a", n = 1L, model_picks = "n")
  expect_identical(harnessr:::study_fields(used), "n")
  expect_true("model_picks" %in% harnessr:::.gr_extract_bookkeeping)
})
