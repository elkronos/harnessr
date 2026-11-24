# core-compose-step.R: steps, and chains of steps that run as one arm.
#
# A step is a function of (input, ctx) that does one part of a run, with the
# settings it was built with recorded beside it. A chain runs its steps in
# order, each given what the one before returned, and is an ordinary hr_arm,
# so hr_benchmark() and hr_report() take it as they take any arm.
# hr_settings() lists a step's or a chain's settings by "step.setting" path,
# and hr_set() builds the chain again with some of them changed, which is how
# hr_sweep() sweeps a chain by name.
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
#' @param skill A skill from [hr_skill()], or `NULL`. Inside [hr_chain()],
#'   the step's `ctx$call()` and `ctx$call_json()` send the skill's
#'   instructions and references as a system message before the step's own
#'   messages, and `ctx$skill` holds the skill. The skill's hash is kept as
#'   the fixed setting `skill` and is part of the fingerprint, and the
#'   skill's version, when it has one, is the step's version.
#' @return A function of `(input, ctx)` with class `hr_step` and the
#'   attributes `name`, `params` (as given), `resolved` (the settings the
#'   schema resolved, or `params` without a schema), `extras` (settings the
#'   schema does not name), `schema`, `input`, `output`, `version`, `build`
#'   `skill` and `fingerprint`, a hash of the step's code, the values it
#'   reads, its settings and its version.
#' @seealso [hr_chain()], [gr_step()], [hr_arm()], [hr_set()]
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
    if (!inherits(skill, "hr_skill")) {
      gr_abort(sprintf("%s: `skill` must come from hr_skill(), or be NULL.", what),
               class = c("hr_bad_skill", "hr_bad_step", "gr_bad_setting"))
    }
    if (is_bench_string(skill$version)) version <- skill$version
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
  # After `build`, which has no use for it: the step reaches the skill
  # through ctx$skill.
  if (!is.null(skill)) extras[["skill"]] <- skill$hash
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
            version = version, build = build, skill = skill, fingerprint = fp)
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
  sk <- attr(x, "skill", exact = TRUE)
  if (!is.null(sk)) cat(sprintf("  skill: %s (%s)\n", sk$name, substr(sk$hash, 1L, 12L)))
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
#' so. A step that takes `"doc"` with no step before it returning one does
#' not warn: a chain usually starts at the segment step, which reads the
#' document at the default ingest settings, and a warning there would fire
#' on almost every chain. Add an ingest step first to choose those
#' settings. After a step that returns `"answer"`, only steps that take
#' `"answer"` or `"state"`, or declare nothing, may follow; any other is an
#' error of class `hr_bad_chain`. A held command step (see
#' [hr_step_command()]) must come last, or be followed only by other held
#' steps; any other step after it is an error of class `hr_held_not_last`.
#'
#' The arm records each step's settings as given, as `"step.setting"`, in
#' `params` and as the settings [hr_benchmark()] turns into `param.*`
#' columns. Its configuration, which [hr_sweep()] and [hr_benchmark()]
#' compare, is a hash of the steps' names, versions, code, the values that
#' code reads and the resolved settings, so a setting given at its default
#' gives the same configuration as the setting left out. [hr_settings()]
#' lists every setting of the chain by path, [hr_set()] changes some of
#' them, and [hr_sweep()] sweeps them by path, as
#' `hr_sweep(chain, data.frame(retrieve.top_k = c(2, 8)))`.
#'
#' @param ... Steps, or a chain to derive from followed by steps and `NULL`s.
#' @param name The chain's name, one string, as an arm's name.
#' @param version The chain's version, one string.
#' @return An [hr_arm()] with the attribute `hr_steps`, the named list of its
#'   steps in order.
#' @seealso [hr_step()], [gr_step()], [hr_settings()], [hr_set()], [hr_benchmark()],
#'   `vignette("compose")`
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
  chain_check_held(steps, what)
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
    sk <- attr(steps[[n]], "skill", exact = TRUE)
    if (!is.null(sk)) flat[[paste0(n, ".skill")]] <- skill_label(sk)
  }
  known <- unlist(lapply(nms, function(n) {
    sc <- attr(steps[[n]], "schema", exact = TRUE)
    if (inherits(sc, "hr_schema")) paste0(n, ".", names(sc)) else character(0)
  }), use.names = FALSE)
  run <- chain_run(chain_fp, lapply(steps, step_runner), nms,
                   lapply(steps, function(s) attr(s, "resolved", exact = TRUE)))
  arm <- hr_arm(name, run, params = flat, version = version)
  arm <- arm_annotate(arm, settings = flat, config = chain_fp,
                      known = as.character(known))
  attr(arm, "hr_steps") <- steps
  arm_annotate(arm, rebuild = chain_rebuild(arm))
}

