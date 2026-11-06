# core-legacy-keys.R: the response-cache and replay keys of readgpt 0.6.0.
#
# The keys moved to harnessr-cache-v3 and harnessr-replay-v2 (SHA-256, see
# hr_hash()). Caches and recordings made before that hold entries only under
# the old keys, and nothing rewrites them: a cache does not store the prompt,
# so an old key cannot be turned into a new one. So both lookups try the new
# key first and then the old one, computed here exactly as 0.6.0 computed it:
# the same parts, gr_hash() (xxhash64) and its mapping of this package's name
# to readgpt. These functions are frozen. Anything that changes the key they
# return orphans every cache and recording made before the change.

#' The readgpt-cache-v2 key of a request, as 0.6.0 computed it.
#'
#' Only ever asked for a request with no draw index: 0.6.0 had none, so every
#' entry it wrote is the first draw.
#' @noRd
legacy_cache_key_v2 <- function(client, messages, model, max_output, temperature,
                                schema, schema_name, extra, effort = NULL) {
  gr_hash(c(
    "readgpt-cache-v2",
    as_chr1(client$api, "?"),
    as_chr1(client$base_url, "?"),
    as_chr1(client$.client_id, "<url-addressed>"),
    as_chr1(model, "?"),
    format(as.integer(max_output)),
    if (is.null(temperature)) "<null>" else format(temperature, digits = 15L),
    as_chr1(schema_name, "result"),
    if (is.null(schema)) "<no-schema>" else gr_hash(schema),
    gr_hash(client$extra_body %||% list()),
    gr_hash(extra %||% list()),
    if (!is.null(effort)) paste0("effort:", as_chr1(effort)),
    key_text(unlist(lapply(messages, function(m) c(as_chr1(m$role), as_chr1(m$content))),
                    use.names = FALSE))
  ))
}

#' The readgpt-replay-v1 key of a call, as 0.6.0 computed it.
#'
#' The prompt, the model asked for and the effort sent. Temperature, output cap
#' and schema were never in it, which is why a recording that carries only
#' this key cannot show that a replay ran under the settings it was made with.
#' `model = NULL` keys the prompt alone, for the diagnostics of a miss.
#' @noRd
legacy_replay_key_v1 <- function(messages, model, effort = NULL) {
  gr_hash(c("readgpt-replay-v1",
            if (is.null(model)) "<any-model>" else as_chr1(model, "?"),
            if (!is.null(effort)) paste0("effort:", as_chr1(effort)),
            key_text(unlist(lapply(messages, function(m) c(as_chr1(m$role), as_chr1(m$content))),
                            use.names = FALSE))))
}

#' Warn that a reply was found only under an old key, once per session for
#' each cache directory or recording.
#'
#' Once, because a run through a warm old cache would otherwise warn on every
#' call. The counts in gr_cache_stats() and a replay client's `$stats()` say
#' how many replies came that way. `what` is "cache" or "replay"; `where` is
#' the cache directory or the replay client's id.
#' @noRd
legacy_key_warn <- function(what, where) {
  seen <- hr_state$legacy_key_warned %||% character(0)
  id <- paste0(what, ":", where)
  if (id %in% seen) return(invisible(FALSE))
  hr_state$legacy_key_warned <- c(seen, id)
  msg <- if (identical(what, "cache")) {
    sprintf(paste0("A reply in the cache at %s was found under its old key (readgpt-cache-v2). ",
                   "Entries written before harnessr-cache-v3 are still read for calls with no ",
                   "draw index, and new entries are written under the new key. ",
                   "Shown once per cache this session; gr_cache_stats() counts these hits."),
            where)
  } else {
    paste0("A reply in this recording was found under its old key (readgpt-replay-v1), ",
           "which covers the prompt, model and effort only, so the replay cannot show that ",
           "the temperature, output cap and schema were the recorded ones. Re-record the ",
           "run to check them. Shown once per recording this session; the replay client's ",
           "$stats() counts these hits.")
  }
  gr_warn(msg, class = "hr_legacy_key")
  invisible(TRUE)
}
