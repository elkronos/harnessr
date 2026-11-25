# doc-stage-upgrade.R: bring a review-stage object saved by an earlier version
# up to the fields this version reads.

#' Fill the fields an older stage object lacks with their defaults.
#'
#' A stage object saved with saveRDS() by an earlier version lacks the fields
#' added since. Each reader used to guard each such field where it read it;
#' this fills them once, at the entry points that read them (gr_gaps(),
#' gr_outline(), gr_synthesise(), gr_recheck(), gr_audit_report() and the
#' print methods of gr_claims and gr_synthesis), so the code after reads the
#' field directly. Each default is the value a run that recorded nothing of
#' the kind would hold:
#'
#' - `gr_claims`: `lost` `integer(0)` and `unmerged` `FALSE` (every batch came
#'   back and merged); `hidden` the conventional bibliographic columns of
#'   `$studies`, which is what a claims table withheld before it recorded
#'   them.
#' - `gr_synthesis`: its `$claims` as above; `unrendered` `integer(0)`;
#'   `cite_style` `"marker"`; `bib_columns` from `$studies`; and the section
#'   counts `n_unsupplied`, `n_unparsed`, `n_truncated`, `n_unbacked`,
#'   `lost_batches` and `capped_batches` `0L`.
#' - `gr_calibration`: an `adequacy` list, with `rule` `"positives"` when it
#'   had none, and the count sentence as its `note` when the sample is not
#'   adequate and the calibration gave no note of its own.
#'
#' Fields whose absence itself means "not recorded" stay absent: a
#' synthesis's `section_studies` (what each section was shown is unknown) and a
#' calibration's `agreement`, `recall` and `worst_case`. So does the `sign_p`
#' column of a claims table: the audit report shows it only when the table
#' holds it, and print() works it out from the counts. The readers keep their
#' checks for those.
#'
#' It never aborts and adds no class. A gr_screening or gr_extraction has no
#' fields to fill, so it comes back as it is, hand-built ones such as
#' `structure(list(table = tab), class = "gr_screening")` included. An object
#' made by this version comes back unchanged.
#' @param x Any object; stage objects are upgraded, anything else is returned
#'   as it is.
#' @return `x`, with the missing fields filled.
#' @noRd
gr_upgrade_stage <- function(x) {
  if (!is.list(x)) return(x)
  fill <- function(x, name, value) {
    if (is.null(x[[name, exact = TRUE]]) && !is.null(value)) x[[name]] <- value
    x
  }
  if (inherits(x, "gr_claims")) {
    x <- fill(x, "lost", integer(0))
    x <- fill(x, "unmerged", FALSE)
    if (is.data.frame(x$studies)) {
      x <- fill(x, "hidden", unlist(bib_columns(x$studies), use.names = FALSE))
    }
  } else if (inherits(x, "gr_synthesis")) {
    if (inherits(x[["claims", exact = TRUE]], "gr_claims")) {
      x$claims <- gr_upgrade_stage(x$claims)
    }
    x <- fill(x, "unrendered", integer(0))
    x <- fill(x, "cite_style", "marker")
    if (is.data.frame(x$studies)) x <- fill(x, "bib_columns", bib_columns(x$studies))
    s <- x[["sections", exact = TRUE]]
    if (is.data.frame(s)) {
      for (col in c("n_unsupplied", "n_unparsed", "n_truncated", "n_unbacked",
                    "lost_batches", "capped_batches")) {
        if (is.null(s[[col]])) s[[col]] <- integer(nrow(s))
      }
      x$sections <- s
    }
  } else if (inherits(x, "gr_calibration")) {
    a <- x[["adequacy", exact = TRUE]]
    if (!is.list(a)) a <- list(rule = "positives")
    note <- a[["note", exact = TRUE]]
    if (!is.character(note) || length(note) != 1L || is.na(note)) {
      a$note <- if (isTRUE(x$adequate)) NA_character_ else
        sprintf(paste0("Only %d eligible record(s) in the sample, below the %s this ",
                       "calibration asks for. The intervals are too wide to conclude much."),
                # %s and format(), not %d: min_positives is a double, and may be
                # Inf (never adequate), which %d refuses.
                as.integer(x$n_positives), format(x$min_positives))
    }
    x$adequacy <- a
  }
  x
}
