# Collect parameters into a schema

Collect parameters into a schema

## Usage

``` r
hr_schema(...)
```

## Arguments

- ...:

  [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  objects. Their order is the order
  [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
  resolves them in, so a bound that depends on another parameter comes
  after it.

## Value

An object of class `hr_schema`: a list of `hr_param`, named by
parameter.

## See also

[`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md),
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)

## Examples

``` r
s <- hr_schema(
  hr_param("max_tokens", "integer", default = 1200L, min = 32, max = 1e6),
  hr_param("overlap_tokens", "integer", default = 0L, min = 0,
           max = function(p) p$max_tokens - 1L))
suppressWarnings(hr_validate(s, list(max_tokens = 100, overlap_tokens = 500)))
#> $max_tokens
#> [1] 100
#> 
#> $overlap_tokens
#> [1] 99
#> 
```
