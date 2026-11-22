# gr_search_recall(): known-item recall of a search against a seed set.

recall_records <- function() {
  data.frame(
    title = c("Spaced practice and long-term retention in adults",
              "Retrieval practice in the classroom: a field trial",
              "Interleaving mathematics problems improves test scores",
              "Reply",
              "Exercise and memory in older adults",
              "Exercise and memory in older adults",
              "Sleep, attention and recall in adolescents"),
    year = c("2019", "2021", "2015", "2020", "2018", "2018", "2022"),
    doi = c("10.1000/sp1", NA, "10.1000/il3", NA, "10.1000/ex1", "10.1000/ex2", NA),
    authors = c("Smith, J.", "Okafor, A.", "Lee, K.", "Brown, T.", "Garcia, M.",
                "Nguyen, P.", "Patel, R."),
    venue = c("J Educ Psychol", "Learning and Instruction", "Mem Cognit", "BMJ",
              "Neurology", "Neurology", "Sleep"),
    stringsAsFactors = FALSE)
}

recall_seeds <- function() {
  data.frame(
    title = c("Spaced practice and long-term retention in adults",   # by DOI and title
              "Retrieval practice in the classroom: a field trial",   # by title and author
              "Reply",                                                # short title
              "Exercise and memory in older adults",                  # two DOIs share it
              "Sleep, attention and recall in adolescents",           # another first author
              "A trial nobody indexed",                               # absent
              NA),                                                    # nothing to match on
    year = c("2019", "2021", "2020", "2018", "2022", "2017", NA),
    doi = c("10.1000/sp1", NA, NA, NA, NA, NA, NA),
    authors = c("Smith, J.", "Okafor, A.", "Brown, T.", "Garcia, M.", "Kowalski, Z.",
                "Diaz, M.", "Nobody, N."),
    venue = c("J Educ Psychol", "Learning and Instruction", "BMJ", "Neurology", "Sleep",
              "Lancet", NA),
    stringsAsFactors = FALSE)
}

