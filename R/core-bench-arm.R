# core-bench-arm.R: one configuration to compare, as hr_benchmark() runs it.
#
# An arm is a function of an item and a context. The context hands the arm the
# client, its own trace and the draw it is on, so the arm cannot reach a
# request that the benchmark does not count, limit or key by draw.

#' A configuration to compare in a benchmark
#'
#' An arm is one way of answering the items of a reference: a prompt, a
#' model, a reading recipe, a baseline that calls no model at all. It is a
#' function `run(item, ctx)` that returns the arm's output for one item,
#' which the benchmark's scorer then compares with the item's label.
#'
#' `ctx` is a list with
#' \describe{
#'   \item{`client`}{The client given to [hr_benchmark()].}
#'   \item{`trace`}{A [gr_trace()] of this run alone. Every request the arm
#'     makes must be recorded into it (`gr_call(..., trace = ctx$trace)`):
#'     it is how the benchmark counts the run's tokens, dollars and refusals,
#'     and how it holds the run to the benchmark's limits.}
#'   \item{`governor`}{The [hr_governor()] the run is held to: the
#'     benchmark's limits less what earlier runs used. It is already attached
#'     to `trace`.}
#'   \item{`draw_index`}{The run number, 1 to `runs`. Pass it to
#'     [gr_call()] as `draw_index` so each run is its own draw: under a
#'     [gr_cache()] or a [gr_replay_client()] a request sent without it
#'     answers every run with the same stored reply, and the benchmark
#'     refuses such an arm.}
#'   \item{`call`}{A shortcut, `ctx$call(messages, ...)`, for
#'     `gr_call(ctx$client, messages, ..., trace = ctx$trace, draw_index =
#'     ctx$draw_index)`.}
#'   \item{`item_id`, `arm`, `run`, `params`}{The item's id, the arm's name,
#'     the run number and the arm's `params`.}
#' }
#'
#' @param name The arm's name: one non-blank string, unique within a
#'   benchmark.
#' @param run A function of `(item, ctx)` returning the arm's output for one
#'   item: what the scorer is given (see [hr_scorer()]). `item` is the item's
#'   payload from [hr_reference()].
#' @param params A named list of the settings that make this arm what it is.
#'   They are recorded with the benchmark and reach `run` as `ctx$params`.
#' @param derived_from The name of the arm this one is built from (for an arm
#'   that reuses another's draws offline), or `NULL`.
#' @param version The arm's version, one string. Change it when the arm's
#'   behaviour changes, so results from before and after can be told apart.
#' @return An object of class `hr_arm`: a list of `name`, `run`, `params`,
#'   `derived_from`, `version` and `hash`, a SHA-256 hash of the other five
#'   that changes when the arm's code, settings or version do. The code is
#'   hashed as text, with the values it names from the environment it was
#'   made in: the workspace for an arm written at top level, or the function
#'   of yours that built it. So an arm that reads a global prompt has a new
#'   hash when that prompt changes, and the same arm has the same hash in
#'   every session and after [saveRDS()]. A function from a package is hashed
#'   by its code and the package's name.
#' @seealso [hr_benchmark()], [hr_reference()], [hr_scorer()]
#' @family harness
#' @export
#' @examples
#' short <- hr_arm("short", function(item, ctx) {
#'   ctx$call(paste("Answer in one word:", item))$text
#' }, params = list(prompt = "one word"))
#' short
hr_arm <- function(name, run, params = list(), derived_from = NULL, version = "0.0.1") {
  if (!is_bench_string(name)) {
    gr_abort("`name` must be one non-blank string.", class = "hr_bad_arm")
  }
  # No default: an arm that answers nothing would be scored as a parse
  # failure on every run instead of being caught here.
  if (missing(run)) {
    gr_abort(sprintf("Arm '%s' needs `run`, a function of (item, ctx).", name),
             class = "hr_bad_arm")
  }
  if (!is.function(run)) {
    gr_abort(sprintf("`run` of arm '%s' must be a function of (item, ctx).", name),
             class = "hr_bad_arm")
  }
  # Two arguments, or dots that can take them: the benchmark calls run(item, ctx).
  args <- names(formals(run))
  if (!("..." %in% args) && length(args) < 2L) {
    gr_abort(sprintf("`run` of arm '%s' must take two arguments, (item, ctx).", name),
             class = "hr_bad_arm")
  }
  if (!is.list(params) || (length(params) && (is.null(names(params)) ||
                                               any(!nzchar(names(params)))))) {
    gr_abort(sprintf("`params` of arm '%s' must be a named list.", name), class = "hr_bad_arm")
  }
  if (inherits(derived_from, "hr_arm")) derived_from <- derived_from$name
  if (!is.null(derived_from) && !is_bench_string(derived_from)) {
    gr_abort(sprintf("`derived_from` of arm '%s' must be the name of another arm, or NULL.",
                     name), class = "hr_bad_arm")
  }
  if (identical(derived_from, name)) {
    gr_abort(sprintf("Arm '%s' cannot be derived from itself.", name), class = "hr_bad_arm")
  }
  if (!is_bench_string(version)) {
    gr_abort(sprintf("`version` of arm '%s' must be one non-blank string.", name),
             class = "hr_bad_arm")
  }
  arm <- list(name = name, run = run, params = params, derived_from = derived_from,
              version = version)
  arm$hash <- hr_hash(arm_parts(arm, values = TRUE))
  structure(arm, class = "hr_arm", shape = arm_shape(arm))
}

