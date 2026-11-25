# The audit header gives each stage's run time and version from its own
# trace, and the caveats say what each check looks at.

header_extraction <- function() {
  fields <- gr_fields(design = "The study design")
  cl <- hr_mock_client(function(m, p) {
    '{"design":"randomised trial","design__quote":"We ran a randomised trial."}'
  })
  f <- tempfile(fileext = ".txt"); writeLines("We ran a randomised trial.", f)
  suppressMessages(gr_extract(f, fields, client = cl))
}

report_html <- function(...) {
  out <- tempfile(fileext = ".html")
  suppressMessages(gr_audit_report(out, ..., open = FALSE))
  paste(readLines(out, warn = FALSE), collapse = "\n")
}

test_that("each stage's run time and version come from its trace, not the report", {
  x <- header_extraction()
  version <- as.character(utils::packageVersion("harnessr"))
  html <- report_html(extraction = x)
  expect_match(html, "Stages run: extracted. Report written ", fixed = TRUE)
  expect_match(html, sprintf("<td>extraction</td><td>%s</td><td>%s</td>",
                             format(x$trace$started, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
                             version), fixed = TRUE)
  expect_false(grepl("ran on a harnessr version other than", html, fixed = TRUE))

  # A run made a year earlier by another version says so, and is flagged.
  x$trace$started <- as.POSIXct("2025-01-02 03:04:05", tz = "UTC")
  x$trace$meta$readgpt <- "0.5.0"
  html <- report_html(extraction = x)
  expect_match(html, "<td>extraction</td><td>2025-01-02 03:04:05 UTC</td><td><span class='flag'>0.5.0</span></td>",
               fixed = TRUE)
  expect_match(html, "extraction ran on a harnessr version other than this report's",
               fixed = TRUE)

  # A stage saved without a trace has nothing to show, and says so.
  x$trace <- NULL
  html <- report_html(extraction = x)
  expect_match(html, "<td>extraction</td><td>not recorded</td><td>not recorded</td>",
               fixed = TRUE)
})

test_that("the caveats say what each check looks at", {
  html <- report_html(extraction = header_extraction())
  expect_match(html, "What each check looks at.", fixed = TRUE)
  expect_match(html, "<li>Quote: the quoted sentence occurs in the chunk", fixed = TRUE)
  expect_match(html, "<li>Value (<code>n_unverified</code>", fixed = TRUE)
  expect_false(grepl("<li>Figure:", html, fixed = TRUE))
  cav <- paste(harnessr:::audit_caveats(values = FALSE, written = TRUE), collapse = "\n")
  expect_match(cav, "<li>Citation: each <code>[study n]</code> names a row", fixed = TRUE)
  expect_match(cav, "<li>Figure: each figure in the write-up is found", fixed = TRUE)
  # An answer alone keeps the caveats it had.
  expect_false(grepl("What each check looks at",
                     paste(harnessr:::audit_caveats(screening = FALSE, answer = TRUE),
                           collapse = "\n"), fixed = TRUE))
})
