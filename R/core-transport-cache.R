# core-transport-cache.R -- a content-addressed cache for model responses.
#
# WHY THIS FILE EXISTS
# Everything in this package is deterministic except the model call. Ingestion,
# cleaning, segmentation, ranking and merging are pure functions of their input,
# and `gr_chunk_stats()` already lets you compare chunkings for nothing. The
# model call is the only step that costs money, the only step that can fail
# halfway through a long run, and -- above a temperature of zero -- the only
# step that does not return the same thing twice.
#
# That combination is what made iterating expensive. Changing a merge prompt,
# fixing a typo in a question, or resuming after call 340 of 900 died all
# re-issued every earlier call at full price, and at temperature > 0 the earlier
# answers came back *different*, so the thing you were debugging moved while you
# were looking at it.
#
# A cache keyed on the exact request fixes both. A re-run is free, and it is
# also *identical*, which is what makes a result you publish something another
# person can check.
#
# WHAT IS AND IS NOT IN THE KEY
# In: the messages, the model, the resolved `max_output`, the temperature, the
# JSON schema and its name, the API shape and base URL, any extra body fields,
# the reasoning effort when the request carries one, and the draw index when it
# is above 0. Out: the API key, the timeout, the retry policy, the trace and
# the label -- none of which can change what the model returns. (A label can
# choose an effort; the effort it chose is what goes in.)
#
# FAILURES ARE NEVER CACHED. A transport error, a rate limit or a refusal is a
# property of the moment, not of the request. Caching one would turn a blip into
# a permanent wrong answer that no amount of re-running could clear. That
# includes a reply that arrived but cannot be used: one cut off at the output
# cap, and a structured reply that does not parse (see model_call()).

