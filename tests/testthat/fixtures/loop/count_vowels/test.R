test_that("every vowel is counted", {
  expect_equal(count_vowels("education"), 5)
})
test_that("a word with no vowels counts zero", {
  expect_equal(count_vowels("rhythm"), 0)
})
