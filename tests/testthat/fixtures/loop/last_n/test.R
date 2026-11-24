test_that("the last two elements are returned", {
  expect_equal(last_n(1:5, 2), 4:5)
})
test_that("asking for every element returns them all", {
  expect_equal(last_n(1:3, 3), 1:3)
})
