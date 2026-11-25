# Delete every entry in a cache

Removes the stored responses and resets the session counters. The
directory itself is left in place, and so is anything in it that is not
a cache entry (a
[`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
store, your own files): only files in the cache's own layout are
removed.

## Usage

``` r
hr_cache_clear(cache)
```

## Arguments

- cache:

  An
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md).

## Value

The number of entries removed, invisibly.

## See also

[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md),
[`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)

## Examples

``` r
cache <- hr_cache(file.path(tempdir(), "harnessr-clear-cache"))
cl <- hr_cache_client(hr_mock_client(function(m, p) "hi"), cache)
invisible(hr_call(cl, "something"))
hr_cache_clear(cache)
hr_cache_stats(cache)$entries
#> [1] 0
```
