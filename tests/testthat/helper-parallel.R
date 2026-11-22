# helper-parallel.R: the skip shared by the tests of parallel runs.
#
# test-parallel.R defined this for itself; a helper file is where testthat
# lets every test file see it.

skip_if_no_future <- function() {
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")
}
