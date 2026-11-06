# readgpt_example() is the name gr_example() had before the package was
# renamed. It still returns the same path, with one warning per session.

test_that("readgpt_example() returns gr_example()'s path and warns once", {
  harnessr:::.warn_once_reset()
  withr::defer(harnessr:::.warn_once_reset())

  w <- expect_warning(old <- readgpt_example(), class = "gr_deprecated")
  expect_match(conditionMessage(w), "gr_example()", fixed = TRUE)
  expect_identical(old, gr_example())
  expect_true(file.exists(old))

  # Once per session: the second call is quiet and still agrees.
  expect_no_warning(expect_identical(readgpt_example(), gr_example()))
})
