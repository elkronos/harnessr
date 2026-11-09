# core-bench-judge.R: a model call that picks between candidates or grades
# one against a reference, and the record that says whether its decisions can
# be used as scores.
#
# A judge is a model-made decision, so it is kept on a short lead. It sees
# the candidates under letters only, never their source. It is asked again
# with the presentation order swapped, and a verdict that moves with the
# order is reported as unresolved rather than picked. Its calls go into a
# ledger of their own, so what judging cost is never folded into the cost of
# the run it scored. And it scores a benchmark only once a validation record
# against blind human labels exists for its exact configuration: the model,
# the prompt and rubric, the order handling and how verdicts are combined.
# Change any of these and the record no longer applies.

#' The judge's modes.
#' @noRd
.hr_judge_modes <- c("select", "grade", "pairwise")

#' The call stem every judge request is labelled under: "judge.<mode>.o<k>",
#' k the presentation order.
#' @noRd
.hr_judge_calls <- "judge"

#' How the verdicts of the presentation orders are combined: all must agree,
#' or the result is unresolved.
#' @noRd
.hr_judge_aggregation <- "unanimous"

#' The instructions each mode's requests start with. Part of a judge's
#' configuration hash, so a change to them voids every validation record.
#' @noRd
.hr_judge_prompts <- list(
  select = paste(
    "You compare candidate answers and choose the one that best meets the rubric.",
    "The candidates are labelled with letters in the order they are shown; the letters",
    "and the order carry no meaning. Judge what each candidate says, not its length,",
    "style or position. Reply with JSON: {\"verdict\": the letter of the chosen",
    "candidate, \"reason\": one sentence}."),
  grade = paste(
    "You grade one response against a reference answer, following the rubric.",
    "Judge what the response says, not its length or style, and not the order in which",
    "the reference and the response are shown. Reply with JSON: {\"verdict\": one of",
    "the allowed grades, \"reason\": one sentence}."),
  pairwise = paste(
    "You compare two candidate answers, A and B, following the rubric. The letters",
    "and the order carry no meaning. Judge what each candidate says, not its length,",
    "style or position. Reply with JSON: {\"verdict\": \"A\", \"B\" or \"tie\",",
    "\"reason\": one sentence}."))

#' The grades a grade-mode judge gives when no schema says otherwise.
#' @noRd
.hr_judge_grades <- c("pass", "fail")

#' A judge configuration
#'
#' Everything that decides what a judge answers, held in one object with a
#' hash: the model, the mode, the rubric, the package's instructions for
#' that mode, the reply schema, the number of presentation orders, how their
#' verdicts are combined (`"unanimous"`: every order must agree) and, for
#' grading, which grade counts as positive. [hr_judge_validate()] keys its
#' record by this hash, and [hr_judge_valid()] says a record no longer holds
#' once any part of it differs.
#'
#' Orders: with `orders = 2` the candidates are shown in their given order
#' and then reversed; for `"grade"` the reference comes first and then the
#' response first. With more than two candidates in `"select"`, `orders`
#' above 2 shows that many cyclic rotations, since a forward and a reversed
#' order leave the middle positions where they were. `orders = 1` is allowed
#' only for `"grade"`, and such a judge has no swap check.
#'
#' The reply is JSON with a string `verdict` and a `reason`. For `"select"`
#' the verdict is a candidate's letter, for `"pairwise"` `"A"`, `"B"` or
#' `"tie"`, and for `"grade"` one of the grades, `"pass"` or `"fail"` unless
#' `schema` gives others as the `enum` of its `verdict` property. A `schema`
#' of your own must be an object schema with a string `verdict` property.
#'
#' @param model The judge's model, one string.
#' @param rubric What the judge is to decide, in words, one string.
#' @param mode `"select"` (choose one of several candidates), `"grade"`
#'   (grade one response against a reference) or `"pairwise"` (A, B or a tie).
#' @param orders How many presentation orders each item is judged in.
#' @param schema `NULL` for the default reply schema, or a JSON schema (a
#'   list) with a string `verdict` property.
#' @param positive For `"grade"`, the grade that counts as positive (the
#'   response is right); the first allowed grade by default. Ignored for the
#'   other modes.
#' @param x An `hr_judge_config`.
#' @param ... Ignored.
#' @return An object of class `hr_judge_config`: a list of `model`, `mode`,
#'   `rubric`, `prompt` (the package's instructions for the mode), `schema`,
#'   `orders`, `aggregation`, `positive`, `grades` and `hash` (SHA-256 of the
#'   others).
#' @seealso [hr_judge()], [hr_judge_validate()], [hr_scorer_judge()]
#' @family judges
#' @export
#' @examples
#' cfg <- hr_judge_config("mock-model", "Is the response's answer the reference's?",
#'                        mode = "grade")
#' cfg
#' # Another rubric is another configuration.
#' other <- hr_judge_config("mock-model", "Is the response fully correct?", mode = "grade")
#' identical(cfg$hash, other$hash)
hr_judge_config <- function(model, rubric, mode = c("select", "grade", "pairwise"), orders = 2,
                            schema = NULL, positive = NULL) {
  mode <- match.arg(mode)
  if (!is_bench_string(model)) {
    gr_abort("`model` must be one non-blank string.", class = "gr_bad_setting")
  }
  if (missing(rubric) || !is_bench_string(rubric)) {
    gr_abort("`rubric` must be one non-blank string saying what the judge decides.",
             class = "gr_bad_setting")
  }
  if (!is.numeric(orders) || length(orders) != 1L || is.na(orders) || !is.finite(orders) ||
      orders < 1 || orders != round(orders)) {
    gr_abort("`orders` must be one whole number, at least 1.", class = "gr_bad_setting")
  }
  orders <- as.integer(orders)
  if (orders == 1L && mode != "grade") {
    gr_abort(sprintf(paste0("`orders = 1` is allowed only for mode \"grade\". A %s judge is ",
                            "asked in at least two orders, so a verdict that follows the ",
                            "position of a candidate is caught."), mode),
             class = "gr_bad_setting")
  }
  if (orders > 2L && mode != "select") {
    gr_abort(sprintf("Mode \"%s\" has two presentation orders at most.", mode),
             class = "gr_bad_setting")
  }
  grades <- NULL
  if (!is.null(schema)) {
    v <- if (is.list(schema)) schema[["properties", exact = TRUE]][["verdict", exact = TRUE]]
    if (!is.list(schema) || !identical(schema[["type", exact = TRUE]], "object") ||
        !is.list(v) || !identical(v[["type", exact = TRUE]], "string")) {
      gr_abort("`schema` must be an object schema with a string `verdict` property.",
               class = "gr_bad_setting")
    }
    e <- v[["enum", exact = TRUE]]
    if (length(e)) grades <- as.character(unlist(e, use.names = FALSE))
  }
  if (mode == "grade") {
    if (is.null(schema)) grades <- .hr_judge_grades
    if (is.null(positive)) {
      if (is.null(grades)) {
        gr_abort(paste0("Give `positive`, the grade that counts as right: the schema's ",
                        "`verdict` has no enum to take it from."), class = "gr_bad_setting")
      }
      positive <- grades[[1L]]
    }
    if (!is_bench_string(positive) || (!is.null(grades) && !positive %in% grades)) {
      gr_abort(sprintf("`positive` must be one of the grades: %s.",
                       paste(grades %||% "(any string)", collapse = ", ")),
               class = "gr_bad_setting")
    }
  } else {
    positive <- NULL
  }
  cfg <- list(model = model, mode = mode, rubric = rubric, prompt = .hr_judge_prompts[[mode]],
              schema = schema, orders = orders, aggregation = .hr_judge_aggregation,
              positive = positive, grades = grades)
  cfg$hash <- judge_config_hash(cfg)
  structure(cfg, class = "hr_judge_config")
}

