# Check that quoted evidence really is in the document

`ans$evidence` says what an answer rests on. For most readers those
spans are verbatim chunk text and are true by construction. For `skim`
they are what the model chose to write when asked to extract the
relevant passages. They are *presented* as quotations, and this is what
checks that they are.

## Usage

``` r
gr_verify_evidence(answer, chunks = NULL)
```

## Arguments

- answer:

  A
  [gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md).

- chunks:

  The
  [gr_chunks](https://elkronos.github.io/harnessr/reference/gr_chunks.md)
  the answer was read from. Needed for readers whose evidence is
  verbatim, where the comparison is against the chunk the span claims to
  come from: its `source_text` where the segmenter recorded one (the
  document text behind a chunk whose `text` carries model-written
  context or propositions), and its `text` otherwise. `skim` answers
  already carry their sources, so they can be checked without it; an
  `ensemble` needs it for the rows its verbatim members contributed,
  even though its `skim` rows do not.

  Pass the chunks the answer was actually read from. Chunk ids are
  positional, so a *different* chunk set of the same size will match on
  id and compare each span against unrelated text, reporting
  `verified = FALSE` for evidence that is perfectly sound. An id the
  chunk set does not contain reports `NA`, because there was nothing to
  compare against.

## Value

A data frame with one row per evidence span: `chunk_id`, `kind`
(`"verbatim"`, `"extracted"` or `"answer"`, **per row**; an `ensemble`
mixes them in one table, and the same value appears as the `kind` column
on `ans$evidence` itself), `verified`, `match` and `span` (the first 60
characters). `verified` is `NA` where the question does not apply: a
`map_reduce` evidence row is a per-chunk *answer*, not a quotation, and
asking whether it appears in the chunk is a category error.

For an `extract` answer, a quote has to carry the value it is cited for
as well as appear in the chunk, and only the reader can check the first:
it knows the value. A row the reader marked `verified = FALSE` for that
reason stays `FALSE` here, with a `match` of 1 when the sentence itself
is in the document. It is there, and it does not say this.

The `quote_*` columns come from a second matcher, recorded beside
`verified` and `match` and deciding nothing yet; see "The edit-distance
score" below.

## Details

A fabricated citation is more convincing than a fabricated answer,
because it looks like the thing that would let you check. Verification
is a string operation on text you already have, so it costs nothing and
there is no reason not to do it.

## What the numbers mean

`match` is 1 for an exact quotation once whitespace, quote marks, dashes
and case are folded away. These are the differences a faithful quotation
introduces. Guillemets and the corner brackets of Chinese and Japanese
count as quote marks, a full-width letter, digit or number sign as its
ASCII form, the ideographic space as a space, and a letter written with
combining accents (as macOS tools write text) as the accented letter,
for Latin, Greek, Cyrillic and Korean letters. harnessr does no other
Unicode normalisation, so a quotation that differs from its document
only in how some other letter is encoded is reported unverified, never
verified by mistake. It has to match whole words and whole numbers: "5%"
is not found in "25%", nor "12%" in "-12%", nor "20" in "200", nor "200"
in "1 200" written with a thin space, nor ".45" in "1.45", nor "65
years" in a range broken across two lines ("aged 18-" at the end of
one). A hyphen between two letters that the quotation writes and the
document does not, as where the cleaner joined a word broken at a line
end ("investigator-blinded"), is not a difference in a quotation of one
passage. Chinese, Japanese and Thai put no spaces between words, so a
clause quoted from them may start and end anywhere; numbers in them are
still whole, and a circled list number before one is not part of it.
That includes ending inside a word: a quotation that stops at a verb's
stem verifies where the document goes on to a negating ending written on
to it, as an English quotation that stops before "not" does, with or
without a full stop the model added. Markdown bold is not text, in the
quotation or the document. A span made of several passages (in
paragraphs, as a list, in separate quote marks, or joined by "..." or
"\[...\]") is checked passage by passage and is verified when every
passage is found, the parts either side of an elision in that order.
What an elision leaves out may not be a negation ("the drug did ...
reduce mortality" is not in "the drug did not reduce mortality"). That
is checked in the major European languages, Russian, Greek, Turkish,
Arabic, Hebrew, Hindi and Bengali by their negation words, and in
Chinese, Japanese, Korean and Thai by the characters and endings that
negate; what an elision leaves out in a script none of those cover is
refused. Where an elision leaves out the end of a sentence the part
after it has to start one ("Revenue ... rose 30%" is not in "Revenue
fell 12%. Costs rose 30%."); a full stop inside a bracketed citation
does not end one. A line break inside a sentence is a line wrap, not a
new passage: the lines are checked as one, even where the next line
opens with a capital, unless the document ends a sentence after the
first line or starts one with the second. Passages the quotation
separates (by a blank line, as a list, in quote marks) may come from
anywhere in the document, but not from one sentence with words left out
between them, which is an elision the quotation did not mark. None of
this reads meaning: a quotation that stops before a negation later in
its sentence still verifies, as it always has. Below 1 it is the
fraction of the span's words carried by its longest consecutive **run**
in the source, for the passage that matches worst; in a script written
without spaces, the fraction of its characters.

Read that number with its shape in mind. Because it measures a run,
*where* the change falls matters as much as how much changed: altering
the last word of a ten-word span leaves a run of nine and scores 0.9,
while altering a word in the middle splits the span and scores about
0.5. So a mid-sentence change (a swapped figure, the case this exists to
catch) lands near 0.5, not near 0.9. Below roughly 0.3 there is no
quotation left at all, only shared vocabulary. A run measure is still
the right one: word overlap cannot tell a quotation from a paraphrase
assembled out of the same words.

## The edit-distance score

The run measure above cannot be given a threshold, because the same edit
scores differently by where it falls. A second matcher is recorded next
to it for every span, so the two can be compared on real runs before the
default changes. It normalises both sides further than the check above:
ligatures and the long s expanded, JSON escapes undone, soft hyphens and
zero-width characters dropped, every full-width ASCII form folded, and a
word broken across a line with a hyphen joined, as is any hyphen between
two letters. It then finds the window of the source that the fewest
character edits turn the quotation into.

`quote_sim` is 1 minus those edits over the longer of the quotation and
the window, so it falls by the same step for each edit wherever it
falls. `quote_coverage` is the share of the quotation's words found in
order in the window, `quote_edits` the count, and `quote_critical_ok`
whether its numbers (with sign, a comparison sign before them and unit,
such as "-12%", "\< 0.05" or "45.2 million"), numbers written in words
("twelve") and negations are the window's, exactly. `quote_status` is
`"verbatim"` for no edit; `"near_verbatim"` for a similarity of at least
0.90 (0.95 under 40 characters) with the critical tokens identical and
five words or more; `"unverified"` otherwise; and `"not_checked"` where
there was nothing to compare, or where a passage was too long to score:
the edit table has a cell for each pair of characters, and a passage
whose length times the source's is over 5e7 is skipped. A quotation
split by an elision or a blank line takes the worst of its passages.
`near_verbatim` is not verified: a changed word that is not a number or
a negation ("Sheffield" for "Leipzig") can stay above the threshold.

## Citations

With `cite = TRUE` a reader asks the model to mark its sources as
`[chunk 3]`. Every answer is checked for citations pointing at chunks
that were never sent, whatever this function is called with; the result
is `ans$notes$cited_unknown`, and an answer carrying one is `partial`.
Lists and ranges are read (`[chunks 1, 2, and 9]`, `[chunks 1-9]`), and
a bracket that opens like a citation but cannot be read, such as
`[chunk nine]`, is listed in `ans$notes$cited_unparsed` and makes the
answer `partial` too.

## See also

[gr_answer](https://elkronos.github.io/harnessr/reference/gr_answer.md),
[`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md),
[`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)

## Examples

``` r
# A model that quotes faithfully.
honest <- gr_mock_client(function(messages, params) {
  txt <- messages[[length(messages)]]$content
  if (grepl("You extract evidence", messages[[1]]$content, fixed = TRUE)) {
    return("Revenue rose to 45.2 million dollars.")
  }
  "Revenue was 45.2 million dollars."
})

doc <- "Revenue rose to 45.2 million dollars.\n\nHeadcount grew to 1,204."
ch <- gr_segment(gr_ingest(doc), list(method = "paragraph", max_tokens = 40))
#> Ingested 2 block(s), ~26 tokens (0 chars removed by cleaning).
#> Segmenting with 'paragraph' (cap 40 tokens, overlap 0).
ans <- gr_read(ch, "What was revenue?", honest, "skim")
#> Reading with 'skim' (all|N+1|none) over 1 chunk(s).
gr_verify_evidence(ans)
#>   chunk_id      kind verified match quote_status quote_sim quote_coverage
#> 1        1 extracted     TRUE     1     verbatim         1              1
#>   quote_edits quote_critical_ok                                  span
#> 1           0              TRUE Revenue rose to 45.2 million dollars.

# A model that invents one. The span is fluent, plausible, and not in the
# document. That is exactly the case a reader cannot catch by eye.
liar <- gr_mock_client(function(messages, params) {
  if (grepl("You extract evidence", messages[[1]]$content, fixed = TRUE)) {
    return("Revenue rose to 88.9 billion dollars on record demand.")
  }
  "Revenue was 88.9 billion dollars."
})
bad <- gr_read(ch, "What was revenue?", liar, "skim")
#> Reading with 'skim' (all|N+1|none) over 1 chunk(s).
gr_verify_evidence(bad)
#>   chunk_id      kind verified match quote_status quote_sim quote_coverage
#> 1        1 extracted    FALSE 0.333   unverified    0.6792         0.4444
#>   quote_edits quote_critical_ok
#> 1          17             FALSE
#>                                                     span
#> 1 Revenue rose to 88.9 billion dollars on record demand.
bad$partial
#> [1] TRUE
```
