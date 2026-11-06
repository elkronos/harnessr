# doc-claims-gaps.R: what the claims leave unanswered.

# ---------------------------------------------------------------------------
# What the corpus does not contain.
# ---------------------------------------------------------------------------

#' What a body of work does not cover
#'
#' Reviews are read for the gap, and a gap a model was asked to notice is an
#' impression. This computes them instead, in R, from the extraction table and
#' the claims: a declared category nobody studied, a dimension with no variation,
#' an empty cell in a crosstab, a claim resting on one study that nobody has
#' tried to replicate, a disagreement nothing in the table explains. Every row is
#' a fact about the corpus that can be checked by counting.
#'
#' No model is called. [gr_synthesise()] takes the result as `gaps =` and hands
#' it to the closing section with an instruction to state these and no others,
#' which is what keeps the written gap list attached to the table.
#'
#' @param claims A [gr_claims()] result.
#' @param extraction The [gr_extract()] result the claims came from. Only its
#'   `$fields` is used, and only to learn which categories were *declared*;
#'   without it a category nobody studied is indistinguishable from one nobody
#'   thought of.
#' @param max_cells Cap on reported empty combinations, which grow as the product
#'   of two fields' sizes.
#' @param min_reported A field missing for more than this fraction of studies is
#'   reported as not reported.
#' @param bib Which columns carry bibliographic identity, as in [gr_claims()]
#'   and [gr_synthesise()]. They are not dimensions of the evidence -- "every
#'   study reports 'Lancet'" is not a gap in a literature -- and a gap line goes
#'   to the writing model, which is never told who wrote a study. The columns
#'   `claims` withheld are left out whatever this says; `bib` adds to them.
#' @return A data frame of class `gr_gaps`: `kind`, `dimension`, `detail`, `n`.
#' @seealso [gr_claims()], [gr_outline()], [gr_synthesise()]
#' @export
#' @examples
#' tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok",
#'                   duplicate_of = NA_character_, n_filled = 1L, n_unverified = 0L,
#'                   conflicts = NA_character_, design = c("cohort", "cohort"),
#'                   stringsAsFactors = FALSE)
#' cl <- gr_mock_client(function(messages, params) paste0(
#'   '{"claims":[{"claim":"One cohort found it.","kind":"finding","supported_by":[1],',
#'   '"contradicted_by":[],"moderator":null,"scope":"one study"}]}'))
#' cm <- gr_claims(tab, question = "Does it work?", client = cl)
#' gr_gaps(cm)
gr_gaps <- function(claims, extraction = NULL, max_cells = 40L, min_reported = 0.5,
                    bib = NULL) {
  if (!inherits(claims, "gr_claims")) {
    gr_abort("`claims` must come from gr_claims().", class = "gr_bad_claims")
  }
  st <- claims$studies
  cw <- claims$claims
  fields <- if (inherits(extraction, "gr_extraction")) extraction$fields else
    if (inherits(extraction, "gr_fields")) extraction else NULL
  # The fields the claims model was shown, by the rule render_studies() uses.
  # Every column but the reserved ones made authors, year and venue dimensions,
  # and "no variation (authors): ... all say 'Smith, J.; Okafor, A.'" went to
  # the closing section as a gap the writer was told to state. `%||%` for a
  # claims table saved before it recorded what it withheld.
  hidden <- union(claims$hidden %||% unlist(bib_columns(st), use.names = FALSE),
                  unlist(bib_columns(st, bib), use.names = FALSE))
  cols <- setdiff(study_fields(st, hide = hidden), .gr_reserved_fields)
  out <- list()
  add <- function(kind, dimension, detail, n) {
    out[[length(out) + 1L]] <<- data.frame(kind = kind, dimension = dimension,
                                          detail = detail, n = as.integer(n),
                                          stringsAsFactors = FALSE)
  }
  # The table's values and the declared categories, labelled UTF-8 before they
  # are compared. Under a non-UTF-8 locale a category typed in gr_fields() is
  # unlabelled bytes, and a value the model returned is labelled, so an
  # accented category never matched itself: it was reported as declared and
  # unstudied, and every combination with it as unstudied, in a table where a
  # study reports it -- gaps the closing section is told to state.
  txt <- function(v) trimws(mark_utf8(as.character(v)))
  vals <- function(col) {
    v <- txt(st[[col]])
    v[!is.na(v) & nzchar(v) & v != "NA"]
  }

  # 1. A category that was declared and nobody studied. Only knowable from the
  #    schema: without it, "no qualitative studies" and "we never asked about
  #    design" look identical.
  enums <- character(0)
  if (!is.null(fields)) {
    for (nm in intersect(names(fields), cols)) {
      f <- fields[[nm]]
      if (!identical(f$type, "enum") || !length(f$values)) next
      enums <- c(enums, nm)
      absent <- setdiff(mark_utf8(as.character(f$values)), vals(nm))
      if (length(absent)) {
        add("declared but unstudied", nm, paste(absent, collapse = "; "), length(absent))
      }
    }
  }

  for (nm in cols) {
    v <- vals(nm)
    # 2. A field every study answers the same way cannot explain a disagreement,
    #    and cannot bound a claim's scope either.
    if (length(v) > 1L && length(unique(v)) == 1L) {
      # "every study reports 'cohort'" was printed when 2 of 10 studies reported
      # it and the other 8 left the cell empty -- `v` drops the missing ones, so
      # the sentence described the reporters as the whole table. A gap report
      # that overstates what the literature says is worse than none.
      add("no variation", nm,
          if (length(v) == nrow(st)) sprintf("every study reports '%s'", unique(v))
          else sprintf("the %d of %d studies that report it all say '%s'",
                       length(v), nrow(st), unique(v)),
          length(v))
    }
    # 3. A field most studies do not report is a gap in the literature's
    #    reporting, which is a finding about the literature.
    miss <- nrow(st) - length(v)
    if (nrow(st) && miss / nrow(st) > min_reported) {
      add("mostly not reported", nm, sprintf("%d of %d studies do not report it",
                                             miss, nrow(st)), miss)
    }
  }

  # 4. Empty cells between two declared dimensions: the combination nobody has
  #    looked at, which is the most actionable kind of gap there is.
  if (length(enums) >= 2L) {
    cells <- 0L
    pairs <- utils::combn(sort(enums), 2L, simplify = FALSE)
    for (pr in pairs) {
      a <- mark_utf8(as.character(fields[[pr[1]]]$values))
      b <- mark_utf8(as.character(fields[[pr[2]]]$values))
      # trimws(), because vals() trims and this did not: a cell holding " cohort"
      # counted as studied for rule 2 and as UNSTUDIED here, so the same table
      # produced "every study reports 'cohort'" and "design = 'cohort' with ...
      # unstudied" in one report.
      seen <- unique(paste(txt(st[[pr[1]]]), txt(st[[pr[2]]]), sep = "\u0001"))
      for (x in a) for (y in b) {
        if (cells >= max_cells) break
        if (!paste(x, y, sep = "\u0001") %in% seen) {
          add("combination unstudied", paste(pr, collapse = " x "),
              sprintf("%s = '%s' with %s = '%s'", pr[1], x, pr[2], y), 0L)
          cells <- cells + 1L
        }
      }
      if (cells >= max_cells) break
    }
  }

  # 5 and 6. Gaps the CLAIMS carry rather than the table.
  if (nrow(cw)) {
    lone <- cw$claim_id[cw$n_support == 1L & cw$n_contradict == 0L]
    for (id in lone) {
      add("unreplicated", sprintf("claim %d", id),
          substr(cw$claim[cw$claim_id == id], 1, 160), 1L)
    }
    open <- cw$claim_id[cw$n_contradict > 0L & is.na(cw$moderator)]
    for (id in open) {
      add("disagreement unexplained", sprintf("claim %d", id),
          substr(cw$claim[cw$claim_id == id], 1, 160),
          cw$n_support[cw$claim_id == id] + cw$n_contradict[cw$claim_id == id])
    }
    for (id in cw$claim_id[cw$kind == "gap"]) {
      add("stated as a gap", sprintf("claim %d", id),
          substr(cw$claim[cw$claim_id == id], 1, 160), cw$n_support[cw$claim_id == id])
    }
  }

  res <- if (length(out)) do.call(rbind, out) else
    data.frame(kind = character(0), dimension = character(0), detail = character(0),
               n = integer(0), stringsAsFactors = FALSE)
  rownames(res) <- NULL
  structure(res, class = c("gr_gaps", "data.frame"),
            studies = nrow(st), had_schema = !is.null(fields))
}