#' The parts of a configuration its hash covers, by name.
#' @noRd
.hr_judge_key_parts <- c("model", "mode", "rubric", "prompt", "schema", "orders",
                         "aggregation", "positive")

#' @noRd
judge_config_hash <- function(cfg) {
  hr_hash(unclass(cfg)[.hr_judge_key_parts])
}

#' A configuration, checked: built by hr_judge_config() and unchanged since.
#' @noRd
check_judge_config <- function(cfg, arg = "judge_config") {
  if (!inherits(cfg, "hr_judge_config") || !is.character(cfg$hash)) {
    gr_abort(sprintf("`%s` must come from hr_judge_config().", arg), class = "gr_bad_setting")
  }
  if (!identical(judge_config_hash(cfg), cfg$hash)) {
    gr_abort(sprintf(paste0("`%s` was changed after hr_judge_config() built it, so its hash ",
                            "no longer describes it. Build a new one."), arg),
             class = "gr_bad_setting")
  }
  invisible(cfg)
}

#' @rdname hr_judge_config
#' @export
print.hr_judge_config <- function(x, ...) {
  cat(sprintf("<hr_judge_config %s> %s, %d order(s), %s\n", substr(x$hash, 1, 12), x$mode,
              x$orders, x$aggregation))
  cat(sprintf("  model: %s\n", x$model))
  if (identical(x$mode, "grade")) {
    cat(sprintf("  grades: %s (positive: %s)\n",
                paste(x$grades %||% "(any)", collapse = ", "), x$positive))
  }
  cat(sprintf("  rubric: %s\n", substr(x$rubric, 1, 200)))
  invisible(x)
}

