test_that("the sum is returned", {
  expect_equal(slow_sum(1:4), 10)
})
test_that("an empty vector sums to zero", {
  expect_equal(slow_sum(integer(0)), 0)
})
