# doc-read-merge.R: partial answers merged in a tree.

#' Merge a set of partial findings into one answer, tree-wise so the merge
#' prompt itself can never exceed the context window.
#'
#' Besides the text, the result says how many findings were cut to fit a merge
#' (`truncated`), how many merge replies came back cut off at the output cap
#' (`truncated_calls`) and how many merge requests failed (`failed`). A reply
#' cut off part way through a level is passed up as a finding like any other,
#' so the final merge can be whole and still rest on one that was not. So is a
#' group whose merge failed, joined unmerged: `ok` says whether the LAST merge
#' worked, and `failed` counts every level, the last included.
#' @noRd
tree_merge <- function(client, question, pieces, spec, trace, label = "merge",
                       system_prompt = NULL, kind = "findings") {
  system_prompt <- system_prompt %||% .gr_prompts$merge_system
  # The same model for the budget and the request: gr_read() fills a spec's
  # model from the client, but a caller that builds its own spec may leave it
  # NULL, and gr_budget() and gr_call() fall back to different models on NULL.
  spec$model <- spec$model %||% as_chr1(client[["model", exact = TRUE]], gr_options("model"))
  pieces <- pieces[has_content(pieces)]
  if (!length(pieces)) return(list(text = .NOT_FOUND, ok = FALSE, levels = 0L,
                                   truncated_calls = 0L, failed = 0L))
  if (length(pieces) == 1L) return(list(text = pieces[[1]], ok = TRUE, levels = 0L,
                                        truncated_calls = 0L, failed = 0L))

  level <- 0L
  truncated <- 0L
  cut <- 0L
  failed <- 0L
  prev_n <- length(pieces) + 1L
  repeat {
    level <- level + 1L
    # "never": tree_merge() builds its own messages below and does not restate,
    # so the question appears once. Left at the default it would reserve room
    # for a second copy that is never sent and shrink every merge group.
    overhead <- prompt_overhead(question, system_prompt, "never")
    bud <- gr_budget(spec$model, reserve_output = spec$max_answer_tokens, overhead = overhead)

    # Each finding as the prompt carries it: in its tags, and joined to the
    # next by a blank line. Counted bare, 300 one-word findings came to 1,200
    # tokens against a 2,145-token budget and went out as one prompt of 3,501,
    # which gr_call() refused for a 3,000-token window. The numbered tags of
    # the final level, the longer of the two, size every level.
    sized <- function(p) gr_count_tokens(sprintf("<%s %d>\n%s\n</%s %d>\n\n", kind,
                                                 seq_along(p), p, kind, seq_along(p)))
    pts <- sized(pieces)

    # A single finding larger than the whole merge budget cannot be reduced by
    # grouping: it lands alone in its group, a one-element group is returned
    # unchanged, and the loop spins through every level doing nothing before
    # concatenating the lot. Truncate it once, and say so, so each level makes
    # real progress.
    over <- pts > bud$input
    if (any(over)) {
      gr_msg(sprintf("Merge: %d finding(s) exceed the %d-token merge budget; truncating them.",
                     sum(over), bud$input))
      # Cut to leave room for its tags, which the truncation does not count.
      big <- pieces[over]
      room <- pmax(1, bud$input - (pts[over] - gr_count_tokens(big)))
      pieces[over] <- vapply(seq_along(big), function(k) {
        truncate_logged(big[k], room[k], paste0(label, ".input"), trace,
                        level = level, piece = which(over)[k])$text
      }, character(1), USE.NAMES = FALSE)
      truncated <- truncated + sum(over)
      pts <- sized(pieces)
    }

    groups <- list(); sizes <- numeric(0); buf <- character(0); tks <- 0L
    for (k in seq_along(pieces)) {
      p <- pieces[k]
      pt <- pts[k]
      if (length(buf) && tks + pt > bud$input) {
        groups[[length(groups) + 1L]] <- buf; sizes <- c(sizes, tks); buf <- character(0); tks <- 0L
      }
      buf <- c(buf, p); tks <- tks + pt
    }
    if (length(buf)) { groups[[length(groups) + 1L]] <- buf; sizes <- c(sizes, tks) }

    if (length(groups) == 1L && length(groups[[1]]) == length(pieces)) {
      body <- paste(sprintf("<%s %d>\n%s\n</%s %d>", kind, seq_along(pieces), pieces,
                            kind, seq_along(pieces)), collapse = "\n\n")
      res <- gr_call(client, list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = body),
        list(role = "user", content = paste0("Question: ", question))
      ), model = spec$model, max_output = spec$max_answer_tokens, temperature = spec$temperature,
         trace = trace, label = label, effort = spec$effort)
      if (is_refused(res)) {
        # A limit stopped us before the final merge. This path used to
        # return unbounded concatenation, an "answer" the size of every
        # finding put together, while the failure path below was carefully
        # capped. Same degradation, same bound, and not counted as a failure.
        return(list(text = merge_giveup(pieces, spec, trace, label), ok = FALSE, levels = level,
                    truncated = truncated, truncated_calls = cut, failed = failed,
                    error = res$error))
      }
      if (!res$ok) {
        # Concatenation is a documented, visible degradation -- not a silent one.
        return(list(text = merge_giveup(pieces, spec, trace, label), ok = FALSE, levels = level,
                    truncated = truncated, truncated_calls = cut, failed = failed + 1L,
                    error = res$error))
      }
      return(list(text = res$text, ok = TRUE, levels = level, truncated = truncated,
                  truncated_calls = cut + reply_cut_off(res), failed = failed))
    }

    gr_msg(sprintf("Merge level %d: %d finding(s) -> %d group(s).", level, length(pieces), length(groups)))
    # The largest group sent with its reply at the cap: what gr_lapply() holds
    # a parallel level to, since the workers cannot see what the run spends. A
    # group of one is passed up without a request.
    worst <- batch_item_usd(client, spec$model,
                            overhead + max_tokens_of(sizes[lengths(groups) > 1L]),
                            spec$max_answer_tokens)
    got <- gr_lapply(groups, function(g, trace) {
      if (length(g) == 1L) return(list(text = g, cut = FALSE, failed = FALSE))
      body <- paste(sprintf("<%s>\n%s\n</%s>", kind, g, kind), collapse = "\n\n")
      res <- gr_call(client, list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = body),
        list(role = "user", content = paste0("Question: ", question))
      ), model = spec$model, max_output = spec$max_answer_tokens, temperature = spec$temperature,
         trace = trace, label = paste0(label, ".level", level), effort = spec$effort)
      if (is_refused(res)) return(list(text = merge_giveup(g, spec, trace, label), cut = FALSE, failed = FALSE))
      # A failed group goes up unmerged, which keeps its findings and says
      # nothing of the failure, so it is counted.
      if (res$ok) list(text = res$text, cut = reply_cut_off(res), failed = FALSE)
      else list(text = paste(g, collapse = "\n\n"), cut = FALSE, failed = TRUE)
    }, parallel = spec$parallel, label = "merge group", trace = trace,
       client = client, item_usd = worst)
    pieces <- vapply(got, function(x) as_chr1(x$text), character(1), USE.NAMES = FALSE)
    cut <- cut + sum(vapply(got, function(x) isTRUE(x$cut), logical(1)))
    failed <- failed + sum(vapply(got, function(x) isTRUE(x$failed), logical(1)))
    pieces <- pieces[has_content(pieces)]

    # Progress guard. If a level did not shrink the pile, another level will not
    # either -- every input to it is the same. Stop now with a bounded answer
    # rather than burning six more rounds of calls to reach the same place.
    if (!length(pieces)) return(list(text = .NOT_FOUND, ok = FALSE, levels = level,
                                     truncated = truncated, truncated_calls = cut,
                                     failed = failed))
    if (length(pieces) >= prev_n || level > 6L) {
      return(list(text = merge_giveup(pieces, spec, trace, label), ok = FALSE, levels = level,
                  truncated = truncated, truncated_calls = cut, failed = failed,
                  error = if (level > 6L) "merge depth cap reached" else "merge made no progress"))
    }
    prev_n <- length(pieces)
  }
}

#' The bounded fallback when merging fails.
#'
#' Returning `paste(pieces, collapse=)` unbounded handed the caller an "answer"
#' that could be the size of the whole document. Cap it at a generous multiple of
#' the answer budget and mark the cut. The cut is written to `trace` as
#' `<label>.giveup`, since the text returned stands in for the merged answer.
#' @noRd
merge_giveup <- function(pieces, spec, trace = NULL, label = "merge") {
  cap <- as.integer(clamp((spec$max_answer_tokens %||% 800L) * 3L, 200L, 8000L))
  truncate_logged(paste(pieces, collapse = "\n\n---\n\n"), cap, paste0(label, ".giveup"),
                  trace, marker = "\n\n...[merge failed; findings above are truncated]")$text
}