#' Judge candidates with a model, in more than one order
#'
#' Asks a model to choose between candidates (`"select"`), to compare two
#' (`"pairwise"`) or to grade one against a reference (`"grade"`), once per
#' presentation order, and combines the verdicts. The candidates are shown
#' under the letters A, B, ... only; their names, and so their source, are not
#' sent. With `orders = 2` the order is swapped on the second request (see
#' [hr_judge_config()]); when the verdicts, mapped back to the candidates they
#' name, differ between orders, the result is `"unresolved"` with
#' `degradation = "judge_inconsistent"`, never a pick. Position bias of this
#' kind is common in model judges (Zheng et al. 2023; Wang et al. 2024).
#'
#' Every request goes through [gr_call()]'s path, so the governor checks it
#' before it is sent, a [gr_cache()] keys it with `draw_index`, and the
#' trace records it, under the label `judge.<mode>.o<k>` for order k. The
#' requests are recorded in a trace of the judge's own (`$trace`), never in
#' `trace`, and their cost is reported in `$judge_cost`, so a run's cost
#' never includes the judging of it. When `trace` is given, the judge is held
#' to what that run's governor has left (calls, dollars and tokens) and a
#' local note naming the judge's trace and cost is added to it. `governor`, if
#' given, is used instead.
#'
#' A failed request, or a reply with no allowed verdict, makes the result
#' `"failed"`.
#'
#' @param candidates The candidates, a character vector (or a list of single
#'   strings). Names, when every candidate has a distinct one, identify them in
#'   `value`; otherwise their positions do. `"select"` takes 2 to 26,
#'   `"pairwise"` exactly 2 and `"grade"` exactly 1.
#' @param client A `gr_client`.
#' @param mode `"select"`, `"grade"` or `"pairwise"`.
#' @param reference Text the judge sees beside the candidates: evidence or a
#'   reference answer. Required for `"grade"`.
#' @param model The judge's model; the client's model when `NULL`.
#' @param orders Presentation orders. See [hr_judge_config()].
#' @param rubric What the judge decides, in words.
#' @param schema `NULL`, or a reply schema with a string `verdict` property.
#' @param trace Optional `gr_trace` of the run being judged.
#' @param governor Optional [hr_governor()] for the judge's requests.
#' @param draw_index Draw index passed to every request (see [gr_call()]).
#' @param x An `hr_judgement`.
#' @param ... Ignored.
#' @return An object of class `hr_judgement`, a list with
#' \describe{
#'   \item{`value`}{The verdict: the chosen candidate's name (or position) for
#'     `"select"`, that or `"tie"` for `"pairwise"`, the grade for `"grade"`;
#'     `NA` unless `outcome` is `"answered"`.}
#'   \item{`outcome`}{`"answered"`, `"unresolved"` or `"failed"`.}
#'   \item{`verdicts`}{A data frame with one row per order: `order`, `shown`
#'     (the candidates in the order shown, or `"reference,response"`), `label`,
#'     `ok`, `verdict` (as the judge gave it), `value` (mapped back to a
#'     candidate), `reason` and `error`.}
#'   \item{`degradation`}{`"judge_inconsistent"` when unresolved, else `NA`.}
#'   \item{`swap_checked`}{`FALSE` when only one order was asked.}
#'   \item{`judge_cost`}{A list of `usd` (`NA` when the model has no price),
#'     `tokens_in`, `tokens_out` and `calls`, over the judge's own requests.}
#'   \item{`mode`, `model`, `candidates` (the ids), `config_hash`}{What was
#'     judged and under which configuration.}
#'   \item{`trace`}{The judge's own `gr_trace`.}
#' }
#' @references
#' Wang, P., Li, L., Chen, L., Cai, Z., Zhu, D., Lin, B., Cao, Y., Kong, L.,
#' Liu, Q., Liu, T. and Sui, Z. (2024). Large language models are not fair
#' evaluators. *Proceedings of ACL 2024*, 9440-9450.
#'
#' Zheng, L., Chiang, W.-L., Sheng, Y., Zhuang, S., Wu, Z., Zhuang, Y., Lin,
#' Z., Li, Z., Li, D., Xing, E. P., Zhang, H., Gonzalez, J. E. and Stoica, I.
#' (2023). Judging LLM-as-a-judge with MT-Bench and Chatbot Arena. *Advances
#' in Neural Information Processing Systems* 36.
#' @seealso [hr_judge_config()], [hr_judge_validate()], [hr_scorer_judge()]
#' @family judges
#' @export
#' @examples
#' # A judge that always picks the candidate naming Paris.
#' fair <- gr_mock_client(function(messages, params) {
#'   txt <- messages[[2]]$content
#'   pick <- if (grepl("Candidate A:\nParis", txt, fixed = TRUE)) "A" else "B"
#'   sprintf('{"verdict": "%s", "reason": "It names the capital."}', pick)
#' })
#' j <- hr_judge(c(first = "Paris", second = "Lyon"), fair, mode = "select",
#'               rubric = "Which candidate names the capital of France?")
#' j$value
#' j$verdicts[, c("order", "shown", "verdict", "value")]
#'
#' # A judge that always says "A" follows the position, so it is unresolved.
#' first <- gr_mock_client(function(messages, params) '{"verdict": "A", "reason": "."}')
#' hr_judge(c("Paris", "Lyon"), first, mode = "select",
#'          rubric = "Which candidate names the capital of France?")$outcome
hr_judge <- function(candidates, client, mode = c("select", "grade", "pairwise"),
                     reference = NULL, model = NULL, orders = 2, rubric, schema = NULL,
                     trace = NULL, governor = NULL, draw_index = 0L) {
  mode <- match.arg(mode)
  if (!inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client() or gr_mock_client().", class = "gr_bad_setting")
  }
  if (!is.null(trace) && !inherits(trace, "gr_trace")) {
    gr_abort("`trace` must come from gr_trace(), or be NULL.", class = "gr_bad_trace")
  }
  if (!is.null(governor) && !inherits(governor, "hr_governor")) {
    gr_abort("`governor` must come from hr_governor(), or be NULL.", class = "gr_bad_setting")
  }
  if (missing(rubric)) rubric <- NULL
  cfg <- hr_judge_config(model %||% as_chr1(client$model, ""), rubric, mode = mode,
                         orders = orders, schema = schema)
  if (is.null(governor) && !is.null(trace)) governor <- bench_governor(trace)
  jt <- gr_trace(governor = governor, meta = list(judge = cfg$hash))
  judge_run(cfg, candidates, reference, client, jt, parent = trace,
            draw_index = check_draw_index(draw_index))
}

#' One judgement under `cfg`, recorded into the judge trace `jt`.
#' @noRd
judge_run <- function(cfg, candidates, reference, client, jt, parent = NULL, draw_index = 0L) {
  cand <- judge_candidates(candidates, cfg$mode)
  k <- length(cand$text)
  if (cfg$mode == "select" && cfg$orders > k) {
    gr_abort(sprintf("`orders` (%d) cannot exceed the number of candidates (%d).",
                     cfg$orders, k), class = "gr_bad_setting")
  }
  if (!is.null(reference)) {
    if (!is.character(reference) || !length(reference) || anyNA(reference)) {
      gr_abort("`reference` must be text, or NULL.", class = "gr_bad_setting")
    }
    reference <- paste(reference, collapse = "\n")
  }
  if (cfg$mode == "grade" && (is.null(reference) || !nzchar(trimws(reference)))) {
    gr_abort("Mode \"grade\" needs a `reference` to grade the response against.",
             class = "gr_bad_setting")
  }
  letters_k <- LETTERS[seq_len(k)]
  allowed <- switch(cfg$mode, select = letters_k, pairwise = c("A", "B", "tie"),
                    grade = cfg$grades)
  schema <- cfg$schema %||% judge_schema(allowed)
  perms <- judge_orders(cfg$mode, k, cfg$orders)
  from <- length(jt$steps)
  rows <- lapply(seq_along(perms), function(o) {
    p <- perms[[o]]
    label <- sprintf("%s.%s.o%d", .hr_judge_calls, cfg$mode, o)
    msgs <- judge_messages(cfg, cand$text, p, reference, allowed)
    res <- gr_call_json(client, msgs, schema = schema, schema_name = "judge_verdict",
                        model = cfg$model, trace = jt, label = label, draw_index = draw_index)
    shown <- if (cfg$mode == "grade") {
      if (p[[1L]] == 1L) "reference,response" else "response,reference"
    } else paste(cand$ids[p], collapse = ",")
    verdict <- if (isTRUE(res$ok)) as_chr1(res$value[["verdict", exact = TRUE]], NA_character_)
               else NA_character_
    ok <- isTRUE(res$ok) && !is.na(verdict) && (is.null(allowed) || verdict %in% allowed)
    value <- NA_character_
    if (ok) {
      value <- if (cfg$mode == "grade" || verdict == "tie") verdict
               else cand$ids[p[match(verdict, letters_k)]]
    }
    error <- if (ok) NA_character_
             else if (!isTRUE(res$result$ok)) as_chr1(res$result$error, "request failed")
             else if (!isTRUE(res$ok)) as_chr1(res$problem, "reply did not parse")
             else sprintf("verdict %s is not one of %s", as_chr1(verdict, "NA"),
                          paste(allowed, collapse = ", "))
    data.frame(order = o, shown = shown, label = label, ok = ok, verdict = verdict,
               value = value,
               reason = if (isTRUE(res$ok)) as_chr1(res$value[["reason", exact = TRUE]],
                                                    NA_character_) else NA_character_,
               error = error, stringsAsFactors = FALSE)
  })
  verdicts <- do.call(rbind, rows)
  outcome <- if (!all(verdicts$ok)) "failed"
             else if (length(unique(verdicts$value)) == 1L) "answered"
             else "unresolved"
  cost <- judge_steps_cost(jt, from)
  if (inherits(parent, "gr_trace")) {
    trace_note(parent, sprintf("%s.%s", .hr_judge_calls, cfg$mode),
               list(judge_trace = jt$run_id, outcome = outcome, calls = cost$calls,
                    usd = cost$usd))
  }
  structure(list(
    value = if (outcome == "answered") verdicts$value[[1L]] else NA_character_,
    outcome = outcome, mode = cfg$mode, verdicts = verdicts,
    degradation = if (outcome == "unresolved") "judge_inconsistent" else NA_character_,
    swap_checked = cfg$orders >= 2L, judge_cost = cost, model = cfg$model,
    candidates = cand$ids, config_hash = cfg$hash, trace = jt), class = "hr_judgement")
}

