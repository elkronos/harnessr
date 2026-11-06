# Declare one parameter of a module or spec

A parameter states its type, default and allowed values once, so that
the spec it belongs to is validated the same way wherever it is built.
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
applies the rules;
[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
collects parameters into a schema.

## Usage

``` r
hr_param(
  name,
  type = c("integer", "number", "string", "boolean", "enum", "string_vector",
    "named_map", "module_ref", "file"),
  default = NULL,
  min = NULL,
  max = NULL,
  choices = NULL,
  required = FALSE,
  help = "",
  cost_class = "none",
  affects_output = TRUE,
  tier = c("basic", "advanced"),
  evidence = NULL,
  depends_on = NULL,
  since = NULL,
  kind = NULL,
  strict = TRUE,
  resolve = NULL
)
```

## Arguments

- name:

  The parameter's name, as the spec field it fills.

- type:

  One of `"integer"`, `"number"`, `"string"`, `"boolean"`, `"enum"`,
  `"string_vector"`, `"named_map"`, `"module_ref"` or `"file"`.

- default:

  The value used when none is given.

- min, max:

  Bounds for `integer` and `number`. Either may be a function of the
  parameters resolved before this one, for a bound that depends on
  another setting.

- choices:

  The allowed values of an `enum`.

- required:

  Whether a value must be given.

- help:

  One plain sentence saying what the parameter does.

- cost_class:

  How the parameter moves the cost of a run: `"none"`, `"local"`,
  `"per_call_constant"`, `"per_unit"`, `"per_sample"` or `"per_round"`.

- affects_output:

  Whether the parameter can change what a run returns, and so belongs in
  cache and store keys.

- tier:

  `"basic"` or `"advanced"`, for grouping in a user interface.

- evidence:

  `NULL`, or a list saying where the setting comes from and whether its
  benefit has been measured.

- depends_on:

  `NULL`, or a condition (a string) under which the parameter applies.

- since:

  The version that added the parameter.

- kind:

  For `module_ref`: the kind of module it names.

- strict:

  For `boolean`: whether a value other than `TRUE` or `FALSE` is an
  error rather than `FALSE`.

- resolve:

  `NULL`, or a function of `(value, param, params)` returning the
  resolved value, used instead of the type's rule. `params` holds the
  parameters resolved before this one.

## Value

An object of class `hr_param`.

## Details

The rules by type:

- `integer`, `number`:

  A value that is missing, not a single value or not a number falls back
  to `default`, with a `gr_bad_setting` warning. With `min` or `max`, a
  value outside the range is moved to the nearest bound and warned about
  (`gr_clamped`, also of class `hr_param_clamped`). An `integer` comes
  back as an integer.

- `boolean`:

  With `strict = TRUE`, anything but a single `TRUE` or `FALSE` is an
  error (`gr_bad_setting`). With `strict = FALSE`, anything but `TRUE`
  is read as `FALSE`.

- `enum`:

  One of `choices`, matched as
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html) matches, so an
  unambiguous abbreviation is accepted and the whole `choices` vector
  means the first choice. Anything else is an error naming the choices.

- `string`, `file`, `module_ref`:

  A single non-blank string, or `NULL` when the default is `NULL`.

- `string_vector`:

  A character vector, or `NULL` when the default is `NULL`.

- `named_map`:

  A character vector, or a list whose elements all have non-empty names
  (an empty list is one), or `NULL` when the default is `NULL`.

A `resolve` function replaces the type's rule for a parameter that needs
its own, such as an effort map checked against declared call stems.

## See also

[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md),
[`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)

## Examples

``` r
p <- hr_param("top_k", "integer", default = 6L, min = 1, max = 1e4,
              help = "Chunks to use.")
hr_validate(hr_schema(p), list(top_k = 8))$top_k
#> [1] 8

# Out of range: moved to the bound and warned about.
suppressWarnings(hr_validate(hr_schema(p), list(top_k = 0))$top_k)
#> [1] 1
```
