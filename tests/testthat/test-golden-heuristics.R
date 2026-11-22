# test-golden-heuristics.R: the numeral parser and the PDF layout pass do
# today what they did when the fixtures were recorded.
#
# fixtures/golden-heuristics/ holds three records (see helper-golden.R):
# every number quote_numbers() reads from a corpus of numeral strings, the
# layout pass on the page text of the fixture PDFs, and the fixture PDFs read
# end to end. Any difference fails and names the fields that changed. When a
# change is intended, run `Rscript dev/record-golden.R` from the repository
# root and say in the commit message what changed and why.

heuristics_skip <- function(needs = golden_needs) {
  for (p in needs) {
    skip_if_not(requireNamespace(p, quietly = TRUE), sprintf("needs the '%s' package", p))
  }
}

heuristics_compare <- function(nm, now) {
  path <- file.path(golden_heuristics_dir(), paste0(nm, ".json"))
  if (!file.exists(path)) {
    fail(sprintf("No fixture %s; run dev/record-golden.R.", basename(path)))
    return(invisible())
  }
  d <- golden_diff(golden_read(path), golden_roundtrip(now), path = nm)
  expect(length(d) == 0L, paste0(
    "Golden record '", nm, "' changed (fixture -> now):\n  ", paste(d, collapse = "\n  "),
    "\nIf the change is intended, run `Rscript dev/record-golden.R` and say why in the commit."))
}

test_that("the heuristic fixtures are all there, and the corpus covers each kind of numeral", {
  heuristics_skip()
  on_disk <- sub("\\.json$", "", list.files(golden_heuristics_dir(), pattern = "\\.json$"))
  expect_setequal(on_disk, c("numerals", "pdf-layout", "pdf-read"))
  expect_setequal(names(golden_pdf_pages()), c("two-column", "single-column", "mixed"))
  for (nm in names(golden_pdf_pages())) {
    expect_true(file.exists(file.path(golden_pdf_dir(), paste0(nm, ".pdf"))), info = nm)
  }
  corpus <- golden_numeral_corpus
  expect_identical(anyDuplicated(corpus), 0L)
  expect_true(any(grepl("[0-9],[0-9]{3}", corpus)))            # thousands
  expect_true(any(grepl("[0-9][.][0-9]", corpus)))             # decimals
  expect_true(any(grepl("[0-9]\u2013[0-9]", corpus)))          # ranges
  expect_true(any(grepl("^[-\u2212]", corpus)))                # negatives
  expect_true(any(grepl("%", corpus, fixed = TRUE)))           # percentages
  expect_true(any(grepl("[$\u00a3\u20ac\u00a5]", corpus)))     # currencies
  expect_true(any(grepl("^[a-z -]+$", corpus)))                # words
  expect_true(any(grepl("[0-9],[0-9](?![0-9])", corpus, perl = TRUE)))  # decimal comma
})

test_that("golden record 'numerals' is unchanged", {
  heuristics_skip()
  heuristics_compare("numerals", golden_numerals())
})

test_that("golden record 'pdf-layout' is unchanged", {
  heuristics_skip()
  heuristics_compare("pdf-layout", golden_pdf_layout())
})

test_that("golden record 'pdf-read' is unchanged", {
  heuristics_skip(c(golden_needs, "pdftools"))
  now <- golden_pdf_read()
  # A pdftools built on another poppler can lay a page out differently, and
  # then the blocks differ for that reason alone. pdf-layout still checks the
  # layout pass on the text the fixtures were built from.
  same <- vapply(now, function(r) r$pages_as_built, logical(1))
  skip_if(!all(same), sprintf(paste("this pdftools reads %s differently from the one that",
                                    "built the fixtures"),
                              paste(names(now)[!same], collapse = ", ")))
  heuristics_compare("pdf-read", now)
})

test_that("the heuristic records are the same twice in one session", {
  heuristics_skip()
  expect_identical(golden_roundtrip(golden_numerals()), golden_roundtrip(golden_numerals()))
  expect_identical(golden_roundtrip(golden_pdf_layout()), golden_roundtrip(golden_pdf_layout()))
})