#' Candidates as text with ids, checked for the mode.
#' @noRd
judge_candidates <- function(candidates, mode) {
  if (is.list(candidates)) {
    one <- vapply(candidates, function(x) is.character(x) && length(x) == 1L, logical(1))
    if (!all(one)) {
      gr_abort("Each candidate must be one string.", class = "gr_bad_setting")
    }
    nm <- names(candidates)
    candidates <- vapply(candidates, identity, character(1))
    names(candidates) <- nm
  }
  if (!is.character(candidates) || anyNA(candidates) || !all(nzchar(trimws(candidates)))) {
    gr_abort("`candidates` must be non-blank strings with no NA.", class = "gr_bad_setting")
  }
  k <- length(candidates)
  need <- switch(mode, select = k >= 2L && k <= 26L, pairwise = k == 2L, grade = k == 1L)
  if (!need) {
    gr_abort(sprintf("Mode \"%s\" takes %s, not %d.", mode,
                     switch(mode, select = "2 to 26 candidates", pairwise = "exactly 2 candidates",
                            grade = "exactly 1 candidate"), k), class = "gr_bad_setting")
  }
  nm <- names(candidates)
  ids <- if (!is.null(nm) && !anyNA(nm) && all(nzchar(nm)) && !anyDuplicated(nm)) nm
         else as.character(seq_len(k))
  list(text = unname(candidates), ids = ids)
}

#' The presentation orders: candidate positions in the order shown, or for
#' grade, c(1, 2) for reference first and c(2, 1) for response first.
#' @noRd
judge_orders <- function(mode, k, orders) {
  if (mode == "grade") return(list(c(1L, 2L), c(2L, 1L))[seq_len(orders)])
  if (orders == 2L) return(list(seq_len(k), rev(seq_len(k))))
  lapply(seq_len(orders) - 1L, function(s) c(seq_len(k)[seq_len(k) > s], seq_len(s)))
}

#' The default reply schema: a verdict from `allowed` and a reason.
#' @noRd
judge_schema <- function(allowed) {
  list(type = "object",
       properties = list(verdict = list(type = "string", enum = as.list(allowed)),
                         reason = list(type = "string")),
       required = list("verdict", "reason"), additionalProperties = FALSE)
}

#' The two messages of one request.
#' @noRd
judge_messages <- function(cfg, text, perm, reference, allowed) {
  parts <- c(sprintf("Rubric:\n%s", cfg$rubric))
  if (cfg$mode == "grade") {
    blocks <- c(sprintf("Reference answer:\n%s", reference),
                sprintf("Response to grade:\n%s", text[[1L]]))
    parts <- c(parts, blocks[perm])
    if (!is.null(allowed)) {
      parts <- c(parts, sprintf("Allowed grades: %s.", paste(allowed, collapse = ", ")))
    }
  } else {
    if (!is.null(reference)) parts <- c(parts, sprintf("Reference:\n%s", reference))
    parts <- c(parts, sprintf("Candidate %s:\n%s", LETTERS[seq_along(perm)], text[perm]))
  }
  list(list(role = "system", content = cfg$prompt),
       list(role = "user", content = paste(parts, collapse = "\n\n")))
}

#' What the steps a judgement added to `jt`, after the first `from`, cost.
#' @noRd
judge_steps_cost <- function(jt, from) {
  n <- length(jt$steps)
  steps <- if (n > from) jt$steps[seq.int(from + 1L, n)] else list()
  tmp <- gr_trace()
  tmp$steps <- steps
  cost <- gr_trace_cost(tmp)
  tok <- function(f) sum(vapply(steps, function(s) as_int1(s$tokens[[f]], 0L), integer(1)))
  list(usd = if (nrow(cost)) sum(cost$usd) else 0, tokens_in = tok("input"),
       tokens_out = tok("output"), calls = length(steps))
}

#' @rdname hr_judge
#' @export
print.hr_judgement <- function(x, ...) {
  cat(sprintf("<hr_judgement> %s, %s: %s\n", x$mode, x$outcome,
              if (identical(x$outcome, "answered")) x$value else "no verdict"))
  for (i in seq_len(nrow(x$verdicts))) {
    v <- x$verdicts[i, ]
    cat(sprintf("  order %d [%s]: %s\n", v$order, v$shown,
                if (v$ok) sprintf("%s -> %s", v$verdict, v$value) else paste("failed:", v$error)))
  }
  if (!isTRUE(x$swap_checked)) cat("  one order only: no swap check\n")
  usd <- x$judge_cost$usd
  cat(sprintf("  judge cost: %d call(s), %s\n", x$judge_cost$calls,
              if (is.na(usd)) "unknown (unpriced model)" else sprintf("$%.6f", usd)))
  invisible(x)
}

