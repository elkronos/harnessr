# test-settings-table.R: gr_settings_table() holds every declared setting,
# its declarations name real settings, and the guide sections it points to
# exist.

ns <- asNamespace("harnessr")

test_that("gr_settings_table() has every declared setting of every stage", {
  s <- gr_settings_table()
  expect_named(s, c("stage", "name", "where", "default", "tier", "status", "source",
                    "description", "guide"))
  has <- function(stage, where, name) {
    any(s$stage == stage & s$where == where & s$name == name)
  }
  for (stage in c("ingest", "segment", "read")) {
    schema <- gr_settings(stage)
    where <- sprintf("gr_%s_spec()", stage)
    for (nm in names(schema)) expect_true(has(stage, where, nm), info = paste(stage, nm))
  }
  for (nm in names(ns$.gr_cleaner_opts)) {
    expect_true(has("ingest", "gr_ingest_spec()", paste0("cleaner_opts.", nm)), info = nm)
  }
  for (nm in ns$.gr_layout_opt_names) {
    expect_true(has("ingest", "gr_ingest_spec()", paste0("layout_opts.", nm)), info = nm)
  }
  for (fn in names(ns$.gr_stage_functions)) {
    decl <- ns$.gr_stage_functions[[fn]]
    args <- setdiff(names(formals(get(fn, envir = ns))), c(decl$inputs, "..."))
    for (a in args) expect_true(has(decl$stage, paste0(fn, "()"), a), info = paste(fn, a))
  }
  for (nm in union(names(hr_options()), names(ns$.gr_option_rules))) {
    expect_true(has("options", "hr_options()", nm), info = nm)
  }
  expect_false(anyDuplicated(paste(s$stage, s$where, s$name)) > 0)
})

test_that("gr_settings_table() carries the schemas' defaults, tiers and evidence", {
  s <- gr_settings_table("read")
  top <- s[s$name == "top_k" & s$where == "gr_read_spec()", ]
  expect_identical(top$default, "6")
  expect_identical(top$tier, "basic")
  expect_identical(top$status, "untested")
  expect_identical(top$guide, "readers#set-top-k")
  bm <- s[s$name == "bm25_b", ]
  expect_identical(bm$status, "cited")
  o <- gr_settings_table("options")
  expect_identical(o$default[o$name == "max_cost_usd"], "5")
  expect_identical(o$status[o$name == "near_verbatim_sim"], "measured")
  expect_identical(o$tier[o$name == "model"], "basic")
  expect_match(o$description[o$name == "max_calls"], "^Hard cap on model calls")
  # The budget options link to the context guide's walkthroughs.
  expect_identical(o$guide[o$name == "safety_margin"], "context#set-safety-margin")
  expect_identical(o$guide[o$name == "output_reserve_share"], "context#set-reply-reserve")
  expect_identical(o$guide[o$name == "min_output_tokens"], "context#set-reply-reserve")
  # The output cap floor links to the effort guide's walkthrough.
  expect_identical(o$guide[o$name == "reasoning_floor"], "effort#set-reasoning-floor")
  # So does a read's effort_mode, whose walkthrough moved there from the runs
  # guide.
  expect_identical(s$guide[s$name == "effort_mode"], "effort#set-effort-mode")
  syn <- gr_settings_table("synthesise")
  expect_identical(syn$default[syn$name == "coherence_rounds"], "1")
  expect_identical(syn$status[syn$name == "prominence"], "untested")
  expect_identical(syn$default[syn$name == "cite_style"], "auto")
  ev <- gr_settings_table("evaluate")
  expect_identical(ev$default[ev$name == "recipes"], "c(\"fast\", \"needle\", \"thorough\")")
  expect_identical(unique(gr_settings_table(c("screen", "extract"))$stage),
                   c("screen", "extract"))
  expect_error(gr_settings_table("nope"), class = "gr_bad_setting")
})

