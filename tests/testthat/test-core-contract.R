# test-core-contract.R: hr_check_module(), which runs a module once and
# reports which of a list of rules it breaks.

halve <- function(x) x / 2

test_that("a module that passes every rule is reported as passing", {
  res <- hr_check_module(halve, function() halve(8),
                         rules = list(numeric = function(v) is.numeric(v),
                                      four = function(v) list(ok = v == 4, detail = "checked")),
                         kind = "function", name = "halve")
  expect_s3_class(res, "hr_conformance")
  expect_s3_class(res, "data.frame")
  expect_identical(names(res), c("rule", "ok", "detail"))
  expect_identical(res$rule, c("is_function", "runs", "numeric", "four"))
  expect_true(all(res$ok))
  expect_identical(res$detail[4], "checked")
  expect_identical(attr(res, "kind"), "function")
  expect_identical(attr(res, "name"), "halve")
  expect_identical(attr(res, "contract"), harnessr:::hr_contract_version())
  expect_identical(attr(res, "warnings"), character(0))
})

test_that("a module that errors fails `runs` and its rules are not checked", {
  broken <- function(x) stop("no input today")
  res <- hr_check_module(broken, function() broken(1),
                         rules = list(numeric = function(v) is.numeric(v)))
  expect_false(res$ok[res$rule == "runs"])
  expect_match(res$detail[res$rule == "runs"], "no input today")
  expect_true(is.na(res$ok[res$rule == "numeric"]))
  expect_match(res$detail[res$rule == "numeric"], "not checked")
})

test_that("a module that breaks a rule is reported, with the rule's detail", {
  res <- hr_check_module(halve, function() halve(3),
                         rules = list(whole = function(v) list(ok = v == round(v),
                                                               detail = sprintf("got %s", v)),
                                      positive = function(v) v > 0))
  expect_identical(res$ok, c(TRUE, TRUE, FALSE, TRUE))
  expect_identical(res$detail[3], "got 1.5")
})

test_that("warnings are kept, a rule that errors fails, and NA means not checked", {
  noisy <- function() {
    warning("first")
    warning("second")
    1
  }
  res <- expect_silent(hr_check_module(noisy, noisy, rules = list(
    raises = function(v) stop("rule broke"),
    unsure = function(v) NA,
    shape = function(v) c(TRUE, TRUE))))
  expect_identical(attr(res, "warnings"), c("first", "second"))
  expect_false(res$ok[res$rule == "raises"])
  expect_match(res$detail[res$rule == "raises"], "rule broke")
  expect_true(is.na(res$ok[res$rule == "unsure"]))
  expect_identical(res$detail[res$rule == "unsure"], "not checked")
  expect_false(res$ok[res$rule == "shape"])
})

test_that("an object that is not a function fails `is_function`", {
  res <- hr_check_module("halve", function() 1)
  expect_false(res$ok[1])
  expect_match(res$detail[1], "character")
  expect_true(res$ok[2])
})

test_that("the module runs in a temporary directory that is removed", {
  where <- NULL
  res <- hr_check_module(halve, function() {
    where <<- getwd()
    writeLines("x", "scratch.txt")
    TRUE
  })
  expect_true(all(res$ok))
  expect_false(identical(where, getwd()))
  expect_false(dir.exists(where))
  expect_false(file.exists("scratch.txt"))
})

test_that("bad arguments are refused", {
  expect_error(hr_check_module(halve, "not a function"), class = "gr_bad_setting")
  expect_error(hr_check_module(halve, function() 1, rules = list(function(v) TRUE)),
               class = "gr_bad_setting")
  expect_error(hr_check_module(halve, function() 1, rules = list(a = TRUE)),
               class = "gr_bad_setting")
})

test_that("print lists broken rules first and says when every rule passes", {
  pass <- hr_check_module(halve, function() halve(8), rules = list(numeric = is.numeric),
                          kind = "function", name = "halve")
  out <- capture.output(print(pass))
  expect_match(out[1], "function 'halve', contract", fixed = TRUE)
  expect_match(out[2], "passes all 3 rules", fixed = TRUE)

  fail <- hr_check_module(halve, function() halve(3), rules = list(
    numeric = is.numeric,
    whole = function(v) list(ok = v == round(v), detail = "got 1.5"),
    unsure = function(v) NA))
  out <- capture.output(print(fail))
  expect_match(out[2], "fails 1 of 5 rules", fixed = TRUE)
  expect_match(out[3], "FAIL  whole: got 1.5", fixed = TRUE)
  expect_match(out[4], "skip  unsure: not checked", fixed = TRUE)
  expect_match(out[5], "ok    is_function", fixed = TRUE)

  partly <- hr_check_module(halve, function() 1, rules = list(unsure = function(v) NA))
  expect_match(capture.output(print(partly))[2], "passes all 2 rules checked; 1 not checked",
               fixed = TRUE)
  capture.output(vis <- withVisible(print(pass)))
  expect_false(vis$visible)
})
