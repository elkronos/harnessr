# doc-methods-text.R: a methods paragraph written from a run's record.

#' A methods paragraph from a run's record
#'
#' Writes what a run's record says about how it was made as one plain
#' paragraph, for the methods section of a paper or a report: the harnessr
#' version, the models the requests asked for and the models the provider
#' said answered, how many requests were made and how many a cache
#' answered, the tokens sent and received (a request a cache or a recording
#' answered sent nothing, and its recorded tokens are given apart), the
#' settings changed from their defaults, and a hash of each distinct system
#' prompt, by stage. For a
#' benchmark it adds the arms, items, runs per item and the scorer.
#'
#' Everything in it is read from the record: the trace's request steps and
#' its pre-flight notes, or the benchmark's columns and attributes. It makes
#' no claim the record does not hold. It does not say the answers are right,
#' and where the record lacks something (the provider did not report the
#' model that answered, say) the paragraph says that it is not recorded.
#' Prompt hashes are the first 12 hex digits of the SHA-256 hash harnessr
#' keys its records with, taken of each system message, so two runs that sent
#' the same instructions show the same hash; the full prompts stay in the
#' trace.
#'
#' @param x A [gr_answer] (its own run's steps; see [gr_answer]), a
#'   [gr_trace], or a benchmark from [hr_benchmark()].
#' @return A character string, one paragraph, of class `gr_methods_text`;
#'   `print()` wraps it.
#' @seealso [as_json()] and [gr_trace_save()] for the full record,
#'   [gr_audit_report()] for a readable account of one answer
#' @family reading functions
#' @export
#' @examples
#' ch <- gr_segment(gr_example(), list(method = "paragraph", max_tokens = 150))
#' cl <- gr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
#' ans <- gr_read(ch, "What was revenue?", cl, gr_read_spec("retrieve", top_k = 3))
#' gr_methods_text(ans)
gr_methods_text <- function(x) {
  if (inherits(x, "hr_bench")) {
    out <- methods_bench(x)
  } else {
    trace <- if (inherits(x, "gr_answer")) answer_trace(x)
             else if (inherits(x, "gr_trace")) x
             else gr_abort("`x` must be a gr_answer, a gr_trace or a benchmark from hr_benchmark().",
                           class = "gr_bad_setting")
    if (!inherits(trace, "gr_trace")) {
      gr_abort("The answer keeps no trace, so there is no record to describe.",
               class = "gr_bad_setting")
    }
    out <- paste(c(methods_version(trace), methods_reads(trace), methods_requests(trace)),
                 collapse = " ")
  }
  structure(paste(c(out, paste0("This paragraph restates the run's record and makes no ",
                                "claim beyond it.")), collapse = " "),
            class = c("gr_methods_text", "character"))
}

#' @export
print.gr_methods_text <- function(x, ...) {
  cat(strwrap(unclass(x), width = 0.9 * getOption("width")), sep = "\n")
  invisible(x)
}

#' The version that wrote the record.
#' @noRd
methods_version <- function(trace) {
  v <- as_chr1(trace$meta[["readgpt", exact = TRUE]], NA_character_)
  if (is.na(v)) "The record does not say which version of harnessr made it."
  else sprintf("The run was made with harnessr %s.", v)
}

#' The reads in a trace, from their pre-flight notes: reader and settings.
#' @noRd
methods_reads <- function(trace) {
  pre <- Filter(function(s) is.list(s) && identical(s$label, "preflight") &&
                  identical(s$kind, "local"), trace$steps)
  if (!length(pre)) return(character(0))
  one <- vapply(pre, function(s) {
    d <- s$detail
    set <- d$settings
    sprintf("the '%s' reader %s", as_chr1(d$reader, "unknown"),
            if (length(set)) sprintf("with these settings changed from their defaults: %s",
                                     methods_settings(set))
            else "at its default settings")
  }, character(1))
  one <- unique(one)
  sprintf("It read %s with %s.", if (length(pre) == 1L) "once" else
            sprintf("%d times", length(pre)), methods_list(one))
}

#' Settings as "name = value" pairs.
#' @noRd
methods_settings <- function(set) {
  set <- set[!vapply(set, is.null, logical(1))]
  paste(sprintf("%s = %s", names(set), vapply(set, function(v) {
    if (is.character(v) && !is.null(names(v)) && any(nzchar(names(v)))) {
      paste(ifelse(nzchar(names(v)), paste0(names(v), ": ", v), v), collapse = ", ")
    } else if (is.atomic(v)) paste(format(v, trim = TRUE), collapse = ", ")
    else class(v)[1]
  }, character(1))), collapse = "; ")
}

#' "a", "a and b", "a, b and c".
#' @noRd
methods_list <- function(x) {
  if (length(x) <= 1L) return(paste(x, collapse = ""))
  paste(paste(x[-length(x)], collapse = ", "), "and", x[length(x)])
}

