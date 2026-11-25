# Cache statistics

Cache statistics

## Usage

``` r
hr_cache_stats(cache)
```

## Arguments

- cache:

  An
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md).

## Value

A one-row data frame: `dir`, `entries`, `bytes`, `hits`, `misses`,
`writes` and `legacy_hits`. `entries` and `bytes` are read from disk, so
they include entries written by earlier sessions; the counters cover
this session only. `legacy_hits` is how many of the hits were found
under the old `readgpt-cache-v2` key (see
[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)).

## See also

[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md),
[`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)

## Examples

``` r
cache <- hr_cache(file.path(tempdir(), "harnessr-stats-cache"))
cl <- hr_cache_client(hr_mock_client(function(m, p) "hi"), cache)
invisible(hr_call(cl, "one"))
invisible(hr_call(cl, "one"))
hr_cache_stats(cache)[c("entries", "hits", "misses", "writes")]
#>   entries hits misses writes
#> 1       1    1      1      1
```
