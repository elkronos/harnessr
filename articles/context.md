# Context: budgets, fitting and cutting

A model reads the prompt and writes the reply inside one context window.
When the text you want to send is longer than the window allows,
harnessr gives you three tools to keep the request inside it:

- [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
  works out how many tokens the prompt may hold.
- [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
  fits named pieces of a prompt into that number, under the rules of an
  [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md).
- [`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
  and
  [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
  cut one piece to a number of tokens, keeping the part you choose.

Every cut can be written to the trace, so the trace records what a run
left out.

harnessr does not summarise or compact a conversation. Each call is one
request with the messages you pass it, and nothing carries over from the
call before. A prompt that is too long is cut by the rules below, and
the cut is recorded; nothing is rewritten in fewer words unless you
build a step that does it (see [Summarising is a step you
build](#summarise)).

Every example runs offline with no API key.

## Setting up

``` r

library(harnessr)
old <- hr_options(verbose = FALSE)
```

[`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
returns the values it replaced, and the last chunk of this guide puts
them back with `hr_options(old)`.

The examples use a model with a 300-token window, so that a short report
overflows it. The arithmetic is the same at 128,000 tokens. The prices
are illustrative and appear only so that no unpriced-model warning
interrupts the output:

``` r

# Illustrative figures, in USD per million tokens.
hr_register_model("small-reader", context_window = 300, max_output = 100,
                  input_usd = 0.5, output_usd = 1.5)
```

## What a call does with a long prompt

[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
does not cut a prompt. It counts the prompt’s tokens and holds the
reply’s cap to the room the window leaves, less 32 tokens of slack. The
stand-in below replies with the cap it was given:

``` r

cap_seen <- hr_mock_client(function(messages, params) paste("cap:", params$max_output))
long_prompt <- paste(rep("word", 195), collapse = " ")
hr_count_tokens(long_prompt)
#> [1] 198
hr_call(cap_seen, long_prompt, model = "small-reader")$text
#> [1] "cap: 70"
```

A 198-token prompt leaves 300 less 198 less 32, so 70 tokens for the
reply, not the model’s 100.

When the prompt leaves no room at all,
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
sends nothing. The result has `ok = FALSE`, `status` 0 and an error that
gives the counts:

``` r

tr <- hr_trace()
res <- hr_call(cap_seen, paste(rep("word", 400), collapse = " "),
               model = "small-reader", trace = tr)
str(res[c("ok", "status")])
#> List of 2
#>  $ ok    : logi FALSE
#>  $ status: int 0
res$error
#> [1] "Prompt is 403 tokens but 'small-reader' has a 300-token context window, leaving no room for a reply. Segment more aggressively (lower `max_tokens` on the segmenter) or use a larger-context model."
```

The trace records the failed call as an error, with no tokens spent. To
avoid both a squeezed reply and a request that never goes out, decide
what the prompt holds before the call: budget it with
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
and fit it with
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md).

## How much room a prompt has: `hr_budget()`

[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
does the context arithmetic for one model:

``` r

bud <- hr_budget("small-reader")
str(bud)
#> List of 6
#>  $ input         : int 170
#>  $ output        : int 100
#>  $ context_window: int 300
#>  $ overhead      : int 0
#>  $ margin        : num 0.1
#>  $ certain       : logi TRUE
```

The figures come from four steps:

1.  The usable window is the context window less `safety_margin`, a
    tenth by default: `floor(300 * 0.9)` is 270. The margin absorbs the
    error of counting tokens locally (see
    [`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)).
2.  The reply’s reserve, `output`, is the `reserve_output` you give,
    held between 1 token and the model’s output cap. Without one, it is
    a quarter of the usable window (`output_reserve_share`), raised to
    at least `min_output_tokens` (256) and held to the model’s output
    cap. Here a quarter is 67, the floor raises it to 256, and the cap
    of 100 holds it at 100.
3.  `overhead` is the tokens of the prompt you count yourself and do not
    want budgeted: a system prompt, a question, message framing. It is 0
    unless you give it.
4.  `input` is what is left: 270 less 100 less 0, so 170 tokens.

`certain` is `TRUE` because the registry knows the model. For a model it
has to guess, `certain` is `FALSE` and the budget rests on guessed
limits.

On a large model the same call leaves far more room. With an explicit
reserve and 200 tokens of overhead:

``` r

unlist(hr_budget("gpt-4o", reserve_output = 1024, overhead = 200))
#>          input         output context_window       overhead         margin 
#>       113976.0         1024.0       128000.0          200.0            0.1 
#>        certain 
#>            1.0
```

### The three guarantees

[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
promises three things:

- `input` is always a positive whole number.
- `input + output + overhead` never exceeds the usable window,
  `context_window * (1 - safety_margin)`.
- When no positive budget exists, it stops with an error of class
  `gr_budget_error` that names what to change. It never returns a
  negative number for code downstream to loop on.

Before it gives up, it lowers the reply’s reserve to
`min_output_tokens`. On gpt-4, with an 8,192-token window, 7,000 tokens
of overhead leave no room for the default reserve of 1,843, so the
reserve drops to 256 and 116 tokens are left for input:

``` r

unlist(hr_budget("gpt-4", overhead = 7000)[c("input", "output", "overhead")])
#>    input   output overhead 
#>      116      256     7000
```

At 9,000 tokens of overhead nothing is left, and the error says why:

``` r

tryCatch(hr_budget("gpt-4", overhead = 9000),
         gr_budget_error = function(e) conditionMessage(e))
#> [1] "No positive input budget for model 'gpt-4': context 8192, usable after a 10% safety margin 7372, output reserve 256, fixed overhead 9000. Reduce `reserve_output`, shorten the question/system prompt, or use a model with a larger context window."
```

An overhead that cannot be read as a number is the same error, since
budgeting it as zero is the direction that overruns the window. A
`reserve_output` that cannot be read warns with class `gr_bad_setting`
and takes the default reserve, and a `safety_margin` outside 0 to 0.5 is
held to that range with a warning:

``` r

tryCatch(hr_budget("gpt-4", overhead = NA),
         gr_budget_error = function(e) class(e)[1])
#> [1] "gr_budget_error"
unlist(suppressWarnings(hr_budget("gpt-4", safety_margin = 0.9))[c("input", "margin")])
#>  input margin 
#> 3072.0    0.5
```

[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
counts no text. It knows only the model’s limits and the numbers you
give it, so the overhead is yours to count, with
[`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md).
It does not check the provider’s count either: a prompt that fits by the
local count can still be a few tokens over by the provider’s, which is
what the margin is for.

## Fitting pieces into a budget: `hr_context_fit()`

A prompt is usually built from parts: instructions, a question, notes
from an earlier step, an excerpt of a document.
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
takes them as a named character vector, in the order the prompt carries
them, and cuts them until their total fits the budget.

Here is a report whose last paragraph restates the revenue figure, and a
prompt built around it:

``` r

report <- paste(c(
  "Acme Ltd annual report, fiscal 2024.",
  "The board met eleven times during the year and approved a new audit charter.",
  "Staff numbers rose from 410 to 452, mostly in the logistics division.",
  "Revenue for fiscal 2024 was 45.2 million dollars, up from 38.1 million.",
  "The company opened two warehouses, in Leeds and in Rotterdam.",
  "Energy costs fell by 6 percent after a supplier change in March.",
  "Note 14 restates fiscal 2024 revenue as 44.9 million dollars."),
  collapse = "\n\n")
pieces <- c(
  instructions = "Answer from the report only. Quote the figure you use.",
  question = "What was revenue in fiscal 2024?",
  notes = paste("Earlier reading: revenue figures appear in the results section",
                "and may be restated in the notes. The 2023 figure was 38.1",
                "million dollars."),
  excerpt = report)
hr_count_tokens(pieces)
#> [1]  15  14  40 122
sum(hr_count_tokens(pieces))
#> [1] 191
```

The pieces hold 191 tokens against a budget of 170. Under the default
policy:

``` r

fit <- hr_context_fit(pieces, bud$input)
fit[c("fits", "tokens", "cut", "tokens_dropped")]
#> $fits
#> [1] TRUE
#> 
#> $tokens
#> [1] 166
#> 
#> $cut
#> [1] "excerpt"
#> 
#> $tokens_dropped
#> [1] 25
cat(fit$pieces[["excerpt"]])
#> Acme Ltd annual report, fiscal 2024.
#> 
#> The board met eleven times during the year and approved a new audit charter.
#> 
#> Staff numbers rose from 410 to 452, mostly in the logistics division.
#> 
#> Revenue for fiscal 2024 was 45.2 million dollars, up from 38.1 million.
#> 
#> The company opened two warehouses, in Leeds and in Rotterdam.
#> 
#> Energy costs fell by ...[truncated]
```

The result is a list:

- `pieces`: the pieces after cutting, named and in the order given. A
  piece cut away entirely is `""`.
- `fits`: whether the total is now within the budget.
- `tokens`: the total after cutting.
- `cut`: the names of the pieces that were cut, in the order they were
  cut.
- `tokens_dropped`: the tokens the cuts saved, the source text removed
  less the marker put in its place. The trace counts a cut differently
  (see [the trace’s truncate steps](#trace-steps)), so its figure for
  the same cut is larger by the marker’s tokens.

The default policy pins `question` and `instructions`, so neither is
cut. Of the other pieces, the last one in the prompt goes first: the
excerpt. It is cut only as far as the total needs, rounded to a whole
word, so it loses 25 tokens and keeps its start. The notes are
untouched, since cutting the excerpt was enough.

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
counts each piece on its own. With the default counter each count
includes 3 tokens for the framing of a message, so the pieces joined
into one prompt count a little less, and a fit errs on the safe side:

``` r

prompt <- paste(fit$pieces[nzchar(fit$pieces)], collapse = "\n\n")
hr_count_tokens(prompt)
#> [1] 155
```

### When the pinned pieces alone do not fit

A pinned piece is never cut. When the pinned pieces are larger than the
budget,
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
cuts every other piece to `""` and reports `fits = FALSE`:

``` r

tight <- hr_context_fit(pieces, 25)
tight[c("fits", "tokens", "cut")]
#> $fits
#> [1] FALSE
#> 
#> $tokens
#> [1] 29
#> 
#> $cut
#> [1] "excerpt" "notes"
```

It does not raise an error, and it does not cut a pinned piece to make
room. The decision is yours: stop, send the request with a smaller reply
reserve, or move to a model with a larger window.

[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
also takes the pieces as a named list of single strings, and reads an
`NA` piece as `""`. It stops with an error of class `gr_bad_setting`
when a piece has no name or two pieces share one, when the policy does
not come from
[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md),
or when the budget is not a number of 0 or more.

## Choosing what gets cut: `hr_context_policy()`

A policy says which pieces are never cut, which are cut first, and which
part of a cut piece is kept. The default:

``` r

hr_context_policy()
#> <hr_context_policy>
#>   pin:          question, instructions
#>   cut first:    -
#>   keep:         head
#>   order merges: FALSE
```

It has four arguments:

- `pin`: names of pieces that are never cut. The default pins
  `"question"` and `"instructions"`.
- `cut_order`: names of pieces to cut first, in that order. The pieces
  it does not name are cut after them, the last piece of the prompt
  first.
- `keep`: which part of a cut piece is kept, `"head"`, `"tail"`,
  `"both"` or `"scored"` (see [Cutting one piece](#truncate)). One rule
  applies to every piece; a named vector sets a rule per piece, with one
  unnamed element as the rule for the rest.
- `order_merges`: read only by the document layer’s merge packers, which
  then place findings by the read’s `context_order`.
  [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
  ignores it.

A name in `pin` or `cut_order` that matches no piece is ignored, so one
policy can serve prompts with different pieces. A piece with no rule of
its own and no unnamed rule is cut with `"head"`, and a piece whose rule
is `"scored"` but that has no scores is cut with `"head"` too.

``` r

p <- hr_context_policy(pin = "question", cut_order = c("notes", "excerpt"),
                       keep = c(excerpt = "both", "tail"))
p
#> <hr_context_policy>
#>   pin:          question
#>   cut first:    notes, excerpt
#>   keep:         excerpt = both, tail
#>   order merges: FALSE
```

[`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)
checks its arguments. A piece both pinned and in `cut_order`, two
unnamed keep rules, or a rule that does not exist is an error of class
`gr_bad_setting`:

``` r

tryCatch(hr_context_policy(pin = "notes", cut_order = "notes"),
         error = conditionMessage)
#> [1] "'notes' is both pinned and in `cut_order`; a pinned piece is never cut."
tryCatch(hr_context_policy(keep = "middle"), error = conditionMessage)
#> [1] "`keep` must be one or more of \"head\", \"tail\", \"both\", \"scored\", named by piece."
```

### One prompt, five policies

The report’s answer depends on its last paragraph. A stand-in for the
model shows which figure each prompt carries: it answers with the
restated figure when the prompt holds it, else the first figure, else
that the figure is missing.

``` r

reader <- hr_mock_client(function(messages, params) {
  p <- messages[[length(messages)]]$content
  if (grepl("44.9", p, fixed = TRUE)) "44.9 million dollars, as restated in note 14."
  else if (grepl("45.2", p, fixed = TRUE)) "45.2 million dollars."
  else "The excerpt does not give the figure."
})
ask <- function(fit) {
  prompt <- paste(fit$pieces[nzchar(fit$pieces)], collapse = "\n\n")
  hr_call(reader, prompt, model = "small-reader")$text
}
```

`"scored"` needs a score per unit of the excerpt. Here a paragraph
scores 1 when it mentions revenue; in a real run the score could come
from a retriever’s ranking. Five policies, one budget:

``` r

paragraphs <- strsplit(report, "\n\n", fixed = TRUE)[[1]]
scores <- list(excerpt = as.numeric(grepl("revenue", paragraphs, ignore.case = TRUE)))
policies <- list(
  default     = hr_context_policy(),
  notes_first = hr_context_policy(cut_order = "notes"),
  tail        = hr_context_policy(keep = c(excerpt = "tail", "head")),
  both        = hr_context_policy(keep = c(excerpt = "both", "head")),
  scored      = hr_context_policy(keep = c(excerpt = "scored", "head")))
fits <- lapply(policies, function(pol) hr_context_fit(pieces, bud$input, pol, scores = scores))
data.frame(cut = vapply(fits, function(f) paste(f$cut, collapse = ", "), ""),
           dropped = vapply(fits, `[[`, 0, "tokens_dropped"),
           answer = vapply(fits, ask, ""))
#>                 cut dropped                                        answer
#> default     excerpt      25                         45.2 million dollars.
#> notes_first   notes      26 44.9 million dollars, as restated in note 14.
#> tail        excerpt      26 44.9 million dollars, as restated in note 14.
#> both        excerpt      27 44.9 million dollars, as restated in note 14.
#> scored      excerpt      26 44.9 million dollars, as restated in note 14.
```

Under the default, the excerpt loses its end and with it the
restatement, so the model sees only 45.2 million. Each other choice
keeps the restatement, and each pays for it somewhere else:

- `notes_first` cuts the notes instead and keeps the whole excerpt. The
  notes lose their end, the 2023 figure among it.

``` r

cat(fits$notes_first$pieces[["notes"]])
#> Earlier reading: revenue figures ...[truncated]
```

- `tail` keeps the end of the excerpt and loses the start, where a
  report names the company and the year.

``` r

cat(fits$tail$pieces[["excerpt"]])
#> ...[truncated] numbers rose from 410 to 452, mostly in the logistics division.
#> 
#> Revenue for fiscal 2024 was 45.2 million dollars, up from 38.1 million.
#> 
#> The company opened two warehouses, in Leeds and in Rotterdam.
#> 
#> Energy costs fell by 6 percent after a supplier change in March.
#> 
#> Note 14 restates fiscal 2024 revenue as 44.9 million dollars.
```

- `both` keeps the two ends and loses the middle. Here the middle held
  the first revenue figure.

``` r

cat(fits$both$pieces[["excerpt"]])
#> Acme Ltd annual report, fiscal 2024.
#> 
#> The board met eleven times during the year and approved a new audit charter.
#> 
#> Staff numbers rose from 410 to 452, mostly in
#> ...[truncated]
#> warehouses, in Leeds and in Rotterdam.
#> 
#> Energy costs fell by 6 percent after a supplier change in March.
#> 
#> Note 14 restates fiscal 2024 revenue as 44.9 million dollars.
```

- `scored` keeps the paragraphs with the highest scores that fit, in
  their original order. The two revenue paragraphs score 1 and the rest
  0; tied paragraphs fill the room left, earliest first. The cut is only
  as good as the scores.

``` r

cat(fits$scored$pieces[["excerpt"]])
#> Acme Ltd annual report, fiscal 2024.
#> 
#> The board met eleven times during the year and approved a new audit charter.
#> 
#> Staff numbers rose from 410 to 452, mostly in the logistics division.
#> 
#> Revenue for fiscal 2024 was 45.2 million dollars, up from 38.1 million.
#> 
#> Note 14 restates fiscal 2024 revenue as 44.9 million dollars.
#> 
#> ...[truncated]
```

No rule is right for every prompt. Keep the head when the start of a
piece matters most (a draft, a document’s opening), the tail when the
latest text matters most (a running log), both ends for a long document
whose summary and conclusion carry the most, and scores when you have a
ranking you trust.

## Cutting one piece

### `hr_truncate()`: keep the part you choose

[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
cuts one string to at most `n` tokens. Six short paragraphs:

``` r

txt <- paste("Para", 1:6, "says something about revenue.", collapse = "\n\n")
hr_count_tokens(txt)
#> [1] 55
```

`keep = "head"`, the default, keeps the start and puts the marker at the
end. It is
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
itself:

``` r

hr_truncate(txt, 20)
#> [1] "Para 1 says something about revenue. ...[truncated]"
identical(hr_truncate(txt, 20), hr_truncate_tokens(txt, 20))
#> [1] TRUE
```

`keep = "tail"` keeps the end and puts the marker at the front:

``` r

hr_truncate(txt, 20, keep = "tail")
#> [1] "...[truncated] Para 6 says something about revenue."
```

`keep = "both"` gives the start and the end about half the budget each,
with the marker on a line of its own between them:

``` r

cat(hr_truncate(txt, 30, keep = "both"))
#> Para 1 says something about
#> ...[truncated]
#> Para 6 says something about revenue.
```

`keep = "scored"` splits the text into units at blank lines, keeps the
units with the highest `scores` that fit, joins them with a blank line
in their original order, and adds the marker after a blank line when any
unit was dropped. Ties keep the earlier unit:

``` r

cat(hr_truncate(txt, 30, keep = "scored", scores = c(1, 9, 2, 8, 3, 4)))
#> Para 2 says something about revenue.
#> 
#> Para 4 says something about revenue.
#> 
#> ...[truncated]
```

A character vector of more than one element is taken as the units, with
no splitting:

``` r

hr_truncate(c("first unit here", "second unit here", "third unit here"), 12,
            keep = "scored", scores = c(3, 1, 2))
#> [1] "first unit here\n\nthird unit here"
```

`"scored"` without one score per unit is an error, and so is a `keep`
that is not one of the four:

``` r

tryCatch(hr_truncate(txt, 20, keep = "scored"), error = conditionMessage)
#> [1] "`keep = \"scored\"` needs `scores`, one number per unit: the text has 6 unit(s) (its elements, or its paragraphs split at blank lines)."
```

### The marker rules

The marker, `" ...[truncated]"` by default, tells the model that text is
missing. The rules:

- The marker appears only when something was cut. Text that fits comes
  back unchanged.
- `"head"` appends the marker as given. `"tail"`, `"both"` and
  `"scored"` trim its spaces and place it at the front, between the
  ends, or after the last unit.
- The marker counts against `n`. When it would cost half the budget or
  more, it is dropped and the whole budget goes to text.
- `marker = ""` turns it off, and the whole budget goes to text.
- With `"both"`, when the end has no room the start alone is kept, as
  `"head"` keeps it; when no word of the start fits, the end alone is
  kept.
- With `"scored"`, when no unit fits beside the marker, the units that
  fit without it are kept, with no marker.

The result is never longer than `n` tokens. A long marker on a small
budget is dropped:

``` r

hr_truncate(txt, 8, marker = " ...[cut here: see the full report]")
#> [1] "Para 1 says"
hr_truncate(txt, 20, keep = "tail", marker = "")
#> [1] "5 says something about revenue.\n\nPara 6 says something about revenue."
```

### `hr_truncate_tokens()`: the start, cut at a word

[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
keeps the start of a string, as written, and adds the marker. Line
breaks and indentation stay, so a table keeps its rows:

``` r

cat(hr_truncate_tokens("Arm | N | Events\nA | 482 | 31\nB | 479 | 44\nC | 470 | 50", 24))
#> Arm | N | Events
#> A | 482 | ...[truncated]
```

The cut falls at the end of a word. A unit too long to be a word (a run
of CJK text, base64, a long URL: anything over 16 tokens alone) is cut
inside, at a character, so a long unbroken run still fills the budget:

``` r

hr_truncate_tokens(paste("Key:", strrep("Q", 300)), 30)
#> [1] "Key: QQQQQQQQQQQQQQQQQQQQQQQ ...[truncated]"
```

`n` of 0 or less, or blank text, returns `""`; `n = Inf` returns the
text unchanged. It never returns `NA`:

``` r

c(hr_truncate_tokens(txt, 0), hr_truncate_tokens("", 10),
  hr_truncate_tokens("short enough already", Inf))
#> [1] ""                     ""                     "short enough already"
```

Neither function writes anything by itself.
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
writes to a trace when you give it one;
[`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
takes no trace.

## Cuts in the trace

Give
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
or
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
a trace, and each cut becomes a step labelled `"truncate"`.
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
names each step’s `where` as `"<where>.<piece>"`:

``` r

tr <- hr_trace()
fit <- hr_context_fit(pieces, bud$input, hr_context_policy(cut_order = "notes"),
                      trace = tr, where = "answer")
cuts <- Filter(function(s) identical(s$label, "truncate"), tr$steps)
do.call(rbind, lapply(cuts, function(s) as.data.frame(s$detail)))
#>          where limit tokens_before tokens_kept tokens_dropped piece keep
#> 1 answer.notes    19            40          11             29 notes head
#>   dropped_part
#> 1          end
```

Each step’s `detail` holds:

| Field | What it holds |
|----|----|
| `where` | The cut site, in the dotted style of call labels. |
| `limit` | The token count the piece was cut to; 0 for a piece cut away. |
| `tokens_before`, `tokens_kept`, `tokens_dropped` | The piece’s tokens before the cut, after it (the marker left out) and the difference. |
| `piece` | The piece’s name, or `NA`. |
| `keep` | The rule the cut used. |
| `dropped_part` | `"end"`, `"start"`, `"middle"`, `"all"`, or for `"scored"` the units dropped, as `"units 2, 5"`. |

The two counts of one cut differ. The step above says the notes lost 29
tokens of source text, while `fit$tokens_dropped` is 26: the fit counts
the marker as kept text, so it gives the tokens the cut saved, and the
trace gives the source text lost.

A text that fits writes nothing, so a trace with no `"truncate"` steps
had no cuts. The printed trace counts them among its steps, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) of a
trace leaves them out, since it lists requests only:

``` r

tr
#> <gr_trace run_20261126222126.804_f19093>  1 steps, 0 model calls, 0 in / 0 out tokens, 0 error(s)
#>   steps: truncate x1 
#>   cost: no cost recorded
#>   started: 2026-11-26T22:21:26.804Z
```

Two other parts of the core read or write these steps.
[`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
cuts a text longer than the embedding model’s window and writes the cut
as a `"truncate"` step whose `where` is `"embed.input"`. And under
[`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md),
a `"truncate"` step in a stage is the `"truncated"` trigger that raises
the next stage’s effort;
[`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md)
covers it.

## Summarising is a step you build

The core does not ask a model to shorten a prompt for you. Each call is
one request, and the only way the core makes text shorter is a cut you
can see in the trace. (The `hierarchical` reader of the document layer
summarises chunks as its way of reading; each summary is a request of
its own in the trace.) When you want a summary in place of a cut, such
as a long set of notes condensed before the next request, make it a step
of its own: a call whose reply becomes a piece of the next prompt.

``` r

condense <- hr_step("condense", function(notes, ctx) {
  if (hr_count_tokens(notes) <= 30) return(notes)
  ctx$call(paste("Condense these notes, keeping every figure:\n\n", notes))$text
}, input = "state", output = "state")
```

Inside a chain, `ctx$call()` sends the request through the arm’s client
and trace, so the summary is a request in the trace like any other, with
its own cost. Called here with a stand-in context:

``` r

summariser <- hr_mock_client(function(messages, params) {
  "Revenue may be restated in the notes; 2023 was 38.1 million."
})
stand_in <- list(call = function(m, ...) hr_call(summariser, m, model = "small-reader"))
condense(pieces[["notes"]], stand_in)
#> [1] "Revenue may be restated in the notes; 2023 was 38.1 million."
```

A summary can drop a figure a cut would have kept, so measure it:
compare answers with and without the step, as
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md)
shows for chains of steps.

## Choosing the settings

Three options decide how much room
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
leaves for a prompt. Each walkthrough says what the option controls, the
signs that point to changing it, where its default came from, and how to
test a change.

### The margin: `safety_margin`

**What it controls.** The share of the context window
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
leaves unused, 0.10 by default, held to 0 to 0.5. It absorbs the
difference between the local token count and the provider’s. The
spending limits use it too: before a request goes out, its prompt count
is raised by the margin when the governor checks it against
`max_cost_usd` (see
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md)).

**Signs it needs changing.** A provider error that a prompt was over the
window means the local count came in under the provider’s by more than
the margin: raise it, or plug in a tokenizer that matches the model (see
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md)).
With an exact tokenizer, a smaller margin gives more of the window to
text.

**Where the default came from.** A tenth of the window was set to absorb
the error of counting tokens locally, and was not measured against it.
`gr_settings_table("options")` lists it as untested.

**How to test it.** Compare the input room at each margin you consider,
and the local count of your prompts with the prompt tokens your provider
reports:

``` r

vapply(c(0, 0.05, 0.10, 0.20), function(m) hr_budget("gpt-4o", safety_margin = m)$input,
       numeric(1))
#> [1] 111616 105216  98816  86016
```

### The reply’s reserve: `output_reserve_share` and `min_output_tokens`

**What they control.** When a call to
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
gives no `reserve_output`, the reply’s reserve is `output_reserve_share`
(0.25) of the usable window, raised to at least `min_output_tokens`
(256) and held to the model’s output cap. Whatever the reserve takes,
the prompt cannot use. `min_output_tokens` is also the floor the reserve
drops to when the default reserve leaves no input room. An explicit
`reserve_output` is used as given between 1 token and the model’s output
cap, unless it leaves no input room, in which case it drops to the same
floor. The readers of the document layer give an explicit reserve, their
`max_answer_tokens`, so `output_reserve_share` changes only the budgets
you compute without one, while `min_output_tokens` still sets the floor
theirs drops to.

**Signs they need changing.** The reserve is room, not the reply’s cap:
[`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
caps a reply at its own `max_output`. When you send the reserve as that
cap, as the readers do, replies cut off at it (`finish_reason`
`"length"`) point to a larger reserve. A prompt cut while the replies
use a small part of their reserve points to a smaller share, which gives
the prompt the difference.

**Where the defaults came from.** A quarter of the window and a floor of
256 tokens were set as room for a short reply and not measured.
`gr_settings_table("options")` lists both as untested.

**How to test them.** See how the input room moves with the share, on
the model you use:

``` r

prev <- hr_options()[c("output_reserve_share", "min_output_tokens")]
room <- vapply(c(0.10, 0.25, 0.40), function(s) {
  hr_options(output_reserve_share = s)
  unlist(hr_budget("gpt-4")[c("input", "output")])
}, numeric(2))
colnames(room) <- c(0.10, 0.25, 0.40)
room
#>         0.1 0.25  0.4
#> input  6635 5529 4424
#> output  737 1843 2948
hr_options(prev)
```

Then run your prompts at the share you pick and check `finish_reason`
and the reply’s token counts in the trace.

## Where the document layer builds on this

The readers size their prompts with
[`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md).
A read takes a policy as the `context_policy` setting of
[`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md):
`refine` fits its draft and excerpt with
[`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md),
and the merges, `hierarchical` and `preview` cut their pieces with
[`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md).
“What a request keeps” in
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md)
covers the setting.

## Next

- [`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md):
  the calls these prompts go into, and the trace that records them.
- [`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md):
  the context windows and output caps the budget reads, and how tokens
  are counted.
- [`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md):
  the reasoning effort that a cut can raise.
- [`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md):
  steps and chains, where a summary step like the one above runs.
- [`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md):
  the readers that use these functions on a document.