#' A response cache
#'
#' Wrap a client with [gr_cache_client()] and every successful model call is
#' written to disk, keyed on the exact request. Re-issuing the same request
#' returns the stored response without touching the network: free, instant, and
#' byte-identical even at a temperature above zero. A failed call is never
#' written, and neither is a reply cut off at the output cap or a structured
#' (JSON-schema) reply that does not parse, so re-running asks again. An
#' unparseable structured reply that an earlier version did store is asked
#' again rather than replayed.
#'
#' The default location is under [tempdir()], so a cache costs nothing and
#' disappears with the session. That is the right default for a package (it
#' writes nothing to your filesystem you did not ask for), but it is not what
#' you want for a long experiment. Pass a real directory, or
#' `tools::R_user_dir("harnessr", "cache")`, to keep entries across sessions and
#' make a run resumable after a crash. With that directory, entries that
#' readgpt stored in `tools::R_user_dir("readgpt", "cache")` are read too, after
#' it; new entries go only to the harnessr directory, and the old one is never
#' cleared.
#'
#' Cross-session reuse needs a client that can say what it is. [gr_client()] and
#' [gr_ellmer_client()] can: an endpoint and a model describe what will answer
#' next month as well as today. A bare [gr_backend_client()] cannot, because what
#' answers is an R closure, so by default it gets a fresh identity per object and
#' its entries are session-scoped. Give it a stable `id` to opt in.
#'
#' @param dir Directory for cache entries. Defaults to the `cache_dir` option,
#'   and to a directory under [tempdir()] when that is not set either. Created
#'   on first write, not here. An empty string or `NA` is an error rather than
#'   a directory: it is what `Sys.getenv()` returns for a variable that is not
#'   set, and taken as a path it pointed the cache at the root of the
#'   filesystem.
#' @param read,write Whether to read existing entries and write new ones. Set
#'   `write = FALSE` to run against a frozen cache; set `read = FALSE` to
#'   refresh entries that are already stored.
#' @return An object of class `gr_cache`. It holds a directory and a counter
#'   environment, so copies of it share the same statistics.
#'
#' @section What is stored:
#' One small RDS file per entry, sharded into subdirectories by the first two
#' characters of the key. Each file holds the [gr_result] (text, token usage,
#' model, finish reason), with the raw parsed API response dropped, because
#' nothing downstream reads it and keeping it multiplied the cache size for no
#' benefit. The prompt is **not** stored, only its hash, so a cache directory
#' does not accumulate copies of your documents. The response itself is stored
#' in full, and a model response can of course quote the document it read.
#'
#' An entry is used only if the file holds plain data (lists, strings and
#' numbers) in the shape this cache writes, and the response is rebuilt from
#' those fields; anything else is a miss. So reading a cache directory someone
#' else wrote cannot run code. It can still hold any answer its author chose,
#' so treat a shared cache as you would its author's results.
#'
#' @section Caching a stochastic call:
#' At a temperature above zero a cache hit replays one sample rather than
#' drawing a new one. That is the point: it is what makes a run reproducible.
#' But it means N identical calls are one draw N times. To keep N draws, give
#' each call its own `draw_index` (see [gr_call()]): it is part of the key when
#' it is above 0, so draws 1 to N are N entries, and a rerun gets the same N
#' replies back in the same order. A call with the default `draw_index = 0`
#' keys as an unsampled call always has. Use a fresh cache directory, or
#' `read = FALSE`, when you want new replies for draws already stored.
#'
#' @section Keys and older caches:
#' An entry is keyed by a SHA-256 hash under the version string
#' `harnessr-cache-v3`. Entries written before that (by readgpt 0.6.0, and by
#' harnessr before this key: `readgpt-cache-v2` under xxhash64) are still
#' read. A call with no draw index that finds nothing under its key is looked
#' up under the old key too, and a reply found there is used. The first such
#' hit in a session warns once for the cache, with class `hr_legacy_key`, and
#' [gr_cache_stats()] counts them as `legacy_hits`. Old entries are never
#' rewritten, and new ones are written under the new key only, so a cache
#' directory stays readable by the version that wrote it.
#'
#' @seealso [gr_cache_client()] to attach one, [gr_cache_stats()],
#'   [gr_cache_clear()], [gr_replay_client()] for reproducing a recorded run
#' @export
#' @examples
#' cache <- gr_cache(dir = file.path(tempdir(), "harnessr-example-cache"))
#' cache
#'
#' # Nothing is written until a call is cached.
#' gr_cache_stats(cache)[c("entries", "hits", "misses")]
gr_cache <- function(dir = NULL, read = TRUE, write = TRUE) {
  # `%||%` falls back only for NULL, so "" (Sys.getenv() of an unset variable)
  # and NA (which as_chr1() turns into "") were kept. file.path("", "ab", key)
  # is "/ab/key.rds": as a normal user nothing was ever written and the run was
  # not resumable, as root the entries went into the filesystem root, and
  # cache_files() skips "" so gr_cache_stats() and gr_cache_clear() could not
  # see them either way. An explicit value is refused, as an empty header value
  # is; an unset option is unset.
  if (!is.null(dir) &&
      (length(dir) != 1L || !is.character(dir) || is.na(dir) || !nzchar(trimws(dir)))) {
    gr_abort(paste0("`dir` must be one directory path. If it came from Sys.getenv(), that ",
                    "variable is not set. Pass NULL for a cache that lasts this session."),
             class = "gr_bad_setting")
  }
  dir <- dir %||% (gr_options("cache_dir") %|z|% default_cache_dir())
  st <- new.env(parent = emptyenv())
  st$hits <- 0L
  st$misses <- 0L
  st$writes <- 0L
  st$legacy_hits <- 0L
  structure(list(
    dir   = as_chr1(dir),
    read  = isTRUE(read),
    write = isTRUE(write),
    .stats = st
  ), class = "gr_cache")
}

#' @export
print.gr_cache <- function(x, ...) {
  s <- gr_cache_stats(x)
  cat(sprintf("<gr_cache> %s\n", x$dir))
  cat(sprintf("  %d entr%s, %s on disk; %d hit(s), %d miss(es), %d write(s)%s\n",
              s$entries, if (identical(s$entries, 1L)) "y" else "ies",
              format_bytes(s$bytes), s$hits, s$misses, s$writes,
              if (!x$read || !x$write)
                sprintf(" [%s]", paste(c(if (!x$read) "read off", if (!x$write) "write off"),
                                       collapse = ", "))
              else ""))
  invisible(x)
}

