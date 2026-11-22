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
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
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
  cl <- gr_mock_client(function(m, p) {
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
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
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
