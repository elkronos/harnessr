# core-bench-run.R: run every arm on every item of a reference, several times,
# and keep one scored row per run.
#
# Two rules shape this file. Repeated runs must be repeated draws: a run
# answered from the cache entry or recorded reply that an earlier run of the
# same arm and item was answered from is a copy, and agreement or spread
# computed from copies measures nothing, so such an arm is refused. And the
# benchmark as a whole is one run under one governor: each arm run gets its
# own trace, held to the benchmark's limits less what the runs before it
# used, and folded into the benchmark's trace when it ends.

#' Run arms against a reference
#'
#' Runs every arm on every item of the chosen split(s) of `reference`, `runs`
#' times, scores each output with `scorer`, and returns one row per cluster x
#' item x arm x run. Rows are ordered that way, and the runs are made in the
#' same order.
#'
#' Run `r` of each arm on each item is given `ctx$draw_index = r` (see
#' [hr_arm()]), so with the index passed to [gr_call()] each run is its own
#' entry in a [gr_cache()] and its own recorded draw in a
#' [gr_replay_client()]. An arm whose runs are not distinct draws is refused
#' with an error of class `hr_duplicate_draw`: a run of an arm on an item is
#' a duplicate when one of its requests was answered from a cache or a
#' recording with the same request and draw index as a request of an earlier
#' run, when one of its replies has the provider response id of a reply in an
#' earlier run, or when a recording served a reply without its own draw key
#' (a repeat after the recording ran out of draws, or a recording made
#' without per-draw keys). Every request a run makes should therefore carry
#' the run's draw index. A [gr_mock_client()] keeps no cache, so under it an arm that
#' leaves the index out is not refused; under a cache it would be.
#'
#' Every request is checked against `governor` before it is sent, for the
#' benchmark as a whole: each run's trace is held to the governor's call,
#' spending and token limits less what the runs before it used. A run ends
#' at its first refused request (the `hr_budget_refused` condition is caught
#' there), is recorded as `failure_kind = "budget_stop"` and counted wrong
#' (or `NA` on an item with no label, as below).
#' The runs after it are still started, so every row exists and the refusals
#' are visible; their requests are refused before anything is sent. With `governor = NULL` the limits are
#' read from [gr_options()] when the benchmark starts and apply to the whole
#' benchmark, as they apply to one run of a reader.
#'
#' An arm that raises an error has that run recorded as `"error"`, counted
#' wrong, with the message in the run's trace. Every run on an item with no
#' label has `correct = NA`, whatever its `failure_kind`: a failure on it
#' cannot count against an arm when a success could not count for it. Rows
#' on the `"dev"` split are
#' marked `reportable = FALSE`: dev is for tuning, and its scores are not
#' evidence. The reference is locked when scoring starts (see
#' [hr_reference()]).
#'
#' Fewer than 5 runs warns (class `hr_few_runs`): with fewer, run-to-run
#' spread cannot be told from the differences between arms, and interval
#' reports are expected to refuse such a benchmark unless it is labelled
#' descriptive.
#'
#' The arms run under a private random stream started from `seed`, so an arm
#' that samples gives the same draws on every call with the same seed, and the
#' caller's random state is left as it was.
#'
#' @param arms An [hr_arm()] or a list of them, with unique names.
#' @param reference An [hr_reference()].
#' @param runs How many times each arm runs on each item: a whole number, at
#'   least 1. 5 or more is the expected minimum.
#' @param client The client passed to the arms in `ctx$client`, or `NULL`
#'   for arms that call no model.
#' @param scorer An [hr_scorer()]; [hr_scorer_exact()] by default.
#' @param split The split or splits of the reference to run on.
#' @param governor An [hr_governor()] the whole benchmark is held to, or
#'   `NULL` to take the limits from [gr_options()].
#' @param seed The seed of the arms' private random stream.
#' @param x An `hr_bench`.
#' @param ... Ignored.
#' @return An object of class `hr_bench`, a data frame with one row per
#'   cluster x item x arm x run and the columns
#' \describe{
#'   \item{`cluster`, `item`, `arm`, `run`, `split`}{Which run of which arm
#'     on which item.}
#'   \item{`correct`}{`TRUE` or `FALSE`, or `NA` on every run of an item
#'     with no label (its `failure_kind` is still recorded).}
#'   \item{`outcome`}{What the scorer saw (see [hr_scorer()]).}
#'   \item{`failure_kind`}{Why a wrong run was wrong: `"parse_failure"`,
#'     `"refusal"`, `"not_in_document"`, `"wrong"`, `"budget_stop"` or
#'     `"error"`; `NA` when it was correct.}
#'   \item{`tokens_in`, `tokens_out`, `tokens_reasoning`, `tokens_cached`}{The
#'     run's prompt and reply tokens over its model calls, and the reasoning
#'     and cached input tokens among them that the provider reported.}
#'   \item{`usd`}{What the run cost, every request priced at its own model,
#'     embeddings included, as [gr_trace_cost()] prices it: 0 for requests a
#'     cache or a recording answered, `NA` when a model has no price.}
#'   \item{`usd_provenance`}{Where the token counts the cost rests on came
#'     from, over the requests that were paid for: `"reported"` when the
#'     provider reported them all, else `"counted"` when they were counted with
#'     the model's own tokenizer, else `"estimated"`; `"none"` when the run
#'     paid for no request, and `NA` when a request does not say.}
#'   \item{`seconds`}{The run's wall-clock time.}
#'   \item{`draw_index`}{The draw index the run was given: its run number.}
#'   \item{`ledger_id`}{The `run_id` of the run's own trace, which is kept in
#'     `attr(x, "traces")` under that name, and which every step the run
#'     added to the benchmark's trace, `attr(x, "trace")`, carries as
#'     `ledger_id`.}
#'   \item{`reportable`}{`FALSE` for rows on the dev split.}
#' }
#' Attributes record the arms (`arms`: name, version, hash, derived_from),
#' the reference hash, `runs`, `split`, `seed`, the scorer's name, and the
#' traces. `print()` shows each arm's accuracy over the reportable rows, the
#' mean over runs within each item and then over items, leaving out items
#' with no label; the dev split's accuracy, when there is one, is shown apart
#' in its own column. It adds failures and cost, and is descriptive only: no
#' interval.
#' @seealso [hr_arm()], [hr_reference()], [hr_scorer()], [hr_governor()]
#' @family harness
#' @export
#' @examples
#' ref <- hr_reference(
#'   items = list(q1 = "France", q2 = "Peru", q3 = "Chad", q4 = "Fiji"),
#'   labels = c("Paris", "Lima", "N'Djamena", "Suva"),
#'   cluster = c("a", "a", "b", "b"), split = "test")
#' capitals <- c(France = "Paris", Peru = "Lima", Chad = "Ndjamena", Fiji = "Suva")
#' cl <- gr_mock_client(function(messages, params) {
#'   country <- sub("Capital of ", "", messages[[1]]$content)
#'   capitals[[country]]
#' })
#' ask <- hr_arm("ask", function(item, ctx) ctx$call(paste0("Capital of ", item))$text)
#' bench <- hr_benchmark(ask, ref, runs = 5, client = cl)
#' bench
#' head(bench[, c("item", "run", "correct", "failure_kind", "draw_index")])
hr_benchmark <- function(arms, reference, runs = 5, client, scorer = hr_scorer_exact(),
                         split = "test", governor = NULL, seed = 1) {
  arms <- check_arms(arms)
  check_reference(reference)
  if (!is.numeric(runs) || length(runs) != 1L || is.na(runs) || !is.finite(runs) ||
      runs < 1 || runs != round(runs)) {
    gr_abort("`runs` must be one whole number, at least 1.", class = "gr_bad_setting")
  }
  runs <- as.integer(runs)
  if (missing(client)) client <- NULL
  if (!is.null(client) && !inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client(), gr_mock_client() or the like, or be NULL.",
             class = "gr_bad_setting")
  }
  if (!inherits(scorer, "hr_scorer")) {
    gr_abort("`scorer` must come from hr_scorer() or hr_scorer_exact().",
             class = "hr_bad_scorer")
  }
  if (!is.character(split) || !length(split) || anyNA(split) || !all(split %in% .hr_splits)) {
    gr_abort(sprintf("`split` must name one or more of %s.", paste(.hr_splits, collapse = ", ")),
             class = "gr_bad_setting")
  }
  split <- unique(split)
  if (is.null(governor)) governor <- hr_governor()
  if (!inherits(governor, "hr_governor")) {
    gr_abort("`governor` must come from hr_governor(), or be NULL.", class = "gr_bad_setting")
  }
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed)) {
    gr_abort("`seed` must be one number.", class = "gr_bad_setting")
  }
  sel <- which(reference$split %in% split)
  if (!length(sel)) {
    gr_abort(sprintf("The reference has no items in split %s.", paste(split, collapse = ", ")),
             class = "hr_bad_reference")
  }
  if (runs < 5L) {
    gr_warn(sprintf(paste0(
      "runs = %d is below 5: run-to-run spread cannot be separated from differences between ",
      "arms, and interval reports will refuse this benchmark unless it is labelled ",
      "descriptive."), runs), class = "hr_few_runs")
  }
  # Clusters in the order they first appear, items in reference order within.
  clusters <- unique(reference$cluster[sel])
  sel <- sel[order(match(reference$cluster[sel], clusters), sel)]

  parent <- gr_trace(governor = governor, meta = list(
    benchmark = list(reference = reference$hash, arms = names(arms), runs = runs,
                     split = split, scorer = scorer$name, seed = seed)))
  reference_lock(reference, parent$run_id)

  n <- length(sel) * length(arms) * runs
  col <- list(cluster = character(n), item = character(n), arm = character(n),
              run = integer(n), split = character(n), correct = logical(n),
              outcome = character(n), failure_kind = character(n),
              tokens_in = integer(n), tokens_out = integer(n), tokens_reasoning = integer(n),
              tokens_cached = integer(n), usd = numeric(n), usd_provenance = character(n),
              seconds = numeric(n), draw_index = integer(n), ledger_id = character(n))
  traces <- vector("list", n)
  k <- 0L
  with_private_rng(seed, {
    for (i in sel) {
      id <- reference$ids[[i]]
      labelled <- has_label(reference$labels[[i]])
      for (arm in arms) {
        seen <- list()
        for (r in seq_len(runs)) {
          k <- k + 1L
          child <- gr_trace(run_id = sprintf("%s:%d", parent$run_id, k),
                            meta = list(recipe = arm$name, item = id,
                                        cluster = reference$cluster[[i]], run = r),
                            governor = bench_governor(parent))
          ctx <- bench_ctx(client, child, r, id, arm)
          started <- proc.time()[["elapsed"]]
          # A refusal ends the run: it is a budget stop whatever the arm
          # would do next, and catching the signal spares the arm's later
          # requests, which would only be refused in turn.
          out <- tryCatch(list(value = arm$run(reference$items[[i]], ctx)),
                          hr_budget_refused = function(e) list(error = e),
                          error = function(e) list(error = e))
          secs <- proc.time()[["elapsed"]] - started
          where <- sprintf("item '%s', arm '%s', run %d", id, arm$name, r)
          scored <- if (length(child$refusals) || inherits(out$error, "hr_budget_refused")) {
            list(correct = FALSE, outcome = NA_character_, failure_kind = "budget_stop")
          } else if (!is.null(out$error)) {
            trace_note(child, "bench.error", list(message = conditionMessage(out$error)))
            list(correct = FALSE, outcome = NA_character_, failure_kind = "error")
          } else {
            score_output(scorer, reference$items[[i]], out$value, reference$labels[[i]], where,
                         labelled = labelled)
          }
          # With no label a run can be neither right nor wrong. Scoring its
          # failures FALSE would let an unlabelled item count only against
          # an arm, so they are NA too; the failure_kind stays for the audit.
          if (!labelled) scored$correct <- NA
          bench_fold(parent, child)
          sig <- draw_signature(child)
          dup <- draw_duplicate(sig, seen, runs)
          if (!is.na(dup)) {
            gr_abort(sprintf(paste0(
              "Arm '%s' did not make distinct draws: on %s, %s. Repeated runs answered from one ",
              "stored reply are copies, not draws. Pass ctx$draw_index to every request the arm ",
              "makes (ctx$call() does), and record enough draws for a replay."),
              arm$name, where, dup), class = "hr_duplicate_draw")
          }
          seen[[length(seen) + 1L]] <- sig
          cost <- gr_trace_cost(child)
          col$cluster[k] <- reference$cluster[[i]]
          col$item[k] <- id
          col$arm[k] <- arm$name
          col$run[k] <- r
          col$split[k] <- reference$split[[i]]
          col$correct[k] <- scored$correct
          col$outcome[k] <- scored$outcome
          col$failure_kind[k] <- scored$failure_kind
          col$tokens_in[k] <- as.integer(child$tokens_in)
          col$tokens_out[k] <- as.integer(child$tokens_out)
          col$tokens_reasoning[k] <- sum_step_tokens(child$steps, "reasoning")
          col$tokens_cached[k] <- sum_step_tokens(child$steps, "cached_input")
          col$usd[k] <- if (nrow(cost)) sum(cost$usd) else 0
          col$usd_provenance[k] <- usd_provenance(child$steps)
          col$seconds[k] <- round(secs, 3)
          col$draw_index[k] <- r
          col$ledger_id[k] <- child$run_id
          traces[[k]] <- child
        }
      }
    }
  })
  out <- as.data.frame(col, stringsAsFactors = FALSE)
  out$reportable <- out$split != "dev"
  names(traces) <- out$ledger_id
  structure(out, class = c("hr_bench", "data.frame"),
            arms = data.frame(
              arm = names(arms),
              version = vapply(arms, function(a) a$version, character(1)),
              hash = vapply(arms, function(a) a$hash, character(1)),
              derived_from = vapply(arms, function(a) as_chr1(a$derived_from, NA_character_),
                                    character(1)),
              stringsAsFactors = FALSE, row.names = NULL),
            reference_hash = reference$hash, runs = runs, split = split, seed = seed,
            scorer = scorer$name, trace = parent, traces = traces)
}