#' Attach a cache to a client
#'
#' Returns the same client with the cache attached, so a cached mock client is
#' still a mock client and `$calls()` still records only the calls that were
#' issued, which is how you check that the cache is working.
#'
#' @param client A [gr_client()] or [gr_mock_client()].
#' @param cache A [gr_cache()]. Pass `NULL` to detach.
#' @return The client, with the cache attached.
#' @seealso [gr_cache()], [gr_cache_stats()]
#' @export
#' @examples
#' calls <- 0
#' cl <- gr_mock_client(function(m, p) { calls <<- calls + 1; "42" })
#' cl <- gr_cache_client(cl, gr_cache(file.path(tempdir(), "harnessr-doc-cache")))
#'
#' gr_call(cl, "What is the answer?")$text
#' gr_call(cl, "What is the answer?")$text   # served from the cache
#' calls                                     # the handler ran once
#'
#' # A cache hit is marked, so a trace can tell spending from replay.
#' gr_call(cl, "What is the answer?")$cached
gr_cache_client <- function(client, cache = gr_cache()) {
  if (!inherits(client, "gr_client")) {
    gr_abort("`client` must come from gr_client() or gr_mock_client().")
  }
  if (!is.null(cache) && !inherits(cache, "gr_cache")) {
    gr_abort("`cache` must come from gr_cache(), or be NULL to detach.")
  }
  client$.cache <- cache
  client
}

#' Cache statistics
#'
#' @param cache A [gr_cache()].
#' @return A one-row data frame: `dir`, `entries`, `bytes`, `hits`, `misses`,
#'   `writes` and `legacy_hits`. `entries` and `bytes` are read from disk, so
#'   they include entries written by earlier sessions; the counters cover this
#'   session only. `legacy_hits` is how many of the hits were found under the
#'   old `readgpt-cache-v2` key (see [gr_cache()]).
#' @seealso [gr_cache()], [gr_cache_clear()]
#' @export
#' @examples
#' cache <- gr_cache(file.path(tempdir(), "harnessr-stats-cache"))
#' cl <- gr_cache_client(gr_mock_client(function(m, p) "hi"), cache)
#' invisible(gr_call(cl, "one"))
#' invisible(gr_call(cl, "one"))
#' gr_cache_stats(cache)[c("entries", "hits", "misses", "writes")]
gr_cache_stats <- function(cache) {
  stopifnot(inherits(cache, "gr_cache"))
  files <- cache_files(cache$dir)
  data.frame(
    dir = cache$dir,
    entries = length(files),
    bytes = if (length(files)) sum(file.size(files), na.rm = TRUE) else 0,
    hits = cache$.stats$hits,
    misses = cache$.stats$misses,
    writes = cache$.stats$writes,
    # A cache object made before the counter existed (one restored with
    # readRDS()) has no such field.
    legacy_hits = as_int1(cache$.stats$legacy_hits, 0L),
    stringsAsFactors = FALSE
  )
}

#' Delete every entry in a cache
#'
#' Removes the stored responses and resets the session counters. The directory
#' itself is left in place, and so is anything in it that is not a cache entry
#' (a [gr_read_many()] store, your own files): only files in the cache's own
#' layout are removed.
#'
#' @param cache A [gr_cache()].
#' @return The number of entries removed, invisibly.
#' @seealso [gr_cache()], [gr_cache_stats()]
#' @export
#' @examples
#' cache <- gr_cache(file.path(tempdir(), "harnessr-clear-cache"))
#' cl <- gr_cache_client(gr_mock_client(function(m, p) "hi"), cache)
#' invisible(gr_call(cl, "something"))
#' gr_cache_clear(cache)
#' gr_cache_stats(cache)$entries
gr_cache_clear <- function(cache) {
  stopifnot(inherits(cache, "gr_cache"))
  files <- cache_files(cache$dir)
  if (length(files)) unlink(files)
  cache$.stats$hits <- 0L
  cache$.stats$misses <- 0L
  cache$.stats$writes <- 0L
  cache$.stats$legacy_hits <- 0L
  invisible(length(files))
}

# --- internals -------------------------------------------------------------

#' A per-session cache directory under `tempdir()`.
#'
#' Resolved on every call, never stored in `gr_defaults`: a `tempdir()` written
#' into that list would be evaluated when the package is installed and then
#' baked into the namespace image, pointing every later session at a directory
#' that no longer exists.
#' @noRd
default_cache_dir <- function() file.path(tempdir(), "harnessr-cache")

