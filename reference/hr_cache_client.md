# Attach a cache to a client

Returns the same client with the cache attached, so a cached mock client
is still a mock client and `$calls()` still records only the calls that
were issued, which is how you check that the cache is working.

## Usage

``` r
hr_cache_client(client, cache = hr_cache())
```

## Arguments

- client:

  An
  [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
  or
  [`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md).

- cache:

  An
  [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md).
  Pass `NULL` to detach.

## Value

The client, with the cache attached.

## See also

[`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md),
[`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)

## Examples

``` r
calls <- 0
cl <- hr_mock_client(function(m, p) { calls <<- calls + 1; "42" })
cl <- hr_cache_client(cl, hr_cache(file.path(tempdir(), "harnessr-doc-cache")))

hr_call(cl, "What is the answer?")$text
#> [1] "42"
hr_call(cl, "What is the answer?")$text   # served from the cache
#> [1] "42"
calls                                     # the handler ran once
#> [1] 1

# A cache hit is marked, so a trace can tell spending from replay.
hr_call(cl, "What is the answer?")$cached
#> [1] TRUE
```
