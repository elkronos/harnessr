# Is a calibration record valid for a run?

A record holds only for the served model, model version, task, format,
prompt hash, effort, module and contract version it was measured on.
`hr_calibration_valid()` is `FALSE` when any of them differs from `key`,
or is missing from it, and the fields that differ are in the `"differs"`
attribute. A `key` without `contract_version` is checked against the
running package's contract version, so a record made under another
contract version is void.

## Usage

``` r
hr_calibration_valid(cal, key)
```

## Arguments

- cal:

  An `hr_calibration` from
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md).

- key:

  A named list with the fields described under `key` in
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
  for the run the record would be used in.

## Value

`TRUE` or `FALSE`, with attribute `differs` naming the fields that did
not match.

## See also

Other signals:
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md),
[`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)

## Examples

``` r
graded <- data.frame(score = rep(c(0.9, 0.2), 20), correct = rep(c(TRUE, FALSE), 20),
                     answerable = rep(c(TRUE, TRUE, TRUE, FALSE), 10))
key <- list(served_model = "m-2026", version = "2026", task = "qa", format = "pdf",
            prompt_hash = "abc", effort = NA, module = "iterative")
cal <- hr_calibrate_signal("demo", graded, key, seed = 1, B = 0)
hr_calibration_valid(cal, key)
#> [1] TRUE
#> attr(,"differs")
#> character(0)
hr_calibration_valid(cal, utils::modifyList(key, list(served_model = "m-2027")))
#> [1] FALSE
#> attr(,"differs")
#> [1] "served_model"
```
