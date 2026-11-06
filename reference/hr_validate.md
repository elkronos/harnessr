# Validate and resolve settings against a schema

Applies each parameter's rule (see
[`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md))
to the value given for it, or to its default when none is given, in
schema order.

## Usage

``` r
hr_validate(schema, values = list())
```

## Arguments

- schema:

  An
  [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md).

- values:

  A named list of settings. A name the schema does not have is an error
  of class `hr_unknown_param`.

## Value

A named list with one resolved value per parameter, in schema order. A
parameter that resolves to `NULL` is kept as a `NULL` element.

## See also

[`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md),
[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)

## Examples

``` r
s <- hr_schema(hr_param("order", "enum", choices = c("relevance", "document")))
hr_validate(s, list(order = "doc"))$order
#> [1] "document"
```