#' Where readgpt's documented cache directory is, when `dir` is harnessr's.
#'
#' The help pages of readgpt suggested `tools::R_user_dir("readgpt", "cache")`
#' as a cache directory that lasts. When the configured directory is the one
#' harnessr suggests in its place, the old one is read after it, so a warm
#' cache kept where the old help said keeps answering: the keys are the same.
#' It is never written to or cleared. For any other directory this is "", no
#' directory: file.path("", ...) would be the filesystem root.
#' @noRd
legacy_cache_dir <- function(dir) {
  same <- function(a, b) {
    identical(normalizePath(a, winslash = "/", mustWork = FALSE),
              normalizePath(b, winslash = "/", mustWork = FALSE))
  }
  new <- tools::R_user_dir("harnessr", "cache")
  if (!same(as_chr1(dir), new)) return("")
  old <- tools::R_user_dir("readgpt", "cache")
  if (same(old, new) || !dir.exists(old)) "" else old
}

#' Every entry file under a cache directory.
#'
#' Only files in the layout cache_path() writes: `<shard>/<key>.rds`, where the
#' key is 64 hex digits (harnessr-cache-v3) or 16 (readgpt-cache-v2, still read
#' and still cleared) and the shard is its first two. gr_cache_clear() unlinks
#' whatever this returns, and a cache directory is often a real project folder
#' (the documentation suggests passing one) that also holds a gr_read_many()
#' store, saved results or anything else ending in `.rds`. Matching on the
#' extension alone deleted all of them, outright, and counted them as entries.
#' @noRd
cache_files <- function(dir) {
  if (!nzchar(dir) || !dir.exists(dir)) return(character(0))
  shards <- list.files(dir, pattern = "^[0-9a-f]{2}$", full.names = TRUE)
  shards <- shards[dir.exists(shards)]
  out <- unlist(lapply(shards, function(s) {
    list.files(s, pattern = paste0("^", basename(s), "([0-9a-f]{14}|[0-9a-f]{62})\\.rds$"),
               full.names = TRUE)
  }), use.names = FALSE)
  if (!length(out)) return(character(0))
  out[utils::file_test("-f", out)]
}

#' The key for one request.
#'
#' Everything that can change the response goes in; nothing else does. The
#' leading version string is what lets a change to the key scheme invalidate
#' old entries instead of silently mixing two schemes in one directory. The
#' previous scheme is still read: see legacy_cache_key_v2() and cache_get().
#' @noRd
cache_key <- function(client, messages, model, max_output, temperature,
                      schema, schema_name, extra, effort = NULL, draw_index = 0L) {
  draw_index <- as_int1(draw_index, 0L)
  parts <- c(
    # v3: SHA-256 through hr_hash() in place of xxhash64, and the draw index.
    # The v2 key is looked up after this one, so entries written under it
    # still answer.
    "harnessr-cache-v3",
    as_chr1(client$api, "?"),
    as_chr1(client$base_url, "?"),
    # Present only on clients whose behaviour is an R closure rather than a URL.
    # Without it two different mock or backend clients shared entries, because
    # api, base_url and model are identical constants for all of them.
    as_chr1(client$.client_id, "<url-addressed>"),
    as_chr1(model, "?"),
    format(as.integer(max_output)),
    if (is.null(temperature)) "<null>" else format(temperature, digits = 15L),
    as_chr1(schema_name, "result"),
    if (is.null(schema)) "<no-schema>" else hr_hash(schema),
    hr_hash(client$extra_body %||% list()),
    hr_hash(extra %||% list()),
    # The reasoning effort the request carries, which changes the reply as a
    # temperature does. A part only when there is one, so two runs at
    # different efforts never trade replies. The prefix keeps it apart from a
    # message's role, which is the part that comes next in a key without one.
    if (!is.null(effort)) paste0("effort:", as_chr1(effort)),
    # Which draw of a sampled request this is. Without it N identical calls
    # were one cached reply N times, and anything that compared them measured
    # perfect agreement. A part only above 0, as effort is only when set: an
    # unsampled call has no draw, and keys as such.
    if (draw_index > 0L) paste0("draw:", draw_index),
    key_text(unlist(lapply(messages, function(m) c(as_chr1(m$role), as_chr1(m$content))),
                    use.names = FALSE))
  )
  hr_hash(parts)
}