#' Validate a judge against blind human labels
#'
#' Compares a judge's binary decisions with blind human labels on the same
#' items and records how far they agree, for one judge configuration.
#' [hr_scorer_judge()] scores with a judge only when such a record exists for
#' its configuration and [hr_judge_valid()] says it still holds.
#'
#' The record gives, over every item with a human label:
#' * Cohen's kappa between judge and human, with a percentile bootstrap
#'   interval, and the full [hr_agreement()] set beside it (kappa is never
#'   read alone);
#' * sensitivity (the share of human positives the judge called positive) and
#'   specificity, with Wilson intervals, and the half-width of the
#'   sensitivity interval;
#' * the swap-inconsistency rate: the share of judged items whose verdict
#'   changed with the presentation order, with a Wilson interval (`NA` for a
#'   one-order judge). Swap inconsistency is the position-bias measure of
#'   Zheng et al. (2023).
#'
#' At least 50 human-positive and 50 human-negative items are required, and a
#' smaller sample is refused with an error of class `hr_judge_too_few_labels`.
#' A bare total is not enough: at 10% prevalence 100 labels hold 10
#' positives, and the sensitivity interval is then about plus or minus 0.3.
#' The minimums cannot be set below 50.
#'
#' Items the judge left unresolved or failed on (`judge` is `NA`) are scored
#' as the judge not calling them positive, which is how [hr_scorer_judge()]
#' counts them: an unresolved verdict is a wrong run there. Kappa,
#' sensitivity and specificity therefore describe the judge as the scorer
#' uses it, and items the judge cannot settle lower them rather than drop
#' out. The rates' denominators are the class sizes the minimums are checked
#' against. These items also count in the swap-inconsistency rate and are
#' reported in `n_unresolved`.
#'
#' The record is keyed by the configuration's hash. `hr_judge_valid()` is
#' `FALSE`, with the reason in `attr(, "reason")`, when the configuration
#' differs in any keyed part (model, mode, rubric, the package's prompt,
#' schema, orders, aggregation, positive grade), or when the record was
#' changed after it was made.
#'
#' Whether the agreement is good enough for a given use is a decision to
#' register before labelling, for example lower bounds on kappa, sensitivity
#' and specificity and a swap-inconsistency rate of at most 10%. This
#' function measures; it does not admit.
#'
#' @param judge_config An [hr_judge_config()].
#' @param labels A data frame with one row per item and the columns
#' \describe{
#'   \item{`judge`}{The judge's decision: `positive` or another value, `NA`
#'     when it was unresolved or failed.}
#'   \item{`human`}{The blind human label on the same scale; rows with `NA`
#'     are left out.}
#'   \item{`consistent`}{Optional. `FALSE` where the judge's verdict changed
#'     with the order.}
#'   \item{`outcome`}{Optional, used when `consistent` is absent: the
#'     judgement's outcome; `"unresolved"` marks an inconsistent item and
#'     `"failed"` an item with no swap check. With neither column, every `NA`
#'     in `judge` is taken as inconsistent.}
#'   \item{`config_hash`}{Optional. When given, every row must carry the
#'     configuration's hash: labels on another configuration's outputs are
#'     refused.}
#' }
#' @param n_pos_min,n_neg_min The fewest human-positive and human-negative
#'   items accepted; 50 or more.
#' @param positive The value of `judge` and `human` that counts as positive.
#'   `NULL` (the default) takes the configuration's positive grade (such as
#'   `"pass"`) when the configuration is in mode `"grade"` and the `judge` or
#'   `human` column holds text, and `TRUE` otherwise.
#' @param B Bootstrap resamples for the kappa interval.
#' @param conf Confidence level of every interval.
#' @param seed Seed for the bootstrap.
#' @param validation An `hr_judge_validation`.
#' @param x An `hr_judge_validation`.
#' @param ... Ignored.
#' @return `hr_judge_validate()` returns an object of class
#'   `hr_judge_validation`: a list of `config_hash`, `config` (the keyed
#'   parts), `n` (items with a human label), `n_pos`, `n_neg`, `n_unresolved`,
#'   `n_dropped` (rows without a human label), `kappa`, `sensitivity` and
#'   `specificity` (one-row data frames: `estimate`, `lower`, `upper`, and
#'   `n` for the rates), `sens_halfwidth`, `swap_inconsistency` (`x`, `n`,
#'   `estimate`, `lower`, `upper`), `agreement` (the [hr_agreement()]
#'   object), `conf`, `validated_at` (UTC) and `hash`. `hr_judge_valid()`
#'   returns `TRUE` or `FALSE`.
#' @references
#' Cohen, J. (1960). A coefficient of agreement for nominal scales.
#' *Educational and Psychological Measurement* 20(1), 37-46.
#'
#' Wilson, E. B. (1927). Probable inference, the law of succession, and
#' statistical inference. *Journal of the American Statistical Association*
#' 22(158), 209-212.
#'
#' Zheng, L. et al. (2023). Judging LLM-as-a-judge with MT-Bench and Chatbot
#' Arena. *Advances in Neural Information Processing Systems* 36.
#' @seealso [hr_judge()], [hr_scorer_judge()], [hr_judge_ppi()]
#' @family judges
#' @export
#' @examples
#' cfg <- hr_judge_config("mock-model", "Does the response give the reference's answer?",
#'                        mode = "grade")
#' set.seed(3)
#' human <- rep(c(TRUE, FALSE), c(60, 60))
#' judge <- ifelse(runif(120) < 0.9, human, !human)
#' judge[c(5, 70)] <- NA   # two items unresolved
#' v <- hr_judge_validate(cfg, data.frame(judge = judge, human = human), B = 200)
#' v
#' hr_judge_valid(v, cfg)
#' # A new rubric voids the record.
#' cfg2 <- hr_judge_config("mock-model", "Is the response right?", mode = "grade")
#' hr_judge_valid(v, cfg2)
hr_judge_validate <- function(judge_config, labels, n_pos_min = 50, n_neg_min = 50,
                              positive = NULL, B = 2000, conf = 0.95, seed = 1) {
  check_judge_config(judge_config)
  check_conf(conf)
  check_boot(B, seed)
  for (nm in c("n_pos_min", "n_neg_min")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v != round(v) || v < 50) {
      gr_abort(sprintf(paste0("`%s` must be a whole number of at least 50: fewer items per ",
                              "class leave the sensitivity and specificity intervals too ",
                              "wide to validate a judge."), nm), class = "gr_bad_setting")
    }
  }
  if (!is.data.frame(labels) || !all(c("judge", "human") %in% names(labels))) {
    gr_abort("`labels` must be a data frame with columns `judge` and `human`.",
             class = "gr_bad_setting")
  }
  if (is.null(positive)) {
    # Labels copied from grade-mode judgements carry the grade text, so the
    # configuration's positive grade is the natural default there.
    texty <- function(v) is.character(v) || is.factor(v)
    positive <- if (identical(judge_config$mode, "grade") && !is.null(judge_config$positive) &&
                    (texty(labels$judge) || texty(labels$human))) judge_config$positive
                else TRUE
  }
  if (length(positive) != 1L || is.na(positive)) {
    gr_abort("`positive` must be one value.", class = "gr_bad_setting")
  }
  if (!is.null(labels$config_hash)) {
    h <- as.character(labels$config_hash)
    if (anyNA(h) || any(h != judge_config$hash)) {
      gr_abort(paste0("Some rows of `labels` were judged under another configuration (their ",
                      "`config_hash` differs). A validation holds for one configuration only."),
               class = "hr_judge_config_mismatch")
    }
  }
  human <- labels$human
  keep <- !is.na(human)
  n_dropped <- sum(!keep)
  pos_h <- as.character(human[keep]) == as.character(positive)
  judge <- labels$judge[keep]
  resolved <- !is.na(judge)
  # An unresolved or failed verdict is not a positive call, as in the scorer.
  pos_j <- resolved & as.character(judge) == as.character(positive)
  n_pos <- sum(pos_h); n_neg <- sum(!pos_h)
  if (n_pos == 0L && length(pos_h)) {
    seen <- unique(as.character(human[keep]))
    gr_abort(sprintf(paste0("No `human` label equals `positive` (%s); the labels hold %s. ",
                            "Set `positive` to the value that marks a positive item."),
                     encodeString(as.character(positive), quote = "\""),
                     paste(encodeString(utils::head(seen, 5), quote = "\""), collapse = ", ")),
             class = "gr_bad_setting")
  }
  if (n_pos < n_pos_min || n_neg < n_neg_min) {
    gr_abort(sprintf(paste0("A judge is validated on at least %d human-positive and %d ",
                            "human-negative items; `labels` has %d and %d. Label more items ",
                            "of the smaller class."), n_pos_min, n_neg_min, n_pos, n_neg),
             class = "hr_judge_too_few_labels")
  }
  if (sum(resolved) < 2L) {
    gr_abort("The judge resolved fewer than two of the labelled items.",
             class = "hr_judge_too_few_labels")
  }
  # Inconsistent items: from `consistent`, else from the outcome, else every
  # unresolved verdict. A one-order judge has no swap check at all.
  swap <- data.frame(x = NA_integer_, n = NA_integer_, estimate = NA_real_, lower = NA_real_,
                     upper = NA_real_)
  if (judge_config$orders >= 2L) {
    if (!is.null(labels$consistent)) {
      cons <- as.logical(labels$consistent[keep])
      checked <- !is.na(cons)
      bad <- !cons[checked]
    } else if (!is.null(labels$outcome)) {
      oc <- as.character(labels$outcome[keep])
      checked <- oc %in% c("answered", "unresolved")
      bad <- oc[checked] == "unresolved"
    } else {
      bad <- !resolved
    }
    if (length(bad)) {
      w <- hr_prop_ci(sum(bad), length(bad), conf = conf)
      swap <- data.frame(x = as.integer(sum(bad)), n = as.integer(length(bad)),
                         estimate = w$est, lower = w$lower, upper = w$upper)
    }
  }
  lv <- c("positive", "negative")
  as_class <- function(p) factor(ifelse(p, "positive", "negative"), levels = lv)
  ag <- hr_agreement(as_class(pos_j), as_class(pos_h),
                     positive = "positive", B = B, conf = conf, seed = seed)
  pick <- function(stat, n) {
    r <- ag$stats[ag$stats$statistic == stat, ]
    out <- data.frame(estimate = r$estimate, lower = r$lower, upper = r$upper)
    if (!missing(n)) out$n <- as.integer(n)
    out
  }
  sens <- pick("sensitivity", n_pos)
  rec <- list(
    config_hash = judge_config$hash,
    config = unclass(judge_config)[.hr_judge_key_parts],
    n = as.integer(sum(keep)), n_pos = as.integer(n_pos), n_neg = as.integer(n_neg),
    n_unresolved = as.integer(sum(!resolved)), n_dropped = as.integer(n_dropped),
    kappa = pick("kappa"), sensitivity = sens,
    specificity = pick("specificity", n_neg),
    sens_halfwidth = (sens$upper - sens$lower) / 2,
    swap_inconsistency = swap, agreement = ag, conf = conf,
    validated_at = utc_stamp(Sys.time()))
  rec$hash <- validation_hash(rec)
  structure(rec, class = "hr_judge_validation")
}

