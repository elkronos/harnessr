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
  for (nm in union(names(gr_options()), names(ns$.gr_option_rules))) {
    expect_true(has("options", "gr_options()", nm), info = nm)
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
  expect_true(all(ns$.gr_option_basic %in% names(gr_options())))
  guide_keys <- c(paste(s$stage, s$name, sep = "."),
                  paste(s$stage, sub("\\(\\)$", "", s$where), s$name, sep = "."))
  expect_true(all(names(ns$.gr_setting_guides) %in% guide_keys))
  # The cleaners' own defaults.
  expect_identical(ns$references_after(list()), ns$.gr_cleaner_opts$references_after$default)
  fm <- formals(ns$drop_running_lines)
  expect_true(all(ns$.gr_layout_opt_names %in% names(fm)))
})
