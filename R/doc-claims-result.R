# doc-claims-result.R: the claims object and how it prints.

#' `lost` is the study numbers whose batch contributed nothing -- cut off at
#' the reply limit, failed, or not sent -- and `partial` says whether there
#' are any. `hidden` is the columns withheld from the model as bibliographic,
#' which gr_gaps() withholds too; `unmerged` says the reconcile pass could not
#' run over claims that needed it.
#' @noRd
new_claims <- function(claims, used, question, dropped, trace, lost = integer(0),
                       hidden = character(0), unmerged = FALSE, values = NULL,
                       unverified = "exclude", declared = character(0), moderators = NULL) {
  claims <- reindex_claims(claims)
  support <- claim_support_table(claims)
  n_sup <- vapply(claims$.support, length, integer(1))
  n_con <- vapply(claims$.contradict, length, integer(1))
  wide <- data.frame(
    claim_id = claims$claim_id, claim = claims$claim, kind = claims$kind,
    moderator = claims$moderator,
    moderator_status = claims$moderator_status %||% rep(NA_character_, nrow(claims)),
    scope = claims$scope,
    n_support = n_sup, n_contradict = n_con,
    # The direction tally's exact sign test, and whether the tally is too
    # small for any split of it to reach p < 0.05.
    sign_p = sign_test(n_sup, n_sup + n_con),
    low_power = sign_test_min(n_sup + n_con) > 0.05,
    note = claims$note, stringsAsFactors = FALSE)
  rownames(wide) <- NULL
  structure(list(claims = wide, support = support, studies = used, question = question,
                 dropped = dropped, partial = length(lost) > 0L, lost = as.integer(lost),
                 unmerged = isTRUE(unmerged), hidden = as.character(hidden),
                 values = values %||% value_status(NULL, used, character(0)),
                 moderators = moderators %||% moderator_tests(claims[0, , drop = FALSE], used),
                 declared = as.character(declared),
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

#' A sign test p as print() and the audit report give it: four significant
#' digits, so 5 of 5 reads 0.0625 and 1 of 1 reads 1.
#' @noRd
format_sign_p <- function(p) {
  ifelse(is.na(p), "NA", trimws(formatC(signif(p, 4), format = "g", digits = 4)))
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
    # Ranked by certainty, as a section ranks them (claim_order()); a claims
    # table saved before the tally existed is ranked from its counts.
    cw <- x$claims
    p <- cw$sign_p %||% sign_test(cw$n_support, cw$n_support + cw$n_contradict)
    low <- sign_test_min(cw$n_support + cw$n_contradict) > 0.05
    ord <- order(p, cw$claim_id)
    for (i in utils::head(ord, 5L)) {
      cat(sprintf("  [%d] %s\n", cw$claim_id[i], substr(cw$claim[i], 1, 96)))
      cat(sprintf("      %d of %d studies in its direction, sign test p = %s%s\n",
                  cw$n_support[i], cw$n_support[i] + cw$n_contradict[i],
                  format_sign_p(p[i]), if (isTRUE(low[i])) " (low power)" else ""))
    }
    if (nrow(cw) > 5L) cat(sprintf("  ... and %d more\n", nrow(cw) - 5L))
    mt <- x$moderators %||% NULL
    if (NROW(mt)) {
      cat(sprintf("  %d moderator(s) named, %d declared in advance; see $moderators\n",
                  nrow(mt), sum(mt$declared)))
      for (j in utils::head(seq_len(nrow(mt)), 5L)) {
        cat(sprintf("    claim %d: %s, %s, %d vs %d studies, Fisher p = %s (smallest attainable %s)%s\n",
                    mt$claim_id[j], mt$moderator[j],
                    if (mt$exploratory[j]) "exploratory" else "declared",
                    mt$n_support[j], mt$n_contradict[j], format_sign_p(mt$fisher_p[j]),
                    format_sign_p(mt$min_p[j]),
                    if (!is.na(mt$holm_p[j])) sprintf(", Holm p = %s", format_sign_p(mt$holm_p[j]))
                    else ""))
      }
      cat(paste0("  assess each against the ICEMAN items (Schandelmaier et al. 2020), listed in\n",
                 "  ?gr_claims; harnessr scores none of them\n"))
    }
    if (any(isTRUE_vec(low))) {
      cat(paste0("  low power: a tally of 5 or fewer studies cannot reach p < 0.05 by a sign\n",
                 "  test however it falls, so read it as a count of directions, not as evidence\n",
                 "  of an effect (Campbell et al. 2020; Boon and Thomson 2021)\n"))
    }
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
