# The right-paper check: is the file matched to a record the paper it names?

test_that("record_identity() looks for the DOI or the title in the opening text", {
  ri <- harnessr:::record_identity
  title <- "Spaced practice and long-term retention in adults"
  page <- paste("Journal of Learning 12(3)", "Spaced practice and long-term",
                "retention in adults", "J. Smith", "Abstract. We ...", sep = "\n")
  expect_true(ri(page, title, NA))
  # Case, accents, punctuation and line breaks do not matter, as in deduplication.
  expect_true(ri("SPACED PRACTICE AND LONG-TERM RETENTION IN ADULTS.", title, NA))
  expect_true(ri("Some other words\nhttps://doi.org/10.1000/SP1\n", "Another title entirely here",
                 "10.1000/sp1"))
  expect_false(ri("Sleep and memory consolidation in students", title, "10.1000/sp1"))
  expect_false(ri("Sleep and memory consolidation in students", title, NA))
  # Nothing to check: no text, a DOI alone that the page does not print, a short title.
  expect_true(is.na(ri("", title, NA)))
  expect_true(is.na(ri("Sleep and memory", NA, "10.1000/sp1")))
  expect_true(is.na(ri("Sleep and memory", "Reply", NA)))
  # Only the opening is searched.
  far <- paste(strrep("Filler text of a long cover page. ", 300), title)
  expect_false(ri(far, title, NA))
})

identity_corpus <- function() {
  d <- tempfile("identity")
  dir.create(d)
  # Matched by first author and year, and the wrong paper.
  writeLines(c("Sleep and memory consolidation in students", "J. Smith",
               "Revenue was 45.2 million dollars."), file.path(d, "Smith 2019.txt"))
  # The right paper, its title broken over two lines.
  writeLines(c("Retrieval practice in the classroom:", "a field trial", "A. Okafor",
               "Revenue was 45.2 million dollars."), file.path(d, "Okafor 2021.txt"))
  # The right paper, named by its DOI only.
  writeLines(c("Interleaved problems and scores", "doi:10.1000/IL3",
               "Revenue was 45.2 million dollars."), file.path(d, "Lee 2015.txt"))
  ris <- tempfile(fileext = ".ris")
  writeLines(c("TY  - JOUR", "AU  - Smith, J.",
               "TI  - Spaced practice and long-term retention in adults", "PY  - 2019", "ER  - ",
               "TY  - JOUR", "AU  - Okafor, A.",
               "TI  - Retrieval practice in the classroom: a field trial", "PY  - 2021", "ER  - ",
               "TY  - JOUR", "AU  - Lee, K.",
               "TI  - Interleaving mathematics problems improves test scores", "PY  - 2015",
               "DO  - 10.1000/il3", "ER  - "), ris)
  gr_records(ris, files = d)
}

test_that("gr_read_many() checks each file against its record, and drops nothing", {
  recs <- identity_corpus()
  expect_true(all(recs$records$retrieved))
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  expect_warning(out <- suppressMessages(gr_read_many(recs, "What was revenue?", "fast",
                                                      client = cl)),
                 class = "gr_identity_mismatch")
  s <- out$summary
  by_doc <- stats::setNames(s$identity, s$document)
  expect_identical(unname(by_doc[c("Smith 2019.txt", "Okafor 2021.txt", "Lee 2015.txt")]),
                   c(FALSE, TRUE, TRUE))
  expect_identical(names(s)[ncol(s)], "identity")
  expect_identical(nrow(s), 3L)
  expect_true(all(s$status == "ok"))
  expect_match(s$warnings[s$document == "Smith 2019.txt"], "may not be the paper", fixed = TRUE)
  expect_output(print(out), "1 document(s) may not be the paper", fixed = TRUE)

  # The audit report shows it.
  f <- tempfile(fileext = ".html")
  suppressMessages(gr_audit_report(f, answer = out, open = FALSE))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "Is each file the paper its record names?", fixed = TRUE)
  expect_match(html, "2 of 3 document(s) name their record", fixed = TRUE)
  expect_match(html, "<th>identity</th>", fixed = TRUE)
})

test_that("the check reaches screening and extraction, and gr_flow() does not move", {
  recs <- identity_corpus()
  p <- gr_protocol("identity", question = "What was revenue?", include = "Reports revenue",
                   fields = gr_fields(revenue = gr_field("Revenue in millions", type = "number")))
  cl <- hr_mock_client(function(m, p) {
    if (identical(p$schema_name, "screen") || any(grepl("screen", vapply(m, function(z)
      as.character(z$content), character(1)), ignore.case = TRUE)))
      return("{\"decision\":\"include\",\"criterion\":null,\"reason\":\"ok\",\"quote\":null}")
    "{\"revenue\":45.2,\"revenue__quote\":\"Revenue was 45.2 million dollars.\"}"
  })
  x <- suppressWarnings(suppressMessages(gr_extract(recs, p, recipe = "fast", client = cl)))
  expect_identical(sort(x$summary$identity), c(FALSE, TRUE, TRUE))
  bare <- x
  bare$summary$identity <- NULL
  expect_identical(gr_flow(extraction = x), gr_flow(extraction = bare))
  f <- tempfile(fileext = ".html")
  suppressWarnings(suppressMessages(gr_audit_report(f, extraction = x, open = FALSE)))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "<b>extraction:</b> 2 of 3 document(s)", fixed = TRUE)
})

