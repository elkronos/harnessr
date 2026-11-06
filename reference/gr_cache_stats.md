# Cache statistics

Cache statistics

## Usage

``` r
gr_cache_stats(cache)
```

## Arguments

- cache:

  A
  [`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md).

## Value

A one-row data frame: `dir`, `entries`, `bytes`, `hits`, `misses`,
`writes` and `legacy_hits`. `entries` and `bytes` are read from disk, so
they include entries written by earlier sessions; the counters cover
this session only. `legacy_hits` is how many of the hits were found
under the old `readgpt-cache-v2` key (see
[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md)).

## See also

[`gr_cache()`](https://elkronos.github.io/readgpt/reference/gr_cache.md),
[`gr_cache_clear()`](https://elkronos.github.io/readgpt/reference/gr_cache_clear.md)

## Examples

``` r
cache <- gr_cache(file.path(tempdir(), "harnessr-stats-cache"))
cl <- gr_cache_client(gr_mock_client(function(m, p) "hi"), cache)
invisible(gr_call(cl, "one"))
invisible(gr_call(cl, "one"))
gr_cache_stats(cache)[c("entries", "hits", "misses", "writes")]
#>   entries hits misses writes
#> 1       1    1      1      1
```