test_that("every description is read from the help pages, one sentence each", {
  s <- gr_settings_table()
  expect_false(anyNA(s$description))
  expect_false(any(grepl("^As [a-z_]+\\(\\)", s$description)))
  # vignettes/settings.Rmd escapes < for the page, which would show as "&lt;"
  # inside a code span.
  spans <- unlist(regmatches(s$description, gregexpr("`[^`]*`", s$description)))
  expect_false(any(grepl("<", spans, fixed = TRUE)))
  rd <- s$description[s$where == "gr_extract()" & s$name == "resolve"]
  expect_identical(rd, paste0("What to do when two parts of one document give different ",
                              "values for the same field."))
  expect_identical(ns$settings_sentence("Use it, e.g. here. Then more."), "Use it, e.g. here.")
})

test_that("the table's own declarations name real settings and agree with the code", {
  s <- gr_settings_table()
  keys <- paste(sub("\\(\\)$", "", s$where), s$name, sep = ".")
  expect_true(all(ns$.gr_stage_basic %in% keys))
  expect_true(all(names(ns$.gr_stage_evidence) %in% keys))
  for (e in ns$.gr_stage_evidence) expect_true(ns$evidence_ok(e))
  expect_true(all(ns$.gr_option_basic %in% names(hr_options())))
  guide_keys <- c(paste(s$stage, s$name, sep = "."),
                  paste(s$stage, sub("\\(\\)$", "", s$where), s$name, sep = "."))
  expect_true(all(names(ns$.gr_setting_guides) %in% guide_keys))
  # The cleaners' own defaults.
  expect_identical(ns$references_after(list()), ns$.gr_cleaner_opts$references_after$default)
  fm <- formals(ns$drop_running_lines)
  expect_true(all(ns$.gr_layout_opt_names %in% names(fm)))
})

test_that("every guide section the table points to exists", {
  guides <- unique(stats::na.omit(gr_settings_table()$guide))
  expect_gt(length(guides), 0L)
  # The vignette sources sit next to the tests in the repository, and an
  # installed package built with its vignettes keeps them under doc/.
  dirs <- c(file.path("..", "..", "vignettes"), system.file("doc", package = "harnessr"))
  dirs <- dirs[nzchar(dirs) & dir.exists(dirs)]
  # A check run without building the guides has neither folder.
  if (!length(dirs)) skip("the guide sources are not available here")
  for (d in dirs[1]) {
    for (g in guides) {
      parts <- strsplit(g, "#", fixed = TRUE)[[1]]
      f <- file.path(d, paste0(parts[1], ".Rmd"))
      expect_true(file.exists(f), info = g)
      expect_true(any(grepl(sprintf("{#%s}", parts[2]), readLines(f, warn = FALSE),
                            fixed = TRUE)), info = g)
    }
  }
})

test_that("the get started guide's counts of settings match the table", {
  s <- gr_settings_table()
  expect_identical(nrow(s), 230L)
  # The counts moved from the README to the get started guide. Its source
  # sits two levels up in the repository; an installed package has none,
  # and then the count above is what holds the figure.
  guide <- file.path("..", "..", "vignettes", "harnessr.Rmd")
  for (f in guide[file.exists(guide)]) {
    text <- readLines(f, warn = FALSE)
    expect_true(any(grepl(sprintf("lists all %d with", nrow(s)), text, fixed = TRUE)))
    n <- table(s$stage)
    for (st in names(n)) {
      expect_true(any(startsWith(text, sprintf("| %s | %d |", st, n[[st]]))), info = st)
    }
  }
})

test_that("the settings table agrees with the command step's schema", {
  sc <- ns$.hr_command_schema
  for (k in names(sc)) {
    ev <- ns$.gr_stage_evidence[[paste0("hr_step_command.", k)]]
    expect_identical(ev, sc[[k]]$evidence, info = k)
  }
  t <- gr_settings_table("evaluate")
  rows <- t[t$where == "hr_step_command()", ]
  expect_identical(rows$name, names(sc))
  d <- as.data.frame(sc)
  expect_identical(rows$default, d$default)
  expect_identical(rows$tier, d$tier)
  expect_identical(rows$status, d$status)
  expect_identical(rows$source, d$source)
})
