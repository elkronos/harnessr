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
`"hr_options()"`), `default` (as text: a string without quotes, the
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
  [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md),
  [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md),
  [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md)
  and
  [`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)),
  leaving out the inputs a call works on (the documents, the client, the
  trace). Defaults are the functions' own, and descriptions the first
  sentence of each argument's help.

- `options`:

  Every
  [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
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
#>         30         10         21         34         50         33         20 
#> synthesise 
#>         29 
s[s$tier == "basic", c("stage", "name", "default")]
#>          stage           name                         default
#> 1       ingest            ocr                            auto
#> 3       ingest          clean                        standard
#> 7       ingest      min_chars                              20
#> 23     segment     max_tokens                            1200
#> 24     segment overlap_tokens                               0
#> 26     segment         method                       paragraph
#> 46        read         verify                           FALSE
#> 48        read         reader                      map_reduce
#> 49        read          model                            NULL
#> 54        read          top_k                               6
#> 64        read           cite                           FALSE
#> 85        read         recipe                        thorough
#> 86        read          store                            NULL
#> 88        read  max_total_usd                            NULL
#> 92      screen         recipe                        research
#> 94      screen  screen_tokens                            NULL
#> 96      screen  max_total_usd                            NULL
#> 103     screen              n                              50
#> 104     screen             of                        excluded
#> 112     screen  recall_target                            0.95
#> 113     screen           conf                            0.95
#> 116     screen  recall_target                            0.95
#> 117     screen           conf                            0.95
#> 118     screen     prevalence                            NULL
#> 122     screen         target                            0.95
#> 125    extract         recipe                        research
#> 127    extract        resolve                           first
#> 128    extract  require_quote                           FALSE
#> 135 synthesise          model                            NULL
#> 143 synthesise   max_sections                               6
#> 150 synthesise          model                            NULL
#> 154 synthesise     cite_style                            auto
#> 156 synthesise      coherence                           FALSE
#> 164   evaluate           runs                               5
#> 165   evaluate         scorer               hr_scorer_exact()
#> 167   evaluate       governor                            NULL
#> 171   evaluate           conf                            0.95
#> 174   evaluate         method                            auto
#> 178   evaluate           mode                          select
#> 179   evaluate          model                            NULL
#> 180   evaluate         orders                               2
#> 183   evaluate        recipes c("fast", "needle", "thorough")
#> 191   evaluate          parse                            exit
#> 194    options        verbose                            TRUE
#> 196    options          model                   gpt-5.6-terra
#> 209    options      cache_dir                            NULL
#> 213    options   max_cost_usd                               5
#> 214    options      max_calls                             400
gr_settings_table("synthesise")[, c("name", "default", "status")]
#>                  name                                   default   status
#> 1               model                                      NULL     <NA>
#> 2         temperature                                      NULL     <NA>
#> 3    max_claim_tokens                                      1600     <NA>
#> 4     include_unclear                                     FALSE     <NA>
#> 5              effort                                      NULL     <NA>
#> 6          unverified                                   exclude untested
#> 7               model                                      NULL     <NA>
#> 8         temperature                                      NULL     <NA>
#> 9        max_sections                                         6     <NA>
#> 10            closing                           What is missing     <NA>
#> 11 max_outline_tokens                                      NULL     <NA>
#> 12             effort                                      NULL     <NA>
#> 13       alternatives                                         1     <NA>
#> 14          max_cells                                        40     <NA>
#> 15       min_reported                                       0.5     <NA>
#> 16              model                                      NULL     <NA>
#> 17 max_section_tokens                                      1200     <NA>
#> 18        temperature                                      NULL     <NA>
#> 19    include_unclear                                     FALSE     <NA>
#> 20         cite_style                                      auto     <NA>
#> 21              style                                      NULL     <NA>
#> 22          coherence                                     FALSE untested
#> 23         references                                      TRUE     <NA>
#> 24             effort                                      NULL     <NA>
#> 25   coherence_rounds                                         1 untested
#> 26       figure_bands c(about = 0.1, over = 0.25, under = 0.25) untested
#> 27         prominence                c(top = 1/3, middle = 1/3) untested
#> 28      study_weights                                      NULL     <NA>
#> 29     revision_check                                   lexicon untested
```
