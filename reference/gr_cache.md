# A response cache

Wrap a client with
[`gr_cache_client()`](https://elkronos.github.io/harnessr/reference/gr_cache_client.md)
and every successful model call is written to disk, keyed on the exact
request. Re-issuing the same request returns the stored response without
touching the network: free, instant, and byte-identical even at a
temperature above zero. A failed call is never written, and neither is a
reply cut off at the output cap or a structured (JSON-schema) reply that
does not parse, so re-running asks again. An unparseable structured
reply that an earlier version did store is asked again rather than
replayed.

## Usage

``` r
gr_cache(dir = NULL, read = TRUE, write = TRUE)
```

## Arguments

- dir:

  Directory for cache entries. Defaults to the `cache_dir` option, and
  to a directory under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html) when that is not
  set either. Created on first write, not here. An empty string or `NA`
  is an error rather than a directory: it is what
  [`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) returns for a
  variable that is not set, and taken as a path it pointed the cache at
  the root of the filesystem.

- read, write:

  Whether to read existing entries and write new ones. Set
  `write = FALSE` to run against a frozen cache; set `read = FALSE` to
  refresh entries that are already stored.

## Value

An object of class `gr_cache`. It holds a directory and a counter
environment, so copies of it share the same statistics.

## Details

The default location is under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html), so a cache costs
nothing and disappears with the session. That is the right default for a
package (it writes nothing to your filesystem you did not ask for), but
it is not what you want for a long experiment. Pass a real directory, or
`tools::R_user_dir("harnessr", "cache")`, to keep entries across
sessions and make a run resumable after a crash. With that directory,
entries that readgpt stored in `tools::R_user_dir("readgpt", "cache")`
are read too, after it; new entries go only to the harnessr directory,
and the old one is never cleared.

Cross-session reuse needs a client that can say what it is.
[`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md)
and
[`gr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/gr_ellmer_client.md)
can: an endpoint and a model describe what will answer next month as
well as today. A bare
[`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
cannot, because what answers is an R closure, so by default it gets a
fresh identity per object and its entries are session-scoped. Give it a
stable `id` to opt in.

## What is stored

One small RDS file per entry, sharded into subdirectories by the first
two characters of the key. Each file holds the
[gr_result](https://elkronos.github.io/harnessr/reference/gr_result.md)
(text, token usage, model, finish reason), with the raw parsed API
response dropped, because nothing downstream reads it and keeping it
multiplied the cache size for no benefit. The prompt is **not** stored,
only its hash, so a cache directory does not accumulate copies of your
documents. The response itself is stored in full, and a model response
can of course quote the document it read.

An entry is used only if the file holds plain data (lists, strings and
numbers) in the shape this cache writes, and the response is rebuilt
from those fields; anything else is a miss. So reading a cache directory
someone else wrote cannot run code. It can still hold any answer its
author chose, so treat a shared cache as you would its author's results.

## Caching a stochastic call

At a temperature above zero a cache hit replays one sample rather than
drawing a new one. That is the point: it is what makes a run
reproducible. But it means N identical calls are one draw N times. To
keep N draws, give each call its own `draw_index` (see
[`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)):
it is part of the key when it is above 0, so draws 1 to N are N entries,
and a rerun gets the same N replies back in the same order. A call with
the default `draw_index = 0` keys as an unsampled call always has. Use a
fresh cache directory, or `read = FALSE`, when you want new replies for
draws already stored.

## Keys and older caches

An entry is keyed by a SHA-256 hash under the version string
`harnessr-cache-v3`. Entries written before that (by readgpt 0.6.0, and
by harnessr before this key: `readgpt-cache-v2` under xxhash64) are
still read. A call with no draw index that finds nothing under its key
is looked up under the old key too, and a reply found there is used. The
first such hit in a session warns once for the cache, with class
`hr_legacy_key`, and
[`gr_cache_stats()`](https://elkronos.github.io/harnessr/reference/gr_cache_stats.md)
counts them as `legacy_hits`. Old entries are never rewritten, and new
ones are written under the new key only, so a cache directory stays
readable by the version that wrote it.

## See also

[`gr_cache_client()`](https://elkronos.github.io/harnessr/reference/gr_cache_client.md)
to attach one,
[`gr_cache_stats()`](https://elkronos.github.io/harnessr/reference/gr_cache_stats.md),
[`gr_cache_clear()`](https://elkronos.github.io/harnessr/reference/gr_cache_clear.md),
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
for reproducing a recorded run

## Examples

``` r
cache <- gr_cache(dir = file.path(tempdir(), "harnessr-example-cache"))
cache
#> <gr_cache> /tmp/Rtmp4M7RcG/harnessr-example-cache
#>   0 entries, 0.0 B on disk; 0 hit(s), 0 miss(es), 0 write(s)

# Nothing is written until a call is cached.
gr_cache_stats(cache)[c("entries", "hits", "misses")]
#>   entries hits misses
#> 1       0    0      0
```
