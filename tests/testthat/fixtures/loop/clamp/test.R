test_that("a value above the range is moved to its top", {
  expect_equal(clamp(5, 0, 3), 3)
})
test_that("a value inside the range is kept", {
  expect_equal(clamp(2, 0, 3), 2)
})
