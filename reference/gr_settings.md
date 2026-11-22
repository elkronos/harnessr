# The settings of a read, segment or ingest spec

Returns the schema
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
or
[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
checks its arguments against: every setting with its type, default,
range, tier and where its default came from. Printed, it lists each
setting's tier (`basic` for the few most runs change, `advanced` for the
rest) and evidence status (`"measured"`, `"cited"` or `"untested"`);
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) adds the
default, the help line and the source the status rests on. Use it to see
what a comparison can vary before building arms with
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md).

## Usage

``` r
gr_settings(module = c("read", "segment", "ingest"))
```

## Arguments

- module:

  `"read"`, `"segment"` or `"ingest"`.

## Value

An
[`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md).

## See also

[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md),
[`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md),
[`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md),
[`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md),
[`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)

## Examples

``` r
gr_settings("segment")
#> <hr_schema> 20 parameter(s)
#>   context_source             enum          advanced  untested  metadata|llm
#>   max_tokens                 integer       basic     untested  [32, 1e+06]
#>   overlap_tokens             integer       basic     untested  [0, f()]
#>   min_tokens                 integer       advanced  untested  [0, f()]
#>   method                     module_ref    basic     untested  
#>   separators                 string_vector advanced  untested  
#>   prefix_section             boolean       advanced  untested  
#>   semantic_window            integer       advanced  untested  [1, 10]
#>   semantic_percentile        number        advanced  untested  [50, 99.5]
#>   proposition_batch_tokens   integer       advanced  untested  [200, 4000]
#>   parallel                   boolean       advanced  untested  
#>   context_reply_tokens       integer       advanced  untested  [16, 4000]
#>   context_document_tokens    integer       advanced  untested  [100, 1e+06]
#>   proposition_reply_tokens   integer       advanced  untested  [100, 1e+06]
#>   semantic_threshold         enum          advanced  untested  percentile|texttiling
#>   table_packing              enum          advanced  untested  rows|grouped
#>   proposition_check          enum          advanced  untested  count|drop
#>   proposition_context_tokens integer       advanced  untested  [0, 2000]
#>   packing                    enum          advanced  untested  greedy|balanced
#>   runt_merge                 enum          advanced  untested  backward|both
s <- as.data.frame(gr_settings("read"))
s[s$tier == "basic", c("name", "default", "status")]
#>      name    default   status
#> 5  verify      FALSE untested
#> 7  reader map_reduce untested
#> 8   model       NULL untested
#> 13  top_k          6 untested
#> 23   cite      FALSE untested
```