test_that("a run without records keeps its columns, and a store keeps the check", {
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  a <- tempfile(fileext = ".txt"); writeLines("Revenue was 45.2 million.", a)
  out <- suppressMessages(gr_read_many(a, "What was revenue?", "fast", client = cl))
  expect_null(out$summary$identity)

  recs <- identity_corpus()
  store <- tempfile("store")
  first <- suppressWarnings(suppressMessages(
    gr_read_many(recs, "What was revenue?", "fast", client = cl, store = store)))
  again <- suppressMessages(gr_read_many(recs, "What was revenue?", "fast", client = cl,
                                         store = store))
  expect_true(all(again$summary$status == "restored"))
  expect_identical(again$summary$identity, first$summary$identity)
})

test_that("a DOI counts only as a whole DOI", {
  ri <- harnessr:::record_identity
  title <- "Spaced practice and long-term retention in adults: a randomised trial"
  body <- strrep("Lorem ipsum. ", 50)
  # Another paper in the same DOI series: the record's DOI is a prefix of it.
  expect_false(ri(paste("Other paper entirely about sleep\ndoi:10.1000/sp12", body),
                  title, "10.1000/sp1"))
  expect_true(is.na(ri(paste("doi:10.1000/sp1.5", body), NA, "10.1000/sp1")))
  expect_true(is.na(ri(paste("doi:10.7554/eLife.12345", body), NA, "10.7554/eLife.1234")))
  # The DOI itself, at the end of a sentence, in brackets or in an address.
  expect_true(ri(paste("See doi:10.1000/sp1.", body), NA, "10.1000/sp1"))
  expect_true(ri(paste("(https://doi.org/10.1000/SP1)", body), NA, "10.1000/sp1"))
  expect_true(ri(paste("doi.org/10.1000/sp1\nJ. Smith", body), NA, "10.1000/sp1"))
  # A DOI with characters a pattern would read as special.
  expect_true(ri("doi: 10.1002/(SICI)1097-0258(1998)17:8 and more", NA,
                 "10.1002/(sici)1097-0258(1998)17:8"))
})

test_that("HTML markup in a record title is taken out before the comparison", {
  ri <- harnessr:::record_identity
  ris <- tempfile(fileext = ".ris")
  writeLines(c("TY  - JOUR", "AU  - Smith, J.",
               "TI  - Growth of <i>Escherichia coli</i> in cold storage", "PY  - 2019",
               "ER  - "), ris)
  r <- gr_records(ris)
  expect_match(r$records$title, "<i>", fixed = TRUE)
  page <- "Growth of Escherichia coli in cold storage\nJ Smith\nAbstract ..."
  expect_true(ri(page, r$records$title, NA))
  expect_true(ri("Diet & exercise in older adults trial", "Diet &amp; exercise in older adults trial",
                 NA))
  expect_false(ri("Sleep and memory consolidation in students", r$records$title, NA))
})

test_that("after remove_numbers the title is compared without its digits", {
  ri <- harnessr:::record_identity
  title <- "COVID-19 vaccination uptake in 2021 among older adults"
  stripped <- gsub("\\d+", " ", paste(title, "doi:10.1000/cv19", sep = "\n"))
  expect_false(ri(stripped, title, "10.1000/cv19"))
  expect_true(ri(stripped, title, "10.1000/cv19", digits = FALSE))
  expect_false(ri("Sleep and memory in students", title, "10.1000/cv19", digits = FALSE))

  d <- tempfile("idl"); dir.create(d)
  writeLines(c(title, "doi:10.1000/cv19", "J. Smith", "Revenue was 45.2 million dollars."),
             file.path(d, "Smith 2021.txt"))
  writeLines(c("Spaced practice and long-term retention", "https://doi.org/10.1000/sp1",
               "A. Okafor", "Revenue was 45.2 million dollars."), file.path(d, "Okafor 2019.txt"))
  ris <- tempfile(fileext = ".ris")
  writeLines(c("TY  - JOUR", "AU  - Smith, J.", paste("TI  -", title), "PY  - 2021",
               "DO  - 10.1000/cv19", "ER  - ",
               "TY  - JOUR", "AU  - Okafor, A.", "TI  - Spaced practice and long-term retention",
               "PY  - 2019", "DO  - 10.1000/sp1", "ER  - "), ris)
  recs <- gr_records(ris, files = d)
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  for (rc in c("fast", "legacy")) {
    expect_no_warning(out <- suppressMessages(gr_read_many(recs, "What was revenue?", rc,
                                                           client = cl)),
                      class = "gr_identity_mismatch")
    expect_identical(out$summary$identity, c(TRUE, TRUE), info = rc)
  }
})

