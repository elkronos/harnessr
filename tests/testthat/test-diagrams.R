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
# `doc` is forced first: read_diagram() skips when the tree or xml2 is missing,
# and that skip has to run before this function calls xml2.
diagram_text <- function(doc, cls = NULL) {
  force(doc)
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
    expect_false(any(grepl("\u2014|\u2013| -- ", txt)), info = f)
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

test_that("layers.svg lists what each layer holds, as the spec does", {
  doc <- read_diagram("layers.svg")
  expect_identical(diagram_text(doc, "core-item"),
                   c("client", "calls", "cache", "trace and ledger", "budget and governor",
                     "registry and modules", "composition"))
  expect_identical(diagram_text(doc, "doc-item"),
                   c("ingest", "segment", "read", "screen", "extract", "claims", "synthesis",
                     "review"))
})

# The points of a <path> drawn with M and L, as a 2-row matrix of x and y.
path_points <- function(p) {
  d <- xml2::xml_attr(p, "d")
  matrix(as.numeric(regmatches(d, gregexpr("-?[0-9.]+", d))[[1]]), nrow = 2)
}

test_that("layers.svg draws calls going down and the crossed-out arrow going up", {
  doc <- read_diagram("layers.svg")
  layer_rect <- function(cls) {
    r <- xml2::xml_find_all(doc, sprintf("//rect[@class='%s']", cls))
    expect_length(r, 1)
    as.numeric(c(xml2::xml_attr(r, "y"), xml2::xml_attr(r, "height")))
  }
  core <- layer_rect("core-layer")
  docl <- layer_rect("doc-layer")
  expect_lt(docl[1] + docl[2], core[1])

  calls <- xml2::xml_find_all(doc, "//path[@class='call']")
  expect_gte(length(calls), 4)
  for (p in calls) {
    m <- path_points(p)
    expect_identical(ncol(m), 2L)
    expect_equal(m[1, 1], m[1, 2])
    expect_gt(m[2, 2], m[2, 1])
  }

  never <- xml2::xml_find_all(doc, "//path[@class='never']")
  expect_length(never, 1)
  m <- path_points(never[[1]])
  expect_identical(ncol(m), 2L)
  expect_equal(m[1, 1], m[1, 2])
  # It starts at the top of the core and ends at the bottom of the document
  # layer: the call the core never makes.
  expect_equal(m[2, 1], core[1])
  expect_equal(m[2, 2], docl[1] + docl[2])
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

# Which limits governor_check() reads in its call stage and in its send
# stage, in the order it reads them: a field read as gov$name, or a reserve
# read through governor_hold(gov, "name").
governor_stage_limits <- function() {
  src <- paste(deparse(body(harnessr:::governor_check), width.cutoff = 500L), collapse = "\n")
  parts <- strsplit(src, "if (stage %in% c(\"both\", \"send\"))", fixed = TRUE)[[1]]
  expect_length(parts, 2)
  lapply(parts, function(part) {
    hits <- regmatches(part, gregexpr("gov\\$[a-z_]+|governor_hold\\(gov, \"[a-z_]+\"", part))[[1]]
    unique(gsub("^gov\\$|^governor_hold\\(gov, \"|\"$", "", hits))
  })
}

# A diagram wraps a long list of limits at spaces, so its lines joined with
# a space give the list back.
limits_shown <- function(doc, cls) paste(diagram_text(doc, cls), collapse = " ")

test_that("document-run.svg puts each governor limit under the stage that checks it", {
  doc <- read_diagram("document-run.svg")
  limits <- governor_stage_limits()
  expect_true(all(c("allowed_models", "max_calls", "reserve_calls") %in% limits[[1]]))
  expect_true(all(c("max_tokens_total", "max_cost_usd", "reserve_usd") %in% limits[[2]]))
  expect_identical(limits_shown(doc, "limits-call"), paste(limits[[1]], collapse = ", "))
  expect_identical(limits_shown(doc, "limits-send"), paste(limits[[2]], collapse = ", "))
  txt <- diagram_text(doc)
  at <- function(s) which(txt == s)
  expect_identical(at(diagram_text(doc, "limits-call")[1]), at("1. governor, before the cache") + 1L)
  expect_identical(at(diagram_text(doc, "limits-send")[1]), at("3. governor, on a cache miss") + 1L)
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

# README.md uses the path from the repository root, which GitHub and pkgdown
# both resolve. The guides use "../man/figures/". That path renders under
# R CMD build, which embeds the image in the built HTML, so the installed
# vignette shows it too, and pkgdown rewrites it to "../reference/figures/",
# where it copies man/figures.
test_that("README and the guides show the diagrams, each with alt text", {
  root <- diagram_root()
  readme <- paste(readLines(file.path(root, "README.md"), warn = FALSE), collapse = "\n")
  expect_match(readme, "![Two stacked layers", fixed = TRUE)
  expect_match(readme, "](man/figures/layers.svg)", fixed = TRUE)

  shown <- c(harnessr = "document-run.svg", compose = "composition.svg",
             extending = "registry.svg")
  for (v in names(shown)) {
    lines <- readLines(file.path(root, "vignettes", paste0(v, ".Rmd")), warn = FALSE)
    call <- sprintf('knitr::include_graphics("../man/figures/%s")', shown[[v]])
    at <- which(lines == call)
    expect_length(at, 1)
    if (length(at) != 1) next
    header <- lines[at - 1]
    expect_match(header, "echo = FALSE", fixed = TRUE, info = v)
    alt <- regmatches(header, regexpr('fig.alt = "[^"]+"', header))
    expect_length(alt, 1)
    expect_gt(nchar(alt), 100)
  }
})

# The fig.alt of the chunk that shows `svg` in vignettes/<v>.Rmd.
vignette_alt <- function(v, svg) {
  lines <- readLines(file.path(diagram_root(), "vignettes", paste0(v, ".Rmd")), warn = FALSE)
  at <- which(lines == sprintf('knitr::include_graphics("../man/figures/%s")', svg))
  expect_length(at, 1)
  alt <- regmatches(lines[at - 1], regexpr('fig.alt = "[^"]+"', lines[at - 1]))
  expect_length(alt, 1)
  sub('^fig.alt = "(.*)"$', "\\1", alt)
}

number_words <- c("one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                  "ten", "eleven", "twelve")

test_that("the alt text of the guides states the same facts as the package", {
  alt <- vignette_alt("extending", "registry.svg")
  kinds <- names(harnessr:::hr_kinds())
  expect_match(alt, sprintf("one of %s kinds: ", number_words[length(kinds)]), fixed = TRUE)
  for (k in kinds) expect_match(alt, paste0("\\b", k, "\\b"), info = k)
  listed <- sub("[.].*$", "", sub("^.* kinds: ", "", alt))
  expect_setequal(strsplit(listed, ", | and ")[[1]], kinds)
  expect_match(alt, sprintf("module contract %s.", harnessr:::hr_contract_version()),
               fixed = TRUE)
  expect_match(alt, sprintf("their own contract, %s.", harnessr:::.hr_signal_contract),
               fixed = TRUE)

  alt <- vignette_alt("harnessr", "document-run.svg")
  stages <- setdiff(names(formals(harnessr::gr_recipe)), "name")
  expect_match(alt, sprintf("runs %s stages in order: ", number_words[length(stages)]),
               fixed = TRUE)
  shown <- regmatches(alt, gregexpr("[a-z]+ with gr_[a-z]+\\(\\)", alt))[[1]]
  expect_identical(shown, sprintf("%s with gr_%s()", stages, stages))
})