#' The governor one arm run is held to: the benchmark's, less the calls,
#' dollars and tokens the runs before it used.
#' @noRd
bench_governor <- function(parent) {
  gov <- fork_governor(parent)
  cap <- finite_limit(gov$max_calls)
  if (!is.null(cap)) gov$max_calls <- max(cap - as_num1(parent$calls, 0), 0)
  gov
}

#' The context an arm run is given. Built in its own function, so the `call`
#' shortcut keeps this run's trace and draw however long the arm holds it.
#' @noRd
bench_ctx <- function(client, trace, run, item_id, arm) {
  list(client = client, trace = trace, governor = trace$governor, draw_index = run,
       item_id = item_id, arm = arm$name, run = run, params = arm$params,
       call = function(messages, ...) {
         gr_call(client, messages, ..., trace = trace, draw_index = run)
       })
}

#' Fold one arm run's trace into the benchmark's, with each folded step
#' naming the run it came from.
#' @noRd
bench_fold <- function(parent, child) {
  from <- length(parent$steps)
  trace_absorb(parent, child)
  n <- length(parent$steps)
  if (n > from) {
    idx <- seq.int(from + 1L, n)
    parent$steps[idx] <- lapply(parent$steps[idx], function(st) {
      st$ledger_id <- child$run_id
      st
    })
  }
  invisible(NULL)
}