# `[` on a classed data frame keeps the class and loses every other attribute, so
# `g[, c("kind", "dimension")]` was still dispatched to print.gr_gaps() -- which
# then reported "NA study/studies" and "no schema given" about a perfectly good
# object, because the attributes carrying both had been dropped by the subset.
# Selecting columns from a table should give a table.
#' @export
`[.gr_gaps` <- function(x, ...) {
  out <- NextMethod()
  if (is.data.frame(out)) {
    class(out) <- "data.frame"
    attr(out, "studies") <- NULL
    attr(out, "had_schema") <- NULL
  }
  out
}

#' @export
print.gr_gaps <- function(x, ...) {
  cat(sprintf("<gr_gaps> %d gap(s) over %s study/studies\n", nrow(x),
              format(attr(x, "studies") %||% NA)))
  if (!isTRUE(attr(x, "had_schema"))) {
    cat("  no schema given, so a category nobody studied cannot be told from one\n")
    cat("  nobody asked about; pass `extraction =` for those\n")
  }
  if (nrow(x)) {
    k <- table(x$kind)
    for (nm in names(k)) cat(sprintf("  %-26s %d\n", nm, as.integer(k[[nm]])))
  }
  invisible(x)
}

#' The gaps as the lines a section may state.
#' @noRd
render_gaps <- function(gaps) {
  if (!is.data.frame(gaps) || !nrow(gaps)) return(NULL)
  # Labelled column by column before they are joined. A gap line quotes the
  # table ("every study reports ...") or a claim, and one of those can be
  # labelled UTF-8 while the other is not -- a table read in under a C locale
  # -- and paste() then escaped the unlabelled lines to "<c3><a9>".
  txt <- function(v) mark_utf8(as.character(v))
  paste(sprintf("- %s (%s): %s", txt(gaps$kind), txt(gaps$dimension), txt(gaps$detail)),
        collapse = "\n")
}
