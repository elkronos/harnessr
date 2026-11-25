# test-skill.R: hr_skill(), a skill folder a person chooses for a step.
#
# Every skill folder is written under tempdir() by the test that uses it.

skill_dir <- function(header = c("name: units", "description: Give amounts with units.",
                                 "version: 1.0.0"),
                      body = "Always state the unit of every amount.",
                      refs = list(), scripts = list()) {
  dir <- tempfile("hr-skill-")
  dir.create(dir)
  writeLines(c("---", header, "---", body), file.path(dir, "SKILL.md"))
  if (length(refs)) dir.create(file.path(dir, "references"))
  for (n in names(refs)) writeLines(refs[[n]], file.path(dir, "references", n))
  if (length(scripts)) dir.create(file.path(dir, "scripts"))
  for (n in names(scripts)) writeLines(scripts[[n]], file.path(dir, "scripts", n))
  dir
}

skill_chain <- function(skill = NULL, name = "c") {
  ask <- hr_step("ask", function(input, ctx) ctx$call(input$question)$text, skill = skill)
  hr_chain(ask = ask, name = name)
}

skill_ref <- function() {
  hr_reference(list(q1 = list(question = "What was revenue?")),
               labels = "45.2 million", cluster = "a", split = "test")
}

test_that("a skill folder is read into its header, instructions, references and scripts", {
  dir <- skill_dir(refs = list(b.md = "Second.", a.md = "First."),
                   scripts = list(check.R = "quit(status = 0)"))
  on.exit(unlink(dir, recursive = TRUE))
  s <- hr_skill(dir)
  expect_s3_class(s, "hr_skill")
  expect_identical(s$name, "units")
  expect_identical(s$description, "Give amounts with units.")
  expect_identical(s$version, "1.0.0")
  expect_identical(s$instructions, "Always state the unit of every amount.")
  expect_identical(s$references, c(a.md = "First.\n", b.md = "Second.\n"))
  expect_identical(names(s$scripts), "check.R")
  expect_true(file.exists(s$scripts[["check.R"]]))
  expect_match(s$hash, "^[0-9a-f]{64}$")
  expect_output(print(s), "<hr_skill> units version 1.0.0")
  expect_output(print(s), "never run")
})