#' The requests in a trace: models, served models, counts, tokens and prompt
#' hashes.
#' @noRd
methods_requests <- function(trace) {
  req <- Filter(function(s) is.list(s) && !identical(s$kind, "local") && is.list(s$tokens),
                trace$steps)
  if (!length(req)) return("The record holds no model or embeddings requests.")
  emb <- vapply(req, function(s) identical(s$kind, "embedding"), logical(1))
  model <- vapply(req, function(s) as_chr1(s$model, NA_character_), character(1))
  served <- vapply(req, function(s) as_chr1(s$served_model, NA_character_), character(1))
  cached <- vapply(req, function(s) isTRUE(s$cached), logical(1))
  tok <- function(f, which) {
    sum(vapply(req[which], function(s) as_int1(s$tokens[[f]], 0L), integer(1)))
  }
  tokens <- function(which) {
    c(format(tok("input", which), big.mark = ","), format(tok("output", which), big.mark = ","))
  }
  named <- function(m) {
    m <- unique(m[!is.na(m) & nzchar(m)])
    if (length(m)) methods_list(sprintf("'%s'", m)) else "a model the record does not name"
  }
  out <- character(0)
  if (any(!emb)) {
    out <- c(out, sprintf("It made %d model request(s), which asked for %s.", sum(!emb),
                          named(model[!emb])))
    held_n <- sum(!emb & cached)
    if (held_n > 0) {
      out[length(out)] <- sprintf(paste0("It needed %d model answer(s), from %s; %s came from a ",
                                         "cache or a recording, not from the provider."),
                                  sum(!emb), named(model[!emb]),
                                  if (held_n == sum(!emb)) "all of them" else
                                    sprintf("%d of them", held_n))
    }
    sv <- served[!emb]
    out <- c(out, if (all(is.na(sv))) {
      "The provider did not report which model answered them."
    } else {
      sprintf("The provider reported that %s answered %d of them.", named(sv), sum(!is.na(sv)))
    })
    # Only a request that went out sent anything. One a cache or a recording
    # answered keeps the tokens of the request it stands for, which this run
    # did not send.
    live <- !emb & !cached
    held <- !emb & cached
    if (!any(held)) {
      out <- c(out, sprintf("They sent %s prompt token(s) and received %s reply token(s).",
                            tokens(live)[1], tokens(live)[2]))
    } else {
      if (any(live)) {
        out <- c(out, sprintf(paste0("The %d sent to the provider carried %s prompt token(s) ",
                                     "and received %s reply token(s)."),
                              sum(live), tokens(live)[1], tokens(live)[2]))
      }
      out <- c(out, sprintf(paste0("The answers from a cache or a recording sent nothing. ",
                                   "Their record holds %s prompt token(s) and %s reply ",
                                   "token(s) from the run that first made those requests."),
                            tokens(held)[1], tokens(held)[2]))
    }
  }
  if (any(emb)) {
    out <- c(out, sprintf("It made %d embeddings request(s), to %s.", sum(emb), named(model[emb])))
  }
  if (any(emb & cached)) {
    out <- c(out, sprintf("%d of the %d embeddings request(s) were answered from a cache.",
                          sum(emb & cached), sum(emb)))
  }
  c(out, methods_prompts(req[!emb]))
}

#' A hash of each distinct system prompt, by stage.
#' @noRd
methods_prompts <- function(req) {
  if (!length(req)) return(character(0))
  stage <- vapply(req, function(s) as_chr1(s$label, "call"), character(1))
  sys <- vapply(req, function(s) {
    m <- Filter(function(p) identical(p$role, "system"), s$prompt %||% list())
    if (length(m)) as_chr1(m[[1]]$content, NA_character_) else NA_character_
  }, character(1))
  keep <- !is.na(sys)
  if (!any(keep)) return("The requests carried no system prompt.")
  key <- unique(data.frame(stage = stage[keep], sys = sys[keep], stringsAsFactors = FALSE))
  hashes <- vapply(key$sys, function(p) substr(hr_hash(p), 1L, 12L), character(1))
  sprintf("Their system prompts, by stage, have the hashes %s.",
          methods_list(sprintf("%s %s", key$stage, hashes)))
}

#' A benchmark: its design, then the requests of the whole benchmark.
#' @noRd
methods_bench <- function(x) {
  arms <- unique(as.character(x$arm))
  runs <- attr(x, "runs", exact = TRUE)
  items <- length(unique(as.character(x$item)))
  pcols <- grep("^param\\.", names(x), value = TRUE)
  arm_set <- vapply(arms, function(a) {
    row <- x[x$arm == a, pcols, drop = FALSE][1, , drop = FALSE]
    vals <- vapply(pcols, function(p) {
      v <- row[[p]]
      if (is.list(v)) v <- v[[1]]
      if (is.null(v) || (length(v) == 1L && is.na(v))) NA_character_
      else paste(format(v, trim = TRUE), collapse = ", ")
    }, character(1))
    vals <- vals[!is.na(vals)]
    if (!length(vals)) return(sprintf("'%s'", a))
    sprintf("'%s' (%s)", a, paste(sprintf("%s = %s", sub("^param\\.", "", names(vals)), vals),
                                  collapse = "; "))
  }, character(1))
  design <- sprintf(paste0("The benchmark ran %d arm(s), %s, on %d item(s), %s run(s) per item, ",
                           "%d run(s) in all, scored by %s."),
                    length(arms), methods_list(arm_set), items,
                    if (is.null(runs)) "an unrecorded number of" else format(runs), nrow(x),
                    sprintf("'%s'", as_chr1(attr(x, "scorer", exact = TRUE), "an unnamed scorer")))
  ref <- as_chr1(attr(x, "reference_hash", exact = TRUE), NA_character_)
  if (!is.na(ref)) design <- paste(design, sprintf("The reference set has the hash %s.",
                                                   substr(ref, 1L, 12L)))
  tr <- attr(x, "trace", exact = TRUE)
  paste(c(if (inherits(tr, "gr_trace")) methods_version(tr), design,
          if (inherits(tr, "gr_trace")) methods_requests(tr)), collapse = " ")
}
