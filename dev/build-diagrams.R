# build-diagrams.R: write the five SVG diagrams in man/figures from the code.
#
# Run from the repository root:
#
#   Rscript dev/build-diagrams.R             # writes man/figures
#   Rscript dev/build-diagrams.R <out_dir>   # writes the five files there
#
# It writes layers.svg, document-run.svg, composition.svg, registry.svg and
# request.svg.
# The markup is written as text with base R, never through a graphics
# device: cairo turns glyphs into paths, which a screen reader cannot read
# and which differ between machines. A rerun gives byte-identical files.
# tests/testthat/test-diagrams.R checks that, and checks the facts each
# diagram states against the package.
#
# Every fact a diagram states is read from the package as it stands: the
# package is loaded from this source tree with pkgload::load_all(), or, when
# pkgload is not installed, the installed copy is used. A fact the code cannot
# give is written here with a comment naming the file it came from, and the
# script checks it against the code where it can. Each function a diagram
# names must exist in the namespace, or the build stops.
#
# Rerun it after changing anything a diagram shows (a kind of module, a
# stage, a composition verb, a contract version) and commit the new files.

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args)) args[[1]] else file.path("man", "figures")

if (!file.exists("DESCRIPTION") || !dir.exists("R") ||
    !identical(unname(read.dcf("DESCRIPTION", "Package")[1, 1]), "harnessr")) {
  stop("Run this from the harnessr repository root: Rscript dev/build-diagrams.R",
       call. = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (requireNamespace("pkgload", quietly = TRUE)) {
  suppressPackageStartupMessages(
    pkgload::load_all(".", quiet = TRUE, helpers = FALSE, attach_testthat = FALSE))
} else {
  suppressPackageStartupMessages(requireNamespace("harnessr", quietly = TRUE))
}
ns <- asNamespace("harnessr")
exports <- getNamespaceExports("harnessr")
old_opts <- ns$hr_options(verbose = FALSE)

# The file in R/ that defines each top-level object, as dev/record-layers.R
# reads them.
r_files <- sort(list.files("R", pattern = "[.][Rr]$", full.names = TRUE), method = "radix")
defined_in <- character(0)
for (f in r_files) {
  for (e in parse(f, keep.source = FALSE)) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]])) {
      defined_in[[as.character(e[[2]])]] <- basename(f)
    }
  }
}

# A function a diagram names. It must be in the namespace, exported unless
# `internal`, and when `layer` is given, defined in a file of that layer.
fn <- function(name, layer = NULL, internal = FALSE) {
  if (!exists(name, envir = ns, inherits = FALSE) || !is.function(get(name, envir = ns))) {
    stop(sprintf("A diagram names %s(), which harnessr does not define.", name), call. = FALSE)
  }
  if (!internal && !name %in% exports) {
    stop(sprintf("A diagram names %s() as exported, and it is not.", name), call. = FALSE)
  }
  if (!is.null(layer) && !startsWith(defined_in[[name]], paste0(layer, "-"))) {
    stop(sprintf("%s() is in %s, not in a %s-*.R file.", name, defined_in[[name]], layer),
         call. = FALSE)
  }
  name
}

# Whether the calls named in `calls` appear in this order in a function's
# body: each one after the one before it.
calls_in_order <- function(f, calls) {
  rest <- paste(deparse(body(f), width.cutoff = 500L), collapse = "\n")
  for (cl in calls) {
    at <- regexpr(cl, rest, fixed = TRUE)[[1]]
    if (at < 0) return(FALSE)
    rest <- substring(rest, at + nchar(cl))
  }
  TRUE
}

