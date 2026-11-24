# List registered embedding backends

List registered embedding backends

## Usage

``` r
gr_embedders()
```

## Value

A data frame with one row per embedder: `name`, `deterministic`
(`"TRUE"`/`"FALSE"`) and `description`. `deterministic` is the column
that matters for reproducibility: only a deterministic embedder lets a
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
reproduce a run's chunk ranking. The last two columns are `version` and
`contract`, `NA` for an embedder registered with
[`gr_register_embedder()`](https://elkronos.github.io/harnessr/reference/gr_register_embedder.md)
and filled for one registered with
[`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md).

## See also

[`gr_register_embedder()`](https://elkronos.github.io/harnessr/reference/gr_register_embedder.md),
[`gr_embed()`](https://elkronos.github.io/harnessr/reference/gr_embed.md),
[`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)

## Examples

``` r
gr_embedders()
#>      name deterministic
#> 1     api         FALSE
#> 2 lexical          TRUE
#>                                                    description version contract
#> 1                 Embeddings endpoint on the client's base URL    <NA>     <NA>
#> 2 Hashed bag-of-words; free, offline, word overlap not meaning    <NA>     <NA>
```
