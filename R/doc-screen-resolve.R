# doc-screen-resolve.R: a person's decision on a record the screener left open.

#' Record a person's decision on screened records
#'
#' An `"unclear"` record is deferred to a person, and a record whose screening
#' call failed has no decision at all. `gr_resolve()` is how that person's
#' decision goes back into the run: the table takes the new decision, keeps the
#' screener's beside it, and says who decided and when, and the trace records
#' the same as a step of its own. `forward`, `deferred` and `included` are
#' rebuilt from the new decisions.
#'
#' The screener's own decision is kept in `screener_decision`, and
#' [gr_calibrate()] compares against that one: a calibration over resolved
#' records would otherwise credit the screener with the person's calls.
#' [gr_flow()] counts the resolved records in a row of their own.
#'
#' @param screening A `gr_screening` from [gr_screen()].
#' @param document The records to resolve, by `document` (as in the table) or
#'   by `document_id`.
#' @param decision `"include"` or `"exclude"`: one for all of `document`, or
#'   one each.
#' @param by Who decided: a name or initials. Required, because a decision with
#'   no one behind it cannot be checked or reported.
#' @param reason Optional: why, one each or one for all.
#' @param at When the decision was made. Defaults to now, and is recorded in
#'   UTC.
#' @return The `gr_screening`, with `table` gaining `screener_decision`,
#'   `resolved_by`, `resolved_at` and `resolved_reason` the first time a record
#'   is resolved.
#' @seealso [gr_screen()], [gr_flow()], [gr_calibrate()]
#' @family corpus functions
#' @export
#' @examples
#' cl <- gr_mock_client(function(messages, params) {
#'   '{"decision":"unclear","reason":"The excerpt does not say.",
#'     "criterion":null,"quote":null}'
#' })
#' f <- tempfile(fileext = ".txt")
#' writeLines("Participants were adults.", f)
#' s <- gr_screen(f, question = "Does the treatment work?",
#'                include = "Reports a randomised comparison", client = cl)
#' s$deferred
#' s <- gr_resolve(s, basename(f), "include", by = "A. Reviewer",
#'                 reason = "Methods section describes randomisation.")
#' s$table[, c("document", "decision", "screener_decision", "resolved_by")]
gr_resolve <- function(screening, document, decision, by, reason = NA_character_,
                       at = Sys.time()) {
  if (!inherits(screening, "gr_screening")) {
    gr_abort("`screening` must be a gr_screening from gr_screen().",
             class = "gr_bad_screening")
  }
  if (missing(by) || !is_nonblank(by) || length(by) != 1L) {
    gr_abort("`by` must name the person who decided: one non-blank string.",
             class = "gr_bad_setting")
  }
  document <- as.character(document)
  if (!length(document) || anyNA(document)) {
    gr_abort("`document` must name at least one screened record.", class = "gr_bad_setting")
  }
  recycle <- function(v, what) {
    if (length(v) == 1L) return(rep(v, length(document)))
    if (length(v) != length(document)) {
      gr_abort(sprintf("`%s` must have length 1 or %d, one per document.", what,
                       length(document)), class = "gr_bad_setting")
    }
    v
  }
  decision <- recycle(lower_text(trimws(to_utf8(as.character(decision)))), "decision")
  if (anyNA(decision) || !all(decision %in% c("include", "exclude"))) {
    gr_abort("`decision` must be 'include' or 'exclude'.", class = "gr_bad_setting")
  }
  reason <- recycle(as.character(reason), "reason")
  if (!inherits(at, "POSIXct") || length(at) != 1L || is.na(at)) {
    gr_abort("`at` must be one date-time, such as Sys.time().", class = "gr_bad_setting")
  }
  when <- format(at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  tab <- screening$table
  row <- match(document, tab$document)
  by_id <- is.na(row)
  row[by_id] <- match(document[by_id], tab$document_id)
  if (anyNA(row)) {
    gr_abort(sprintf("%d document(s) are not in this screening, starting with '%s'.",
                     sum(is.na(row)), document[which(is.na(row))[1]]),
             class = "gr_reference_mismatch")
  }
  dup <- !is.na(tab$duplicate_of[row])
  if (any(dup)) {
    gr_abort(sprintf(paste0("'%s' is a duplicate of '%s' and carries its decision. ",
                            "Resolve the first copy instead."),
                     tab$document[row[dup][1]], tab$duplicate_of[row[dup][1]]),
             class = "gr_bad_setting")
  }
  if (anyDuplicated(row)) {
    gr_abort("`document` names the same record more than once.", class = "gr_bad_setting")
  }
  if (is.null(screening$sources) || length(screening$sources) != nrow(tab)) {
    gr_abort(paste0("This screening has no `sources` to rebuild `forward` and `deferred` ",
                    "from; it was made before gr_resolve() existed. Screen again (with ",
                    "the same `store`, nothing is sent twice) and resolve that."),
             class = "gr_bad_screening")
  }

  # Added on the first resolution, so a run nobody has resolved keeps the
  # columns it always had.
  if (is.null(tab$screener_decision)) {
    tab$screener_decision <- tab$decision
    tab$resolved_by <- NA_character_
    tab$resolved_at <- NA_character_
    tab$resolved_reason <- NA_character_
  }
  from <- tab$decision[row]
  tab$decision[row] <- decision
  tab$resolved_by[row] <- by
  tab$resolved_at[row] <- when
  tab$resolved_reason[row] <- reason
  # A duplicate carries its first copy's decision, so it takes the person's
  # too; left alone, the table said "unclear" for the same study it had just
  # settled. Its screener_decision stays as it was.
  for (i in seq_along(row)) {
    copies <- which(!is.na(tab$duplicate_of) & tab$duplicate_of == tab$document[row[i]])
    tab$decision[copies] <- decision[i]
    tab$resolved_by[copies] <- by
    tab$resolved_at[copies] <- when
    tab$resolved_reason[copies] <- reason[i]
  }
  screening$table <- tab
  sets <- screening_sets(tab, screening$sources)
  screening$included <- sets$included
  screening$forward <- sets$forward
  screening$deferred <- sets$deferred

  # In the run's own record too: the table can be edited by anyone with the
  # object, the trace is where a reader checks what happened in what order.
  trace_note(screening$trace, "screen.resolve",
             list(document = tab$document[row], from = from, to = decision,
                  by = by, at = when, reason = reason))
  screening
}