#' The content hash of a validation record: everything but the hash and the
#' agreement object, whose figures the record repeats.
#' @noRd
validation_hash <- function(rec) {
  x <- unclass(rec)[c("config_hash", "config", "n", "n_pos", "n_neg", "n_unresolved",
                      "n_dropped", "kappa", "sensitivity", "specificity", "sens_halfwidth",
                      "swap_inconsistency", "conf", "validated_at")]
  x <- lapply(x, function(v) if (is.data.frame(v)) as.list(v) else v)
  hr_hash(x)
}

#' @rdname hr_judge_validate
#' @export
hr_judge_valid <- function(validation, judge_config) {
  no <- function(why) structure(FALSE, reason = why)
  if (!inherits(validation, "hr_judge_validation") || is.null(validation$hash)) {
    return(no("no validation record from hr_judge_validate()"))
  }
  if (!identical(validation_hash(validation), validation$hash)) {
    return(no("the validation record was changed after it was made"))
  }
  if (!inherits(judge_config, "hr_judge_config") ||
      !identical(judge_config_hash(judge_config), judge_config$hash)) {
    return(no("`judge_config` is not an unchanged hr_judge_config()"))
  }
  if (!identical(validation$config_hash, judge_config$hash)) {
    now <- unclass(judge_config)[.hr_judge_key_parts]
    then <- validation$config
    diff <- .hr_judge_key_parts[!vapply(.hr_judge_key_parts, function(p) {
      identical(hr_hash(now[p]), hr_hash(then[p]))
    }, logical(1))]
    return(no(sprintf("the judge configuration changed since validation (%s)",
                      if (length(diff)) paste(diff, collapse = ", ") else "hash")))
  }
  TRUE
}

