# doc-ingest-example.R: the example document that ships with the package.


#' Path to the bundled example document
#'
#' A short Markdown report with headings, figures and dates, used by the
#' examples in this package so they run without an API key or a file of your
#' own.
#'
#' @return Absolute path to the file.
#' @export
#' @examples
#' gr_ingest(readgpt_example())
readgpt_example <- function() {
  system.file("extdata", "annual_report.md", package = "harnessr", mustWork = TRUE)
}