#' Normalise text before it is hashed into a key.
#'
#' `digest()` hashes the serialised R object, and a string's declared encoding
#' is part of that object. So the SAME BYTES marked "UTF-8" and marked "unknown"
#' hash differently -- which meant a prompt that had been round-tripped through
#' JSON (as a saved trace is) never matched the same prompt held in memory, and
#' any non-ASCII prompt missed on replay while every ASCII one hit. Both key
#' schemes normalise through the package's own decoder first, so a key depends
#' on the characters and not on how they happen to be labelled.
#'
#' The one thing this merges is line endings: `to_utf8()` normalises CRLF, so
#' two prompts differing only in that share a key. Ingestion has already done
#' the same to every chunk, so it can only arise for a hand-built message, and
#' the model would not have distinguished them either.
#' @noRd
key_text <- function(x) {
  if (!length(x)) return(character(0))
  to_utf8(x)
}

#' @noRd
cache_path <- function(dir, key) {
  file.path(dir, substr(key, 1L, 2L), paste0(key, ".rds"))
}

#' Look one request up.
#'
#' A cache is an optimisation, never a source of errors: an unreadable,
#' truncated or half-written file is a miss, not a failure. Returning the error
#' would mean a corrupted byte on disk could stop a run that has nothing wrong
#' with it.
#'
#' `legacy` is a function returning the request's readgpt-cache-v2 key, or
#' NULL when it has none (a call with a draw index). It is called and looked up
#' only when `key` finds nothing, so a hit under the new key costs one hash,
#' and a reply found under it is counted and warned about (legacy_key_warn()).
#' @noRd
cache_get <- function(cache, key, legacy = NULL) {
  # No directory is no cache: file.path("", ...) is the filesystem root.
  if (!isTRUE(cache$read) || !nzchar(as_chr1(cache$dir))) return(NULL)
  old <- legacy_cache_dir(cache$dir)
  find <- function(k) {
    path <- cache_path(cache$dir, k)
    if (!file.exists(path) && nzchar(old)) path <- cache_path(old, k)
    if (file.exists(path)) path
  }
  path <- find(key)
  was_legacy <- FALSE
  if (is.null(path) && is.function(legacy)) {
    path <- find(legacy())
    was_legacy <- !is.null(path)
  }
  if (is.null(path)) {
    cache$.stats$misses <- cache$.stats$misses + 1L
    return(NULL)
  }
  entry <- tryCatch(readRDS(path), error = function(e) NULL, warning = function(w) NULL)
  res <- tryCatch(cache_entry_result(entry), error = function(e) NULL)
  if (is.null(res)) {
    cache$.stats$misses <- cache$.stats$misses + 1L
    return(NULL)
  }
  cache$.stats$hits <- cache$.stats$hits + 1L
  if (was_legacy) {
    cache$.stats$legacy_hits <- as_int1(cache$.stats$legacy_hits, 0L) + 1L
    legacy_key_warn("cache", cache$dir)
    # So that cache_unhit() can take the count back when the caller cannot
    # use the reply.
    attr(res, "legacy_key") <- TRUE
  }
  res
}

#' Count a hit the caller could not use as the miss it is.
#'
#' client_dispatch() asks again when a stored reply fails the caller's test of
#' a usable one (see model_call()); the statistics should say it was asked.
#' @noRd
cache_unhit <- function(cache, hit = NULL) {
  cache$.stats$hits <- max(cache$.stats$hits - 1L, 0L)
  if (isTRUE(attr(hit, "legacy_key", exact = TRUE))) {
    cache$.stats$legacy_hits <- max(as_int1(cache$.stats$legacy_hits, 0L) - 1L, 0L)
  }
  cache$.stats$misses <- cache$.stats$misses + 1L
  invisible(NULL)
}