test_that("a run without records drops the check from rows a records run stored", {
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  recs <- identity_corpus()
  store <- tempfile("store")
  first <- suppressWarnings(suppressMessages(
    gr_read_many(recs, "What was revenue?", "fast", client = cl, store = store)))
  expect_false(is.null(first$summary$identity))
  new <- tempfile(fileext = ".txt"); writeLines("Revenue was 45.2 million dollars.", new)
  out <- suppressMessages(gr_read_many(c(recs$records$file, new), "What was revenue?", "fast",
                                       client = cl, store = store))
  expect_identical(nrow(out$summary), 4L)
  expect_identical(sum(out$summary$status == "restored"), 3L)
  expect_null(out$summary$identity)
  expect_identical(names(out$summary), names(
    suppressMessages(gr_read_many(new, "What was revenue?", "fast", client = cl))$summary))
})

test_that("the mismatch message names what was looked for", {
  cri <- harnessr:::check_record_identity
  page <- "Sleep and memory consolidation in students\nJ. Smith\nRevenue was 45.2 million."
  title <- "Spaced practice and long-term retention in adults"
  both <- attr(cri(page, list(title = title, doi = "10.1000/sp1"), "a.txt"), "message")
  expect_match(both, "has neither the record's title nor its DOI.", fixed = TRUE)
  no_doi <- attr(cri(page, list(title = title, doi = NA_character_), "a.txt"), "message")
  expect_match(no_doi, "does not have the record's title, and the record has no DOI.",
               fixed = TRUE)
  stripped <- attr(cri(page, list(title = title, doi = "10.1000/sp1"), "a.txt",
                       steps = "remove_numbers"), "message")
  expect_match(stripped, paste0("does not have the record's title (its DOI was not looked ",
                                "for, because the cleaning took the digits out)."), fixed = TRUE)
  for (m in c(both, no_doi, stripped)) {
    expect_match(m, "^'a.txt' may not be the paper its record names: the opening of its text")
    expect_false(grepl("neither the record's title.", m, fixed = TRUE) &&
                   !grepl(" nor ", m, fixed = TRUE))
  }
})

test_that("a restored row keeps its check only for the record it was checked against", {
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  recs <- identity_corpus()
  store <- tempfile("store")
  first <- suppressWarnings(suppressMessages(
    gr_read_many(recs, "What was revenue?", "fast", client = cl, store = store)))
  smith <- function(x) x$summary[x$summary$document == "Smith 2019.txt", ]
  expect_false(smith(first)$identity)

  # The same record set: the check and its warning are kept.
  same <- suppressMessages(gr_read_many(recs, "What was revenue?", "fast", client = cl,
                                        store = store))
  expect_true(all(same$summary$status == "restored"))
  expect_identical(same$summary$identity, first$summary$identity)
  expect_identical(same$summary$warnings, first$summary$warnings)

  # Another record set pairs the file with its right record: the stored FALSE
  # and its warning do not carry over, and a note says the check needs the
  # document read again.
  ris <- tempfile(fileext = ".ris")
  writeLines(c("TY  - JOUR", "AU  - Smith, J.",
               "TI  - Sleep and memory consolidation in students", "PY  - 2019", "ER  - "), ris)
  r2 <- gr_records(ris, files = dirname(recs$records$file[1]))
  expect_no_warning(other <- suppressMessages(gr_read_many(r2, "What was revenue?", "fast",
                                                           client = cl, store = store)))
  s <- smith(other)
  expect_identical(s$status, "restored")
  expect_true(is.na(s$identity))
  expect_false(grepl("may not be the paper", s$warnings, fixed = TRUE))
  expect_match(s$warnings, "needs the document read again", fixed = TRUE)
  # Read without the store, the check is made against this record.
  fresh <- suppressMessages(gr_read_many(r2, "What was revenue?", "fast", client = cl))
  expect_true(smith(fresh)$identity)

  # A run over the files alone drops the old warning with the column.
  files <- suppressMessages(gr_read_many(recs$records$file, "What was revenue?", "fast",
                                         client = cl, store = store))
  expect_null(files$summary$identity)
  expect_false(any(grepl("may not be the paper", files$summary$warnings, fixed = TRUE)))

  # An entry that does not say what it was checked against (one written
  # before the store kept it) restores with identity NA and the note.
  for (f in list.files(store, full.names = TRUE)) {
    e <- readRDS(f); e$identity_of <- NULL; saveRDS(e, f)
  }
  old <- suppressMessages(gr_read_many(recs, "What was revenue?", "fast", client = cl,
                                       store = store))
  expect_true(all(is.na(old$summary$identity)))
  expect_true(all(grepl("needs the document read again", old$summary$warnings, fixed = TRUE)))
  expect_false(any(grepl("may not be the paper", old$summary$warnings, fixed = TRUE)))
})
