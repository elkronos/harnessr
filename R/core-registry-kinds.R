# core-registry-kinds.R: the core's own state, its registries, and the kinds
# of module it knows about.
#
# Core code keeps everything it needs here and reads nothing else. The
# document layer keeps its modules in an environment of its own
# (doc-modules.R) and tells the core about them through the hooks below: the
# kinds it brings, and what a parallel worker has to be handed to see the
# same modules as its parent.

hr_state <- new.env(parent = emptyenv())

# Bumped once per id made, so two ids made at the same moment differ (gr_new_id()).
hr_state$counter        <- 0L

# Registered models override the built-in ones, which .onLoad() puts in
# seed_models. Patterns guess limits for a model id in neither.
hr_state$models         <- list()

hr_state$model_patterns <- list()

hr_state$tokenizers     <- list()

hr_state$embed_cache    <- new.env(parent = emptyenv())

# What gr_options() has set; gr_defaults fills in the rest.
hr_state$options        <- list()

# The kinds of module a layer above the core has said it registers, by name.
hr_state$kinds          <- list()

# Functions that say what a parallel worker needs from a layer above the core
# (see hr_register_worker_state()).
hr_state$worker_providers <- list()

#' Tell the core about a kind of module.
#'
#' `name` is the kind, such as "reader". Anything in `...` is kept with it as
#' given. The modules themselves stay in the registries of the layer that
#' registers the kind; the core keeps only the list of kinds. Registering a
#' kind again replaces what was kept for it.
#' @noRd
hr_register_kind <- function(name, ...) {
  if (!is_nonblank(name)) gr_abort("A kind's name must be a non-empty string.")
  kinds <- hr_state$kinds
  kinds[[name]] <- c(list(name = name), list(...))
  hr_state$kinds <- kinds
  invisible(name)
}

#' The registered kinds of module, by name, each with what it was registered with.
#' @noRd
hr_kinds <- function() hr_state$kinds

#' Say what a parallel worker needs from a layer above the core.
#'
#' A worker is a fresh process: it loads the package, whose .onLoad() puts
#' back the built-in modules and nothing a user registered since. `snapshot()`
#' runs in the process that sends a batch and returns what the worker needs,
#' and `restore(values)` runs in the worker with what it returned. Both should
#' be functions of the package itself, so a worker finds them in its own copy
#' of the namespace and they touch that copy's state.
#' @noRd
hr_register_worker_state <- function(name, snapshot, restore) {
  if (!is_nonblank(name)) gr_abort("A worker state provider needs a name.")
  if (!is.function(snapshot) || !is.function(restore)) {
    gr_abort("`snapshot` and `restore` must both be functions.")
  }
  providers <- hr_state$worker_providers
  providers[[name]] <- list(snapshot = snapshot, restore = restore)
  hr_state$worker_providers <- providers
  invisible(name)
}

#' Generic registry machinery.
#'
#' Every pluggable axis (extractors, cleaners, segmenters, readers) uses this,
#' so third-party additions behave exactly like built-ins. `state` is the
#' environment the registry lives in: the core's own for models, the document
#' layer's own for its modules. It has no default, so a call that leaves it
#' out fails instead of filing a module where no one would look for it.
#' @noRd
registry_set <- function(slot, name, entry, state) {
  if (!is_nonblank(name)) gr_abort("Registry name must be a non-empty string.")
  reg <- state[[slot]]
  reg[[name]] <- entry
  state[[slot]] <- reg
  invisible(name)
}

#' @noRd
registry_get <- function(slot, name, what = slot, state) {
  reg <- state[[slot]]
  if (!is_nonblank(name) || is.null(reg[[name]])) {
    gr_abort(sprintf("Unknown %s '%s'. Registered: %s.",
                     sub("s$", "", what), as_chr1(name, "<missing>"),
                     paste(sort(names(reg)), collapse = ", ")),
             class = "gr_unknown_method")
  }
  reg[[name]]
}

#' @noRd
registry_table <- function(slot, cols, state) {
  reg <- state[[slot]]
  if (!length(reg)) {
    empty <- as.data.frame(stats::setNames(
      rep(list(character(0)), length(cols) + 1L), c("name", cols)),
      stringsAsFactors = FALSE)
    return(empty)
  }
  rows <- lapply(names(reg), function(nm) {
    e <- reg[[nm]]
    vals <- lapply(cols, function(cl) as_chr1(e[[cl]], ""))
    stats::setNames(c(list(nm), vals), c("name", cols))
  })
  df <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  df <- df[order(df$name), , drop = FALSE]
  # Drop row names. rbind() over one-row frames keeps the registry key as a row
  # name, so every printed table showed the name twice -- once as a row label and
  # again in the `name` column.
  rownames(df) <- NULL
  df
}
