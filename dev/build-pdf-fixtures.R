# build-pdf-fixtures.R: write the fixture PDFs the PDF golden records read.
#
# Run from the repository root, once, with pdftools installed:
#
#   Rscript dev/build-pdf-fixtures.R
#
# It draws three small PDFs with grDevices::pdf() into
# tests/testthat/fixtures/pdf/ and saves the text pdftools::pdf_text() reads
# from each page in pages.json beside them:
#
#   two-column.pdf     four pages in two columns under a running head, with
#                      page numbers, a title across both columns, a caption
#                      across both columns and two section headings.
#   single-column.pdf  three pages in one column with headings, a word
#                      hyphenated across a page break and a small table.
#   mixed.pdf          a full-width abstract above two columns, then a page
#                      that is mostly a table.
#
# The layout record in helper-golden.R reads pages.json, so it runs without
# pdftools; the read record reads the PDFs and needs it. Rebuilding the PDFs
# changes both inputs, so do it only to add a case, then rerun
# dev/record-golden.R and say why in the commit.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "testthat"))) {
  stop("Run this from the repository root: Rscript dev/build-pdf-fixtures.R", call. = FALSE)
}
for (p in c("pdftools", "jsonlite")) {
  if (!requireNamespace(p, quietly = TRUE)) stop(sprintf("Package '%s' is needed.", p), call. = FALSE)
}
dir <- file.path("tests", "testthat", "fixtures", "pdf")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)

page <- function() {
  graphics::plot.new()
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.window(c(0, 1), c(0, 1))
}
lines_at <- function(x, y0, txt, cex = 0.8, step = 0.02) {
  graphics::text(x, y0 - (seq_along(txt) - 1) * step, txt, adj = 0, cex = cex)
}

draw <- function(name, fn) {
  f <- file.path(dir, paste0(name, ".pdf"))
  grDevices::pdf(f, width = 8.5, height = 11, title = name, useDingbats = FALSE,
                 compress = TRUE)
  fn()
  invisible(grDevices::dev.off())
  f
}

two_column <- function() {
  for (pg in 1:4) {
    page()
    graphics::text(0.05, 0.97, "Journal of Learning Studies, vol. 12", adj = 0, cex = 0.8)
    y <- 0.88
    if (pg == 1) {
      graphics::text(0.05, 0.93, "Spacing and Retention in Adult Learners: A Randomised Trial",
                     adj = 0, cex = 1)
      graphics::text(0.05, 0.90, "Introduction", adj = 0)
      y <- 0.86
    }
    if (pg == 3) graphics::text(0.05, 0.92, "2. Methods", adj = 0)
    lines_at(0.05, y, sprintf("Left %d.%d: the spacing effect was studied in adults.", pg, 1:6))
    lines_at(0.55, y, sprintf("Right %d.%d: retention fell when practice was massed.", pg, 1:6))
    if (pg == 2) {
      graphics::text(0.05, 0.70, paste("Figure 1. Retention after one week, by schedule, for",
                                       "all 482 participants across the nine sites."),
                     adj = 0, cex = 0.8)
      lines_at(0.05, 0.66, sprintf("Left %d.%d: spaced sessions were a week apart.", pg, 7:10))
      lines_at(0.55, 0.66, sprintf("Right %d.%d: massed sessions were on one day.", pg, 7:10))
    }
    graphics::text(0.5, 0.03, as.character(pg), cex = 0.8)
  }
}

single_column <- function() {
  body <- c("Revenue was 45.2 million dollars in fiscal 2024, up from 41.0 million.",
            "The north region grew fastest, at 12.5 percent, while the south held level.",
            "Costs rose by 3.1 million dollars, most of it in staff and premises.")
  page()
  graphics::text(0.05, 0.95, "Annual Report 2024", adj = 0, cex = 1.2)
  graphics::text(0.05, 0.90, "Abstract", adj = 0)
  lines_at(0.05, 0.86, body, cex = 0.9, step = 0.025)
  graphics::text(0.05, 0.76, "Results", adj = 0)
  lines_at(0.05, 0.72, c(body[2:3], "The board approved a new multi-"), cex = 0.9, step = 0.025)
  graphics::text(0.5, 0.03, "Page 1 of 3", cex = 0.8)
  page()
  lines_at(0.05, 0.95, c("component plan for the coming year, phased over three quarters.",
                         body[1]), cex = 0.9, step = 0.025)
  graphics::text(0.05, 0.85, "Table 1. Revenue by region, in millions of dollars", adj = 0, cex = 0.9)
  rows <- list(c("Region", "2023", "2024"), c("North", "12.1", "13.6"),
               c("South", "15.0", "15.1"), c("East", "13.9", "16.5"))
  for (i in seq_along(rows)) {
    y <- 0.81 - (i - 1) * 0.025
    graphics::text(c(0.05, 0.40, 0.60), y, rows[[i]], adj = 0, cex = 0.9)
  }
  graphics::text(0.5, 0.03, "Page 2 of 3", cex = 0.8)
  page()
  graphics::text(0.05, 0.95, "Discussion", adj = 0)
  lines_at(0.05, 0.91, rev(body), cex = 0.9, step = 0.025)
  graphics::text(0.5, 0.03, "Page 3 of 3", cex = 0.8)
}

mixed <- function() {
  page()
  graphics::text(0.05, 0.95, "Abstract", adj = 0)
  lines_at(0.05, 0.91, rep(paste("The cohort comprised 482 participants recruited across nine",
                                 "clinical sites, and adherence exceeded 91 percent overall."), 3),
           cex = 0.8)
  lines_at(0.05, 0.82, sprintf("Left %d: participants were randomised by site.", 1:8))
  lines_at(0.55, 0.82, sprintf("Right %d: outcomes were assessed blind.", 1:8))
  page()
  graphics::text(0.05, 0.95, "Results", adj = 0)
  for (i in 1:12) {
    graphics::text(c(0.05, 0.55), 0.91 - (i - 1) * 0.02,
                   c(sprintf("Site %d, clinic %s", i, LETTERS[i]),
                     sprintf("%d participants", 40 + i)), adj = 0, cex = 0.8)
  }
}

files <- c(`two-column` = draw("two-column", two_column),
           `single-column` = draw("single-column", single_column),
           mixed = draw("mixed", mixed))
pages <- lapply(files, function(f) enc2utf8(pdftools::pdf_text(f)))
json <- jsonlite::toJSON(pages, auto_unbox = FALSE, pretty = TRUE)
writeBin(charToRaw(paste0(enc2utf8(as.character(json)), "\n")), file.path(dir, "pages.json"))
cat(sprintf("%s: %d page(s), %.1f KB\n", names(files), lengths(pages),
            file.size(files) / 1024), sep = "")
cat(sprintf("Wrote %s\n", dir))