#' @rdname hr_judge_validate
#' @export
print.hr_judge_validation <- function(x, ...) {
  f <- function(r) sprintf("%.3f [%.3f, %.3f]", r$estimate, r$lower, r$upper)
  cat(sprintf("<hr_judge_validation> config %s (%s, %s)\n", substr(x$config_hash, 1, 12),
              x$config$mode, x$config$model))
  cat(sprintf("  items: %d labelled (%d positive, %d negative), %d unresolved, %d dropped\n",
              x$n, x$n_pos, x$n_neg, x$n_unresolved, x$n_dropped))
  cat(sprintf("  kappa:       %s\n", f(x$kappa)))
  cat(sprintf("  sensitivity: %s, n = %d, half-width %.3f\n", f(x$sensitivity),
              x$sensitivity$n, x$sens_halfwidth))
  cat(sprintf("  specificity: %s, n = %d\n", f(x$specificity), x$specificity$n))
  if (is.na(x$swap_inconsistency$n)) {
    cat("  swap inconsistency: not measured (one order)\n")
  } else {
    cat(sprintf("  swap inconsistency: %s, %d of %d\n", f(x$swap_inconsistency),
                x$swap_inconsistency$x, x$swap_inconsistency$n))
  }
  if (isTRUE(x$agreement$paradox_flag)) {
    cat("  note: prevalence or bias is extreme; read kappa with the table (see $agreement)\n")
  }
  invisible(x)
}

#' Score benchmark runs with a validated judge
#'
#' An [hr_scorer()] that grades each run's output against the item's label
#' with a grade-mode judge. It is built only for a configuration that has a
#' validation record [hr_judge_valid()] accepts; without one it refuses with
#' an error of class `hr_judge_unvalidated`, since an unvalidated judge's
#' decisions are not evidence of accuracy.
#'
#' Each output is graded in the configuration's orders with the label as the
#' reference (several accepted answers are listed). A run is right when the
#' judgement is answered with the configuration's positive grade. A run the
#' judge left unresolved is wrong with outcome `"judge_unresolved"`, and one
#' it failed on is an `"error"` with outcome `"judge_failed"`: counting them
#' wrong keeps the arm's accuracy from rising on the items the judge could
#' not settle. Outputs that report their own failure, or have no text, are
#' sorted as [hr_scorer_exact()] sorts them, with no judge call.
#'
#' The judge's requests are recorded in the scorer's own trace (`$trace`),
#' held to `governor`, and never in the runs' traces, so a benchmark's cost
#' columns leave judging out. Accuracy estimated by a judge should be
#' reported corrected against human labels, with [hr_judge_ppi()].
#'
#' @param judge_config A grade-mode [hr_judge_config()].
#' @param validation Its [hr_judge_validate()] record.
#' @param client The `gr_client` the judge calls.
#' @param governor Optional [hr_governor()] for the judge's requests.
#' @param draw_index Draw index passed to every judge request (see
#'   [gr_call()]). With a caching client and a fixed index, identical outputs
#'   graded against the same label reuse one cached verdict; give another
#'   index for a fresh judge draw.
#' @return An `hr_scorer` with two more elements: `trace`, the judge's
#'   `gr_trace`, and `config_hash`.
#' @seealso [hr_judge_validate()], [hr_benchmark()], [hr_judge_ppi()]
#' @family judges
#' @export
#' @examples
#' cfg <- hr_judge_config("mock-model", "Does the response give the reference's answer?",
#'                        mode = "grade")
#' try(hr_scorer_judge(cfg, NULL, gr_mock_client()))
#'
#' set.seed(3)
#' human <- rep(c(TRUE, FALSE), c(60, 60))
#' v <- hr_judge_validate(cfg, data.frame(judge = ifelse(runif(120) < 0.9, human, !human),
#'                                        human = human), B = 200)
#' grader <- gr_mock_client(function(messages, params) {
#'   txt <- messages[[2]]$content
#'   ok <- grepl("Response to grade:\nParis", txt, fixed = TRUE)
#'   sprintf('{"verdict": "%s", "reason": "."}', if (ok) "pass" else "fail")
#' })
#' sc <- hr_scorer_judge(cfg, v, grader)
#' sc$fn("Capital of France?", "Paris", "Paris")$correct
#' sc$fn("Capital of France?", "Lyon", "Paris")$correct
hr_scorer_judge <- function(judge_config, validation, client, governor = NULL,
                            draw_index = 0L) {
  check_judge_config(judge_config)
  draw_index <- check_draw_index(draw_index)
  if (missing(validation)) validation <- NULL
  ok <- hr_judge_valid(validation, judge_config)
  if (!isTRUE(ok)) {
    gr_abort(sprintf(paste0("This judge has no valid validation record: %s. Validate the ",
                            "configuration against blind human labels with ",
                            "hr_judge_validate() first."), attr(ok, "reason")),
             class = "hr_judge_unvalidated")
  }
  if (!identical(judge_config$mode, "grade")) {
    gr_abort("hr_scorer_judge() needs a judge in mode \"grade\".", class = "gr_bad_setting")
  }
  if (!inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client() or gr_mock_client().", class = "gr_bad_setting")
  }
  if (!is.null(governor) && !inherits(governor, "hr_governor")) {
    gr_abort("`governor` must come from hr_governor(), or be NULL.", class = "gr_bad_setting")
  }
  cfg <- judge_config
  jt <- gr_trace(governor = governor, meta = list(judge = cfg$hash, scorer = TRUE))
  fn <- function(item, output, label) {
    given <- output_failure(output)
    if (!is.na(given)) return(list(correct = FALSE, outcome = NA_character_,
                                   failure_kind = given))
    text <- output_text(output)
    if (is.na(text) || !nzchar(trimws(text))) {
      return(list(correct = FALSE, outcome = NA_character_, failure_kind = "parse_failure"))
    }
    accepted <- unlist(label, use.names = FALSE)
    accepted <- as.character(accepted[!is.na(accepted)])
    if (!length(accepted)) return(list(correct = NA, outcome = NA_character_,
                                       failure_kind = NA_character_))
    ref <- if (length(accepted) == 1L) accepted
           else paste(c("Any of these is right:", paste("-", accepted)), collapse = "\n")
    j <- judge_run(cfg, text, ref, client, jt, draw_index = draw_index)
    switch(j$outcome,
      answered = list(correct = identical(j$value, cfg$positive), outcome = j$value,
                      failure_kind = if (identical(j$value, cfg$positive)) NA_character_
                                     else "wrong"),
      unresolved = list(correct = FALSE, outcome = "judge_unresolved", failure_kind = "wrong"),
      list(correct = FALSE, outcome = "judge_failed", failure_kind = "error"))
  }
  sc <- hr_scorer(fn, name = sprintf("judge_%s", substr(cfg$hash, 1, 12)))
  sc$trace <- jt
  sc$config_hash <- cfg$hash
  sc
}

