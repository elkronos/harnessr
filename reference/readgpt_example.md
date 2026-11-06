# Deprecated: path to the bundled example document

`readgpt_example()` is the name
[`gr_example()`](https://elkronos.github.io/readgpt/reference/gr_example.md)
had before the package was renamed. It returns the same path, with one
`gr_deprecated` warning per session naming the new function.

## Usage

``` r
readgpt_example()
```

## Value

Absolute path to the file, as
[`gr_example()`](https://elkronos.github.io/readgpt/reference/gr_example.md)
returns it.

## See also

[`gr_example()`](https://elkronos.github.io/readgpt/reference/gr_example.md)

## Examples

``` r
identical(suppressWarnings(readgpt_example()), gr_example())
#> [1] TRUE
```
