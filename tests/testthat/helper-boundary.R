# helper-boundary.R: the parsing behind test-boundary.R, test-doc-internal.R
# and dev/record-doc-internal.R.
#
# It reads the layer of each object from fixtures/boundary/layers.csv and
# asks codetools what each function in the installed namespace calls, hands
# on or changes. Nothing in this file runs on load: it only defines
# functions, so the recorder can source it from the repository root.

# The fixture directory, from the test directory or from the repository root.
boundary_dir <- function(root = NULL) {
  if (!is.null(root)) return(file.path(root, "tests", "testthat", "fixtures", "boundary"))
  testthat::test_path("fixtures", "boundary")
}

boundary_layers <- function(root = NULL) {
  utils::read.csv(file.path(boundary_dir(root), "layers.csv"), stringsAsFactors = FALSE)
}

boundary_allowed <- function(root = NULL) {
  utils::read.csv(file.path(boundary_dir(root), "allowed.csv"), stringsAsFactors = FALSE)
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

# Every reference from a function of layer `from` to an object of layer `to`
# in the installed namespace, with the kind of object it reaches: a function
# called or handed on, or a value used. The default is the direction the
# boundary forbids: core reaching into the document layer.
boundary_crossings <- function(layers, from = "core", to = "doc") {
  ns <- asNamespace("harnessr")
  kind <- stats::setNames(layers$kind, layers$name)
  target <- layers$name[layers$layer == to]
  callers <- layers$name[layers$layer == from & layers$kind == "function"]
  out <- list()
  for (caller in callers) {
    if (!exists(caller, envir = ns, inherits = FALSE)) next
    callees <- intersect(boundary_callees(get(caller, envir = ns), layers$name), target)
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

# The core functions that are not exported and that some document layer
# function calls or hands on, sorted. This is what
# fixtures/boundary/doc-uses-internal.csv records.
boundary_doc_internal <- function(layers) {
  found <- boundary_crossings(layers, from = "doc", to = "core")
  found <- found[found$kind == "function", ]
  used <- setdiff(unique(found$callee), getNamespaceExports("harnessr"))
  sort(used, method = "radix")
}

boundary_doc_internal_csv <- function(root = NULL) {
  file.path(boundary_dir(root), "doc-uses-internal.csv")
}
