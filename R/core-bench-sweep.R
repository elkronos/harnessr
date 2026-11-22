# core-bench-sweep.R: one arm per row of a grid of settings, the settings each
# arm records, and the check that a swept setting changed what was sent.
#
# An arm may carry three attributes besides its fields, which this file reads
# and hr_arm()'s hash leaves out: `hr_settings`, the named settings it was
# built with, which hr_benchmark() turns into param.<name> columns;
# `hr_config`, a hash of what the arm will do whatever it is called, which two
# arms share only when they run the same configuration; and `hr_rebuild` with
# `hr_known`, a function that builds the arm again with some settings changed
# and the names it accepts. gr_arm() sets all four; an arm made by hr_arm()
# alone has none, and its configuration is its fields other than its name.

#' Build one arm per row of a grid of settings
#'
#' `hr_sweep()` turns a grid of settings into arms for [hr_benchmark()], one
#' per row, each named after its settings and recording them, so the
#' benchmark gets a `param.<name>` column per setting and a sweep is
#' summarised with [aggregate()] or [hr_report()] like any other comparison.
#'
#' `base` is either a function or an arm:
#' \describe{
#'   \item{A function}{Called once per row with the row's values as named
#'     arguments, and must return an [hr_arm()]. A column it has no argument
#'     for (and no `...` to take) is an error.}
#'   \item{An arm made by [gr_arm()]}{Each row's values replace the arm's
#'     settings of the same name, and the arm is built again with
#'     [gr_arm()]. A column may be any setting [answer_document()] takes as
#'     an override (see [gr_settings_table()]), or `recipe`. A name that is
#'     none of these is an error that lists the names that are.}
#' }
#' An arm made by [hr_arm()] alone records no settings, so it cannot be
#' swept by name; give a function that builds it instead. The same holds for
#' a chain from [hr_chain()] for now: it records its settings, but
#' `hr_sweep()` cannot yet build it again from a row, so give a function
#' that builds the chain.
#'
#' Rows that build the same configuration are collapsed: the first is kept
#' and the others are dropped with a message of class `hr_sweep_collapsed`
#' naming them. Two arms from [gr_arm()] have the same configuration when
#' their recipes resolve to the same settings, so a row that sets a setting
#' to the recipe's own value is the base arm again. Any other two arms have
#' the same configuration when everything but their names is the same,
#' including the values their code reads and the values read by any helper
#' function it calls by name: a function that ignores one of its arguments
#' builds the same arm for every value of it. A value held in an
#' environment rather than read by name is not compared, and neither is a
#' helper reached through a list or another object (`h$ask()`), whose code is
#' compared but not the values it reads. Two such arms can look like one
#' configuration here and still send different requests, and a sweep would
#' keep only one of them: call such helpers by name, or check with
#' [hr_sweep_check()], which compares what was sent.
#'
#' Sweeping one setting at a time on the dev split, then comparing the arm
#' chosen with the default on test, is the order `vignette("compare")`
#' follows. [hr_sweep_check()] then says which settings changed nothing
#' that was sent.
#'
#' @param base A function of the grid's columns that returns an
#'   [hr_arm()], or an arm made by [gr_arm()].
#' @param grid A data frame with one row per arm and one column per setting,
#'   or a named list of values, which is crossed with [expand.grid()]. A
#'   setting whose values are not single values (an `effort` map, a vector
#'   of cleaners) goes in a list column, for instance with [I()].
#' @param name `NULL` to name each arm after the base arm's name and its
#'   settings, as `"needle:top_k=2,max_tokens=200"`; one string to use in
#'   place of the base arm's name; or one string per row.
#' @return A list of [hr_arm()] objects named by arm, one per distinct row,
#'   each with its row's settings recorded.
#' @seealso [hr_benchmark()], [hr_sweep_check()], [gr_arm()],
#'   [gr_settings_table()], `vignette("compare")`
#' @family harness
#' @export
#' @examples
#' # Sweep a recipe's settings by name.
#' arms <- hr_sweep(gr_arm("needle"), list(top_k = c(2, 4, 8)))
#' names(arms)
#'
#' # The same with a function, crossing two settings.
#' arms <- hr_sweep(function(top_k, max_tokens) {
#'   gr_arm("needle", list(top_k = top_k, max_tokens = max_tokens))
#' }, expand.grid(top_k = c(2, 8), max_tokens = c(200, 500)))
#' names(arms)
#'
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ref <- gr_qa_reference(
#'   questions = c(revenue = "What was revenue in 2024?"),
#'   documents = gr_example(), answers = list("45.2 million"), split = "test")
#' old <- gr_options(verbose = FALSE, embedder = "lexical")
#' bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
#'                       scorer = gr_scorer_answer())
#' aggregate(correct ~ param.top_k + param.max_tokens, bench, mean)
#' gr_options(old)
hr_sweep <- function(base, grid, name = NULL) {
  grid <- sweep_grid(grid)
  n <- nrow(grid)
  if (!is.null(name) && (!is.character(name) || !(length(name) %in% c(1L, n)) ||
                         anyNA(name) || !all(nzchar(trimws(name))))) {
    gr_abort(sprintf("`name` must be NULL, one string, or one string per row (%d).", n),
             class = "hr_bad_arm")
  }
  if (inherits(base, "hr_arm")) {
    rebuild <- attr(base, "hr_rebuild", exact = TRUE)
    known <- attr(base, "hr_known", exact = TRUE)
    if (!is.function(rebuild) && !is.null(attr(base, "hr_steps", exact = TRUE))) {
      gr_abort(sprintf(paste0(
        "Arm '%s' is a chain from hr_chain(), which hr_sweep() cannot rebuild from a ",
        "grid yet. Give hr_sweep() a function of the grid's columns that builds the ",
        "chain instead, such as function(k) hr_chain(..., name = \"c\")."),
        base$name), class = "hr_bad_arm")
    }
    if (!is.function(rebuild)) {
      gr_abort(sprintf(paste0(
        "Arm '%s' records no settings to override: it was not built by gr_arm(). Give ",
        "hr_sweep() a function of the grid's columns that builds the arm instead."),
        base$name), class = "hr_bad_arm")
    }
    sweep_check_names(names(grid), known, sprintf("arm '%s'", base$name))
    build <- function(row) rebuild(row, base$name)
  } else if (is.function(base)) {
    args <- names(formals(base))
    if (!"..." %in% args) sweep_check_names(names(grid), args, "`base`")
    build <- function(row) {
      arm <- do.call(base, row)
      if (!inherits(arm, "hr_arm")) {
        gr_abort("`base` must return an hr_arm(), such as one from gr_arm().",
                 class = "hr_bad_arm")
      }
      own <- arm_settings(arm)
      arm_annotate(arm, settings = c(row, own[setdiff(names(own), names(row))]))
    }
  } else {
    gr_abort("`base` must be an arm from gr_arm(), or a function that returns an hr_arm().",
             class = "hr_bad_arm")
  }
  arms <- vector("list", n)
  for (i in seq_len(n)) {
    row <- sweep_row(grid, i)
    arm <- build(row)
    label <- paste(sprintf("%s=%s", names(row), vapply(row, format_setting_value, "")),
                   collapse = ",")
    nm <- if (is.null(name)) paste0(arm$name, ":", label) else
      if (length(name) == n) name[[i]] else if (n == 1L) name else paste0(name, ":", label)
    arms[[i]] <- arm_rename(arm, nm)
  }
  config <- vapply(arms, arm_config, character(1))
  dup <- duplicated(config)
  if (any(dup)) {
    nms <- vapply(arms, function(a) a$name, character(1))
    kept <- nms[match(config[dup], config)]
    sweep_message(sprintf(paste0(
      "hr_sweep(): %d of %d rows build a configuration an earlier row already builds, and ",
      "were dropped: %s."), sum(dup), n,
      paste(sprintf("'%s' (same as '%s')", nms[dup], kept), collapse = ", ")))
    arms <- arms[!dup]
  }
  nms <- vapply(arms, function(a) a$name, character(1))
  repeated <- unique(nms[duplicated(nms)])
  if (length(repeated)) {
    gr_abort(sprintf("Arm names must be unique; repeated: %s. Give `name` one string per row.",
                     paste(repeated, collapse = ", ")), class = "hr_bad_arm")
  }
  stats::setNames(arms, nms)
}

#' Find the settings of a sweep that changed nothing that was sent
#'
#' A setting a reader does not use (`top_k` under a reader that sends every
#' chunk, `mmr` with `top_k` at or above the number of chunks) leaves the
#' requests as they were, and a sweep over it compares an arm with itself.
#' `hr_sweep_check()` finds such pairs in a benchmark: two arms that sent
#' byte-identical requests (the same model, prompts and request settings, in
#' the same order) on every item and run they share.
#'
#' An arm is reported once, against the first arm before it with the same
#' requests, so three arms that sent the same requests give two rows. Pairs
#' in which neither arm sent a request are left out, since requests
#' cannot tell them apart. A request answered from a cache counts as sent:
#' its prompt is recorded as it would have gone out.
#'
#' @param bench An `hr_bench` from [hr_benchmark()].
#' @return A data frame with one row per arm whose requests were identical
#'   to an earlier arm's: `arm` and `same_as` (the first earlier arm, in the
#'   benchmark's order, that sent the same requests), `runs` (the item and run pairs compared),
#'   `requests` (the requests `arm` sent over them), and `settings`, the
#'   recorded settings (`param.*` columns) that differ between the two, as
#'   `"top_k: 2 vs 8"`, which are the settings that changed nothing. No
#'   rows when every pair of arms sent different requests.
#' @seealso [hr_sweep()], [hr_benchmark()]
#' @family harness
#' @export
#' @examples
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ref <- gr_qa_reference(
#'   questions = c(revenue = "What was revenue in 2024?"),
#'   documents = gr_example(), answers = list("45.2 million"), split = "test")
#' old <- gr_options(verbose = FALSE)
#' # `stuff` sends the whole document, so top_k changes nothing.
#' arms <- hr_sweep(gr_arm("fast"), list(top_k = c(2, 8)))
#' bench <- hr_benchmark(arms, ref, runs = 5, client = cl,
#'                       scorer = gr_scorer_answer())
#' hr_sweep_check(bench)
#' gr_options(old)
hr_sweep_check <- function(bench) {
  if (!inherits(bench, "hr_bench")) {
    gr_abort("`bench` must be an hr_bench from hr_benchmark().", class = "gr_bad_setting")
  }
  traces <- attr(bench, "traces", exact = TRUE)
  if (!is.list(traces) || !all(c("arm", "item", "run", "ledger_id") %in% names(bench))) {
    gr_abort("`bench` has lost the columns or traces hr_sweep_check() reads.",
             class = "gr_bad_setting")
  }
  rows <- as.data.frame(bench)[, c("arm", "item", "run", "ledger_id")]
  fp <- lapply(rows$ledger_id, function(id) request_fingerprints(traces[[id]]))
  rows$sig <- vapply(fp, function(x) hr_hash(x), character(1))
  rows$n <- vapply(fp, length, integer(1))
  rows$key <- paste(rows$item, rows$run, sep = "\r")
  arms <- unique(rows$arm)
  params <- grep("^param\\.", names(bench), value = TRUE)
  out <- list()
  for (j in seq_along(arms)) {
    for (i in seq_len(j - 1L)) {
      a <- rows[rows$arm == arms[j], ]
      b <- rows[rows$arm == arms[i], ]
      shared <- intersect(a$key, b$key)
      if (!length(shared)) next
      a <- a[match(shared, a$key), ]
      b <- b[match(shared, b$key), ]
      if (!sum(a$n) && !sum(b$n)) next
      if (!identical(a$sig, b$sig)) next
      out[[length(out) + 1L]] <- data.frame(
        arm = arms[j], same_as = arms[i], runs = length(shared), requests = sum(a$n),
        settings = sweep_setting_diff(bench, params, arms[j], arms[i]),
        stringsAsFactors = FALSE)
      break
    }
  }
  if (!length(out)) {
    return(data.frame(arm = character(0), same_as = character(0), runs = integer(0),
                      requests = integer(0), settings = character(0),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}

#' The grid as a data frame with one row per arm: a named list is crossed,
#' factors become strings.
#' @noRd
sweep_grid <- function(grid) {
  if (is.list(grid) && !is.data.frame(grid)) {
    if (!length(grid) || is.null(names(grid))) {
      gr_abort("`grid` must be a data frame or a named list of values.", class = "hr_bad_arm")
    }
    grid <- expand.grid(grid, stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE)
  }
  if (!is.data.frame(grid) || !nrow(grid) || !ncol(grid)) {
    gr_abort("`grid` must be a data frame with at least one row and one column.",
             class = "hr_bad_arm")
  }
  nms <- names(grid)
  if (anyNA(nms) || !all(nzchar(nms)) || anyDuplicated(nms)) {
    gr_abort("The columns of `grid` must have unique, non-empty names.", class = "hr_bad_arm")
  }
  for (k in nms) if (is.factor(grid[[k]])) grid[[k]] <- as.character(grid[[k]])
  grid
}

#' Row `i` of a grid as a named list; a list column gives its element.
#' @noRd
sweep_row <- function(grid, i) {
  row <- lapply(grid, function(col) if (is.list(col)) col[[i]] else col[[i]])
  # I() leaves an AsIs class on what it wraps.
  lapply(row, function(v) { if (inherits(v, "AsIs")) class(v) <- setdiff(class(v), "AsIs"); v })
}

#' Stop when a grid has a column the base cannot take, naming the ones it can.
#' @noRd
sweep_check_names <- function(given, known, what) {
  unknown <- setdiff(given, known)
  if (length(unknown)) {
    gr_abort(sprintf("%s %s not a setting of %s. Known settings: %s.",
                     paste0("'", unknown, "'", collapse = ", "),
                     if (length(unknown) == 1L) "is" else "are", what,
                     paste(known, collapse = ", ")),
             class = c("hr_unknown_setting", "hr_bad_arm"))
  }
  invisible(NULL)
}

#' A message of class hr_sweep_collapsed, shown whatever `verbose` says.
#' @noRd
sweep_message <- function(msg) {
  message(structure(class = c("hr_sweep_collapsed", "message", "condition"),
                    list(message = paste0(msg, "\n"), call = NULL)))
}

#' One setting's value as short text, for an arm's name and a summary.
#' @noRd
format_setting_value <- function(v) {
  if (is.null(v)) return("NULL")
  if (is.function(v)) return("<function>")
  if (is.atomic(v) && length(v) == 1L && is.null(names(v))) {
    return(if (is.na(v)) "NA" else format(v, trim = TRUE, scientific = FALSE))
  }
  paste(deparse(v, width.cutoff = 500L), collapse = "")
}

#' The settings an arm records, a named list; empty for an arm that records
#' none.
#' @noRd
arm_settings <- function(arm) {
  s <- attr(arm, "hr_settings", exact = TRUE)
  if (is.list(s)) s else list()
}

#' What an arm will do whatever it is called: its recorded configuration
#' hash, else a hash of its fields other than its name. The run function is
#' hashed with the values its code reads and, for a helper function among
#' them, the values the helper reads, so two arms whose helpers hold
#' different prompts are different configurations.
#' @noRd
arm_config <- function(arm) {
  cfg <- attr(arm, "hr_config", exact = TRUE)
  if (is.character(cfg) && length(cfg) == 1L && !is.na(cfg)) return(cfg)
  parts <- arm_parts(arm, values = TRUE)[c("run", "params", "derived_from", "version")]
  parts$run <- fn_fingerprint(arm$run, values = TRUE, follow = TRUE)
  hr_hash(parts)
}

#' Attach what hr_sweep() and hr_benchmark() read to an arm. Arguments left
#' NULL keep what the arm has.
#' @noRd
arm_annotate <- function(arm, settings = NULL, config = NULL, rebuild = NULL, known = NULL) {
  if (!is.null(settings)) attr(arm, "hr_settings") <- settings
  if (!is.null(config)) attr(arm, "hr_config") <- config
  if (!is.null(rebuild)) attr(arm, "hr_rebuild") <- rebuild
  if (!is.null(known)) attr(arm, "hr_known") <- known
  arm
}

#' The same arm under another name: built again by hr_arm(), so its hash is
#' its own, with the attributes it carried, a chain's steps among them.
#' @noRd
arm_rename <- function(arm, name) {
  if (identical(arm$name, name)) return(arm)
  out <- hr_arm(name, arm$run, params = arm$params, derived_from = arm$derived_from,
                version = arm$version)
  for (a in c("hr_settings", "hr_config", "hr_rebuild", "hr_known", "hr_steps")) {
    attr(out, a) <- attr(arm, a, exact = TRUE)
  }
  out
}

#' The param.<name> columns of a benchmark, one value per row: each arm's
#' recorded setting, NA for an arm that does not record it. A column of
#' single values keeps their type; any other value is written as text.
#' @noRd
bench_param_columns <- function(out, arms) {
  sets <- lapply(arms, arm_settings)
  keys <- unique(unlist(lapply(sets, names), use.names = FALSE))
  at <- match(out$arm, names(arms))
  for (k in keys) {
    vals <- lapply(sets, function(s) s[[k]])
    simple <- vapply(vals, function(v) is.null(v) ||
                       (is.atomic(v) && length(v) == 1L && is.null(names(v)) &&
                          !is.factor(v)), logical(1))
    col <- if (all(simple)) {
      unlist(lapply(vals, function(v) if (is.null(v)) NA else v), use.names = FALSE)
    } else {
      vapply(vals, function(v) if (is.null(v)) NA_character_ else format_setting_value(v),
             character(1))
    }
    out[[paste0("param.", k)]] <- col[at]
  }
  out
}

#' Warn, with class hr_same_config, when two arms of a benchmark resolve to
#' the same configuration.
#' @noRd
warn_same_config <- function(arms) {
  config <- vapply(arms, arm_config, character(1))
  dup <- duplicated(config)
  if (!any(dup)) return(invisible(NULL))
  nms <- names(arms)
  pairs <- sprintf("'%s' and '%s'", nms[match(config[dup], config)], nms[dup])
  gr_warn(sprintf(paste0(
    "Arms %s resolve to the same configuration, so their differences are run-to-run spread ",
    "and nothing else. Change a setting that the configuration uses, or drop one of them."),
    paste(pairs, collapse = "; ")), class = "hr_same_config")
}

#' One fingerprint per request a run sent, in order: its kind, model,
#' prompt and the request settings, without anything that differs between
#' arms by construction (the arm's draw scope) or between sends (timings,
#' replies).
#' @noRd
request_fingerprints <- function(trace) {
  if (is.null(trace)) return(list())
  lapply(request_steps(trace$steps), function(s) {
    hr_hash(list(kind = as_chr1(s$kind, "call"), model = as_chr1(s$model, NA_character_),
                 prompt = s$prompt, params = s$params, sent = s[["params_sent", exact = TRUE]]))
  })
}

#' The recorded settings that differ between two arms of a benchmark, as
#' "top_k: 2 vs 8; mmr: 1 vs 0.5".
#' @noRd
sweep_setting_diff <- function(bench, params, a, b) {
  if (!length(params)) return("")
  d <- bench
  class(d) <- "data.frame"
  va <- as.list(d[match(a, d$arm), params, drop = FALSE])
  vb <- as.list(d[match(b, d$arm), params, drop = FALSE])
  show <- function(v) if (length(v) == 1L && is.na(v)) "unset" else format_setting_value(v)
  diff <- vapply(params, function(p) !identical(va[[p]], vb[[p]]), logical(1))
  if (!any(diff)) return("")
  paste(sprintf("%s: %s vs %s", sub("^param\\.", "", params[diff]),
                vapply(vb[params[diff]], show, ""), vapply(va[params[diff]], show, "")),
        collapse = "; ")
}
