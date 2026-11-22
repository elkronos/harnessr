# test-contract-files.R: CONTRACT.md and NOTES-primitives.md match the code.
#
# Both files are at the repository root and are not part of the built
# package, so these tests run from the source tree (run-tests.sh, the tests
# workflow) and skip under R CMD check.

root_file <- function(name) {
  path <- test_path("..", "..", name)
  skip_if_not(file.exists(path), sprintf("%s is not in an installed package", name))
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

test_that("CONTRACT.md names the version hr_contract_version() returns", {
  txt <- root_file("CONTRACT.md")
  line <- grep("^\\*\\*Current version: [0-9]+[.][0-9]+\\*\\*$", txt, value = TRUE)
  expect_length(line, 1L)
  expect_identical(sub("^\\*\\*Current version: ([0-9.]+)\\*\\*$", "\\1", line),
                   harnessr:::hr_contract_version())
  # The changelog has an entry for the current version.
  expect_true(any(grepl(sprintf("^### %s ", harnessr:::hr_contract_version()), txt)))
})

test_that("NOTES-primitives.md lists every exported hr_ function, and only those", {
  txt <- root_file("NOTES-primitives.md")
  rows <- grep("^\\| `hr_[A-Za-z0-9_.]+\\(\\)` \\|", txt, value = TRUE)
  listed <- sub("^\\| `(hr_[A-Za-z0-9_.]+)\\(\\)`.*$", "\\1", rows)
  exported <- grep("^hr_", getNamespaceExports("harnessr"), value = TRUE)
  expect_identical(anyDuplicated(listed), 0L)
  missing <- setdiff(exported, listed)
  extra <- setdiff(listed, exported)
  expect(length(missing) == 0,
         sprintf("Exported but not in NOTES-primitives.md: %s. Name a caller for each.",
                 paste(missing, collapse = ", ")))
  expect(length(extra) == 0,
         sprintf("In NOTES-primitives.md but not exported: %s.", paste(extra, collapse = ", ")))
})
