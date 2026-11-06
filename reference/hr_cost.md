# What one run of a module can cost

The return value of a module's `cost(input_stats, params)` function.
Counts are upper bounds for one run over the given input, except
`calls`, which is the number of model requests expected.

## Usage

``` r
hr_cost(
  calls,
  calls_max = calls,
  tokens_in_max = 0,
  tokens_out_max = 0,
  embed_max = 0,
  sends = list(),
  batched = TRUE
)
```

## Arguments

- calls:

  Model requests the run is expected to make.

- calls_max:

  Model requests it can make at worst. Never taken as less than `calls`
  once costs are summed.

- tokens_in_max:

  Prompt tokens the run sends beyond the input itself and the fixed
  prompt of each request: replies handed on to later merge or summary
  requests.

- tokens_out_max:

  Reply tokens the run can be billed for at worst. Zero leaves it to the
  pre-flight check, which prices every request at `input_stats$out_cap`,
  the largest reply cap the run's model is sent. A module whose replies
  can exceed that states its own bound here, and the check uses the
  larger of the two.

- embed_max:

  Requests to the embeddings endpoint.

- sends:

  Input every run must send, as a list of `list(tokens =, model =)`: a
  reader that sends every chunk sends at least their tokens to the model
  that reads them. Priced to refuse a run that cannot finish under the
  spending limit before it starts. `NULL` is the same as none.

- batched:

  Whether requests can go out in parallel batches, which cannot be
  stopped part way and so are held to their worst case.

## Value

An object of class `hr_cost`.

## See also

[`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)

## Examples

``` r
hr_cost(calls = 4, calls_max = 6)
#> $calls
#> [1] 4
#> 
#> $calls_max
#> [1] 6
#> 
#> $tokens_in_max
#> [1] 0
#> 
#> $tokens_out_max
#> [1] 0
#> 
#> $embed_max
#> [1] 0
#> 
#> $sends
#> list()
#> 
#> $batched
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "hr_cost"
```