test_that("seeds are matched by the dedupe rules, and refusals are listed with a reason", {
  r <- gr_search_recall(recall_records(), recall_seeds())
  expect_s3_class(r, "gr_search_recall")
  expect_identical(r$seeds$found, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(r$seeds$record_id[1:2], c(1L, 2L))
  expect_identical(r$missed$reason, c("short_title", "multi_doi", "not_confirmed",
                                      "not_in_records", "no_identifier"))
  expect_identical(r$refused$seed, 3:5)
  expect_identical(nrow(r$excluded), 0L)
  ci <- hr_prop_ci(2, 7, method = "clopper_pearson")
  expect_identical(r$recall$tier, "all")
  expect_identical(c(r$recall$found, r$recall$n), c(2L, 7L))
  expect_equal(c(r$recall$estimate, r$recall$lower, r$recall$upper),
               c(ci$est, ci$lower, ci$upper))
  expect_identical(r$recall$method, "clopper_pearson")
  out <- capture.output(print(r))
  expect_true(any(grepl("relative to the seed set", out, fixed = TRUE)))
  expect_true(any(grepl("refused by the matching rules", out, fixed = TRUE)))
})

test_that("a seed is found exactly when a dedupe run over every record would merge it", {
  recs <- recall_records()
  seeds <- recall_seeds()
  r <- gr_search_recall(recs, seeds)
  cols <- c("authors", "year", "title", "venue", "doi")
  for (s in seq_len(nrow(seeds))) {
    all <- rbind(recs[, cols], seeds[s, cols])
    all$record_id <- seq_len(nrow(all))
    hit <- harnessr:::dedupe_records(all, "doi+title")[nrow(all)]
    expect_identical(!is.na(hit), isTRUE(r$seeds$found[s]), info = s)
  }
})

test_that("seeds used to build the search are left out and reported", {
  seeds <- recall_seeds()[1:2, ]
  seeds$used_to_build <- c(TRUE, FALSE)
  r <- gr_search_recall(recall_records(), seeds)
  expect_identical(r$excluded$seed, 1L)
  expect_identical(c(r$recall$found, r$recall$n), c(1L, 1L))
  expect_true(is.na(r$seeds$found[1]))
  expect_true(any(grepl("used to build the search are left out", capture.output(print(r)))))

  # held_out says the same thing the other way round, as a logical or as rows.
  seeds$used_to_build <- NULL
  a <- gr_search_recall(recall_records(), seeds, held_out = c(FALSE, TRUE))
  b <- gr_search_recall(recall_records(), seeds, held_out = 2)
  expect_identical(a$recall, r$recall)
  expect_identical(b$recall, r$recall)

  seeds$used_to_build <- c(FALSE, TRUE)
  expect_error(gr_search_recall(recall_records(), seeds, held_out = 2), class = "gr_bad_seeds")
  expect_error(gr_search_recall(recall_records(), seeds, held_out = 3), class = "gr_bad_seeds")
  seeds$used_to_build <- c(TRUE, TRUE)
  expect_error(gr_search_recall(recall_records(), seeds), class = "gr_bad_seeds")
  seeds$used_to_build <- c(TRUE, NA)
  expect_error(gr_search_recall(recall_records(), seeds), class = "gr_bad_seeds")
})

test_that("recall is given per tier, and an empty seed set or tier is refused", {
  seeds <- recall_seeds()
  seeds$tier <- c("core", "core", "core", "other", "other", "other", "other")
  r <- gr_search_recall(recall_records(), seeds, tier = "tier")
  expect_identical(r$recall$tier, c("all", "core", "other"))
  expect_identical(r$recall$found, c(2L, 2L, 0L))
  expect_identical(r$recall$n, c(7L, 3L, 4L))
  ci <- hr_prop_ci(c(2, 2, 0), c(7, 3, 4), method = "clopper_pearson")
  expect_equal(r$recall$lower, ci$lower)
  expect_equal(r$recall$upper, ci$upper)
  # The same tiers given as values.
  v <- gr_search_recall(recall_records(), seeds, tier = seeds$tier)
  expect_identical(v$recall, r$recall)

  expect_error(gr_search_recall(recall_records(), seeds[0, ]), class = "gr_bad_seeds")
  # A tier whose every seed helped build the search has nothing to count.
  seeds$used_to_build <- seeds$tier == "other"
  expect_error(gr_search_recall(recall_records(), seeds, tier = "tier"),
               "Tier 'other' has no seed", class = "gr_bad_seeds")
  # A factor level with no seed at all is an empty tier too.
  seeds$used_to_build <- NULL
  expect_error(gr_search_recall(recall_records(), seeds,
                                tier = factor(seeds$tier, levels = c("core", "other", "grey"))),
               class = "gr_bad_seeds")
  seeds$tier[2] <- NA
  expect_error(gr_search_recall(recall_records(), seeds, tier = "tier"), class = "gr_bad_seeds")
  expect_error(gr_search_recall(recall_records(), seeds, tier = "no_such_column"),
               class = "gr_bad_seeds")
})

test_that("records and seeds can come from gr_records()", {
  ris <- function(path, entries) {
    writeLines(unlist(lapply(entries, function(e) c("TY  - JOUR", e, "ER  - "))), path)
    path
  }
  found <- ris(tempfile(fileext = ".ris"), list(
    c("AU  - Smith, J.", "TI  - Spaced practice and long-term retention in adults",
      "PY  - 2019", "DO  - https://doi.org/10.1000/SP1"),
    c("AU  - Lee, K.", "TI  - Interleaving mathematics problems improves test scores",
      "PY  - 2015")))
  known <- ris(tempfile(fileext = ".ris"), list(
    c("AU  - Smith, J.", "TI  - Spaced practice and long-term retention in adults",
      "PY  - 2019", "DO  - 10.1000/sp1"),
    c("AU  - Lee, K.", "TI  - Interleaving Mathematics Problems Improves Test Scores.",
      "PY  - 2015")))
  r <- gr_search_recall(gr_records(found), gr_records(known))
  expect_identical(r$seeds$found, c(TRUE, TRUE))
  expect_identical(r$recall$estimate, 1)
})

test_that("gr_audit_report() takes the recall as a last argument, and old calls keep working", {
  seeds <- recall_seeds()
  seeds$used_to_build <- c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  r <- gr_search_recall(recall_records(), seeds)
  fields <- gr_fields(design = "The study design")
  cl <- gr_mock_client(function(m, p) {
    '{"design":"randomised trial","design__quote":"We ran a randomised trial."}'
  })
  f <- tempfile(fileext = ".txt"); writeLines("We ran a randomised trial.", f)
  x <- suppressMessages(gr_extract(f, fields, client = cl))
  expect_identical(tail(names(formals(gr_audit_report)), 2), c("open", "recall"))

  out <- tempfile(fileext = ".html")
  suppressMessages(gr_audit_report(out, extraction = x, open = FALSE, recall = r))
  html <- paste(readLines(out, warn = FALSE), collapse = "\n")
  expect_match(html, "Known papers the search found", fixed = TRUE)
  expect_match(html, "Recall is relative to the seed set", fixed = TRUE)
  expect_match(html, "3 missed seed(s) were refused by the matching rules", fixed = TRUE)
  expect_match(html, "1 seed(s) used to build the search are left out", fixed = TRUE)
  expect_match(html, "<td class=\"num\">2</td><td class=\"num\">6</td><td>33.3%</td>",
               fixed = TRUE)

  # Every argument before it keeps its place: a call that names nothing still
  # files the extraction as the extraction, and has no recall section.
  old <- tempfile(fileext = ".html")
  suppressMessages(gr_audit_report(old, NULL, x, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                                   FALSE))
  html <- paste(readLines(old, warn = FALSE), collapse = "\n")
  expect_match(html, "What was extracted", fixed = TRUE)
  expect_false(grepl("Known papers the search found", html, fixed = TRUE))
  expect_error(gr_audit_report(old, extraction = x, open = FALSE, recall = list()),
               class = "gr_bad_audit_input")
})