#' The response a cache file holds, rebuilt from its fields, or NULL.
#'
#' RDS can rebuild any R object, including an environment or a closure, and a
#' class attribute costs nothing to forge. The old check,
#' `inherits(entry$result, "gr_result")`, passed an environment carrying that
#' class, and the next line wrote a field into it: reading or writing a field of
#' an environment can run code its author chose, in the session of whoever
#' pointed a cache at a directory they did not write (a shared cache, a
#' reproducibility bundle). So nothing is read from an entry until the whole
#' object is known to be plain data, and what comes back is a fresh `gr_result`
#' built from the expected fields, never the object from the file.
#' @noRd
cache_entry_result <- function(entry) {
  if (!is_plain_data(entry) || !is.list(entry)) return(NULL)
  if (!identical(.subset2(entry, "format"), 1L)) return(NULL)
  r <- .subset2(entry, "result")
  if (!is.list(r) || !inherits(r, "gr_result")) return(NULL)
  # Failures are never written (see cache_put()), so an entry holding one did
  # not come from this cache.
  if (!isTRUE(.subset2(r, "ok"))) return(NULL)
  u <- .subset2(r, "usage")
  if (!is.list(u)) u <- list()
  # The provenance and breakdown the reply was stored with. An entry written
  # before they were kept has neither, and its provenance reads as NA.
  prov <- as_chr1(.subset2(u, "provenance"), NA_character_)
  if (!prov %in% .gr_usage_provenance) prov <- NA_character_
  chr <- function(nm) as_chr1(.subset2(r, nm), NA_character_)
  gr_result(TRUE,
            text = as_chr1(.subset2(r, "text")),
            status = as_int1(.subset2(r, "status"), NA_integer_),
            usage = usage_record(as_int1(.subset2(u, "input"), 0L),
                                 as_int1(.subset2(u, "output"), 0L), prov,
                                 reasoning = as_int1(.subset2(u, "reasoning"), NA_integer_),
                                 cached_input = as_int1(.subset2(u, "cached_input"),
                                                        NA_integer_)),
            model = chr("model"),
            finish_reason = chr("finish_reason"),
            cached = TRUE,
            served_model = chr("served_model"), response_id = chr("response_id"),
            fingerprint = chr("fingerprint"))
}

#' Is `x` plain data all the way down?
#'
#' NULL, atomic vectors and lists of them, with attributes that are plain data
#' too. Anything else (an environment, a closure, a language object, an external
#' pointer, an S4 object) is refused before it is touched. Elements are reached
#' with `x[[i]]` handed straight to this function, never bound to a loop
#' variable, and the first thing done with each is `typeof()`, which looks at an
#' object without evaluating it. The depth limit is far beyond anything
#' cache_put() writes.
#' @noRd
is_plain_data <- function(x, depth = 0L) {
  if (depth > 16L) return(FALSE)
  if (!typeof(x) %in% c("NULL", "logical", "integer", "double", "complex",
                        "character", "raw", "list")) return(FALSE)
  if (isS4(x)) return(FALSE)
  a <- attributes(x)
  if (length(a) && !all(vapply(seq_along(a), function(i) is_plain_data(a[[i]], depth + 1L),
                               logical(1)))) return(FALSE)
  if (is.list(x) && length(x) &&
      !all(vapply(seq_along(x), function(i) is_plain_data(x[[i]], depth + 1L),
                  logical(1)))) return(FALSE)
  TRUE
}

#' Store one response.
#'
#' Written to a temporary name in the same directory and then renamed, so a
#' crash or an interrupt mid-write cannot leave a half file that a later run
#' would have to distinguish from a real one. A failed write is silent: the run
#' continues uncached rather than dying over a full disk or a read-only mount.
#' @noRd
cache_put <- function(cache, key, res) {
  if (!isTRUE(cache$write) || is.null(key) || !nzchar(as_chr1(cache$dir))) {
    return(invisible(FALSE))
  }
  path <- cache_path(cache$dir, key)
  dir <- dirname(path)
  if (!dir.exists(dir) && !dir.create(dir, recursive = TRUE, showWarnings = FALSE)) {
    return(invisible(FALSE))
  }
  res$raw <- NULL          # nothing downstream reads it; keeping it bloats the cache
  res$cached <- FALSE      # what is stored is an original, not a replay
  entry <- list(format = 1L, key = key, created = Sys.time(), result = res)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  ok <- tryCatch({
    saveRDS(entry, tmp, compress = TRUE)
    file.rename(tmp, path)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) {
    if (file.exists(tmp)) unlink(tmp)
    return(invisible(FALSE))
  }
  cache$.stats$writes <- cache$.stats$writes + 1L
  invisible(TRUE)
}

#' @noRd
format_bytes <- function(n) {
  n <- as.numeric(n)[1]
  if (!is.finite(n)) return("?")
  units <- c("B", "KB", "MB", "GB")
  i <- 1L
  while (n >= 1024 && i < length(units)) { n <- n / 1024; i <- i + 1L }
  sprintf(if (i == 1L) "%.0f %s" else "%.1f %s", n, units[i])
}
