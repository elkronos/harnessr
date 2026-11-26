# Clear the session's document and embedding caches

harnessr keeps two caches in memory for the life of the R session: the
documents
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
has already extracted and cleaned, keyed on the file and every setting
that changes the result, and the vectors the built-in `"api"` embedder
has already fetched (see
[`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)).
This empties them. The next ingestion of a file reads and cleans it
again, and the next ranking sends its embeddings requests again, which
are counted against `max_calls` and `max_cost_usd` like any others.

## Usage

``` r
gr_flush_caches(what = "all")
```

## Arguments

- what:

  One or more of `"all"` (the default), `"documents"` and
  `"embeddings"`.

## Value

Invisibly, the caches cleared: `"documents"`, `"embeddings"` or both.

## Details

Each cache is bounded: when what it holds passes its budget (256 MB of
documents, 128 MB of vectors) the entries used least recently are
dropped, so a long session or a Shiny server does not need this to stay
within memory. It is for starting again from nothing: to give the memory
back at once, or to time or test a run as a fresh session would see it.

Not to be confused with
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md),
which deletes the model *responses* an
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
keeps in a directory on disk. Neither touches the other's cache: this
leaves every stored response in place, and
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
leaves every document and vector in memory.
`hr_options(cache_documents = FALSE, cache_embeddings = FALSE)` turns
the two memory caches off instead.

## See also

[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
for the on-disk response cache,
[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
for `cache_documents` and `cache_embeddings`,
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md),
[`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)

## Examples

``` r
doc <- gr_ingest(gr_example())
#> Using cached ingestion for this document + settings.
gr_flush_caches("documents")
gr_flush_caches()
```
