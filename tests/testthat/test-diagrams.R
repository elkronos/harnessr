# test-diagrams.R: the SVG diagrams in man/figures match the package.
#
# dev/build-diagrams.R writes layers.svg, document-run.svg, composition.svg
# and registry.svg from the code. The script is not part of the built
# package, so these tests run from the source tree (run-tests.sh, the tests
# workflow) and skip under R CMD check, as test-contract-files.R does. After
# a change to anything a diagram shows, rerun the script from the repository
# root and commit the new files:
#
#   Rscript dev/build-diagrams.R

diagram_files <- c("layers.svg", "document-run.svg", "composition.svg", "registry.svg")

diagram_root <- function() {
  root <- test_path("..", "..")
  skip_if_not(file.exists(file.path(root, "dev", "build-diagrams.R")),
              "dev/build-diagrams.R is not in an installed package")
  root
}

diagram_path <- function(name) file.path(diagram_root(), "man", "figures", name)

read_diagram <- function(name) {
  skip_if_not_installed("xml2")
  xml2::xml_ns_strip(xml2::read_xml(diagram_path(name)))
}

# The text of every <text> element, or of those with class `cls`.
diagram_text <- function(doc, cls = NULL) {
  xp <- if (is.null(cls)) "//text" else sprintf("//text[@class='%s']", cls)
  xml2::xml_text(xml2::xml_find_all(doc, xp))
}

test_that("each diagram is there and parses as SVG", {
  for (f in diagram_files) {
    expect_true(file.exists(diagram_path(f)), info = f)
    doc <- read_diagram(f)
    expect_identical(xml2::xml_name(doc), "svg", info = f)
  }
})

test_that("each diagram starts with a title and desc that label it", {
  for (f in diagram_files) {
    doc <- read_diagram(f)
    kids <- xml2::xml_children(doc)
    expect_identical(xml2::xml_name(kids[1:2]), c("title", "desc"), info = f)
    expect_true(all(nzchar(trimws(xml2::xml_text(kids[1:2])))), info = f)
    expect_identical(xml2::xml_attr(doc, "role"), "img", info = f)
    expect_identical(xml2::xml_attr(doc, "aria-labelledby"),
                     paste(xml2::xml_attr(kids[1:2], "id"), collapse = " "), info = f)
  }
})

test_that("each diagram keeps its labels as text on a white background", {
  for (f in diagram_files) {
    doc <- read_diagram(f)
    expect_gt(length(diagram_text(doc)), 10)
    sizes <- as.numeric(xml2::xml_attr(xml2::xml_find_all(doc, "//text[@font-size]"),
                                       "font-size"))
    expect_true(all(sizes >= 13), info = f)
    view <- as.numeric(strsplit(xml2::xml_attr(doc, "viewBox"), " ")[[1]])
    expect_lte(view[3], 900)
    bg <- xml2::xml_find_first(doc, "/svg/rect")
    expect_identical(xml2::xml_attr(bg, "fill"), "#ffffff", info = f)
    expect_false(is.na(xml2::xml_attr(bg, "rx")), info = f)
    fonts <- unique(xml2::xml_attr(xml2::xml_find_all(doc, "//*[@font-family]"), "font-family"))
    expect_length(fonts, 1L)
  }
})

test_that("no diagram has an em dash, an en dash or a spaced double hyphen", {
  for (f in diagram_files) {
    txt <- readLines(diagram_path(f), warn = FALSE, encoding = "UTF-8")
    expect_false(any(grepl("—|–| -- ", txt)), info = f)
  }
})

test_that("every function a diagram names is in harnessr", {
  ns <- asNamespace("harnessr")
  for (f in diagram_files) {
    txt <- diagram_text(read_diagram(f))
    hits <- regmatches(txt, gregexpr("(?<![$A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*(?=\\()", txt,
                                     perl = TRUE))
    named <- unique(unlist(hits))
    expect_gt(length(named), 0)
    missing <- named[!vapply(named, exists, logical(1), envir = ns, mode = "function")]
    expect(length(missing) == 0,
           sprintf("%s names functions harnessr does not have: %s", f,
                   paste(missing, collapse = ", ")))
  }
})

test_that("layers.svg names both layers and the rule between them", {
  txt <- paste(diagram_text(read_diagram("layers.svg")), collapse = "\n")
  expect_match(txt, "Document layer: gr_ functions", fixed = TRUE)
  expect_match(txt, "Core: hr_ functions", fixed = TRUE)
  expect_match(txt, "never: core to document layer", fixed = TRUE)
  expect_match(txt, "test-boundary.R", fixed = TRUE)
})

test_that("document-run.svg shows the stages of a run, in order, and what each hands on", {
  doc <- read_diagram("document-run.svg")
  stages <- setdiff(names(formals(harnessr::gr_recipe)), "name")
  expect_identical(diagram_text(doc, "stage"), stages)
  for (s in diagram_text(doc, "stage")) {
    expect_true(paste0("gr_", s) %in% getNamespaceExports("harnessr"), info = s)
  }
  old <- hr_options(verbose = FALSE)
  on.exit(hr_options(old), add = TRUE)
  d <- gr_ingest(gr_example(), cache = FALSE)
  ch <- gr_segment(d)
  a <- gr_read(ch, "What is the answer?", hr_mock_client(function(m, p) "42."))
  expect_identical(diagram_text(doc, "object"),
                   c(class(d)[1], class(ch)[1], class(a)[1]))
})

test_that("registry.svg shows every kind and both contract versions", {
  doc <- read_diagram("registry.svg")
  kinds <- names(harnessr:::hr_kinds())
  expect_setequal(diagram_text(doc, "kind"), kinds)
  txt <- paste(diagram_text(doc), collapse = "\n")
  expect_match(txt, sprintf("Modules: contract %s", harnessr:::hr_contract_version()),
               fixed = TRUE)
  expect_match(txt, sprintf("Signal calibrations: contract %s", harnessr:::.hr_signal_contract),
               fixed = TRUE)
})

test_that("composition.svg names every composition verb and the held step rule", {
  root <- diagram_root()
  txt <- paste(diagram_text(read_diagram("composition.svg")), collapse = "\n")
  # The files dev/build-diagrams.R reads the verbs from.
  files <- file.path(root, "R", c("core-compose-step.R", "core-verify-command.R",
                                  "doc-steps.R", "core-bench-sweep.R"))
  defined <- unlist(lapply(files, function(f) {
    vapply(Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]),
                  as.list(parse(f, keep.source = FALSE))),
           function(e) as.character(e[[2]]), character(1))
  }))
  verbs <- intersect(defined, getNamespaceExports("harnessr"))
  expect_true(all(c("hr_step", "hr_chain", "hr_step_command") %in% verbs))
  for (v in verbs) expect_match(txt, paste0(v, "()"), fixed = TRUE, info = v)
  expect_match(txt, "hr_held_not_last", fixed = TRUE)
})

test_that("rerunning dev/build-diagrams.R gives byte-identical files", {
  root <- normalizePath(diagram_root())
  out <- withr::local_tempdir()
  res <- withr::with_dir(root, suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c(file.path("dev", "build-diagrams.R"), shQuote(out)),
    stdout = TRUE, stderr = TRUE)))
  expect_null(attr(res, "status"), info = paste(res, collapse = "\n"))
  for (f in diagram_files) {
    expect_identical(unname(tools::md5sum(file.path(out, f))),
                     unname(tools::md5sum(diagram_path(f))), info = f)
  }
})
