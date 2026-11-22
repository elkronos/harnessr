# core-compose-step.R: steps, and chains of steps that run as one arm.
#
# A step is a function of (input, ctx) that does one part of a run, with the
# settings it was built with recorded beside it. A chain runs its steps in
# order, each given what the one before returned, and is an ordinary hr_arm,
# so hr_benchmark(), hr_sweep() and hr_report() take it as they take any arm.
# The chain's configuration hash is built from its steps' code, the values
# that code reads and their resolved settings, so two chains that would send
# the same requests share it and two that would not do not.

#' A step of a run, with the settings it was built with
#'
#' A step does one part of a run: it takes what the step before it returned
#' (the item, for the first step) and returns what the next step takes.
#' [hr_chain()] runs steps in order as one [hr_arm()]. [gr_step()] and
#' [gr_step_retrieve()] build the document steps (ingest, segment, retrieve,
#' read) with this function.
#'
#' Give exactly one of `fn` and `build`:
#' \describe{
#'   \item{`fn`}{A function of `(input, ctx)`. Inside a chain, `ctx` is the
#'     context [hr_benchmark()] gives the arm (see [hr_arm()]), with two more
#'     entries: `step`, the step's name in the chain, and `step_params`, its
#'     resolved settings. `ctx$params` is still the arm's `params`.}
#'   \item{`build`}{A function of one argument, the step's settings as a
#'     named list, that returns such a function. It is called here, so a
#'     setting it checks is checked when the step is built, not on the first
#'     run of a benchmark.}
#' }
#'
#' With a `schema` (an [hr_schema()]), the settings in `params` that the
#' schema names are checked and resolved by [hr_validate()], and every
#' setting the schema has is filled from its default. A setting the schema
#' does not name is an error of class `hr_unknown_param` for a step given
#' `fn`. A step given `build` keeps it as a fixed extra setting, which
#' reaches `build` but is not part of the schema. Without a schema, `params`
#' is kept as given.
#'
#' `input` and `output` say what the step takes and returns, so
#' [hr_chain()] can check the order of its steps: `"document"` (a file, URL
#' or text), `"doc"` (an ingested document), `"chunks"`, `"answer"` or
#' `"state"` (anything else). `NULL` declares nothing.
#'
#' @param name The step's name: one non-blank string. [hr_chain()] uses it
#'   when the step is given without a name.
#' @param fn A function of `(input, ctx)`, or of `...`; `NULL` when `build`
#'   is given.
#' @param params A named list of the step's settings.
#' @param schema An [hr_schema()] the settings are checked against, or
#'   `NULL`.
#' @param input,output What the step takes and returns: `NULL` or one of
#'   `"document"`, `"doc"`, `"chunks"`, `"answer"` and `"state"`.
#' @param version The step's version, one string. Change it when the step's
#'   behaviour changes.
#' @param build A function of the settings that returns the step's function,
#'   or `NULL` when `fn` is given.
#' @param skill Reserved for a later release; must be `NULL`.
#' @return A function of `(input, ctx)` with class `hr_step` and the
#'   attributes `name`, `params` (as given), `resolved` (the settings the
#'   schema resolved, or `params` without a schema), `extras` (settings the
#'   schema does not name), `schema`, `input`, `output`, `version`, `build`
#'   and `fingerprint`, a hash of the step's code, the values it reads, its
#'   settings and its version.
#' @seealso [hr_chain()], [gr_step()], [hr_arm()]
#' @family harness
#' @export
#' @examples
#' shout <- hr_step("shout", function(input, ctx) {
#'   paste0(toupper(input), strrep("!", ctx$step_params$marks))
#' }, params = list(marks = 2L),
#'    schema = hr_schema(hr_param("marks", "integer", default = 1L, min = 0, max = 5)))
#' attr(shout, "resolved")
#' shout("hello", list(step_params = attr(shout, "resolved")))
hr_step <- function(name, fn = NULL, params = list(), schema = NULL, input = NULL,
                    output = NULL, version = "0.0.1", build = NULL, skill = NULL) {
  if (missing(name) || !is_bench_string(name)) {
    gr_abort("`name` must be one non-blank string.", class = c("hr_bad_step", "gr_bad_setting"))
  }
  what <- sprintf("Step '%s'", name)
  if (!is.null(skill)) {
    gr_abort(sprintf("%s: `skill` is not used yet; leave it NULL.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (is.null(fn) == is.null(build)) {
    gr_abort(sprintf("%s needs exactly one of `fn` and `build`.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (!is.null(build) && !is.function(build)) {
    gr_abort(sprintf("%s: `build` must be a function of the step's settings.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (is.null(params)) params <- list()
  if (!is.list(params) || (length(params) && (is.null(names(params)) ||
                                               anyNA(names(params)) ||
                                               any(!nzchar(names(params))) ||
                                               anyDuplicated(names(params))))) {
    gr_abort(sprintf("%s: `params` must be a list with every element named once.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (!is.null(schema) && !inherits(schema, "hr_schema")) {
    gr_abort(sprintf("%s: `schema` must come from hr_schema(), or be NULL.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  input <- step_io(input, "input", what)
  output <- step_io(output, "output", what)
  if (!is_bench_string(version)) {
    gr_abort(sprintf("%s: `version` must be one non-blank string.", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  if (is.null(schema)) {
    resolved <- params
    extras <- list()
  } else {
    named <- names(params) %in% names(schema)
    if (!all(named) && is.null(build)) {
      unknown <- names(params)[!named]
      gr_abort(sprintf("%s: %s not a setting of its schema. Settings: %s.", what,
                       paste0("'", unknown, "'", collapse = ", "),
                       paste(names(schema), collapse = ", ")),
               class = c("hr_unknown_setting", "hr_unknown_param", "gr_bad_setting"))
    }
    resolved <- hr_validate(schema, params[named])
    extras <- params[!named]
  }
  # An empty list is kept without names, whatever it was cut from.
  if (!length(params)) params <- list()
  if (!length(resolved)) resolved <- list()
  if (!length(extras)) extras <- list()
  if (!is.null(build)) fn <- build(c(resolved, extras))
  if (!is.function(fn)) {
    gr_abort(sprintf("%s: %s a function of (input, ctx).", what,
                     if (is.null(build)) "`fn` must be" else "`build` must return"),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  args <- names(formals(fn))
  if (!("..." %in% args) && length(args) < 2L) {
    gr_abort(sprintf("%s: its function must take two arguments, (input, ctx).", what),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  fp <- hr_hash(list(fn_fingerprint(step_bare(fn), values = TRUE, follow = TRUE),
                     fingerprint_value(resolved), fingerprint_value(extras), version))
  cls <- unique(c(setdiff(oldClass(fn), c("hr_step", "function")), "hr_step", "function"))
  structure(fn, class = cls, name = name, params = params, resolved = resolved,
            extras = extras, schema = schema, input = input, output = output,
            version = version, build = build, fingerprint = fp)
}

#' @export
print.hr_step <- function(x, ...) {
  io <- c(attr(x, "input", exact = TRUE) %||% "?", attr(x, "output", exact = TRUE) %||% "?")
  cat(sprintf("<hr_step> %s (%s to %s) version %s\n", attr(x, "name", exact = TRUE),
              io[1], io[2], attr(x, "version", exact = TRUE)))
  p <- attr(x, "params", exact = TRUE)
  if (length(p)) {
    cat("  params:", paste(sprintf("%s = %s", names(p),
                                   vapply(p, format_setting_value, character(1))),
                           collapse = ", "), "\n")
  }
  invisible(x)
}

#' Run steps in order as one arm
#'
#' `hr_chain()` turns steps into an [hr_arm()] whose run passes the item to
#' the first step, what that returns to the second, and so on, and returns
#' what the last step returns. Each step is called as `step(x, ctx)`, where
#' `ctx` is the arm's context with `ctx$step` (the step's name) and
#' `ctx$step_params` (its resolved settings) added; `ctx$params` stays the
#' arm's `params`.
#'
#' Steps come from [hr_step()], [gr_step()] or [gr_step_retrieve()]. A named
#' argument names its step, and the name is written into the step; an
#' unnamed one keeps the step's own name. Names must be unique, must not
#' contain a dot (a setting is named `"step.setting"`) and must not be
#' `name` or `version`.
#'
#' Given a chain first, `hr_chain()` derives a new chain from it: `x = NULL`
#' drops step `x`, `x = step` replaces step `x` where it stands, and a step
#' under a new name is added at the end. So `hr_chain(checked, judge = NULL,
#' name = "nojudge")` is `checked` without its judge.
#'
#' The order is checked when the chain is built, from what each step
#' declares it takes and returns. A step that takes `"chunks"` when no step
#' before it returns chunks warns with class `hr_chain_gap`: a [gr_step()]
#' read step would cut the document at the default settings without saying
#' so. After a step that returns `"answer"`, only steps that take
#' `"answer"` or `"state"`, or declare nothing, may follow; any other is an
#' error of class `hr_bad_chain`.
#'
#' The arm records each step's settings as given, as `"step.setting"`, in
#' `params` and as the settings [hr_benchmark()] turns into `param.*`
#' columns. Its configuration, which [hr_sweep()] and [hr_benchmark()]
#' compare, is a hash of the steps' names, versions, code, the values that
#' code reads and the resolved settings, so a setting given at its default
#' gives the same configuration as the setting left out.
#'
#' @param ... Steps, or a chain to derive from followed by steps and `NULL`s.
#' @param name The chain's name, one string, as an arm's name.
#' @param version The chain's version, one string.
#' @return An [hr_arm()] with the attribute `hr_steps`, the named list of its
#'   steps in order.
#' @seealso [hr_step()], [gr_step()], [hr_benchmark()], `vignette("compose")`
#' @family harness
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ref <- gr_qa_reference(
#'   questions = c(revenue = "What was revenue in 2024?"),
#'   documents = gr_example(), answers = list("45.2 million"), split = "test")
#' tidy <- hr_step("tidy", function(a, ctx) {
#'   a$answer <- trimws(a$answer)
#'   a
#' }, input = "answer", output = "answer")
#' checked <- hr_chain(segment = gr_step("segment"),
#'                     retrieve = gr_step_retrieve(top_k = 4),
#'                     read = gr_step("read", reader = "stuff"),
#'                     tidy = tidy, name = "checked")
#' plain <- hr_chain(checked, tidy = NULL, name = "plain")
#' names(attr(plain, "hr_steps"))
#' old <- gr_options(verbose = FALSE)
#' bench <- hr_benchmark(list(checked, plain), ref, runs = 5, client = cl,
#'                       scorer = gr_scorer_answer())
#' table(bench$arm, bench$correct)
#' gr_options(old)
hr_chain <- function(..., name, version = "0.0.1") {
  if (missing(name) || !is_bench_string(name)) {
    gr_abort("A chain needs `name`, one non-blank string.", class = c("hr_bad_chain", "hr_bad_arm"))
  }
  if (!is_bench_string(version)) {
    gr_abort(sprintf("`version` of chain '%s' must be one non-blank string.", name),
             class = c("hr_bad_chain", "hr_bad_arm"))
  }
  what <- sprintf("Chain '%s'", name)
  args <- list(...)
  given <- names(args) %||% rep("", length(args))
  given[is.na(given)] <- ""
  steps <- list()
  from <- character(0)
  if (length(args) && inherits(args[[1]], "hr_arm")) {
    base <- attr(args[[1]], "hr_steps", exact = TRUE)
    if (!is.list(base) || !length(base)) {
      gr_abort(sprintf("%s: arm '%s' was not built by hr_chain(), so it has no steps to derive from.",
                       what, args[[1]]$name), class = "hr_bad_chain")
    }
    steps <- base
    from <- names(base)
    args <- args[-1]
    given <- given[-1]
  }
  seen <- character(0)
  for (i in seq_along(args)) {
    s <- args[i][[1]]
    nm <- given[[i]]
    if (is.null(s)) {
      if (!length(from)) {
        gr_abort(sprintf("%s: `NULL` drops a step only when deriving from a chain.", what),
                 class = "hr_bad_chain")
      }
      if (!nzchar(nm) || !nm %in% names(steps)) {
        gr_abort(sprintf("%s: there is no step '%s' to drop. Steps: %s.", what, nm,
                         paste(names(steps), collapse = ", ")), class = "hr_bad_chain")
      }
      steps[[nm]] <- NULL
      seen <- c(seen, nm)
      next
    }
    if (!inherits(s, "hr_step")) {
      gr_abort(sprintf(paste0("%s: argument %d is not a step. Build steps with hr_step(), ",
                              "gr_step() or gr_step_retrieve(); only the first argument may ",
                              "be a chain to derive from."), what, i), class = "hr_bad_chain")
    }
    if (!nzchar(nm)) nm <- attr(s, "name", exact = TRUE)
    chain_check_name(nm, what)
    if (nm %in% seen || (nm %in% names(steps) && !nm %in% from)) {
      gr_abort(sprintf("%s names step '%s' more than once.", what, nm), class = "hr_bad_chain")
    }
    seen <- c(seen, nm)
    attr(s, "name") <- nm
    steps[[nm]] <- s
  }
  if (!length(steps)) {
    gr_abort(sprintf("%s has no steps.", what), class = "hr_bad_chain")
  }
  chain_check_order(steps, what)
  nms <- names(steps)
  chain_fp <- hr_hash(list(
    steps = lapply(nms, function(n) {
      s <- steps[[n]]
      list(name = n, version = attr(s, "version", exact = TRUE),
           fingerprint = attr(s, "fingerprint", exact = TRUE),
           resolved = fingerprint_value(attr(s, "resolved", exact = TRUE)),
           extras = fingerprint_value(attr(s, "extras", exact = TRUE)))
    }),
    version = version))
  flat <- list()
  for (n in nms) {
    p <- attr(steps[[n]], "params", exact = TRUE)
    for (k in names(p)) flat[paste0(n, ".", k)] <- list(p[[k]])
  }
  known <- unlist(lapply(nms, function(n) {
    sc <- attr(steps[[n]], "schema", exact = TRUE)
    if (inherits(sc, "hr_schema")) paste0(n, ".", names(sc)) else character(0)
  }), use.names = FALSE)
  run <- chain_run(chain_fp, lapply(steps, step_bare), nms,
                   lapply(steps, function(s) attr(s, "resolved", exact = TRUE)))
  arm <- hr_arm(name, run, params = flat, version = version)
  arm <- arm_annotate(arm, settings = flat, config = chain_fp,
                      known = as.character(known))
  attr(arm, "hr_steps") <- steps
  arm
}

#' The run function of a chain. `chain_fp` is named in the body so the arm's
#' hash, which hashes the values a run function names, changes with any step's
#' code, closure values or settings; the step functions themselves are hashed
#' there by their code only.
#' @noRd
chain_run <- function(chain_fp, fns, snames, sparams) {
  force(chain_fp)
  force(fns)
  force(snames)
  force(sparams)
  function(item, ctx) {
    chain_fp
    x <- item
    base <- if (is.list(ctx)) ctx else list()
    for (i in seq_along(fns)) {
      sctx <- base
      sctx[["step"]] <- snames[[i]]
      sctx["step_params"] <- list(sparams[[i]])
      x <- fns[[i]](x, sctx)
    }
    x
  }
}

#' A step's function without its attributes, so its code is hashed and
#' called without the settings and schema it carries.
#' @noRd
step_bare <- function(fn) {
  attributes(fn) <- NULL
  fn
}

#' @noRd
step_io <- function(x, arg, what) {
  if (is.null(x)) return(NULL)
  kinds <- c("document", "doc", "chunks", "answer", "state")
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% kinds) {
    gr_abort(sprintf("%s: `%s` must be NULL or one of %s.", what, arg,
                     paste0("\"", kinds, "\"", collapse = ", ")),
             class = c("hr_bad_step", "gr_bad_setting"))
  }
  x
}

#' @noRd
chain_check_name <- function(nm, what) {
  if (!is_bench_string(nm)) {
    gr_abort(sprintf("%s: every step needs a non-blank name.", what), class = "hr_bad_chain")
  }
  if (grepl(".", nm, fixed = TRUE)) {
    gr_abort(sprintf(paste0("%s: step name '%s' has a dot. Settings are named ",
                            "\"step.setting\", so a step name cannot have one."), what, nm),
             class = "hr_bad_chain")
  }
  if (nm %in% c("name", "version")) {
    gr_abort(sprintf("%s: '%s' is an argument of hr_chain() and cannot name a step.", what, nm),
             class = "hr_bad_chain")
  }
  invisible(NULL)
}

#' Check the order of a chain's steps from what each takes and returns.
#' @noRd
chain_check_order <- function(steps, what) {
  have <- "document"
  answered <- NULL
  for (n in names(steps)) {
    input <- attr(steps[[n]], "input", exact = TRUE)
    output <- attr(steps[[n]], "output", exact = TRUE)
    if (!is.null(answered) && !is.null(input) && !input %in% c("answer", "state")) {
      gr_abort(sprintf(paste0("%s: step '%s' takes \"%s\", but it comes after step '%s', ",
                              "which returns the answer. After an answer only steps that take ",
                              "\"answer\" or \"state\" can follow."), what, n, input, answered),
               class = "hr_bad_chain")
    }
    if (identical(input, "chunks") && !"chunks" %in% have) {
      gr_warn(sprintf(paste0("%s: step '%s' takes chunks, but no step before it returns ",
                             "them, so it will cut the document into chunks at the default ",
                             "settings. Add a segment step before it to choose them."), what, n),
              class = "hr_chain_gap")
    }
    if (!is.null(output)) have <- c(have, output)
    if (identical(output, "answer")) answered <- n
  }
  invisible(NULL)
}
