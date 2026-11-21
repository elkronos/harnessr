# Collect parameters into a schema

Collect parameters into a schema

## Usage

``` r
hr_schema(...)

# S3 method for class 'hr_schema'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)
```

## Arguments

- ...:

  [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  objects. Their order is the order
  [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
  resolves them in, so a bound that depends on another parameter comes
  after it.

- x:

  An `hr_schema`.

- row.names, optional:

  Ignored.

## Value

An object of class `hr_schema`: a list of `hr_param`, named by
parameter.

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) gives one
row per parameter: `name`, `type`, `default` (as text; an enum's is its
first choice), `range` (the bounds or choices, `f()` for a bound set by
another parameter), `tier`, `status` and `source` (from its `evidence`,
`NA` when not declared) and `help`.

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
