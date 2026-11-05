# The options that carried the old package name, readgpt.api_key and
# readgpt.allow_local_urls, are still read when their harnessr names are not
# set, with one warning per session. The new name wins when both are set.

test_that("a readgpt.* option is read when the harnessr.* one is not, with one warning", {
  harnessr:::.warn_once_reset()
  withr::defer(harnessr:::.warn_once_reset())
  withr::local_envvar(OPENAI_API_KEY = NA)
  withr::local_options(harnessr.api_key = NULL, readgpt.api_key = "sk-old-name")

  w <- expect_warning(k <- gr_api_key(), class = "gr_deprecated")
  expect_identical(k, "sk-old-name")
  expect_match(conditionMessage(w), "options(harnessr.api_key =)", fixed = TRUE)
  # Once per session: the second read is quiet.
  expect_no_warning(expect_identical(gr_api_key(), "sk-old-name"))

  # The new name wins, and reading it says nothing.
  harnessr:::.warn_once_reset()
  withr::local_options(harnessr.api_key = "sk-new-name")
  expect_no_warning(expect_identical(gr_api_key(), "sk-new-name"))

  # The URL option goes through the same fallback.
  withr::local_options(harnessr.allow_local_urls = NULL, readgpt.allow_local_urls = TRUE)
  expect_warning(v <- harnessr:::renamed_option("harnessr.allow_local_urls",
                                                "readgpt.allow_local_urls"),
                 "options(harnessr.allow_local_urls =)", fixed = TRUE)
  expect_true(v)
  withr::local_options(readgpt.allow_local_urls = NULL)
  expect_null(harnessr:::renamed_option("harnessr.allow_local_urls", "readgpt.allow_local_urls"))
})
