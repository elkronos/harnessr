# Measure a search against papers you already know are relevant

Known-item recall: the share of a seed set of relevant papers that a
search returned. Each seed is matched to the search's records by the
rules
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
uses to find duplicates, so a seed counts as found when those rules
would call it the same work as one of the records. The figure comes with
an exact (Clopper-Pearson) interval from
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md),
overall and for each tier when `tier` is given.

## Usage

``` r
gr_search_recall(records, known, tier = NULL, held_out = NULL, conf = 0.95)
```

## Arguments

- records:

  The search's results: a
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
  or a data frame with its columns (`title`, `year`, `doi`, `authors`
  and `venue` are the ones used). Every row counts, duplicates included.

- known:

  The seed set: a
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  read from an export of the papers, or a data frame with `doi`, or
  `title` and `year`, and where it has them `authors` and `venue`. A
  logical `used_to_build` column marks the seeds used to write the
  search. An empty seed set is refused. A row whose `duplicate_of` names
  another seed's `record_id` (two exports of one paper, as
  [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  marks them) is a copy of that seed: the paper is counted once, as used
  to build the search when any copy is, and the copy is listed in
  `$copies`.

- tier:

  `NULL`, the name of a column of `known`, or one value per seed: a
  grouping set by a person (say, core papers and the rest), to report
  recall for each group as well as overall. A single string is always
  read as a column name, even with one seed. A seed without a tier, a
  tier with no seed (an unused factor level), a tier left with no seed
  once the seeds used to build the search are out, and copies of one
  paper given different tiers are refused.

- held_out:

  `NULL`, or the seeds kept out of the search: a logical vector with one
  value per seed, or their row numbers. Every other seed is counted as
  used to build the search. A seed marked both `held_out` and
  `used_to_build` is refused.

- conf:

  Confidence level of the intervals.

## Value

An object of class `gr_search_recall`:

- `recall`:

  One row for all seeds (`tier` is `"all"`) and one per tier: `found`,
  `n` (seeds counted), `estimate`, `lower`, `upper`, `method`
  (`"clopper_pearson"`) and `conf`.

- `seeds`:

  One row per distinct seed: `seed` (its row in `known`), `label`,
  `tier`, `used_to_build`, `found` (`NA` for a seed left out),
  `record_id` (the record it matched) and `reason`.

- `missed`:

  The seeds counted and not found, with `reason`.

- `refused`:

  The missed seeds the matching rules refused, as described above.

- `excluded`:

  The seeds left out as used to build the search.

- `copies`:

  The rows of `known` that are copies of another seed: `seed` (the
  copy's row) and `copy_of` (the row it is a copy of).

- `note`:

  The sentence saying what the figure is relative to.

## Details

Nothing here calls a model.

## Relative recall

The figure is recall relative to the seed set: the share of the papers
you already knew that the search found, not the share of every relevant
paper that exists. Seeds are rarely a random sample of the relevant
literature. They tend to be the well-known, well-indexed papers a search
finds most easily, so the figure is usually higher than recall against
everything relevant. Report it as relative recall, with the number of
seeds and how they were chosen, as PRISMA-S asks a review to describe
how its search was tested.

A seed used to write the search (to pick its terms, or to test drafts of
it) is found because the search was built to find it. Mark those with a
logical `used_to_build` column in `known`, or give the seeds kept out of
the search in `held_out`. They are left out of the figure and listed in
`$excluded`.

## Seeds that cannot be matched

A seed is matched exactly as
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
merges duplicates (see its `dedupe` argument, `"doi+title"`): by DOI, or
by title and year with the first author or the venue agreeing. Where
those rules refuse a match, the seed counts as not found, and `$missed`
says why in `reason`:

- `"short_title"`:

  A record has the seed's title and year, but the title has fewer than
  12 letters or digits ("Reply", "Editorial"), which the rules never
  match on.

- `"multi_doi"`:

  Records with the seed's title and year carry two or more different
  DOIs between them and the seed, so the title cannot say which work the
  seed is.

- `"not_confirmed"`:

  A record has the seed's title and year, but the first author or the
  venue disagrees, nothing beyond the title confirms it, or it could be
  either of two records.

- `"no_identifier"`:

  The seed has no DOI and no title with a year.

- `"not_in_records"`:

  No record has the seed's DOI, or its title and year.

The first three are listed again in `$refused`: a search that returned
the paper under another record can show as a miss there, and a person
should look at those rows before the figure is reported.

## References

Sampson, M., Zhang, L., Morrison, A., Barrowman, N. J., Clifford, T. J.,
Platt, R. W., Klassen, T. P. and Moher, D. (2006). An alternative to the
hand searching gold standard: validating methodological search filters
using relative recall. *BMC Medical Research Methodology* 6, 33.

Rethlefsen, M. L., Kirtley, S., Waffenschmidt, S., Ayala, A. P., Moher,
D., Page, M. J., Koffel, J. B. and PRISMA-S Group (2021). PRISMA-S: an
extension to the PRISMA Statement for Reporting Literature Searches in
Systematic Reviews. *Systematic Reviews* 10, 39.

Clopper, C. J. and Pearson, E. S. (1934). The use of confidence or
fiducial limits illustrated in the case of the binomial. *Biometrika*
26(4), 404-413.

## See also

[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md),
[`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md),
[`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)

Other corpus functions:
[`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md),
[`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md),
[`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md),
[`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md),
[`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md),
[`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md),
[`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md),
[`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)

## Examples

``` r
found <- data.frame(
  title = c("Spaced practice and long-term retention in adults",
            "Retrieval practice in the classroom: a field trial",
            "Interleaving mathematics problems improves test scores"),
  year = c("2019", "2021", "2015"),
  doi = c("10.1000/sp1", NA, "10.1000/il3"),
  authors = c("Smith, J.", "Okafor, A.", "Lee, K."),
  stringsAsFactors = FALSE)
seeds <- data.frame(
  title = c("Spaced practice and long-term retention in adults",
            "Retrieval practice in the classroom: a field trial",
            "Sleep and memory consolidation in students",
            "Interleaving mathematics problems improves test scores"),
  year = c("2019", "2021", "2020", "2015"),
  doi = c(NA, NA, "10.1000/sl9", "10.1000/il3"),
  authors = c("Smith, J.", "Okafor, A.", "Diaz, M.", "Lee, K."),
  used_to_build = c(FALSE, FALSE, FALSE, TRUE),
  tier = c("core", "core", "other", "other"),
  stringsAsFactors = FALSE)
r <- gr_search_recall(found, seeds, tier = "tier")
r
#> <gr_search_recall> 2 of 3 seed(s) found among 3 record(s)
#>   all              2/3    66.7%  [9.4%, 99.2%]
#>   core             2/2   100.0%  [15.8%, 100.0%]
#>   other            0/1     0.0%  [0.0%, 97.5%]
#>   (95% Clopper-Pearson intervals)
#>   Recall is relative to the seed set: the share of the papers already known
#>   to be relevant that the search found, not the share of every relevant
#>   paper.
#>   1 seed(s) used to build the search are left out (see $excluded)
#>     missed: Diaz 2020: Sleep and memory consolidation in students (not_in_records)
r$missed
#>   seed                                                 label  tier
#> 1    3 Diaz 2020: Sleep and memory consolidation in students other
#>   used_to_build found record_id         reason
#> 1         FALSE FALSE        NA not_in_records
```