#' Judge-scored accuracy corrected with human labels
#'
#' A judge's accuracy figures are biased by its own errors. Given the judge's
#' score on every item and human labels on a sample of them, this returns the
#' prediction-powered estimate of the human-scored mean (Angelopoulos et al.
#' 2023), through [hr_ppi()]:
#'
#'     estimate = mean(judge on unlabelled) + mean(human - judge on labelled)
#'
#' with PPI++ tuning by default. When `inclusion_prob` varies, the labelled
#' items were drawn with unequal probabilities and the correction is
#' inverse-probability weighted, the design-based supervised learning form
#' (Egami et al. 2023):
#'
#'     estimate = mean over all items of
#'                lambda * judge_i + R_i * (human_i - lambda * judge_i) / pi_i
#'
#' with R_i = 1 for labelled items. Equal probabilities give the plain form.
#'
#' The interval is a normal approximation and needs enough labelled items in
#' every inclusion stratum. Small inclusion probabilities with few labels
#' give intervals that are too narrow: with about 150 labels drawn at 0.05
#' and 0.4, a nominal 95% interval covered the true mean about 91% of the
#' time in simulation.
#'
#' @param judge_scores The judge's score for every item, numeric or logical
#'   (1 or `TRUE` for right), no `NA`.
#' @param human_labels The human score on the same scale, the same length,
#'   `NA` on the items no person labelled.
#' @param inclusion_prob `NULL`, or the probability with which each item was
#'   chosen for human labelling: one per item, or one per labelled item.
#' @param conf Confidence level.
#' @param tune Whether to tune lambda (PPI++); see [hr_ppi()].
#' @return The one-row data frame of [hr_ppi()], with `judge_mean`, the
#'   uncorrected mean of `judge_scores`, added.
#' @references
#' Angelopoulos, A. N., Bates, S., Fannjiang, C., Jordan, M. I. and Zrnic, T.
#' (2023). Prediction-powered inference. *Science* 382(6671), 669-674.
#'
#' Egami, N., Hinck, M., Stewart, B. M. and Wei, H. (2023). Using imperfect
#' surrogates for downstream inference: design-based supervised learning for
#' social science applications of large language models. *Advances in Neural
#' Information Processing Systems* 36.
#' @seealso [hr_ppi()], [hr_judge_validate()]
#' @family judges
#' @export
#' @examples
#' set.seed(7)
#' truth <- rbinom(1000, 1, 0.6)
#' # A lenient judge: it passes 30% of wrong answers.
#' judge <- ifelse(truth == 1, rbinom(1000, 1, 0.95), rbinom(1000, 1, 0.3))
#' human <- rep(NA, 1000)
#' lab <- sample(1000, 150)
#' human[lab] <- truth[lab]
#' hr_judge_ppi(judge, human)
hr_judge_ppi <- function(judge_scores, human_labels, inclusion_prob = NULL, conf = 0.95,
                         tune = TRUE) {
  if (is.logical(judge_scores)) judge_scores <- as.numeric(judge_scores)
  if (!is.numeric(judge_scores) || !length(judge_scores) || anyNA(judge_scores)) {
    gr_abort("`judge_scores` must be numeric (or logical) with no NA.", class = "gr_bad_setting")
  }
  N <- length(judge_scores)
  if (length(human_labels) != N) {
    gr_abort(sprintf("`human_labels` must have one entry per item (%d), with NA where unlabelled.",
                     N), class = "gr_bad_setting")
  }
  if (is.logical(human_labels)) human_labels <- as.numeric(human_labels)
  if (!is.numeric(human_labels)) {
    gr_abort("`human_labels` must be numeric (or logical).", class = "gr_bad_setting")
  }
  lab <- !is.na(human_labels)
  pi <- NULL
  if (!is.null(inclusion_prob)) {
    if (!is.numeric(inclusion_prob)) {
      gr_abort("`inclusion_prob` must be numeric.", class = "gr_bad_setting")
    }
    pi <- if (length(inclusion_prob) == N) inclusion_prob[lab]
          else if (length(inclusion_prob) == sum(lab)) inclusion_prob
          else if (length(inclusion_prob) == 1L) rep(inclusion_prob, sum(lab))
          else gr_abort(sprintf(paste0("`inclusion_prob` must have one value per item (%d) or ",
                                       "per labelled item (%d)."), N, sum(lab)),
                        class = "gr_bad_setting")
  }
  out <- hr_ppi(judge_scores[!lab], judge_scores[lab], human_labels[lab], pi = pi,
                conf = conf, tune = tune)
  out$judge_mean <- mean(judge_scores)
  out
}
