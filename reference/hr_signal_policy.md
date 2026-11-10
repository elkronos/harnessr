# What a signal may do, and what happens when it may not

A policy names a signal, the action it would gate and where an item goes
when the signal cannot gate it. `hr_apply_signal()` applies it.

## Usage

``` r
hr_signal_policy(
  signal,
  action,
  on_fail = c("route_check", "route_person", "ignore")
)

hr_apply_signal(sig, policy, cal = NULL, key = NULL)
```

## Arguments

- signal:

  The signal's name.

- action:

  The action the signal would gate, as given to
  [`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md).

- on_fail:

  Where an item goes when the signal does not gate it: `"route_check"`
  (an outside check, the default), `"route_person"` or `"ignore"`.

- sig:

  An `hr_signal` from
  [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md),
  or the bare value (one or more), taken to be the policy's signal.

- policy:

  An `hr_signal_policy`.

- cal:

  An `hr_calibration`, or `NULL`.

- key:

  The run's calibration key (see
  [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)).
  Without it the record cannot be checked, and the signal stays
  advisory.

## Value

`hr_signal_policy()` returns an `hr_signal_policy`: a list with
`signal`, `action` and `on_fail`.

`hr_apply_signal()` returns a data frame with one row per value:
`signal`, `value`, `p` (the mapped probability, or `NA`), `threshold`,
`gated` (whether the gate decided), `act` (whether the action is taken),
`would_act` (what the value alone suggests: the value of a logical
signal, or `p >= threshold` when both are known), `route` (`"act"`, or
the policy's `on_fail`) and `reason`.

## Details

`hr_apply_signal()` lets the signal gate only when every one of these
holds: a calibration record is given, it is for this signal, its key
matches the run's `key`
([`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md)),
its status is `"gating"`, and its gate was set for the policy's action.
Otherwise the signal is advisory: `gated` is `FALSE`, the action is not
taken, the item is routed by `on_fail`, and `reason` says which
condition failed. When the signal does gate, the action is taken for a
value whose mapped probability is at or above the gate's threshold, and
a value below it is routed by `on_fail`. No reader calls this yet, so
nothing in the package gates on a signal.

## See also

Other signals:
[`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md),
[`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md),
[`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md),
[`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)

## Examples

``` r
pol <- hr_signal_policy("gr.iterative.can_answer", "stop")
sig <- hr_signal("gr.iterative.can_answer", TRUE)

# With no calibration record the signal stays advisory.
hr_apply_signal(sig, pol)
#>                    signal value  p threshold gated   act would_act       route
#> 1 gr.iterative.can_answer  TRUE NA        NA FALSE FALSE      TRUE route_check
#>                  reason
#> 1 no calibration record
```