#' What an arm's hash is computed from: its fields, with `run` replaced by
#' its code and where that code runs.
#'
#' A closure made inside a function (an arm factory) has an unnamed
#' environment, and hashing it by address gave the same arm a new hash in
#' every session and refused an arm read back with readRDS(). So the code is
#' hashed as text, a named environment by its name, and an unnamed one or the
#' global environment by the values its code names there, which are what make
#' one closure from a factory, or one top-level arm reading a global prompt,
#' differ from another. With `values = FALSE` those values are left
#' out: that is the arm's shape, which check_arms() compares.
#' @noRd
arm_parts <- function(arm, values = TRUE) {
  arm <- unclass(arm)[c("name", "run", "params", "derived_from", "version")]
  arm$run <- fn_fingerprint(arm$run, values)
  arm$params <- fingerprint_value(arm$params)
  arm
}

#' A function as code plus where it runs, without any address.
#' @noRd
fn_fingerprint <- function(f, values = FALSE) {
  code <- deparse(f)
  env <- environment(f)
  if (is.null(env)) return(list(code = code, env = "<primitive>"))
  nm <- environmentName(env)
  # The global environment is named, but what an arm written at top level
  # reads from it (a prompt, a model name) is as much the arm as its code, so
  # its values are hashed as a factory's are. A package namespace or another
  # named environment is hashed by its name.
  global <- identical(env, globalenv())
  if (nzchar(nm) && !global) return(list(code = code, env = nm))
  if (!values) return(list(code = code, env = if (global) nm else "<closure>"))
  used <- unique(c(all.names(body(f)),
                   unlist(lapply(formals(f), function(d) all.names(d)), use.names = FALSE)))
  # A name the function takes as an argument is not read from its
  # environment, so a global `item` or `ctx` left over from testing is not
  # part of the arm.
  used <- setdiff(used, names(formals(f)))
  used <- sort(intersect(used, ls(env, all.names = TRUE)))
  vals <- lapply(used, function(v) {
    fingerprint_value(tryCatch(get(v, envir = env, inherits = FALSE),
                               error = function(e) "<unavailable>"))
  })
  list(code = code, env = stats::setNames(vals, used))
}

#' A value with every function in it reduced to its code, so the hash of the
#' value holds no address. Functions found here are not followed into their
#' own environments, whose state (a client's counters) changes as it runs.
#' @noRd
fingerprint_value <- function(x) {
  if (is.function(x)) return(fn_fingerprint(x, values = FALSE))
  if (is.environment(x)) return("<environment>")
  if (is.list(x) && length(x)) {
    cls <- class(x)
    x <- lapply(unclass(x), fingerprint_value)
    class(x) <- cls
  }
  x
}

#' The hash check_arms() compares: the arm's fields and its recorded hash,
#' with `run` as code and environment name only, so it is the same after
#' saveRDS() and in another session, and changes when a field is replaced.
#' @noRd
arm_shape <- function(arm) {
  hr_hash(list(parts = arm_parts(arm, values = FALSE), hash = arm[["hash"]]))
}

#' @export
print.hr_arm <- function(x, ...) {
  cat(sprintf("<hr_arm %s> version %s\n", x$name, x$version))
  if (!is.null(x$derived_from)) cat(sprintf("  derived from: %s\n", x$derived_from))
  if (length(x$params)) {
    vals <- vapply(x$params, function(v) {
      if (is.atomic(v) && length(v) == 1L) as.character(v) else sprintf("<%s>", class(v)[1])
    }, character(1))
    cat("  params:", paste(sprintf("%s = %s", names(x$params), vals), collapse = ", "), "\n")
  }
  cat(sprintf("  hash: %s\n", substr(x$hash, 1, 12)))
  invisible(x)
}

#' One non-blank string.
#' @noRd
is_bench_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

#' The arms given to hr_benchmark(), as a list of hr_arm with unique names.
#' @noRd
check_arms <- function(arms) {
  if (inherits(arms, "hr_arm")) arms <- list(arms)
  if (!is.list(arms) || !length(arms) ||
      !all(vapply(arms, inherits, logical(1), what = "hr_arm"))) {
    gr_abort("`arms` must be an hr_arm() or a list of them.", class = "hr_bad_arm")
  }
  nms <- vapply(arms, function(a) a$name, character(1))
  dup <- unique(nms[duplicated(nms)])
  if (length(dup)) {
    gr_abort(sprintf("Arm names must be unique; repeated: %s.", paste(dup, collapse = ", ")),
             class = "hr_bad_arm")
  }
  # An arm whose hash no longer matches was changed with `$<-` after it was
  # built, and its recorded hash would describe code that did not run.
  for (a in arms) {
    if (!identical(attr(a, "shape", exact = TRUE), arm_shape(a))) {
      gr_abort(sprintf("Arm '%s' was changed after hr_arm() built it; build it again.", a$name),
               class = "hr_bad_arm")
    }
  }
  # An arm derived from one that is not in this benchmark cannot have its
  # draws checked against that arm here.
  for (a in arms) {
    if (!is.null(a$derived_from) && !a$derived_from %in% nms) {
      gr_warn(sprintf("Arm '%s' is derived from '%s', which is not in this benchmark.",
                      a$name, a$derived_from), class = "hr_unknown_parent_arm")
    }
  }
  stats::setNames(arms, nms)
}
