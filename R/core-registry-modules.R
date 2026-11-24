# core-registry-modules.R: one way to register and list modules of any kind.
#
# The kinds and how to reach each one's registry live in hr_state (see
# core-registry-kinds.R). The registries themselves stay with the layer that
# registered the kind, so this file reads and writes them only through the
# `get` and `set` functions that layer gave hr_register_kind().

#' The `get`, `set` or `check` function of a kind, or an error of class
#' `hr_unknown_kind` naming the kinds that have the one asked for.
#' @noRd
kind_access <- function(kind, need = c("get", "set", "check")) {
  need <- match.arg(need)
  access <- hr_state$kind_access
  usable <- names(access)[vapply(access, function(a) is.function(a[[need]]), logical(1))]
  if (!is_nonblank(kind) || !(kind %in% usable)) {
    gr_abort(sprintf("Unknown kind of module '%s'. Kinds you can %s: %s.",
                     as_chr1(kind, "<missing>"),
                     switch(need, set = "register", get = "list", check = "check"),
                     paste(usable, collapse = ", ")),
             class = "hr_unknown_kind")
  }
  access[[kind]][[need]]
}

#' Register a module of any kind
#'
#' `hr_register()` files a module under a kind, such as `"reader"` or
#' `"segmenter"`, through the same checks as that kind's own registration
#' function: `hr_register("reader", ...)` runs what [gr_register_reader()]
#' runs, so a reader named `"auto"` or with a malformed `signature` is refused
#' here as it is there. [hr_modules()] lists the kinds and what each holds.
#'
#' The kinds the package brings, and the function each one goes through:
#' `"extractor"` ([gr_register_extractor()]), `"cleaner"`
#' ([gr_register_cleaner()]), `"segmenter"` ([gr_register_segmenter()]),
#' `"reader"` ([gr_register_reader()]), `"embedder"`
#' ([gr_register_embedder()]), `"protocol"` ([gr_register_protocol()]) and
#' `"step"`. For a protocol, `fn` is the protocol object from
#' [gr_protocol()]. For a step, `fn` is a step from [hr_step()], or a
#' function of `(input, ctx)` that `hr_register()` passes to [hr_step()]
#' with the name and the arguments in `...`.
#'
#' A module registered here records two more fields: `version`, the version
#' you give, and `contract`, the version of the module contract the package
#' implements, 0.2 in this release. Every listing shows them as its last two
#' columns. A module registered through a kind's own function has `NA` in
#' both, and its conformance check stays advisory.
#'
#' @param kind The kind of module, one string. A kind the package does not
#'   know is an error of class `hr_unknown_kind`.
#' @param name The module's name, one string. Registering a name again
#'   replaces the module.
#' @param fn The module's function, with the arguments its kind calls it
#'   with (see the kind's own registration function). For a protocol, the
#'   protocol object; for a step, a step or a function of `(input, ctx)`.
#' @param ... The other arguments of the kind's own registration function,
#'   by name, such as `signature` for a reader or `extensions` for an
#'   extractor. A segmenter also takes `effort_label`, a function of the
#'   segment spec that returns the trace label its model requests carry, or
#'   `""` when it sends none. A run's `effort` setting then reaches the
#'   segmenter as the effort for that label alone. Without it, the segmenter
#'   gets the run's whole effort map. A step takes the arguments of
#'   [hr_step()], such as `params`, `input` and `output`.
#' @param description One-line description, shown by the kind's listing and
#'   by [hr_modules()]. For a protocol, a non-empty description replaces the
#'   protocol's own.
#' @param calls The stems of the trace labels the module's model calls
#'   carry, for the kinds that declare them (readers, segmenters and steps).
#'   `NULL` (the default) declares the module's name for a reader or a
#'   segmenter and no stems for a step. Any other value for a kind that does
#'   not declare calls is an error of class `gr_bad_setting`.
#' @param version The module's own version, one string, kept in the
#'   `version` field. `NULL` (the default) records `NA`, or, for a step, the
#'   step's own version.
#' @return Invisibly, `name`.
#' @seealso [hr_modules()], `vignette("extending")`
#' @family harness
#' @export
#' @examples
#' # A segmenter that makes one chunk per line, registered by kind.
#' hr_register("segmenter", "by_line", description = "one chunk per line",
#'   version = "1.0.0",
#'   fn = function(doc, spec, client, trace) {
#'     new_chunks(strsplit(doc$text, "\n+")[[1]], "by_line", spec)
#'   })
#' subset(hr_modules("segmenter"), name == "by_line")[, c("kind", "name", "cost", "contract")]
#' nrow(gr_segment(gr_example(), list(method = "by_line"))$chunks)
#'
#' # A step, registered by kind and listed with its input and output.
#' hr_register("step", "shout", fn = function(input, ctx) toupper(input),
#'   input = "answer", output = "state")
#' hr_modules("step")[, c("name", "input", "output", "version", "contract")]
#'
#' # A kind the package does not know is refused.
#' try(hr_register("ranker", "mine", fn = identity))
hr_register <- function(kind, name, fn, ..., description = "", calls = NULL, version = NULL) {
  set <- kind_access(kind, "set")
  if (!is.null(version) && !is_nonblank(version)) {
    gr_abort("`version` must be one non-empty string, or NULL.", class = "gr_bad_setting")
  }
  set(name = name, fn = fn, ..., description = description, calls = calls,
      version = version, contract = hr_contract_version())
  invisible(name)
}

