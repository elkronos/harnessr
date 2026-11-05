# test-boundary.R -- the core layer does not call the document layer.
#
# R/ is split into core-*.R (the general core), doc-*.R (the document layer),
# compat-*.R (shims) and the glue files zzz.R and harnessr-package.R. No
# function defined in a core file may call a function defined in a doc file,
# except the crossings listed in fixtures/boundary/allowed.csv.
#
# The tests run against the installed package, where R/ is not available, so
# the layer of each function is read from fixtures/boundary/layers.csv. After
# adding, removing or moving a function, run `Rscript dev/record-layers.R`
# from the repository root to rewrite it. allowed.csv is edited by hand and
# should only shrink: when a crossing is removed, delete its row.

boundary_layers <- function() {
  utils::read.csv(test_path("fixtures", "boundary", "layers.csv"),
                  stringsAsFactors = FALSE)
}

boundary_allowed <- function() {
  utils::read.csv(test_path("fixtures", "boundary", "allowed.csv"),
                  stringsAsFactors = FALSE)
}

boundary_ns_functions <- function() {
  ns <- asNamespace("harnessr")
  nms <- ls(ns, all.names = TRUE)
  nms[vapply(nms, function(n) is.function(get(n, envir = ns)), logical(1))]
}

# What a function calls, by name. codetools reports names in call position
# as functions; a function that is only handed on as a value, as in
# lapply(x, helper) or do.call(helper, args), shows up among the variables
# instead. Those count too when they name a namespace function, since passing
# a function along is as much a dependency as calling it. Names given as
# strings (do.call("helper", ...)) are not seen. A qualified call such as
# harnessr:::helper(x) is reported by codetools only as `:::`, so the body is
# also walked for harnessr:: and harnessr::: and the name on the right is added.
boundary_qualified <- function(x) {
  if (is.function(x)) {
    return(c(boundary_qualified(formals(x)), boundary_qualified(body(x))))
  }
  if (!is.call(x) && !is.pairlist(x)) return(character(0))
  if (is.call(x) && (identical(x[[1]], quote(`::`)) || identical(x[[1]], quote(`:::`))) &&
      identical(as.character(x[[2]]), "harnessr")) {
    return(as.character(x[[3]]))
  }
  unlist(lapply(as.list(x), boundary_qualified), use.names = FALSE)
}

boundary_callees <- function(fun, known) {
  g <- codetools::findGlobals(fun, merge = FALSE)
  unique(c(g$functions, intersect(g$variables, known), boundary_qualified(fun)))
}

# Every core -> doc reference in the installed namespace.
boundary_crossings <- function(layers) {
  ns <- asNamespace("harnessr")
  layer <- stats::setNames(layers$layer, layers$name)
  doc <- layers$name[layers$layer == "doc"]
  out <- list()
  for (caller in layers$name[layers$layer == "core"]) {
    if (!exists(caller, envir = ns, inherits = FALSE)) next
    callees <- intersect(boundary_callees(get(caller, envir = ns), layers$name), doc)
    if (length(callees) > 0) {
      out[[caller]] <- data.frame(caller = caller, callee = callees,
                                  stringsAsFactors = FALSE)
    }
  }
  if (length(out) == 0) return(data.frame(caller = character(0), callee = character(0)))
  do.call(rbind, unname(out))
}

test_that("every namespace function is placed in a layer", {
  layers <- boundary_layers()
  missing <- setdiff(boundary_ns_functions(), layers$name)
  expect(length(missing) == 0,
         sprintf(paste("Not in fixtures/boundary/layers.csv: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(missing, collapse = ", ")))
})

test_that("layers.csv names only functions that exist", {
  layers <- boundary_layers()
  odd <- setdiff(layers$layer, c("core", "doc", "compat", "glue"))
  expect(length(odd) == 0, sprintf("Unknown layer in layers.csv: %s.",
                                   paste(odd, collapse = ", ")))
  gone <- setdiff(layers$name, boundary_ns_functions())
  expect(length(gone) == 0,
         sprintf(paste("In fixtures/boundary/layers.csv but not in the namespace: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(gone, collapse = ", ")))
})

test_that("core functions call doc functions only where allowed", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  allowed <- boundary_allowed()
  key <- function(d) paste(d$caller, "->", d$callee)
  new <- setdiff(key(found), key(allowed))
  expect(length(new) == 0,
         sprintf(paste("Core calls the document layer: %s.",
                       "Move the code, or list the pair in fixtures/boundary/allowed.csv",
                       "with the phase that removes it."),
                 paste(new, collapse = "; ")))
})

test_that("every allowed crossing still occurs", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  allowed <- boundary_allowed()
  expect_true(all(nzchar(trimws(allowed$reason))))
  key <- function(d) paste(d$caller, "->", d$callee)
  stale <- setdiff(key(allowed), key(found))
  expect(length(stale) == 0,
         sprintf("No longer crosses, delete from fixtures/boundary/allowed.csv: %s.",
                 paste(stale, collapse = "; ")))
})
