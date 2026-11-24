# core-registry-ctx.R: the run snapshot a parallel batch hands its workers.
#
# A worker is a fresh R process. It needs the caller's options, registries,
# trace meta, its share of the run's limits, the run's draw, the API key, and
# the user's own globals with the packages they come from. gr_lapply() used to
# pass these to worker_item() as seven loose arguments; new_hr_ctx() puts them
# in one classed list, checked once where it is built.
#
# The snapshot is internal. format_hr_ctx() shows it as text without the key,
# and there is no print method, so the package's exported surface (api.json)
# stays as it was.

#' Build the run snapshot for a batch's workers.
#'
#' @param key The API key a worker sets for each item, or "" for none. A mock
#'   client gets "" (see gr_lapply()). It lives only here: never in a hash, a
#'   trace, the ledger or format_hr_ctx().
#' @param opts The options a worker applies, or an empty list to leave them.
#' @param regs What worker_state() returned, or an empty list.
#' @param parent_meta The run trace's meta, copied onto each item's trace.
#' @param governor An hr_governor holding one item's share of the run's
#'   limits (batch_share()), or NULL.
#' @param draw What trace_draw() returned, or NULL.
#' @param globals The user's workspace globals the batch sends (user_globals()).
#' @param packages The packages those globals come from.
#' @return A list of class "hr_ctx".
#' @noRd
new_hr_ctx <- function(key = "", opts = list(), regs = list(), parent_meta = list(),
                       governor = NULL, draw = NULL, globals = list(),
                       packages = character(0)) {
  bad <- function(what) {
    gr_abort(sprintf("A run snapshot needs %s.", what), class = "gr_bad_ctx")
  }
  if (!is.character(key) || length(key) != 1L || is.na(key)) bad("`key` as one string")
  if (!is.list(opts)) bad("`opts` as a list")
  if (!is.list(regs)) bad("`regs` as a list")
  if (!is.list(parent_meta)) bad("`parent_meta` as a list")
  if (!is.null(governor) && !inherits(governor, "hr_governor")) {
    bad("`governor` as an hr_governor() or NULL")
  }
  if (!is.null(draw) && !is.list(draw)) bad("`draw` as a list or NULL")
  if (!is.list(globals)) bad("`globals` as a list")
  if (!is.character(packages)) bad("`packages` as a character vector")
  structure(list(key = key, opts = opts, regs = regs, parent_meta = parent_meta,
                 governor = governor, draw = draw, globals = globals,
                 packages = unique(packages)),
            class = "hr_ctx")
}

#' What a worker keeps of the snapshot: all of it but the globals and their
#' packages, which future sends to each worker itself. Kept in the function a
#' worker runs as well, each global reached every worker twice.
#' @noRd
hr_ctx_for_worker <- function(ctx) {
  ctx$globals <- list()
  ctx$packages <- character(0)
  ctx
}

#' Describe a run snapshot as lines of text. It says whether a key is set and
#' never shows the key.
#' @noRd
format_hr_ctx <- function(ctx) {
  if (!inherits(ctx, "hr_ctx")) gr_abort("`ctx` must come from new_hr_ctx().", class = "gr_bad_ctx")
  names_or <- function(x, none = "none") {
    nm <- names(x)
    if (length(nm)) paste(nm, collapse = ", ") else none
  }
  lim <- function(v) if (is.null(v) || !is.finite(v)) "none" else format(v, scientific = FALSE)
  gov <- ctx$governor
  draw <- ctx$draw
  c("<hr_ctx>",
    paste0("  key: ", if (nzchar(ctx$key)) "set" else "none"),
    paste0("  options: ", if (length(ctx$opts)) sprintf("%d applied", length(ctx$opts)) else "left as they are"),
    paste0("  registries: ", names_or(ctx$regs$core),
           sprintf("; %d layer provider(s)", length(ctx$regs$layers))),
    paste0("  meta: ", names_or(ctx$parent_meta)),
    paste0("  governor: ", if (is.null(gov)) "none" else
      sprintf("max_calls %s, max_cost_usd %s, max_tokens_total %s", lim(gov$max_calls),
              lim(gov$max_cost_usd), lim(gov$max_tokens_total))),
    paste0("  draw: ", if (is.null(draw$index) && is.null(draw$scope)) "none" else
      sprintf("index %s, scope %s", draw$index %||% 0L, draw$scope %||% "none")),
    paste0("  globals: ", names_or(ctx$globals)),
    paste0("  packages: ", if (length(ctx$packages)) paste(ctx$packages, collapse = ", ") else "none"))
}
