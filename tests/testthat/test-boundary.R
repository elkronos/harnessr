# test-boundary.R: the core layer does not call or read the document layer.
#
# R/ is split into core-*.R (the general core), doc-*.R (the document layer),
# compat-*.R (shims) and the glue files zzz.R and harnessr-package.R. No
# function defined in a core file may call a function defined in a doc file,
# or use a value defined in one (the document layer's state, a pattern, a
# table), except the crossings listed in fixtures/boundary/allowed.csv.
#
# The tests run against the installed package, where R/ is not available, so
# the layer of each object is read from fixtures/boundary/layers.csv. After
# adding, removing or moving an object, run `Rscript dev/record-layers.R`
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

# Every object the package defines, without the ones R and pkgload add to a
# namespace themselves.
boundary_ns_objects <- function() {
  nms <- ls(asNamespace("harnessr"), all.names = TRUE)
  nms[!grepl("^[.]__", nms) & nms != ".packageName"]
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

# The objects a function changes in place without defining: `x$y <- v`,
# `x[[i]] <- v`, names(x) <- v. codetools counts the root of such an assignment
# as a local variable, so gr_state$models <- list() would be invisible to it.
# The root is a local only when the function it sits in, or one around it,
# binds the name itself: as an argument, a for variable or a plain `<-`. Each
# function is its own scope, so an inner function's argument named gr_state
# does not hide a change to the package's gr_state made outside it. A plain
# `<-` counts for its whole function wherever it sits, which is looser than R
# but only matters for code that changes an object and then shadows it.
boundary_assigned <- function(fun) {
  root_of <- function(x) {
    while (is.call(x)) x <- x[[2]]
    if (is.name(x)) as.character(x) else character(0)
  }
  scan <- function(args, body, outer) {
    bound <- args
    roots <- character(0)
    inner <- list()
    walk <- function(x) {
      if (!is.call(x)) return(invisible(NULL))
      op <- if (is.name(x[[1]])) as.character(x[[1]]) else ""
      if (op == "function") {
        inner[[length(inner) + 1L]] <<- x
        return(invisible(NULL))
      }
      if (op %in% c("<-", "=", "<<-") && length(x) == 3L) {
        # `x <<- v` binds nothing here; it changes x in an enclosing scope.
        if (is.name(x[[2]])) {
          if (op != "<<-") bound <<- c(bound, as.character(x[[2]]))
        } else {
          roots <<- c(roots, root_of(x[[2]]))
        }
      }
      if (op == "for") bound <<- c(bound, as.character(x[[2]]))
      lapply(as.list(x), walk)
    }
    walk(body)
    scope <- c(outer, bound)
    out <- setdiff(roots, scope)
    for (f in inner) out <- c(out, scan(names(f[[2]]), f[[3]], scope))
    out
  }
  unique(scan(names(formals(fun)), body(fun), character(0)))
}

boundary_callees <- function(fun, known) {
  g <- codetools::findGlobals(fun, merge = FALSE)
  unique(c(g$functions, intersect(c(g$variables, boundary_assigned(fun)), known),
           boundary_qualified(fun)))
}

# Every core -> doc reference in the installed namespace, with the kind of
# doc object it reaches: a function called or handed on, or a value used.
boundary_crossings <- function(layers) {
  ns <- asNamespace("harnessr")
  kind <- stats::setNames(layers$kind, layers$name)
  doc <- layers$name[layers$layer == "doc"]
  callers <- layers$name[layers$layer == "core" & layers$kind == "function"]
  out <- list()
  for (caller in callers) {
    if (!exists(caller, envir = ns, inherits = FALSE)) next
    callees <- intersect(boundary_callees(get(caller, envir = ns), layers$name), doc)
    if (length(callees) > 0) {
      out[[caller]] <- data.frame(caller = caller, callee = callees,
                                  kind = unname(kind[callees]), stringsAsFactors = FALSE)
    }
  }
  if (length(out) == 0) {
    return(data.frame(caller = character(0), callee = character(0), kind = character(0)))
  }
  do.call(rbind, unname(out))
}

# paste() with "->" gives one string even for no rows, hence the check.
boundary_key <- function(d) if (nrow(d) == 0) character(0) else paste(d$caller, "->", d$callee)

test_that("every namespace object is placed in a layer", {
  layers <- boundary_layers()
  missing <- setdiff(boundary_ns_objects(), layers$name)
  expect(length(missing) == 0,
         sprintf(paste("Not in fixtures/boundary/layers.csv: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(missing, collapse = ", ")))
})

test_that("layers.csv names only objects that exist, as what they are", {
  layers <- boundary_layers()
  odd <- setdiff(layers$layer, c("core", "doc", "compat", "glue"))
  expect(length(odd) == 0, sprintf("Unknown layer in layers.csv: %s.",
                                   paste(odd, collapse = ", ")))
  gone <- setdiff(layers$name, boundary_ns_objects())
  expect(length(gone) == 0,
         sprintf(paste("In fixtures/boundary/layers.csv but not in the namespace: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(gone, collapse = ", ")))
  ns <- asNamespace("harnessr")
  here <- layers[layers$name %in% boundary_ns_objects(), ]
  is_fun <- vapply(here$name, function(n) is.function(get(n, envir = ns)), logical(1))
  wrong <- here$name[is_fun != (here$kind == "function")]
  expect(length(wrong) == 0,
         sprintf(paste("The kind in fixtures/boundary/layers.csv is out of date for: %s.",
                       "Run Rscript dev/record-layers.R from the repository root."),
                 paste(wrong, collapse = ", ")))
})

test_that("core functions call doc functions only where allowed", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  found <- found[found$kind == "function", ]
  new <- setdiff(boundary_key(found), boundary_key(boundary_allowed()))
  expect(length(new) == 0,
         sprintf(paste("Core calls the document layer: %s.",
                       "Move the code, or list the pair in fixtures/boundary/allowed.csv",
                       "with the phase that removes it."),
                 paste(new, collapse = "; ")))
})

test_that("core functions use doc values only where allowed", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  found <- found[found$kind != "function", ]
  new <- setdiff(boundary_key(found), boundary_key(boundary_allowed()))
  expect(length(new) == 0,
         sprintf(paste("Core reads or changes a document layer object: %s.",
                       "Keep what the core needs in hr_state or reach it through a hook,",
                       "or list the pair in fixtures/boundary/allowed.csv with the phase",
                       "that removes it."),
                 paste(new, collapse = "; ")))
})

test_that("every allowed crossing still occurs", {
  skip_if_not_installed("codetools")
  found <- boundary_crossings(boundary_layers())
  allowed <- boundary_allowed()
  expect_true(all(nzchar(trimws(allowed$reason))))
  stale <- setdiff(boundary_key(allowed), boundary_key(found))
  expect(length(stale) == 0,
         sprintf("No longer crosses, delete from fixtures/boundary/allowed.csv: %s.",
                 paste(stale, collapse = "; ")))
})
