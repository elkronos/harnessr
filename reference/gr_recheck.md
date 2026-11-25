# Check and render an edited write-up again

[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
keeps `$text_marked`, the write-up with its `[study N]` markers, so that
the checks can be run again on the text as published. Edit that text, by
hand or with another tool, and pass it here: every check that reads the
text runs on it again, and the citations and the reference list are
rendered from it as
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
renders them. Nothing is sent to a model.

## Usage

``` r
gr_recheck(synthesis, text_marked = synthesis$text_marked)
```

## Arguments

- synthesis:

  A
  [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  result.

- text_marked:

  The edited write-up, in the marker form of `synthesis$text_marked`:
  citations as `[study N]`, sections under `## ` headings, and no
  reference list (one is appended from what it cites). Defaults to
  `synthesis$text_marked`, which renders the write-up again.

## Value

The `gr_synthesis`, with `text_marked` the edited text, `text` rendered
from it, and `references`, `figures`, `sentences`, `uncited` and
`contradictions` worked out again, and `recheck`, a list of `unknown`
(studies cited that are not in the table), `unsupplied` (studies cited
under a heading whose section was not shown them) and `unparsed`
(citations the check cannot read).

## Details

The checks are those of
[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md).
A marker naming a row that does not exist, or a study the section under
whose heading it stands was not shown, is left as a marker and counted;
one the check cannot read is counted. Each is warned about
(`gr_recheck_citations`). A heading the write-up did not have is checked
against every study any section was shown. A study cited honestly under
one heading keeps its rendered citation and its reference even where
another heading cites it without being shown it. The figures are checked
against the rows their sentence cites, with the `style` and
`figure_bands` the write-up was made with, as the revised text of a
write-up is (`stage` `"edited"` in `$figures`); the sentences are linked
to verified records again; and `$uncited` and `$contradictions` are
worked out again. The sections, their counts and `$draft` are left as
written: they describe the draft, not the edit. For a synthesis saved
before `$section_studies` was kept, `shown` in `$uncited` is `NA`, since
what each section was shown is not known. A synthesis saved by an
earlier version comes back with the fields added since filled with their
defaults: no studies lost or left unrendered, and the citation style and
bibliographic columns it was written with.

## See also

[`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)

## Examples

``` r
tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok",
                  n_filled = 1L, n_unverified = 0L, n = c(120L, 300L))
cl <- hr_mock_client(function(messages, params) "One trial enrolled 120 people [study 1].")
s <- gr_synthesise(tab, question = "How large were the trials?",
                   outline = c(Findings = "Sample sizes"), client = cl)
#> [1/1] Findings
edited <- paste0(s$text_marked, " Another enrolled 300 [study 2]. A third [study 9].")
r <- suppressWarnings(gr_recheck(s, edited))
r$recheck$unknown
#> [1] 9
r$uncited
#> [1] study       document    document_id shown      
#> <0 rows> (or 0-length row.names)
```