#' Where the token counts behind a run's cost came from: the least direct
#' source among the requests it paid for.
#' @noRd
usd_provenance <- function(steps) {
  paid <- Filter(function(s) !isTRUE(s$cached), request_steps(steps))
  if (!length(paid)) return("none")
  prov <- vapply(paid, function(s) as_chr1(s$tokens$provenance, NA_character_), character(1))
  if (anyNA(prov)) return(NA_character_)
  if (any(prov == "estimated")) return("estimated")
  if (any(prov == "counted")) return("counted")
  "reported"
}

#' What tells one run's model requests apart from another run's: for each
#' request, a hash of its model, prompt and draw index, whether a cache or a
#' recording answered it, whether it kept a replay key (a replay drops it for a
#' repeat after its replies ran out and for a reply found by the old key),
#' and the provider's response id.
#' @noRd
draw_signature <- function(trace) {
  req <- Filter(function(s) !identical(s$kind, "embedding"), request_steps(trace$steps))
  list(
    sig = vapply(req, function(s) {
      hr_hash(list(model = as_chr1(s$model, NA_character_), prompt = s$prompt,
                   draw = as_int1(s$params[["draw_index", exact = TRUE]], 0L)))
    }, character(1)),
    cached = vapply(req, function(s) isTRUE(s$cached), logical(1)),
    keyed = vapply(req, function(s) is.character(s$replay_key), logical(1)),
    response_id = vapply(req, function(s) as_chr1(s$response_id, NA_character_), character(1)))
}

