# Check a module against a set of rules

Runs a module once and reports which of a list of rules it breaks. It is
a report and nothing more: registering a module does not run it, and a
module that breaks a rule is still registered and still runs.
[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md)
and
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)
use it with the rules for readers and segmenters.

## Usage

``` r
hr_check_module(fn, run, rules = list(), kind = "module", name = NA_character_)
```

## Arguments

- fn:

  The module's function. The `is_function` rule checks that it is one.

- run:

  A function of no arguments that calls the module once and returns what
  the rules are to check.

- rules:

  A named list of rule functions, checked in order.

- kind:

  The kind of module, such as `"reader"`, for the report.

- name:

  The module's name, for the report.

## Value

An object of class `hr_conformance`: a data frame with one row per rule
and the columns `rule`, `ok` (logical, `NA` for a rule that was not
checked) and `detail` (character, `""` when there is nothing to say).
Its attributes are `kind`, `name`, `contract` (the contract version it
was checked against) and `warnings` (the messages of the warnings the
run raised). The first two rows are always `is_function` and `runs`.
[`print()`](https://rdrr.io/r/base/print.html) lists the broken rules
first.

## Details

`run()` is called with no arguments inside a temporary working
directory, which is removed afterwards, so a module that writes files
leaves nothing behind. An error it raises is caught and reported by the
`runs` rule; its warnings are caught too, kept in the `warnings`
attribute and not shown.

Each rule is a function of one argument, the value `run()` returned. It
returns `TRUE` when the module passes, `FALSE` when it breaks the rule,
and `NA` when the rule could not be checked on this run, or a list with
`ok` (one of those three) and `detail` (one string saying why). A rule
that raises an error is reported as broken, with the error as its
detail. When `run()` fails, no rule is asked and each is reported as
`NA`.

## See also

[`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md),
[`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)

## Examples

``` r
double_it <- function(x) x * 2
hr_check_module(double_it, function() double_it(2),
  rules = list(numeric = function(v) is.numeric(v),
               above_three = function(v) list(ok = v > 3, detail = sprintf("got %s", v))),
  kind = "function", name = "double_it")
#> <hr_conformance> function 'double_it', contract 0.1
#>   passes all 4 rules
#>   ok    is_function
#>   ok    runs
#>   ok    numeric
#>   ok    above_three: got 4
```