#' The function hr_sweep() calls to build a chain again with some settings
#' changed and under a new name.
#' @noRd
chain_rebuild <- function(arm) {
  force(arm)
  function(changes, name) arm_rename(do.call(hr_set, c(list(arm), changes)), name)
}

#' List the settings of a step or a chain
#'
#' `hr_settings()` lists every setting that [hr_set()] can change: one row
#' per setting of each step's schema, with the value the step resolved it
#' to, whether it was given or left at its default, and what the schema
#' declares about it (default, range, type, tier and evidence). In a chain a
#' setting is named by its path, `"step.setting"`, as in [hr_set()], in
#' [hr_sweep()]'s grid and in the `param.*` columns of [hr_benchmark()]:
#' `paste(step, param, sep = ".")`.
#'
#' A step with no schema has no rows: its settings are fixed when it is
#' built. Neither has a setting the schema does not name, which a step
#' built with `build` keeps as a fixed extra (see [hr_step()]); to change
#' one, build the step again and replace it with [hr_chain()].
#'
#' Only steps and chains carry schemas. An arm from [gr_arm()] is a recipe,
#' whose settings [gr_settings_table()] lists, and an arm from [hr_arm()]
#' alone records none, so either is an error of class `hr_bad_arm`.
#'
#' The arm attribute `hr_settings`, which [hr_benchmark()] turns into
#' `param.*` columns, is a different thing: it holds only the settings the
#' chain was given, as `"step.setting"`, while this function lists every
#' setting with its resolved value.
#'
#' @param x A step from [hr_step()], [gr_step()] or [gr_step_retrieve()], or
#'   an arm built by [hr_chain()].
#' @return A data frame with one row per setting: `step` (the step's name in
#'   the chain, or the step's own name), `param`, `value` (the resolved value
#'   as text), `set` (`TRUE` when the value was given rather than left at its
#'   default), and from the schema `default`, `range`, `type`, `tier`,
#'   `status` and `source` (the evidence for the default, `NA` when none is
#'   declared).
#' @seealso [hr_set()], [hr_sweep()], [hr_chain()], [gr_settings_table()]
#' @family harness
#' @export
#' @examples
#' chain <- hr_chain(segment = gr_step("segment"),
#'                   retrieve = gr_step_retrieve(top_k = 4),
#'                   read = gr_step("read", reader = "stuff"), name = "checked")
#' s <- hr_settings(chain)
#' s[s$set, c("step", "param", "value", "default")]
#' hr_settings(gr_step_retrieve())[, c("param", "value", "range")]
hr_settings <- function(x) {
  steps <- settings_steps(x, "hr_settings")
  rows <- lapply(names(steps), function(n) {
    s <- steps[[n]]
    sc <- attr(s, "schema", exact = TRUE)
    if (!inherits(sc, "hr_schema") || !length(sc)) return(NULL)
    d <- as.data.frame(sc)
    res <- attr(s, "resolved", exact = TRUE)
    given <- names(attr(s, "params", exact = TRUE))
    data.frame(step = rep(n, nrow(d)), param = d$name,
               value = vapply(d$name, function(k) format_setting_value(res[[k]]),
                              character(1), USE.NAMES = FALSE),
               set = d$name %in% given, default = d$default, range = d$range,
               type = d$type, tier = d$tier, status = d$status, source = d$source,
               stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) {
    return(data.frame(step = character(0), param = character(0), value = character(0),
                      set = logical(0), default = character(0), range = character(0),
                      type = character(0), tier = character(0), status = character(0),
                      source = character(0), stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Change some settings of a step or a chain
#'
#' `hr_set()` builds a step or a chain again with some settings changed and
#' the rest as they were. In a chain each setting is named by its path,
#' `"step.setting"` (split at the first dot), as [hr_settings()] lists them:
#' `hr_set(chain, retrieve.top_k = 8)`. For a single step, the setting's
#' own name is enough: `hr_set(step, top_k = 8)`.
#'
#' Only settings of a step's schema can be changed. A path whose step is
#' not in the chain, or whose setting is not in that step's schema, is an
#' error of class `hr_unknown_setting` (also `hr_unknown_param` and
#' `gr_bad_setting`) that lists the settings of the step it names, or the
#' steps of the chain. A setting the schema
#' does not name, which a step built with `build` keeps as a fixed extra, is
#' refused the same way.
#'
#' The new values are checked by [hr_validate()] as when the step was built,
#' so a number outside its range is moved to the nearest bound with a
#' warning of class `hr_param_clamped` (also `gr_clamped`), and a value the
#' step's constructor refuses, such as an unknown reader, is an error. Each step that changed is built again from its
#' settings, through its `build` function when it has one, so a setting its
#' constructor checks is checked here, and keeps its class: a [gr_step()]
#' stays a `gr_step`.
#'
#' The chain is then built again by [hr_chain()] under its own name and
#' version, with the changed steps in place, so its hash and configuration
#' are those of the new settings. A setting changed to its default gives the
#' configuration of the chain with that setting left out. [hr_sweep()]
#' calls `hr_set()` for each row of its grid when given a chain, which is
#' how a chain is swept by name.
#'
#' @param x A step from [hr_step()], [gr_step()] or [gr_step_retrieve()], or
#'   an arm built by [hr_chain()].
#' @param ... The settings to change, each named: `"step.setting" = value`
#'   for a chain, `setting = value` for a single step.
#' @return `x` built again with the settings changed: a step of the same
#'   class, or an arm from [hr_chain()] with the same name and version. With
#'   no settings given, `x` as it is.
#' @seealso [hr_settings()], [hr_sweep()], [hr_chain()], [hr_validate()]
#' @family harness
#' @export
#' @examples
#' chain <- hr_chain(segment = gr_step("segment"),
#'                   retrieve = gr_step_retrieve(top_k = 4),
#'                   read = gr_step("read", reader = "stuff"), name = "checked")
#' wider <- hr_set(chain, retrieve.top_k = 8, segment.max_tokens = 300)
#' wider$params
#' hr_settings(wider)[hr_settings(wider)$set, c("step", "param", "value")]
#'
#' # A setting at its default is the chain without it.
#' six <- hr_set(chain, retrieve.top_k = 6)
#' plain <- hr_chain(chain, retrieve = gr_step_retrieve(), name = "checked")
#' identical(attr(six, "hr_config"), attr(plain, "hr_config"))
#'
#' # A single step takes the setting's own name.
#' attr(hr_set(gr_step_retrieve(), top_k = 2), "resolved")$top_k
hr_set <- function(x, ...) {
  steps <- settings_steps(x, "hr_set")
  changes <- list(...)
  if (!length(changes)) return(x)
  single <- !inherits(x, "hr_arm")
  given <- names(changes)
  if (is.null(given) || anyNA(given) || any(!nzchar(given)) || anyDuplicated(given)) {
    gr_abort(sprintf("Every setting given to hr_set() must be named once, as %s.",
                     if (single) "setting = value" else "\"step.setting\" = value"),
             class = "gr_bad_setting")
  }
  if (single) {
    step <- rep(names(steps), length(given))
    param <- given
  } else {
    dot <- regexpr(".", given, fixed = TRUE)
    step <- ifelse(dot > 0L, substr(given, 1L, dot - 1L), NA_character_)
    param <- ifelse(dot > 0L, substring(given, dot + 1L), given)
  }
  path <- function(n, k) if (single) k else paste0(n, ".", k)
  known <- unlist(lapply(names(steps), function(n) {
    sc <- attr(steps[[n]], "schema", exact = TRUE)
    if (inherits(sc, "hr_schema")) path(n, names(sc)) else character(0)
  }), use.names = FALSE)
  bad <- !(vapply(seq_along(given), function(i) path(step[[i]], param[[i]]),
                  character(1)) %in% known)
  if (any(bad)) {
    fixed <- vapply(which(bad), function(i) {
      s <- if (!is.na(step[[i]])) steps[[step[[i]]]] else NULL
      !is.null(s) && param[[i]] %in% names(attr(s, "extras", exact = TRUE))
    }, logical(1))
    what <- if (single) sprintf("step '%s'", names(steps)) else sprintf("chain '%s'", x$name)
    gr_abort(sprintf("%s %s not a setting of %s.%s %s",
                     paste0("'", given[bad], "'", collapse = ", "),
                     if (sum(bad) == 1L) "is" else "are", what,
                     if (any(fixed)) sprintf(paste0(
                       " %s %s fixed when the step was built; build the step again ",
                       "and replace it with hr_chain() to change it."),
                       paste0("'", given[bad][fixed], "'", collapse = ", "),
                       if (sum(fixed) == 1L) "was" else "were") else "",
                     settings_known(known, step[bad], steps, single)),
             class = c("hr_unknown_setting", "hr_unknown_param", "gr_bad_setting"))
  }
  rebuilt <- list()
  for (n in unique(step)) {
    at <- step == n
    p <- attr(steps[[n]], "params", exact = TRUE) %||% list()
    p[param[at]] <- changes[at]
    rebuilt[[n]] <- step_rebuild(steps[[n]], p)
  }
  if (single) return(rebuilt[[1]])
  # The order of the steps has not changed, so a gap hr_chain() warned
  # about when the chain was built is not warned about again.
  withCallingHandlers(
    do.call(hr_chain, c(list(x), rebuilt, list(name = x$name, version = x$version))),
    hr_chain_gap = function(w) invokeRestart("muffleWarning"))
}

#' The sentence that ends hr_set()'s refusal: the settings of the steps the
#' refused paths name, or, when none names a step of the chain, the steps.
#' @noRd
settings_known <- function(known, named, steps, single) {
  if (single) {
    return(sprintf("Settings: %s.", if (length(known)) paste(known, collapse = ", ") else "none"))
  }
  named <- intersect(named[!is.na(named)], names(steps))
  if (!length(named)) {
    return(sprintf("Settings are named \"step.setting\", and the steps are %s.",
                   paste0("'", names(steps), "'", collapse = ", ")))
  }
  own <- known[sub("\\..*$", "", known) %in% named]
  sprintf("Settings of %s: %s.", paste0("'", named, "'", collapse = ", "),
          if (length(own)) paste(own, collapse = ", ") else "none")
}

#' The steps of a step or a chain, as a named list, for hr_settings() and
#' hr_set(); any other object is an error that says where its settings are.
#' @noRd
settings_steps <- function(x, fun) {
  if (inherits(x, "hr_arm")) {
    steps <- attr(x, "hr_steps", exact = TRUE)
    if (is.list(steps) && length(steps)) return(steps)
    gr_abort(sprintf(paste0(
      "%s(): arm '%s' was not built by hr_chain(), so it has no steps. The settings of ",
      "a recipe arm from gr_arm() are listed by gr_settings_table() and swept by name ",
      "with hr_sweep(); an arm from hr_arm() alone records none."), fun, x$name),
      class = c("hr_bad_arm", "gr_bad_setting"))
  }
  if (inherits(x, "hr_step")) {
    return(stats::setNames(list(x), attr(x, "name", exact = TRUE)))
  }
  gr_abort(sprintf("%s(): `x` must be a step from hr_step() or an arm from hr_chain().", fun),
           class = c("hr_bad_arm", "gr_bad_setting"))
}

#' A step built again from new settings as hr_step() built it, through its
#' `build` function when it has one, keeping its class.
#' @noRd
step_rebuild <- function(s, params) {
  build <- attr(s, "build", exact = TRUE)
  out <- hr_step(attr(s, "name", exact = TRUE),
                 fn = if (is.null(build)) step_bare(s) else NULL, params = params,
                 schema = attr(s, "schema", exact = TRUE),
                 input = attr(s, "input", exact = TRUE),
                 output = attr(s, "output", exact = TRUE),
                 version = attr(s, "version", exact = TRUE), build = build,
                 skill = attr(s, "skill", exact = TRUE))
  class(out) <- class(s)
  out
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

#' The function a chain calls for a step: the step without its attributes,
#' and for a step with a skill, a function that first gives it a context
#' whose `call` and `call_json` send the skill (skill_ctx()). The skill's hash
#' reaches the chain's configuration through the step's fingerprint.
#' @noRd
step_runner <- function(s) {
  fn <- step_bare(s)
  skill <- attr(s, "skill", exact = TRUE)
  if (is.null(skill)) return(fn)
  function(input, ctx) fn(input, skill_ctx(if (is.list(ctx)) ctx else list(), skill))
}

#' How a chain records a step's skill among its settings: the skill's name
#' and the start of its hash.
#' @noRd
skill_label <- function(skill) paste0(skill$name, "@", substr(skill$hash, 1L, 12L))

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

#' Check that no step comes after a held step (see hr_step_command()) unless
#' it is held too: a held result must not reach a later step.
#' @noRd
chain_check_held <- function(steps, what) {
  held <- vapply(steps, step_held, logical(1))
  if (!any(held)) return(invisible(NULL))
  first <- which(held)[1]
  late <- names(steps)[seq_along(steps) > first & !held]
  if (length(late)) {
    gr_abort(sprintf(paste0("%s: step '%s' comes after the held step '%s'. A held step keeps ",
                            "its result from the steps after it, so it must come last; only ",
                            "other held steps may follow it."), what, late[1],
                     names(steps)[first]), class = c("hr_held_not_last", "hr_bad_chain"))
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

#' The rules a step or a chain must meet, for hr_check_module(): it returns
#' something, it returns what it declares (for a chain, what its last step
#' that declares an output returns), and every held step at its end attaches
#' its result in attr(output, "hr_held"). A rule that has nothing to check
#' says NA. `x` is an hr_step or an arm built by hr_chain().
#' @noRd
hr_rules_step <- function(x) {
  steps <- if (inherits(x, "hr_step")) list(x) else attr(x, "hr_steps", exact = TRUE)
  if (!is.list(steps) || !length(steps)) {
    gr_abort("`x` must be a step from hr_step() or a chain from hr_chain().",
             class = "gr_bad_setting")
  }
  names(steps) <- vapply(seq_along(steps), function(i) {
    nm <- names(steps)[i]
    if (is.null(nm) || !nzchar(nm)) attr(steps[[i]], "name", exact = TRUE) else nm
  }, character(1))
  outputs <- Filter(Negate(is.null), lapply(steps, attr, which = "output", exact = TRUE))
  declared <- if (length(outputs)) outputs[[length(outputs)]] else NULL
  held <- names(steps)[vapply(steps, step_held, logical(1))]
  list(
    returns_value = function(v) list(ok = !is.null(v),
                                     detail = if (is.null(v)) "returned NULL" else ""),
    declared_output = function(v) {
      if (is.null(declared)) return(list(ok = NA, detail = "not checked: no output declared"))
      ok <- step_output_is(v, declared)
      list(ok = ok, detail = if (ok) "" else
        sprintf("declared \"%s\" but returned class %s", declared,
                paste(class(v), collapse = "/")))
    },
    held_attached = function(v) {
      if (!length(held)) return(list(ok = NA, detail = "not checked: no held step"))
      got <- attr(v, "hr_held", exact = TRUE)
      bad <- held[!vapply(held, function(h) {
        is.list(got) && inherits(got[[h]], "hr_command_result")
      }, logical(1))]
      list(ok = !length(bad), detail = if (length(bad))
        sprintf("no held result for %s", paste0("'", bad, "'", collapse = ", ")) else "")
    })
}

#' Whether a value is of the kind a step declares it returns. The classes are
#' those the document layer gives its objects; "state" is anything.
#' @noRd
step_output_is <- function(v, kind) {
  switch(kind,
    document = is.character(v) && length(v) >= 1L,
    doc = inherits(v, "gr_document"),
    chunks = inherits(v, "gr_chunks"),
    answer = inherits(v, "gr_answer"),
    TRUE)
}