#' Whether a label holds any value that is not NA.
#' @noRd
has_label <- function(label) {
  v <- unlist(label, use.names = FALSE)
  length(v) > 0L && !all(is.na(v))
}

#' Why a run is a copy of an earlier run of the same arm on the same item, or
#' NA when it is not.
#' @noRd
draw_duplicate <- function(sig, seen, runs) {
  if (runs < 2L || !length(sig$sig)) return(NA_character_)
  if (any(sig$cached & !sig$keyed)) {
    return(paste0("a recorded reply was served without its own draw key (a repeat after ",
                  "the recording ran out of draws, or a recording without per-draw keys)"))
  }
  if (!length(seen)) return(NA_character_)
  prev_sig <- unlist(lapply(seen, `[[`, "sig"), use.names = FALSE)
  if (any(sig$cached & sig$sig %in% prev_sig)) {
    return(paste0("a request was answered from the cache entry or recording of the same ",
                  "request and draw index in an earlier run"))
  }
  ids <- sig$response_id[!is.na(sig$response_id)]
  prev_ids <- unlist(lapply(seen, `[[`, "response_id"), use.names = FALSE)
  if (length(ids) && any(ids %in% prev_ids[!is.na(prev_ids)])) {
    return("a reply had the same response id as a reply in an earlier run")
  }
  NA_character_
}