#' List the registered modules of every kind
#'
#' One table across the kinds of module: each registered extractor, cleaner,
#' segmenter, reader, embedder, protocol and step, with its description, the
#' call stems it declares, its version and the contract it was registered
#' under. Ask for one kind to add the columns only that kind has, such
#' as a reader's `signature` or an extractor's `extensions`. The kind's own
#' listing, such as [gr_readers()], keeps its own shape and is unchanged.
#'
#' @param kind `NULL` (the default) for every kind, or one kind, such as
#'   `"reader"`. A kind the package does not know is an error of class
#'   `hr_unknown_kind`.
#' @return A data frame with one row per module, sorted by kind in the order
#'   the kinds were registered and by name within a kind: `kind`, `name`,
#'   `description`, and `calls`, a list column of the call stems each module
#'   declares (`character(0)` for none). With `kind`, it also has a column
#'   for each other setting the kind's modules were registered with, except
#'   functions; a setting with more than one value per module, such as an
#'   extractor's `extensions`, is a list column. The last two columns are
#'   always `version` and `contract` (character): the module's version and
#'   the module contract it was registered under with [hr_register()], `NA`
#'   for a module registered through its kind's own function.
#' @seealso [hr_register()], `vignette("extending")`
#' @family harness
#' @export
#' @examples
#' m <- hr_modules()
#' table(m$kind)
#'
#' # One kind, with that kind's own columns.
#' r <- hr_modules("reader")
#' r[r$name %in% c("stuff", "retrieve"), c("name", "signature", "cost_calls")]
#' r$calls[r$name == "refine"][[1]]
hr_modules <- function(kind = NULL) {
  if (is.null(kind)) {
    access <- hr_state$kind_access
    kinds <- names(access)[vapply(access, function(a) is.function(a$get), logical(1))]
    parts <- lapply(kinds, function(k) modules_frame(k, access[[k]]$get(), own = FALSE))
    if (!length(parts)) return(modules_frame(character(0), list(), own = FALSE))
    out <- do.call(rbind, parts)
    rownames(out) <- NULL
    return(out)
  }
  modules_frame(kind, kind_access(kind, "get")(), own = TRUE)
}

#' The rows of hr_modules() for one kind's registry entries. With `own`, a
#' column is added for each field the entries carry beyond the shared ones.
#' @noRd
modules_frame <- function(kind, entries, own) {
  nms <- names(entries) %||% character(0)
  entries <- entries[order(nms, method = "radix")]
  nms <- names(entries) %||% character(0)
  out <- data.frame(kind = rep(as.character(kind), length(nms)), name = nms,
                    description = vapply(entries, function(e) as_chr1(e$description, ""),
                                         character(1), USE.NAMES = FALSE),
                    stringsAsFactors = FALSE)
  out$calls <- lapply(unname(entries), function(e) {
    if (is.character(e$calls)) e$calls else character(0)
  })
  if (own) out <- modules_own_columns(out, entries)
  out$version <- vapply(entries, function(e) as_chr1(e$version, NA_character_),
                        character(1), USE.NAMES = FALSE)
  out$contract <- vapply(entries, function(e) as_chr1(e$contract, NA_character_),
                         character(1), USE.NAMES = FALSE)
  rownames(out) <- NULL
  out
}

