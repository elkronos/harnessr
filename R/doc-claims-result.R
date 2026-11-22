# doc-claims-result.R: the claims object and how it prints.

#' `lost` is the study numbers whose batch contributed nothing -- cut off at
#' the reply limit, failed, or not sent -- and `partial` says whether there
#' are any. `hidden` is the columns withheld from the model as bibliographic,
#' which gr_gaps() withholds too; `unmerged` says the reconcile pass could not
#' run over claims that needed it.
#' @noRd
new_claims <- function(claims, used, question, dropped, trace, lost = integer(0),
                       hidden = character(0), unmerged = FALSE, values = NULL,
                       unverified = "exclude") {
  claims <- reindex_claims(claims)
  support <- claim_support_table(claims)
  wide <- data.frame(
    claim_id = claims$claim_id, claim = claims$claim, kind = claims$kind,
    moderator = claims$moderator, scope = claims$scope,
    n_support = vapply(claims$.support, length, integer(1)),
    n_contradict = vapply(claims$.contradict, length, integer(1)),
    note = claims$note, stringsAsFactors = FALSE)
  rownames(wide) <- NULL
  structure(list(claims = wide, support = support, studies = used, question = question,
                 dropped = dropped, partial = length(lost) > 0L, lost = as.integer(lost),
                 unmerged = isTRUE(unmerged), hidden = as.character(hidden),
                 values = values %||% value_status(NULL, used, character(0)),
                 unverified = claims_unverified(values, unverified),
                 trace = trace), class = "gr_claims")
}

#' The unverified values, listed apart from the claims: `study`, `document`,
#' `field`, `value`, `quote` (the quote given, which did not verify, or NA)
#' and `shown`, whether the claims prompt showed it (`unverified = "include"`).
#' @noRd
claims_unverified <- function(values, mode = "exclude") {
  if (!NROW(values)) {
    return(data.frame(study = integer(0), document = character(0), field = character(0),
                      value = character(0), quote = character(0), shown = logical(0),
                      stringsAsFactors = FALSE))
  }
  un <- values[values$status == "unverified", c("study", "document", "field", "value", "quote"),
               drop = FALSE]
  un$shown <- rep(identical(mode, "include"), nrow(un))
  rownames(un) <- NULL
  un
}

#' Long form, the shape `$citations` already uses: one row per claim per study.
#' @noRd
claim_support_table <- function(claims) {
  if (!nrow(claims)) {
    return(data.frame(claim_id = integer(0), study = integer(0), role = character(0),
                      stringsAsFactors = FALSE))
  }
  parts <- list()
  for (i in seq_len(nrow(claims))) {
    for (role in c("supports", "contradicts")) {
      v <- if (identical(role, "supports")) claims$.support[[i]] else claims$.contradict[[i]]
      if (!length(v)) next
      parts[[length(parts) + 1L]] <- data.frame(claim_id = claims$claim_id[i], study = v,
                                                role = role, stringsAsFactors = FALSE)
    }
  }
  out <- if (length(parts)) do.call(rbind, parts) else
    data.frame(claim_id = integer(0), study = integer(0), role = character(0),
               stringsAsFactors = FALSE)
  rownames(out) <- NULL
  out
}

#' @export
print.gr_claims <- function(x, ...) {
  cat(sprintf("<gr_claims> %d claim(s) over %d study/studies\n",
              nrow(x$claims), nrow(x$studies)))
  if (nrow(x$claims)) {
    kinds <- table(x$claims$kind)
    cat(sprintf("  kinds: %s\n", paste(sprintf("%s %d", names(kinds), as.integer(kinds)),
                                       collapse = ", ")))
    dis <- sum(x$claims$n_contradict > 0L)
    cat(sprintf("  %d contested, %d of those with a moderator named\n", dis,
                sum(x$claims$n_contradict > 0L & !is.na(x$claims$moderator))))
    single <- sum(x$claims$n_support == 1L)
    if (single) cat(sprintf("  %d resting on a single study\n", single))
    for (i in seq_len(min(5L, nrow(x$claims)))) {
      cat(sprintf("  [%d] %s\n", x$claims$claim_id[i],
                  substr(x$claims$claim[i], 1, 96)))
    }
    if (nrow(x$claims) > 5L) cat(sprintf("  ... and %d more\n", nrow(x$claims) - 5L))
  }
  if (nrow(x$dropped)) {
    cat(sprintf("  %d dropped in verification; see $dropped\n", nrow(x$dropped)))
  }
  # `%||%` for a claims table saved before the field existed.
  un <- x$unverified %||% NULL
  if (NROW(un)) {
    cat(sprintf(paste0("  %d unverified value(s) %s; see $unverified\n"), nrow(un),
                if (all(un$shown)) "shown to the model, marked unverified"
                else "left out of the claims prompt"))
  }
  # `%||%` for a claims table saved before the field existed.
  if (length(x$lost %||% integer(0))) {
    cat(sprintf(paste0("  PARTIAL: %d of %d studies contributed nothing, their batch cut off, ",
                       "failed or not sent; see $lost\n"),
                length(x$lost), nrow(x$studies)))
  }
  if (isTRUE(x$unmerged)) {
    cat("  UNMERGED: claims from different batches were not reconciled, so one finding may\n")
    cat("  appear as more than one claim\n")
  }
  invisible(x)
}