must <- function(ok, what) {
  if (!isTRUE(ok)) stop(sprintf("The code no longer matches the diagrams: %s.", what),
                        call. = FALSE)
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

width_px <- 900
font_stack <- paste("system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue',",
                    "Arial, 'Liberation Sans', sans-serif")

# One neutral, one color for core, one for the document layer, one accent.
pal <- list(
  neutral = list(fill = "#f6f8fa", line = "#8c959f", ink = "#1f2328"),
  core    = list(fill = "#ddf4ff", line = "#0969da", ink = "#0550ae"),
  doc     = list(fill = "#dafbe1", line = "#1a7f37", ink = "#116329"),
  accent  = list(fill = "#fff1e5", line = "#bc4c00", ink = "#953800"))
ink <- "#1f2328"
muted <- "#57606a"

fmt <- function(v) sub("[.]0$", "", sprintf("%.1f", v))

esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

# A generous estimate of a line's width, so text that fits here fits in the
# wider fallback fonts too.
text_width <- function(s, size, bold = FALSE) nchar(s) * size * if (bold) 0.64 else 0.6

# A canvas keeps the elements of one diagram and the box of every text, so
# overlapping text or text off the canvas stops the build.
canvas <- function(stem, height) {
  env <- new.env()
  env$stem <- stem
  env$height <- height
  env$els <- character(0)
  env$boxes <- list()
  env
}

add <- function(cv, ...) cv$els <- c(cv$els, ...)

txt <- function(cv, x, y, s, size = 14, anchor = "start", bold = FALSE, color = ink,
                cls = NULL) {
  if (size < 13) stop("Text must be at least 13 px.", call. = FALSE)
  w <- text_width(s, size, bold)
  x0 <- switch(anchor, start = x, middle = x - w / 2, end = x - w)
  bb <- c(x0, y - size * 0.8, x0 + w, y + size * 0.25)
  if (bb[1] < 8 || bb[3] > width_px - 8 || bb[2] < 8 || bb[4] > cv$height - 8) {
    stop(sprintf("'%s' runs off the %s canvas.", s, cv$stem), call. = FALSE)
  }
  for (o in cv$boxes) {
    if (bb[1] < o$bb[3] && o$bb[1] < bb[3] && bb[2] < o$bb[4] && o$bb[2] < bb[4]) {
      stop(sprintf("In %s, '%s' overlaps '%s'.", cv$stem, s, o$s), call. = FALSE)
    }
  }
  cv$boxes[[length(cv$boxes) + 1L]] <- list(bb = bb, s = s)
  attrs <- paste0(
    sprintf(" x=\"%s\" y=\"%s\"", fmt(x), fmt(y)),
    if (size != 14) sprintf(" font-size=\"%s\"", fmt(size)),
    if (anchor != "start") sprintf(" text-anchor=\"%s\"", anchor),
    if (bold) " font-weight=\"bold\"",
    if (color != ink) sprintf(" fill=\"%s\"", color),
    if (!is.null(cls)) sprintf(" class=\"%s\"", cls))
  add(cv, sprintf("<text%s>%s</text>", attrs, esc(s)))
}

# One line of text inside a box.
ln <- function(s, size = 14, bold = FALSE, color = ink, cls = NULL) {
  list(s = s, size = size, bold = bold, color = color, cls = cls)
}

# Split `s` into lines no wider than `w` at `size`, at spaces.
wrap <- function(s, w, size = 14, bold = FALSE) {
  words <- strsplit(s, " ", fixed = TRUE)[[1]]
  out <- character(0)
  cur <- ""
  for (wd in words) {
    try_line <- if (nzchar(cur)) paste(cur, wd) else wd
    if (text_width(try_line, size, bold) > w && nzchar(cur)) {
      out <- c(out, cur)
      cur <- wd
    } else {
      cur <- try_line
    }
  }
  c(out, cur)
}

rect <- function(cv, x, y, w, h, style = "neutral", rx = 8, dash = FALSE, fill = NULL,
                 cls = NULL) {
  p <- pal[[style]]
  add(cv, sprintf(
    "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.5\"%s%s/>",
    fmt(x), fmt(y), fmt(w), fmt(h), fmt(rx), fill %||% p$fill, p$line,
    if (dash) " stroke-dasharray=\"6 4\"" else "",
    if (!is.null(cls)) sprintf(" class=\"%s\"", cls) else ""))
}

# A box with its lines centred in it. Text that does not fit stops the build.
box <- function(cv, x, y, w, h, lines, style = "neutral", align = "middle", dash = FALSE) {
  rect(cv, x, y, w, h, style, dash = dash)
  heights <- vapply(lines, function(l) l$size * 1.3, numeric(1))
  if (sum(heights) > h - 6) stop(sprintf("The lines of '%s' do not fit its box.", lines[[1]]$s),
                                 call. = FALSE)
  yy <- y + (h - sum(heights)) / 2
  for (i in seq_along(lines)) {
    l <- lines[[i]]
    if (text_width(l$s, l$size, l$bold) > w - 16) {
      stop(sprintf("'%s' does not fit its box in %s.", l$s, cv$stem), call. = FALSE)
    }
    yy <- yy + heights[[i]]
    base <- yy - l$size * 0.32
    xx <- if (align == "middle") x + w / 2 else x + 10
    txt(cv, xx, base, l$s, l$size, anchor = if (align == "middle") "middle" else "start",
        bold = l$bold, color = l$color, cls = l$cls)
  }
}

arrow <- function(cv, points, style = "neutral", dash = FALSE, head = TRUE, cls = NULL) {
  d <- paste0("M", fmt(points[1]), " ", fmt(points[2]))
  rest <- matrix(points[-(1:2)], nrow = 2)
  for (i in seq_len(ncol(rest))) d <- paste0(d, " L", fmt(rest[1, i]), " ", fmt(rest[2, i]))
  add(cv, sprintf("<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.75\"%s%s%s/>",
                  d, pal[[style]]$line, if (dash) " stroke-dasharray=\"6 4\"" else "",
                  if (head) sprintf(" marker-end=\"url(#%s-arrow-%s)\"", cv$stem, style) else "",
                  if (!is.null(cls)) sprintf(" class=\"%s\"", cls) else ""))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# The whole file: title and desc first, a white rounded background, one font
# stack for every text.
svg_file <- function(cv, title, desc) {
  markers <- vapply(names(pal), function(st) sprintf(paste0(
    "<marker id=\"%s-arrow-%s\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" ",
    "markerWidth=\"7\" markerHeight=\"7\" orient=\"auto\">",
    "<path d=\"M0 0 L10 5 L0 10 z\" fill=\"%s\"/></marker>"),
    cv$stem, st, pal[[st]]$line), character(1), USE.NAMES = FALSE)
  out <- c(
    sprintf(paste0("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%s\" ",
                   "viewBox=\"0 0 %d %s\" role=\"img\" aria-labelledby=\"%s-title %s-desc\">"),
            width_px, fmt(cv$height), width_px, fmt(cv$height), cv$stem, cv$stem),
    sprintf("<title id=\"%s-title\">%s</title>", cv$stem, esc(title)),
    sprintf("<desc id=\"%s-desc\">%s</desc>", cv$stem, esc(desc)),
    "<defs>", markers, "</defs>",
    sprintf("<rect width=\"%d\" height=\"%s\" rx=\"14\" fill=\"#ffffff\"/>",
            width_px, fmt(cv$height)),
    sprintf("<g font-family=\"%s\" font-size=\"14\" fill=\"%s\">", font_stack, ink),
    cv$els,
    "</g>",
    "</svg>")
  # Any character outside printable ASCII (an em or en dash among them), or a
  # spaced double hyphen.
  bad <- grepl("[^ -~]", out) | grepl(paste0(" ", strrep("-", 2), " "), out, fixed = TRUE)
  if (any(bad)) stop(sprintf("%s has a character outside printable ASCII or a dash: %s",
                             cv$stem, out[bad][1]), call. = FALSE)
  out
}

write_svg <- function(lines, name) {
  path <- file.path(out_dir, name)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(lines, con, sep = "\n", useBytes = TRUE)
  path
}

heading <- function(cv, title, caption) {
  txt(cv, 24, 36, title, 20, bold = TRUE)
  txt(cv, 24, 60, caption, 14, color = muted)
}

# ---------------------------------------------------------------------------
# 1. layers.svg
# ---------------------------------------------------------------------------

# The prefix most exported functions of each layer share. Core files are
# R/core-*.R and document layer files R/doc-*.R (dev/record-layers.R).
layer_prefix <- function(layer) {
  own <- names(defined_in)[startsWith(defined_in, paste0(layer, "-"))]
  own <- intersect(own, exports)
  own <- own[vapply(own, function(n) is.function(get(n, envir = ns)), logical(1))]
  tab <- table(sub("_.*$", "_", own))
  names(tab)[which.max(tab)]
}
core_prefix <- layer_prefix("core")
doc_prefix <- layer_prefix("doc")
must(identical(core_prefix, "hr_") && identical(doc_prefix, "gr_"),
     "the core exports hr_ functions and the document layer gr_ functions")

# What each layer holds, with the functions that stand for it. The core items
# follow the core guides in the order the site lists them (core, models,
# context, effort, runs, compose, evaluate, then extending for the registry);
# each function is checked to be exported and to be defined in a file of its
# layer.
core_items <- list(
  list("calls and clients", fn("hr_call", "core"), fn("hr_client", "core")),
  list("trace", fn("hr_trace", "core")),
  list("models and prices", fn("hr_register_model", "core"), fn("hr_load_models", "core")),
  list("context", fn("hr_budget", "core"), fn("hr_context_fit", "core")),
  list("effort", fn("hr_effort_escalate", "core"), fn("hr_effort_check", "core")),
  list("limits", fn("hr_governor", "core")),
  list("cache and replay", fn("hr_cache_client", "core"), fn("hr_replay_client", "core")),
  list("composing", fn("hr_chain", "core"), fn("hr_step", "core")),
  list("evaluating", fn("hr_benchmark", "core"), fn("hr_report", "core")),
  list("registry and modules", fn("hr_register", "core")))
doc_items <- list(
  list("ingest", fn("gr_ingest", "doc")),
  list("segment", fn("gr_segment", "doc")),
  list("read", fn("gr_read", "doc")),
  list("screen", fn("gr_screen", "doc")),
  list("extract", fn("gr_extract", "doc")),
  list("claims", fn("gr_claims", "doc")),
  list("synthesis", fn("gr_synthesise", "doc")),
  list("review", fn("gr_audit_report", "doc")))
clients <- c(fn("hr_client", "core"), fn("hr_ellmer_client", "core"),
             fn("hr_backend_client", "core"), fn("hr_mock_client", "core"),
             fn("hr_replay_client", "core"))

item_lines <- function(it, layer) {
  c(list(ln(it[[1]], 14, bold = TRUE, color = pal[[layer]]$ink, cls = paste0(layer, "-item"))),
    lapply(it[-1], function(f) ln(paste0(f, "()"), 13, cls = "fn")))
}

draw_layers <- function() {
  cv <- canvas("layers", 756)
  heading(cv, "harnessr: a core and a document layer",
          "The core sends every model request. The document layer builds on it; calls go down.")
  box(cv, 24, 76, 852, 40, list(ln("Your R code", 15, bold = TRUE)))

  # The document layer.
  arrow(cv, c(380, 116, 380, 154), cls = "call")
  txt(cv, 388, 140, sprintf("calls %s functions", doc_prefix), 13, color = muted)
  rect(cv, 24, 154, 720, 166, "doc", cls = "doc-layer")
  txt(cv, 40, 178, sprintf("Document layer: %s functions in R/doc-*.R", doc_prefix), 15,
      bold = TRUE, color = pal$doc$ink)
  iw <- (720 - 32 - 36) / 4
  for (i in seq_along(doc_items)) {
    col <- (i - 1) %% 4
    row <- (i - 1) %/% 4
    box(cv, 40 + col * (iw + 12), 190 + row * 62, iw, 52,
        item_lines(doc_items[[i]], "doc"), "doc")
  }

  # Your code can call the core directly.
  arrow(cv, c(810, 116, 810, 378), cls = "call")
  txt(cv, 818, 140, sprintf("calls %s", core_prefix), 13, color = muted)

  arrow(cv, c(380, 320, 380, 378), cls = "call")
  txt(cv, 388, 354, sprintf("calls %s functions", core_prefix), 13, color = muted)

  # The rule, crossed out: no call goes up.
  arrow(cv, c(520, 378, 520, 320), "accent", dash = TRUE, cls = "never")
  add(cv, sprintf(paste0("<path d=\"M512 341 L528 357 M528 341 L512 357\" stroke=\"%s\" ",
                         "stroke-width=\"2.5\"/>"), pal$accent$line))
  txt(cv, 540, 344, "never: core to document layer", 13, bold = TRUE, color = pal$accent$ink)
  txt(cv, 540, 362, "test-boundary.R checks it", 13, color = muted)

  # The core, one box per core guide.
  rows <- ceiling(length(core_items) / 4)
  core_h <- 36 + rows * 76 + 4
  rect(cv, 24, 378, 852, core_h, "core", cls = "core-layer")
  txt(cv, 40, 402, sprintf("Core: %s functions in R/core-*.R", core_prefix), 15,
      bold = TRUE, color = pal$core$ink)
  cw <- (852 - 32 - 36) / 4
  for (i in seq_along(core_items)) {
    col <- (i - 1) %% 4
    row <- (i - 1) %/% 4
    box(cv, 40 + col * (cw + 12), 414 + row * 76, cw, 66,
        item_lines(core_items[[i]], "core"), "core")
  }

  core_end <- 378 + core_h
  arrow(cv, c(450, core_end, 450, core_end + 38), cls = "call")
  txt(cv, 458, core_end + 24, "sends requests", 13, color = muted)
  box(cv, 24, core_end + 38, 852, 52, list(
    ln("A model provider over HTTP or through ellmer, your own function, a mock or a recording", 13),
    ln(paste0(clients, "()", collapse = ", "), 13, cls = "fn")))
  if (core_end + 38 + 52 + 20 != cv$height) {
    stop(sprintf("Set the layers height to %s.", fmt(core_end + 38 + 52 + 20)), call. = FALSE)
  }

  svg_file(cv, "harnessr: a core and a document layer",
           paste0("Two stacked layers. The core (", core_prefix, " functions: ",
                  paste(vapply(core_items, `[[`, "", 1), collapse = ", "),
                  ") sends every request to a model provider or a stand-in: ",
                  paste0(clients, "()", collapse = ", "), ". The document layer (", doc_prefix,
                  " functions: ", paste(vapply(doc_items, `[[`, "", 1), collapse = ", "),
                  ") sits above it and calls the core. Your R code calls either layer. ",
                  "The core never calls the document layer; tests/testthat/test-boundary.R ",
                  "checks that."))
}

# ---------------------------------------------------------------------------
# 2. document-run.svg
# ---------------------------------------------------------------------------

# The stages are the parts of a recipe, in order (R/doc-read-recipe.R,
# gr_recipe()), and answer_document() runs them in that order
# (R/doc-read-route.R).
stages <- setdiff(names(formals(ns$gr_recipe)), "name")
stage_fns <- vapply(stages, function(s) fn(paste0("gr_", s), "doc"), character(1))
must(calls_in_order(ns$answer_document, paste0(stage_fns, "(")),
     "answer_document() runs the stages in the order gr_recipe() lists them")

# The object each stage hands to the next, from one offline run of the
# bundled example.
mock <- ns$hr_mock_client(function(messages, params) "The answer is 42.")
run_doc <- ns$gr_ingest(ns$gr_example(), cache = FALSE)
run_chunks <- ns$gr_segment(run_doc)
run_answer <- ns$gr_read(run_chunks, "What is the answer?", mock)
handed <- c(class(run_doc)[1], class(run_chunks)[1], class(run_answer)[1])
answer_fields <- c("answer", "evidence", "trace")
must(all(answer_fields %in% names(run_answer)), "a gr_answer carries $answer, $evidence, $trace")

# The steps a run records in its trace, from a "fast" run of the example.
run_trace <- ns$hr_trace()
invisible(ns$answer_document(ns$gr_example(), "What is the answer?", "fast", client = mock,
                             trace = run_trace))
trace_labels <- vapply(run_trace$steps, function(s) s$label, character(1))
must(identical(trace_labels[1:2], stages[1:2]), "a run's trace starts with its ingest and segment steps")

# Which stages send model requests: the modules of the kinds each stage looks
# up declare their call stems (hr_modules()$calls). Ingestion uses extractors
# and cleaners (R/doc-ingest-run.R), segmentation a segmenter
# (R/doc-segment-run.R), reading a reader (R/doc-read-run.R).
mods <- ns$hr_modules()
calls_of <- function(kind) mods$name[mods$kind %in% kind & lengths(mods$calls) > 0]
ingest_calls <- calls_of(c("extractor", "cleaner"))
segment_calls <- sort(calls_of("segmenter"))
reader_all <- all(lengths(mods$calls[mods$kind == "reader"]) > 0)
must(length(ingest_calls) == 0, "no extractor or cleaner declares model calls")
must(reader_all, "every built-in reader declares model calls")

# The path of one request through hr_call(), in the order the code takes it:
# model_call() checks the governor, dispatches, then records the step
# (R/core-transport-call.R); the client's dispatch looks in the cache, asks
# the governor about the spend on a miss, sends, and stores the reply.
must(calls_in_order(ns$model_call, c("governor_check(trace, gate, \"call\")",
                                     "client_dispatch(client, req)", "trace_record(trace")),
     "model_call() checks the governor, dispatches and then records the step")
must(calls_in_order(get("client_dispatch.gr_client", envir = ns),
                    c("cache_get(", "req$admit()", "client_send(client, req)", "cache_put(")),
     "a client looks in its cache before the spend check and sends only on a miss")
# The limits governor_check() reads before the cache and after a miss, and
# the reserve each stage holds back for closing requests, read through
# governor_hold(gov, "name").
gov_body <- paste(deparse(body(ns$governor_check), width.cutoff = 500L), collapse = "\n")
gov_split <- strsplit(gov_body, "if (stage %in% c(\"both\", \"send\"))", fixed = TRUE)[[1]]
must(length(gov_split) == 2, "governor_check() has a call stage and a send stage")
gov_limits <- lapply(gov_split, function(part) {
  hits <- regmatches(part, gregexpr("gov\\$[a-z_]+", part))[[1]]
  unique(sub("^gov\\$", "", hits))
})
gov_reserves <- lapply(gov_split, function(part) {
  hits <- regmatches(part, gregexpr("governor_hold\\(gov, \"[a-z_]+\"", part))[[1]]
  unique(gsub("^governor_hold\\(gov, \"|\"$", "", hits))
})
must(identical(gov_reserves, list("reserve_calls", "reserve_usd")),
     "governor_check() holds back reserve_calls in its call stage and reserve_usd in its send stage")
must(all(unlist(c(gov_limits, gov_reserves)) %in% names(formals(ns$hr_governor))),
     "each limit governor_check() reads is an argument of hr_governor()")
# The line under a governor stage's limits that names its reserve.
reserve_line <- function(reserve) sprintf("%s, kept for closing = TRUE requests", reserve)
readers_budget <- basename(r_files[startsWith(basename(r_files), "doc-read-") &
  vapply(r_files, function(f) any(grepl("hr_budget(", readLines(f, warn = FALSE),
                                        fixed = TRUE)), logical(1))])
must(length(readers_budget) > 0, "readers size prompts with hr_budget()")
cache_documents <- isTRUE(ns$hr_options("cache_documents"))

draw_document_run <- function() {
  cv <- canvas("document-run", 752)
  heading(cv, "A document run",
          sprintf("%s() runs the stages of %s() in order: %s.", fn("answer_document", "doc"),
                  fn("gr_recipe", "doc"), paste(stages, collapse = ", ")))
  lx <- 24
  lw <- 400
  box(cv, lx, 84, lw, 40, list(ln("source: a file path, a URL or text")))
  sig <- function(f) sprintf("%s(%s)", f, paste(names(formals(get(f, envir = ns))),
                                                collapse = ", "))
  notes <- list(
    c("extractors and cleaners declare no model calls",
      sprintf("cache_documents = %s keeps a session cache", cache_documents)),
    c("segmenters that declare model calls:", paste(segment_calls, collapse = ", ")),
    "every reader declares model calls")
  y <- 124
  for (i in seq_along(stages)) {
    arrow(cv, c(lx + 120, y, lx + 120, y + 40))
    if (i > 1) txt(cv, lx + 132, y + 26, handed[[i - 1]], 14, bold = TRUE, cls = "object")
    y <- y + 40
    h <- 62 + 17 * length(notes[[i]])
    box(cv, lx, y, lw, h, c(
      list(ln(stages[[i]], 15, bold = TRUE, color = pal$doc$ink, cls = "stage"),
           ln(sig(stage_fns[[i]]), 13, cls = "fn")),
      lapply(notes[[i]], function(n) ln(n, 13, color = muted))), "doc")
    if (i == 1) ingest_y <- y
    if (i == 2) segment_mid <- y + h / 2
    if (i == 3) read_mid <- y + h / 2
    y <- y + h
  }
  arrow(cv, c(lx + 120, y, lx + 120, y + 40))
  txt(cv, lx + 132, y + 26, handed[[3]], 14, bold = TRUE, cls = "object")
  y <- y + 40
  box(cv, lx, y, lw, 44, list(ln(sprintf("the answer: %s",
                                         paste0("$", answer_fields, collapse = ", ")))))
  end_left <- y + 44

  # One request, through hr_call().
  rx <- 464
  rw <- 412
  box(cv, rx, 84, rw, 40, list(ln(sprintf("each model request: %s()", fn("hr_call", "core")),
                                  14, bold = TRUE, cls = "fn")), "core")
  arrow(cv, c(lx + lw, segment_mid, 444, segment_mid), head = FALSE)
  arrow(cv, c(lx + lw, read_mid, 444, read_mid, 444, 104, rx, 104))
  steps <- list(
    list(list(ln("1. governor, before the cache", 14, bold = TRUE),
              ln(paste(gov_limits[[1]], collapse = ", "), 13, cls = "limits-call"),
              ln(reserve_line(gov_reserves[[1]]), 13, color = muted, cls = "reserve-call")),
         "core"),
    list(list(ln(sprintf("2. cache: %s()", fn("hr_cache_client", "core")), 14, bold = TRUE),
              ln("a hit is returned; nothing is sent", 13)), "core"),
    list(list(ln("3. governor, on a cache miss", 14, bold = TRUE),
              ln(paste(gov_limits[[2]], collapse = ", "), 13, cls = "limits-send"),
              ln(reserve_line(gov_reserves[[2]]), 13, color = muted, cls = "reserve-send")),
         "core"),
    list(list(ln("4. the client answers it", 14, bold = TRUE),
              ln("a provider over HTTP, a mock or a replay", 13)), "neutral"),
    list(list(ln(sprintf("5. %s()", fn("trace_record", "core", internal = TRUE)), 14,
                 bold = TRUE, cls = "fn"),
              ln("adds the call as a step of the trace", 13)), "core"))
  y <- 124
  for (s in steps) {
    arrow(cv, c(rx + rw / 2, y, rx + rw / 2, y + 20))
    y <- y + 20
    h <- max(56, 12 + sum(vapply(s[[1]], function(l) l$size * 1.3, numeric(1))))
    box(cv, rx, y, rw, h, s[[1]], s[[2]])
    y <- y + h
  }
  txt(cv, rx, y + 26, sprintf("A refused request is not sent; %s()", fn("hr_governor", "core")),
      13, color = muted)
  txt(cv, rx, y + 44, "sets the limits for the run.", 13, color = muted)
  y <- y + 64
  box(cv, rx, y, rw, 62, list(
    ln(sprintf("budget: %s()", fn("hr_budget", "core")), 14, bold = TRUE, cls = "fn"),
    ln("readers fit each prompt to the model's", 13),
    ln("context window", 13)), "core")

  # The trace, through every stage.
  ty <- max(end_left, y + 62) + 24
  box(cv, 24, ty, 852, 62, list(
    ln(sprintf("trace: one gr_trace from %s() goes to every stage", fn("hr_trace", "core")), 14,
       bold = TRUE, cls = "fn"),
    ln(sprintf("A \"fast\" run of %s() records: %s", fn("gr_example", "doc"),
               paste(trace_labels, collapse = ", ")), 13)), "core")
  if (ty + 62 + 20 != cv$height) stop(sprintf("Set the document-run height to %s.",
                                              fmt(ty + 62 + 20)), call. = FALSE)

  svg_file(cv, "A document run",
           paste0("answer_document() runs ", length(stages), " stages in order: ",
                  paste(sprintf("%s with %s(), which hands on a %s", stages, stage_fns, handed),
                        collapse = "; "),
                  ". Segmenters and readers that declare model calls send each request ",
                  "through hr_call(): the governor checks ", paste(gov_limits[[1]], collapse = ", "),
                  " and ", gov_reserves[[1]], "; the cache answers a repeat; on a miss the ",
                  "governor checks ", paste(gov_limits[[2]], collapse = ", "), " and ",
                  gov_reserves[[2]], "; the client answers it; trace_record() adds a step. Readers size prompts with ",
                  "hr_budget(). One trace from hr_trace() goes to every stage."))
}

# ---------------------------------------------------------------------------
# 3. composition.svg
# ---------------------------------------------------------------------------

# The composition verbs: the exported functions of the files that build and
# sweep steps.
compose_files <- c("core-compose-step.R", "core-verify-command.R", "doc-steps.R",
                   "core-bench-sweep.R")
verbs <- sort(intersect(names(defined_in)[defined_in %in% compose_files], exports))

# The document steps, and what each takes and returns.
doc_steps <- list(ingest = ns$gr_step("ingest"), segment = ns$gr_step("segment"),
                  retrieve = ns$gr_step_retrieve(), read = ns$gr_step("read"))
must(identical(eval(formals(ns$gr_step)$kind), c("ingest", "segment", "read")),
     "gr_step() builds ingest, segment and read steps")
io <- lapply(doc_steps, function(s) c(attr(s, "input"), attr(s, "output")))
checked <- do.call(ns$hr_chain, c(doc_steps, list(name = "checked")))
settings <- ns$hr_settings(checked)
top_k <- settings$value[settings$step == "retrieve" & settings$param == "top_k"]
must(length(top_k) == 1, "a chain lists retrieve.top_k among its settings")
swept <- names(ns$hr_sweep(checked, data.frame(retrieve.top_k = c(2, 8))))

# A step reads its resolved settings as ctx$step_params (chain_run() in
# R/core-compose-step.R).
probe <- ns$hr_chain(p = ns$hr_step("p", function(input, ctx) ctx$step_params$k,
                                    params = list(k = 7L)), name = "probe")
must(identical(probe$run("x", list()), 7L), "a step in a chain reads ctx$step_params")

# The coding loop: no step that is not held may follow a held command step.
rscript <- file.path(R.home("bin"), "Rscript")
cmd_visible <- ns$hr_step_command("check", c(rscript, "-e", "1"))
cmd_held <- ns$hr_step_command("held", c(rscript, "-e", "1"), held = TRUE)
must(!ns$step_held(cmd_visible) && ns$step_held(cmd_held),
     "hr_step_command() is held only with held = TRUE")
draft <- ns$hr_step("draft", function(input, ctx) input)
revise <- ns$hr_step("revise", function(input, ctx) input)
loop <- ns$hr_chain(draft = draft, check = cmd_visible, revise = revise, held = cmd_held,
                    name = "loop")
must(identical(names(attr(loop, "hr_steps")), c("draft", "check", "revise", "held")),
     "a chain takes draft, visible check, revise, held check")
held_error <- tryCatch({
  ns$hr_chain(draft = draft, held = cmd_held, revise = revise, name = "bad")
  character(0)
}, error = function(e) class(e))
must("hr_held_not_last" %in% held_error, "hr_chain() refuses a step after a held one")

draw_composition <- function() {
  cv <- canvas("composition", 742)
  heading(cv, "Composing steps",
          sprintf("%s() runs steps in order as one arm; each step takes what the one before returned.",
                  fn("hr_chain", "core")))
  section <- function(y, s) txt(cv, 24, y, s, 16, bold = TRUE)

  section(96, "A document chain")
  ctor <- c(ingest = "gr_step(\"ingest\")", segment = "gr_step(\"segment\")",
            retrieve = "gr_step_retrieve()", read = "gr_step(\"read\")")
  bw <- 184
  gap <- (852 - 4 * bw) / 3
  for (i in seq_along(doc_steps)) {
    x <- 24 + (i - 1) * (bw + gap)
    nm <- names(doc_steps)[[i]]
    box(cv, x, 108, bw, 70, list(
      ln(nm, 15, bold = TRUE, color = pal$doc$ink),
      ln(ctor[[nm]], 13, cls = "fn"),
      ln(sprintf("%s in, %s out", io[[nm]][1], io[[nm]][2]), 13, color = muted)), "doc")
    if (i < length(doc_steps)) arrow(cv, c(x + bw, 143, x + bw + gap, 143))
  }
  txt(cv, 24, 204, sprintf(paste0("hr_chain(..., name = \"checked\") returns one %s(); ",
                                  "%s() runs it like any arm."),
                           fn("hr_arm", "core"), fn("hr_benchmark", "core")), 13, color = muted)

  section(244, "Settings")
  bw <- 272
  gap <- (852 - 3 * bw) / 2
  row1 <- list(
    list(ln(sprintf("%s() in an %s()", fn("hr_param", "core"), fn("hr_schema", "core")), 14,
            bold = TRUE, cls = "fn"),
         ln("a type, a default and a range", 13)),
    list(ln(sprintf("%s(params, schema)", fn("hr_step", "core")), 14, bold = TRUE, cls = "fn"),
         ln(sprintf("%s() resolves them", fn("hr_validate", "core")), 13, cls = "fn")),
    list(ln("ctx$step_params", 14, bold = TRUE),
         ln("what the step reads when it runs", 13)))
  row2 <- list(
    list(ln(sprintf("%s(chain)", fn("hr_settings", "core")), 14, bold = TRUE, cls = "fn"),
         ln(sprintf("by path: retrieve.top_k = %s", top_k), 13)),
    list(ln(sprintf("%s(x, retrieve.top_k = 8)", fn("hr_set", "core")), 13, bold = TRUE,
            cls = "fn"),
         ln("builds the chain again", 13)),
    list(ln(sprintf("%s(chain, grid)", fn("hr_sweep", "core")), 14, bold = TRUE, cls = "fn"),
         ln("one arm per row, named as", 13), ln(swept[[1]], 13)))
  for (r in 1:2) {
    rows <- if (r == 1) row1 else row2
    y <- if (r == 1) 256 else 346
    for (i in 1:3) {
      x <- 24 + (i - 1) * (bw + gap)
      box(cv, x, y, bw, 62, rows[[i]], "core")
      if (i < 3) arrow(cv, c(x + bw, y + 31, x + bw + gap, y + 31))
    }
  }
  arrow(cv, c(24 + bw / 2, 318, 24 + bw / 2, 346))
  txt(cv, 24 + bw / 2 + 8, 337, "a chain lists them", 13, color = muted)
  txt(cv, 24, 432, sprintf("%s() records each swept setting as a param.* column.",
                           fn("hr_benchmark", "core")), 13, color = muted)
  txt(cv, 24, 450, sprintf("%s() finds arms that sent the same requests.",
                           fn("hr_sweep_check", "core")), 13, color = muted)

  section(478, "A coding loop: held command steps come last")
  loop_boxes <- list(
    list(list(ln("draft", 15, bold = TRUE), ln("hr_step()", 13, cls = "fn"),
              ln("writes a draft", 13, color = muted)), "core"),
    list(list(ln("visible check", 15, bold = TRUE),
              ln(sprintf("%s()", fn("hr_step_command", "core")), 13, cls = "fn"),
              ln("held = FALSE", 13), ln("result in $check", 13, color = muted)),
         "core"),
    list(list(ln("revise", 15, bold = TRUE), ln("hr_step()", 13, cls = "fn"),
              ln("reads $check, rewrites", 13, color = muted)), "core"),
    list(list(ln("held check", 15, bold = TRUE, color = pal$accent$ink),
              ln("hr_step_command()", 13, cls = "fn"), ln("held = TRUE", 13),
              ln("kept from later steps", 13, color = muted)), "accent"))
  bw <- 192
  gap <- (852 - 4 * bw) / 3
  for (i in seq_along(loop_boxes)) {
    x <- 24 + (i - 1) * (bw + gap)
    box(cv, x, 492, bw, 96, loop_boxes[[i]][[1]], loop_boxes[[i]][[2]])
    if (i < length(loop_boxes)) arrow(cv, c(x + bw, 540, x + bw + gap, 540))
  }
  box(cv, 24, 612, 852, 70, list(
    ln("A held step returns its input unchanged and attaches its result as attr(output, \"hr_held\"),", 13),
    ln(sprintf("which a scorer from %s() reads. %s() refuses any other step after a held one,",
               fn("hr_scorer", "core"), fn("hr_chain", "core")), 13, cls = "fn"),
    ln("with class hr_held_not_last: draft, visible check, revise, held check is the order.", 13)),
    "accent", align = "start")
  verb_lines <- wrap(sprintf("The composition verbs: %s.", paste0(verbs, "()", collapse = ", ")),
                     852, 13)
  for (i in seq_along(verb_lines)) {
    txt(cv, 24, 708 + (i - 1) * 18, verb_lines[[i]], 13, color = muted, cls = "fn")
  }

  svg_file(cv, "Composing steps",
           paste0("A document chain built with hr_chain() from ",
                  paste(sprintf("%s (%s in, %s out)", names(doc_steps),
                                vapply(io, `[`, "", 1), vapply(io, `[`, "", 2)),
                        collapse = ", "),
                  ". Settings flow from hr_param() and hr_schema() through hr_step() and ",
                  "hr_validate() to ctx$step_params; hr_settings() lists them by path, hr_set() ",
                  "changes them and hr_sweep() makes one arm per row. A coding loop runs draft, ",
                  "visible check, revise and held check. No step that is not held may follow a ",
                  "held command step."))
}

# ---------------------------------------------------------------------------
# 4. registry.svg
# ---------------------------------------------------------------------------

kinds <- ns$hr_kinds()
# Which layer registers each kind: the file whose hr_register_kind() call
# names it (register_doc_layer() in R/doc-modules.R, register_core_kinds() in
# R/core-registry-modules.R).
kind_owner <- character(0)
for (f in r_files) {
  src <- paste(readLines(f, warn = FALSE), collapse = "\n")
  hits <- regmatches(src, gregexpr("hr_register_kind\\(\"[a-z]+\"", src))[[1]]
  for (h in hits) kind_owner[[sub("^hr_register_kind\\(\"([a-z]+)\"$", "\\1", h)]] <- basename(f)
}
must(all(names(kinds) %in% names(kind_owner)), "every kind has an hr_register_kind() call")
# Where each kind's registry lives: what its `get` reads.
kind_store <- vapply(names(kinds), function(k) {
  g <- ns$hr_state$kind_access[[k]]$get
  paste(deparse(body(g)), collapse = "")
}, character(1))
must(all(grepl("^(gr|hr)_state\\$[a-z]+$", kind_store)), "each kind's get reads one registry")
# hr_register() goes through the kind's own function (R/doc-modules.R) and
# stamps the contract.
reader_set <- paste(deparse(ns$hr_state$kind_access$reader$set), collapse = "\n")
must(grepl("gr_register_reader(", reader_set, fixed = TRUE) &&
       grepl("stamp_contract(", reader_set, fixed = TRUE),
     "a reader registered by kind goes through gr_register_reader() and stamp_contract()")
must(calls_in_order(ns$hr_register, c("kind_access(kind, \"set\")", "hr_contract_version()")),
     "hr_register() finds the kind's set and passes the contract version")
must(calls_in_order(ns$gr_read, "registry_get(\"reader\", spec$reader)"),
     "gr_read() looks its reader up by name")
must(calls_in_order(ns$gr_read, "rd$fn(chunks, question, client, spec, trace)"),
     "gr_read() calls the entry's fn")
lookup_error <- tryCatch(ns$registry_get("reader", "no-such-reader"),
                         error = function(e) class(e)[1])
kind_error <- tryCatch(ns$registry_get("no-such-kind", "x"), error = function(e) class(e)[1])
must(identical(lookup_error, "gr_unknown_method") && identical(kind_error, "hr_unknown_kind"),
     "an unknown name and an unknown kind raise their own classes")
contract <- ns$hr_contract_version()
signal_contract <- ns$.hr_signal_contract
key_fields <- ns$.hr_calibration_key_fields

draw_registry <- function() {
  cv <- canvas("registry", 750)
  heading(cv, "The registry and modules",
          sprintf("%s() stores a module of any kind, and %s() finds it by kind and name.",
                  fn("hr_register", "core"), fn("registry_get", "core", internal = TRUE)))
  txt(cv, 24, 96, "Registering", 16, bold = TRUE)
  reg <- list(
    list(ln(sprintf("%s(kind, name, fn,", fn("hr_register", "core")), 14, bold = TRUE,
            cls = "fn"),
         ln("..., version)", 14, bold = TRUE)),
    list(ln(sprintf("%s(kind, \"set\")", fn("kind_access", "core", internal = TRUE)), 14,
            bold = TRUE, cls = "fn"),
         ln("goes to the kind's own function,", 13),
         ln(sprintf("such as %s()", fn("gr_register_reader", "doc")), 13, cls = "fn")),
    list(ln("the entry keeps", 14, bold = TRUE),
         ln(sprintf("version, and contract = \"%s\"", contract), 13)))
  bw <- 272
  gap <- (852 - 3 * bw) / 2
  for (i in 1:3) {
    x <- 24 + (i - 1) * (bw + gap)
    box(cv, x, 108, bw, 64, reg[[i]], "neutral")
    if (i < 3) arrow(cv, c(x + bw, 140, x + bw + gap, 140))
  }
  arrow(cv, c(24 + 2 * (bw + gap) + bw / 2, 172, 24 + 2 * (bw + gap) + bw / 2, 196))

  # The kinds, from hr_kinds(), colored by the layer that registers them.
  rect(cv, 24, 196, 852, 180, "neutral", fill = "#ffffff")
  txt(cv, 40, 220, sprintf("The registry: %d kinds, listed by %s()", length(kinds),
                           fn("hr_modules", "core")), 15, bold = TRUE)
  cw <- (852 - 32 - 36) / 4
  for (i in seq_along(kinds)) {
    k <- names(kinds)[[i]]
    st <- if (startsWith(kind_owner[[k]], "core-")) "core" else "doc"
    col <- (i - 1) %% 4
    row <- (i - 1) %/% 4
    box(cv, 40 + col * (cw + 12), 234 + row * 70, cw, 58, list(
      ln(k, 15, bold = TRUE, color = pal[[st]]$ink, cls = "kind"),
      ln(kind_store[[k]], 13)), st)
  }
  # The legend sits in the empty cell after the last kind.
  lx <- 40 + 3 * (cw + 12)
  rect(cv, lx, 312, 18, 14, "doc", rx = 3)
  txt(cv, lx + 26, 324, "document layer kind", 13)
  rect(cv, lx, 338, 18, 14, "core", rx = 3)
  txt(cv, lx + 26, 350, "core kind", 13)

  txt(cv, 24, 430, "Looking up", 16, bold = TRUE)
  # registry_get() reads the registry.
  arrow(cv, c(24 + bw + gap + bw / 2, 376, 24 + bw + gap + bw / 2, 442))
  look <- list(
    list(ln("a spec names a module", 14, bold = TRUE),
         ln("spec$reader = \"stuff\"", 13)),
    list(ln(sprintf("%s(\"reader\", name)", fn("registry_get", "core", internal = TRUE)), 14,
            bold = TRUE, cls = "fn"),
         ln(sprintf("via %s(kind, \"get\")", "kind_access"), 13, cls = "fn")),
    list(ln(sprintf("%s() calls the entry's fn", fn("gr_read", "doc")), 13, bold = TRUE,
            cls = "fn"),
         ln("rd$fn(chunks, question,", 13), ln("client, spec, trace)", 13)))
  for (i in 1:3) {
    x <- 24 + (i - 1) * (bw + gap)
    box(cv, x, 442, bw, 64, look[[i]], "neutral")
    if (i < 3) arrow(cv, c(x + bw, 474, x + bw + gap, 474))
  }
  txt(cv, 24, 524, sprintf("An unknown name is an error of class %s, which lists the registered names;",
                           lookup_error), 13, color = pal$accent$ink)
  txt(cv, 24, 542, sprintf("an unknown kind is an error of class %s.", kind_error), 13,
      color = pal$accent$ink)

  txt(cv, 24, 582, "Two contracts", 16, bold = TRUE)
  hw <- (852 - 16) / 2
  box(cv, 24, 594, hw, 132, list(
    ln(sprintf("Modules: contract %s", contract), 15, bold = TRUE, color = pal$core$ink),
    ln(sprintf("%s() returns \"%s\"", fn("hr_contract_version", "core", internal = TRUE),
               contract), 13, cls = "fn"),
    ln("hr_register() records it on each entry", 13, cls = "fn"),
    ln(sprintf("%s() reports which rules a", fn("hr_check_module", "core")), 13, cls = "fn"),
    ln("module breaks, and does not refuse it", 13)), "core")
  sig_lines <- wrap(sprintf("A record is keyed by %s.", paste(key_fields, collapse = ", ")),
                    hw - 24, 13)
  box(cv, 24 + hw + 16, 594, hw, 132, c(
    list(ln(sprintf("Signal calibrations: contract %s", signal_contract), 15, bold = TRUE,
            color = pal$core$ink),
         ln(sprintf(".hr_signal_contract stays \"%s\", apart from", signal_contract), 13),
         ln(sprintf("modules, for %s()", fn("hr_calibrate_signal", "core")), 13, cls = "fn")),
    lapply(sig_lines, function(s) ln(s, 13))), "core")

  svg_file(cv, "The registry and modules",
           paste0("hr_register(kind, name, fn, ..., version) finds the kind's own function ",
                  "through kind_access(kind, \"set\") and the entry keeps its version and ",
                  "contract ", contract, ". The registry has ", length(kinds), " kinds: ",
                  paste(sprintf("%s (%s)", names(kinds), kind_store), collapse = ", "),
                  ". A lookup such as gr_read() calls registry_get(\"reader\", name), which ",
                  "reads through kind_access(kind, \"get\"), and calls the entry's fn; an ",
                  "unknown name raises ", lookup_error, " and an unknown kind ", kind_error,
                  ". Modules follow contract ", contract, "; signal calibrations keep contract ",
                  signal_contract, " (.hr_signal_contract)."))
}

# ---------------------------------------------------------------------------
# 5. request.svg
# ---------------------------------------------------------------------------

# The life of one request through hr_call(), in the order model_call() takes
# it (R/core-transport-call.R): the cap, the governor's call stage, the
# client's dispatch, the trace step, then a context overflow and its one
# retry. A prompt that leaves no room for a reply is recorded and not sent.
must(calls_in_order(ns$model_call, c(
  "call_cap(", "max_output <= 0L", "trace_record(trace", "governor_check(trace, gate, \"call\")",
  "client_dispatch(client, req)", "governor_refuse(trace", "is_context_overflow(res)",
  "trace_record(trace", "signalCondition(", "overflow_refit(", "model_call(client, smaller")),
  "model_call() caps the reply, checks the governor, dispatches, records, then retries an overflow")
must(grepl("overflow_retry = TRUE", paste(deparse(body(ns$model_call), width.cutoff = 500L),
                                          collapse = "\n"), fixed = TRUE),
     "an overflow is retried once, marked overflow_retry = TRUE")
# A replay client checks the send stage and answers from its recording; it
# has no cache (R/core-transport-call.R).
must(calls_in_order(get("client_dispatch.gr_replay_client", envir = ns),
                    c("req$admit()", "replay_lookup(client, req)")),
     "a replay client checks the send stage and then looks the request up")
# What the cache does not keep.
dispatch_src <- paste(deparse(body(get("client_dispatch.gr_client", envir = ns)),
                              width.cutoff = 500L), collapse = "\n")
must(grepl("isTRUE(res$ok) && !identical(res$finish_reason, \"length\") && usable(res)",
           dispatch_src, fixed = TRUE),
     "the cache keeps only a usable reply that was not cut off")
# HTTP retries (R/core-transport-http.R).
http_src <- paste(deparse(body(ns$http_call), width.cutoff = 500L), collapse = "\n")
must(grepl("status %in% .retryable_status && attempt <= client$max_retries", http_src,
           fixed = TRUE) && grepl("out_of_quota(status, body_text)", http_src, fixed = TRUE),
     "http_call() retries the retryable statuses up to max_retries, and not an account out of quota")
retry_status <- ns$.retryable_status
max_retries <- ns$gr_defaults$max_retries
on_overflow_default <- ns$gr_defaults$on_overflow
must(identical(on_overflow_default, "error"), "on_overflow is \"error\" by default")
must(identical(ns$check_closing(TRUE), TRUE), "hr_call() takes closing = TRUE")
# deparse() breaks a line after `if (...)`, so whitespace is made one space.
gov_src <- gsub("\\s+", " ", paste(deparse(body(ns$governor_check), width.cutoff = 500L),
                                   collapse = " "))
must(grepl("hold <- if (closing) 0 else governor_hold(gov, \"reserve_calls\"", gov_src,
           fixed = TRUE) &&
       grepl("hold <- if (closing) 0 else governor_hold(gov, \"reserve_usd\"", gov_src,
             fixed = TRUE),
     "a closing request may spend reserve_calls and reserve_usd")
must(grepl("\"hr_budget_refused\"", gov_src, fixed = TRUE), "a refusal has class hr_budget_refused")
overflow_phrases <- ns$.hr_overflow_phrases
must("prompt is too long" %in% overflow_phrases, "\"prompt is too long\" names an overflow")

draw_request <- function() {
  # The height is checked at the end, as for document-run.svg.
  cv <- canvas("request", 864)
  heading(cv, "The life of one request",
          sprintf("%s() takes each request down these steps; a refusal, a hit or no room ends it early.",
                  fn("hr_call", "core")))
  mx <- 24
  mw <- 500
  ox <- 564
  ow <- 312
  box(cv, mx, 84, mw, 40, list(ln(sprintf("%s(client, messages, ..., closing = FALSE)",
                                          fn("hr_call", "core")), 14, bold = TRUE, cls = "fn")),
      "core")
  step <- function(title, ...) c(list(ln(title, 14, bold = TRUE, cls = "step")), list(...))
  rows <- list(
    list(main = step(sprintf("1. count and cap: %s()", fn("hr_count_tokens", "core")),
                     ln("counts the prompt; max_output is held to the model's", 13),
                     ln("output limit and to the room its context window leaves", 13)),
         out = list(ln("no room for a reply", 14, bold = TRUE, color = pal$accent$ink),
                    ln("a failed result with status 0;", 13),
                    ln("a step of the trace, never sent", 13)), out_style = "accent"),
    list(main = step("2. governor, before the cache",
                     ln(paste(gov_limits[[1]], collapse = ", "), 13, cls = "limits-call"),
                     ln(reserve_line(gov_reserves[[1]]), 13, color = muted, cls = "reserve-call")),
         out = list(ln("refused", 14, bold = TRUE, color = pal$accent$ink),
                    ln("ok = FALSE, refused = TRUE;", 13),
                    ln("class hr_budget_refused;", 13),
                    ln("not sent and not a step", 13)), out_style = "accent"),
    list(main = step(sprintf("3. cache: %s()", fn("hr_cache_client", "core")),
                     ln(sprintf("an %s() answers from its recording", fn("hr_replay_client", "core")),
                        13, cls = "fn"),
                     ln("instead, and has no cache", 13)),
         out = list(ln("a hit", 14, bold = TRUE),
                    ln("returned with cached = TRUE and", 13),
                    ln("attempts = 0; nothing is paid", 13)), out_style = "core"),
    list(main = step("4. governor, on a cache miss",
                     ln(paste(gov_limits[[2]], collapse = ", "), 13, cls = "limits-send"),
                     ln(reserve_line(gov_reserves[[2]]), 13, color = muted, cls = "reserve-send")),
         out = list(ln("refused", 14, bold = TRUE, color = pal$accent$ink),
                    ln("as at step 2: nothing is sent", 13),
                    ln("and nothing is paid", 13)), out_style = "accent"),
    list(main = step("5. the client sends it",
                     ln(sprintf("%s() retries a dropped connection and HTTP",
                                fn("hr_client", "core")), 13, cls = "fn"),
                     ln(paste(paste(retry_status[-length(retry_status)], collapse = ", "), "and",
                              retry_status[length(retry_status)]), 13, cls = "retry-status"),
                     ln(sprintf("up to max_retries = %d times, pausing between tries;",
                                max_retries), 13),
                     ln("an account out of quota is not retried", 13)),
         main_style = "neutral",
         out = list(ln("the reply is cached", 14, bold = TRUE),
                    ln("unless it failed, was cut off at", 13),
                    ln("its cap or fails the caller's check", 13)), out_style = "core"),
    list(main = step(sprintf("6. %s()", fn("trace_record", "core", internal = TRUE)),
                     ln("adds one step: tokens, cost, seconds, when it started", 13),
                     ln("and ended, and the overflow fields when there is one", 13))),
    list(main = step("7. context overflow",
                     ln("a 400 or 413 whose body says the prompt is too long", 13),
                     ln("signals hr_context_overflow", 13)),
         out = list(ln(sprintf("%s(on_overflow = fn)", fn("hr_options", "core")), 14, bold = TRUE,
                       cls = "fn"),
                    ln("fn makes a smaller prompt, sent", 13),
                    ln("once, from step 1 again; the default", 13),
                    ln(sprintf("\"%s\" returns the failure", on_overflow_default), 13)),
         out_style = "core"))
  need <- function(lines) ceiling(12 + sum(vapply(lines, function(l) l$size * 1.3, numeric(1))))
  y <- 124
  for (r in rows) {
    arrow(cv, c(mx + mw / 2, y, mx + mw / 2, y + 20))
    y <- y + 20
    h <- max(56, need(r$main), if (!is.null(r$out)) need(r$out) else 0)
    box(cv, mx, y, mw, h, r$main, r$main_style %||% "core")
    if (!is.null(r$out)) {
      arrow(cv, c(mx + mw, y + h / 2, ox, y + h / 2), r$out_style)
      box(cv, ox, y, ow, h, r$out, r$out_style)
    }
    y <- y + h
  }
  arrow(cv, c(mx + mw / 2, y, mx + mw / 2, y + 20))
  y <- y + 20
  box(cv, mx, y, 852, 44, list(ln(
    "the result: a gr_result with $ok, $text, $usage, $cached, $attempts and more", 14)))
  if (y + 44 + 20 != cv$height) stop(sprintf("Set the request height to %s.", fmt(y + 44 + 20)),
                                     call. = FALSE)

  svg_file(cv, "The life of one request",
           paste0("hr_call() takes a request through seven steps. 1: it counts the prompt and ",
                  "caps the reply; a prompt that leaves no room is a failed step, not sent. ",
                  "2: the governor checks ", paste(gov_limits[[1]], collapse = ", "), " and ",
                  gov_reserves[[1]], "; a refused request is not sent and not a step. 3: the cache of ",
                  "hr_cache_client() returns a hit with nothing paid; a replay client answers ",
                  "from its recording. 4: on a miss the governor checks ",
                  paste(gov_limits[[2]], collapse = ", "), " and ", gov_reserves[[2]],
                  ". A closing request may spend the ",
                  "reserves. 5: the client sends it; hr_client() retries a dropped connection and ",
                  "HTTP ", paste(retry_status, collapse = ", "), " up to ", max_retries,
                  " times, and the cache keeps a usable reply. 6: trace_record() adds the step. ",
                  "7: a provider's refusal of a prompt that is too long signals ",
                  "hr_context_overflow, and an on_overflow function can retry it once with a ",
                  "smaller prompt. The call returns a gr_result."))
}

written <- c(
  write_svg(draw_layers(), "layers.svg"),
  write_svg(draw_document_run(), "document-run.svg"),
  write_svg(draw_composition(), "composition.svg"),
  write_svg(draw_registry(), "registry.svg"),
  write_svg(draw_request(), "request.svg"))
ns$hr_options(old_opts)
cat(paste0("Wrote ", written, "\n"), sep = "")