test_that("the header is read without a YAML parser and refuses what it cannot read", {
  quoted <- skill_dir(header = c("name: \"units\"", "description: 'Say: units.'",
                                 "version: \"2\""))
  on.exit(unlink(quoted, recursive = TRUE), add = TRUE)
  s <- hr_skill(quoted)
  expect_identical(s$name, "units")
  expect_identical(s$description, "Say: units.")
  expect_identical(s$version, "2")
  # A quote only at one end is kept.
  half <- skill_dir(header = c("name: units", "description: \"half"))
  on.exit(unlink(half, recursive = TRUE), add = TRUE)
  expect_identical(hr_skill(half)$description, "\"half")
  expect_null(hr_skill(half)$version)

  nested <- skill_dir(header = c("name: units", "metadata:", "  owner: me"))
  on.exit(unlink(nested, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(nested), "nested or indented", class = "hr_bad_skill")
  multi <- skill_dir(header = c("name: units", "description: |"))
  on.exit(unlink(multi, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(multi), "spread over lines", class = "hr_bad_skill")
  folded <- skill_dir(header = c("name: units", "description: >-"))
  on.exit(unlink(folded, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(folded), class = "hr_bad_skill")
  noname <- skill_dir(header = "description: no name")
  on.exit(unlink(noname, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(noname), "needs a `name`", class = "hr_bad_skill")
  blank <- skill_dir(header = "name: \"\"")
  on.exit(unlink(blank, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(blank), "needs a `name`", class = "hr_bad_skill")
  twice <- skill_dir(header = c("name: a", "name: b"))
  on.exit(unlink(twice, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(twice), "twice", class = "hr_bad_skill")
  empty <- skill_dir(body = "")
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(empty), "no instructions", class = "hr_bad_skill")

  unknown <- skill_dir(header = c("name: units", "license: MIT", "allowed-tools: Bash"))
  on.exit(unlink(unknown, recursive = TRUE), add = TRUE)
  expect_warning(s <- hr_skill(unknown), "'license', 'allowed-tools'",
                 class = "hr_skill_unknown_key")
  expect_identical(s$name, "units")

  open <- tempfile("hr-skill-")
  dir.create(open)
  on.exit(unlink(open, recursive = TRUE), add = TRUE)
  writeLines(c("---", "name: units", "Always state the unit."), file.path(open, "SKILL.md"))
  expect_error(hr_skill(open), "no closing", class = "hr_bad_skill")
  writeLines(c("name: units", "---", "Always."), file.path(open, "SKILL.md"))
  expect_error(hr_skill(open), "must start", class = "hr_bad_skill")
  writeLines(c("--- ", "name: units", "---", "Always."), file.path(open, "SKILL.md"))
  expect_error(hr_skill(open), "must start", class = "hr_bad_skill")
  # Windows line ends are read as the same lines.
  writeBin(charToRaw("---\r\nname: units\r\n---\r\nAlways.\r\n"), file.path(open, "SKILL.md"))
  expect_identical(hr_skill(open)$instructions, "Always.")
})

test_that("a missing folder, a file or a folder without SKILL.md is refused", {
  expect_error(hr_skill(file.path(tempdir(), "no-such-skill-folder")), class = "hr_bad_skill")
  expect_error(hr_skill(NA_character_), class = "hr_bad_skill")
  expect_error(hr_skill(c("a", "b")), class = "hr_bad_skill")
  f <- tempfile(fileext = ".md")
  writeLines("x", f)
  on.exit(unlink(f), add = TRUE)
  expect_error(hr_skill(f), "is a file", class = "hr_bad_skill")
  d <- tempfile("hr-skill-")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(d), "no SKILL.md", class = "hr_bad_skill")
})

test_that("nul bytes, oversized folders, too many files and outside links are refused", {
  dir <- skill_dir(refs = list(a.md = "fine"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeBin(as.raw(c(0x61, 0x00, 0x62)), file.path(dir, "references", "bin.md"))
  expect_error(hr_skill(dir), "nul byte", class = "hr_bad_skill")
  unlink(file.path(dir, "references", "bin.md"))
  writeBin(as.raw(c(0x61, 0xff, 0xfe)), file.path(dir, "references", "latin.md"))
  expect_error(hr_skill(dir), "not UTF-8", class = "hr_bad_skill")
  unlink(file.path(dir, "references", "latin.md"))
  expect_silent(hr_skill(dir))

  writeLines(strrep("x", 2e5), file.path(dir, "references", "big.md"))
  expect_error(hr_skill(dir), "more than 200,000 bytes", class = "hr_bad_skill")
  unlink(file.path(dir, "references", "big.md"))

  many <- skill_dir(refs = stats::setNames(as.list(rep("x", 51)), sprintf("r%02d.md", 1:51)))
  on.exit(unlink(many, recursive = TRUE), add = TRUE)
  expect_error(hr_skill(many), "51 files in references/", class = "hr_bad_skill")

  skip_on_os("windows")
  outside <- tempfile("hr-skill-secret-")
  writeLines("secret", outside)
  on.exit(unlink(outside), add = TRUE)
  linked <- skill_dir(refs = list(a.md = "fine"))
  on.exit(unlink(linked, recursive = TRUE), add = TRUE)
  expect_true(file.symlink(outside, file.path(linked, "references", "leak.md")))
  expect_error(hr_skill(linked), "outside the skill folder", class = "hr_bad_skill")
  # A link that stays inside the folder is read.
  unlink(file.path(linked, "references", "leak.md"))
  expect_true(file.symlink(file.path(linked, "references", "a.md"),
                           file.path(linked, "references", "same.md")))
  expect_identical(unname(hr_skill(linked)$references), c("fine\n", "fine\n"))
  # SKILL.md itself may not point outside either.
  out_md <- tempfile("hr-skill-md-", fileext = ".md")
  writeLines(c("---", "name: x", "---", "y"), out_md)
  on.exit(unlink(out_md), add = TRUE)
  bare <- tempfile("hr-skill-")
  dir.create(bare)
  on.exit(unlink(bare, recursive = TRUE), add = TRUE)
  expect_true(file.symlink(out_md, file.path(bare, "SKILL.md")))
  expect_error(hr_skill(bare), "outside the skill folder", class = "hr_bad_skill")
})

test_that("the hash changes with the instructions, a reference or a script byte", {
  dir <- skill_dir(refs = list(a.md = "First."), scripts = list(check.R = "x <- 1"))
  on.exit(unlink(dir, recursive = TRUE))
  h0 <- hr_skill(dir)$hash
  expect_identical(hr_skill(dir)$hash, h0)
  writeLines("First!", file.path(dir, "references", "a.md"))
  h1 <- hr_skill(dir)$hash
  expect_false(identical(h1, h0))
  writeLines("x <- 2", file.path(dir, "scripts", "check.R"))
  h2 <- hr_skill(dir)$hash
  expect_false(identical(h2, h1))
  writeLines(c("---", "name: units", "version: 1.0.0", "---", "Other words."),
             file.path(dir, "SKILL.md"))
  expect_false(identical(hr_skill(dir)$hash, h2))
  # The folder's place is not part of the hash.
  moved <- tempfile("hr-skill-moved-")
  dir.create(moved)
  on.exit(unlink(moved, recursive = TRUE), add = TRUE)
  file.copy(list.files(dir, full.names = TRUE), moved, recursive = TRUE)
  expect_identical(hr_skill(moved)$hash, hr_skill(dir)$hash)
})

test_that("a step with a skill has its hash in its settings, fingerprint and version", {
  dir <- skill_dir()
  on.exit(unlink(dir, recursive = TRUE))
  s <- hr_skill(dir)
  plain <- hr_step("ask", function(input, ctx) input)
  skilled <- hr_step("ask", function(input, ctx) input, skill = s)
  expect_identical(attr(skilled, "skill"), s)
  expect_identical(attr(skilled, "extras"), list(skill = s$hash))
  expect_identical(attr(skilled, "version"), "1.0.0")
  expect_identical(attr(plain, "version"), "0.0.1")
  expect_false(identical(attr(skilled, "fingerprint"), attr(plain, "fingerprint")))
  expect_output(print(skilled), "skill: units")
  expect_error(hr_step("ask", function(input, ctx) input, skill = "units"),
               class = "hr_bad_skill")
  # A skill without a version leaves the step's own.
  nover <- skill_dir(header = "name: units")
  on.exit(unlink(nover, recursive = TRUE), add = TRUE)
  expect_identical(attr(hr_step("ask", function(input, ctx) input, version = "3.0.0",
                                skill = hr_skill(nover)), "version"), "3.0.0")

  a <- skill_chain(NULL)
  b <- skill_chain(s)
  expect_false(identical(a$hash, b$hash))
  expect_false(identical(attr(a, "hr_config"), attr(b, "hr_config")))
  expect_identical(a$params, list())
  expect_identical(b$params, list(ask.skill = paste0("units@", substr(s$hash, 1, 12))))
  # The same skill read again gives the same chain.
  expect_identical(skill_chain(hr_skill(dir))$hash, b$hash)
})

test_that("the skill reaches the step's requests as a system message, and ctx$skill", {
  dir <- skill_dir(refs = list(style.md = "Write million in full."))
  on.exit(unlink(dir, recursive = TRUE))
  s <- hr_skill(dir)
  cl <- hr_mock_client(function(m, p) "45.2 million")
  seen <- NULL
  ask <- hr_step("ask", function(input, ctx) {
    seen <<- ctx$skill
    ctx$call(input$question)$text
  }, skill = s)
  ask_json <- hr_step("ask_json", function(input, ctx) {
    ctx$call_json(list(list(role = "system", content = "Own system."),
                       list(role = "user", content = "Give it as JSON.")),
                  schema = list(type = "object"))
  }, skill = s, input = "state")
  bench <- hr_benchmark(list(hr_chain(ask = ask, name = "skilled"), skill_chain(NULL, "plain")),
                        skill_ref(), runs = 5, client = cl, scorer = hr_scorer_exact())
  expect_identical(seen, s)
  calls <- cl$calls()
  first <- calls[[1]]$messages
  roles <- vapply(calls, function(x) x$messages[[1]]$role, "")
  expect_identical(sum(roles == "system"), 5L)
  expect_identical(sum(roles == "user"), 5L)
  expect_identical(first[[1]]$role, "system")
  expect_match(first[[1]]$content, "Always state the unit of every amount.", fixed = TRUE)
  expect_match(first[[1]]$content, "Reference style.md:\nWrite million in full.", fixed = TRUE)
  expect_identical(first[[2]], list(role = "user", content = "What was revenue?"))
  expect_setequal(unique(bench$param.ask.skill), c(paste0("units@", substr(s$hash, 1, 12)), NA))

  cl$reset()
  json <- hr_chain(ask_json = ask_json, name = "json")
  ctx <- list(call_json = function(messages, schema, ...) gr_call_json(cl, messages, schema)$value)
  json$run(list(), ctx)
  sent <- cl$calls()[[1]]$messages
  expect_identical(vapply(sent, function(m) m$role, ""), c("system", "system", "user"))
  expect_identical(sent[[2]]$content, "Own system.")

  # Outside a chain the step is called as it is, without the skill.
  cl$reset()
  ask(list(question = "q"), list(call = function(m, ...) hr_call(cl, m)))
  expect_identical(cl$calls()[[1]]$messages[[1]]$role, "user")
})

test_that("hr_set() and a derived chain keep a step's skill", {
  dir <- skill_dir()
  on.exit(unlink(dir, recursive = TRUE))
  s <- hr_skill(dir)
  ask <- hr_step("ask", function(input, ctx) input, skill = s,
                 schema = hr_schema(hr_param("n", "integer", default = 1L, min = 1, max = 9)))
  chain <- hr_chain(ask = ask, name = "c")
  moved <- hr_set(chain, ask.n = 2L)
  expect_identical(attr(attr(moved, "hr_steps")$ask, "skill"), s)
  expect_identical(moved$params[["ask.skill"]], chain$params[["ask.skill"]])
  expect_error(hr_set(chain, ask.skill = "x"), "fixed when the step was built",
               class = "hr_unknown_setting")
  dropped <- hr_chain(chain, ask = hr_step("ask", function(input, ctx) input), name = "d")
  expect_null(dropped$params[["ask.skill"]])
})

test_that("the built-in steps refuse a skill", {
  dir <- skill_dir()
  on.exit(unlink(dir, recursive = TRUE))
  s <- hr_skill(dir)
  expect_error(gr_step("read", reader = "stuff", skill = s), "does not take a skill",
               class = "hr_bad_skill")
  expect_error(gr_step_retrieve(top_k = 2, skill = s), class = "hr_bad_skill")
  expect_s3_class(gr_step("read", reader = "stuff"), "gr_step")
})

test_that("a skill's scripts are listed and never run", {
  sentinel <- tempfile("hr-skill-sentinel-")
  code <- sprintf("writeLines('ran', '%s')", gsub("\\\\", "/", sentinel))
  dir <- skill_dir(body = c("Run scripts/touch.R.", "```r", code, "```"),
                   refs = list(also.R = code), scripts = list(touch.R = code))
  on.exit(unlink(c(dir, sentinel), recursive = TRUE))
  s <- hr_skill(dir)
  invisible(utils::capture.output(print(s)))
  cl <- hr_mock_client(function(m, p) "45.2 million")
  bench <- hr_benchmark(skill_chain(s), skill_ref(), runs = 5, client = cl,
                        scorer = hr_scorer_exact())
  expect_false(file.exists(sentinel))
  # Run only when the user wraps it.
  rscript <- file.path(R.home("bin"), "Rscript")
  run <- hr_step_command("touch", c(rscript, s$scripts[["touch.R"]]))
  expect_identical(run(list(), list())$check$status, "passed")
  expect_true(file.exists(sentinel))
})

test_that("a SKILL.md that is a folder is refused with hr_bad_skill", {
  d <- tempfile("hr-skill-")
  dir.create(file.path(d, "SKILL.md"), recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  expect_error(expect_no_warning(hr_skill(d)), "SKILL.md is a folder", class = "hr_bad_skill")
})

test_that("non-ASCII file names in references/ and scripts/ are read", {
  dir <- skill_dir(refs = list(a.md = "plain"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("accent", file.path(dir, "references", enc2native("ré.md")))
  dir.create(file.path(dir, "scripts"))
  writeLines("1", file.path(dir, "scripts", enc2native("é.R")))
  s <- hr_skill(dir)
  expect_identical(names(s$references), c("a.md", "ré.md"))
  expect_identical(names(s$scripts), "é.R")
})

test_that("CRLF line endings in a reference give the same text and hash as LF", {
  lf <- skill_dir(refs = list(a.md = "unused"))
  crlf <- skill_dir(refs = list(a.md = "unused"))
  on.exit(unlink(c(lf, crlf), recursive = TRUE), add = TRUE)
  writeBin(charToRaw("ref line\ntwo\n"), file.path(lf, "references", "a.md"))
  writeBin(charToRaw("ref line\r\ntwo\r\n"), file.path(crlf, "references", "a.md"))
  a <- hr_skill(lf)
  b <- hr_skill(crlf)
  expect_identical(unname(b$references), "ref line\ntwo\n")
  expect_identical(a$hash, b$hash)
})

test_that("linked subfolders, link loops and broken links are refused with hr_bad_skill", {
  skip_on_os("windows")
  # A references/ folder that links outside is refused before it is walked.
  big <- tempfile("hr-skill-outside-")
  dir.create(big)
  on.exit(unlink(big, recursive = TRUE), add = TRUE)
  for (i in 1:60) writeLines("x", file.path(big, sprintf("f%02d.md", i)))
  away <- skill_dir()
  on.exit(unlink(away, recursive = TRUE), add = TRUE)
  expect_true(file.symlink(big, file.path(away, "references")))
  expect_error(hr_skill(away), "'references/' is a link to a folder outside",
               class = "hr_bad_skill")
  # A link to a folder under references/ is never followed, so a loop is refused.
  loop <- skill_dir(refs = list(a.md = "fine"))
  on.exit(unlink(loop, recursive = TRUE), add = TRUE)
  expect_true(file.symlink(file.path(loop, "references"),
                           file.path(loop, "references", "loop")))
  expect_error(hr_skill(loop), "is a link to a folder", class = "hr_bad_skill")
  # A broken link, in references/ or scripts/.
  broken <- skill_dir(refs = list(a.md = "fine"), scripts = list(ok.R = "1"))
  on.exit(unlink(broken, recursive = TRUE), add = TRUE)
  expect_true(file.symlink(file.path(tempdir(), "hr-no-such-file"),
                           file.path(broken, "references", "z.md")))
  expect_error(hr_skill(broken), "'references/z.md' is a broken or looping link",
               class = "hr_bad_skill")
  unlink(file.path(broken, "references", "z.md"))
  expect_true(file.symlink(file.path(tempdir(), "hr-no-such-file"),
                           file.path(broken, "scripts", "z.R")))
  expect_error(hr_skill(broken), "'scripts/z.R' is a broken or looping link",
               class = "hr_bad_skill")
})
