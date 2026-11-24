# test-step-rules.R: the core's rules for a step or a chain, used with
# hr_check_module().

test_that("a document chain passes the step rules", {
  local_clean_cache()
  cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  chain <- hr_chain(segment = gr_step("segment"), read = gr_step("read", reader = "stuff"),
                    name = "plain")
  rules <- harnessr:::hr_rules_step(chain)
  expect_identical(names(rules), c("returns_value", "declared_output", "held_attached"))
  item <- list(question = "What was revenue?", document = gr_example())
  res <- quiet(hr_check_module(chain$run, function() chain$run(item, list(client = cl)),
                               rules = rules, kind = "chain", name = "plain"))
  expect_true(all(res$ok[1:4]), info = paste(res$rule, res$detail, collapse = "; "))
  expect_identical(res$detail[res$rule == "declared_output"], "")
  expect_true(is.na(res$ok[res$rule == "held_attached"]))
})

test_that("a step that returns what it did not declare is reported", {
  liar <- hr_step("liar", function(input, ctx) list(text = input), input = "document",
                  output = "chunks")
  res <- hr_check_module(liar, function() liar("Some text.", list()),
                         rules = harnessr:::hr_rules_step(liar))
  expect_false(res$ok[res$rule == "declared_output"])
  expect_match(res$detail[res$rule == "declared_output"], "declared \"chunks\"", fixed = TRUE)

  quiet_step <- hr_step("quiet", function(input, ctx) NULL)
  res <- hr_check_module(quiet_step, function() quiet_step(1, list()),
                         rules = harnessr:::hr_rules_step(quiet_step))
  expect_false(res$ok[res$rule == "returns_value"])
  expect_true(is.na(res$ok[res$rule == "declared_output"]))
})

test_that("a chain whose held step leaves no result is reported", {
  held <- hr_step_command("held", c("Rscript", "-e", "invisible(0)"), held = TRUE)
  chain <- hr_chain(draft = hr_step("draft", function(input, ctx) list(code = "x")),
                    held = held, name = "held-chain")
  rules <- harnessr:::hr_rules_step(chain)
  expect_true(rules$held_attached(chain$run(list(), list()))$ok)
  detail <- rules$held_attached(list(code = "x"))
  expect_false(detail$ok)
  expect_match(detail$detail, "'held'", fixed = TRUE)
  expect_error(harnessr:::hr_rules_step(function(x) x), class = "gr_bad_setting")
})
