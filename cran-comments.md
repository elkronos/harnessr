## Test environments

* Ubuntu 24.04, R 4.3.3 (development container)
* GitHub Actions, via `r-lib/actions/check-r-package`: ubuntu-latest with
  R release and R oldrel-1, and macOS-latest with R release

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes for the reviewer

This package talks to language-model APIs. Nothing in the checked material makes
a network request:

* Every example that would reach an endpoint is wrapped in `\dontrun{}`. The
  rest use `hr_mock_client()`, a client whose handler is an ordinary R function,
  so they run offline and deterministically.
* The test suite (1040 tests) uses the same mock throughout and sets no API key.
* The vignette is built against the mock client, with
  `hr_options(embedder = "lexical")` for a deterministic embedding backend, so
  it compiles with no key and no network.

Files are written only under `tempdir()`. The response cache
(`hr_cache()`) defaults to a directory under `tempdir()` and creates it on first
write; a persistent location is opt-in via `hr_options(cache_dir = )`, and the
documentation suggests `tools::R_user_dir("harnessr", "cache")` for it.

`ellmer` is a suggested dependency used by a single exported function,
`hr_ellmer_client()`; its tests are guarded with `skip_if_not_installed()`.
