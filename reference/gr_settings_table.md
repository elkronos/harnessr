# Every setting of every stage

One table of every setting harnessr has, across the stages of a run:
ingesting a file, cutting it into chunks, reading it, screening,
extracting and writing a review, evaluating, and the session's options.
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)
prints it, grouped by stage.

## Usage

``` r
gr_settings_table(stage = NULL)
```

## Arguments

- stage:

  `NULL` for every stage, or one or more of `"ingest"`, `"segment"`,
  `"read"`, `"screen"`, `"extract"`, `"synthesise"`, `"evaluate"` and
  `"options"`.

## Value

A data frame with one row per setting and the columns `stage`, `name`,
`where` (the function that takes it, as `"gr_read_spec()"`, or
`"gr_options()"`), `default` (as text: a string without quotes, the
first choice of a set of choices, other values as R code), `tier`
(`"basic"` for the few settings most runs change, else `"advanced"`),
`status` and `source` (where the default came from: `"measured"`,
`"cited"` or `"untested"` and why, `NA` when nothing is declared),
`description`, and `guide`, the guide section that explains how to
choose it, as `"readers#set-top-k"` (the article, then the section's
id), or `NA`.

## Details

The table is built when it is asked for, from what declares each
setting, so it says what the installed code does:

- `ingest`, `segment`, `read`:

  The schemas of
  [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md),
  [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  and
  [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  (see
  [`gr_settings()`](https://elkronos.github.io/harnessr/reference/gr_settings.md)),
  with their defaults, tiers and evidence. The ingest stage adds the
  entries of `cleaner_opts` and `layout_opts` the built-in code reads,
  as `cleaner_opts.references_after` and so on, and the read stage adds
  the arguments of
  [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md).

- `screen`, `extract`, `synthesise`, `evaluate`:

  The arguments of the functions of each stage
  ([`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md),
  [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
  [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
  [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
  and
  [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md);
  [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md);
  [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md),
  [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md),
  [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
  and
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md);
  [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md),
  [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md),
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  and
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)),
  leaving out the inputs a call works on (the documents, the client, the
  trace). Defaults are the functions' own, and descriptions the first
  sentence of each argument's help.

- `options`:

  Every
  [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
  option, with its default, the evidence its rule declares, and the
  first sentence of its entry in the help page.

Descriptions come from the installed help pages; where they cannot be
read, `description` is `NA`.

## See also

[`gr_settings()`](https://elkronos.github.io/harnessr/reference/gr_settings.md)
for one spec's schema,
[`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
to test a setting,
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md)

## Examples

``` r
s <- gr_settings_table()
table(s$stage)
#> 
#>   evaluate    extract     ingest    options       read     screen    segment 
#>         22          9         19         34         40         30         14 
#> synthesise 
#>         27 
s[s$tier == "basic", c("stage", "name", "default")]
#>          stage           name                         default
#> 1       ingest            ocr                            auto
#> 3       ingest          clean                        standard
#> 7       ingest      min_chars                              20
#> 21     segment     max_tokens                            1200
#> 22     segment overlap_tokens                               0
#> 24     segment         method                       paragraph
#> 38        read         verify                           FALSE
#> 40        read         reader                      map_reduce
#> 41        read          model                            NULL
#> 46        read          top_k                               6
#> 56        read           cite                           FALSE
#> 67        read         recipe                        thorough
#> 68        read          store                            NULL
#> 70        read  max_total_usd                            NULL
#> 74      screen         recipe                        research
#> 76      screen  screen_tokens                            NULL
#> 78      screen  max_total_usd                            NULL
#> 82      screen              n                              50
#> 83      screen             of                        excluded
#> 91      screen  recall_target                            0.95
#> 92      screen           conf                            0.95
#> 95      screen  recall_target                            0.95
#> 96      screen           conf                            0.95
#> 97      screen     prevalence                            NULL
#> 101     screen         target                            0.95
#> 104    extract         recipe                        research
#> 106    extract        resolve                           first
#> 107    extract  require_quote                           FALSE
#> 113 synthesise          model                            NULL
#> 120 synthesise   max_sections                               6
#> 127 synthesise          model                            NULL
#> 131 synthesise     cite_style                            auto
#> 133 synthesise      coherence                           FALSE
#> 140   evaluate           runs                               5
#> 141   evaluate         scorer               hr_scorer_exact()
#> 143   evaluate       governor                            NULL
#> 147   evaluate           conf                            0.95
#> 150   evaluate         method                            auto
#> 154   evaluate           mode                          select
#> 155   evaluate          model                            NULL
#> 156   evaluate         orders                               2
#> 159   evaluate        recipes c("fast", "needle", "thorough")
#> 162    options        verbose                            TRUE
#> 164    options          model                   gpt-5.6-terra
#> 177    options      cache_dir                            NULL
#> 181    options   max_cost_usd                               5
#> 182    options      max_calls                             400
gr_settings_table("synthesise")[, c("name", "default", "status")]
#>                  name                                   default   status
#> 1               model                                      NULL     <NA>
#> 2         temperature                                      NULL     <NA>
#> 3    max_claim_tokens                                      1600     <NA>
#> 4     include_unclear                                     FALSE     <NA>
#> 5              effort                                      NULL     <NA>
#> 6               model                                      NULL     <NA>
#> 7         temperature                                      NULL     <NA>
#> 8        max_sections                                         6     <NA>
#> 9             closing                           What is missing     <NA>
#> 10 max_outline_tokens                                      NULL     <NA>
#> 11             effort                                      NULL     <NA>
#> 12       alternatives                                         1     <NA>
#> 13          max_cells                                        40     <NA>
#> 14       min_reported                                       0.5     <NA>
#> 15              model                                      NULL     <NA>
#> 16 max_section_tokens                                      1200     <NA>
#> 17        temperature                                      NULL     <NA>
#> 18    include_unclear                                     FALSE     <NA>
#> 19         cite_style                                      auto     <NA>
#> 20              style                                      NULL     <NA>
#> 21          coherence                                     FALSE untested
#> 22         references                                      TRUE     <NA>
#> 23             effort                                      NULL     <NA>
#> 24   coherence_rounds                                         1 untested
#> 25       figure_bands c(about = 0.1, over = 0.25, under = 0.25) untested
#> 26         prominence                c(top = 1/3, middle = 1/3) untested
#> 27      study_weights                                      NULL     <NA>
```