#' The columns hr_modules(kind) adds for the fields a kind's entries carry
#' beyond the shared ones, leaving out functions and the registration stamp.
#' @noRd
modules_own_columns <- function(out, entries) {
  shared <- c("name", "description", "calls", "fn", "registered", "version", "contract")
  fields <- setdiff(unique(unlist(lapply(entries, names), use.names = FALSE)), shared)
  for (f in fields) {
    vals <- lapply(unname(entries), `[[`, f)
    if (any(vapply(vals, is.function, logical(1)))) next
    scalar <- vapply(vals, function(v) is.null(v) || (is.atomic(v) && length(v) == 1L),
                     logical(1))
    out[[f]] <- if (all(scalar)) {
      unlist(lapply(vals, function(v) if (is.null(v)) NA else v), use.names = FALSE)
    } else {
      vals
    }
  }
  rownames(out) <- NULL
  out
}

#' Run the conformance check of one registered module of any kind, through
#' the `check` its layer gave hr_register_kind(). `client` reaches the checks
#' that call a model or embed, `path` the extractor check, and `input` the
#' step check (the value the step runs on). A kind with no check is an error
#' of class `hr_unknown_kind`.
#' @noRd
check_kind <- function(kind, name, client = NULL, path = NULL, input = NULL) {
  kind_access(kind, "check")(name, client = client, path = path, input = input)
}

#' Tell the core about its own kind of module, "step", run by .onLoad() after
#' the document layer has registered its kinds. Steps are kept in
#' `hr_state$steps`. The model registry stays outside the module registry.
#' @noRd
register_core_kinds <- function() {
  hr_register_kind("step", registry = "steps",
                   get = function() hr_state$steps,
                   set = register_step,
                   check = check_step)
  invisible(NULL)
}

#' The `set` of the step kind: file a step under `name`. `fn` is a step from
#' hr_step(), or a function of (input, ctx) passed to hr_step() with `...`.
#' The entry keeps the step as `fn`, its input and output, and its version
#' unless `version` gives another.
#' @noRd
register_step <- function(name, fn, ..., description = "", calls = NULL, version = NULL,
                          contract = NA_character_) {
  if (!is_nonblank(name)) gr_abort("A step's name must be a non-empty string.",
                                   class = "gr_bad_setting")
  if (!is.character(description) || length(description) != 1L || is.na(description)) {
    gr_abort("`description` must be one string.", class = "gr_bad_setting")
  }
  # The rule the document layer's kinds apply to their call stems: no blanks,
  # no whitespace, each stem once.
  if (!is.null(calls) && (!is.character(calls) || anyNA(calls) || !all(has_visible(calls)) ||
                          any(grepl("\\s", calls)))) {
    gr_abort(paste0("`calls` must be a character vector of call label stems, such as ",
                    "c(\"mine.score\", \"mine.answer\"), with no blanks or spaces."),
             class = "gr_bad_setting")
  }
  if (!is.null(calls)) calls <- unique(calls)
  step <- if (inherits(fn, "hr_step")) {
    if (...length()) {
      gr_abort("Give the settings of a step built with hr_step() to hr_step(), not here.",
               class = "gr_bad_setting")
    }
    fn
  } else {
    hr_step(name, fn, ...)
  }
  entry <- list(name = name, fn = step, description = description,
                calls = calls %||% character(0),
                input = attr(step, "input", exact = TRUE) %||% NA_character_,
                output = attr(step, "output", exact = TRUE) %||% NA_character_,
                version = version %||% attr(step, "version", exact = TRUE),
                contract = as_chr1(contract, NA_character_))
  registry_set("steps", name, entry, state = hr_state)
}

#' The `check` of the step kind: run a registered step once on `input`, with
#' `client` in its ctx, against the step rules (hr_rules_step()).
#' @noRd
check_step <- function(name, client = NULL, input = NULL, ...) {
  step <- registry_get("step", name)$fn
  ctx <- list(client = client, step_params = attr(step, "resolved", exact = TRUE))
  hr_check_module(step, function() step(input, ctx), rules = hr_rules_step(step),
                  kind = "step", name = name)
}