#' @rdname hr_benchmark
#' @export
print.hr_bench <- function(x, ...) {
  # A subset without the scored columns is an ordinary table.
  need <- c("cluster", "item", "arm", "correct", "failure_kind", "usd", "reportable")
  if (!all(need %in% names(x))) {
    print(structure(x, class = "data.frame"), ...)
    return(invisible(x))
  }
  df <- as.data.frame(unclass(x)[c("item", "arm", "correct", "failure_kind", "usd",
                                   "reportable")], stringsAsFactors = FALSE)
  runs <- attr(x, "runs") %||% length(unique(x$run))
  cat(sprintf("<hr_bench> %d arm(s) x %d item(s) in %d cluster(s) x %s run(s)",
              length(unique(df$arm)), length(unique(x$item)), length(unique(x$cluster)),
              format(runs)))
  if (!is.null(attr(x, "split"))) cat(sprintf("; split %s", paste(attr(x, "split"),
                                                                  collapse = ", ")))
  if (!is.null(attr(x, "scorer"))) cat(sprintf("; scorer %s", attr(x, "scorer")))
  cat("\n")
  if (!nrow(df)) return(invisible(x))
  arms <- unique(df$arm)
  # Mean over runs within each item, then over items; an item whose runs
  # are all NA (it has no label) is left out rather than counted.
  accuracy <- function(d) {
    if (!nrow(d)) return("-")
    per_item <- tapply(d$correct, d$item, function(v) if (all(is.na(v))) NA_real_
                                                    else mean(v, na.rm = TRUE))
    if (all(is.na(per_item))) "-" else sprintf("%.3f", mean(per_item, na.rm = TRUE))
  }
  any_dev <- any(!df$reportable)
  tab <- do.call(rbind, lapply(arms, function(a) {
    d <- df[df$arm == a, , drop = FALSE]
    usd <- sum(d$usd)
    # Dev rows tune the arms; their accuracy is kept out of the main column.
    row <- data.frame(arm = a, accuracy = accuracy(d[d$reportable, , drop = FALSE]),
                      stringsAsFactors = FALSE)
    if (any_dev) row$dev <- accuracy(d[!d$reportable, , drop = FALSE])
    cbind(row, data.frame(
               runs = nrow(d),
               wrong = sum(d$failure_kind %in% "wrong"),
               failed = sum(!is.na(d$failure_kind) &
                              !d$failure_kind %in% c("wrong", "budget_stop")),
               budget_stop = sum(d$failure_kind %in% "budget_stop"),
               usd = if (is.na(usd)) "unknown" else sprintf("%.4f", usd),
               stringsAsFactors = FALSE))
  }))
  print(tab, row.names = FALSE, right = FALSE)
  dev <- sum(!df$reportable)
  if (dev) {
    cat(sprintf(paste0("  %d row(s) on the dev split are not reportable; their accuracy is ",
                       "the dev column alone.\n"), dev))
  }
  cat(paste0("  Descriptive only: accuracy is the mean over runs within each item, then over ",
             "labelled items, with no interval.\n"))
  invisible(x)
}
