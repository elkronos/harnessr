# record-layers.R: write the layer of every top-level object in R/ to the
# fixture test-boundary.R reads.
#
# Run from the repository root:
#
#   Rscript dev/record-layers.R
#
# The tests run against the installed package, where R/ is not there to read,
# so the layer each object belongs to is taken from the file that defines it
# and kept in tests/testthat/fixtures/boundary/layers.csv. Functions and values
# (environments such as the state of each layer, lists, patterns) are both
# recorded, with `kind` saying which, since a core function that reads a
# document layer value depends on that layer as much as one that calls a
# document layer function:
#
#   core-*.R          core
#   doc-*.R           doc
#   compat-*.R        compat
#   zzz.R and harnessr-package.R   glue
#
# Rerun it after adding, removing, renaming or moving an object, and commit
# the new layers.csv with the change. The rule the test checks (core never
# calls or reads doc) does not change by rerunning this: a new crossing still fails
# until it is removed or listed in allowed.csv.

if (!file.exists("DESCRIPTION") || !dir.exists("R")) {
  stop("Run this from the repository root: Rscript dev/record-layers.R", call. = FALSE)
}

layer_of_file <- function(file) {
  base <- basename(file)
  if (startsWith(base, "core-")) return("core")
  if (startsWith(base, "doc-")) return("doc")
  if (startsWith(base, "compat-")) return("compat")
  if (base %in% c("zzz.R", "harnessr-package.R")) return("glue")
  stop(sprintf("No layer for %s: name it core-, doc- or compat-, or add it to the glue files here.",
               base), call. = FALSE)
}

# Every top-level `name <- value` or `name = value` in R/. Only a plain name on
# the left counts; `x$y <- value` changes an object, it does not define one.
files <- sort(list.files("R", pattern = "[.][Rr]$", full.names = TRUE), method = "radix")
defs <- list()
for (f in files) {
  for (e in parse(f, keep.source = FALSE)) {
    if (!is.call(e) || !(identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("=")))) next
    if (!is.name(e[[2]])) next
    defs[[length(defs) + 1]] <- data.frame(name = as.character(e[[2]]),
                                           file = basename(f),
                                           layer = layer_of_file(f))
  }
}
defs <- do.call(rbind, defs)

# A name defined in two files: the later file in collation order wins when the
# package is built, but both copies are code of their layer, so the two files
# must agree on it.
split_layers <- tapply(defs$layer, defs$name, function(x) length(unique(x)))
if (any(split_layers > 1)) {
  bad <- names(split_layers)[split_layers > 1]
  stop(sprintf("Defined in files of different layers: %s", paste(bad, collapse = ", ")),
       call. = FALSE)
}
# Defined twice in the same layer passes, but say so: only the copy collated
# last is kept, and the other one is dead code.
twice <- tapply(defs$file, defs$name, function(x) length(unique(x)))
if (any(twice > 1)) {
  for (n in names(twice)[twice > 1]) {
    message(sprintf("%s is defined in more than one file: %s", n,
                    paste(unique(defs$file[defs$name == n]), collapse = ", ")))
  }
}
defs <- defs[!duplicated(defs$name, fromLast = TRUE), ]

# Each object as the package has it once loaded, so layers.csv lists exactly
# what the test finds in the namespace. Whether it is a function is read from
# the loaded value, since some functions are made by calling another function.
if (requireNamespace("pkgload", quietly = TRUE)) {
  ns <- suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE,
                                           quiet = TRUE))$env
} else {
  ns <- asNamespace("harnessr")
  message("pkgload is not installed: reading the installed harnessr, which must be current.")
}
# What R and pkgload put in a namespace themselves.
internal <- function(n) grepl("^[.]__", n) | n == ".packageName"
gone <- defs$name[!vapply(defs$name, exists, logical(1), envir = ns, inherits = FALSE)]
if (length(gone) > 0) {
  stop(sprintf("Defined at the top level of R/ but not in the namespace: %s",
               paste(gone, collapse = ", ")), call. = FALSE)
}
defs$kind <- ifelse(vapply(defs$name, function(n) is.function(get(n, envir = ns)), logical(1)),
                    "function", "value")
out <- defs[, c("name", "layer", "kind")]
out <- out[order(out$layer, out$name, method = "radix"), ]

ns_objs <- ls(ns, all.names = TRUE)
stray <- setdiff(ns_objs[!internal(ns_objs)], out$name)
if (length(stray) > 0) {
  stop(sprintf("In the namespace but not defined at the top level of R/: %s",
               paste(stray, collapse = ", ")), call. = FALSE)
}

path <- file.path("tests", "testthat", "fixtures", "boundary", "layers.csv")
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(out, path, row.names = FALSE)
counts <- table(out$layer)
cat(sprintf("%d objects (%d functions): %s\n", nrow(out), sum(out$kind == "function"),
            paste(sprintf("%s %d", names(counts), counts), collapse = ", ")))
cat(sprintf("Wrote %s\n", path))
